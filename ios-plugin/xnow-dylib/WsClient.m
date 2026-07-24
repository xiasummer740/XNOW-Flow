// WsClient.m
// XNOW WebSocket 客户端 — 基于 CFStream（绕过 BH TikTok 对 NSURLSession 的 hook）
// 原 NSURLSessionWebSocketTask 版本触发 TikTok 退出检测，改用底层 C 接口

#import "WsClient.h"
#import <CFNetwork/CFNetwork.h>
#import <Security/SecureTransport.h>

@interface WsClient () <NSStreamDelegate>
@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong) NSOutputStream *outputStream;
@property (nonatomic, copy) NSString *serverHost;
@property (nonatomic, assign) int serverPort;
@property (nonatomic, copy) NSString *serverPath;
@property (nonatomic, copy) NSString *deviceId;
@property (nonatomic, assign) BOOL intentionalDisconnect;
@property (nonatomic, strong) dispatch_queue_t socketQueue;
@property (nonatomic, strong) NSMutableData *readBuffer;
// WebSocket 帧解析
@property (nonatomic, assign) BOOL wsUpgraded;
@end

static const int kMaxReconnectAttempts = 20;
static const int kBaseReconnectDelay = 2;

@implementation WsClient

- (instancetype)init {
    self = [super init];
    if (self) {
        _socketQueue = dispatch_queue_create("com.xnow.websocket", DISPATCH_QUEUE_SERIAL);
        _readBuffer = [NSMutableData data];
        _intentionalDisconnect = NO;
        _wsUpgraded = NO;
    }
    return self;
}

#pragma mark - Public

- (void)connectToServer:(NSString *)serverURL deviceId:(NSString *)deviceId {
    self.deviceId = deviceId;
    self.intentionalDisconnect = NO;
    self.wsUpgraded = NO;
    self.serverHost = @"192.129.210.52";
    self.serverPort = 8000;

    // 解析 URL 提取 host/port/path/query
    NSString *base = serverURL;
    NSString *query = @"";
    NSRange qr = [base rangeOfString:@"?"];
    if (qr.location != NSNotFound) {
        query = [base substringFromIndex:qr.location];
        base = [base substringToIndex:qr.location];
    }
    // 去掉 ws:// 前缀
    if ([base hasPrefix:@"ws://"]) base = [base substringFromIndex:5];
    if ([base hasPrefix:@"wss://"]) base = [base substringFromIndex:6];
    // 去掉路径部分
    NSRange sr = [base rangeOfString:@"/"];
    if (sr.location != NSNotFound) {
        self.serverPath = [base substringFromIndex:sr.location];
        base = [base substringToIndex:sr.location];
    } else {
        self.serverPath = @"/";
    }
    // host:port
    NSRange cr = [base rangeOfString:@":"];
    if (cr.location != NSNotFound) {
        self.serverHost = [base substringToIndex:cr.location];
        self.serverPort = [[base substringFromIndex:cr.location + 1] intValue];
    } else {
        self.serverHost = base;
        self.serverPort = 8000;
    }
    // 构建 WS 路径 (含 deviceId 和 query)
    self.serverPath = [NSString stringWithFormat:@"/ws/%@%@", deviceId, query];

    dispatch_async(_socketQueue, ^{
        [self _connectInternal];
    });
}

- (void)disconnect {
    self.intentionalDisconnect = YES;
    dispatch_async(_socketQueue, ^{
        [self _closeStreams];
    });
}

- (void)sendMessage:(NSDictionary *)message {
    if (!_isConnected || !self.wsUpgraded) return;
    NSError *err = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:message options:0 error:&err];
    if (!json) return;
    [self _sendWSFrame:json];
}

- (void)sendString:(NSString *)string {
    if (!_isConnected || !self.wsUpgraded) return;
    [self _sendWSFrame:[string dataUsingEncoding:NSUTF8StringEncoding]];
}

#pragma mark - TCP Connection (CFStream)

- (void)_connectInternal {
    [self _closeStreams];
    self.wsUpgraded = NO;

    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;

    CFStreamCreatePairWithSocketToHost(NULL,
        (__bridge CFStringRef)self.serverHost,
        (UInt32)self.serverPort,
        &readStream, &writeStream);

    if (!readStream || !writeStream) {
        [self _notifyError:@"创建 CFStream 失败"];
        return;
    }

    self.inputStream = (__bridge_transfer NSInputStream *)readStream;
    self.outputStream = (__bridge_transfer NSOutputStream *)writeStream;
    self.inputStream.delegate = self;
    self.outputStream.delegate = self;

    [self.inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.inputStream open];
    [self.outputStream open];

    // 保持 runloop 运行以接收流事件（在 socketQueue 线程上）
    CFRunLoopRun();
}

- (void)_closeStreams {
    self.wsUpgraded = NO;
    _isConnected = NO;
    if (self.inputStream) {
        self.inputStream.delegate = nil;
        [self.inputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [self.inputStream close];
        self.inputStream = nil;
    }
    if (self.outputStream) {
        self.outputStream.delegate = nil;
        [self.outputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [self.outputStream close];
        self.outputStream = nil;
    }
    // 停止 runloop（_connectInternal 中调了 CFRunLoopRun()）
    CFRunLoopStop(CFRunLoopGetCurrent());
}

#pragma mark - WebSocket Upgrade

- (void)_sendUpgradeRequest {
    // 生成 WebSocket key
    NSMutableData *keyData = [NSMutableData dataWithLength:16];
    arc4random_buf((void *)keyData.bytes, 16);
    NSString *wsKey = [keyData base64EncodedStringWithOptions:0];

    NSString *request = [NSString stringWithFormat:
        @"GET %@ HTTP/1.1\r\n"
        @"Host: %@:%d\r\n"
        @"Upgrade: websocket\r\n"
        @"Connection: Upgrade\r\n"
        @"Sec-WebSocket-Key: %@\r\n"
        @"Sec-WebSocket-Version: 13\r\n"
        @"\r\n",
        self.serverPath, self.serverHost, self.serverPort, wsKey];

    NSData *requestData = [request dataUsingEncoding:NSUTF8StringEncoding];
    [self.outputStream write:requestData.bytes maxLength:requestData.length];
    NSLog(@"[WsClient] WS upgrade request sent");
}

- (void)_handleUpgradeResponse:(NSData *)data {
    NSString *response = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if ([response containsString:@" 101 "]) {
        self.wsUpgraded = YES;
        _isConnected = YES;
        NSLog(@"[WsClient] WS upgrade successful");
        [self.readBuffer setLength:0];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate wsClientDidConnect:self];
        });
    } else {
        NSLog(@"[WsClient] WS upgrade failed: %@", [response substringToIndex:MIN(100, response.length)]);
        [self _notifyError:@"WS upgrade 失败"];
    }
}

#pragma mark - WebSocket Frames

- (void)_sendWSFrame:(NSData *)payload {
    // 构造 WebSocket 数据帧 (opcode=0x2 = binary, MASK=1)
    NSMutableData *frame = [NSMutableData data];
    uint8_t header = 0x82; // FIN + opcode binary
    [frame appendBytes:&header length:1];

    NSUInteger len = payload.length;
    uint8_t maskKey[4];
    arc4random_buf(maskKey, 4);

    if (len < 126) {
        uint8_t b = 0x80 | (uint8_t)len; // MASK + len
        [frame appendBytes:&b length:1];
    } else if (len < 65536) {
        uint8_t b = 0x80 | 126;
        [frame appendBytes:&b length:1];
        uint16_t n = CFSwapInt16HostToBig((uint16_t)len);
        [frame appendBytes:&n length:2];
    } else {
        uint8_t b = 0x80 | 127;
        [frame appendBytes:&b length:1];
        uint64_t n = CFSwapInt64HostToBig(len);
        [frame appendBytes:&n length:8];
    }

    [frame appendBytes:maskKey length:4];
    // Mask payload
    uint8_t *payloadBytes = (uint8_t *)payload.bytes;
    for (NSUInteger i = 0; i < len; i++) {
        uint8_t masked = payloadBytes[i] ^ maskKey[i % 4];
        [frame appendBytes:&masked length:1];
    }

    [self.outputStream write:frame.bytes maxLength:frame.length];
}

- (void)_handleWSFrame:(NSData *)data {
    // 简化解析：只处理文本帧 (opcode=1, FIN=1, unmasked)
    // 完整 WS 解析器需处理分片、ping/pong 等
    if (data.length < 2) return;
    const uint8_t *bytes = data.bytes;
    uint8_t opcode = bytes[0] & 0x0F;
    BOOL fin = (bytes[0] & 0x80) != 0;
    BOOL masked = (bytes[1] & 0x80) != 0;

    if (opcode == 0x8) {
        // Close frame
        [self _notifyError:@"WS关闭帧"];
        return;
    }
    if (opcode == 0x9) {
        // Ping → send pong
        [self _sendPong];
        return;
    }
    if (opcode == 0xA) {
        // Pong — ignore
        return;
    }
    if (opcode != 0x1) {
        // 不处理二进制帧等其他类型
        return;
    }

    NSUInteger offset = 2;
    uint64_t payloadLen = bytes[1] & 0x7F;
    if (payloadLen == 126) {
        if (data.length < 4) return;
        payloadLen = CFSwapInt16BigToHost(*(uint16_t *)(bytes + 2));
        offset = 4;
    } else if (payloadLen == 127) {
        if (data.length < 10) return;
        payloadLen = CFSwapInt64BigToHost(*(uint64_t *)(bytes + 2));
        offset = 10;
    }

    if (masked) offset += 4;
    if (offset + payloadLen > data.length) return;

    NSData *payload = [data subdataWithRange:NSMakeRange(offset, (NSUInteger)payloadLen)];
    // 如果 masked，需要 unmask
    if (masked) {
        const uint8_t *maskKey = bytes + offset - 4;
        uint8_t *unmasked = malloc(payloadLen);
        for (NSUInteger i = 0; i < payloadLen; i++) {
            unmasked[i] = ((const uint8_t *)payload.bytes)[i] ^ maskKey[i % 4];
        }
        payload = [NSData dataWithBytesNoCopy:unmasked length:(NSUInteger)payloadLen freeWhenDone:YES];
    }

    // 解析 JSON
    NSError *jsonErr = nil;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:payload options:0 error:&jsonErr];
    if (dict && !jsonErr) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate wsClient:self didReceiveMessage:dict];
        });
    }
}

- (void)_sendPong {
    uint8_t pong[2] = {0x8A, 0x00}; // FIN + opcode=0xA (pong)
    [self.outputStream write:pong maxLength:2];
}

#pragma mark - NSStreamDelegate

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)event {
    switch (event) {
        case NSStreamEventOpenCompleted:
            break;

        case NSStreamEventHasSpaceAvailable:
            if (aStream == self.outputStream && !self.wsUpgraded) {
                NSLog(@"[WsClient] TCP connected, sending WS upgrade...");
                [self _sendUpgradeRequest];
            }
            break;

        case NSStreamEventHasBytesAvailable:
            if (aStream == self.inputStream) {
                [self _readFromStream];
            }
            break;

        case NSStreamEventErrorOccurred: {
            NSError *err = [aStream streamError];
            NSLog(@"[WsClient] Stream error: %@", err.localizedDescription);
            [self _notifyError:err.localizedDescription ?: @"流错误"];
            break;
        }

        case NSStreamEventEndEncountered:
            NSLog(@"[WsClient] Stream ended");
            if (!self.intentionalDisconnect) {
                [self _notifyError:@"连接断开"];
            }
            break;

        default:
            break;
    }
}

- (void)_readFromStream {
    uint8_t buffer[4096];
    NSInteger len = [self.inputStream read:buffer maxLength:sizeof(buffer)];
    if (len <= 0) return;

    [self.readBuffer appendBytes:buffer length:(NSUInteger)len];

    if (!self.wsUpgraded) {
        // 检查是否收到完整的 HTTP 响应头
        NSString *resp = [[NSString alloc] initWithData:self.readBuffer encoding:NSUTF8StringEncoding];
        if ([resp containsString:@"\r\n\r\n"]) {
            [self _handleUpgradeResponse:self.readBuffer];
        }
        return;
    }

    // WebSocket 帧数据
    [self _handleWSFrame:self.readBuffer];
    [self.readBuffer setLength:0];
}

#pragma mark - Error & Reconnect

- (void)_notifyError:(NSString *)desc {
    _isConnected = NO;
    self.wsUpgraded = NO;

    NSError *error = [NSError errorWithDomain:@"XNOWER" code:-1
        userInfo:@{NSLocalizedDescriptionKey: desc ?: @"未知错误"}];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate wsClientDidDisconnect:self error:error];
    });

    if (!self.intentionalDisconnect) {
        [self _scheduleReconnect];
    }
}

- (void)_scheduleReconnect {
    // 指数退避
    static int retryCount = 0;
    retryCount++;
    if (retryCount > kMaxReconnectAttempts) return;

    int delay = MIN(kBaseReconnectDelay * (1 << (retryCount - 1)), 60);
    int jitter = arc4random_uniform(5);
    delay += jitter;

    NSLog(@"[WsClient] Reconnect in %ds (attempt %d)", delay, retryCount);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (!self.intentionalDisconnect) {
            retryCount = 0;
            [self _connectInternal];
        }
    });
}

@end

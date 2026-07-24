// WsClient.m
// XNOW WebSocket 客户端 — 基于 CFSocketConnectToAddress（纯 C 接口，最底层）
// 完全不碰 NSURLSession 或 CFStream，避免 BH TikTok hook

#import "WsClient.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <CFNetwork/CFSocket.h>

@interface WsClient ()
@property (nonatomic, copy) NSString *deviceId;
@property (nonatomic, assign) BOOL intentionalDisconnect;
@property (nonatomic, strong) dispatch_queue_t socketQueue;
@property (nonatomic, assign) CFSocketRef socketRef;
@property (nonatomic, strong) NSMutableData *readBuffer;
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
        _socketRef = NULL;
    }
    return self;
}

- (void)dealloc {
    [self _closeSocket];
}

#pragma mark - Public

- (void)connectToServer:(NSString *)serverURL deviceId:(NSString *)deviceId {
    self.deviceId = deviceId;
    self.intentionalDisconnect = NO;
    self.wsUpgraded = NO;

    // 构建 WebSocket 请求路径
    NSString *query = @"";
    NSString *base = serverURL;
    NSRange qr = [base rangeOfString:@"?"];
    if (qr.location != NSNotFound) {
        query = [base substringFromIndex:qr.location];
        base = [base substringToIndex:qr.location];
    }
    if ([base hasPrefix:@"ws://"]) base = [base substringFromIndex:5];
    NSRange sr = [base rangeOfString:@"/"];
    if (sr.location != NSNotFound) base = [base substringToIndex:sr.location];

    NSString *host = base;
    int port = 8000;
    NSRange cr = [base rangeOfString:@":"];
    if (cr.location != NSNotFound) {
        host = [base substringToIndex:cr.location];
        port = [[base substringFromIndex:cr.location + 1] intValue];
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(_socketQueue, ^{
        // POSIX socket connection
        int sock = socket(AF_INET, SOCK_STREAM, 0);
        if (sock < 0) { [weakSelf _notifyError:@"socket创建失败"]; return; }

        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_len = sizeof(addr);
        addr.sin_family = AF_INET;
        addr.sin_port = htons(port);

        if (inet_pton(AF_INET, [host UTF8String], &addr.sin_addr) != 1) {
            // DNS解析
            struct hostent *he = gethostbyname([host UTF8String]);
            if (!he) { close(sock); [weakSelf _notifyError:@"DNS解析失败"]; return; }
            memcpy(&addr.sin_addr, he->h_addr_list[0], he->h_length);
        }

        // 设置超时
        struct timeval tv = {10, 0};
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

        if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
            close(sock);
            [weakSelf _notifyError:@"连接失败"];
            return;
        }

        NSLog(@"[WsClient] TCP connected to %s:%d", [host UTF8String], port);

        // 发送 WebSocket 升级请求
        NSMutableData *keyData = [NSMutableData dataWithLength:16];
        arc4random_buf((void *)keyData.bytes, 16);
        NSString *wsKey = [keyData base64EncodedStringWithOptions:0];
        NSString *path = [NSString stringWithFormat:@"/ws/%@%@", deviceId, query];

        NSString *request = [NSString stringWithFormat:
            @"GET %@ HTTP/1.1\r\n"
            @"Host: %@:%d\r\n"
            @"Upgrade: websocket\r\n"
            @"Connection: Upgrade\r\n"
            @"Sec-WebSocket-Key: %@\r\n"
            @"Sec-WebSocket-Version: 13\r\n"
            @"\r\n",
            path, host, port, wsKey];

        const char *reqC = [request UTF8String];
        size_t toSend = strlen(reqC);
        size_t sent = 0;
        while (sent < toSend) {
            ssize_t n = write(sock, reqC + sent, toSend - sent);
            if (n <= 0) { close(sock); [weakSelf _notifyError:@"发送失败"]; return; }
            sent += n;
        }
        NSLog(@"[WsClient] WS upgrade request sent");

        // 读取 HTTP 响应
        NSMutableData *respData = [NSMutableData data];
        char buf[4096];
        BOOL headerComplete = NO;
        while (!headerComplete) {
            ssize_t n = read(sock, buf, sizeof(buf));
            if (n <= 0) { close(sock); [weakSelf _notifyError:@"读取响应失败"]; return; }
            [respData appendBytes:buf length:n];
            NSString *resp = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];
            if ([resp containsString:@"\r\n\r\n"]) {
                headerComplete = YES;
            }
        }

        // 检查升级结果
        NSString *response = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];
        if (![response containsString:@" 101 "]) {
            close(sock);
            [weakSelf _notifyError:@"WS升级失败"];
            return;
        }
        NSLog(@"[WsClient] WS upgrade successful!");

        // 升级成功！进入 WebSocket 帧循环
        weakSelf.wsUpgraded = YES;
        _isConnected = YES;

        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.delegate wsClientDidConnect:weakSelf];
        });

        // 创建 CFSocket 监视读取
        CFSocketContext ctx = {0, (__bridge void *)weakSelf, NULL, NULL, NULL};
        CFSocketRef cfSock = CFSocketCreateWithNative(NULL, sock, kCFSocketReadCallBack, _socketCallback, &ctx);
        if (cfSock) {
            [weakSelf _closeSocket];
            weakSelf.socketRef = cfSock;
            CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(NULL, cfSock, 0);
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
            CFRelease(source);
            CFRunLoopRun(); // 运行 runloop 接收数据
        }

        // Runloop 结束（disconnect或socket关闭）
        close(sock);
        weakSelf.socketRef = NULL;
        weakSelf.wsUpgraded = NO;
        _isConnected = NO;
    });
}

/// CFSocket 回调 — 收到数据
static void _socketCallback(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
    WsClient *self = (__bridge WsClient *)info;
    if (!self || type != kCFSocketReadCallBack) return;

    CFSocketNativeHandle sock = CFSocketGetNative(s);
    char buf[8192];
    ssize_t n = read(sock, buf, sizeof(buf));

    if (n <= 0) {
        // 连接关闭或错误
        [self _notifyError:@"连接断开"];
        CFSocketInvalidate(s);
        CFRunLoopStop(CFRunLoopGetCurrent());
        return;
    }

    // 解析 WebSocket 帧
    if (n < 2) return;
    const uint8_t *b = (const uint8_t *)buf;
    uint8_t opcode = b[0] & 0x0F;

    if (opcode == 0x8) { // Close
        [self _notifyError:@"WS关闭"];
        CFSocketInvalidate(s);
        CFRunLoopStop(CFRunLoopGetCurrent());
        return;
    }
    if (opcode == 0x9) { // Ping → Pong
        uint8_t pong[2] = {0x8A, 0x00};
        write(sock, pong, 2);
        return;
    }
    if (opcode == 0xA) return; // Pong

    if (opcode != 0x1) return; // 只处理文本帧

    // 解析 payload 长度
    NSUInteger offset = 2;
    uint64_t payloadLen = b[1] & 0x7F;
    BOOL masked = (b[1] & 0x80) != 0;
    if (payloadLen == 126) {
        if (n < 4) return;
        payloadLen = CFSwapInt16BigToHost(*(uint16_t *)(b + 2));
        offset = 4;
    } else if (payloadLen == 127) {
        if (n < 10) return;
        payloadLen = CFSwapInt64BigToHost(*(uint64_t *)(b + 2));
        offset = 10;
    }
    if (masked) offset += 4;
    if (offset + payloadLen > (NSUInteger)n) return;

    NSData *payload = [NSData dataWithBytes:b + offset length:(NSUInteger)payloadLen];

    // 解析 JSON
    NSError *jsonErr = nil;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:payload options:0 error:&jsonErr];
    if (dict) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate wsClient:self didReceiveMessage:dict];
        });
    }
}

- (void)disconnect {
    self.intentionalDisconnect = YES;
    dispatch_async(_socketQueue, ^{
        [self _closeSocket];
        CFRunLoopStop(CFRunLoopGetCurrent());
    });
}

- (void)_closeSocket {
    if (_socketRef) {
        CFSocketInvalidate(_socketRef);
        CFRelease(_socketRef);
        _socketRef = NULL;
    }
}

/// 发送 WebSocket 文本帧（带 mask）
- (void)sendMessage:(NSDictionary *)message {
    if (!_isConnected || !self.wsUpgraded || !_socketRef) return;
    NSError *err = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:message options:0 error:&err];
    if (!json) return;

    CFSocketNativeHandle sock = CFSocketGetNative(_socketRef);
    NSMutableData *frame = [NSMutableData data];

    // FIN + opcode text
    uint8_t header = 0x81;
    [frame appendBytes:&header length:1];

    NSUInteger len = json.length;
    uint8_t maskKey[4];
    arc4random_buf(maskKey, 4);

    if (len < 126) {
        uint8_t b = 0x80 | (uint8_t)len;
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

    const uint8_t *payload = json.bytes;
    for (NSUInteger i = 0; i < len; i++) {
        uint8_t masked = payload[i] ^ maskKey[i % 4];
        [frame appendBytes:&masked length:1];
    }

    write(sock, frame.bytes, frame.length);
}

- (void)sendString:(NSString *)string {
    [self sendMessage:@{@"text": string}];
}

#pragma mark - Error & Reconnect

- (void)_notifyError:(NSString *)desc {
    _isConnected = NO;
    self.wsUpgraded = NO;
    [self _closeSocket];

    NSError *error = [NSError errorWithDomain:@"XNOWER" code:-1
        userInfo:@{NSLocalizedDescriptionKey: desc ?: @"未知错误"}];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate wsClientDidDisconnect:self error:error];
    });

    if (!self.intentionalDisconnect) {
        static int retryCount = 0;
        retryCount++;
        if (retryCount > kMaxReconnectAttempts) return;
        int delay = MIN(kBaseReconnectDelay * (1 << (retryCount - 1)), 60);
        delay += arc4random_uniform(5);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            if (!self.intentionalDisconnect) {
                retryCount = 0;
                [self connectToServer:[NSString stringWithFormat:@"ws://%@:%d", self->_serverHost ?: @"192.129.210.52", 8000] deviceId:self.deviceId ?: @""];
            }
        });
    }
}

@end

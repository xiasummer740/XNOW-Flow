// WsClient.m
// XNOW 原始 TCP + TLS 客户端
// 使用 dlsym 加载原始 connect() 绕过 BH fishhook，然后 CFStream 做 TLS
// 通信方式：HTTP 短连接轮询（每次请求新建 TCP 连接，POST/GET 后关闭）
// 连接目标：wss://yunkong.taikon.top（Cloudflare Tunnel，绕过 BH IP 检测）

#import "WsClient.h"
#import <dlfcn.h>
#import <sys/socket.h>
#import <netdb.h>
#import <arpa/inet.h>
#import <CFNetwork/CFHTTPMessage.h>

// ====== 绕过 fishhook 的原始系统函数 ======
typedef int (*sys_socket_t)(int, int, int);
typedef int (*sys_connect_t)(int, const struct sockaddr *, socklen_t);
typedef int (*sys_close_t)(int);

static sys_socket_t real_socket = NULL;
static sys_connect_t real_connect = NULL;
static sys_close_t  real_close  = NULL;

static void ensure_raw_funcs(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *lib = dlopen("/usr/lib/system/libsystem_kernel.dylib", RTLD_LAZY | RTLD_NOLOAD);
        if (lib) {
            real_socket = (sys_socket_t)dlsym(lib, "socket");
            real_connect = (sys_connect_t)dlsym(lib, "connect");
            real_close  = (sys_close_t)dlsym(lib, "close");
        }
        // 安全 fallback（如果 dlsym 返回相同的已 hook 地址，那也是 try 了）
        if (!real_socket) real_socket = socket;
        if (!real_connect) real_connect = connect;
        if (!real_close)  real_close  = close;
    });
}

// ====== 接口定义 ======
@interface WsClient ()
@property (nonatomic, copy)   NSString *deviceId;
@property (nonatomic, copy)   NSString *host;
@property (nonatomic, assign) int       port;
@property (nonatomic, assign) BOOL      intentionalDisconnect;
@property (nonatomic, strong) dispatch_source_t pollTimer;
@property (nonatomic, assign) int       sockFd;     // 当前 raw socket fd
@property (nonatomic, assign) CFReadStreamRef  readStream;
@property (nonatomic, assign) CFWriteStreamRef writeStream;
@end

@implementation WsClient

- (instancetype)init {
    self = [super init];
    if (self) {
        _intentionalDisconnect = NO;
        _sockFd = -1;
        _readStream = NULL;
        _writeStream = NULL;
        _port = 443;
    }
    return self;
}

#pragma mark - 原始 TCP + TLS 连接

// 建立原始 TCP 连接（绕过 fishhook）→ CFStream + TLS
- (BOOL)_rawConnect:(NSString *)host port:(int)port timeout:(NSTimeInterval)timeout {
    ensure_raw_funcs();
    [self _cleanupStreams];

    // DNS 解析
    struct hostent *he = gethostbyname([host UTF8String]);
    if (!he || !he->h_addr_list[0]) {
        NSLog(@"[WsClient] ❌ DNS 解析失败: %@", host);
        return NO;
    }

    // 原始 socket（不被 BH fishhook 拦截）
    int fd = real_socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        NSLog(@"[WsClient] ❌ socket() 失败: %s", strerror(errno));
        return NO;
    }

    // 设置 socket 超时（connect 默认可能卡 2 分钟）
    struct timeval tv;
    tv.tv_sec = (int)timeout;
    tv.tv_usec = (timeout - (int)timeout) * 1000000;
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    // 原始 connect（绕过 BH 的 connect hook）
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port   = htons(port);
    memcpy(&addr.sin_addr, he->h_addr_list[0], he->h_length);

    if (real_connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        NSLog(@"[WsClient] ❌ connect() 失败: %s (目标 %s:%d)", strerror(errno), [host UTF8String], port);
        real_close(fd);
        return NO;
    }

    NSLog(@"[WsClient] ✅ 原始 connect() 成功 (fd=%d, %s:%d)", fd, inet_ntoa(addr.sin_addr), port);

    // 用 CFStream 包装已连接的 socket + 添加 TLS
    CFStreamCreatePairWithSocket(kCFAllocatorDefault, fd, &_readStream, &_writeStream);
    if (!_readStream || !_writeStream) {
        NSLog(@"[WsClient] ❌ CFStreamCreatePairWithSocket 失败");
        real_close(fd);
        return NO;
    }

    // 配置 TLS（信任自签名和过期证书，兼容各种场景）
    NSDictionary *sslSettings = @{
        (__bridge id)kCFStreamSSLLevel: (__bridge id)kCFStreamSocketSecurityLevelNegotiatedSSL,
        (__bridge id)kCFStreamSSLPeerName: host,
    };
    CFReadStreamSetProperty(_readStream, kCFStreamPropertySSLSettings, (__bridge CFTypeRef)sslSettings);
    CFWriteStreamSetProperty(_writeStream, kCFStreamPropertySSLSettings, (__bridge CFTypeRef)sslSettings);

    // 打开流（触发 TLS 握手）
    Boolean rOk = CFReadStreamOpen(_readStream);
    Boolean wOk = CFWriteStreamOpen(_writeStream);
    if (!rOk || !wOk) {
        NSLog(@"[WsClient] ❌ CFStreamOpen 失败 (r=%d w=%d)", rOk, wOk);
        [self _cleanupStreams];
        return NO;
    }

    // 等待 TLS 握手完成（最多 10 秒）
    for (int i = 0; i < 100; i++) {
        CFStreamStatus rStatus = CFReadStreamGetStatus(_readStream);
        CFStreamStatus wStatus = CFWriteStreamGetStatus(_writeStream);
        if (rStatus == kCFStreamStatusOpen || rStatus == kCFStreamStatusReading ||
            wStatus == kCFStreamStatusOpen || wStatus == kCFStreamStatusWriting) {
            break;
        }
        if (rStatus == kCFStreamStatusError || wStatus == kCFStreamStatusError) {
            CFErrorRef error = CFReadStreamCopyError(_readStream);
            if (error) {
                NSLog(@"[WsClient] ❌ TLS 握手失败: %@", error);
                CFRelease(error);
            }
            [self _cleanupStreams];
            return NO;
        }
        usleep(100000); // 100ms
    }

    _sockFd = fd;
    NSLog(@"[WsClient] 🔒 TLS 握手成功 (%@:%d)", host, port);
    return YES;
}

- (void)_cleanupStreams {
    if (_readStream) {
        CFReadStreamClose(_readStream);
        CFRelease(_readStream);
        _readStream = NULL;
    }
    if (_writeStream) {
        CFWriteStreamClose(_writeStream);
        CFRelease(_writeStream);
        _writeStream = NULL;
    }
    if (_sockFd >= 0) {
        real_close(_sockFd);
        _sockFd = -1;
    }
}

#pragma mark - HTTP 请求（通过 TLS 流）

// 发送 HTTP 请求，返回响应体（NSData）
- (NSData *)_httpRequest:(NSString *)method path:(NSString *)path body:(NSData *)body {
    if (!_readStream || !_writeStream) {
        NSLog(@"[WsClient] ⚠️ 流未就绪，尝试重连...");
        if (![self _rawConnect:self.host port:self.port timeout:10]) {
            return nil;
        }
    }

    // 构建 URL
    NSString *urlStr = [NSString stringWithFormat:@"https://%@%@", self.host, path];
    CFURLRef url = CFURLCreateWithString(kCFAllocatorDefault, (__bridge CFStringRef)urlStr, NULL);
    if (!url) { NSLog(@"[WsClient] ❌ URL 创建失败: %@", urlStr); return nil; }

    // 创建 CFHTTP 请求
    CFHTTPMessageRef request = CFHTTPMessageCreateRequest(kCFAllocatorDefault,
        (__bridge CFStringRef)method, url, kCFHTTPVersion1_1);
    CFRelease(url);

    CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Host"), (__bridge CFStringRef)self.host);
    CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Connection"), CFSTR("close"));
    CFHTTPMessageSetHeaderFieldValue(request, CFSTR("User-Agent"), CFSTR("XNOW/1.3.2"));

    if (body) {
        CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Content-Type"), CFSTR("application/json"));
        NSString *lenStr = [NSString stringWithFormat:@"%lu", (unsigned long)[body length]];
        CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Content-Length"), (__bridge CFStringRef)lenStr);
        CFHTTPMessageSetBody(request, (__bridge CFDataRef)body);
    }

    // 序列化为原始 HTTP 字节
    CFDataRef requestData = CFHTTPMessageCopySerializedMessage(request);
    CFRelease(request);

    if (!requestData) { NSLog(@"[WsClient] ❌ 序列化 HTTP 失败"); return nil; }

    // 发送
    const UInt8 *ptr = CFDataGetBytePtr(requestData);
    CFIndex len = CFDataGetLength(requestData);
    CFIndex totalSent = 0;
    while (totalSent < len) {
        CFIndex sent = CFWriteStreamWrite(_writeStream, ptr + totalSent, len - totalSent);
        if (sent <= 0) {
            NSLog(@"[WsClient] ❌ 写入流失败 (sent=%ld)", (long)sent);
            CFRelease(requestData);
            return nil;
        }
        totalSent += sent;
    }
    CFRelease(requestData);

    // 读取响应
    NSMutableData *responseData = [NSMutableData data];
    uint8_t buf[16384];
    while (1) {
        CFIndex n = CFReadStreamRead(_readStream, buf, sizeof(buf));
        if (n == 0) break; // EOF (Connection: close)
        if (n < 0) {
            CFErrorRef err = CFReadStreamCopyError(_readStream);
            if (err) {
                NSLog(@"[WsClient] ⚠️ 读流错误: %@", err);
                CFRelease(err);
            }
            break;
        }
        [responseData appendBytes:buf length:n];
    }

    // 清理连接（短连接，用完即关）
    [self _cleanupStreams];

    return [self _httpResponseBody:responseData];
}

// 从 HTTP 响应 data 中提取 body（跳过 headers）
- (NSData *)_httpResponseBody:(NSData *)responseData {
    if (!responseData || responseData.length < 4) return nil;
    const uint8_t *bytes = [responseData bytes];
    NSUInteger len = [responseData length];
    for (NSUInteger i = 0; i < len - 3; i++) {
        if (bytes[i] == '\r' && bytes[i+1] == '\n' && bytes[i+2] == '\r' && bytes[i+3] == '\n') {
            NSUInteger bodyLen = len - i - 4;
            if (bodyLen == 0) return nil;
            return [responseData subdataWithRange:NSMakeRange(i+4, bodyLen)];
        }
    }
    return nil;
}

// HTTP 状态码
- (NSInteger)_httpStatus:(NSData *)responseData {
    if (!responseData || responseData.length < 4) return 0;
    NSString *str = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
    NSArray *lines = [str componentsSeparatedByString:@"\r\n"];
    if (lines.count > 0) {
        NSArray *parts = [lines[0] componentsSeparatedByString:@" "];
        if (parts.count >= 2) return [parts[1] integerValue];
    }
    return 0;
}

#pragma mark - 外部接口

- (void)connectToServer:(NSString *)serverURL deviceId:(NSString *)deviceId {
    self.deviceId = deviceId;
    self.intentionalDisconnect = NO;

    // 解析 URL
    NSString *url = serverURL;
    // 去掉协议前缀
    if ([url hasPrefix:@"wss://"]) url = [url substringFromIndex:6];
    else if ([url hasPrefix:@"ws://"]) url = [url substringFromIndex:5];
    else if ([url hasPrefix:@"https://"]) url = [url substringFromIndex:8];
    else if ([url hasPrefix:@"http://"]) url = [url substringFromIndex:7];

    // 分离 path/query
    NSRange qRange = [url rangeOfString:@"/"];
    NSString *hostPort;
    if (qRange.location != NSNotFound) {
        hostPort = [url substringToIndex:qRange.location];
    } else {
        hostPort = url;
    }

    // 分离 host 和 port
    NSRange colonRange = [hostPort rangeOfString:@":"];
    if (colonRange.location != NSNotFound) {
        self.host = [hostPort substringToIndex:colonRange.location];
        self.port = [[hostPort substringFromIndex:colonRange.location + 1] intValue];
    } else {
        self.host = hostPort;
        self.port = 443;
    }

    self.intentionalDisconnect = NO;

    NSLog(@"[WsClient] 🚀 目标: %@:%d (设备: %@)", self.host, self.port, deviceId);

    // 尝试初始连接测试
    NSData *resp = [self _httpRequest:@"GET" path:@"/health" body:nil];
    if (resp) {
        NSLog(@"[WsClient] ✅ 初始连接测试成功");
        _isConnected = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate wsClientDidConnect:self];
        });

        // 上报初始状态
        [self sendMessage:@{
            @"type": @"status",
            @"data": @{@"device_id": deviceId ?: @"", @"status": @"online"}
        }];

        // 启动轮询
        [self _startPolling];
    } else {
        NSLog(@"[WsClient] ❌ 初始连接测试失败");
        _isConnected = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSError *err = [NSError errorWithDomain:@"WsClient" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"连接失败"}];
            [self.delegate wsClientDidDisconnect:self error:err];
        });
    }
}

- (void)disconnect {
    self.intentionalDisconnect = YES;
    _isConnected = NO;
    [self _stopPolling];
    [self _cleanupStreams];
}

- (void)sendMessage:(NSDictionary *)message {
    if (!message || self.intentionalDisconnect) return;

    NSError *err = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:message options:0 error:&err];
    if (!jsonData) {
        NSLog(@"[WsClient] ❌ JSON 序列化失败: %@", err);
        return;
    }

    NSString *path = [NSString stringWithFormat:@"/ws/%@", self.deviceId ?: @"unknown"];
    NSData *respData = [self _httpRequest:@"POST" path:path body:jsonData];

    if (!respData) {
        NSLog(@"[WsClient] ⚠️ sendMessage 请求失败");
        // 通知 delegate 断线（可能连接有问题）
        if (_isConnected) {
            _isConnected = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                NSError *e = [NSError errorWithDomain:@"WsClient" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"请求失败"}];
                [self.delegate wsClientDidDisconnect:self error:e];
            });
        }
        return;
    }

    // 解析响应，看是否包含指令
    NSError *jsonErr = nil;
    NSDictionary *respDict = [NSJSONSerialization JSONObjectWithData:respData options:0 error:&jsonErr];
    if (respDict && !jsonErr) {
        // 有 command 字段表示服务器有指令
        if (respDict[@"command"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate wsClient:self didReceiveMessage:respDict[@"command"]];
            });
        } else if (respDict[@"ack"]) {
            // 处理 ack 消息（如 bind_info_ack）
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate wsClient:self didReceiveMessage:respDict[@"ack"]];
            });
        } else if (respDict[@"pong"]) {
            // ping pong — 不需要处理
        }
    }
}

#pragma mark - 轮询

- (void)_startPolling {
    [self _stopPolling];

    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0));
    dispatch_source_set_timer(timer,
        dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
        5 * NSEC_PER_SEC, 1 * NSEC_PER_SEC);

    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(timer, ^{
        [weakSelf _pollTick];
    });

    _pollTimer = timer;
    dispatch_resume(timer);
}

- (void)_stopPolling {
    if (_pollTimer) {
        dispatch_source_cancel(_pollTimer);
        _pollTimer = nil;
    }
}

- (void)_pollTick {
    if (self.intentionalDisconnect || !self.isConnected) return;

    NSString *path = [NSString stringWithFormat:@"/ws/%@/poll", self.deviceId ?: @"unknown"];
    NSData *respData = [self _httpRequest:@"GET" path:path body:nil];

    if (!respData) {
        // 连接失败（静默重试，下次 poll 会自动重连 _httpRequest 中的 _rawConnect）
        return;
    }

    // 解析响应中的指令
    NSError *jsonErr = nil;
    id respObj = [NSJSONSerialization JSONObjectWithData:respData options:0 error:&jsonErr];
    if (!jsonErr && [respObj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *command = (NSDictionary *)respObj;
        // 如果是有效指令（有 action 字段）
        if (command[@"action"] || command[@"type"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate wsClient:self didReceiveMessage:command];
            });
        }
    } else if ([respObj isKindOfClass:[NSArray class]]) {
        // 数组 = 多条指令
        for (NSDictionary *cmd in (NSArray *)respObj) {
            if ([cmd isKindOfClass:[NSDictionary class]] && (cmd[@"action"] || cmd[@"type"])) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate wsClient:self didReceiveMessage:cmd];
                });
            }
        }
    }
    // 204 No Content 或解析失败 = 无指令
}

- (void)sendString:(NSString *)string {
    // 不支持原始字符串发送
}

- (void)dealloc {
    self.intentionalDisconnect = YES;
    [self _stopPolling];
    [self _cleanupStreams];
}

@end

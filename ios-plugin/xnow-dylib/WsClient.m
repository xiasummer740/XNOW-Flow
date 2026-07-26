// WsClient.m
// XNOW 原始 TCP + TLS 客户端
// 使用 dlsym 加载原始 connect/send/recv 绕过 BH fishhook
// TLS: Secure Transport API (SSLCreateContext) — 全同步，无 run loop 依赖
// 通信：HTTP 短连接轮询（Cloudflare Tunnel → wss://yunkong.taikon.top）

#import "WsClient.h"
#import <dlfcn.h>
#import <sys/socket.h>
#import <netdb.h>
#import <arpa/inet.h>
#import <Security/Security.h>

// ====== 绕过 fishhook — 从系统库加载原始函数 ======
typedef int (*sys_socket_t)(int, int, int);
typedef int (*sys_connect_t)(int, const struct sockaddr *, socklen_t);
typedef int (*sys_close_t)(int);
typedef ssize_t (*sys_send_t)(int, const void *, size_t, int);
typedef ssize_t (*sys_recv_t)(int, void *, size_t, int);

static sys_socket_t real_socket = NULL;
static sys_connect_t real_connect = NULL;
static sys_close_t   real_close   = NULL;
static sys_send_t    real_send    = NULL;
static sys_recv_t    real_recv    = NULL;

static void ensure_raw_funcs(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *lib = dlopen("/usr/lib/system/libsystem_kernel.dylib", RTLD_LAZY | RTLD_NOLOAD);
        if (lib) {
            real_socket = (sys_socket_t)dlsym(lib, "socket");
            real_connect = (sys_connect_t)dlsym(lib, "connect");
            real_close   = (sys_close_t)dlsym(lib, "close");
            real_send    = (sys_send_t)dlsym(lib, "send");
            real_recv    = (sys_recv_t)dlsym(lib, "recv");
        }
        if (!real_socket) real_socket = socket;
        if (!real_connect) real_connect = connect;
        if (!real_close)   real_close   = close;
        if (!real_send)    real_send    = (sys_send_t)send;
        if (!real_recv)    real_recv    = (sys_recv_t)recv;
    });
}

// ====== Secure Transport I/O 回调（通过 real_send/real_recv） ======
static OSStatus tls_send(SSLConnectionRef conn, const void *data, size_t *len) {
    int fd = (int)(intptr_t)conn;
    ssize_t n = real_send(fd, data, *len, 0);
    if (n > 0) { *len = n; return errSecSuccess; }
    *len = 0;
    return errSecIO;
}

static OSStatus tls_recv(SSLConnectionRef conn, void *data, size_t *len) {
    int fd = (int)(intptr_t)conn;
    ssize_t n = real_recv(fd, data, *len, 0);
    if (n > 0) { *len = n; return errSecSuccess; }
    if (n == 0) { *len = 0; return errSSLClosed; }
    *len = 0;
    return errSecIO;
}

// ====== 接口定义 ======
@interface WsClient ()
@property (nonatomic, copy)   NSString *deviceId;
@property (nonatomic, copy)   NSString *host;
@property (nonatomic, assign) int       port;
@property (nonatomic, assign) BOOL      intentionalDisconnect;
@property (nonatomic, strong) dispatch_source_t pollTimer;
@property (nonatomic, assign) int       sockFd;     // 当前 socket fd
@property (nonatomic, assign) SSLContextRef sslCtx; // TLS 上下文
@end

@implementation WsClient

- (instancetype)init {
    self = [super init];
    if (self) {
        _intentionalDisconnect = NO;
        _sockFd = -1;
        _sslCtx = NULL;
        _port = 443;
    }
    return self;
}

#pragma mark - 原始 TCP + Secure Transport TLS

- (BOOL)_tlsConnect:(NSString *)host port:(int)port timeout:(NSTimeInterval)timeout {
    ensure_raw_funcs();
    [self _cleanup];

    // 解析 DNS
    struct hostent *he = gethostbyname([host UTF8String]);
    if (!he || !he->h_addr_list[0]) {
        NSLog(@"[WsClient] ❌ DNS: %@", host);
        return NO;
    }

    // 原始 socket（绕过 BH fishhook）
    int fd = real_socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) { NSLog(@"[WsClient] ❌ socket: %s", strerror(errno)); return NO; }

    // 连接超时
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
        NSLog(@"[WsClient] ❌ connect(%s:%d): %s", [host UTF8String], port, strerror(errno));
        real_close(fd);
        return NO;
    }
    NSLog(@"[WsClient] ✅ TCP 连接 (%s:%d)", inet_ntoa(addr.sin_addr), port);
    _sockFd = fd;

    // Secure Transport TLS 握手（全同步，无需 run loop）
    SSLContextRef ctx = SSLCreateContext(kCFAllocatorDefault, kSSLClientSide, kSSLStreamType);
    if (!ctx) { NSLog(@"[WsClient] ❌ SSLCreateContext 失败"); [self _cleanup]; return NO; }

    SSLSetConnection(ctx, (SSLConnectionRef)(intptr_t)fd);
    SSLSetIOFuncs(ctx, tls_recv, tls_send);
    // 设置 SNI（Server Name Indication），Cloudflare 需要
    SSLSetPeerDomainName(ctx, [host UTF8String], (SInt32)[host length]);

    OSStatus status = SSLHandshake(ctx);
    if (status != errSecSuccess) {
        NSLog(@"[WsClient] ❌ TLS 握手失败: %d", (int)status);
        CFRelease(ctx);
        [self _cleanup];
        return NO;
    }

    _sslCtx = ctx;
    NSLog(@"[WsClient] 🔒 TLS 握手成功 (%@:%d)", host, port);
    return YES;
}

- (void)_cleanup {
    if (_sslCtx) {
        SSLClose(_sslCtx);
        CFRelease(_sslCtx);
        _sslCtx = NULL;
    }
    if (_sockFd >= 0) {
        real_close(_sockFd);
        _sockFd = -1;
    }
}

// 通过 TLS 发送数据
- (BOOL)_tlsSend:(const void *)data length:(size_t)len {
    if (!_sslCtx) return NO;
    size_t processed = 0;
    while (processed < len) {
        size_t sent = 0;
        OSStatus s = SSLWrite(_sslCtx, (const uint8_t *)data + processed, len - processed, &sent);
        if (s != errSecSuccess) { return NO; }
        processed += sent;
    }
    return YES;
}

// 通过 TLS 读取数据（返回实际读取的字节数）
- (NSInteger)_tlsRead:(void *)buf maxLen:(size_t)maxLen {
    if (!_sslCtx) return -1;
    size_t got = 0;
    OSStatus s = SSLRead(_sslCtx, buf, maxLen, &got);
    if (s == errSecSuccess || s == errSSLWouldBlock) return (NSInteger)got;
    if (s == errSSLClosedGraceful || got > 0) return (NSInteger)got;
    return -1;
}

#pragma mark - HTTP 请求（通过 TLS）

- (NSData *)_httpRequest:(NSString *)method path:(NSString *)path body:(NSData *)body {
    // 首次或断线时建立连接
    if (!_sslCtx || _sockFd < 0) {
        if (![self _tlsConnect:self.host port:self.port timeout:10]) {
            NSLog(@"[WsClient] ⚠️ 连接失败");
            return nil;
        }
    }

    // 构造 HTTP 请求
    NSMutableString *req = [NSMutableString stringWithFormat:@"%@ %@ HTTP/1.1\r\nHost: %@\r\nConnection: close\r\nUser-Agent: XNOW/1.3.2\r\n", method, path, self.host];
    if (body) {
        [req appendFormat:@"Content-Type: application/json\r\nContent-Length: %lu\r\n", (unsigned long)[body length]];
    }
    [req appendString:@"\r\n"];

    // 发送请求头
    NSData *headerData = [req dataUsingEncoding:NSUTF8StringEncoding];
    if (![self _tlsSend:[headerData bytes] length:[headerData length]]) {
        NSLog(@"[WsClient] ❌ 发送失败");
        [self _cleanup];
        return nil;
    }

    // 发送 body
    if (body) {
        if (![self _tlsSend:[body bytes] length:[body length]]) {
            NSLog(@"[WsClient] ❌ body 发送失败");
            [self _cleanup];
            return nil;
        }
    }

    // 读取响应
    NSMutableData *resp = [NSMutableData data];
    uint8_t buf[4096];
    while (1) {
        NSInteger n = [self _tlsRead:buf maxLen:sizeof(buf)];
        if (n <= 0) break;
        [resp appendBytes:buf length:n];
    }

    [self _cleanup]; // 短连接，用完即关
    return [self _httpBody:resp];
}

// 从 HTTP 响应中提取 body
- (NSData *)_httpBody:(NSData *)data {
    if (!data || data.length < 4) return nil;
    const uint8_t *b = [data bytes];
    NSUInteger len = [data length];
    // 找 \r\n\r\n
    for (NSUInteger i = 0; i < len - 3; i++) {
        if (b[i]=='\r' && b[i+1]=='\n' && b[i+2]=='\r' && b[i+3]=='\n') {
            NSUInteger bodyLen = len - i - 4;
            return bodyLen > 0 ? [data subdataWithRange:NSMakeRange(i+4, bodyLen)] : nil;
        }
    }
    return nil;
}

#pragma mark - 外部接口

- (void)connectToServer:(NSString *)serverURL deviceId:(NSString *)deviceId {
    self.deviceId = deviceId;
    self.intentionalDisconnect = NO;

    // 解析 URL: "wss://yunkong.taikon.top?api_id=xxx&device_code=xxx"
    NSString *url = serverURL;
    for (NSString *prefix in @[@"wss://", @"ws://", @"https://", @"http://"]) {
        if ([url hasPrefix:prefix]) { url = [url substringFromIndex:[prefix length]]; break; }
    }
    // 去掉 path/query 部分，只保留 host:port
    NSRange slash = [url rangeOfString:@"/"];
    if (slash.location != NSNotFound) url = [url substringToIndex:slash.location];
    NSRange colon = [url rangeOfString:@":"];
    if (colon.location != NSNotFound) {
        self.host = [url substringToIndex:colon.location];
        self.port = [[url substringFromIndex:colon.location+1] intValue];
    } else {
        self.host = url;
        self.port = 443;
    }

    NSLog(@"[WsClient] 🚀 连接 %@:%d 设备 %@", self.host, self.port, deviceId);

    // 连接 + 健康检查
    NSData *resp = [self _httpRequest:@"GET" path:@"/health" body:nil];
    if (resp) {
        NSLog(@"[WsClient] ✅ 连接成功");
        _isConnected = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate wsClientDidConnect:self];
        });
        // 上报初始状态
        [self sendMessage:@{@"type": @"status", @"data": @{@"device_id": deviceId ?: @"", @"status": @"online"}}];
        [self _startPolling];
    } else {
        NSLog(@"[WsClient] ❌ 连接失败");
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
    [self _cleanup];
}

- (void)sendMessage:(NSDictionary *)message {
    if (!message || self.intentionalDisconnect || !_isConnected) return;

    NSError *err = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:message options:0 error:&err];
    if (!json) { NSLog(@"[WsClient] ❌ JSON: %@", err); return; }

    NSString *path = [NSString stringWithFormat:@"/ws/%@", self.deviceId ?: @"unknown"];
    NSData *resp = [self _httpRequest:@"POST" path:path body:json];
    if (!resp) {
        NSLog(@"[WsClient] ⚠️ POST 失败");
        if (_isConnected) {
            _isConnected = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate wsClientDidDisconnect:self error:[NSError errorWithDomain:@"WsClient" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"请求失败"}]];
            });
        }
        return;
    }
    // 解析响应指令
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:resp options:0 error:nil];
    if ([dict isKindOfClass:[NSDictionary class]]) {
        if (dict[@"command"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate wsClient:self didReceiveMessage:dict[@"command"]];
            });
        } else if (dict[@"ack"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate wsClient:self didReceiveMessage:dict[@"ack"]];
            });
        }
    }
}

- (void)sendString:(NSString *)string {}

#pragma mark - 轮询

- (void)_startPolling {
    [self _stopPolling];
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
        dispatch_get_main_queue());
    dispatch_source_set_timer(timer,
        dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC),
        8 * NSEC_PER_SEC, 2 * NSEC_PER_SEC);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(timer, ^{ [weakSelf _pollTick]; });
    _pollTimer = timer;
    dispatch_resume(timer);
}

- (void)_stopPolling {
    if (_pollTimer) { dispatch_source_cancel(_pollTimer); _pollTimer = nil; }
}

- (void)_pollTick {
    if (self.intentionalDisconnect || !self.isConnected) return;

    NSString *path = [NSString stringWithFormat:@"/ws/%@/poll", self.deviceId ?: @"unknown"];
    NSData *resp = [self _httpRequest:@"GET" path:path body:nil];
    if (!resp) return;

    id obj = [NSJSONSerialization JSONObjectWithData:resp options:0 error:nil];
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *cmd = (NSDictionary *)obj;
        if (cmd[@"action"] || cmd[@"type"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate wsClient:self didReceiveMessage:cmd];
            });
        }
    }
}

- (void)dealloc {
    self.intentionalDisconnect = YES;
    [self _stopPolling];
    [self _cleanup];
}

@end

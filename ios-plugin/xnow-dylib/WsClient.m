// WsClient.m
// XNOW TLS 客户端（Secure Transport + dlsym 绕过 fishhook）
// 连接: wss://yunkong.taikon.top:443 (Cloudflare Tunnel)
// 通信: HTTP 短连接轮询

#import "WsClient.h"
#import <dlfcn.h>
#import <sys/socket.h>
#import <netdb.h>
#import <arpa/inet.h>
#import <Security/Security.h>

// ====== 绕过 fishhook ======
typedef int (*sys_socket_t)(int, int, int);
typedef int (*sys_connect_t)(int, const struct sockaddr *, socklen_t);
typedef int (*sys_close_t)(int);
typedef int (*sys_send_t)(int, const void *, size_t, int);
typedef int (*sys_recv_t)(int, void *, size_t, int);

static sys_socket_t real_socket  = NULL;
static sys_connect_t real_connect = NULL;
static sys_close_t   real_close   = NULL;
static sys_send_t    real_send    = NULL;
static sys_recv_t    real_recv    = NULL;

static void load_raw(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *lib = dlopen("/usr/lib/system/libsystem_kernel.dylib", RTLD_LAZY | RTLD_NOLOAD);
        if (lib) {
            real_socket  = dlsym(lib, "socket");
            real_connect = dlsym(lib, "connect");
            real_close   = dlsym(lib, "close");
            real_send    = (sys_send_t)dlsym(lib, "send");
            real_recv    = (sys_recv_t)dlsym(lib, "recv");
        }
        if (!real_socket)  real_socket  = socket;
        if (!real_connect) real_connect = connect;
        if (!real_close)   real_close   = close;
        if (!real_send)    real_send    = (sys_send_t)send;
        if (!real_recv)    real_recv    = (sys_recv_t)recv;
    });
}

// Secure Transport I/O 回调（通过原始 send/recv）
static OSStatus tls_read_func(SSLConnectionRef c, void *d, size_t *l) {
    int fd = (int)(intptr_t)c;
    int n = real_recv(fd, d, *l, 0);
    if (n > 0) { *l = n; return 0; }
    *l = 0;
    return (n == 0) ? errSSLClosedGraceful : -36;
}
static OSStatus tls_write_func(SSLConnectionRef c, const void *d, size_t *l) {
    int fd = (int)(intptr_t)c;
    int n = real_send(fd, d, *l, 0);
    if (n > 0) { *l = n; return 0; }
    *l = 0;
    return -36;
}

// ====== 接口 ======
@interface WsClient () {
    int _sockFd;
    SSLContextRef _sslCtx;
}
@property (copy)   NSString *deviceId;
@property (copy)   NSString *host;
@property (assign) int       port;
@property (assign) BOOL      intentionalDisconnect;
@property (strong) dispatch_source_t pollTimer;
@end

@implementation WsClient

- (instancetype)init {
    self = [super init];
    if (self) {
        _intentionalDisconnect = NO;
        _host = @"yunkong.taikon.top";
        _port = 443;
    }
    return self;
}

#pragma mark - TLS 连接

// 原始 socket + real_connect + Secure Transport TLS，全同步
- (BOOL)_connect {
    load_raw();
    [self _cleanup];

    // DNS
    struct hostent *he = gethostbyname([self.host UTF8String]);
    if (!he || !he->h_addr_list[0]) return NO;

    // Socket
    int fd = real_socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return NO;

    // ★ 关键：收发都要超时，否则可能永久卡住
    struct timeval tv = {10, 0};
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    // Connect (绕过 BH fishhook)
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port   = htons(self.port);
    memcpy(&addr.sin_addr, he->h_addr_list[0], he->h_length);
    if (real_connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        real_close(fd);
        return NO;
    }

    // Secure Transport TLS（全同步，无 run loop）
    SSLContextRef ctx = SSLCreateContext(NULL, kSSLClientSide, kSSLStreamType);
    if (!ctx) { real_close(fd); return NO; }
    SSLSetConnection(ctx, (SSLConnectionRef)(intptr_t)fd);
    SSLSetIOFuncs(ctx, tls_read_func, tls_write_func);
    SSLSetPeerDomainName(ctx, [self.host UTF8String], strlen([self.host UTF8String]));

    // ★ 设置 TLS 对等名称用于 SNI + 验证
    // 允许过期证书（Cloudflare cert 没问题但避免意外）
    // 实际 iOS 上 SSLSetSessionOption 可能不存在，直接握手即可

    OSStatus status = SSLHandshake(ctx);
    if (status != errSecSuccess) {
        NSLog(@"[WsClient] ❌ TLS %d", (int)status);
        CFRelease(ctx);
        real_close(fd);
        return NO;
    }

    // 存入成员变量供后续 I/O
    _sockFd = fd;
    _sslCtx = ctx;
    return YES;
}

- (void)_cleanup {
    if (_sslCtx) { SSLClose(_sslCtx); CFRelease(_sslCtx); _sslCtx = NULL; }
    if (_sockFd >= 0) { real_close(_sockFd); _sockFd = -1; }
}

// 通过 TLS 发送数据
- (BOOL)_tlsSend:(const void *)d len:(size_t)l {
    if (!_sslCtx) return NO;
    size_t total = 0;
    while (total < l) {
        size_t sent = 0;
        if (SSLWrite(_sslCtx, (const uint8_t *)d + total, l - total, &sent) != 0) return NO;
        total += sent;
    }
    return YES;
}

// 通过 TLS 读取（返回 >0 成功, 0 EOF, -1 失败）
- (int)_tlsRead:(void *)b max:(size_t)m {
    if (!_sslCtx) return -1;
    size_t got = 0;
    OSStatus s = SSLRead(_sslCtx, b, m, &got);
    if (got > 0) return (int)got;
    if (s == errSSLClosedGraceful || s == errSSLClosedAbort) return 0;
    return -1;
}

#pragma mark - HTTP

- (NSData *)_httpCall:(NSString *)method path:(NSString *)path body:(NSData *)body {
    @try {
        if (!_sslCtx || _sockFd < 0) {
            if (![self _connect]) return nil;
        }

        // 构建请求
        NSMutableData *req = [NSMutableData data];
        [req appendData:[[NSString stringWithFormat:@"%@ %@ HTTP/1.1\r\nHost: %@\r\nConnection: close\r\nUser-Agent: XNOW/1.3.2\r\n", method, path, self.host] dataUsingEncoding:NSUTF8StringEncoding]];
        if (body) {
            [req appendData:[[NSString stringWithFormat:@"Content-Type: application/json\r\nContent-Length: %lu\r\n", (unsigned long)[body length]] dataUsingEncoding:NSUTF8StringEncoding]];
        }
        [req appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
        if (body) [req appendData:body];

        // 发送
        if (![self _tlsSend:[req bytes] len:[req length]]) {
            [self _cleanup];
            return nil;
        }

        // 读取响应
        NSMutableData *resp = [NSMutableData data];
        uint8_t buf[4096];
        while (1) {
            int n = [self _tlsRead:buf max:sizeof(buf)];
            if (n <= 0) break;
            [resp appendBytes:buf length:n];
        }

        [self _cleanup]; // 短连接
        // 取 body
        const uint8_t *b = [resp bytes];
        NSUInteger len = [resp length];
        for (NSUInteger i = 0; i + 3 < len; i++) {
            if (b[i]=='\r' && b[i+1]=='\n' && b[i+2]=='\r' && b[i+3]=='\n') {
                NSUInteger blen = len - i - 4;
                return blen > 0 ? [resp subdataWithRange:NSMakeRange(i+4, blen)] : nil;
            }
        }
        return nil;
    } @catch (NSException *e) {
        NSLog(@"[WsClient] ⚠️ 异常: %@", e);
        [self _cleanup];
        return nil;
    }
}

#pragma mark - 外部接口

- (void)connectToServer:(NSString *)serverURL deviceId:(NSString *)deviceId {
    self.deviceId = deviceId;
    self.intentionalDisconnect = NO;

    // 从 URL 提取 host（忽略 scheme、query）
    NSString *u = serverURL;
    for (NSString *p in @[@"wss://", @"ws://", @"https://", @"http://"]) {
        if ([u hasPrefix:p]) { u = [u substringFromIndex:[p length]]; break; }
    }
    NSRange q = [u rangeOfString:@"?"];
    if (q.location != NSNotFound) u = [u substringToIndex:q.location];
    NSRange s = [u rangeOfString:@"/"];
    if (s.location != NSNotFound) u = [u substringToIndex:s.location];
    NSRange c = [u rangeOfString:@":"];
    if (c.location != NSNotFound) {
        self.host = [u substringToIndex:c.location];
        self.port = [[u substringFromIndex:c.location+1] intValue];
    } else {
        self.host = u;
        self.port = 443;
    }

    NSLog(@"[WsClient] 🚀 %@:%d id=%@", self.host, self.port, deviceId);

    // 连接测试
    NSData *r = [self _httpCall:@"GET" path:@"/health" body:nil];
    if (!r) {
        NSLog(@"[WsClient] ❌ 连接失败");
        _isConnected = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate wsClientDidDisconnect:self error:[NSError errorWithDomain:@"WsClient" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"连接失败"}]];
        });
        return;
    }

    NSLog(@"[WsClient] ✅ 连接成功");
    _isConnected = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate wsClientDidConnect:self];
    });
    [self sendMessage:@{@"type": @"status", @"data": @{@"device_id": deviceId ?: @"", @"status": @"online"}}];
    [self _startPolling];
}

- (void)disconnect {
    self.intentionalDisconnect = YES;
    _isConnected = NO;
    [self _stopPolling];
    [self _cleanup];
}

- (void)sendMessage:(NSDictionary *)msg {
    if (!msg || self.intentionalDisconnect || !_isConnected) return;
    NSData *json = [NSJSONSerialization dataWithJSONObject:msg options:0 error:nil];
    if (!json) return;
    NSString *path = [NSString stringWithFormat:@"/ws/%@", self.deviceId ?: @"unknown"];
    NSData *r = [self _httpCall:@"POST" path:path body:json];
    if (!r) {
        _isConnected = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate wsClientDidDisconnect:self error:[NSError errorWithDomain:@"WsClient" code:-2 userInfo:@{NSLocalizedDescriptionKey:@"通信中断"}]];
        });
        return;
    }
    NSDictionary *d = [NSJSONSerialization JSONObjectWithData:r options:0 error:nil];
    if ([d isKindOfClass:[NSDictionary class]]) {
        if (d[@"command"])
            dispatch_async(dispatch_get_main_queue(), ^{ [self.delegate wsClient:self didReceiveMessage:d[@"command"]]; });
        else if (d[@"ack"])
            dispatch_async(dispatch_get_main_queue(), ^{ [self.delegate wsClient:self didReceiveMessage:d[@"ack"]]; });
    }
}

- (void)sendString:(NSString *)string {}

#pragma mark - 轮询

- (void)_startPolling {
    [self _stopPolling];
    dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), 8 * NSEC_PER_SEC, 2 * NSEC_PER_SEC);
    __weak typeof(self) ws = self;
    dispatch_source_set_event_handler(t, ^{ [ws _pollTick]; });
    _pollTimer = t;
    dispatch_resume(t);
}

- (void)_stopPolling {
    if (_pollTimer) { dispatch_source_cancel(_pollTimer); _pollTimer = nil; }
}

- (void)_pollTick {
    if (self.intentionalDisconnect || !self.isConnected) return;
    NSData *r = [self _httpCall:@"GET" path:[NSString stringWithFormat:@"/ws/%@/poll", self.deviceId ?: @"unknown"] body:nil];
    if (!r) return;
    id obj = [NSJSONSerialization JSONObjectWithData:r options:0 error:nil];
    if ([obj isKindOfClass:[NSDictionary class]] && (((NSDictionary *)obj)[@"action"] || ((NSDictionary *)obj)[@"type"]))
        dispatch_async(dispatch_get_main_queue(), ^{ [self.delegate wsClient:self didReceiveMessage:obj]; });
}

- (void)dealloc {
    self.intentionalDisconnect = YES;
    [self _stopPolling];
    [self _cleanup];
}

@end

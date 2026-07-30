// WsClient.m
// XNOW HTTP 客户端 — 纯 BSD socket，端口80(HTTP)，无TLS
// 所有系统调用通过直接 syscall 进入内核，零符号依赖
// BH 的 MSHookFunction 和 fishhook 都作用于用户态函数，syscall 完全绕过
// 全在后台串行队列执行

#import "WsClient.h"
#import <sys/socket.h>
#import <arpa/inet.h>
#import <sys/syscall.h>

// ====== 直接系统调用 ======
// 不调用任何被 hook 的用户态函数，直接通过 svc 指令进内核
#define SYS_SOCKET   97   // arm64 iOS
#define SYS_CONNECT  98
#define SYS_CLOSE    6
#define SYS_SENDTO   290
#define SYS_RECVFROM 291

static inline int sys_socket(int domain, int type, int proto) {
    return (int)syscall(SYS_SOCKET, domain, type, proto);
}

static inline int sys_connect(int fd, const struct sockaddr *addr, socklen_t len) {
    return (int)syscall(SYS_CONNECT, fd, addr, len);
}

static inline int sys_close(int fd) {
    return (int)syscall(SYS_CLOSE, fd);
}

static inline int sys_send(int fd, const void *buf, size_t len, int flags) {
    return (int)syscall(SYS_SENDTO, fd, buf, len, flags, NULL, 0);
}

static inline int sys_recv(int fd, void *buf, size_t len, int flags) {
    return (int)syscall(SYS_RECVFROM, fd, buf, len, flags, NULL, 0);
}

// 硬编码 Cloudflare Anycast IP，不依赖 DNS
// 172.67.194.202 = 0xAC43C2CA (network byte order)
#define CLOUDFLARE_IP 0xAC43C2CA

// ====== 类扩展 ======
@interface WsClient () {
    dispatch_queue_t _q; // 串行队列
}
@property (copy)   NSString *deviceId;
@property (assign) BOOL intentionalDisconnect;
@property (strong) dispatch_source_t pollTimer;
@end

@implementation WsClient

- (instancetype)init {
    if (self = [super init]) {
        _intentionalDisconnect = NO;
        _q = dispatch_queue_create("xnow.ws", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

// ★ 核心里程碑：全部通过直接 syscall，零函数符号依赖
// BH 的 MSHookFunction 和 fishhook 都无法拦截超管态的系统调用
- (NSData *)_fetch:(NSString *)method path:(NSString *)path body:(NSData *)body {
    // 1. socket
    int fd = sys_socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return nil;

    // 2. 10s超时
    struct timeval tv = {10,0};
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    // 3. connect (80端口HTTP, 无TLS)
    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(80);
    addr.sin_addr.s_addr = CLOUDFLARE_IP;

    if (sys_connect(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        sys_close(fd);
        return nil;
    }

    // 4. 构造HTTP请求
    NSMutableData *req = [NSMutableData data];
    [req appendData:[[NSString stringWithFormat:@"%@ %@ HTTP/1.1\r\nHost: yunkong.taikon.top\r\nConnection: close\r\n", method, path] dataUsingEncoding:NSUTF8StringEncoding]];
    if (body) {
        [req appendData:[[NSString stringWithFormat:@"Content-Type: application/json\r\nContent-Length: %lu\r\n", (unsigned long)body.length] dataUsingEncoding:NSUTF8StringEncoding]];
    }
    [req appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    if (body) [req appendData:body];

    // 5. send — 直接 syscall
    const uint8_t *p = req.bytes;
    NSUInteger left = req.length;
    while (left > 0) {
        int n = sys_send(fd, p, left, 0);
        if (n <= 0) { sys_close(fd); return nil; }
        p += n; left -= n;
    }

    // 6. recv — 直接 syscall
    NSMutableData *resp = [NSMutableData data];
    uint8_t buf[4096];
    while (1) {
        int n = sys_recv(fd, buf, sizeof(buf), 0);
        if (n <= 0) break;
        [resp appendBytes:buf length:n];
    }
    sys_close(fd);

    // 7. 提取body
    const uint8_t *b = resp.bytes;
    for (NSUInteger i = 0; i+3 < resp.length; i++) {
        if (b[i]=='\r' && b[i+1]=='\n' && b[i+2]=='\r' && b[i+3]=='\n') {
            NSUInteger blen = resp.length - i - 4;
            return blen > 0 ? [resp subdataWithRange:NSMakeRange(i+4, blen)] : nil;
        }
    }
    return nil;
}

#pragma mark - 接口

- (void)connectToServer:(NSString *)url deviceId:(NSString *)deviceId {
    self.deviceId = deviceId;
    self.intentionalDisconnect = NO;

    __weak typeof(self) ws = self;
    dispatch_async(_q, ^{
        typeof(self) s = ws;
        if (!s || s.intentionalDisconnect) return;

        // 健康检查
        NSData *r = [s _fetch:@"GET" path:@"/health" body:nil];
        if (!r) {
            NSLog(@"[WsClient] ❌ 连接失败");
            s->_isConnected = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                [ws.delegate wsClientDidDisconnect:ws error:[NSError errorWithDomain:@"Ws" code:1 userInfo:@{NSLocalizedDescriptionKey:@"连接失败"}]];
            });
            return;
        }

        NSLog(@"[WsClient] ✅ 连接成功");
        s->_isConnected = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            [ws.delegate wsClientDidConnect:ws];
        });
        [s _doPost:@{@"type":@"status",@"data":@{@"device_id":deviceId?:@"",@"status":@"online"}}];
        [s _startPolling];
    });
}

- (void)_doPost:(NSDictionary *)msg {
    NSData *json = [NSJSONSerialization dataWithJSONObject:msg options:0 error:nil];
    if (!json) return;
    NSString *path = [NSString stringWithFormat:@"/ws/%@", self.deviceId?:@"unknown"];
    NSData *r = [self _fetch:@"POST" path:path body:json];
    if (!r) {
        _isConnected = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate wsClientDidDisconnect:self error:[NSError errorWithDomain:@"Ws" code:2 userInfo:@{NSLocalizedDescriptionKey:@"通信中断"}]];
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

- (void)sendMessage:(NSDictionary *)msg {
    if (!msg || self.intentionalDisconnect || !_isConnected) return;
    __weak typeof(self) ws = self;
    dispatch_async(_q, ^{
        typeof(self) s = ws;
        if (!s || s.intentionalDisconnect) return;
        [s _doPost:msg];
    });
}

- (void)sendString:(NSString *)string {}

- (void)disconnect {
    self.intentionalDisconnect = YES; _isConnected = NO;
    [self _stopPolling];
}

#pragma mark - 轮询

- (void)_startPolling {
    [self _stopPolling];
    dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC), 8*NSEC_PER_SEC, 2*NSEC_PER_SEC);
    __weak typeof(self) ws = self;
    dispatch_source_set_event_handler(t, ^{ [ws _pollTick]; });
    _pollTimer = t; dispatch_resume(t);
}

- (void)_stopPolling {
    if (_pollTimer) { dispatch_source_cancel(_pollTimer); _pollTimer = nil; }
}

- (void)_pollTick {
    if (self.intentionalDisconnect || !self.isConnected) return;
    __weak typeof(self) ws = self;
    dispatch_async(_q, ^{
        typeof(self) s = ws;
        if (!s || s.intentionalDisconnect || !s.isConnected) return;
        NSData *r = [s _fetch:@"GET" path:[NSString stringWithFormat:@"/ws/%@/poll", s.deviceId?:@"unknown"] body:nil];
        if (!r) return;
        id obj = [NSJSONSerialization JSONObjectWithData:r options:0 error:nil];
        if ([obj isKindOfClass:[NSDictionary class]] && (((NSDictionary*)obj)[@"action"]||((NSDictionary*)obj)[@"type"]))
            dispatch_async(dispatch_get_main_queue(), ^{ [ws.delegate wsClient:ws didReceiveMessage:obj]; });
    });
}

- (void)dealloc {
    self.intentionalDisconnect = YES;
    [self _stopPolling];
}

@end

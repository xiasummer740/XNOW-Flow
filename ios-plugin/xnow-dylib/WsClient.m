// WsClient.m
// XNOW HTTP 客户端 — 纯 BSD socket，端口80(HTTP)，无TLS
// 所有系统函数通过dlsym绕过BH fishhook（PLT级）
// send/recv 使用直接 syscall 绕过 BH 的 MSHookFunction（指令级inline hook）
// 全在后台串行队列执行

#import "WsClient.h"
#import <dlfcn.h>
#import <sys/socket.h>
#import <netdb.h>
#import <arpa/inet.h>
#import <sys/syscall.h>

// ====== 原始系统函数（全部走dlsym绕过BH fishhook PLT级hook） ======
typedef int (*fn_socket)(int,int,int);
typedef int (*fn_connect)(int,const struct sockaddr*,socklen_t);
typedef int (*fn_close)(int);
typedef struct hostent* (*fn_gethostbyname)(const char*);

static fn_socket       real_socket;
static fn_connect      real_connect;
static fn_close        real_close;
static fn_gethostbyname real_gethostbyname;

// 从指定dylib加载符号，返回是否成功
static bool _dlsym_from(void *lib, const char *name, void **out) {
    if (!lib) return false;
    void *p = dlsym(lib, name);
    if (p) { *out = p; return true; }
    return false;
}

static void load(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *kernel  = dlopen("/usr/lib/system/libsystem_kernel.dylib",  RTLD_LAZY|RTLD_NOLOAD);
        void *network = dlopen("/usr/lib/system/libsystem_network.dylib", RTLD_LAZY|RTLD_NOLOAD);

        _dlsym_from(kernel,  "socket",        (void**)&real_socket);
        _dlsym_from(kernel,  "connect",       (void**)&real_connect);
        _dlsym_from(kernel,  "close",         (void**)&real_close);
        _dlsym_from(kernel,  "gethostbyname", (void**)&real_gethostbyname);
        _dlsym_from(network, "gethostbyname", (void**)&real_gethostbyname);

        // 兜底
        if (!real_socket)        real_socket        = socket;
        if (!real_connect)       real_connect       = connect;
        if (!real_close)         real_close         = close;
        if (!real_gethostbyname) real_gethostbyname = gethostbyname;
    });
}

// ★ send/recv 通过直接 syscall 绕过 BH 的 MSHookFunction（指令级 inline hook）
// syscall() 直接触发 svc 指令进入内核，不经过被 hook 的 send()/recv() 函数体
#define SYS_SENDTO   290  // arm64 iOS
#define SYS_RECVFROM 291

static inline int sys_send(int fd, const void *buf, size_t len, int flags) {
    return (int)syscall(SYS_SENDTO, fd, buf, len, flags, NULL, 0);
}

static inline int sys_recv(int fd, void *buf, size_t len, int flags) {
    return (int)syscall(SYS_RECVFROM, fd, buf, len, flags, NULL, 0);
}

static uint32_t resolve_ip(void) {
    load();
    struct hostent *h = real_gethostbyname("yunkong.taikon.top");
    if (h && h->h_addr_list[0]) {
        uint32_t ip;
        memcpy(&ip, h->h_addr_list[0], 4);
        return ip;
    }
    // DNS兜底 — Cloudflare Anycast IP
    return inet_addr("172.67.194.202");
}

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

// ★ 核心里程碑：BSD socket + dlsym(connect) + syscall(send/recv)
// connect 走 dlsym 绕过 BH fishhook（PLT级），
// send/recv 走 syscall 绕过 BH MSHookFunction（指令级 inline hook）
- (NSData *)_fetch:(NSString *)method path:(NSString *)path body:(NSData *)body {
    load();

    // 1. 解析IP
    uint32_t ip = resolve_ip();
    if (!ip) return nil;

    // 2. socket
    int fd = real_socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return nil;

    // 3. 10s超时
    struct timeval tv = {10,0};
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    // 4. connect (80端口HTTP, 无TLS)
    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(80);
    addr.sin_addr.s_addr = ip;

    if (real_connect(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        real_close(fd);
        return nil;
    }

    // 5. 构造HTTP请求
    NSMutableData *req = [NSMutableData data];
    [req appendData:[[NSString stringWithFormat:@"%@ %@ HTTP/1.1\r\nHost: yunkong.taikon.top\r\nConnection: close\r\n", method, path] dataUsingEncoding:NSUTF8StringEncoding]];
    if (body) {
        [req appendData:[[NSString stringWithFormat:@"Content-Type: application/json\r\nContent-Length: %lu\r\n", (unsigned long)body.length] dataUsingEncoding:NSUTF8StringEncoding]];
    }
    [req appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    if (body) [req appendData:body];

    // 6. send — 用 syscall 绕过 MSHookFunction
    const uint8_t *p = req.bytes;
    NSUInteger left = req.length;
    while (left > 0) {
        int n = sys_send(fd, p, left, 0);
        if (n <= 0) { real_close(fd); return nil; }
        p += n; left -= n;
    }

    // 7. recv — 用 syscall 绕过 MSHookFunction
    NSMutableData *resp = [NSMutableData data];
    uint8_t buf[4096];
    while (1) {
        int n = sys_recv(fd, buf, sizeof(buf), 0);
        if (n <= 0) break;
        [resp appendBytes:buf length:n];
    }
    real_close(fd);

    // 8. 提取body
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

// WsClient.m
// 全部走 syscall 绕过 BH hook + VPS/Cloudflare 多目标探测
// connect/send/recv/socket/close 全部 syscall(0 符号依赖)

#import "WsClient.h"
#import <sys/socket.h>
#import <sys/syscall.h>
#import <sys/select.h>
#import <sys/time.h>
#import <arpa/inet.h>
#import <errno.h>
#import <fcntl.h>

// ====== 内联汇编 syscall（不调用任何函数，svc 指令直接进内核） ======
// BH 即使 hook 了 syscall() 函数也无法拦截直接 svc
#define SYS_SOCKET   97
#define SYS_CONNECT  98
#define SYS_CLOSE    6
#define SYS_FCNTL    92
#define SYS_SELECT   93
#define SYS_GETSOCKOPT 118
#define SYS_SENDTO   290
#define SYS_RECVFROM 291

__attribute__((always_inline))
static long asm_syscall(long n, long a1, long a2, long a3, long a4, long a5, long a6) {
    register long x0 __asm__("x0") = n;
    register long x1 __asm__("x1") = a1;
    register long x2 __asm__("x2") = a2;
    register long x3 __asm__("x3") = a3;
    register long x4 __asm__("x4") = a4;
    register long x5 __asm__("x5") = a5;
    register long x6 __asm__("x6") = a6;
    __asm__ volatile(
        "mov x16, x0\n"
        "mov x0, x1\n"
        "mov x1, x2\n"
        "mov x2, x3\n"
        "mov x3, x4\n"
        "mov x4, x5\n"
        "mov x5, x6\n"
        "svc #0x80\n"
        : "+r"(x0)
        : "r"(x1), "r"(x2), "r"(x3), "r"(x4), "r"(x5), "r"(x6)
        : "x16", "memory", "cc"
    );
    return x0;
}

#define RAW_SYSCALL(ret, num, ...) ret = (int)asm_syscall((num), (long)(__VA_ARGS__), 0,0,0,0,0)
#define RAW_SYSCALL6(ret, num, a1,a2,a3,a4,a5,a6) ret = (int)asm_syscall((num), (long)(a1),(long)(a2),(long)(a3),(long)(a4),(long)(a5),(long)(a6))

static int sys_sock(int d, int t, int p) { int r; RAW_SYSCALL(r, SYS_SOCKET, d,t,p); return r; }
static int sys_con(int fd, const struct sockaddr *a, socklen_t l) { int r; RAW_SYSCALL(r, SYS_CONNECT, fd,a,l); return r; }
static int sys_cls(int fd) { int r; RAW_SYSCALL(r, SYS_CLOSE, fd); return r; }
static int sys_snd(int fd, const void *b, size_t l, int f) { int r; RAW_SYSCALL6(r, SYS_SENDTO, fd,b,l,f,0,0); return r; }
static int sys_rcv(int fd, void *b, size_t l, int f) { int r; RAW_SYSCALL6(r, SYS_RECVFROM, fd,b,l,f,0,0); return r; }
static int sys_fctl(int fd, int cmd, int val) { int r; RAW_SYSCALL(r, SYS_FCNTL, fd,cmd,val); return r; }
static int sys_sel(int nfds, fd_set *r, fd_set *w, fd_set *e, struct timeval *t) { int r; RAW_SYSCALL6(r, SYS_SELECT, nfds,r,w,e,t,0); return r; }
static int sys_gso(int fd, int lv, int on, void *v, socklen_t *len) { int r; RAW_SYSCALL(r, SYS_GETSOCKOPT, fd,lv,on,v,len); return r; }

// ====== 地址 ======
#define VPS_IP  0xC081D234  // 192.129.210.52
#define CF_IP1  0xAC43C2CA  // 172.67.194.202
#define CF_IP2  0x68153525  // 104.21.52.37

// ====== 类扩展 ======
@interface WsClient () {
    dispatch_queue_t _q;
}
@property (copy)   NSString *deviceId;
@property (copy)   NSString *lastError;
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

// 试一个 IP:PORT 组合（非阻塞 + select 5s）
- (BOOL)_tryConn:(int)fd ip:(uint32_t)ip port:(int)port {
    int flags = sys_fctl(fd, F_GETFL, 0);
    if (flags >= 0) sys_fctl(fd, F_SETFL, flags | O_NONBLOCK);

    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = ip;

    int ret = sys_con(fd, (struct sockaddr*)&addr, sizeof(addr));
    if (ret == 0) { if (flags>=0) sys_fctl(fd, F_SETFL, flags); return YES; }
    if (errno != EINPROGRESS) {
        self.lastError = [NSString stringWithFormat:@"conn %d.%d.%d.%d:%d errno=%d",
            (ip>>24)&0xFF, (ip>>16)&0xFF, (ip>>8)&0xFF, ip&0xFF, port, errno];
        if (flags>=0) sys_fctl(fd, F_SETFL, flags);
        return NO;
    }

    struct timeval tv = {5, 0};
    fd_set wset;
    FD_ZERO(&wset);
    FD_SET(fd, &wset);
    ret = sys_sel(fd+1, NULL, &wset, NULL, &tv);
    if (ret <= 0) {
        self.lastError = [NSString stringWithFormat:@"conn %d.%d.%d.%d:%d timeout",
            (ip>>24)&0xFF, (ip>>16)&0xFF, (ip>>8)&0xFF, ip&0xFF, port];
        if (flags>=0) sys_fctl(fd, F_SETFL, flags);
        return NO;
    }

    int err = 0;
    socklen_t elen = sizeof(err);
    sys_gso(fd, SOL_SOCKET, SO_ERROR, &err, &elen);
    if (flags>=0) sys_fctl(fd, F_SETFL, flags);
    if (err != 0) {
        self.lastError = [NSString stringWithFormat:@"conn %d.%d.%d.%d:%d err=%d",
            (ip>>24)&0xFF, (ip>>16)&0xFF, (ip>>8)&0xFF, ip&0xFF, port, err];
        return NO;
    }
    return YES;
}

// 连接 + 发 HTTP 请求
- (NSData *)_fetch:(NSString *)method path:(NSString *)path body:(NSData *)body {
    // 目标: [ip, port] 组合
    struct { uint32_t ip; int port; } targets[] = {
        {VPS_IP, 8000},   // VPS 直连（绕过 BH hook）
        {CF_IP1, 80},     // Cloudflare
        {CF_IP1, 8080},
        {CF_IP2, 80},
        {CF_IP2, 8080},
    };
    int ntargets = sizeof(targets)/sizeof(targets[0]);

    for (int i = 0; i < ntargets; i++) {
        uint32_t ip = targets[i].ip;
        int port = targets[i].port;

        int fd = sys_sock(AF_INET, SOCK_STREAM, 0);
        if (fd < 0) continue;

        if (![self _tryConn:fd ip:ip port:port]) {
            sys_cls(fd);
            continue; // 连接失败，试下一个
        }

        // ✅ connect 成功，发 HTTP
        NSMutableData *req = [NSMutableData data];
        [req appendData:[[NSString stringWithFormat:@"%@ %@ HTTP/1.1\r\nHost: yunkong.taikon.top\r\nConnection: close\r\n", method, path] dataUsingEncoding:NSUTF8StringEncoding]];
        if (body) {
            [req appendData:[[NSString stringWithFormat:@"Content-Type: application/json\r\nContent-Length: %lu\r\n", (unsigned long)body.length] dataUsingEncoding:NSUTF8StringEncoding]];
        }
        [req appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
        if (body) [req appendData:body];

        const uint8_t *p = req.bytes;
        NSUInteger left = req.length;
        BOOL bad = NO;
        while (left > 0) {
            int n = sys_snd(fd, p, left, 0);
            if (n <= 0) { bad = YES; break; }
            p += n; left -= n;
        }
        if (bad) { sys_cls(fd); continue; }

        NSMutableData *resp = [NSMutableData data];
        uint8_t buf[4096];
        while (1) {
            int n = sys_rcv(fd, buf, sizeof(buf), 0);
            if (n <= 0) break;
            [resp appendBytes:buf length:n];
        }
        sys_cls(fd);

        const uint8_t *b = resp.bytes;
        if (resp.length > 4) {
            for (NSUInteger j = 0; j+3 < resp.length; j++) {
                if (b[j]=='\r' && b[j+1]=='\n' && b[j+2]=='\r' && b[j+3]=='\n') {
                    NSUInteger blen = resp.length - j - 4;
                    return blen > 0 ? [resp subdataWithRange:NSMakeRange(j+4, blen)] : nil;
                }
            }
        }
        // 连上了但响应不对，标记然后重试
    }
    return nil;
}

- (void)connectToServer:(NSString *)url deviceId:(NSString *)deviceId {
    self.deviceId = deviceId;
    self.intentionalDisconnect = NO;
    self.lastError = nil;

    __weak typeof(self) ws = self;
    dispatch_async(_q, ^{
        typeof(self) s = ws;
        if (!s || s.intentionalDisconnect) return;

        NSData *r = [s _fetch:@"GET" path:@"/health" body:nil];
        if (!r) {
            NSString *msg = s.lastError ?: @"全部连接尝试均失败";
            NSLog(@"[WsClient] ❌ %@", msg);
            s->_isConnected = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                [ws.delegate wsClientDidDisconnect:ws error:
                    [NSError errorWithDomain:@"Ws" code:1 userInfo:@{NSLocalizedDescriptionKey: msg}]];
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
            [self.delegate wsClientDidDisconnect:self error:
                [NSError errorWithDomain:@"Ws" code:2 userInfo:@{NSLocalizedDescriptionKey: self.lastError ?: @"通信中断"}]];
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

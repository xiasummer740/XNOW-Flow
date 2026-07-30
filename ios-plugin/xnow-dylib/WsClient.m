// WsClient.m
// XNOW HTTP 客户端 — dlsym(connect+超时) + syscall(send/recv)
// connect 非阻塞 + select 5s 超时，快速失败

#import "WsClient.h"
#import <dlfcn.h>
#import <sys/socket.h>
#import <arpa/inet.h>
#import <sys/syscall.h>
#import <sys/select.h>

// ====== dlsym 加载 ======
typedef int (*fn_socket)(int,int,int);
typedef int (*fn_connect)(int,const struct sockaddr*,socklen_t);
typedef int (*fn_close)(int);
typedef int (*fn_fcntl)(int,int,...);
typedef int (*fn_select)(int,fd_set*,fd_set*,fd_set*,struct timeval*);
typedef int (*fn_getsockopt)(int,int,int,void*,socklen_t*);

static fn_socket      real_socket;
static fn_connect     real_connect;
static fn_close       real_close;
static fn_fcntl       real_fcntl;
static fn_select      real_select;
static fn_getsockopt  real_getsockopt;

static void load(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *lib = dlopen("/usr/lib/system/libsystem_kernel.dylib", RTLD_LAZY|RTLD_NOLOAD);
        if (lib) {
            real_socket     = dlsym(lib, "socket");
            real_connect    = dlsym(lib, "connect");
            real_close      = dlsym(lib, "close");
            real_fcntl      = dlsym(lib, "fcntl");
            real_select     = dlsym(lib, "select");
            real_getsockopt = dlsym(lib, "getsockopt");
        }
        if (!real_socket)     real_socket     = socket;
        if (!real_connect)    real_connect    = connect;
        if (!real_close)      real_close      = close;
        if (!real_fcntl)      real_fcntl      = fcntl;
        if (!real_select)     real_select     = select;
        if (!real_getsockopt) real_getsockopt = getsockopt;
    });
}

// ====== syscall send/recv ======
#define SYS_SENDTO   290
#define SYS_RECVFROM 291
static inline int sys_send(int fd, const void *buf, size_t len, int flags) {
    return (int)syscall(SYS_SENDTO, fd, buf, len, flags, NULL, 0);
}
static inline int sys_recv(int fd, void *buf, size_t len, int flags) {
    return (int)syscall(SYS_RECVFROM, fd, buf, len, flags, NULL, 0);
}

// ====== 目标 ======
// 172.67.194.202 = 0xAC43C2CA
#define CLOUDFLARE_IP 0xAC43C2CA
// 104.21.52.37 = 0x68153525
#define CLOUDFLARE_IP2 0x68153525

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

// 单次 connect 尝试（非阻塞 + select 5s 超时）
- (BOOL)_tryConnect:(int)fd ip:(uint32_t)ip port:(int)port {
    // 设置非阻塞
    int flags = real_fcntl(fd, F_GETFL, 0);
    real_fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = ip;

    int ret = real_connect(fd, (struct sockaddr*)&addr, sizeof(addr));
    if (ret == 0) {
        real_fcntl(fd, F_SETFL, flags); // 恢复阻塞
        return YES;
    }
    if (errno != EINPROGRESS) {
        self.lastError = [NSString stringWithFormat:@"conn %d.%d.%d.%d:%d errno=%d",
            (ip>>24)&0xFF, (ip>>16)&0xFF, (ip>>8)&0xFF, ip&0xFF, port, errno];
        real_fcntl(fd, F_SETFL, flags);
        return NO;
    }

    // select 等待 5 秒
    struct timeval tv = {5, 0};
    fd_set wset;
    FD_ZERO(&wset);
    FD_SET(fd, &wset);
    ret = real_select(fd + 1, NULL, &wset, NULL, &tv);

    if (ret <= 0) {
        self.lastError = [NSString stringWithFormat:@"conn %d.%d.%d.%d:%d timeout",
            (ip>>24)&0xFF, (ip>>16)&0xFF, (ip>>8)&0xFF, ip&0xFF, port];
        real_fcntl(fd, F_SETFL, flags);
        return NO;
    }

    // 检查 socket 错误
    int err = 0;
    socklen_t elen = sizeof(err);
    real_getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &elen);
    real_fcntl(fd, F_SETFL, flags);
    if (err != 0) {
        self.lastError = [NSString stringWithFormat:@"conn %d.%d.%d.%d:%d err=%d",
            (ip>>24)&0xFF, (ip>>16)&0xFF, (ip>>8)&0xFF, ip&0xFF, port, err];
        return NO;
    }
    return YES; // ✅ 连接成功
}

// 尝试连接 + 发请求
- (NSData *)_fetch:(NSString *)method path:(NSString *)path body:(NSData *)body {
    load();

    // 依次尝试 2 个 IP × 2 个端口
    uint32_t ips[] = {CLOUDFLARE_IP, CLOUDFLARE_IP2};
    int ports[] = {80, 8080};
    int retryAfter = 0; // 0=正常, 1=但send/recv失败

    for (int pi = 0; pi < 2; pi++) {
        for (int ii = 0; ii < 2; ii++) {
            int port = ports[pi];
            uint32_t ip = ips[ii];

            int fd = real_socket(AF_INET, SOCK_STREAM, 0);
            if (fd < 0) continue;

            BOOL ok = [self _tryConnect:fd ip:ip port:port];
            if (!ok) { real_close(fd); continue; }

            // ✅ connect 成功，发 HTTP
            NSMutableData *req = [NSMutableData data];
            [req appendData:[[NSString stringWithFormat:@"%@ %@ HTTP/1.1\r\nHost: yunkong.taikon.top\r\nConnection: close\r\n", method, path] dataUsingEncoding:NSUTF8StringEncoding]];
            if (body) {
                [req appendData:[[NSString stringWithFormat:@"Content-Type: application/json\r\nContent-Length: %lu\r\n", (unsigned long)body.length] dataUsingEncoding:NSUTF8StringEncoding]];
            }
            [req appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
            if (body) [req appendData:body];

            // send (syscall)
            const uint8_t *p = req.bytes;
            NSUInteger left = req.length;
            BOOL sendBad = NO;
            while (left > 0) {
                int n = sys_send(fd, p, left, 0);
                if (n <= 0) { sendBad = YES; break; }
                p += n; left -= n;
            }
            if (sendBad) { real_close(fd); continue; }

            // recv (syscall)
            NSMutableData *resp = [NSMutableData data];
            uint8_t buf[4096];
            while (1) {
                int n = sys_recv(fd, buf, sizeof(buf), 0);
                if (n < 0) break;
                if (n == 0) break;
                [resp appendBytes:buf length:n];
            }
            real_close(fd);

            // 提取 body
            const uint8_t *b = resp.bytes;
            if (resp.length > 4) {
                for (NSUInteger i = 0; i+3 < resp.length; i++) {
                    if (b[i]=='\r' && b[i+1]=='\n' && b[i+2]=='\r' && b[i+3]=='\n') {
                        NSUInteger blen = resp.length - i - 4;
                        return blen > 0 ? [resp subdataWithRange:NSMakeRange(i+4, blen)] : nil;
                    }
                }
            }
            // 连上了但响应解析失败 → 标记重试
            retryAfter = 1;
            real_close(fd);
        }
    }

    // 全失败
    if (!retryAfter) {
        NSLog(@"[WsClient] ❌ 全部连接失败");
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
            NSString *errMsg = s.lastError ?: @"全部连接失败";
            NSLog(@"[WsClient] ❌ %@", errMsg);
            s->_isConnected = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                [ws.delegate wsClientDidDisconnect:ws error:
                    [NSError errorWithDomain:@"Ws" code:1 userInfo:@{NSLocalizedDescriptionKey: errMsg}]];
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

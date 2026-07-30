// WsClient.m
// XNOW HTTP 客户端 — 多IP多端口探测 + syscall(send/recv)

#import "WsClient.h"
#import <dlfcn.h>
#import <sys/socket.h>
#import <arpa/inet.h>
#import <sys/syscall.h>

// ====== dlsym 加载（socket/connect/close） ======
typedef int (*fn_socket)(int,int,int);
typedef int (*fn_connect)(int,const struct sockaddr*,socklen_t);
typedef int (*fn_close)(int);

static fn_socket  real_socket;
static fn_connect real_connect;
static fn_close   real_close;

static void load(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *lib = dlopen("/usr/lib/system/libsystem_kernel.dylib", RTLD_LAZY|RTLD_NOLOAD);
        if (lib) {
            real_socket  = dlsym(lib, "socket");
            real_connect = dlsym(lib, "connect");
            real_close   = dlsym(lib, "close");
        }
        if (!real_socket)  real_socket  = socket;
        if (!real_connect) real_connect = connect;
        if (!real_close)   real_close   = close;
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

// ====== 多 IP 探测 ======
// Cloudflare Anycast IPs for yunkong.taikon.top
static const uint32_t TRY_IPS[] = {
    0xAC43C2CA,  // 172.67.194.202
    0x68153525,  // 104.21.52.37
};
static const int TRY_PORTS[] = {80, 8080, 443};
#define IP_COUNT  (sizeof(TRY_IPS)/sizeof(TRY_IPS[0]))
#define PORT_COUNT (sizeof(TRY_PORTS)/sizeof(TRY_PORTS[0]))

// ====== 类扩展 ======
@interface WsClient () {
    dispatch_queue_t _q;
}
@property (copy)   NSString *deviceId;
@property (copy)   NSString *lastError;  // 最后一次错误详情
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

// 尝试所有 IP:PORT 组合，直到一个成功
- (NSData *)_fetch:(NSString *)method path:(NSString *)path body:(NSData *)body {
    load();

    for (int pi = 0; pi < PORT_COUNT; pi++) {
        for (int ii = 0; ii < IP_COUNT; ii++) {
            int port = TRY_PORTS[pi];
            uint32_t ip = TRY_IPS[ii];

            int fd = real_socket(AF_INET, SOCK_STREAM, 0);
            if (fd < 0) continue;

            struct sockaddr_in addr = {0};
            addr.sin_family = AF_INET;
            addr.sin_port = htons(port);
            addr.sin_addr.s_addr = ip;

            if (real_connect(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
                self.lastError = [NSString stringWithFormat:@"conn %d.%d.%d.%d:%d errno=%d",
                    (ip>>24)&0xFF, (ip>>16)&0xFF, (ip>>8)&0xFF, ip&0xFF, port, errno];
                real_close(fd);
                continue;
            }

            // connect 成功 → 发 HTTP 请求
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
            BOOL sendOk = YES;
            while (left > 0) {
                int n = sys_send(fd, p, left, 0);
                if (n <= 0) { sendOk = NO; break; }
                p += n; left -= n;
            }
            if (!sendOk) { real_close(fd); continue; }

            // recv (syscall)
            NSMutableData *resp = [NSMutableData data];
            uint8_t buf[4096];
            while (1) {
                int n = sys_recv(fd, buf, sizeof(buf), 0);
                if (n <= 0) break;
                [resp appendBytes:buf length:n];
            }
            real_close(fd);

            // 提取 HTTP body
            const uint8_t *b = resp.bytes;
            for (NSUInteger i = 0; i+3 < resp.length; i++) {
                if (b[i]=='\r' && b[i+1]=='\n' && b[i+2]=='\r' && b[i+3]=='\n') {
                    NSUInteger blen = resp.length - i - 4;
                    return blen > 0 ? [resp subdataWithRange:NSMakeRange(i+4, blen)] : nil;
                }
            }
            return nil;
        }
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
            NSString *errMsg = s.lastError ?: @"全部连接尝试均失败";
            NSLog(@"[WsClient] ❌ 连接失败 — %@", errMsg);
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

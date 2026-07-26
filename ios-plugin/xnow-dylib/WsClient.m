// WsClient.m
// XNOW HTTP 客户端（纯原始 BSD socket，无 TLS）
// 所有系统调用通过 dlsym 从 libsystem_kernel.dylib 加载，绕过 BH fishhook
// 连接目标：yunkong.taikon.top:80 (Cloudflare HTTP → Tunnel → VPS)
// 通信：HTTP 短连接轮询（每次新建连接，用完即关）

#import "WsClient.h"
#import <dlfcn.h>
#import <sys/socket.h>
#import <netdb.h>
#import <arpa/inet.h>

// ====== 绕过 fishhook — 从系统库加载原始函数 ======
typedef int (*sys_socket_t)(int, int, int);
typedef int (*sys_connect_t)(int, const struct sockaddr *, socklen_t);
typedef int (*sys_close_t)(int);
typedef int (*sys_send_t)(int, const void *, size_t, int);
typedef int (*sys_recv_t)(int, void *, size_t, int);

static sys_socket_t real_socket = NULL;
static sys_connect_t real_connect = NULL;
static sys_close_t   real_close   = NULL;
static sys_send_t    real_send    = NULL;
static sys_recv_t    real_recv    = NULL;

static void load_raw_funcs(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *lib = dlopen("/usr/lib/system/libsystem_kernel.dylib", RTLD_LAZY | RTLD_NOLOAD);
        if (lib) {
            real_socket  = (sys_socket_t)dlsym(lib, "socket");
            real_connect = (sys_connect_t)dlsym(lib, "connect");
            real_close   = (sys_close_t)dlsym(lib, "close");
            real_send    = (sys_send_t)dlsym(lib, "send");
            real_recv    = (sys_recv_t)dlsym(lib, "recv");
        }
        // fallback（如果 dlsym 被 MSHookFunction 也 hook 了再试原始符号）
        if (!real_socket)  real_socket  = socket;
        if (!real_connect) real_connect = connect;
        if (!real_close)   real_close   = close;
        if (!real_send)    real_send    = (sys_send_t)send;
        if (!real_recv)    real_recv    = (sys_recv_t)recv;
    });
}

// ====== 接口定义 ======
@interface WsClient ()
@property (nonatomic, copy)   NSString *deviceId;
@property (nonatomic, copy)   NSString *host;
@property (nonatomic, assign) int       port;
@property (nonatomic, assign) BOOL      intentionalDisconnect;
@property (nonatomic, strong) dispatch_source_t pollTimer;
@end

@implementation WsClient

- (instancetype)init {
    self = [super init];
    if (self) {
        _intentionalDisconnect = NO;
        _host = @"yunkong.taikon.top";
        _port = 80;
    }
    return self;
}

#pragma mark - 原始 TCP + HTTP（完全无 TLS）

// 建立原始 TCP 连接，发送 HTTP 请求，读取完整响应，关闭连接
// 返回: 响应 body (NSData)，失败返回 nil
- (NSData *)_httpCall:(NSString *)method path:(NSString *)path body:(NSData *)body {
    load_raw_funcs();

    // 1. DNS 解析
    struct hostent *he = gethostbyname([self.host UTF8String]);
    if (!he || !he->h_addr_list[0]) {
        NSLog(@"[WsClient] ❌ DNS 失败: %@", self.host);
        return nil;
    }

    // 2. 原始 socket
    int fd = real_socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) { return nil; }

    // 3. 连接超时（防止卡死）
    struct timeval tv = {8, 0}; // 8 秒
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    // 4. 原始 connect
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port   = htons(self.port);
    memcpy(&addr.sin_addr, he->h_addr_list[0], he->h_length);

    if (real_connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        real_close(fd);
        return nil;
    }

    // 5. 构造 HTTP 请求
    NSMutableData *reqData = [NSMutableData data];
    [reqData appendData:[[NSString stringWithFormat:@"%@ %@ HTTP/1.1\r\nHost: %@\r\nConnection: close\r\nUser-Agent: XNOW/1.3.2\r\n", method, path, self.host] dataUsingEncoding:NSUTF8StringEncoding]];
    if (body) {
        [reqData appendData:[[NSString stringWithFormat:@"Content-Type: application/json\r\nContent-Length: %lu\r\n", (unsigned long)[body length]] dataUsingEncoding:NSUTF8StringEncoding]];
    }
    [reqData appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    if (body) {
        [reqData appendData:body];
    }

    // 6. 原始 send
    const uint8_t *ptr = [reqData bytes];
    NSUInteger remain = [reqData length];
    while (remain > 0) {
        int n = real_send(fd, ptr, remain, 0);
        if (n <= 0) { real_close(fd); return nil; }
        ptr += n;
        remain -= n;
    }

    // 7. 原始 recv
    NSMutableData *resp = [NSMutableData data];
    uint8_t buf[4096];
    while (1) {
        int n = real_recv(fd, buf, sizeof(buf), 0);
        if (n <= 0) break;
        [resp appendBytes:buf length:n];
    }

    real_close(fd);

    // 8. 解析 HTTP 响应 body
    return [self _parseBody:resp];
}

// 从 HTTP 响应中提取 body（跳过 \r\n\r\n）
- (NSData *)_parseBody:(NSData *)data {
    if (!data || data.length < 4) return nil;
    const uint8_t *b = [data bytes];
    NSUInteger len = [data length];
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

    // 从 URL 提取 host（忽略 scheme 和 query 参数）
    NSString *url = serverURL;
    for (NSString *p in @[@"wss://", @"ws://", @"https://", @"http://"]) {
        if ([url hasPrefix:p]) { url = [url substringFromIndex:[p length]]; break; }
    }
    // 去掉 query & fragment
    NSRange qm = [url rangeOfString:@"?"];
    if (qm.location != NSNotFound) url = [url substringToIndex:qm.location];
    // 只保留 host:port
    NSRange slash = [url rangeOfString:@"/"];
    if (slash.location != NSNotFound) url = [url substringToIndex:slash.location];
    // 解析 host:port
    NSRange colon = [url rangeOfString:@":"];
    if (colon.location != NSNotFound) {
        self.host = [url substringToIndex:colon.location];
        self.port = [[url substringFromIndex:colon.location+1] intValue];
    } else {
        self.host = url;
        self.port = 80; // 走 HTTP，不走 HTTPS
    }

    NSLog(@"[WsClient] 🚀 %@:%d 设备:%@", self.host, self.port, deviceId);

    // 健康检查
    NSData *resp = [self _httpCall:@"GET" path:@"/health" body:nil];
    if (resp) {
        NSLog(@"[WsClient] ✅ 连接成功");
        _isConnected = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate wsClientDidConnect:self];
        });
        [self sendMessage:@{@"type": @"status", @"data": @{@"device_id": deviceId ?: @"", @"status": @"online"}}];
        [self _startPolling];
    } else {
        NSLog(@"[WsClient] ❌ 连接失败");
        _isConnected = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSError *e = [NSError errorWithDomain:@"WsClient" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"连接服务器失败"}];
            [self.delegate wsClientDidDisconnect:self error:e];
        });
    }
}

- (void)disconnect {
    self.intentionalDisconnect = YES;
    _isConnected = NO;
    [self _stopPolling];
}

- (void)sendMessage:(NSDictionary *)message {
    if (!message || self.intentionalDisconnect || !_isConnected) return;

    NSError *err = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:message options:0 error:&err];
    if (!json) return;

    NSString *path = [NSString stringWithFormat:@"/ws/%@", self.deviceId ?: @"unknown"];
    NSData *resp = [self _httpCall:@"POST" path:path body:json];
    if (!resp) {
        if (_isConnected) {
            _isConnected = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate wsClientDidDisconnect:self error:[NSError errorWithDomain:@"WsClient" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"通信中断"}]];
            });
        }
        return;
    }

    // 解析响应指令
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:resp options:0 error:nil];
    if ([dict isKindOfClass:[NSDictionary class]]) {
        if (dict[@"command"]) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self.delegate wsClient:self didReceiveMessage:dict[@"command"]]; });
        } else if (dict[@"ack"]) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self.delegate wsClient:self didReceiveMessage:dict[@"ack"]]; });
        } else if ([dict[@"pong"] boolValue]) {
            // ping pong，忽略
        }
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
    NSString *path = [NSString stringWithFormat:@"/ws/%@/poll", self.deviceId ?: @"unknown"];
    NSData *resp = [self _httpCall:@"GET" path:path body:nil];
    if (!resp) return;

    id obj = [NSJSONSerialization JSONObjectWithData:resp options:0 error:nil];
    if ([obj isKindOfClass:[NSDictionary class]] && (((NSDictionary *)obj)[@"action"] || ((NSDictionary *)obj)[@"type"])) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self.delegate wsClient:self didReceiveMessage:(NSDictionary *)obj]; });
    }
}

- (void)dealloc {
    self.intentionalDisconnect = YES;
    [self _stopPolling];
}

@end

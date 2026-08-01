// WsClient.m
// XNOW HTTP 客户端 — 基于 NSURLSession（借 TikTok 网络栈）
// 直连 socket 全被运营商封锁，NSURLSession 走 TikTok 的 URL Loading System 可达
// 连接到 VPS:8000（实测可达，Cloudflare 被封）

#import "WsClient.h"

// 后端地址（VPS 直连，Cloudflare 被封）
#define XN_BACKEND_HOST @"192.129.210.52"
#define XN_BACKEND_PORT 8000

// ====== 类扩展 ======
@interface WsClient () {
    dispatch_queue_t _q;
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

// ★ 核心里程碑：NSURLSession 借 TikTok 网络栈通信（VPS:8000 实测可达）
- (NSData *)_fetch:(NSString *)method path:(NSString *)path body:(NSData *)body {
    NSString *urlStr = [NSString stringWithFormat:@"http://%@:%d%@", XN_BACKEND_HOST, XN_BACKEND_PORT, path];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return nil;

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = method;
    if (body) {
        req.HTTPBody = body;
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }
    [req setValue:@"close" forHTTPHeaderField:@"Connection"];
    req.timeoutInterval = 10;

    __block NSData *result = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);

    // ephemeral session（同 XNURLProtocol 已验证可用）
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.timeoutIntervalForRequest = 10;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

    [[session dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
            if (data && !error) {
                NSHTTPURLResponse *hr = (NSHTTPURLResponse *)resp;
                if (hr.statusCode == 200) {
                    result = data;
                }
            }
            dispatch_semaphore_signal(sema);
            [session finishTasksAndInvalidate];
    }] resume];

    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC));
    return result;
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
                [ws.delegate wsClientDidDisconnect:ws error:
                    [NSError errorWithDomain:@"Ws" code:1 userInfo:@{NSLocalizedDescriptionKey:@"连接失败"}]];
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
                [NSError errorWithDomain:@"Ws" code:2 userInfo:@{NSLocalizedDescriptionKey:@"通信中断"}]];
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
    dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), 5 * NSEC_PER_SEC, 2 * NSEC_PER_SEC);
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
        if ([obj isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)obj;
            if (dict[@"action"] || dict[@"type"])
                dispatch_async(dispatch_get_main_queue(), ^{ [ws.delegate wsClient:ws didReceiveMessage:dict]; });
        }
    });
}

- (void)dealloc {
    self.intentionalDisconnect = YES;
    [self _stopPolling];
}

@end

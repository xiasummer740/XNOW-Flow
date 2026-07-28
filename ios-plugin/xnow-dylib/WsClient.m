// WsClient.m
// XNOW HTTP 客户端 — 基于 NSURLSessionDataTask
// 所有网络请求通过 XPC → nsurlsessiond 独立进程 → TCP
// 绕过 BH TikTok 的 send/recv inline hook
// 零外部依赖，适配 iOS 13+

#import "WsClient.h"

// ====== 类扩展 ======
@interface WsClient () {
    dispatch_queue_t _q; // 串行队列
}
@property (copy)   NSString *baseURL;
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

/// 解析原始 serverURL（可能含 wss:// + 查询参数），返回 http(s)://host 基础 URL
/// 例如: wss://yunkong.taikon.top?api_id=xxx → http://yunkong.taikon.top
- (NSString *)_parseBaseURL:(NSString *)rawURL {
    if (!rawURL || rawURL.length == 0) return nil;

    // 去掉查询参数
    NSString *cleanURL = rawURL;
    NSRange qmark = [cleanURL rangeOfString:@"?"];
    if (qmark.location != NSNotFound) {
        cleanURL = [cleanURL substringToIndex:qmark.location];
    }

    // 替换 scheme: wss:// → https://, ws:// → http://
    if ([cleanURL hasPrefix:@"wss://"]) {
        cleanURL = [cleanURL stringByReplacingCharactersInRange:NSMakeRange(0, 6) withString:@"https://"];
    } else if ([cleanURL hasPrefix:@"ws://"]) {
        cleanURL = [cleanURL stringByReplacingCharactersInRange:NSMakeRange(0, 5) withString:@"http://"];
    }

    // 确保末尾没有斜杠
    if ([cleanURL hasSuffix:@"/"]) {
        cleanURL = [cleanURL substringToIndex:cleanURL.length - 1];
    }

    return cleanURL;
}

// ★ 核心里程碑：NSURLSessionDataTask 替代 BSD socket
// NSURLSession 内部通过 XPC (Mach IPC) 与系统守护进程 nsurlsessiond 通信
// 实际 TCP 连接在 nsurlsessiond 独立进程中完成
// BH TikTok 的 send/recv inline hook 作用域仅在 TikTok 进程内，无法触及
- (NSData *)_fetch:(NSString *)method path:(NSString *)path body:(NSData *)body {
    if (!self.baseURL) return nil;

    NSString *urlStr = [NSString stringWithFormat:@"%@%@", self.baseURL, path];
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

    [[[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
            if (data && !error) {
                NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)resp;
                if (httpResp.statusCode == 200) {
                    result = data;
                }
            }
            dispatch_semaphore_signal(sema);
    }] resume];

    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC));
    return result;
}

#pragma mark - 接口

- (void)connectToServer:(NSString *)url deviceId:(NSString *)deviceId {
    self.baseURL = [self _parseBaseURL:url];
    self.deviceId = deviceId;
    self.intentionalDisconnect = NO;

    if (!self.baseURL) {
        NSLog(@"[WsClient] ❌ 无效 URL: %@", url);
        _isConnected = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate wsClientDidDisconnect:self error:
                [NSError errorWithDomain:@"Ws" code:3 userInfo:@{NSLocalizedDescriptionKey:@"无效URL"}]];
        });
        return;
    }

    __weak typeof(self) ws = self;
    dispatch_async(_q, ^{
        typeof(self) s = ws;
        if (!s || s.intentionalDisconnect) return;

        // 健康检查
        NSData *r = [s _fetch:@"GET" path:@"/health" body:nil];
        if (!r) {
            NSLog(@"[WsClient] ❌ 连接失败 (baseURL=%@)", s.baseURL);
            s->_isConnected = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                [ws.delegate wsClientDidDisconnect:ws error:
                    [NSError errorWithDomain:@"Ws" code:1 userInfo:@{NSLocalizedDescriptionKey:@"连接失败"}]];
            });
            return;
        }

        NSLog(@"[WsClient] ✅ 连接成功 (baseURL=%@)", s.baseURL);
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
    // 解析响应中的指令
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
    dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), 8 * NSEC_PER_SEC, 2 * NSEC_PER_SEC);
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

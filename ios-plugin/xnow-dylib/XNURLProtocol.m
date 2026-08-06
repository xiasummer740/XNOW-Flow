// XNURLProtocol.m
// 轻量 NSURLProtocol — 用 TikTok 的网络栈做 piggyback 通信
//
// 流程:
//   TikTok 发起 HTTP 请求 → canInitWithRequest: 判断是否拦截
//   → startLoading: 标记防递归 + 转发原始请求 + 向后端发心跳
//   → 后端可达则标记成功，后续可扩展为轮询指令
//
// 注意:
//   - 只拦截 feed/recommend 请求（频率适中，不影响核心功能）
//   - 转发时标记请求，防止 XNOWURLProtocol（TikTokHooks.m 中的）重复拦截
//   - 向后端通信使用 ephemeral session（无 cookie/cache 副作用）

#import "XNURLProtocol.h"

// ====== 防递归标记（同时兼容 TikTokHooks.m 中的 XNOWURLProtocol） ======
static NSString *const kXNHandledKey    = @"XN_piggyback_handled";
static NSString *const kXNProcKey       = @"XNOWER_processed";

// ====== 后端配置 ======
// 优先 VPS 直连（运营商封了 Cloudflare，但 VPS IP 通）
// 后端地址（全局共享，供 XNOWER 等使用）
NSString *const kXnowBackendHost = @"192.129.210.52";
int const kXnowBackendPort = 8000;
#define XN_BACKEND_HOST  kXnowBackendHost
#define XN_BACKEND_PORT  kXnowBackendPort
#define XN_POLL_INTERVAL 8.0  // 秒，两次后端请求最小间隔

// ====== 全局状态 ======
static volatile BOOL    sBackendReachable = NO;
static volatile CFAbsoluteTime sLastPing = 0;

// ====== 类扩展 ======
@interface XNURLProtocol ()
@property (strong) NSURLSessionDataTask *forwardTask;
@property (strong) NSURLSession *forwardSession;
@end

@implementation XNURLProtocol

/// 后端是否可达（供其他模块查询）
+ (BOOL)isBackendReachable {
    return sBackendReachable;
}

/// 手动立即检测后端连通性（按钮触发用，不限频）
+ (void)checkBackendNow:(void (^)(BOOL ok))completion {
    NSString *urlStr = [NSString stringWithFormat:@"http://%@:%d/api/health",
                         XN_BACKEND_HOST, XN_BACKEND_PORT];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) { if (completion) completion(NO); return; }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";
    req.timeoutInterval = 10;

    NSURLSessionConfiguration *ephemeral = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:ephemeral];

    [[session dataTaskWithRequest:req
                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        BOOL ok = NO;
        if (!error) {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            ok = (httpResp.statusCode == 200);
            sBackendReachable = ok;
            NSLog(@"[XNURLProtocol] %@ checkBackendNow: %@",
                  ok ? @"✅" : @"❌",
                  ok ? @"后端可达" : [NSString stringWithFormat:@"HTTP %ld", (long)httpResp.statusCode]);
        } else {
            NSLog(@"[XNURLProtocol] ❌ checkBackendNow: %@", error.localizedDescription);
        }
        if (completion) completion(ok);
        [session finishTasksAndInvalidate];
    }] resume];
}

/// 读取设备共享密钥（NSUserDefaults，由 XNOWER 初始化）
+ (NSString *)_deviceSecret {
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"XN_DeviceSecret"] ?: @"";
}

/// 通用请求（纯完成回调，无 semaphore）
+ (void)_sendRequest:(NSString *)method path:(NSString *)path body:(NSData *)body
          completion:(void (^)(NSData *data, NSError *error))completion {
    // 附加设备密钥鉴权
    NSString *secret = [self _deviceSecret];
    NSString *authPath = path;
    if (secret.length > 0) {
        authPath = [path containsString:@"?"] ?
            [NSString stringWithFormat:@"%@&secret=%@", path, secret] :
            [NSString stringWithFormat:@"%@?secret=%@", path, secret];
    }
    NSString *urlStr = [NSString stringWithFormat:@"http://%@:%d%@",
                         XN_BACKEND_HOST, XN_BACKEND_PORT, authPath];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) { if (completion) completion(nil, [NSError errorWithDomain:@"XN" code:9 userInfo:nil]); return; }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = method;
    if (body) {
        req.HTTPBody = body;
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }
    req.timeoutInterval = 10;

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = 10;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];

    [[session dataTaskWithRequest:req
                completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
        if (completion) completion(data, error);
        [session finishTasksAndInvalidate];
    }] resume];
}

/// 上报设备状态
+ (void)reportOnline:(NSString *)deviceId {
    if (!deviceId) return;
    NSString *appVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    NSDictionary *payload = @{
        @"type": @"status",
        @"data": @{
            @"device_id": deviceId,
            @"status": @"online",
            @"app_version": appVersion,
            @"bundle_id": bundleId,
        }
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!json) return;
    NSString *path = [NSString stringWithFormat:@"/ws/%@", deviceId];
    [self _sendRequest:@"POST" path:path body:json completion:^(NSData *data, NSError *error) {
        if (error) {
            NSLog(@"[XNURLProtocol] ⚠️ 上报失败: %@", error.localizedDescription);
        } else {
            NSLog(@"[XNURLProtocol] ✅ 已上报设备状态");
            // 上报响应可能带回指令
            [self _handleResponseData:data];
        }
    }];
}

/// 发送消息（上报账号/结果等），响应可能带回指令
+ (void)sendMessage:(NSDictionary *)msg deviceId:(NSString *)deviceId {
    [self sendMessage:msg deviceId:deviceId completion:nil];
}

/// 发送消息，带完成回调（ok = 回传成功，供浮窗日志显示回传结果）
+ (void)sendMessage:(NSDictionary *)msg deviceId:(NSString *)deviceId
         completion:(void (^)(BOOL ok, NSError *error))completion {
    if (!msg || !deviceId) { if (completion) completion(NO, nil); return; }
    NSData *json = [NSJSONSerialization dataWithJSONObject:msg options:0 error:nil];
    if (!json) { if (completion) completion(NO, nil); return; }
    NSString *path = [NSString stringWithFormat:@"/ws/%@", deviceId];
    [self _sendRequest:@"POST" path:path body:json completion:^(NSData *data, NSError *error) {
        BOOL ok = (!error && data);
        if (ok) [self _handleResponseData:data];
        if (completion) completion(ok, error);
    }];
}

/// 轮询指令
+ (void)pollCommands:(NSString *)deviceId {
    if (!deviceId) return;
    NSString *path = [NSString stringWithFormat:@"/ws/%@/poll", deviceId];
    [self _sendRequest:@"GET" path:path body:nil completion:^(NSData *data, NSError *error) {
        if (!error && data) [self _handleResponseData:data];
    }];
}

/// 激活卡密（POST /api/biz/v2/licenses/activate/）
/// 请求体 {key, device_id, udid}，响应 {status, expires_at}
+ (void)activateLicense:(NSString *)key deviceId:(NSString *)deviceId udid:(NSString *)udid
             completion:(void (^)(NSDictionary *result, NSError *error))completion {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    if (key.length > 0) payload[@"key"] = key;
    if (deviceId.length > 0) payload[@"device_id"] = deviceId;
    if (udid.length > 0) payload[@"udid"] = udid;
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!json) {
        if (completion) completion(nil, [NSError errorWithDomain:@"XN" code:10 userInfo:nil]);
        return;
    }
    [self _sendRequest:@"POST" path:@"/api/biz/v2/licenses/activate/" body:json
            completion:^(NSData *data, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSDictionary *result = nil;
        if (data) {
            id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([obj isKindOfClass:[NSDictionary class]]) result = obj;
        }
        if (completion) completion(result, nil);
    }];
}

/// 检查设备授权状态（GET /api/biz/v2/licenses/device/{uid}/）
/// 使用设备唯一标识 UID（Keychain 持久化），重装/改编号不丢授权。
/// 响应 {licensed, status, expires_at, days_left}
+ (void)checkLicenseForDevice:(NSString *)uid
                   completion:(void (^)(BOOL licensed, NSDictionary *info))completion {
    if (uid.length == 0) {
        if (completion) completion(NO, nil);
        return;
    }
    // 用稳定 UID 查授权（后端同时匹配 udid 和 device_id）
    NSString *path = [NSString stringWithFormat:@"/api/biz/v2/licenses/device/%@/", uid];
    [self _sendRequest:@"GET" path:path body:nil completion:^(NSData *data, NSError *error) {
        BOOL licensed = NO;
        NSDictionary *info = nil;
        if (!error && data) {
            id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([obj isKindOfClass:[NSDictionary class]]) {
                info = obj;
                id licensedVal = obj[@"licensed"];
                if ([licensedVal respondsToSelector:@selector(boolValue)]) {
                    licensed = [licensedVal boolValue];
                }
            }
        }
        if (completion) completion(licensed, info);
    }];
}

/// 解析响应中的指令并派发
/// 兼容两种格式:
///   - POST 响应: {"status":"ok", "command": {...}}   → 取 d[@"command"]
///   - poll 响应: {"type":"command","action":"..."}     → 响应本身就是指令
+ (void)_handleResponseData:(NSData *)data {
    if (!data) return;
    NSDictionary *d = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![d isKindOfClass:[NSDictionary class]]) return;

    NSDictionary *cmd = d[@"command"];
    if (![cmd isKindOfClass:[NSDictionary class]] && (d[@"type"] || d[@"action"])) {
        cmd = d;  // poll 响应直接就是指令本体
    }
    if (![cmd isKindOfClass:[NSDictionary class]]) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"XNPiggybackCommand"
                                                            object:nil
                                                          userInfo:@{@"command": cmd}];
    });
}

#pragma mark - NSURLProtocol 拦截判定

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    // 防递归（同时兼容 XNOWURLProtocol 的标记）
    if ([NSURLProtocol propertyForKey:kXNHandledKey inRequest:request] ||
        [NSURLProtocol propertyForKey:kXNProcKey inRequest:request]) {
        return NO;
    }

    NSString *url = request.URL.absoluteString;

    // 轻量拦截 — 只拦截 TikTok 的 feed/recommend API 请求
    // 这些请求 TikTok 频繁发出，我们挑一种做 piggyback 而不影响其他功能
    if ([url containsString:@"tiktok.com"] || [url containsString:@"byteoversea.com"]) {
        if ([url containsString:@"/feed"] || [url containsString:@"/recommend"]) {
            return YES;
        }
    }

    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

#pragma mark - 拦截处理

- (void)startLoading {
    // 标记防递归（双标记兼容 XNOWURLProtocol）
    NSMutableURLRequest *forwardReq = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:kXNHandledKey inRequest:forwardReq];
    [NSURLProtocol setProperty:@YES forKey:kXNProcKey    inRequest:forwardReq];

    // [Piggyback] 利用 TikTok 网络栈向后端发心跳（限频）
    [self _maybePingBackend];

    // 转发原始请求回 TikTok（让 TikTok 正常工作）
    [self _forwardRequest:forwardReq];
}

- (void)stopLoading {
    [self.forwardTask cancel];
    self.forwardTask = nil;
}

#pragma mark - 转发原始请求

/// 共享转发 session（避免每个请求新建 session 造成卡顿）
+ (NSURLSession *)_sharedForwardSession {
    static NSURLSession *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 20;
        config.timeoutIntervalForResource = 30;
        s = [NSURLSession sessionWithConfiguration:config];
    });
    return s;
}

- (void)_forwardRequest:(NSURLRequest *)request {
    __weak typeof(self) weakSelf = self;
    self.forwardTask = [[XNURLProtocol _sharedForwardSession] dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (error) {
                [strongSelf.client URLProtocol:strongSelf didFailWithError:error];
            } else {
                [strongSelf.client URLProtocol:strongSelf didReceiveResponse:response
                                cacheStoragePolicy:NSURLCacheStorageNotAllowed];
                [strongSelf.client URLProtocol:strongSelf didLoadData:data];
                [strongSelf.client URLProtocolDidFinishLoading:strongSelf];
            }
        }];
    [self.forwardTask resume];
}

#pragma mark - Piggyback: 向后端通信（限频）

- (void)_maybePingBackend {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - sLastPing < XN_POLL_INTERVAL) return;
    sLastPing = now;

    // 构造后端健康检查 URL
    NSString *urlStr = [NSString stringWithFormat:@"http://%@:%d/api/health",
                         XN_BACKEND_HOST, XN_BACKEND_PORT];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return;

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";
    req.timeoutInterval = 10;

    // 复用共享 session（不每次新建，降低开销）
    NSURLSession *session = [XNURLProtocol _sharedForwardSession];

    [[session dataTaskWithRequest:req
                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[XNURLProtocol] ⚠️ Backend unreachable: %@", error.localizedDescription);
            sBackendReachable = NO;
        } else {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            sBackendReachable = (httpResp.statusCode == 200);
            if (sBackendReachable) {
                NSLog(@"[XNURLProtocol] ✅ Backend REACHABLE (HTTP %ld, %lu bytes)",
                      (long)httpResp.statusCode, (unsigned long)data.length);
            } else {
                NSLog(@"[XNURLProtocol] ⚠️ Backend responded HTTP %ld",
                      (long)httpResp.statusCode);
            }
        }
        [session finishTasksAndInvalidate];
    }] resume];
}

@end

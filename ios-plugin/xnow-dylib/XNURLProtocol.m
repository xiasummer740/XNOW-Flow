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
#import "CountryEnv.h"

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
static NSDictionary     *gLastFeedVideo = nil;   // 最近一次 feed 响应里的视频信息（供下载无水印视频）
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
    // 【v1.4.97 安全修复】设备密钥不再拼进 URL query（server.log/代理会明文记录泄露设备密钥），
    // 改走 X-Device-Secret 请求头。后端双兼容：header 优先，query 兜底（旧设备/旧后端过渡期）。
    NSString *secret = [self _deviceSecret];
    NSString *urlStr = [NSString stringWithFormat:@"http://%@:%d%@",
                         XN_BACKEND_HOST, XN_BACKEND_PORT, path];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) { if (completion) completion(nil, [NSError errorWithDomain:@"XN" code:9 userInfo:nil]); return; }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = method;
    if (body) {
        req.HTTPBody = body;
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }
    if (secret.length > 0) {
        [req setValue:secret forHTTPHeaderField:@"X-Device-Secret"];
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

/// v1.4.108 F14 私信实时翻译：调后端 /api/biz/v2/translate/（设备 secret 已由 _sendRequest 带 header）
+ (void)translateText:(NSString *)text
           targetLang:(NSString *)targetLang
             deviceId:(NSString *)deviceId
           completion:(void (^)(NSString *translated, NSError *error))completion {
    if (!text.length || !deviceId.length) {
        if (completion) completion(nil, [NSError errorWithDomain:@"XN" code:9 userInfo:nil]);
        return;
    }
    NSDictionary *payload = @{
        @"text": text,
        @"target_lang": targetLang ?: @"中文",
        @"device_id": deviceId,
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!json) { if (completion) completion(nil, [NSError errorWithDomain:@"XN" code:9 userInfo:nil]); return; }
    [self _sendRequest:@"POST" path:@"/api/biz/v2/translate/" body:json
            completion:^(NSData *data, NSError *error) {
        if (error || !data) { if (completion) completion(nil, error); return; }
        NSDictionary *j = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *translated = j[@"translated"];
        if (completion) completion([translated isKindOfClass:[NSString class]] ? translated : text, nil);
    }];
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

/// v1.4.108 F6：上传视频到后台落库（multipart/form-data，60s 超时）
/// 先下载 URL → 再 multipart POST /api/biz/v2/videos/save/ → 后端存 data/uploads/ + Media 表
/// 不复用 _sendRequest（强制 application/json + 10s 超时），单独走 NSURLSession multipart
+ (void)uploadVideoToBackend:(NSString *)url
                    metadata:(NSDictionary *)metadata
                    deviceId:(NSString *)deviceId
                  completion:(void (^)(BOOL ok, NSString *message))completion {
    if (!url.length || !deviceId.length) {
        if (completion) completion(NO, @"参数缺失");
        return;
    }
    // Step 1: 下载视频（TikTok CDN 有重定向，用可重定向 NSURLSession）
    __block NSData *videoData = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSession *dlSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    [[dlSession dataTaskWithURL:[NSURL URLWithString:url]
              completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        videoData = d;
        dispatch_semaphore_signal(sem);
    }] resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC));
    [dlSession finishTasksAndInvalidate];
    if (!videoData || videoData.length == 0) {
        if (completion) completion(NO, @"下载视频失败");
        return;
    }
    NSLog(@"[XNURLProtocol] 视频下载完成 %lu bytes，上传后台...", (unsigned long)videoData.length);

    // Step 2: multipart/form-data 构造（boundary 随机；顺序：先文本字段 → file → 结束标记）
    NSString *boundary = [NSString stringWithFormat:@"XNOW-Boundary-%d", arc4random()];
    NSMutableData *body = [NSMutableData data];
    void (^addField)(NSString *, NSString *) = ^(NSString *name, NSString *value) {
        [body appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n", boundary, name, value ?: @""] dataUsingEncoding:NSUTF8StringEncoding]];
    };
    addField(@"device_id", deviceId);
    addField(@"author", metadata[@"author"] ?: @"");
    addField(@"desc", metadata[@"desc"] ?: @"");
    addField(@"aweme_id", metadata[@"aweme_id"] ?: @"");
    [body appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"file\"; filename=\"video.mp4\"\r\nContent-Type: video/mp4\r\n\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:videoData];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];

    // Step 3: POST 上传（设备 secret 走 header，同 _sendRequest 安全模式）
    NSString *urlStr = [NSString stringWithFormat:@"http://%@:%d/api/biz/v2/videos/save/",
                        XN_BACKEND_HOST, XN_BACKEND_PORT];
    NSURL *uploadURL = [NSURL URLWithString:urlStr];
    if (!uploadURL) { if (completion) completion(NO, @"URL 非法"); return; }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:uploadURL];
    req.HTTPMethod = @"POST";
    req.HTTPBody = body;
    [req setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary]
 forHTTPHeaderField:@"Content-Type"];
    NSString *secret = [self _deviceSecret];
    if (secret.length > 0) [req setValue:secret forHTTPHeaderField:@"X-Device-Secret"];
    req.timeoutInterval = 60;

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = 60;
    NSURLSession *upSession = [NSURLSession sessionWithConfiguration:cfg];
    [[upSession dataTaskWithRequest:req
                  completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
        BOOL ok = (!error && data);
        NSString *msg = @"";
        if (data) {
            NSDictionary *j = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (j[@"message"]) msg = j[@"message"];
        }
        if (error) NSLog(@"[XNURLProtocol] 视频上传失败: %@", error.localizedDescription);
        [upSession finishTasksAndInvalidate];
        if (completion) completion(ok, msg);
    }] resume];
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

/// 回关自动私信：随机取一条激活话术（设备 secret 鉴权，POST 带 device_id）
+ (void)fetchReplyTemplate:(NSString *)deviceId
                completion:(void (^)(NSDictionary *template, NSError *error))completion {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    if (deviceId.length > 0) payload[@"device_id"] = deviceId;
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!json) {
        if (completion) completion(nil, [NSError errorWithDomain:@"XN" code:10 userInfo:nil]);
        return;
    }
    [self _sendRequest:@"POST" path:@"/api/biz/v2/reply-templates/device-random/" body:json
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

    // 轻量拦截 — feed/recommend（piggyback）只拦 tiktok.com/byteoversea.com（tiktokv.com 全量拦截曾导致不稳定，已撤）
    // /user/ 额外拦 tiktokv.com（低频，仅用于当前用户资料捕获，供备份/账号检测）
    BOOL onTikHost = [url containsString:@"tiktok.com"] || [url containsString:@"byteoversea.com"];
    BOOL onTikVHost = [url containsString:@"tiktokv.com"];
    if ([url containsString:@"/user/"]) {
        if (onTikHost || onTikVHost) return YES;
    } else if (onTikHost) {
        if ([url containsString:@"/feed"] || [url containsString:@"/recommend"]) return YES;
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

    // [环境伪装] 若已设置目标国，改写 region/时区/语言/MCC 等 query 参数（与出口IP一致）
    [CountryEnv applyEnvToMutableRequest:forwardReq];

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
    BOOL isFeed = [request.URL.absoluteString containsString:@"/feed"]
               || [request.URL.absoluteString containsString:@"/recommend"];
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
                // 从 feed 响应提取当前视频的无水印 URL（供"下载无水印视频"使用，避免 UI 自动化崩溃）
                if (isFeed && data.length > 0) {
                    [XNURLProtocol _captureFeedVideo:data];
                }
            }
        }];
    [self.forwardTask resume];
}

/// 解析 feed/recommend 响应，缓存第一条视频的无水印播放地址
+ (void)_captureFeedVideo:(NSData *)data {
    @try {
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![obj isKindOfClass:[NSDictionary class]]) return;
        NSArray *list = obj[@"aweme_list"];
        if (![list isKindOfClass:[NSArray class]] || list.count == 0) return;
        NSDictionary *aweme = list[0];
        if (![aweme isKindOfClass:[NSDictionary class]]) return;

        NSDictionary *video = aweme[@"video"];
        NSString *url = nil;
        if ([video isKindOfClass:[NSDictionary class]]) {
            NSDictionary *playAddr = video[@"play_addr"];
            NSArray *urls = playAddr[@"url_list"];
            if ([urls isKindOfClass:[NSArray class]] && urls.count > 0) {
                url = [urls firstObject];
            }
            if (!url) {
                NSDictionary *dlAddr = video[@"download_addr"];
                NSArray *dlUrls = dlAddr[@"url_list"];
                if ([dlUrls isKindOfClass:[NSArray class]] && dlUrls.count > 0) url = [dlUrls firstObject];
            }
        }

        NSString *awemeId = [aweme[@"aweme_id"] isKindOfClass:[NSString class]] ? aweme[@"aweme_id"] : @"";
        NSString *author = [aweme valueForKeyPath:@"author.nickname"];
        if (![author isKindOfClass:[NSString class]]) author = @"";
        NSString *desc = aweme[@"desc"];
        if (![desc isKindOfClass:[NSString class]]) desc = @"";

        if (url.length > 0) {
            gLastFeedVideo = @{@"url": url, @"author": author, @"desc": desc, @"aweme_id": awemeId};
            NSLog(@"[XNOWER] 已捕获feed视频URL(无水印): %@", url);
        }
    } @catch (NSException *e) {
        NSLog(@"[XNOWER] feed解析异常: %@", e.reason);
    }
}

/// 返回最近一次 feed 捕获到的视频信息
+ (NSDictionary *)lastFeedVideo {
    return gLastFeedVideo ?: @{};
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

    // ⚠️ 修复闪退：原实现复用 _sharedForwardSession 并 finishTasksAndInvalidate 销毁它，
    // 导致 TikTok feed 转发(_forwardRequest 也用共享 session)在已销毁 session 上建任务崩溃。
    // 改为独立 session（不复用共享、不销毁），每次用完释放。
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = 10;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];

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

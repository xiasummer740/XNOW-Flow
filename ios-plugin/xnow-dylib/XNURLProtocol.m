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
#define XN_BACKEND_HOST  @"192.129.210.52"
#define XN_BACKEND_PORT  8000
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
    NSString *urlStr = [NSString stringWithFormat:@"http://%@:%d/health",
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
    [self.forwardSession invalidateAndCancel];
    self.forwardSession = nil;
}

#pragma mark - 转发原始请求

- (void)_forwardRequest:(NSURLRequest *)request {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    self.forwardSession = [NSURLSession sessionWithConfiguration:config];

    __weak typeof(self) weakSelf = self;
    self.forwardTask = [self.forwardSession dataTaskWithRequest:request
                                              completionHandler:^(NSData *data,
                                                                  NSURLResponse *response,
                                                                  NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (error) {
            [strongSelf.client URLProtocol:strongSelf didFailWithError:error];
        } else {
            [strongSelf.client URLProtocol:strongSelf
                         didReceiveResponse:response
                         cacheStoragePolicy:NSURLCacheStorageNotAllowed];
            [strongSelf.client URLProtocol:strongSelf didLoadData:data];
            [strongSelf.client URLProtocolDidFinishLoading:strongSelf];
        }
        [strongSelf.forwardSession finishTasksAndInvalidate];
        strongSelf.forwardSession = nil;
    }];
    [self.forwardTask resume];
}

#pragma mark - Piggyback: 向后端通信（限频）

- (void)_maybePingBackend {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - sLastPing < XN_POLL_INTERVAL) return;
    sLastPing = now;

    // 构造后端健康检查 URL
    NSString *urlStr = [NSString stringWithFormat:@"http://%@:%d/health",
                         XN_BACKEND_HOST, XN_BACKEND_PORT];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return;

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";
    req.timeoutInterval = 10;

    // ephemeral session: 不存 cookie/cache，最小副作用
    NSURLSessionConfiguration *ephemeral = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:ephemeral];

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

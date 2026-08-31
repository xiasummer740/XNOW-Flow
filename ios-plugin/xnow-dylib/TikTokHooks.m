// TikTokHooks.m
// TikTok 运行时方法挂钩完整实现
// 包含: 生命周期监控 + 网络数据拦截 + ViewController 追踪 + 页面状态采集

#import "TikTokHooks.h"
#import "XNOWER.h"
#import "XNURLProtocol.h"
#import "AccountManager.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

#define XNOW_LOG(fmt, ...) NSLog(@"[XNOWER] " fmt, ##__VA_ARGS__)
#define XNOW_FILE_LOG(fmt, ...) XNOW_LOG(fmt, ##__VA_ARGS__)

#pragma mark - Swizzle 工具

static void SwizzleInstanceMethod(Class cls, SEL original, SEL swizzled) {
    Method origMethod = class_getInstanceMethod(cls, original);
    Method newMethod = class_getInstanceMethod(cls, swizzled);
    if (!origMethod || !newMethod) return;

    BOOL didAdd = class_addMethod(cls, original,
                                  method_getImplementation(newMethod),
                                  method_getTypeEncoding(newMethod));
    if (didAdd) {
        class_replaceMethod(cls, swizzled,
                            method_getImplementation(origMethod),
                            method_getTypeEncoding(origMethod));
    } else {
        method_exchangeImplementations(origMethod, newMethod);
    }
}

static void SwizzleClassMethod(Class cls, SEL original, SEL swizzled) {
    SwizzleInstanceMethod(objc_getMetaClass(object_getClassName(cls)),
                          original, swizzled);
}

#pragma mark - XNOWURLProtocol — 网络数据拦截器

@protocol XNOWDataCollector <NSObject>
+ (void)onTikTokAPIResponse:(NSDictionary *)json url:(NSString *)url;
@end

@interface XNOWURLProtocol : NSURLProtocol <NSURLSessionDelegate>
@property (nonatomic, strong) NSURLSessionDataTask *dataTask;
@end

// 数据收集代理（由 XNOWER 设置）
static __weak id<XNOWDataCollector> sDataCollector = nil;

// ====== v1.4.136 网络路径探针（XNOWURLProtocol 侧） ======
static volatile int64_t  sXNOWAsked   = 0;  // canInitWithRequest 被询问次数（URL Loading System 是否经过）
static volatile int64_t  sXNOWHandled = 0;  // startLoading 实际拦截次数
static NSMutableArray    *sXNowURLs   = nil; // 最近 URL 环形缓冲
// ====== v1.4.138 全局询问计数（XNOWURLProtocol 侧） ======
static volatile int64_t  sXNOWGlobalAsked = 0;  // 不管域名，被系统问一次 +1 —— 区分「注册成功被系统询问」vs「从未注册」
static NSMutableArray    *sXNOWGlobalURLs = nil; // 全局最近 URL（含第三方，证明系统确实在问本协议）
// ====== v1.4.136 网络路径探针（NSURLSession swizzle 侧） ======
static volatile int64_t  sSessionHits = 0;  // NSURLSession dataTask 命中次数（TikTok 是否走系统栈）
static NSMutableArray    *sSessionURLs = nil;
static BOOL              sSwizzlingSession = NO; // 防递归（dataTaskWithRequest: 内部可能调带 completion 的变体）
// ====== v1.4.138 net_sniff 时间盒抓包缓冲 ======
static NSMutableArray    *sSniffURLs = nil;  // 时间盒内捕获的所有 URL（append-only，不被环形缓冲覆盖）
static BOOL              sSniffActive = NO;  // 抓包进行中

// v1.4.138 前向声明：实现定义在后面（@implementation NSURLSession (XNOWERProbe) 之前）
static void XNProbeRecordURL(NSMutableArray *__strong *buf, NSString *url, NSString *via);

@implementation XNOWURLProtocol

+ (void)setDataCollector:(id<XNOWDataCollector>)collector {
    sDataCollector = collector;
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *url = request.URL.absoluteString;

    // v1.4.138 全局询问计数：不管域名，被系统问一次 +1 并记录 URL。
    // 若 global_asked>0 而 TikTok 域 asked==0 → 协议注册成功、系统确实在问，
    // 但 TikTok 请求不走 URL Loading System（→ 路线 B）。
    // 若 global_asked==0 → 协议从未被系统询问（注册失败/未生效）。
    sXNOWGlobalAsked++;
    if (url.length > 0) {
        XNProbeRecordURL(&sXNOWGlobalURLs, url, @"xnow-global");
        [TikTokHooks sniffRecord:url];  // v1.4.138 net_sniff 时间盒
    }

    // 只拦截 TikTok 关键 API
    static NSArray *patterns = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        patterns = @[
            @"musically.com",
            @"tiktok.com",
            @"amemv.com",
            @"douyin.com",
            @"byteoversea.com",
        ];
    });

    for (NSString *pattern in patterns) {
        if ([url containsString:pattern]) {
            // v1.4.136 探针：TikTok 域请求是否经过 URL Loading System（排除非 TikTok 请求污染计数）
            sXNOWAsked++;
            [TikTokHooks _recordURL:url via:@"xnow"];
            // 防止重复拦截
            if ([NSURLProtocol propertyForKey:@"XNOWER_processed" inRequest:request]) {
                return NO;
            }
            return YES;
        }
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    sXNOWHandled++;
    NSMutableURLRequest *newRequest = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"XNOWER_processed" inRequest:newRequest];

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config
                                                          delegate:self
                                                     delegateQueue:nil];

    self.dataTask = [session dataTaskWithRequest:newRequest
                               completionHandler:^(NSData *data,
                                                   NSURLResponse *response,
                                                   NSError *error) {
        if (error) {
            [self.client URLProtocol:self didFailWithError:error];
            return;
        }

        // 解析 JSON 响应
        if (data && response) {
            NSError *jsonError = nil;
            id jsonObj = [NSJSONSerialization JSONObjectWithData:data
                                                         options:0
                                                           error:&jsonError];
            if (!jsonError && jsonObj) {
                NSString *urlStr = self.request.URL.absoluteString;

                // 通知数据收集器
                [sDataCollector onTikTokAPIResponse:jsonObj url:urlStr];

                // 记录关键数据路径
                if ([urlStr containsString:@"feed"] || [urlStr containsString:@"item"]) {
                    XNOW_FILE_LOG(@"API: %@ - %lu bytes", urlStr, (unsigned long)data.length);
                }
            }

            [self.client URLProtocol:self didReceiveResponse:response
                    cacheStoragePolicy:NSURLCacheStorageNotAllowed];
            [self.client URLProtocol:self didLoadData:data];
            [self.client URLProtocolDidFinishLoading:self];
        }
    }];
    [self.dataTask resume];
}

- (void)stopLoading {
    [self.dataTask cancel];
}

#pragma mark - NSURLSessionDelegate

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
      didCompleteWithError:(NSError *)error {
    if (error) {
        [self.client URLProtocol:self didFailWithError:error];
    }
    [session finishTasksAndInvalidate];
}

@end

#pragma mark - NSURLSession 网络路径探针 (v1.4.136)

/// 记录最近 URL 到 sSessionURLs/sXNowURLs（环形缓冲，上限 10）
static void XNProbeRecordURL(NSMutableArray *__strong *buf, NSString *url, NSString *via) {
    if (url.length == 0) return;
    if (*buf == nil) *buf = [NSMutableArray arrayWithCapacity:12];
    NSDictionary *entry = @{@"t": @(CFAbsoluteTimeGetCurrent()), @"url": url, @"via": via};
    [*buf insertObject:entry atIndex:0];
    while ((*buf).count > 10) [*buf removeLastObject];
}

@implementation NSURLSession (XNOWERProbe)

- (NSURLSessionDataTask *)xnow_dataTaskWithRequest:(NSURLRequest *)request {
    if (sSwizzlingSession) return [self xnow_dataTaskWithRequest:request]; // 防递归（原实现内部再调变体）
    sSwizzlingSession = YES;
    [NSURLSession _probeSessionRequest:request];
    NSURLSessionDataTask *t = [self xnow_dataTaskWithRequest:request];
    sSwizzlingSession = NO;
    return t;
}

- (NSURLSessionDataTask *)xnow_dataTaskWithRequest:(NSURLRequest *)request
                                 completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (sSwizzlingSession) return [self xnow_dataTaskWithRequest:request completionHandler:completionHandler];
    sSwizzlingSession = YES;
    [NSURLSession _probeSessionRequest:request];
    NSURLSessionDataTask *t = [self xnow_dataTaskWithRequest:request completionHandler:completionHandler];
    sSwizzlingSession = NO;
    return t;
}

// ====== v1.4.138 扩展 swizzle 变体（覆盖 TikTok 可能用的其他 dataTask 入口） ======

- (NSURLSessionDataTask *)xnow_dataTaskWithURL:(NSURL *)url {
    if (sSwizzlingSession) return [self xnow_dataTaskWithURL:url];
    sSwizzlingSession = YES;
    if (url) {
        NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:url];
        [NSURLSession _probeSessionRequest:r];
    }
    NSURLSessionDataTask *t = [self xnow_dataTaskWithURL:url];
    sSwizzlingSession = NO;
    return t;
}

- (NSURLSessionUploadTask *)xnow_uploadTaskWithRequest:(NSURLRequest *)request
                                              fromData:(NSData *)bodyData {
    if (sSwizzlingSession) return [self xnow_uploadTaskWithRequest:request fromData:bodyData];
    sSwizzlingSession = YES;
    [NSURLSession _probeSessionRequest:request];
    NSURLSessionUploadTask *t = [self xnow_uploadTaskWithRequest:request fromData:bodyData];
    sSwizzlingSession = NO;
    return t;
}

/// 探针：统计命中 + 记录 URL + 统一缓存 feed headers（供净网络层复用 app 会话）
+ (void)_probeSessionRequest:(NSURLRequest *)request {
    if (!request || !request.URL) return;
    // 排除后端自己的请求（避免污染命中计数 / 刷掉 recent_urls）
    NSString *host = request.URL.host.lowercaseString ?: @"";
    if ([host containsString:@"192.129.210.52"] || [host isEqualToString:@"localhost"]) return;
    sSessionHits++;
    NSString *url = request.URL.absoluteString;
    // 统一缓存 feed/recommend 请求的 header+URL（同一入口，与 XNURLProtocol.startLoading 共用）
    [XNURLProtocol cacheFeedRequestHeaders:request];
    [TikTokHooks sniffRecord:url];  // v1.4.138 net_sniff 时间盒
    @synchronized ([NSURLSession class]) {
        XNProbeRecordURL(&sSessionURLs, url, @"session");
    }
}

@end

#pragma mark - UIViewController Hooks

@interface UIViewController (XNOWER)
@end

@implementation UIViewController (XNOWER)

- (void)xnow_viewDidAppear:(BOOL)animated {
    [self xnow_viewDidAppear:animated];

    NSString *className = NSStringFromClass([self class]);
    NSString *title = self.title ?: @"";

    // 识别 TikTok 页面类型
    NSString *pageType = @"unknown";
    if ([className containsString:@"Feed"] || [className containsString:@"MainViewController"]) {
        pageType = @"feed";
    } else if ([className containsString:@"Profile"] || [className containsString:@"UserProfile"]) {
        pageType = @"profile";
    } else if ([className containsString:@"Comment"]) {
        pageType = @"comment";
    } else if ([className containsString:@"Search"]) {
        pageType = @"search";
    } else if ([className containsString:@"Video"] || [className containsString:@"Player"]) {
        pageType = @"video_detail";
    } else if ([className containsString:@"Photo"]) {
        pageType = @"photo";
    } else if ([className containsString:@"Follow"]) {
        pageType = @"following";
    } else if ([className containsString:@"Shop"] || [className containsString:@"Mall"]) {
        pageType = @"shop";
    } else if ([className containsString:@"Message"] || [className containsString:@"Inbox"]) {
        pageType = @"inbox";
    } else if ([className containsString:@"Setting"]) {
        pageType = @"settings";
    }

    XNOW_LOG(@"Page: %@ | %@", className, pageType);
    XNOW_FILE_LOG(@"PAGE: %@ (%@)", pageType, className);
}

- (void)xnow_viewDidDisappear:(BOOL)animated {
    [self xnow_viewDidDisappear:animated];
}

@end

#pragma mark - UIApplication Hooks

@interface UIApplication (XNOWER)
@end

@implementation UIApplication (XNOWER)

- (void)xnow_sendEvent:(UIEvent *)event {
    // 在事件分发前拦截（可用于监控用户操作）
    [self xnow_sendEvent:event];
}

- (void)xnow_applicationWillResignActive {
    [self xnow_applicationWillResignActive];
    XNOW_FILE_LOG(@"APP:进入后台");
}

- (void)xnow_applicationDidBecomeActive {
    [self xnow_applicationDidBecomeActive];
    XNOW_FILE_LOG(@"APP:回到前台");
}

@end

#pragma mark - UIScrollView Hook（用于检测滑动）

@interface UIScrollView (XNOWER)
@end

@implementation UIScrollView (XNOWER)

- (void)xnow_setContentOffset:(CGPoint)contentOffset {
    [self xnow_setContentOffset:contentOffset];

    // 检测大幅滑动（翻页）— 上报后端，用于验证远程滑动指令是否真正让 feed 滚动
    static CGFloat lastOffsetY = 0;
    CGFloat diff = fabs(contentOffset.y - lastOffsetY);
    if (diff > self.bounds.size.height * 0.3) {
        XNOW_LOG(@"Scroll page: offset %.0f -> %.0f", lastOffsetY, contentOffset.y);
        @try {
            NSString *devId = [XNOWER sharedInstance].deviceId;
            if (devId.length > 0) {
                [XNURLProtocol sendMessage:@{
                    @"type": @"scroll_event",
                    @"data": @{@"from": @(lastOffsetY), @"to": @(contentOffset.y), @"delta": @(diff)}
                } deviceId:devId];
            }
        } @catch (NSException *e) {
            XNOW_LOG(@"scroll report error: %@", e.reason);
        }
    }
    lastOffsetY = contentOffset.y;
}

@end

#pragma mark - 数据采集器实现

@interface TikTokHooks () <XNOWDataCollector>
@end

@implementation TikTokHooks

static TikTokHooks *gHooksInstance = nil;

#pragma mark - v1.4.136 网络路径探针

/// 记录最近观察到的 URL（XNOWURLProtocol 侧；NSURLSession 侧走 XNProbeRecordURL）
+ (void)_recordURL:(NSString *)url via:(NSString *)via {
    @synchronized ([TikTokHooks class]) {
        XNProbeRecordURL(&sXNowURLs, url, via);
    }
}

/// XNOWURLProtocol 侧诊断（供 net_diag）
+ (NSDictionary *)xnowURLProtocolNetDiag {
    NSArray *urls = nil;
    @synchronized ([TikTokHooks class]) { urls = [sXNowURLs copy] ?: @[]; }
    NSArray *globalURLs = nil;
    @synchronized ([TikTokHooks class]) { globalURLs = [sXNOWGlobalURLs copy] ?: @[]; }
    return @{@"asked": @(sXNOWAsked),
             @"handled": @(sXNOWHandled),
             @"global_asked": @(sXNOWGlobalAsked),
             @"recent_urls": urls,
             @"global_recent_urls": globalURLs};
}

/// NSURLSession swizzle 侧诊断（供 net_diag）
+ (NSDictionary *)nsurlSessionNetDiag {
    NSArray *urls = nil;
    @synchronized ([NSURLSession class]) { urls = [sSessionURLs copy] ?: @[]; }
    return @{@"hits": @(sSessionHits),
             @"recent_urls": urls};
}

+ (void)installHooks {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        XNOW_LOG(@"===================================");
        XNOW_LOG(@"XNOWER 开始安装 TikTok Hooks...");
        XNOW_LOG(@"设备: %@ %@",
                 [[UIDevice currentDevice] model],
                 [[UIDevice currentDevice] systemVersion]);
        XNOW_LOG(@"===================================");

        // 1. UIViewController 生命周期（页面追踪）
        SwizzleInstanceMethod([UIViewController class],
                              @selector(viewDidAppear:),
                              @selector(xnow_viewDidAppear:));
        SwizzleInstanceMethod([UIViewController class],
                              @selector(viewDidDisappear:),
                              @selector(xnow_viewDidDisappear:));
        XNOW_LOG(@"  [OK] UIViewController viewDidAppear/viewDidDisappear");

        // 2. UIApplication 事件管道（触摸事件监控）
        SwizzleInstanceMethod([UIApplication class],
                              @selector(sendEvent:),
                              @selector(xnow_sendEvent:));
        XNOW_LOG(@"  [OK] UIApplication sendEvent");

        // 3. 前后台切换
        SwizzleInstanceMethod([UIApplication class],
                              @selector(applicationWillResignActive),
                              @selector(xnow_applicationWillResignActive));
        SwizzleInstanceMethod([UIApplication class],
                              @selector(applicationDidBecomeActive),
                              @selector(xnow_applicationDidBecomeActive));
        XNOW_LOG(@"  [OK] UIApplication foreground/background");

        // 4. UIScrollView 滑动检测
        SwizzleInstanceMethod([UIScrollView class],
                              @selector(setContentOffset:),
                              @selector(xnow_setContentOffset:));
        XNOW_LOG(@"  [OK] UIScrollView contentOffset");

        // 5. 注册 URL 协议拦截器
        [NSURLProtocol registerClass:[XNOWURLProtocol class]];
        XNOW_LOG(@"  [OK] NSURLProtocol (TikTok API 拦截)");

        // 5.5 NSURLSession 网络路径探针（v1.4.136）：记录 TikTok 请求是否走系统栈 + 统一缓存 feed headers。
        //     swizzle dataTaskWithRequest 两个变体（覆盖绝大多数请求发起路径）。
        SwizzleInstanceMethod([NSURLSession class],
                              @selector(dataTaskWithRequest:),
                              @selector(xnow_dataTaskWithRequest:));
        SwizzleInstanceMethod([NSURLSession class],
                              @selector(dataTaskWithRequest:completionHandler:),
                              @selector(xnow_dataTaskWithRequest:completionHandler:));
        // v1.4.138 扩展变体：TikTok 可能用 dataTaskWithURL: / uploadTask（防 swizzle 覆盖不全误判路线）
        SwizzleInstanceMethod([NSURLSession class],
                              @selector(dataTaskWithURL:),
                              @selector(xnow_dataTaskWithURL:));
        SwizzleInstanceMethod([NSURLSession class],
                              @selector(uploadTaskWithRequest:fromData:),
                              @selector(xnow_uploadTaskWithRequest:fromData:));
        XNOW_LOG(@"  [OK] NSURLSession probe (dataTask/uploadTask swizzle)");

        // 6. 初始化数据采集器
        gHooksInstance = [[TikTokHooks alloc] init];
        [XNOWURLProtocol setDataCollector:gHooksInstance];
        XNOW_LOG(@"  [OK] 数据采集器就绪");

        XNOW_LOG(@"===================================");
        XNOW_LOG(@"XNOWER 所有 Hooks 安装完成");
        XNOW_LOG(@"===================================");
    });
}

#pragma mark - net_sniff 时间盒抓包（v1.4.138）

/// 开始抓包：清空缓冲，开始记录所有观察到的 URL（不管域名/层）
+ (void)sniffBegin {
    @synchronized ([TikTokHooks class]) {
        sSniffURLs = [NSMutableArray array];
        sSniffActive = YES;
    }
}

/// 抓包期间记录一个 URL（三个观察点都调：canInit xnow / canInit xnurl / session probe）
+ (void)sniffRecord:(NSString *)url {
    if (url.length == 0) return;
    @synchronized ([TikTokHooks class]) {
        if (!sSniffActive) return;
        [sSniffURLs addObject:@{@"t": @(CFAbsoluteTimeGetCurrent()), @"url": url}];
    }
}

/// 结束抓包：返回结果并复位
+ (NSDictionary *)sniffCollect {
    @synchronized ([TikTokHooks class]) {
        NSArray *urls = sSniffURLs ? [sSniffURLs copy] : @[];
        sSniffURLs = nil;
        sSniffActive = NO;
        // 按 host 聚合（去 scheme + 去 query 的 host）
        NSMutableDictionary *hostCount = [NSMutableDictionary dictionary];
        for (NSDictionary *e in urls) {
            NSString *u = e[@"url"];
            NSURL *parsed = [NSURL URLWithString:u];
            NSString *host = parsed.host ?: @"";
            if (host.length == 0) continue;
            hostCount[host] = @([hostCount[host] intValue] + 1);
        }
        NSMutableArray *hosts = [NSMutableArray array];
        [hostCount enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) {
            [hosts addObject:@{@"host": k, @"count": v}];
        }];
        [hosts sortUsingComparator:^NSComparisonResult(id a, id b) {
            return [b[@"count"] compare:a[@"count"]];
        }];
        return @{@"total": @(urls.count),
                 @"hosts": hosts,
                 @"recent_urls": urls.count > 30 ? [urls subarrayWithRange:NSMakeRange(0, 30)] : urls};
    }
}

- (instancetype)init {
    self = [super init];
    if (self) {
    }
    return self;
}

#pragma mark - XNOWDataCollector

+ (void)onTikTokAPIResponse:(NSDictionary *)json url:(NSString *)url {
    [gHooksInstance onTikTokAPIResponse:json url:url];
}

- (void)onTikTokAPIResponse:(NSDictionary *)json url:(NSString *)url {
    // 解析 TikTok API 响应，提取有价值的数据
    @try {
        // Feed 列表响应
        if ([url containsString:@"feed"] || [url containsString:@"recommend"]) {
            NSArray *items = json[@"data"][@"itemList"] ?: json[@"itemList"] ?: @[];
            XNOW_FILE_LOG(@"FEED: %lu videos loaded", (unsigned long)[items count]);

            // 提取每个视频的信息
            for (NSDictionary *item in items) {
                NSString *vid = item[@"video"][@"id"] ?: item[@"id"] ?: @"";
                NSString *desc = item[@"desc"] ?: @"";
                NSString *author = item[@"author"][@"uniqueId"] ?: item[@"author"][@"nickname"] ?: @"";
                NSNumber *likes = item[@"stats"][@"diggCount"] ?: @(0);
                NSNumber *comments = item[@"stats"][@"commentCount"] ?: @(0);

                if (vid.length > 0) {
                    [self _cacheVideoInfo:@{
                        @"id": vid,
                        @"desc": desc,
                        @"author": author,
                        @"likes": likes,
                        @"comments": comments,
                    }];
                }
            }
        }

        // 用户资料响应
        if ([url containsString:@"user"]) {
            NSDictionary *user = json[@"data"][@"user"] ?: json[@"user"] ?: @{};
            NSString *uid = user[@"id"] ?: user[@"uid"] ?: @"";
            NSString *nickname = user[@"nickname"] ?: user[@"uniqueId"] ?: @"";
            NSNumber *fans = user[@"stats"][@"followerCount"] ?: @(0);
            NSNumber *followings = user[@"stats"][@"followingCount"] ?: @(0);
            NSNumber *likes = user[@"stats"][@"heart"] ?: @(0);

            if (uid.length > 0) {
                XNOW_FILE_LOG(@"USER: %@ (%@) | 粉丝:%@ 关注:%@ 获赞:%@",
                              nickname, uid, fans, followings, likes);
            }

            // 路由到 AccountManager 做详细解析
            [[AccountManager sharedManager] onTikTokAPIResponse:json url:url];
        }
    } @catch (NSException *e) {
        // 解析失败不阻塞
    }
}

/// 缓存视频信息到本地 plist（供 collect_videos 使用）
+ (NSMutableArray *)_cachedVideos {
    static NSMutableArray *videos = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        videos = [NSMutableArray array];
    });
    return videos;
}

- (void)_cacheVideoInfo:(NSDictionary *)info {
    NSMutableArray *videos = [TikTokHooks _cachedVideos];
    @synchronized(videos) {
        NSString *vid = info[@"id"];
        for (NSDictionary *v in videos) {
            if ([v[@"id"] isEqualToString:vid]) return;
        }
        [videos addObject:info];
    }
}

/// 获取缓存的视频列表
+ (NSArray *)cachedVideos {
    return [[TikTokHooks _cachedVideos] copy];
}

@end

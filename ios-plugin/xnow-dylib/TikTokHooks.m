// TikTokHooks.m
// TikTok 运行时方法挂钩完整实现
// 包含: 生命周期监控 + 网络数据拦截 + ViewController 追踪 + 页面状态采集

#import "TikTokHooks.h"
#import "XNOWER.h"
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

@implementation XNOWURLProtocol

+ (void)setDataCollector:(id<XNOWDataCollector>)collector {
    sDataCollector = collector;
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *url = request.URL.absoluteString;

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

#pragma mark - UIViewController Hooks

@interface UIViewController (XNOWER)
@end

@implementation UIViewController (XNOWER)

- (void)xnow_viewDidAppear:(BOOL)animated {
    [self xnow_viewDidAppear:animated];

    // 页面出现时触发浮窗显示（此时 window 一定存在）
    if (self.view.window) {
        [[XNOWER sharedInstance] showFloatingPanelInWindow:self.view.window];
    }

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

    // 检测大幅滑动（翻页）
    static CGFloat lastOffsetY = 0;
    CGFloat diff = fabs(contentOffset.y - lastOffsetY);
    if (diff > self.bounds.size.height * 0.3) {
        XNOW_LOG(@"Scroll page: offset %.0f -> %.0f", lastOffsetY, contentOffset.y);
    }
    lastOffsetY = contentOffset.y;
}

@end

#pragma mark - 数据采集器实现

@interface TikTokHooks () <XNOWDataCollector>
@end

@implementation TikTokHooks

static TikTokHooks *gHooksInstance = nil;

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

        // 6. 初始化数据采集器
        gHooksInstance = [[TikTokHooks alloc] init];
        [XNOWURLProtocol setDataCollector:gHooksInstance];
        XNOW_LOG(@"  [OK] 数据采集器就绪");

        XNOW_LOG(@"===================================");
        XNOW_LOG(@"XNOWER 所有 Hooks 安装完成");
        XNOW_LOG(@"===================================");
    });
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

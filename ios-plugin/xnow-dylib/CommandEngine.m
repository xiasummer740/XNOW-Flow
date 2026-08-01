// CommandEngine.m
// XNOW 指令执行引擎完整实现
// 通过 UITouch/UIEvent 真实模拟用户操作 + 视图层级遍历 + 网络数据采集

#import "CommandEngine.h"
#import "AccountManager.h"
#import "XNWindowHelper.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma mark - 常量

// TikTok 已知的 accessibility identifiers（不同版本可能不同，这里是常见值）
static NSString *const kAccLike = @"like";
static NSString *const kAccFollow = @"follow";
static NSString *const kAccComment = @"comment";
static NSString *const kAccShare = @"share";
static NSString *const kAccProfileAvatar = @"avatar";
static NSString *const kAccSend = @"send";
static NSString *const kAccPost = @"post";
static NSString *const kAccTextField = @"text_input";

// 默认坐标（以 iPhone 8 Plus 414x736 为基准，按比例缩放）
static const CGFloat kLikeBtnRatioX = 0.91;    // 屏幕右侧
static const CGFloat kLikeBtnRatioY = 0.45;
static const CGFloat kFollowBtnRatioX = 0.91;
static const CGFloat kFollowBtnRatioY = 0.35;
static const CGFloat kAvatarRatioX = 0.08;
static const CGFloat kAvatarRatioY = 0.82;

@interface CommandEngine ()
@property (nonatomic, strong) dispatch_queue_t execQueue;
@property (nonatomic, strong) NSMutableDictionary *collectedFans;
@property (nonatomic, strong) NSMutableDictionary *collectedVideos;
@property (nonatomic, assign) BOOL isCollectingData;
@end

@implementation CommandEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        _execQueue = dispatch_queue_create("com.xnow.command", DISPATCH_QUEUE_SERIAL);
        _currentPage = @"unknown";
        _collectedFans = [NSMutableDictionary dictionary];
        _collectedVideos = [NSMutableDictionary dictionary];
    }
    return self;
}

- (CommandAction)actionFromString:(NSString *)actionString {
    static NSDictionary *map = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = @{
            @"scroll_down":      @(CommandActionScrollDown),
            @"scroll_up":        @(CommandActionScrollUp),
            @"like":             @(CommandActionLike),
            @"follow":           @(CommandActionFollow),
            @"comment":          @(CommandActionComment),
            @"collect":          @(CommandActionCollect),
            @"screenshot":       @(CommandActionScreenshot),
            @"open_profile":     @(CommandActionOpenProfile),
            @"collect_fans":     @(CommandActionCollectFans),
            @"collect_videos":   @(CommandActionCollectVideos),
            @"batch_like":       @(CommandActionBatchLike),
            @"batch_follow":     @(CommandActionBatchFollow),
            @"batch_comment":    @(CommandActionBatchComment),
            // 账号管理
            @"get_account_info":  @(CommandActionGetAccountInfo),
            @"switch_account":    @(CommandActionSwitchAccount),
            @"report_account":    @(CommandActionReportAccount),
            // 智能任务
            @"smart_browse":      @(CommandActionSmartBrowse),
            @"check_health":      @(CommandActionCheckHealth),
            // 导航
            @"go_back":           @(CommandActionGoBack),
            @"go_home":           @(CommandActionGoHome),
            @"open_tab":          @(CommandActionOpenTab),
            @"open_search":       @(CommandActionOpenSearch),
            @"search_keyword":    @(CommandActionSearchKeyword),
            @"open_user":         @(CommandActionOpenUser),
            @"open_video":        @(CommandActionOpenVideo),
            // 视频操作
            @"refresh":           @(CommandActionRefresh),
            @"share":             @(CommandActionShare),
            @"save_video":        @(CommandActionSaveVideo),
            // 账号
            @"logout":            @(CommandActionLogout),
        };
    });
    NSNumber *val = map[actionString.lowercaseString];
    return val ? (CommandAction)[val integerValue] : CommandActionUnknown;
}

- (void)executeCommand:(NSDictionary *)command completion:(CommandCompletion)completion {
    NSString *actionStr = command[@"action"] ?: @"";
    NSDictionary *params = command[@"params"] ?: @{};
    CommandAction action = [self actionFromString:actionStr];

    dispatch_async(_execQueue, ^{
        NSDictionary *result = [self _executeAction:action params:params actionName:actionStr];
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(result);
            });
        }
    });
}

// ======== 指令派发 ========

- (NSDictionary *)_executeAction:(CommandAction)action
                          params:(NSDictionary *)params
                      actionName:(NSString *)actionName {
    NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];
    __block NSDictionary *result = nil;
    __block BOOL hasResult = NO;

    @try {
        switch (action) {
            case CommandActionScrollDown:
                [self _performSwipeUp]; // 上滑 = 下一个视频
                break;
            case CommandActionScrollUp:
                [self _performSwipeDown]; // 下滑 = 上一个视频
                break;

            case CommandActionLike:
                [self _performLike];
                break;

            case CommandActionFollow:
                [self _performFollow];
                break;

            case CommandActionComment: {
                NSString *text = params[@"text"] ?: @"Nice!";
                [self _performComment:text];
                break;
            }

            case CommandActionCollect:
                [self _performCollect];
                break;

            case CommandActionScreenshot:
                [self _performScreenshot];
                break;

            case CommandActionOpenProfile: {
                NSString *username = params[@"username"] ?: @"";
                [self _performOpenProfile:username];
                break;
            }

            case CommandActionCollectFans: {
                int count = [params[@"count"] intValue] ?: 20;
                result = [self _performCollectFans:count];
                hasResult = YES;
                break;
            }

            case CommandActionCollectVideos: {
                int count = [params[@"count"] intValue] ?: 10;
                result = [self _performCollectVideos:count];
                hasResult = YES;
                break;
            }

            case CommandActionBatchLike:
                [self _performBatchLike:params];
                break;
            case CommandActionBatchFollow:
                [self _performBatchFollow:params];
                break;
            case CommandActionBatchComment:
                [self _performBatchComment:params];
                break;

            // === 账号管理 ===
            case CommandActionGetAccountInfo: {
                result = [[AccountManager sharedManager] currentAccount] ?: @{};
                hasResult = YES;
                break;
            }
            case CommandActionSwitchAccount: {
                NSString *targetId = params[@"aweme_id"] ?: @"";
                // 切换账号: 打开设置 → 退出登录 → 登录其他账号
                [self _performSwitchAccount:targetId];
                break;
            }
            case CommandActionReportAccount: {
                [[AccountManager sharedManager] reportCurrentAccount];
                break;
            }

            // === 智能任务 ===
            case CommandActionSmartBrowse: {
                int minScrolls = [params[@"min_scrolls"] intValue] ?: 5;
                int maxScrolls = [params[@"max_scrolls"] intValue] ?: 15;
                int minDelay = [params[@"min_delay"] intValue] ?: 3;
                int maxDelay = [params[@"max_delay"] intValue] ?: 8;
                result = [self _performSmartBrowse:minScrolls max:maxScrolls minDelay:minDelay maxDelay:maxDelay];
                hasResult = YES;
                break;
            }
            case CommandActionCheckHealth: {
                result = [self _performCheckHealth];
                hasResult = YES;
                break;
            }

            // === 导航 ===
            case CommandActionGoBack:
                [self _performGoBack];
                break;
            case CommandActionGoHome:
                [self _tapTab:@"home"];
                break;
            case CommandActionOpenTab: {
                NSString *tab = params[@"tab"] ?: @"home";
                [self _tapTab:tab];
                break;
            }
            case CommandActionOpenSearch:
                [self _performOpenSearch];
                break;
            case CommandActionSearchKeyword: {
                NSString *keyword = params[@"keyword"] ?: @"";
                [self _performSearchKeyword:keyword];
                break;
            }
            case CommandActionOpenUser: {
                NSString *uid = params[@"uid"] ?: params[@"unique_id"] ?: @"";
                [self _performOpenUser:uid];
                break;
            }
            case CommandActionOpenVideo: {
                NSString *awemeId = params[@"aweme_id"] ?: @"";
                [self _performOpenVideo:awemeId];
                break;
            }

            // === 视频操作 ===
            case CommandActionRefresh:
                [self _performPullToRefresh];
                break;
            case CommandActionShare:
                [self _performShare];
                break;
            case CommandActionSaveVideo:
                [self _performSaveVideo];
                break;

            // === 账号 ===
            case CommandActionLogout:
                [self _performLogout];
                break;

            default:
                break;
        }

        NSTimeInterval elapsed = [[NSDate date] timeIntervalSince1970] - startTime;

        if (hasResult && result) {
            NSMutableDictionary *mutable = [result mutableCopy];
            mutable[@"action"] = actionName;
            mutable[@"duration"] = @((int)elapsed);
            return mutable;
        }

        return @{
            @"action": actionName,
            @"status": @"success",
            @"message": [NSString stringWithFormat:@"OK: %@", actionName],
            @"duration": @((int)elapsed),
        };
    } @catch (NSException *e) {
        return @{
            @"action": actionName,
            @"status": @"failed",
            @"message": [NSString stringWithFormat:@"%@: %@", e.name, e.reason],
            @"duration": @((int)([[NSDate date] timeIntervalSince1970] - startTime)),
        };
    }
}

#pragma mark - 滑动手势（安全版，避免私有API崩溃）

/// 通过 UIScrollView setContentOffset 实现安全滑动
- (void)_safeScrollBy:(CGFloat)deltaY {
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        if (!window) return;

        // 找到主要 UIScrollView（TikTok 的 feed 页）
        __block UIScrollView *feedScroll = nil;
        [self _findFeedScrollViewInView:window result:&feedScroll];
        if (feedScroll) {
            CGPoint offset = feedScroll.contentOffset;
            offset.y = MAX(0, offset.y + deltaY);
            [feedScroll setContentOffset:offset animated:YES];
            NSLog(@"[XNOWER] ScrollView 滑动 %.0fpt", deltaY);
        } else {
            // 回退：发 UIScrollView 通知
            [[NSNotificationCenter defaultCenter] postNotificationName:@"XNOWER_ScrollRequest"
                                                                object:nil
                                                              userInfo:@{@"delta": @(deltaY)}];
            NSLog(@"[XNOWER] 未找到 ScrollView，发送通知");
        }
    });
}

/// 递归查找主要 UIScrollView
- (void)_findFeedScrollViewInView:(UIView *)view result:(UIScrollView **)result {
    if (*result) return;
    if ([view isKindOfClass:[UIScrollView class]]) {
        UIScrollView *sv = (UIScrollView *)view;
        // 找比较大的 ScrollView（全屏级别），排除小的
        if (sv.frame.size.width >= [UIScreen mainScreen].bounds.size.width * 0.8 &&
            sv.frame.size.height >= [UIScreen mainScreen].bounds.size.height * 0.5) {
            *result = sv;
            return;
        }
    }
    for (UIView *sub in view.subviews) {
        [self _findFeedScrollViewInView:sub result:result];
        if (*result) return;
    }
}

/// 上滑（下一个视频）
- (void)_performSwipeUp {
    [self _safeScrollBy:-[UIScreen mainScreen].bounds.size.height * 0.6];
}

/// 下滑（上一个视频）
- (void)_performSwipeDown {
    [self _safeScrollBy:[UIScreen mainScreen].bounds.size.height * 0.6];
}

/// 安全模拟点击（通过 sendActionsForControlEvents 或直接调用）
- (void)_safeTapAtPoint:(CGPoint)point {
    UIWindow *window = XN_ActiveWindow();
    if (!window) return;
    UIView *targetView = [window hitTest:point withEvent:nil];
    if (!targetView) return;

    @try {
        // 对于 UIControl，直接触发 action
        if ([targetView isKindOfClass:[UIControl class]]) {
            [(UIControl *)targetView sendActionsForControlEvents:UIControlEventTouchUpInside];
        } else {
            // 对于普通 UIView，通过响应链传递
            [targetView touchesBegan:[NSSet set] withEvent:nil];
            [targetView touchesEnded:[NSSet set] withEvent:nil];
        }
        NSLog(@"[XNOWER] 点击 (%.0f, %.0f) 完成", point.x, point.y);
    } @catch (NSException *e) {
        NSLog(@"[XNOWER] 点击失败: %@", e.reason);
    }
}

#pragma mark - 点赞

- (void)_performLike {
    dispatch_sync(dispatch_get_main_queue(), ^{
        // 1. 通过 accessibility identifier 找点赞按钮
        UIView *likeView = [self _findViewWithAccessibilityIdentifier:kAccLike
                                                               inView:XN_ActiveWindow()];
        if (likeView) {
            CGPoint center = [likeView.superview convertPoint:likeView.center toView:nil];
            [self _safeTapAtPoint:center];
            return;
        }

        // 2. 通过 accessibility label
        UIButton *likeBtn = [self _findButtonWithAnyLabel:@[@"like", @"Like", @"heart", @"Heart"]
                                                   inView:XN_ActiveWindow()];
        if (likeBtn) {
            CGPoint center = [likeBtn.superview convertPoint:likeBtn.center toView:nil];
            [self _safeTapAtPoint:center];
            return;
        }

        // 3. 坐标回退
        CGSize screen = [UIScreen mainScreen].bounds.size;
        [self _safeTapAtPoint:CGPointMake(
            screen.width * kLikeBtnRatioX,
            screen.height * kLikeBtnRatioY)];
    });
}

#pragma mark - 关注

- (void)_performFollow {
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *btn = [self _findButtonWithAnyLabel:@[@"follow", @"Follow", @"+"]
                                               inView:XN_ActiveWindow()];
        if (btn) {
            [self _safeTapAtPoint:[btn.superview convertPoint:btn.center toView:nil]];
            return;
        }
        CGSize screen = [UIScreen mainScreen].bounds.size;
        [self _safeTapAtPoint:CGPointMake(
            screen.width * kFollowBtnRatioX,
            screen.height * kFollowBtnRatioY)];
    });
}

#pragma mark - 评论

- (void)_performComment:(NSString *)text {
    // Step 1: 打开评论面板
    dispatch_sync(dispatch_get_main_queue(), ^{
        // 找评论按钮
        UIView *commentView = [self _findViewWithAccessibilityIdentifier:kAccComment
                                                                  inView:XN_ActiveWindow()];
        if (commentView) {
            [self _safeTapAtPoint:[commentView.superview convertPoint:commentView.center toView:nil]];
        } else {
            CGSize screen = [UIScreen mainScreen].bounds.size;
            [self _safeTapAtPoint:CGPointMake(screen.width * 0.5, screen.height * 0.15)];
        }
    });

    // Step 2: 等待评论面板出现，填入文本
    [NSThread sleepForTimeInterval:1.5];

    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();

        // 找到输入框
        UITextField *textField = [self _findTextFieldInView:window];
        UITextView *textView = [self _findTextViewInView:window];

        if (textField) {
            textField.text = text;
            [textField sendActionsForControlEvents:UIControlEventEditingChanged];
            [[NSNotificationCenter defaultCenter]
             postNotificationName:UITextFieldTextDidChangeNotification object:textField];
        } else if (textView) {
            textView.text = text;
            [[NSNotificationCenter defaultCenter]
             postNotificationName:UITextViewTextDidChangeNotification object:textView];
        }
    });

    // Step 3: 发送评论
    [NSThread sleepForTimeInterval:0.8];
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIView *sendBtn = [self _findViewWithAccessibilityIdentifier:kAccSend
                                                              inView:XN_ActiveWindow()];
        if (!sendBtn) {
            sendBtn = [self _findViewWithAccessibilityIdentifier:kAccPost
                                                          inView:XN_ActiveWindow()];
        }
        if (sendBtn) {
            [self _safeTapAtPoint:[sendBtn.superview convertPoint:sendBtn.center toView:nil]];
        } else {
            // 尝试找到底部工具栏的发发送按钮
            UIButton *btn = [self _findButtonWithAnyLabel:@[@"send", @"Send", @"Post",
                                                             @"发送", @"发布"]
                                                   inView:XN_ActiveWindow()];
            if (btn) {
                [self _safeTapAtPoint:[btn.superview convertPoint:btn.center toView:nil]];
            }
        }
    });
}

#pragma mark - 收藏

- (void)_performCollect {
    dispatch_sync(dispatch_get_main_queue(), ^{
        // TikTok 收藏按钮通常在分享面板里，模拟点击收藏
        UIView *collectView = [self _findViewWithAccessibilityIdentifier:kAccShare
                                                                  inView:XN_ActiveWindow()];
        if (collectView) {
            // 先点分享
            [self _safeTapAtPoint:[collectView.superview convertPoint:collectView.center toView:nil]];
        } else {
            // 直接搜索 "save" 或 "bookmark"
            UIButton *btn = [self _findButtonWithAnyLabel:@[@"save", @"Save", @"bookmark",
                                                             @"收藏", @"Add to Favorites"]
                                                   inView:XN_ActiveWindow()];
            if (btn) {
                [self _safeTapAtPoint:[btn.superview convertPoint:btn.center toView:nil]];
            }
        }
    });
}

#pragma mark - 截图

- (void)_performScreenshot {
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        if (!window) return;

        // 截图前先隐藏 overlay（如果有）
        UIGraphicsBeginImageContextWithOptions(window.bounds.size, NO, [[UIScreen mainScreen] scale]);
        [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:NO];
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();

        if (image) {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil);
        }
    });
}

#pragma mark - 打开个人主页

- (void)_performOpenProfile:(NSString *)username {
    dispatch_sync(dispatch_get_main_queue(), ^{
        if (username.length > 0) {
            // TikTok URL scheme 直接打开用户主页
            NSString *urlStr = [NSString stringWithFormat:@"snssdk1233://user/%@", username];
            NSURL *url = [NSURL URLWithString:urlStr];
            if (url && [[UIApplication sharedApplication] canOpenURL:url]) {
                [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
                return;
            }
        }

        // 回退：点击当前视频创作者头像
        UIView *avatarView = [self _findViewWithAccessibilityIdentifier:kAccProfileAvatar
                                                                 inView:XN_ActiveWindow()];
        if (avatarView) {
            [self _safeTapAtPoint:[avatarView.superview convertPoint:avatarView.center toView:nil]];
        } else {
            CGSize screen = [UIScreen mainScreen].bounds.size;
            [self _safeTapAtPoint:CGPointMake(
                screen.width * kAvatarRatioX,
                screen.height * kAvatarRatioY)];
        }
    });
}

#pragma mark - 粉丝/视频数据采集（网络拦截方案）

- (NSDictionary *)_performCollectFans:(int)count {
    __block NSMutableArray *fans = [NSMutableArray array];
    __block BOOL done = NO;

    dispatch_sync(dispatch_get_main_queue(), ^{
        // 1. 打开当前用户的个人主页（点头像）
        [self _performOpenProfile:@""];
    });

    [NSThread sleepForTimeInterval:3.0];

    // 2. 点击粉丝列表按钮
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *fansBtn = [self _findButtonWithAnyLabel:@[@"fans", @"Fans", @"followers",
                                                             @"粉丝", @"Followers"]
                                                   inView:XN_ActiveWindow()];
        if (fansBtn) {
            [self _safeTapAtPoint:[fansBtn.superview convertPoint:fansBtn.center toView:nil]];
        }
    });

    [NSThread sleepForTimeInterval:2.0];

    // 3. 滚动采集粉丝列表
    int collected = 0;
    int emptyScrolls = 0;
    while (collected < count && emptyScrolls < 5) {
        // 通过 accessibility 采集当前可见的粉丝条目
        [self _collectVisibleFans:fans limit:count];
        int before = (int)fans.count;

        // 下滑加载更多
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self _performSwipeUp];
        });
        [NSThread sleepForTimeInterval:1.5];

        if (fans.count == before) {
            emptyScrolls++;
        } else {
            emptyScrolls = 0;
        }
        collected = (int)fans.count;
    }

    return @{
        @"status": @"success",
        @"message": [NSString stringWithFormat:@"采集粉丝 %lu 人", (unsigned long)fans.count],
        @"data": fans,
        @"count": @(fans.count),
    };
}

- (NSDictionary *)_performCollectVideos:(int)count {
    __block NSMutableArray *videos = [NSMutableArray array];
    __block BOOL done = NO;

    dispatch_sync(dispatch_get_main_queue(), ^{
        [self _performOpenProfile:@""];
    });
    [NSThread sleepForTimeInterval:3.0];

    // 点击视频列表 tab
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *videoBtn = [self _findButtonWithAnyLabel:@[@"video", @"Video", @"作品",
                                                              @"post", @"Post"]
                                                    inView:XN_ActiveWindow()];
        if (videoBtn) {
            [self _safeTapAtPoint:[videoBtn.superview convertPoint:videoBtn.center toView:nil]];
        }
    });
    [NSThread sleepForTimeInterval:1.5];

    // 滚动采集
    int collected = 0;
    int emptyScrolls = 0;
    while (collected < count && emptyScrolls < 5) {
        [self _collectVisibleVideos:videos limit:count];
        int before = (int)videos.count;

        dispatch_sync(dispatch_get_main_queue(), ^{
            [self _performSwipeUp];
        });
        [NSThread sleepForTimeInterval:1.5];

        if (videos.count == before) emptyScrolls++;
        else emptyScrolls = 0;
        collected = (int)videos.count;
    }

    return @{
        @"status": @"success",
        @"message": [NSString stringWithFormat:@"采集视频 %lu 条", (unsigned long)videos.count],
        @"data": videos,
        @"count": @(videos.count),
    };
}

/// 从当前可见视图采集粉丝数据
- (void)_collectVisibleFans:(NSMutableArray *)fans limit:(int)limit {
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        [self _enumerateLabelsInView:window block:^(NSString *text, UIView *view) {
            if (fans.count >= limit) return;
            // 检测用户名的启发式规则：2-30字符，不含特殊符号
            if (text.length >= 2 && text.length <= 30) {
                if (![fans containsObject:text]) {
                    [fans addObject:text];
                }
            }
        }];
    });
}

/// 从当前可见视图采集视频描述数据
- (void)_collectVisibleVideos:(NSMutableArray *)videos limit:(int)limit {
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        [self _enumerateLabelsInView:window block:^(NSString *text, UIView *view) {
            if (videos.count >= limit) return;
            if (text.length >= 5 && text.length <= 100) {
                if (![videos containsObject:text]) {
                    [videos addObject:text];
                }
            }
        }];
    });
}

#pragma mark - 批量操作

- (void)_performBatchLike:(NSDictionary *)params {
    int count = [params[@"count"] intValue] ?: 5;
    int interval = [params[@"interval"] intValue] ?: 2;
    if (interval < 1) interval = 1;

    for (int i = 0; i < count; i++) {
        [self _performLike];
        [NSThread sleepForTimeInterval:1.0];
        [self _performSwipeUp];
        [NSThread sleepForTimeInterval:interval];
    }
}

- (void)_performBatchFollow:(NSDictionary *)params {
    int count = [params[@"count"] intValue] ?: 5;
    int interval = [params[@"interval"] intValue] ?: 3;
    if (interval < 2) interval = 2;

    for (int i = 0; i < count; i++) {
        [self _performFollow];
        [NSThread sleepForTimeInterval:1.0];
        [self _performSwipeUp];
        [NSThread sleepForTimeInterval:interval];
    }
}

- (void)_performBatchComment:(NSDictionary *)params {
    int count = [params[@"count"] intValue] ?: 5;
    NSString *text = params[@"text"] ?: @"Nice!";
    int interval = [params[@"interval"] intValue] ?: 5;
    if (interval < 3) interval = 3;

    for (int i = 0; i < count; i++) {
        [self _performComment:text];
        [NSThread sleepForTimeInterval:2.0];
        // 关闭评论面板
        [self _performSwipeDown];
        [NSThread sleepForTimeInterval:1.0];
        [self _performSwipeUp]; // 切到下一个视频
        [NSThread sleepForTimeInterval:interval];
    }
}

#pragma mark - 视图辅助方法

/// 通过 accessibilityIdentifier 找视图
- (UIView *)_findViewWithAccessibilityIdentifier:(NSString *)identifier inView:(UIView *)view {
    if ([view.accessibilityIdentifier.lowercaseString isEqualToString:identifier.lowercaseString]) {
        return view;
    }
    for (UIView *subview in view.subviews) {
        UIView *result = [self _findViewWithAccessibilityIdentifier:identifier inView:subview];
        if (result) return result;
    }
    return nil;
}

/// 通过 accessibility label 找按钮
- (UIButton *)_findButtonWithAnyLabel:(NSArray<NSString *> *)labels inView:(UIView *)view {
    if ([view isKindOfClass:[UIButton class]]) {
        UIButton *btn = (UIButton *)view;
        NSString *accLabel = btn.accessibilityLabel;
        NSString *accId = btn.accessibilityIdentifier;
        NSString *title = [btn titleForState:UIControlStateNormal];

        for (NSString *label in labels) {
            NSString *lowerLabel = label.lowercaseString;
            if ([accLabel.lowercaseString isEqualToString:lowerLabel] ||
                [accLabel.lowercaseString containsString:lowerLabel] ||
                [accId.lowercaseString containsString:lowerLabel] ||
                [title.lowercaseString containsString:lowerLabel]) {
                return btn;
            }
        }
    }
    for (UIView *subview in view.subviews) {
        UIButton *result = [self _findButtonWithAnyLabel:labels inView:subview];
        if (result) return result;
    }
    return nil;
}

- (UITextField *)_findTextFieldInView:(UIView *)view {
    if ([view isKindOfClass:[UITextField class]]) {
        UITextField *tf = (UITextField *)view;
        if (tf.isEnabled && !tf.isHidden) return tf;
    }
    for (UIView *subview in view.subviews) {
        UITextField *result = [self _findTextFieldInView:subview];
        if (result) return result;
    }
    return nil;
}

- (UITextView *)_findTextViewInView:(UIView *)view {
    if ([view isKindOfClass:[UITextView class]]) {
        UITextView *tv = (UITextView *)view;
        if (!tv.isHidden) return tv;
    }
    for (UIView *subview in view.subviews) {
        UITextView *result = [self _findTextViewInView:subview];
        if (result) return result;
    }
    return nil;
}

/// 枚举视图中的所有 UILabel 文本
- (void)_enumerateLabelsInView:(UIView *)view
                         block:(void(^)(NSString *text, UIView *view))block {
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        if (label.text.length > 0 && !label.hidden && label.alpha > 0.1) {
            block(label.text, label);
        }
    }
    for (UIView *subview in view.subviews) {
        [self _enumerateLabelsInView:subview block:block];
    }
}

#pragma mark - 账号管理

/// 切换账号: 导航到设置 → 退出 → 登录页
- (void)_performSwitchAccount:(NSString *)targetAwemeId {
    dispatch_sync(dispatch_get_main_queue(), ^{
        CGSize screen = [UIScreen mainScreen].bounds.size;

        // Step 1: 进入个人主页（点右下角 "我" 或 点头像）
        [self _navigateToProfile];
    });
    [NSThread sleepForTimeInterval:2.0];

    dispatch_sync(dispatch_get_main_queue(), ^{
        // Step 2: 打开设置（右上角三个点或设置图标）
        [self _tapTopRightCorner];
    });
    [NSThread sleepForTimeInterval:1.5];

    dispatch_sync(dispatch_get_main_queue(), ^{
        // Step 3: 找 "设置" 按钮
        UIButton *settingsBtn = [self _findButtonWithAnyLabel:@[@"Settings", @"设置", @"settings"]
                                                       inView:XN_ActiveWindow()];
        if (settingsBtn) {
            [self _safeTapAtPoint:[settingsBtn.superview convertPoint:settingsBtn.center toView:nil]];
        }
    });
    [NSThread sleepForTimeInterval:1.5];

    dispatch_sync(dispatch_get_main_queue(), ^{
        // Step 4: 滑动到底部找 "退出登录"
        // 需要滑到设置页底部
        CGSize screen = [UIScreen mainScreen].bounds.size;
        for (int i = 0; i < 5; i++) {
            [self _safeScrollBy:-screen.height * 0.4];
            [NSThread sleepForTimeInterval:0.3];
        }
    });
    [NSThread sleepForTimeInterval:0.5];

    dispatch_sync(dispatch_get_main_queue(), ^{
        // Step 5: 找 "退出登录" / "Log out" 按钮
        UIButton *logoutBtn = [self _findButtonWithAnyLabel:@[@"Log out", @"退出登录", @"log out", @"Log Out"]
                                                     inView:XN_ActiveWindow()];
        if (logoutBtn) {
            [self _safeTapAtPoint:[logoutBtn.superview convertPoint:logoutBtn.center toView:nil]];
        }
    });
    [NSThread sleepForTimeInterval:1.0];

    // Step 6: 确认退出
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *confirmBtn = [self _findButtonWithAnyLabel:@[@"Log out", @"退出", @"Confirm", @"确认"]
                                                     inView:XN_ActiveWindow()];
        if (confirmBtn) {
            [self _safeTapAtPoint:[confirmBtn.superview convertPoint:confirmBtn.center toView:nil]];
        }
    });
    [NSThread sleepForTimeInterval:2.0];

    // 清除当前账号缓存
    [[AccountManager sharedManager] clearAccount];
}

/// 导航到个人主页
- (void)_navigateToProfile {
    CGSize screen = [UIScreen mainScreen].bounds.size;
    // 点底部 "我" tab（通常在右下角）
    CGFloat tabY = screen.height - 50;
    CGFloat profileTabX = screen.width * 0.88;
    [self _safeTapAtPoint:CGPointMake(profileTabX, tabY)];
}

/// 点右上角
- (void)_tapTopRightCorner {
    CGSize screen = [UIScreen mainScreen].bounds.size;
    [self _safeTapAtPoint:CGPointMake(screen.width - 30, 60)];
}

#pragma mark - 智能任务

/// 模拟真人浏览: 随机滑动 + 随机停留 + 随机点赞/关注
- (NSDictionary *)_performSmartBrowse:(int)minScrolls max:(int)maxScrolls
                             minDelay:(int)minDelay maxDelay:(int)maxDelay {
    int scrollCount = minScrolls + arc4random_uniform(maxScrolls - minScrolls + 1);
    __block int likes = 0;
    __block int follows = 0;

    for (int i = 0; i < scrollCount; i++) {
        // 随机观看时间
        int watchTime = minDelay + arc4random_uniform(maxDelay - minDelay + 1);
        [NSThread sleepForTimeInterval:watchTime];

        dispatch_sync(dispatch_get_main_queue(), ^{
            // 20% 概率点赞
            if (arc4random_uniform(100) < 20) {
                [self _performLike];
                likes++;
                [NSThread sleepForTimeInterval:0.5];
            }

            // 8% 概率关注
            if (arc4random_uniform(100) < 8) {
                [self _performFollow];
                follows++;
                [NSThread sleepForTimeInterval:0.5];
            }

            // 上滑到下一个视频
            [self _performSwipeUp];
        });

        // 滑动后短延迟
        [NSThread sleepForTimeInterval:0.3];
    }

    int totalDuration = scrollCount * (minDelay + maxDelay) / 2;
    return @{
        @"status": @"success",
        @"scrolls": @(scrollCount),
        @"likes": @(likes),
        @"follows": @(follows),
        @"duration": @(totalDuration),
    };
}

/// 检测账号健康状态
- (NSDictionary *)_performCheckHealth {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"status"] = @"active";
    result[@"health_score"] = @(100);
    result[@"issues"] = @[];

    // 检查是否存在风控弹窗
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        if (!window) return;

        // 找 "被封禁/限制/异常" 相关文本
        __block BOOL hasRestriction = NO;
        [self _enumerateLabelsInView:window block:^(NSString *text, UIView *view) {
            if (hasRestriction) return;
            NSArray *riskKeywords = @[@"restricted", @"suspended", @"blocked", @"违规",
                                       @"封禁", @"限制", @"异常", @"暂时"];
            for (NSString *kw in riskKeywords) {
                if ([text.lowercaseString containsString:kw.lowercaseString]) {
                    hasRestriction = YES;
                    result[@"status"] = @"risk_control";
                    result[@"health_score"] = @(50);
                    result[@"issues"] = @[text];
                    break;
                }
            }
        }];

        // 找 "登录" 按钮（未登录状态）
        UIButton *loginBtn = [self _findButtonWithAnyLabel:@[@"Log in", @"登录", @"Sign up"]
                                                    inView:window];
        if (loginBtn && !hasRestriction) {
            result[@"status"] = @"offline";
            result[@"health_score"] = @(0);
        }
    });

    // 从 AccountManager 获取缓存账号状态
    NSDictionary *account = [AccountManager sharedManager].currentAccount;
    if (account[@"health_score"]) {
        result[@"health_score"] = account[@"health_score"];
    }
    if (account[@"status"]) {
        result[@"status"] = account[@"status"];
    }

    return result;
}

#pragma mark - 导航 (Phase 3)

/// 返回上一页（左边缘右滑或点返回按钮）
- (void)_performGoBack {
    dispatch_sync(dispatch_get_main_queue(), ^{
        // 找返回按钮
        UIButton *backBtn = [self _findButtonWithAnyLabel:@[@"Back", @"back", @"返回", @"‹", @"chevron"]
                                                   inView:XN_ActiveWindow()];
        if (backBtn) {
            [self _safeTapAtPoint:[backBtn.superview convertPoint:backBtn.center toView:nil]];
            return;
        }
        // 回退：左边缘右滑手势
        CGSize screen = [UIScreen mainScreen].bounds.size;
        CGPoint from = CGPointMake(5, screen.height * 0.5);
        CGPoint to = CGPointMake(screen.width * 0.6, screen.height * 0.5);
        [self _simulateSwipeFrom:from to:to];
    });
}

/// 点击底部 Tab（home/discover/inbox/profile）
- (void)_tapTab:(NSString *)tab {
    dispatch_sync(dispatch_get_main_queue(), ^{
        CGSize screen = [UIScreen mainScreen].bounds.size;
        CGFloat tabY = screen.height - 40;
        CGFloat ratioX;
        if ([tab isEqualToString:@"discover"]) ratioX = 0.35;
        else if ([tab isEqualToString:@"inbox"]) ratioX = 0.62;
        else if ([tab isEqualToString:@"profile"]) ratioX = 0.88;
        else ratioX = 0.12;  // home 默认
        [self _safeTapAtPoint:CGPointMake(screen.width * ratioX, tabY)];
        self->_currentPage = tab;
    });
}

/// 打开搜索（点右上角搜索图标，或 URL scheme）
- (void)_performOpenSearch {
    dispatch_sync(dispatch_get_main_queue(), ^{
        CGSize screen = [UIScreen mainScreen].bounds.size;
        // 首页右上角搜索图标
        [self _safeTapAtPoint:CGPointMake(screen.width - 30, 65)];
    });
}

/// 搜索关键词（打开搜索 → 输入 → 提交）
- (void)_performSearchKeyword:(NSString *)keyword {
    if (keyword.length == 0) return;
    dispatch_sync(dispatch_get_main_queue(), ^{
        [self _performOpenSearch];
    });
    [NSThread sleepForTimeInterval:1.5];

    dispatch_sync(dispatch_get_main_queue(), ^{
        // 找输入框输入
        UITextField *tf = [self _findTextFieldInView:XN_ActiveWindow()];
        if (tf) {
            [tf becomeFirstResponder];
            tf.text = keyword;
            // 触发搜索提交
            [[NSNotificationCenter defaultCenter] postNotificationName:UITextFieldTextDidChangeNotification object:tf];
            // 找搜索/确认按钮
            UIButton *searchBtn = [self _findButtonWithAnyLabel:@[@"Search", @"search", @"搜索", @"确定", @"Go"]
                                                         inView:XN_ActiveWindow()];
            if (searchBtn) {
                [self _safeTapAtPoint:[searchBtn.superview convertPoint:searchBtn.center toView:nil]];
            } else {
                // 回车提交
                if ([tf canPerformAction:@selector(insertText:) withSender:nil]) {
                    [tf.delegate textFieldShouldReturn:tf];
                }
            }
        }
    });
}

/// 通过 URL scheme 打开用户主页
- (void)_performOpenUser:(NSString *)uid {
    if (uid.length == 0) return;
    NSString *scheme = [NSString stringWithFormat:@"snssdk1233://user/%@", uid];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *url = [NSURL URLWithString:scheme];
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    });
}

/// 通过 URL scheme 打开视频详情
- (void)_performOpenVideo:(NSString *)awemeId {
    if (awemeId.length == 0) return;
    NSString *scheme = [NSString stringWithFormat:@"snssdk1233://aweme/detail/%@", awemeId];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *url = [NSURL URLWithString:scheme];
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    });
}

#pragma mark - 视频操作 (Phase 3)

/// 下拉刷新
- (void)_performPullToRefresh {
    dispatch_sync(dispatch_get_main_queue(), ^{
        CGSize screen = [UIScreen mainScreen].bounds.size;
        CGPoint from = CGPointMake(screen.width * 0.5, screen.height * 0.3);
        CGPoint to = CGPointMake(screen.width * 0.5, screen.height * 0.7);
        [self _simulateSwipeFrom:from to:to];
    });
}

/// 分享当前视频（点分享按钮）
- (void)_performShare {
    dispatch_sync(dispatch_get_main_queue(), ^{
        CGSize screen = [UIScreen mainScreen].bounds.size;
        // 分享按钮通常在右侧下部
        [self _safeTapAtPoint:CGPointMake(screen.width * 0.91, screen.height * 0.55)];
    });
}

/// 保存视频（点分享 → 保存）
- (void)_performSaveVideo {
    dispatch_sync(dispatch_get_main_queue(), ^{
        [self _performShare];
    });
    [NSThread sleepForTimeInterval:1.5];
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *saveBtn = [self _findButtonWithAnyLabel:@[@"Save", @"save", @"保存", @"Download", @"下载"]
                                                   inView:XN_ActiveWindow()];
        if (saveBtn) {
            [self _safeTapAtPoint:[saveBtn.superview convertPoint:saveBtn.center toView:nil]];
        }
    });
}

#pragma mark - 账号 (Phase 3)

/// 退出登录（个人主页 → 设置 → 退出）
- (void)_performLogout {
    // 导航到个人主页
    dispatch_sync(dispatch_get_main_queue(), ^{
        [self _navigateToProfile];
    });
    [NSThread sleepForTimeInterval:2.0];

    // 点右上角设置
    dispatch_sync(dispatch_get_main_queue(), ^{
        [self _tapTopRightCorner];
    });
    [NSThread sleepForTimeInterval:1.5];

    // 找退出登录
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *logoutBtn = [self _findButtonWithAnyLabel:@[@"Log out", @"Log Out", @"退出登录", @"退出", @"Sign out"]
                                                     inView:XN_ActiveWindow()];
        if (logoutBtn) {
            [self _safeTapAtPoint:[logoutBtn.superview convertPoint:logoutBtn.center toView:nil]];
            [NSThread sleepForTimeInterval:1.0];
            // 确认弹窗
            UIButton *confirmBtn = [self _findButtonWithAnyLabel:@[@"Confirm", @"Log out", @"退出", @"确定"]
                                                          inView:XN_ActiveWindow()];
            if (confirmBtn) {
                [self _safeTapAtPoint:[confirmBtn.superview convertPoint:confirmBtn.center toView:nil]];
            }
        }
    });

    // 清除本地账号缓存
    [[AccountManager sharedManager] clearAccount];
}

#pragma mark - 辅助: 手势模拟 / 输入框查找

/// 模拟滑动手势（通过 touchesBegan/Moved/Ended）
- (void)_simulateSwipeFrom:(CGPoint)from to:(CGPoint)to {
    UIWindow *window = XN_ActiveWindow();
    if (!window) return;
    UIView *target = [window hitTest:from withEvent:nil];
    if (!target) return;
    @try {
        [target touchesBegan:[NSSet set] withEvent:nil];
        [target touchesMoved:[NSSet set] withEvent:nil];
        [target touchesEnded:[NSSet set] withEvent:nil];
        // 发滚动通知
        CGFloat deltaY = to.y - from.y;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"XNOWER_ScrollRequest"
                                                            object:nil
                                                          userInfo:@{@"delta": @(deltaY)}];
        NSLog(@"[XNOWER] 模拟滑动 %.0fpt", deltaY);
    } @catch (NSException *e) {
        NSLog(@"[XNOWER] 滑动失败: %@", e.reason);
    }
}

/// 查找输入框
- (UITextField *)_findTextFieldInView:(UIView *)view {
    if ([view isKindOfClass:[UITextField class]]) return (UITextField *)view;
    for (UIView *sub in view.subviews) {
        UITextField *tf = [self _findTextFieldInView:sub];
        if (tf) return tf;
    }
    return nil;
}

@end

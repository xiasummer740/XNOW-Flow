// CommandEngine.m
// XNOW 指令执行引擎完整实现
// 通过 UITouch/UIEvent 真实模拟用户操作 + 视图层级遍历 + 网络数据采集

#import "CommandEngine.h"
#import "AccountManager.h"
#import "XNWindowHelper.h"
#import "XNTouchSimulator.h"
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
            @"collect_comments": @(CommandActionCollectComments),
            @"collect_live_users": @(CommandActionCollectLiveUsers),
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
            // 修改资料
            @"edit_profile":      @(CommandActionEditProfile),
            // 自动发视频
            @"post_video":        @(CommandActionPostVideo),
            // 自动私信
            @"send_dm":           @(CommandActionSendDm),
            @"send_card":         @(CommandActionSendCard),
            @"share_live":        @(CommandActionShareLive),
            // 批量注册 + 自动养号
            @"nurture_tick":      @(CommandActionNurtureTick),
            @"nurture_stop":      @(CommandActionNurtureStop),
            @"register_account":  @(CommandActionRegisterAccount),
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

            case CommandActionCollectComments: {
                int count = [params[@"count"] intValue] ?: 20;
                result = [self _performCollectComments:count];
                hasResult = YES;
                break;
            }

            case CommandActionCollectLiveUsers: {
                int count = [params[@"count"] intValue] ?: 20;
                result = [self _performCollectLiveUsers:count];
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

            // === 修改资料 ===
            case CommandActionEditProfile:
                [self _performEditProfile:params];
                break;

            // === 自动发视频 ===
            case CommandActionPostVideo: {
                result = [self _performPostVideo:params];
                hasResult = YES;
                break;
            }

            // === 自动私信 ===
            case CommandActionSendDm: {
                result = [self _performSendDm:params];
                hasResult = YES;
                break;
            }
            case CommandActionSendCard: {
                result = [self _performSendCard:params];
                hasResult = YES;
                break;
            }
            case CommandActionShareLive: {
                result = [self _performShareLive:params];
                hasResult = YES;
                break;
            }

            // === 批量注册 + 自动养号 ===
            case CommandActionNurtureTick: {
                result = [self _performNurtureTick:params];
                hasResult = YES;
                break;
            }
            case CommandActionNurtureStop: {
                result = [self _performNurtureStop];
                hasResult = YES;
                break;
            }
            case CommandActionRegisterAccount: {
                result = [self _performRegisterAccount:params];
                hasResult = YES;
                break;
            }

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

/// 按 deltaY 转滑动：优先直接翻页 feed UICollectionView，失败再注入真实手势
- (void)_safeScrollBy:(CGFloat)deltaY {
    if ([self _tryPageFeed:deltaY]) return;
    CGSize s = [UIScreen mainScreen].bounds.size;
    CGFloat fromY = s.height * 0.5;
    CGFloat toY = MAX(s.height * 0.1, MIN(s.height * 0.9, fromY + deltaY));
    [XNTouchSimulator swipeFrom:CGPointMake(s.width * 0.5, fromY)
                             to:CGPointMake(s.width * 0.5, toY)];
    NSLog(@"[XNOWER] 真实滑动 delta=%.0fpt", deltaY);
}

/// 尝试直接翻页 feed（TikTok feed 是 UITableView，用 scrollToRowAtIndexPath）
- (BOOL)_tryPageFeed:(CGFloat)deltaY {
    UIWindow *window = XN_ActiveWindow();
    if (!window) return NO;
    __block UIScrollView *feedScroll = nil;
    [self _findLargeFeedScrollViewInView:window result:&feedScroll];
    if (!feedScroll) {
        NSLog(@"[XNOWER] feed 滚动视图未找到");
        return NO;
    }
    NSLog(@"[XNOWER] feed scroll view = %@", NSStringFromClass(feedScroll.class));

    if ([feedScroll isKindOfClass:[UITableView class]]) {
        UITableView *tv = (UITableView *)feedScroll;
        NSIndexPath *current = [tv indexPathsForVisibleRows].firstObject;
        if (!current) return NO;
        NSInteger targetRow = (deltaY < 0) ? current.row + 1 : MAX(0, current.row - 1);
        if (targetRow >= [tv numberOfRowsInSection:current.section]) return NO;
        NSIndexPath *target = [NSIndexPath indexPathForRow:targetRow inSection:current.section];
        [tv scrollToRowAtIndexPath:target atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
        NSLog(@"[XNOWER] feed 表翻页到 row=%ld", (long)targetRow);
        return YES;
    }
    if ([feedScroll isKindOfClass:[UICollectionView class]]) {
        UICollectionView *cv = (UICollectionView *)feedScroll;
        NSIndexPath *current = [cv indexPathsForVisibleItems].firstObject;
        if (!current) return NO;
        NSInteger targetItem = (deltaY < 0) ? current.item + 1 : MAX(0, current.item - 1);
        if (targetItem >= [cv numberOfItemsInSection:current.section]) return NO;
        NSIndexPath *target = [NSIndexPath indexPathForItem:targetItem inSection:current.section];
        [cv scrollToItemAtIndexPath:target atScrollPosition:UICollectionViewScrollPositionCenteredVertically animated:YES];
        NSLog(@"[XNOWER] feed 集合翻页到 item=%ld", (long)targetItem);
        return YES;
    }
    return NO;
}

/// 递归查找大面积 UIScrollView（feed，UITableView 或 UICollectionView）
- (void)_findLargeFeedScrollViewInView:(UIView *)view result:(UIScrollView **)result {
    if (*result) return;
    if ([view isKindOfClass:[UITableView class]] || [view isKindOfClass:[UICollectionView class]]) {
        UIScrollView *sv = (UIScrollView *)view;
        if (sv.frame.size.width >= [UIScreen mainScreen].bounds.size.width * 0.8 &&
            sv.frame.size.height >= [UIScreen mainScreen].bounds.size.height * 0.5) {
            *result = sv;
            return;
        }
    }
    for (UIView *sub in view.subviews) {
        [self _findLargeFeedScrollViewInView:sub result:result];
        if (*result) return;
    }
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

/// 上滑（下一个视频）— 真实手势注入
- (void)_performSwipeUp {
    [XNTouchSimulator swipeUp];
}

/// 下滑（上一个视频）— 真实手势注入
- (void)_performSwipeDown {
    [XNTouchSimulator swipeDown];
}

/// 真实模拟点击（注入 UITouch/UIEvent，让 TikTok 手势识别器真正响应）
- (void)_safeTapAtPoint:(CGPoint)point {
    [XNTouchSimulator tapAtPoint:point];
    NSLog(@"[XNOWER] 点击 (%.0f, %.0f) 完成", point.x, point.y);
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
            // 右侧操作栏评论按钮位置（like下方）
            CGSize screen = [UIScreen mainScreen].bounds.size;
            [self _safeTapAtPoint:CGPointMake(screen.width * 0.91, screen.height * 0.55)];
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

#pragma mark - 评论/直播间用户采集（UI 遍历方案）

/// 采集评论用户：打开评论面板 → 滚动收集评论作者用户名
- (NSDictionary *)_performCollectComments:(int)count {
    __block NSMutableArray *users = [NSMutableArray array];

    // 1. 打开评论面板（点头评按钮）
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIView *commentView = [self _findViewWithAccessibilityIdentifier:kAccComment
                                                                 inView:XN_ActiveWindow()];
        if (commentView) {
            [self _safeTapAtPoint:[commentView.superview convertPoint:commentView.center toView:nil]];
        } else {
            UIButton *btn = [self _findButtonWithAnyLabel:@[@"comment", @"Comment", @"评论"]
                                                   inView:XN_ActiveWindow()];
            if (btn) {
                [self _safeTapAtPoint:[btn.superview convertPoint:btn.center toView:nil]];
            } else {
                CGSize screen = [UIScreen mainScreen].bounds.size;
                [self _safeTapAtPoint:CGPointMake(screen.width * 0.5, screen.height * 0.15)];
            }
        }
    });
    [NSThread sleepForTimeInterval:2.0];

    // 2. 滚动采集评论作者用户名
    int collected = 0;
    int emptyScrolls = 0;
    while (collected < count && emptyScrolls < 5) {
        [self _collectVisibleUsers:users limit:count];
        int before = (int)users.count;

        dispatch_sync(dispatch_get_main_queue(), ^{
            [self _performSwipeUp];
        });
        [NSThread sleepForTimeInterval:1.5];

        if (users.count == before) emptyScrolls++;
        else emptyScrolls = 0;
        collected = (int)users.count;
    }

    // 3. 关闭评论面板
    dispatch_sync(dispatch_get_main_queue(), ^{
        [self _performSwipeDown];
    });

    return @{
        @"status": @"success",
        @"message": [NSString stringWithFormat:@"采集评论用户 %lu 人", (unsigned long)users.count],
        @"source_type": @"comments",
        @"users": users,
        @"count": @(users.count),
    };
}

/// 采集直播间用户：在当前直播页面滚动收集用户名（best-effort）
- (NSDictionary *)_performCollectLiveUsers:(int)count {
    __block NSMutableArray *users = [NSMutableArray array];

    // 直播间页面假设用户已进入；等页面稳定
    [NSThread sleepForTimeInterval:1.0];

    int collected = 0;
    int emptyScrolls = 0;
    while (collected < count && emptyScrolls < 5) {
        [self _collectVisibleUsers:users limit:count];
        int before = (int)users.count;

        dispatch_sync(dispatch_get_main_queue(), ^{
            [self _performSwipeUp];
        });
        [NSThread sleepForTimeInterval:1.5];

        if (users.count == before) emptyScrolls++;
        else emptyScrolls = 0;
        collected = (int)users.count;
    }

    return @{
        @"status": @"success",
        @"message": [NSString stringWithFormat:@"采集直播间用户 %lu 人", (unsigned long)users.count],
        @"source_type": @"live_users",
        @"users": users,
        @"count": @(users.count),
    };
}

/// 从当前可见视图采集疑似用户名文本（去重）
- (void)_collectVisibleUsers:(NSMutableArray *)users limit:(int)limit {
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        [self _enumerateLabelsInView:window block:^(NSString *text, UIView *view) {
            if (users.count >= limit) return;
            if ([self _looksLikeUsername:text] && ![users containsObject:text]) {
                [users addObject:text];
            }
        }];
    });
}

/// 判断文本是否像用户名（昵称/评论作者），排除纯数字与常见 UI 文本
- (BOOL)_looksLikeUsername:(NSString *)text {
    if (text.length < 2 || text.length > 30) return NO;
    // 排除纯数字（评论数/点赞数等）
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([text rangeOfCharacterFromSet:nonDigits].location == NSNotFound) return NO;
    // 排除含空格的文本（评论内容通常含空格/标点）
    if ([text rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]].location != NSNotFound) return NO;
    // 排除常见 UI 文本
    NSArray *excludes = @[@"回复", @"点赞", @"评论", @"关注", @"粉丝", @"更多", @"复制", @"举报",
                          @"取消", @"分享", @"收藏", @"分享到", @"加载中",
                          @"reply", @"replies", @"likes", @"comment", @"comments",
                          @"cancel", @"share", @"loading"];
    for (NSString *kw in excludes) {
        if ([text.lowercaseString isEqualToString:kw.lowercaseString]) return NO;
    }
    return YES;
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

/// 枚举视图中的所有可用输入框（用于注册流程中找密码框等）
- (void)_enumerateTextFieldsInView:(UIView *)view
                             block:(void(^)(UITextField *tf))block {
    if ([view isKindOfClass:[UITextField class]]) {
        UITextField *tf = (UITextField *)view;
        if (tf.isEnabled && !tf.isHidden) {
            block(tf);
        }
    }
    for (UIView *subview in view.subviews) {
        [self _enumerateTextFieldsInView:subview block:block];
    }
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

/// 修改账号资料（昵称/签名/链接）
/// params: {nickname, signature, link}
- (void)_performEditProfile:(NSDictionary *)params {
    NSString *nickname = params[@"nickname"] ?: @"";
    NSString *signature = params[@"signature"] ?: @"";
    NSString *link = params[@"link"] ?: @"";
    if (nickname.length == 0 && signature.length == 0 && link.length == 0) return;

    // 导航到个人主页 → 点编辑资料
    dispatch_sync(dispatch_get_main_queue(), ^{
        [self _navigateToProfile];
    });
    [NSThread sleepForTimeInterval:1.5];

    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *editBtn = [self _findButtonWithAnyLabel:@[@"Edit profile", @"Edit Profile", @"编辑资料", @"编辑"]
                                                   inView:XN_ActiveWindow()];
        if (editBtn) {
            [self _safeTapAtPoint:[editBtn.superview convertPoint:editBtn.center toView:nil]];
        } else {
            // 坐标回退：编辑按钮通常在资料卡右上
            CGSize screen = [UIScreen mainScreen].bounds.size;
            [self _safeTapAtPoint:CGPointMake(screen.width - 40, screen.height * 0.38)];
        }
    });
    [NSThread sleepForTimeInterval:1.5];

    // 改昵称
    if (nickname.length > 0) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            UITextField *nameField = [self _findTextFieldWithPlaceholderInView:XN_ActiveWindow()
                                                                     keywords:@[@"name", @"Name", @"昵称", @"name", @"username"]];
            if (nameField) {
                nameField.text = nickname;
                [nameField becomeFirstResponder];
                [[NSNotificationCenter defaultCenter] postNotificationName:UITextFieldTextDidChangeNotification object:nameField];
            }
        });
        [NSThread sleepForTimeInterval:0.5];
    }

    // 改签名
    if (signature.length > 0) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            UITextField *bioField = [self _findTextFieldWithPlaceholderInView:XN_ActiveWindow()
                                                                     keywords:@[@"bio", @"Bio", @"签名", @"简介", @"introduce"]];
            if (bioField) {
                bioField.text = signature;
                [bioField becomeFirstResponder];
                [[NSNotificationCenter defaultCenter] postNotificationName:UITextFieldTextDidChangeNotification object:bioField];
            }
        });
        [NSThread sleepForTimeInterval:0.5];
    }

    // 保存
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *saveBtn = [self _findButtonWithAnyLabel:@[@"Save", @"save", @"保存", @"Done", @"完成"]
                                                   inView:XN_ActiveWindow()];
        if (saveBtn) {
            [self _safeTapAtPoint:[saveBtn.superview convertPoint:saveBtn.center toView:nil]];
        }
    });
    [NSThread sleepForTimeInterval:1.0];
}

/// 按 placeholder 关键词查找输入框
- (UITextField *)_findTextFieldWithPlaceholderInView:(UIView *)view keywords:(NSArray *)keywords {
    if ([view isKindOfClass:[UITextField class]]) {
        UITextField *tf = (UITextField *)view;
        NSString *ph = tf.placeholder ?: @"";
        for (NSString *kw in keywords) {
            if ([ph.lowercaseString containsString:kw.lowercaseString]) return tf;
        }
    }
    for (UIView *sub in view.subviews) {
        UITextField *tf = [self _findTextFieldWithPlaceholderInView:sub keywords:keywords];
        if (tf) return tf;
    }
    return nil;
}

#pragma mark - 自动发视频 (Phase 5)

/// 自动发视频：点 "+" → 上传 → 选第一个媒体 → 下一步 → 填文案 → 发布
/// params: {title, video_url}
/// 说明：UI 自动化无法按 URL 精确定位相册素材，video_url 为 best-effort，
///       实际选取相册中第一张媒体（后续有精确素材注入方案时再升级）。
- (NSDictionary *)_performPostVideo:(NSDictionary *)params {
    NSString *title = params[@"title"] ?: @"";
    NSString *videoUrl = params[@"video_url"] ?: @"";

    // Step 1: 点底部 "+" 发视频按钮
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *postBtn = [self _findButtonWithAnyLabel:@[@"post", @"Post", @"create", @"Create",
                                                             @"发布", @"上传", @"+"]
                                                    inView:XN_ActiveWindow()];
        if (postBtn) {
            [self _safeTapAtPoint:[postBtn.superview convertPoint:postBtn.center toView:nil]];
        } else {
            // 坐标回退：底部中间 "+"
            CGSize screen = [UIScreen mainScreen].bounds.size;
            [self _safeTapAtPoint:CGPointMake(screen.width * 0.5, screen.height - 50)];
        }
    });
    [NSThread sleepForTimeInterval:2.0];

    // Step 2: 点 "上传"（从相册/本地上传）
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *uploadBtn = [self _findButtonWithAnyLabel:@[@"Upload", @"upload", @"上传", @"相册",
                                                               @"Album", @"Gallery", @"照片"]
                                                      inView:XN_ActiveWindow()];
        if (uploadBtn) {
            [self _safeTapAtPoint:[uploadBtn.superview convertPoint:uploadBtn.center toView:nil]];
        } else {
            // 坐标回退：上传入口通常在顶部区域
            CGSize screen = [UIScreen mainScreen].bounds.size;
            [self _safeTapAtPoint:CGPointMake(screen.width * 0.5, screen.height * 0.18)];
        }
    });
    [NSThread sleepForTimeInterval:2.5];

    // Step 3: 相册选择第一个媒体（best-effort，无素材库精确注入时选第一张）
    [self _tapFirstMediaCell];
    [NSThread sleepForTimeInterval:1.5];

    // Step 4: 点 "下一步"（Next）
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *nextBtn = [self _findButtonWithAnyLabel:@[@"Next", @"next", @"下一步", @"完成", @"Done"]
                                                    inView:XN_ActiveWindow()];
        if (nextBtn) {
            [self _safeTapAtPoint:[nextBtn.superview convertPoint:nextBtn.center toView:nil]];
        } else {
            // 坐标回退：右上角
            CGSize screen = [UIScreen mainScreen].bounds.size;
            [self _safeTapAtPoint:CGPointMake(screen.width - 40, 60)];
        }
    });
    [NSThread sleepForTimeInterval:2.0];

    // Step 5: 填文案/标题
    if (title.length > 0) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            UITextView *textView = [self _findTextViewInView:XN_ActiveWindow()];
            UITextField *textField = [self _findTextFieldInView:XN_ActiveWindow()];
            if (textView) {
                textView.text = title;
                [[NSNotificationCenter defaultCenter]
                 postNotificationName:UITextViewTextDidChangeNotification object:textView];
            } else if (textField) {
                textField.text = title;
                [[NSNotificationCenter defaultCenter]
                 postNotificationName:UITextFieldTextDidChangeNotification object:textField];
            }
        });
        [NSThread sleepForTimeInterval:0.5];
    }

    // Step 6: 点 "发布"（Publish）
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *publishBtn = [self _findButtonWithAnyLabel:@[@"Publish", @"publish", @"发布", @"Post", @"Share"]
                                                       inView:XN_ActiveWindow()];
        if (publishBtn) {
            [self _safeTapAtPoint:[publishBtn.superview convertPoint:publishBtn.center toView:nil]];
        } else {
            // 坐标回退：右下角/底部
            CGSize screen = [UIScreen mainScreen].bounds.size;
            [self _safeTapAtPoint:CGPointMake(screen.width * 0.5, screen.height - 50)];
        }
    });
    [NSThread sleepForTimeInterval:1.0];

    return @{
        @"status": @"success",
        @"message": @"已触发发视频流程（best-effort UI 自动化）",
        @"title": title.length ? title : @"",
        @"video_url": videoUrl,
        @"note": @"UI自动化无法精确定位指定 URL 素材，实际选择了相册第一张媒体",
    };
}

/// 点击相册选择器中的第一个媒体 cell
- (void)_tapFirstMediaCell {
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        if (!window) return;
        __block UIView *firstCell = nil;
        [self _findFirstMediaCellInView:window result:&firstCell];
        if (firstCell) {
            [self _safeTapAtPoint:[firstCell.superview convertPoint:firstCell.center toView:nil]];
        } else {
            // 坐标回退：左上角第一个格
            CGSize screen = [UIScreen mainScreen].bounds.size;
            [self _safeTapAtPoint:CGPointMake(screen.width * 0.1, screen.height * 0.2)];
        }
    });
}

/// 递归查找第一个可见的相册媒体 cell（UICollectionViewCell）
- (void)_findFirstMediaCellInView:(UIView *)view result:(UIView **)result {
    if (*result) return;
    if ([view isKindOfClass:[UICollectionViewCell class]]) {
        UIView *target = view;
        CGRect globalRect = [target.superview convertRect:target.frame toView:nil];
        if (CGRectIntersectsRect(globalRect, [UIScreen mainScreen].bounds)) {
            *result = view;
        }
        return;
    }
    for (UIView *sub in view.subviews) {
        [self _findFirstMediaCellInView:sub result:result];
        if (*result) return;
    }
}

#pragma mark - 自动私信 (Phase 6)

/// 自动私信：打开用户主页（URL scheme）→ 点"私信/发消息" → 输入内容 → 发送
/// params: {target, content}
/// best-effort UI 自动化（fragile），失败返回 status=failed + 原因
- (NSDictionary *)_performSendDm:(NSDictionary *)params {
    NSString *target = params[@"target"] ?: @"";
    NSString *content = params[@"content"] ?: @"";
    if (content.length == 0) {
        return @{@"status": @"failed", @"message": @"私信内容不能为空"};
    }

    // Step 1: 打开目标用户主页（URL scheme）；无 target 则切到消息页
    if (target.length > 0) {
        [self _performOpenUser:target];
    } else {
        [self _tapTab:@"inbox"];
    }
    [NSThread sleepForTimeInterval:3.0];

    // Step 2: 点"私信/发消息"按钮（资料页）
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *msgBtn = [self _findButtonWithAnyLabel:@[@"Message", @"message", @"私信",
                                                           @"发消息", @"Say hi", @"say hi"]
                                                  inView:XN_ActiveWindow()];
        if (msgBtn) {
            [self _safeTapAtPoint:[msgBtn.superview convertPoint:msgBtn.center toView:nil]];
        } else {
            // 坐标回退：私信按钮通常在资料页中下部右侧
            CGSize screen = [UIScreen mainScreen].bounds.size;
            [self _safeTapAtPoint:CGPointMake(screen.width * 0.85, screen.height * 0.4)];
        }
    });
    [NSThread sleepForTimeInterval:2.0];

    // Step 3: 找输入框，填入私信内容
    __block BOOL fieldFound = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        UITextField *textField = [self _findTextFieldInView:window];
        UITextView *textView = [self _findTextViewInView:window];
        if (textField) {
            textField.text = content;
            [textField sendActionsForControlEvents:UIControlEventEditingChanged];
            [[NSNotificationCenter defaultCenter]
             postNotificationName:UITextFieldTextDidChangeNotification object:textField];
            fieldFound = YES;
        } else if (textView) {
            textView.text = content;
            [[NSNotificationCenter defaultCenter]
             postNotificationName:UITextViewTextDidChangeNotification object:textView];
            fieldFound = YES;
        }
    });
    if (!fieldFound) {
        return @{@"status": @"failed", @"message": @"未找到私信输入框"};
    }
    [NSThread sleepForTimeInterval:0.8];

    // Step 4: 点发送
    __block BOOL sent = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *sendBtn = [self _findButtonWithAnyLabel:@[@"Send", @"send", @"发送", @"发送私信"]
                                                   inView:XN_ActiveWindow()];
        if (sendBtn) {
            [self _safeTapAtPoint:[sendBtn.superview convertPoint:sendBtn.center toView:nil]];
            sent = YES;
            return;
        }
        UIView *sendView = [self _findViewWithAccessibilityIdentifier:kAccSend
                                                               inView:XN_ActiveWindow()];
        if (sendView) {
            [self _safeTapAtPoint:[sendView.superview convertPoint:sendView.center toView:nil]];
            sent = YES;
        }
    });

    if (!sent) {
        return @{@"status": @"failed", @"message": @"未找到发送按钮"};
    }
    return @{@"status": @"success", @"message": @"已发送私信", @"target": target};
}

/// 发名片：打开分享面板 → 点"名片"分享选项（best-effort）
- (NSDictionary *)_performSendCard:(NSDictionary *)params {
    [self _performShare];
    [NSThread sleepForTimeInterval:1.5];

    __block BOOL tapped = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *cardBtn = [self _findButtonWithAnyLabel:@[@"Card", @"card", @"名片",
                                                            @"business card", @"Business Card"]
                                                   inView:XN_ActiveWindow()];
        if (cardBtn) {
            [self _safeTapAtPoint:[cardBtn.superview convertPoint:cardBtn.center toView:nil]];
            tapped = YES;
        }
    });
    [NSThread sleepForTimeInterval:1.0];

    if (!tapped) {
        return @{@"status": @"failed", @"message": @"未找到名片分享选项"};
    }
    return @{@"status": @"success", @"message": @"已触发发送名片"};
}

/// 分享直播间：打开分享面板 → 点"直播"分享选项（best-effort）
- (NSDictionary *)_performShareLive:(NSDictionary *)params {
    [self _performShare];
    [NSThread sleepForTimeInterval:1.5];

    __block BOOL tapped = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *liveBtn = [self _findButtonWithAnyLabel:@[@"Live", @"live", @"直播",
                                                            @"直播间", @"Share Live", @"分享直播"]
                                                   inView:XN_ActiveWindow()];
        if (liveBtn) {
            [self _safeTapAtPoint:[liveBtn.superview convertPoint:liveBtn.center toView:nil]];
            tapped = YES;
        }
    });
    [NSThread sleepForTimeInterval:1.0];

    if (!tapped) {
        return @{@"status": @"failed", @"message": @"未找到直播间分享选项"};
    }
    return @{@"status": @"success", @"message": @"已触发分享直播间"};
}

#pragma mark - 批量注册 + 自动养号 (Feature 5)

/// 养号心跳：一次短随机浏览会话（2~5 次滑动 + 按概率点赞/关注/评论），约 1~2 分钟
/// params: {min_scrolls, max_scrolls, like_probability, follow_probability, comment_probability, browse_minutes}
- (NSDictionary *)_performNurtureTick:(NSDictionary *)params {
    int minScrolls = [params[@"min_scrolls"] intValue];
    if (minScrolls < 1) minScrolls = 2;
    int maxScrolls = [params[@"max_scrolls"] intValue];
    if (maxScrolls < minScrolls) maxScrolls = minScrolls + 3;

    double likeProb = [params[@"like_probability"] doubleValue];
    if (likeProb <= 0) likeProb = 0.2;
    double followProb = [params[@"follow_probability"] doubleValue];
    if (followProb <= 0) followProb = 0.05;
    double commentProb = [params[@"comment_probability"] doubleValue];
    if (commentProb <= 0) commentProb = 0.02;

    int scrollCount = minScrolls + arc4random_uniform(maxScrolls - minScrolls + 1);
    if (scrollCount < minScrolls) scrollCount = minScrolls;

    // 用 browse_minutes 折算每步观看秒数，使总时长接近目标分钟数
    int browseMinutes = [params[@"browse_minutes"] intValue];
    if (browseMinutes < 1) browseMinutes = 1;
    if (browseMinutes > 10) browseMinutes = 10;
    int perStepSeconds = (browseMinutes * 60) / MAX(1, scrollCount);
    if (perStepSeconds < 10) perStepSeconds = 10;
    if (perStepSeconds > 45) perStepSeconds = 45;

    __block int likes = 0;
    __block int follows = 0;
    __block int comments = 0;
    NSMutableArray *doneActions = [NSMutableArray array];

    for (int i = 0; i < scrollCount; i++) {
        // 每步随机观看 perStepSeconds±5 秒
        int watchTime = perStepSeconds - 5 + arc4random_uniform(11);
        if (watchTime < 5) watchTime = 5;
        [NSThread sleepForTimeInterval:watchTime];

        dispatch_sync(dispatch_get_main_queue(), ^{
            // 按概率点赞
            if ((double)(arc4random_uniform(1000)) / 1000.0 < likeProb) {
                [self _performLike];
                likes++;
                [doneActions addObject:@"like"];
                [NSThread sleepForTimeInterval:0.6];
            }
            // 按概率关注
            if ((double)(arc4random_uniform(1000)) / 1000.0 < followProb) {
                [self _performFollow];
                follows++;
                [doneActions addObject:@"follow"];
                [NSThread sleepForTimeInterval:0.6];
            }
            // 按概率评论
            if ((double)(arc4random_uniform(1000)) / 1000.0 < commentProb) {
                [self _performComment:@"Nice!"];
                comments++;
                [doneActions addObject:@"comment"];
                [NSThread sleepForTimeInterval:1.5];
                // 关闭评论面板
                [self _performSwipeDown];
                [NSThread sleepForTimeInterval:0.5];
            }
            // 上滑到下一个视频
            [self _performSwipeUp];
        });

        [NSThread sleepForTimeInterval:0.5];
    }

    return @{
        @"status": @"success",
        @"message": [NSString stringWithFormat:@"养号 tick 完成: %d 滑, %d 赞, %d 关注, %d 评论",
                     scrollCount, likes, follows, comments],
        @"scrolls": @(scrollCount),
        @"likes": @(likes),
        @"follows": @(follows),
        @"comments": @(comments),
        @"actions": doneActions,
    };
}

/// 停止养号：tick 为一次性指令，停止是隐式的，仅返回状态
- (NSDictionary *)_performNurtureStop {
    return @{
        @"status": @"stopped",
        @"message": @"养号已停止（tick 为一次性指令，无需显式停止）",
    };
}

/// 注册新账号：导航到个人页 → 点"登录/注册" → 切"注册" → 填邮箱/手机 → 密码 → 继续
/// params: {email, phone, password, nickname?}
/// 说明：滑块/验证码无法通过纯 UI 自动化解决，需人工介入或专用打码工具（best-effort）
- (NSDictionary *)_performRegisterAccount:(NSDictionary *)params {
    NSString *email = params[@"email"] ?: @"";
    NSString *phone = params[@"phone"] ?: @"";
    NSString *password = params[@"password"] ?: @"";
    NSString *credential = email.length > 0 ? email : phone;

    if (credential.length == 0) {
        return @{@"status": @"failed", @"message": @"缺少邮箱或手机号"};
    }

    // Step 1: 导航到个人主页（点底部"我"）
    dispatch_sync(dispatch_get_main_queue(), ^{
        [self _navigateToProfile];
    });
    [NSThread sleepForTimeInterval:2.0];

    // Step 2: 若在登录页，找 "登录/注册" 入口
    __block BOOL loginTap = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        UIButton *loginBtn = [self _findButtonWithAnyLabel:@[@"Log in", @"Sign up", @"Sign Up",
                                                             @"登录", @"注册"]
                                                    inView:window];
        if (loginBtn) {
            [self _safeTapAtPoint:[loginBtn.superview convertPoint:loginBtn.center toView:nil]];
            loginTap = YES;
        }
    });
    if (!loginTap) {
        // 可能已经在登录/注册页
        return @{@"status": @"failed", @"message": @"未找到登录/注册入口（请确认处于未登录状态）"};
    }
    [NSThread sleepForTimeInterval:1.5];

    // Step 3: 切到 "注册/Sign up" tab
    __block BOOL signUpTap = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        UIButton *signUpBtn = [self _findButtonWithAnyLabel:@[@"Sign up", @"Sign Up", @"注册", @"Register"]
                                                     inView:window];
        if (signUpBtn) {
            [self _safeTapAtPoint:[signUpBtn.superview convertPoint:signUpBtn.center toView:nil]];
            signUpTap = YES;
        } else {
            // 坐标回退：注册 tab 通常在登录页上部
            CGSize screen = [UIScreen mainScreen].bounds.size;
            [self _safeTapAtPoint:CGPointMake(screen.width * 0.5, screen.height * 0.12)];
            signUpTap = YES;
        }
    });
    [NSThread sleepForTimeInterval:1.5];

    // Step 4: 填邮箱/手机号
    __block BOOL fieldFound = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        UITextField *tf = [self _findTextFieldInView:window];
        if (tf) {
            tf.text = credential;
            [tf becomeFirstResponder];
            [tf sendActionsForControlEvents:UIControlEventEditingChanged];
            [[NSNotificationCenter defaultCenter]
             postNotificationName:UITextFieldTextDidChangeNotification object:tf];
            fieldFound = YES;
        }
    });
    if (!fieldFound) {
        return @{@"status": @"failed", @"message": @"未找到邮箱/手机号输入框"};
    }
    [NSThread sleepForTimeInterval:0.8];

    // Step 5: 填密码（若提供，且存在第二个输入框）
    if (password.length > 0) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            UIWindow *window = XN_ActiveWindow();
            __block UITextField *secondTf = nil;
            __block int count = 0;
            [self _enumerateTextFieldsInView:window block:^(UITextField *tf) {
                count++;
                if (count == 2) secondTf = tf;
            }];
            if (secondTf) {
                secondTf.text = password;
                [secondTf becomeFirstResponder];
                [secondTf sendActionsForControlEvents:UIControlEventEditingChanged];
                [[NSNotificationCenter defaultCenter]
                 postNotificationName:UITextFieldTextDidChangeNotification object:secondTf];
            }
        });
        [NSThread sleepForTimeInterval:0.5];
    }

    // Step 6: 点 "继续/下一步"
    __block BOOL continueTap = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        UIButton *nextBtn = [self _findButtonWithAnyLabel:@[@"Continue", @"continue", @"下一步",
                                                            @"继续", @"Next", @"Sign up"]
                                                   inView:window];
        if (nextBtn) {
            [self _safeTapAtPoint:[nextBtn.superview convertPoint:nextBtn.center toView:nil]];
            continueTap = YES;
        }
    });
    [NSThread sleepForTimeInterval:1.0];

    if (!continueTap) {
        return @{@"status": @"failed", @"message": @"未找到继续按钮（滑块/验证码需人工处理）"};
    }

    return @{
        @"status": @"success",
        @"message": @"已触发注册流程（best-effort UI 自动化；滑块/验证码需人工或专用打码工具）",
        @"credential": credential,
        @"note": @"滑块/验证码无法纯 UI 自动化解决",
    };
}

#pragma mark - 辅助: 手势模拟

/// 真实滑动手势（注入 UITouch/UIEvent）
- (void)_simulateSwipeFrom:(CGPoint)from to:(CGPoint)to {
    [XNTouchSimulator swipeFrom:from to:to];
    NSLog(@"[XNOWER] 真实滑动 %.0fpt", to.y - from.y);
}

@end

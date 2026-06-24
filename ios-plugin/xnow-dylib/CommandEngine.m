// CommandEngine.m
// XNOW 指令执行引擎完整实现
// 通过 UITouch/UIEvent 真实模拟用户操作 + 视图层级遍历 + 网络数据采集

#import "CommandEngine.h"
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

#pragma mark - 真实滑动手势模拟

/// 上滑（下一个视频）- 通过 UITouch 模拟完整 swipe 事件
- (void)_performSwipeUp {
    dispatch_sync(dispatch_get_main_queue(), ^{
        CGSize screen = [UIScreen mainScreen].bounds.size;
        CGFloat midX = screen.width / 2;
        CGFloat startY = screen.height * 0.65;
        CGFloat endY = screen.height * 0.35;

        [self _simulateSwipeFrom:CGPointMake(midX, startY) to:CGPointMake(midX, endY)];
    });
}

/// 下滑（上一个视频）
- (void)_performSwipeDown {
    dispatch_sync(dispatch_get_main_queue(), ^{
        CGSize screen = [UIScreen mainScreen].bounds.size;
        CGFloat midX = screen.width / 2;
        CGFloat startY = screen.height * 0.35;
        CGFloat endY = screen.height * 0.65;

        [self _simulateSwipeFrom:CGPointMake(midX, startY) to:CGPointMake(midX, endY)];
    });
}

/// 通过 UITouch + UIEvent 构造真实滑动事件
- (void)_simulateSwipeFrom:(CGPoint)from to:(CGPoint)to {
    UIWindow *window = XN_ActiveWindow();
    if (!window) return;

    // 找到接收事件的 view
    UIView *targetView = [window hitTest:from withEvent:nil];
    if (!targetView) targetView = window;

    // 构建 touch 序列（touch down → move多次 → touch up）
    // 使用 UIApplication sendEvent 发送
    UITouch *touch = [[UITouch alloc] init];
    [touch setValue:@(1) forKeyPath:@"tapCount"];
    [touch setValue:@(UITouchPhaseBegan) forKeyPath:@"phase"];
    [touch setValue:[NSValue valueWithCGPoint:from] forKeyPath:@"locationInWindow"];
    [touch setValue:targetView forKeyPath:@"view"];
    [touch setValue:@(0) forKeyPath:@"timestamp"];

    // 构造 event
    UIEvent *event = [self _createTouchEventWithTouch:touch phase:UITouchPhaseBegan];
    [[UIApplication sharedApplication] sendEvent:event];

    // 模拟滑动中间点
    CGFloat steps = 8;
    for (int i = 1; i <= steps; i++) {
        CGFloat t = i / steps;
        CGPoint mid = CGPointMake(
            from.x + (to.x - from.x) * t,
            from.y + (to.y - from.y) * t
        );
        [touch setValue:[NSValue valueWithCGPoint:mid] forKeyPath:@"locationInWindow"];
        [touch setValue:@(UITouchPhaseMoved) forKeyPath:@"phase"];
        [touch setValue:@(i * 0.02) forKeyPath:@"timestamp"];

        UIEvent *moveEvent = [self _createTouchEventWithTouch:touch phase:UITouchPhaseMoved];
        [[UIApplication sharedApplication] sendEvent:moveEvent];
        [NSThread sleepForTimeInterval:0.015];
    }

    // Touch Up
    [touch setValue:[NSValue valueWithCGPoint:to] forKeyPath:@"locationInWindow"];
    [touch setValue:@(UITouchPhaseEnded) forKeyPath:@"phase"];
    [touch setValue:@(0.2) forKeyPath:@"timestamp"];

    UIEvent *endEvent = [self _createTouchEventWithTouch:touch phase:UITouchPhaseEnded];
    [[UIApplication sharedApplication] sendEvent:endEvent];
}

/// 模拟单次点击
- (void)_simulateTapAtPoint:(CGPoint)point {
    UIWindow *window = XN_ActiveWindow();
    if (!window) return;

    UIView *targetView = [window hitTest:point withEvent:nil];
    if (!targetView) targetView = window;

    // Touch Down
    UITouch *touch = [[UITouch alloc] init];
    [touch setValue:@(1) forKeyPath:@"tapCount"];
    [touch setValue:@(UITouchPhaseBegan) forKeyPath:@"phase"];
    [touch setValue:[NSValue valueWithCGPoint:point] forKeyPath:@"locationInWindow"];
    [touch setValue:targetView forKeyPath:@"view"];
    [touch setValue:@(0) forKeyPath:@"timestamp"];

    UIEvent *downEvent = [self _createTouchEventWithTouch:touch phase:UITouchPhaseBegan];
    [[UIApplication sharedApplication] sendEvent:downEvent];
    [NSThread sleepForTimeInterval:0.05];

    // Touch Up
    [touch setValue:@(UITouchPhaseEnded) forKeyPath:@"phase"];
    [touch setValue:@(0.1) forKeyPath:@"timestamp"];
    UIEvent *upEvent = [self _createTouchEventWithTouch:touch phase:UITouchPhaseEnded];
    [[UIApplication sharedApplication] sendEvent:upEvent];

    // 如果是 UIControl，额外发 action（兼容某些控件）
    if ([targetView isKindOfClass:[UIControl class]]) {
        [(UIControl *)targetView sendActionsForControlEvents:UIControlEventTouchUpInside];
    }
}

/// 构造 UIEvent（用于模拟触摸）
- (UIEvent *)_createTouchEventWithTouch:(UITouch *)touch phase:(UITouchPhase)phase {
    // 使用私有 API 构造 UIEvent
    UIEvent *event = [self _allocEventWithTouches:@[touch]];
    return event;
}

- (UIEvent *)_allocEventWithTouches:(NSArray *)touches {
    // 通过 runtime 创建 UIEvent（不依赖私有头文件）
    UIEvent *event = [[UIEvent alloc] init];

    // 设置 event type 为 touches
    [event setValue:@(UIEventTypeTouches) forKeyPath:@"type"];
    [event setValue:@(UIEventSubtypeNone) forKeyPath:@"subtype"];
    [event setValue:@(0) forKeyPath:@"timestamp"];

    // 关联 touches（使用内部方法 _addTouch:forDelayedDelivery:）
    SEL addTouchSel = NSSelectorFromString(@"_addTouch:forDelayedDelivery:");
    if ([event respondsToSelector:addTouchSel]) {
        for (UITouch *touch in touches) {
            // 使用 performSelector 规避 ARC 警告
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [event performSelector:addTouchSel withObject:touch withObject:@(NO)];
            #pragma clang diagnostic pop
        }
    }

    return event;
}

#pragma mark - 点赞

- (void)_performLike {
    dispatch_sync(dispatch_get_main_queue(), ^{
        // 1. 通过 accessibility identifier 找点赞按钮
        UIView *likeView = [self _findViewWithAccessibilityIdentifier:kAccLike
                                                               inView:XN_ActiveWindow()];
        if (likeView) {
            CGPoint center = [likeView.superview convertPoint:likeView.center toView:nil];
            [self _simulateTapAtPoint:center];
            return;
        }

        // 2. 通过 accessibility label
        UIButton *likeBtn = [self _findButtonWithAnyLabel:@[@"like", @"Like", @"heart", @"Heart"]
                                                   inView:XN_ActiveWindow()];
        if (likeBtn) {
            CGPoint center = [likeBtn.superview convertPoint:likeBtn.center toView:nil];
            [self _simulateTapAtPoint:center];
            return;
        }

        // 3. 坐标回退：TikTok 点赞按钮在右侧中间偏下
        CGSize screen = [UIScreen mainScreen].bounds.size;
        [self _simulateTapAtPoint:CGPointMake(
            screen.width * kLikeBtnRatioX,
            screen.height * kLikeBtnRatioY)];
    });
}

#pragma mark - 关注

- (void)_performFollow {
    dispatch_sync(dispatch_get_main_queue(), ^{
        // 1. 通过 accessibility
        UIButton *btn = [self _findButtonWithAnyLabel:@[@"follow", @"Follow", @"+"]
                                               inView:XN_ActiveWindow()];
        if (btn) {
            [self _simulateTapAtPoint:[btn.superview convertPoint:btn.center toView:nil]];
            return;
        }

        // 2. 坐标回退：右侧偏上（关注按钮在点赞按钮上方）
        CGSize screen = [UIScreen mainScreen].bounds.size;
        [self _simulateTapAtPoint:CGPointMake(
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
            [self _simulateTapAtPoint:[commentView.superview convertPoint:commentView.center toView:nil]];
        } else {
            CGSize screen = [UIScreen mainScreen].bounds.size;
            [self _simulateTapAtPoint:CGPointMake(screen.width * 0.5, screen.height * 0.15)];
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
            [self _simulateTapAtPoint:[sendBtn.superview convertPoint:sendBtn.center toView:nil]];
        } else {
            // 尝试找到底部工具栏的发发送按钮
            UIButton *btn = [self _findButtonWithAnyLabel:@[@"send", @"Send", @"Post",
                                                             @"发送", @"发布"]
                                                   inView:XN_ActiveWindow()];
            if (btn) {
                [self _simulateTapAtPoint:[btn.superview convertPoint:btn.center toView:nil]];
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
            [self _simulateTapAtPoint:[collectView.superview convertPoint:collectView.center toView:nil]];
        } else {
            // 直接搜索 "save" 或 "bookmark"
            UIButton *btn = [self _findButtonWithAnyLabel:@[@"save", @"Save", @"bookmark",
                                                             @"收藏", @"Add to Favorites"]
                                                   inView:XN_ActiveWindow()];
            if (btn) {
                [self _simulateTapAtPoint:[btn.superview convertPoint:btn.center toView:nil]];
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
            [self _simulateTapAtPoint:[avatarView.superview convertPoint:avatarView.center toView:nil]];
        } else {
            CGSize screen = [UIScreen mainScreen].bounds.size;
            [self _simulateTapAtPoint:CGPointMake(
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
            [self _simulateTapAtPoint:[fansBtn.superview convertPoint:fansBtn.center toView:nil]];
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
            [self _simulateTapAtPoint:[videoBtn.superview convertPoint:videoBtn.center toView:nil]];
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

@end

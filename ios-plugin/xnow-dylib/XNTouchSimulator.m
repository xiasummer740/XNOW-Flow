// XNTouchSimulator.m
// 通过 KVC 创建真实 UITouch / UIEvent 对象，经 [window sendEvent:] 注入，
// 使 TikTok 的 UIGestureRecognizer（点击/滑动/长按）真正触发。

#import "XNTouchSimulator.h"
#import "XNWindowHelper.h"
#import "XNOWER.h"
#import "XNURLProtocol.h"
#import <QuartzCore/QuartzCore.h>

@implementation XNTouchSimulator

/// 创建真实 UITouch（私有 ivar 用 KVC 写入，模拟触摸位置/相位）
+ (UITouch *)_makeTouchAt:(CGPoint)point phase:(UITouchPhase)phase view:(UIView *)view window:(UIWindow *)window {
    UITouch *touch = [[UITouch alloc] init];
    if (!touch) return nil;
    @try {
        if (view) [touch setValue:view forKey:@"_view"];
        if (window) [touch setValue:window forKey:@"_window"];
        [touch setValue:@(phase) forKey:@"_phase"];
        [touch setValue:[NSValue valueWithCGPoint:point] forKey:@"_locationInWindow"];
        [touch setValue:[NSValue valueWithCGPoint:point] forKey:@"_previousLocationInWindow"];
        [touch setValue:@(CACurrentMediaTime()) forKey:@"_timestamp"];
        [touch setValue:@(1) forKey:@"_tapCount"];
    } @catch (NSException *e) {
        NSLog(@"[XNTouch] makeTouch error: %@", e.reason);
        return nil;
    }
    return touch;
}

/// 创建承载 touch 的 UIEvent
+ (UIEvent *)_makeEventWithTouch:(UITouch *)touch {
    UIEvent *event = [[UIEvent alloc] init];
    if (!event) return nil;
    @try {
        [event setValue:[NSSet setWithObject:touch] forKey:@"_touches"];
        [event setValue:@(UIEventTypeTouches) forKey:@"_type"];
        [event setValue:@(UIEventSubtypeNone) forKey:@"_subtype"];
        [event setValue:@(CACurrentMediaTime()) forKey:@"_timestamp"];
    } @catch (NSException *e) {
        NSLog(@"[XNTouch] makeEvent error: %@", e.reason);
        return nil;
    }
    return event;
}

/// 更新 touch 相位与位置（同一 touch 对象跨 phase 复用，手势识别器才能跟踪）
+ (void)_updateTouch:(UITouch *)touch phase:(UITouchPhase)phase at:(CGPoint)point {
    @try {
        [touch setValue:@(phase) forKey:@"_phase"];
        [touch setValue:[NSValue valueWithCGPoint:point] forKey:@"_locationInWindow"];
        [touch setValue:[NSValue valueWithCGPoint:point] forKey:@"_previousLocationInWindow"];
        [touch setValue:@(CACurrentMediaTime()) forKey:@"_timestamp"];
    } @catch (NSException *e) {
        NSLog(@"[XNTouch] update error: %@", e.reason);
    }
}

+ (void)_dispatchWithTouch:(UITouch *)touch window:(UIWindow *)window {
    UIEvent *event = [self _makeEventWithTouch:touch];
    if (!event || !window) return;
    // 经 UIApplication sendEvent: 走完整事件管线（比 window sendEvent 更能触发手势识别器）
    // 必须 @try：合成事件在页面过渡期可能触发 TikTok 内部异常，防止崩溃
    @try {
        [[UIApplication sharedApplication] sendEvent:event];
    } @catch (NSException *e) {
        NSLog(@"[XNTouch] sendEvent error: %@", e.reason);
    }
}

/// 诊断上报：注入点击时，把命中的控件信息发到后端（用于验证是否点到正确元素）
+ (void)_reportTapDiagnostic:(CGPoint)point view:(UIView *)view {
    @try {
        NSString *cls = NSStringFromClass(view.class) ?: @"nil";
        BOOL isControl = [view isKindOfClass:[UIControl class]];
        NSString *devId = [XNOWER sharedInstance].deviceId;
        if (devId.length == 0) return;
        [XNURLProtocol sendMessage:@{
            @"type": @"touch_diag",
            @"data": @{
                @"x": @(round(point.x)), @"y": @(round(point.y)),
                @"view": cls,
                @"is_control": @(isControl),
                @"frame": NSStringFromCGRect(view.frame),
                @"superview": NSStringFromClass(view.superview.class) ?: @"nil",
                @"gestures": [self _gestureInfo:view],
                @"target_actions": [self _targetActionInfo:view],
                @"super_gestures": [self _superGestureChain:view],
            }
        } deviceId:devId];
    } @catch (NSException *e) {
        NSLog(@"[XNTouch] diag error: %@", e.reason);
    }
}

/// 诊断：view 上的手势识别器 + target-action 列表（用于判断 TikTok 按钮怎么接线）
+ (NSArray *)_gestureInfo:(UIView *)view {
    NSMutableArray *info = [NSMutableArray array];
    @try {
        for (UIGestureRecognizer *gr in view.gestureRecognizers) {
            NSMutableDictionary *d = [@{@"class": NSStringFromClass(gr.class)} mutableCopy];
            NSArray *targets = [gr valueForKey:@"_targets"];
            NSMutableArray *acts = [NSMutableArray array];
            for (id t in targets) {
                id target = [t valueForKey:@"_target"];
                id actionVal = [t valueForKey:@"_action"];
                if ([actionVal isKindOfClass:[NSString class]]) {
                    [acts addObject:[NSString stringWithFormat:@"%@->%@", NSStringFromClass([target class]), actionVal]];
                }
            }
            if (acts.count) d[@"actions"] = acts;
            [info addObject:d];
        }
    } @catch (NSException *e) {}
    return info;
}

/// 诊断：UIControl 的 target-action 接线（所有常见 control event）
+ (NSArray *)_targetActionInfo:(UIView *)view {
    NSMutableArray *info = [NSMutableArray array];
    if (![view isKindOfClass:[UIControl class]]) return info;
    UIControl *ctrl = (UIControl *)view;
    @try {
        NSArray *events = @[@(UIControlEventTouchDown), @(UIControlEventTouchDownRepeat),
                            @(UIControlEventTouchUpInside), @(UIControlEventTouchUpOutside),
                            @(UIControlEventValueChanged), @(UIControlEventAllTouchEvents)];
        for (id target in [ctrl allTargets]) {
            for (NSNumber *evt in events) {
                NSArray *acts = [ctrl actionsForTarget:target forControlEvent:[evt unsignedIntegerValue]];
                for (NSString *selStr in acts) {
                    [info addObject:[NSString stringWithFormat:@"%@/0x%lx:%@",
                                     NSStringFromClass([target class]),
                                     (unsigned long)[evt unsignedIntegerValue], selStr]];
                }
            }
        }
    } @catch (NSException *e) {}
    return info;
}

/// 诊断：superview 链上每层的手势识别器（TikTok 可能把点击手势挂在父视图）
+ (NSArray *)_superGestureChain:(UIView *)view {
    NSMutableArray *chain = [NSMutableArray array];
    UIView *superV = view.superview;
    int depth = 0;
    while (superV && depth < 6) {
        [chain addObject:@{
            @"class": NSStringFromClass(superV.class) ?: @"nil",
            @"gestures": [self _gestureInfo:superV],
        }];
        superV = superV.superview;
        depth++;
    }
    return chain;
}

#pragma mark - 公开接口

+ (void)tapAtPoint:(CGPoint)point {
    // sendEvent: 必须在主线程（UIKit 线程约束）
    if (![NSThread isMainThread]) {
        dispatch_sync(dispatch_get_main_queue(), ^{ [self tapAtPoint:point]; });
        return;
    }
    UIWindow *window = XN_ActiveWindow();
    if (!window) return;
    UIView *view = window;
    @try {
        view = [window hitTest:point withEvent:nil] ?: window;
    } @catch (NSException *e) {
        NSLog(@"[XNTouch] hitTest error: %@", e.reason);
    }
    [self _reportTapDiagnostic:point view:view];      // 诊断上报命中的控件

    // 若是 UIControl（按钮），直接触发其 action（比合成触摸更可靠，不依赖手势识别）
    if ([view isKindOfClass:[UIControl class]]) {
        UIControl *ctrl = (UIControl *)view;
        @try {
            [ctrl sendActionsForControlEvents:UIControlEventTouchUpInside];
        } @catch (NSException *e) {
            NSLog(@"[XNTouch] sendActions error: %@", e.reason);
        }
        // 枚举所有 target-action 直接发送（覆盖 sendActions 漏掉的）
        @try {
            for (id target in [ctrl allTargets]) {
                NSArray *acts = [ctrl actionsForTarget:target forControlEvent:UIControlEventTouchUpInside];
                for (NSString *selStr in acts) {
                    SEL sel = NSSelectorFromString(selStr);
                    if (sel && [target respondsToSelector:sel]) {
                        [UIApplication.sharedApplication sendAction:sel to:target from:ctrl forEvent:nil];
                    }
                }
            }
        } @catch (NSException *e) {
            NSLog(@"[XNTouch] target-action error: %@", e.reason);
        }
    }

    // 直接触发手势识别器的 target-action（TikTok 按钮多用手势识别器，不响应 sendActions）。
    // ⚠️ v1.4.95 修复：合成触摸走不完手势状态机，TikTok 的 tap handler 普遍 if(state==Ended) 才执行，
    //    直接 performSelector 时手势 state 仍是 Possible → 被状态检查拦死（评论区 X 按钮实测：触摸命中但关不掉）。
    //    这里对 tap 类手势先把 state 置为 Ended（已识别）再触发 target，触发后还原。
    //    同时沿 superview 链上溯触发 tap 手势（mask 外点关闭的 gesture 挂在父视图上，命中视图自身无手势）。
    NSMutableArray<UIView *> *fireChain = [NSMutableArray array];
    [fireChain addObject:view];
    UIView *sup = view.superview;
    int depth = 0;
    while (sup && depth < 3) { [fireChain addObject:sup]; sup = sup.superview; depth++; }
    for (UIView *fireView in fireChain) {
        for (UIGestureRecognizer *gr in fireView.gestureRecognizers) {
            @try {
                if (![gr isKindOfClass:[UITapGestureRecognizer class]]) continue;  // 仅 tap：长按/拖拽触发会误动作
                UIGestureRecognizerState origState = gr.state;
                // v1.4.96：补 _touches —— TikTok 的 tap handler 除查 state 外还查
                // numberOfTouches/locationInView，合成触摸没被系统关联到手势，_touches 空 → handler 提前 return。
                UITouch *synTouch = [self _makeTouchAt:point phase:UITouchPhaseEnded view:fireView window:window];
                if (synTouch) {
                    [gr setValue:@[synTouch] forKey:@"_touches"];
                }
                [gr setValue:@(UIGestureRecognizerStateEnded) forKey:@"_state"];  // KVC 写私有 ivar，让 handler 的 state 检查通过
                NSArray *targets = [gr valueForKey:@"_targets"];
                for (id t in targets) {
                    id target = [t valueForKey:@"_target"];
                    id actionVal = [t valueForKey:@"_action"];
                    SEL sel = [actionVal isKindOfClass:[NSString class]] ? NSSelectorFromString(actionVal)
                                                                        : (SEL)(uintptr_t)[actionVal pointerValue];
                    if (sel && target && [target respondsToSelector:sel]) {
                        [target performSelector:sel withObject:gr];
                    }
                }
                [gr setValue:@(origState) forKey:@"_state"];
            } @catch (NSException *e) {
                NSLog(@"[XNTouch] gesture invoke error: %@", e.reason);
            }
        }
    }

    // 合成触摸（三重保险）：began → 短按下 → ended，模拟真实点击时序
    UITouch *touch = [self _makeTouchAt:point phase:UITouchPhaseBegan view:view window:window];
    if (!touch) return;
    NSSet *touchSet = [NSSet setWithObject:touch];

    // 1) 直接调用 view 的 touchesBegan（按钮常重写此方法，直接命中）
    @try {
        if ([view respondsToSelector:@selector(touchesBegan:withEvent:)]) {
            [view touchesBegan:touchSet withEvent:[self _makeEventWithTouch:touch]];
        }
    } @catch (NSException *e) { NSLog(@"[XNTouch] touchesBegan err: %@", e.reason); }

    // 2) 经 UIApplication 分发 began
    [self _dispatchWithTouch:touch window:window];

    // 3) 按下时长（真实点击约 50-100ms）
    [NSThread sleepForTimeInterval:0.06];

    // 4) 更新为 ended 并直接调 view 的 touchesEnded
    [self _updateTouch:touch phase:UITouchPhaseEnded at:point];
    @try {
        if ([view respondsToSelector:@selector(touchesEnded:withEvent:)]) {
            [view touchesEnded:touchSet withEvent:[self _makeEventWithTouch:touch]];
        }
    } @catch (NSException *e) { NSLog(@"[XNTouch] touchesEnded err: %@", e.reason); }

    // 5) 经 UIApplication 分发 ended
    [self _dispatchWithTouch:touch window:window];

    // 6) 点击后读取按钮状态（自验收：红心是否变红/收藏是否选中）
    [NSThread sleepForTimeInterval:0.15];
    [self _reportStateDiagnostic:view];
}

/// 上报控件当前状态（自验收：点击后按钮选中态/无障碍值变化即说明操作生效）
+ (void)_reportStateDiagnostic:(UIView *)view {
    @try {
        NSMutableDictionary *st = [NSMutableDictionary dictionary];
        if ([view isKindOfClass:[UIControl class]]) {
            UIControl *c = (UIControl *)view;
            st[@"isSelected"] = @(c.isSelected);
            st[@"isHighlighted"] = @(c.isHighlighted);
            st[@"isEnabled"] = @(c.isEnabled);
        }
        if (view.accessibilityValue) st[@"acc_value"] = view.accessibilityValue;
        if (view.accessibilityLabel) st[@"acc_label"] = view.accessibilityLabel;
        NSString *devId = [XNOWER sharedInstance].deviceId;
        if (devId.length > 0) {
            [XNURLProtocol sendMessage:@{@"type": @"state_diag", @"data": st} deviceId:devId];
        }
    } @catch (NSException *e) {}
}

+ (void)swipeFrom:(CGPoint)from to:(CGPoint)to {
    if (![NSThread isMainThread]) {
        dispatch_sync(dispatch_get_main_queue(), ^{ [self swipeFrom:from to:to]; });
        return;
    }
    UIWindow *window = XN_ActiveWindow();
    if (!window) return;
    UIView *view = window;
    @try {
        view = [window hitTest:from withEvent:nil] ?: window;
    } @catch (NSException *e) {
        NSLog(@"[XNTouch] swipe hitTest error: %@", e.reason);
    }
    UITouch *touch = [self _makeTouchAt:from phase:UITouchPhaseBegan view:view window:window];
    if (!touch) return;
    NSSet *touchSet = [NSSet setWithObject:touch];

    // began：直接调 view 的 touchesBegan + sendEvent（与 tap 生效方式一致）
    @try {
        if ([view respondsToSelector:@selector(touchesBegan:withEvent:)]) {
            [view touchesBegan:touchSet withEvent:[self _makeEventWithTouch:touch]];
        }
    } @catch (NSException *e) { NSLog(@"[XNTouch] swipe began err: %@", e.reason); }
    [self _dispatchWithTouch:touch window:window];

    // 10 步中间移动，让 UIScrollView/手势识别器识别为拖动
    int steps = 10;
    for (int i = 1; i <= steps; i++) {
        CGFloat t = (CGFloat)i / steps;
        CGPoint p = CGPointMake(from.x + (to.x - from.x) * t,
                                from.y + (to.y - from.y) * t);
        [self _updateTouch:touch phase:UITouchPhaseMoved at:p];
        @try {
            if ([view respondsToSelector:@selector(touchesMoved:withEvent:)]) {
                [view touchesMoved:touchSet withEvent:[self _makeEventWithTouch:touch]];
            }
        } @catch (NSException *e) { NSLog(@"[XNTouch] swipe moved err: %@", e.reason); }
        [self _dispatchWithTouch:touch window:window];
        [NSThread sleepForTimeInterval:0.016];
    }

    // ended：直接调 view 的 touchesEnded + sendEvent
    [self _updateTouch:touch phase:UITouchPhaseEnded at:to];
    @try {
        if ([view respondsToSelector:@selector(touchesEnded:withEvent:)]) {
            [view touchesEnded:touchSet withEvent:[self _makeEventWithTouch:touch]];
        }
    } @catch (NSException *e) { NSLog(@"[XNTouch] swipe ended err: %@", e.reason); }
    [self _dispatchWithTouch:touch window:window];
}

+ (void)swipeUp {
    CGSize s = [UIScreen mainScreen].bounds.size;
    [self swipeFrom:CGPointMake(s.width * 0.5, s.height * 0.78)
                 to:CGPointMake(s.width * 0.5, s.height * 0.22)];
}

+ (void)swipeDown {
    CGSize s = [UIScreen mainScreen].bounds.size;
    [self swipeFrom:CGPointMake(s.width * 0.5, s.height * 0.22)
                 to:CGPointMake(s.width * 0.5, s.height * 0.78)];
}

@end

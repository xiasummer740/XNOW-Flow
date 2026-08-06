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
    [[UIApplication sharedApplication] sendEvent:event];
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

#pragma mark - 公开接口

+ (void)tapAtPoint:(CGPoint)point {
    // sendEvent: 必须在主线程（UIKit 线程约束）
    if (![NSThread isMainThread]) {
        dispatch_sync(dispatch_get_main_queue(), ^{ [self tapAtPoint:point]; });
        return;
    }
    UIWindow *window = XN_ActiveWindow();
    if (!window) return;
    UIView *view = [window hitTest:point withEvent:nil] ?: window;
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

    // 直接触发 view 上所有手势识别器的 target-action（TikTok 按钮多用手势识别器，不响应 sendActions）
    for (UIGestureRecognizer *gr in view.gestureRecognizers) {
        @try {
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
        } @catch (NSException *e) {
            NSLog(@"[XNTouch] gesture invoke error: %@", e.reason);
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
}

+ (void)swipeFrom:(CGPoint)from to:(CGPoint)to {
    if (![NSThread isMainThread]) {
        dispatch_sync(dispatch_get_main_queue(), ^{ [self swipeFrom:from to:to]; });
        return;
    }
    UIWindow *window = XN_ActiveWindow();
    if (!window) return;
    UIView *view = [window hitTest:from withEvent:nil] ?: window;
    UITouch *touch = [self _makeTouchAt:from phase:UITouchPhaseBegan view:view window:window];
    if (!touch) return;
    [self _dispatchWithTouch:touch window:window];   // began

    // 10 步中间移动，让 UIScrollView/手势识别器识别为拖动
    int steps = 10;
    for (int i = 1; i <= steps; i++) {
        CGFloat t = (CGFloat)i / steps;
        CGPoint p = CGPointMake(from.x + (to.x - from.x) * t,
                                from.y + (to.y - from.y) * t);
        [self _updateTouch:touch phase:UITouchPhaseMoved at:p];
        [self _dispatchWithTouch:touch window:window];
        [NSThread sleepForTimeInterval:0.016];
    }

    [self _updateTouch:touch phase:UITouchPhaseEnded at:to];
    [self _dispatchWithTouch:touch window:window];   // ended
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

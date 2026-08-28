// XNTouchSimulator.m
// 通过 KVC 创建真实 UITouch / UIEvent 对象，经 [window sendEvent:] 注入，
// 使 TikTok 的 UIGestureRecognizer（点击/滑动/长按）真正触发。

#import "XNTouchSimulator.h"
#import "XNWindowHelper.h"
#import "XNOWER.h"
#import "XNURLProtocol.h"
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <objc/message.h>

@implementation XNTouchSimulator

// ============================================================
// v1.4.130 触摸盲区根治：IOHIDEvent 真实事件注入
// 背景证据：KVC 合成 UITouch 经 sendEvent: 注入时 touch 的 _gestureRecognizers 为空，
//   UIWindow 的 _sendTouchesForEvent: 不会关联手势识别器 → TikTok 手势收不到事件，
//   强置 state=Ended 只骗过 state 检查，handler 查 locationInView/numberOfTouches 仍失败。
//   实测坐标命中 hitTest 正确但事件不被消费 = 触摸盲区（like/follow/search/头像/切tab 全失效）。
// 方案：IOHIDEvent digitizer 事件注入（iOS 触摸系统真入口）。_handleHIDEvent: 收到后
//   UIKit 完整建 UITouch + 关联手势识别器，手势状态机正常走 → 根治盲区。
//   需匹配设备 ContextID（iOS 14+ 无匹配上下文会丢弃合成事件）。
// 降级：符号/ContextID 取不到时回退旧 KVC 合成触摸（总比不点强）。
// ============================================================

typedef struct __IOHIDEvent *XNIOHIDEventRef;
typedef struct __IOHIDEventSystemClient *XNIOHIDClientRef;
typedef struct __IOHIDServiceClient *XNIOHIDServiceRef;

// 私有 C 符号（dlsym 运行时解析，避免链接期依赖）
static XNIOHIDEventRef (*s_fnCreateDigitizer)(CFAllocatorRef, uint32_t, double, uint32_t, uint32_t,
                                              double, double, double, double,
                                              uint32_t, uint32_t, uint32_t, uint32_t);
static XNIOHIDClientRef (*s_fnSysClientCreate)(CFAllocatorRef);
static int (*s_fnSysClientSetMatching)(XNIOHIDClientRef, CFDictionaryRef, CFArrayRef);
static CFArrayRef (*s_fnSysClientCopyServices)(XNIOHIDClientRef);
static CFTypeRef (*s_fnServiceCopyProperty)(XNIOHIDServiceRef, CFStringRef);

// IOHIDDigitizerEvent 相位（私有头常量，硬编码稳定值）
#define XNHID_PHASE_RANGE     (1 << 0)
#define XNHID_PHASE_TOUCHING  (1 << 1)
#define XNHID_PHASE_CANCEL    (1 << 3)
// IOHIDDigitizerTransducerType.Hand
#define XNHID_TRANSDUCER_HAND (uint32_t)1
// HID usage（公开标准）：Digitizer page / TouchScreen usage
#define XNHID_PAGE_DIGITIZER  0x0d
#define XNHID_USAGE_TOUCH     0x04

+ (BOOL)_hidResolveSymbols {
    static dispatch_once_t once;
    static BOOL ok;
    dispatch_once(&once, ^{
        s_fnCreateDigitizer      = (typeof(s_fnCreateDigitizer))dlsym(RTLD_DEFAULT, "IOHIDEventCreateDigitizerEvent");
        s_fnSysClientCreate      = (typeof(s_fnSysClientCreate))dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientCreate");
        s_fnSysClientSetMatching = (typeof(s_fnSysClientSetMatching))dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientSetMatching");
        s_fnSysClientCopyServices= (typeof(s_fnSysClientCopyServices))dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientCopyServices");
        s_fnServiceCopyProperty  = (typeof(s_fnServiceCopyProperty))dlsym(RTLD_DEFAULT, "IOHIDServiceClientCopyProperty");
        ok = s_fnCreateDigitizer && s_fnSysClientCreate && s_fnSysClientSetMatching
             && s_fnSysClientCopyServices && s_fnServiceCopyProperty;
        if (!ok) {
            NSLog(@"[XNTouch] IOHIDEvent 符号解析失败，回退 KVC 合成触摸");
            [self _hidDiag:@"symbols_fail" data:@{}];
        } else {
            [self _hidDiag:@"symbols_ok" data:@{}];
        }
    });
    return ok;
}

/// HID 注入诊断上报（进 server.log，用于取证哪一步失败）
+ (void)_hidDiag:(NSString *)msg data:(NSDictionary *)data {
    @try {
        NSString *devId = [XNOWER sharedInstance].deviceId;
        if (devId.length == 0) return;
        NSMutableDictionary *d = [@{@"msg": msg} mutableCopy];
        if (data) [d addEntriesFromDictionary:data];
        [XNURLProtocol sendMessage:@{@"type": @"hid_diag", @"data": d} deviceId:devId];
    } @catch (NSException *e) {}
}

+ (uint32_t)_hidContextID {
    if (![self _hidResolveSymbols]) return 0;
    XNIOHIDClientRef client = s_fnSysClientCreate(kCFAllocatorDefault);
    if (!client) return 0;
    // 匹配 Digitizer/TouchScreen 服务（dict key 用字面量，避免依赖私有常量头）
    NSDictionary *matching = @{(id)CFSTR("PrimaryUsagePage"): @(XNHID_PAGE_DIGITIZER),
                               (id)CFSTR("PrimaryUsage"):    @(XNHID_USAGE_TOUCH)};
    s_fnSysClientSetMatching(client, (__bridge CFDictionaryRef)matching, NULL);
    CFArrayRef services = s_fnSysClientCopyServices(client);
    uint32_t ctx = 0;
    if (services) {
        for (CFIndex i = 0; i < CFArrayGetCount(services) && !ctx; i++) {
            XNIOHIDServiceRef sc = (XNIOHIDServiceRef)CFArrayGetValueAtIndex(services, i);
            CFTypeRef prop = s_fnServiceCopyProperty(sc, CFSTR("ContextID"));
            if (prop) {
                ctx = (uint32_t)[(__bridge NSNumber *)prop unsignedIntValue];
                CFRelease(prop);
            }
        }
        CFRelease(services);
    }
    CFRelease(client);
    return ctx;
}

+ (void)_hidInject:(uint32_t)phase at:(CGPoint)p ctx:(uint32_t)ctx {
    // IOHIDEvent 时间戳为纳秒
    double ts = CACurrentMediaTime() * 1e9;
    XNIOHIDEventRef event = s_fnCreateDigitizer(kCFAllocatorDefault, XNHID_TRANSDUCER_HAND, ts,
                                                phase, 0, p.x, p.y, 0, 0,
                                                0, ctx, 0, 1);
    if (!event) return;
    @try {
        UIApplication *app = [UIApplication sharedApplication];
        SEL sel = NSSelectorFromString(@"_handleHIDEvent:");
        if ([app respondsToSelector:sel]) {
            ((void(*)(id, SEL, XNIOHIDEventRef))objc_msgSend)(app, sel, event);
        }
    } @catch (NSException *e) {
        NSLog(@"[XNTouch] _handleHIDEvent 异常: %@", e.reason);
    }
    CFRelease(event);
}

+ (BOOL)_hidTapAtPoint:(CGPoint)p {
    if (![self _hidResolveSymbols]) return NO;
    uint32_t ctx = [self _hidContextID];
    if (!ctx) {
        [self _hidDiag:@"tap_ctx_zero" data:@{@"x": @(round(p.x)), @"y": @(round(p.y))}];
        NSLog(@"[XNTouch] IOHIDEvent 未取到 ContextID，回退 KVC");
        return NO;
    }
    [self _hidDiag:@"tap_hid" data:@{@"x": @(round(p.x)), @"y": @(round(p.y)), @"ctx": @(ctx)}];
    NSLog(@"[XNTouch] IOHIDEvent tap(%.0f,%.0f) ctx=%u", p.x, p.y, ctx);
    [self _hidInject:(XNHID_PHASE_RANGE | XNHID_PHASE_TOUCHING) at:p ctx:ctx];
    [NSThread sleepForTimeInterval:0.06];
    [self _hidInject:0 at:p ctx:ctx];
    return YES;
}

+ (BOOL)_hidSwipeFrom:(CGPoint)from to:(CGPoint)to {
    if (![self _hidResolveSymbols]) return NO;
    uint32_t ctx = [self _hidContextID];
    if (!ctx) {
        [self _hidDiag:@"swipe_ctx_zero" data:@{}];
        NSLog(@"[XNTouch] IOHIDEvent 未取到 ContextID，回退 KVC");
        return NO;
    }
    [self _hidDiag:@"swipe_hid" data:@{}];
    NSLog(@"[XNTouch] IOHIDEvent swipe (%.0f,%.0f)->(%.0f,%.0f) ctx=%u", from.x, from.y, to.x, to.y, ctx);
    [self _hidInject:(XNHID_PHASE_RANGE | XNHID_PHASE_TOUCHING) at:from ctx:ctx];
    int steps = 12;
    for (int i = 1; i <= steps; i++) {
        CGFloat k = (CGFloat)i / steps;
        CGPoint p = CGPointMake(from.x + (to.x - from.x) * k, from.y + (to.y - from.y) * k);
        [self _hidInject:(XNHID_PHASE_RANGE | XNHID_PHASE_TOUCHING) at:p ctx:ctx];
        [NSThread sleepForTimeInterval:0.016];
    }
    [self _hidInject:0 at:to ctx:ctx];
    return YES;
}

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
        // v1.4.131 根治触摸盲区根因：补全手势识别器关联。
        //   UIWindow _sendGesturesForEvent: 按 touch._gestureRecognizers 把 touches 分发给手势；
        //   之前 KVC 合成 touch 该数组为空 → 手势识别器收不到事件 → TikTok 全按钮
        //   坐标命中但事件不被消费（like/follow/search/头像/切tab 全盲区）。
        //   收集 view + superview 链（到 window）上所有手势挂到 touch，手势状态机即可正常识别。
        if (view) {
            NSMutableArray *grs = [NSMutableArray array];
            UIView *vv = view;
            int depth = 0;
            while (vv && depth < 8) {
                for (UIGestureRecognizer *gr in vv.gestureRecognizers) {
                    if (![grs containsObject:gr]) [grs addObject:gr];
                }
                vv = vv.superview;
                depth++;
            }
            if (grs.count) [touch setValue:grs forKey:@"_gestureRecognizers"];
        }
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
    // v1.4.130 首选 IOHIDEvent 真实注入（根治触摸盲区）；失败回退 KVC 合成触摸
    if ([self _hidTapAtPoint:point]) {
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
    [self tapView:view atPoint:point window:window reportDiagnostic:YES];
}

+ (void)tapView:(UIView *)view atPoint:(CGPoint)point {
    if (![NSThread isMainThread]) {
        dispatch_sync(dispatch_get_main_queue(), ^{ [self tapView:view atPoint:point]; });
        return;
    }
    [self tapView:view atPoint:point window:XN_ActiveWindow() reportDiagnostic:YES];
}

+ (void)tapView:(UIView *)view atPoint:(CGPoint)point window:(UIWindow *)window reportDiagnostic:(BOOL)diag {
    if (!view || !window) return;
    // v1.4.130 首选 IOHIDEvent 真实注入（坐标注入走真实 hitTest，盲区按钮恢复响应）；失败回退 KVC
    if ([self _hidTapAtPoint:point]) {
        return;
    }
    if (diag) [self _reportTapDiagnostic:point view:view];      // 诊断上报目标控件

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
    // v1.4.130 首选 IOHIDEvent 真实滑动（根治触摸盲区）；失败回退 KVC
    if ([self _hidSwipeFrom:from to:to]) {
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

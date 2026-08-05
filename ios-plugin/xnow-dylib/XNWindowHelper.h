// XNWindowHelper.h
// 兼容 iOS 13+ UIScene 的窗口获取工具
// 所有需要 UIWindow 的地方都用此函数代替 [UIApplication sharedApplication].keyWindow

#import <UIKit/UIKit.h>

/// 获取当前最活跃的 UIWindow（兼容 iOS 13+ UIScene + 多策略 fallback）
/// 跳过自己的 overlay 浮窗层（XNPassThroughWindow），否则命中测试会落在浮窗层而非 TikTok UI
/// 不限制 scene activationState，遍历所有可见窗口
static inline UIWindow *XN_ActiveWindow(void) {
    Class overlayCls = NSClassFromString(@"XNPassThroughWindow");
#define XN_IS_OVERLAY(w) (overlayCls && [(w) isKindOfClass:overlayCls])

    // 策略 1: iOS 13+ UIScene — 遍历所有 scene，不限制 activationState
    if (@available(iOS 13, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            // 优先 keyWindow
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow && !w.hidden && !XN_IS_OVERLAY(w)) return w;
            }
            // fallback: 任意可见的非 overlay 窗口
            for (UIWindow *w in ws.windows) {
                if (!w.hidden && !XN_IS_OVERLAY(w)) return w;
            }
        }
    }

    // 策略 2: App Delegate 的 window 属性
    id delegate = [UIApplication sharedApplication].delegate;
    if ([delegate respondsToSelector:@selector(window)]) {
        UIWindow *w = [delegate window];
        if (w && !w.hidden && !XN_IS_OVERLAY(w)) return w;
    }

    // 策略 3: 弃用的 keyWindow（iOS 16 仍然可用）
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (keyWindow && !keyWindow.hidden && !XN_IS_OVERLAY(keyWindow)) return keyWindow;

    return nil;
#undef XN_IS_OVERLAY
}

/// 获取根视图控制器
static inline UIViewController *XN_RootViewController(void) {
    UIWindow *w = XN_ActiveWindow();
    return w.rootViewController;
}

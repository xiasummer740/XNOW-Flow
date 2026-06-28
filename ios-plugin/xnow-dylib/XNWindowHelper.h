// XNWindowHelper.h
// 兼容 iOS 13+ UIScene 的窗口获取工具
// 所有需要 UIWindow 的地方都用此函数代替 [UIApplication sharedApplication].keyWindow

#import <UIKit/UIKit.h>

/// 获取当前最活跃的 UIWindow（兼容 iOS 13+ UIScene）
/// 当 app 使用 UISceneDelegate 时 keyWindow 返回 nil，此函数通过 Scene 遍历找到正确窗口
static inline UIWindow *XN_ActiveWindow(void) {
    // iOS 13+ 优先用 Scene-based API
    if (@available(iOS 13, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] &&
                scene.activationState == UISceneActivationStateForegroundActive) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                for (UIWindow *w in ws.windows) {
                    if (w.isKeyWindow) return w;
                }
                return [ws.windows firstObject]; // fallback
            }
        }
    }
    // iOS 12 以下
    return [UIApplication sharedApplication].keyWindow;
}

/// 获取根视图控制器
static inline UIViewController *XN_RootViewController(void) {
    UIWindow *w = XN_ActiveWindow();
    return w.rootViewController;
}

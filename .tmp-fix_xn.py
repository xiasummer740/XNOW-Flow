import re
with open('/root/xnow-build/XNWindowHelper.h', 'r') as fh:
    c = fh.read()
new_fn = """static inline UIWindow *XN_ActiveWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                if ([scene isKindOfClass:UIWindowScene.class]) {
                    UIWindowScene *ws = (UIWindowScene *)scene;
                    for (UIWindow *w in ws.windows) {
                        if (w.isKeyWindow) return w;
                    }
                }
            }
        }
    }
    for (UIWindow *w in UIApplication.sharedApplication.windows) {
        if (w.isKeyWindow) return w;
    }
    return UIApplication.sharedApplication.keyWindow;
}"""
c = re.sub(r'static inline UIWindow \*XN_ActiveWindow\(void\) \{.*?^\}', new_fn, c, count=1, flags=re.DOTALL | re.MULTILINE)
with open('/root/xnow-build/XNWindowHelper.h', 'w') as fh:
    fh.write(c)
print('Fixed XNWindowHelper.h')

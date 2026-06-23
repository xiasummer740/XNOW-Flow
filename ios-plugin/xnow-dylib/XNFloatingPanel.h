// XNFloatingPanel.h
// XNOW 控制浮窗 - 美观的半透明操作面板

#import <UIKit/UIKit.h>

@class XNFloatingPanel;

@protocol XNFloatingPanelDelegate <NSObject>
- (void)floatingPanelDidTapLike:(XNFloatingPanel *)panel;
- (void)floatingPanelDidTapFollow:(XNFloatingPanel *)panel;
- (void)floatingPanelDidTapScrollDown:(XNFloatingPanel *)panel;
- (void)floatingPanelDidTapScreenshot:(XNFloatingPanel *)panel;
- (void)floatingPanelDidTapCollectFans:(XNFloatingPanel *)panel;
- (void)floatingPanelDidTapCollectVideos:(XNFloatingPanel *)panel;
@end

@interface XNFloatingPanel : UIView

@property (nonatomic, weak) id<XNFloatingPanelDelegate> delegate;

/// 设置连接状态显示
- (void)setConnected:(BOOL)connected;
/// 设置设备 ID
- (void)setDeviceId:(NSString *)deviceId;
/// 设置服务器地址
- (void)setServerURL:(NSString *)serverURL;

/// 显示在指定窗口
- (void)showInWindow:(UIWindow *)window;
/// 隐藏
- (void)dismiss;

@end

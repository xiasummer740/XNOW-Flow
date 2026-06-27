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
@optional
/// 账号管理
- (void)floatingPanelDidTapAccountInfo:(XNFloatingPanel *)panel;
- (void)floatingPanelDidTapSmartBrowse:(XNFloatingPanel *)panel;
@end

@interface XNFloatingPanel : UIView

@property (nonatomic, weak) id<XNFloatingPanelDelegate> delegate;

/// 设置连接状态显示
- (void)setConnected:(BOOL)connected;
/// 设置设备 ID
- (void)setDeviceId:(NSString *)deviceId;
/// 设置服务器地址
- (void)setServerURL:(NSString *)serverURL;

/// 设置当前账号信息（昵称、头像URL、粉丝数）
- (void)setAccountInfo:(NSDictionary *)account;
/// 设置连接质量
- (void)setConnectionQuality:(NSString *)quality;

/// 显示在指定窗口
- (void)showInWindow:(UIWindow *)window;
/// 隐藏
- (void)dismiss;

@end

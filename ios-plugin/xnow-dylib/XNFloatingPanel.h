// XNFloatingPanel.h
// XNOW 控制浮窗 v2 — 三标签设计：账号 + 自动任务 + 手动操作

#import <UIKit/UIKit.h>

@class XNFloatingPanel;

@protocol XNFloatingPanelDelegate <NSObject>
@optional
// 手动操作
- (void)floatingPanelDidTapLike:(XNFloatingPanel *)panel;
- (void)floatingPanelDidTapFollow:(XNFloatingPanel *)panel;
- (void)floatingPanelDidTapScrollDown:(XNFloatingPanel *)panel;
- (void)floatingPanelDidTapScreenshot:(XNFloatingPanel *)panel;
- (void)floatingPanelDidTapCollectFans:(XNFloatingPanel *)panel;
- (void)floatingPanelDidTapCollectVideos:(XNFloatingPanel *)panel;
- (void)floatingPanelDidTapAccountInfo:(XNFloatingPanel *)panel;
- (void)floatingPanelDidTapConnectServer:(XNFloatingPanel *)panel;
- (void)floatingPanelDidTapSmartBrowse:(XNFloatingPanel *)panel;
- (void)floatingPanelDidTapClearData:(XNFloatingPanel *)panel;
- (void)floatingPanelDidTapDisconnect:(XNFloatingPanel *)panel;
- (void)floatingPanelDidTapCollectLikes:(XNFloatingPanel *)panel;
- (void)floatingPanelDidTapNurture:(XNFloatingPanel *)panel;
- (void)floatingPanelDidTapDownloadVideo:(XNFloatingPanel *)panel;
// 自动任务开关
- (void)floatingPanel:(XNFloatingPanel *)panel didToggleAutoLike:(BOOL)on;
- (void)floatingPanel:(XNFloatingPanel *)panel didToggleAutoFollow:(BOOL)on;
- (void)floatingPanel:(XNFloatingPanel *)panel didToggleAutoComment:(BOOL)on;
- (void)floatingPanel:(XNFloatingPanel *)panel didToggleAutoBrowse:(BOOL)on;
// 参数变更
- (void)floatingPanel:(XNFloatingPanel *)panel didChangeAutoLikeCount:(int)count delay:(int)delay;
- (void)floatingPanel:(XNFloatingPanel *)panel didChangeAutoFollowCount:(int)count delay:(int)delay;
- (void)floatingPanel:(XNFloatingPanel *)panel didChangeAutoCommentCount:(int)count delay:(int)delay text:(NSString *)text;
- (void)floatingPanel:(XNFloatingPanel *)panel didChangeAutoBrowseMinScrolls:(int)min maxScrolls:(int)max minDelay:(int)minDelay maxDelay:(int)maxDelay;
// 切换账号
- (void)floatingPanel:(XNFloatingPanel *)panel didSelectAccountId:(NSInteger)accountId;
- (void)floatingPanelDidRequestAccountList:(XNFloatingPanel *)panel;
// 商业激活 / 设备绑定
- (void)floatingPanel:(XNFloatingPanel *)panel didEnterLicenseKey:(NSString *)key;
- (void)floatingPanel:(XNFloatingPanel *)panel didSubmitBindingWithCode:(NSString *)code apiId:(NSString *)apiId;
@end

@interface XNFloatingPanel : UIView

@property (nonatomic, weak) id<XNFloatingPanelDelegate> delegate;

- (void)setConnected:(BOOL)connected;
- (void)setDeviceId:(NSString *)deviceId;
- (void)setServerURL:(NSString *)serverURL;
- (void)setAccountInfo:(NSDictionary *)account;
- (void)setConnectionQuality:(NSString *)quality;
- (void)setAccountList:(NSArray<NSDictionary *> *)accounts;
- (void)setActivated:(BOOL)activated expires:(NSString *)expires;
- (void)showActivationView;

- (void)showInWindow:(UIWindow *)window;
- (void)show;
- (void)dismiss;
- (void)addLog:(NSString *)message;
- (BOOL)isVisible;

@end

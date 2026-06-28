// XNOWER.h
// XNOW iOS 注入插件 - 主入口
// 编译时注入 TikTok，通过 WebSocket 连接 XNOW 后端实现远程控制

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

/// 插件配置
extern NSString *const kXnowDefaultServerURL;
extern NSString *const kXnowConfigKeyServerURL;
extern NSString *const kXnowConfigKeyEnabled;
extern NSString *const kXnowConfigKeyDebugOverlay;

/// 插件主控制器
@interface XNOWER : NSObject

@property (class, readonly) XNOWER *sharedInstance;

/// 是否已连接
@property (nonatomic, readonly) BOOL isConnected;
/// 设备唯一标识
@property (nonatomic, readonly) NSString *deviceId;
/// 后端服务器地址
@property (nonatomic, copy) NSString *serverURL;

/// 启动插件
- (void)start;
/// 停止插件
- (void)stop;

/// 显示控制浮窗（自动等待窗口就绪）
- (void)showFloatingPanel;
/// 从已知窗口直接显示浮窗（比自动查找更可靠）
- (void)showFloatingPanelInWindow:(UIWindow *)window;
/// 隐藏控制浮窗
- (void)hideFloatingPanel;

@end

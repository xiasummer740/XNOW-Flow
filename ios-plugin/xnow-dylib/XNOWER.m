// XNOWER.m
// XNOW iOS 注入插件 - 主入口 + 生命周期
// 作为 dylib 被 TikTok 加载后自动初始化

#import "XNOWER.h"
#import "WsClient.h"
#import "CommandEngine.h"
#import "DeviceStatus.h"
#import "TikTokHooks.h"
#import "XNFloatingPanel.h"
#import "AccountManager.h"
#import "XNWindowHelper.h"
#import <objc/runtime.h>

// ======== 默认配置 ========
NSString *const kXnowDefaultServerURL = @"ws://192.129.210.52:8000";
NSString *const kXnowConfigKeyServerURL = @"XNOWER_ServerURL";
NSString *const kXnowConfigKeyEnabled = @"XNOWER_Enabled";
static NSString *const kXnowDeviceIdKey = @"XNOWER_DeviceID";

// ======== 静态实例 ========
static XNOWER *gSharedInstance = nil;

// ======== C 构造函数 - dylib 加载时自动执行 ========
__attribute__((constructor)) static void XNOWERLoad() {
    // === 诊断红色条（20 秒延迟，等 TikTok 完全启动） ===
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIWindow *w = nil;
        id delegate = [UIApplication sharedApplication].delegate;
        if ([delegate respondsToSelector:@selector(window)]) {
            w = [delegate window];
        }
        if (!w) w = [UIApplication sharedApplication].keyWindow;
        if (w) {
            UIView *redBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w.bounds.size.width, 60)];
            redBar.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.85];
            redBar.tag = 99998;
            [w addSubview:redBar];
            UILabel *label = [[UILabel alloc] initWithFrame:redBar.bounds];
            label.text = @"XNOWER LOADED";
            label.textColor = [UIColor whiteColor];
            label.font = [UIFont boldSystemFontOfSize:22];
            label.textAlignment = NSTextAlignmentCenter;
            [redBar addSubview:label];
        }
    });

    // 延迟 2 秒启动主逻辑
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [[XNOWER sharedInstance] start];
    });
}

// ======== 析构函数（dylib 卸载时） ========
__attribute__((destructor)) static void XNOWERUnload() {
    [[XNOWER sharedInstance] stop];
}

// ======== 实现 ========
@interface XNOWER () <WsClientDelegate, XNFloatingPanelDelegate>
@property (nonatomic, strong) WsClient *wsClient;
@property (nonatomic, strong) CommandEngine *cmdEngine;
@property (nonatomic, strong) DeviceStatus *deviceStatus;
@property (nonatomic, strong) XNFloatingPanel *floatingPanel;
@property (nonatomic, strong) UIWindow *floatingFloatWindow;
@property (nonatomic, strong) dispatch_queue_t workerQueue;
@property (nonatomic, assign) BOOL floatingPanelVisible;
@end

@implementation XNOWER

+ (XNOWER *)sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSharedInstance = [[self alloc] init];
    });
    return gSharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _workerQueue = dispatch_queue_create("com.xnow.plugin", DISPATCH_QUEUE_SERIAL);
        _deviceStatus = [[DeviceStatus alloc] init];
        _cmdEngine = [[CommandEngine alloc] init];
        _isConnected = NO;
        _floatingPanelVisible = NO;

        // 读取配置
        NSString *savedURL = [[NSUserDefaults standardUserDefaults]
                               stringForKey:kXnowConfigKeyServerURL];
        _serverURL = savedURL ?: kXnowDefaultServerURL;

        // 生成或恢复设备 ID
        NSString *savedId = [[NSUserDefaults standardUserDefaults]
                              stringForKey:kXnowDeviceIdKey];
        if (savedId) {
            _deviceId = savedId;
        } else {
            NSString *vendorID = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
            NSString *shortID = vendorID.length >= 8 ? [vendorID substringToIndex:8] :
                                 [NSUUID UUID].UUIDString;
            _deviceId = [NSString stringWithFormat:@"iphone_%@", shortID];
            [[NSUserDefaults standardUserDefaults] setObject:_deviceId forKey:kXnowDeviceIdKey];
        }

        // 设置账号上报回调
        __weak typeof(self) weakSelf = self;
        [[AccountManager sharedManager] setReportCallback:^(NSDictionary *msg) {
            [weakSelf.wsClient sendMessage:msg];
        }];
    }
    return self;
}

- (void)start {
    BOOL enabled = [[NSUserDefaults standardUserDefaults] boolForKey:kXnowConfigKeyEnabled];
    if (!enabled) {
        // 默认启用，首次运行自动打开
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kXnowConfigKeyEnabled];
    }

    dispatch_async(_workerQueue, ^{
        // 安装 TikTok hooks
        [TikTokHooks installHooks];

        // 启动设备状态监控
        [self.deviceStatus startMonitoring];

        // 显示控制浮窗
        [self showFloatingPanel];

        // 连接 WebSocket
        [self connectWebSocket];
    });
}

- (void)stop {
    dispatch_async(_workerQueue, ^{
        [self.wsClient disconnect];
        [self.deviceStatus stopMonitoring];
        self.wsClient = nil;
    });
}

- (void)connectWebSocket {
    if (self.wsClient) {
        [self.wsClient disconnect];
        self.wsClient = nil;
    }

    self.wsClient = [[WsClient alloc] init];
    self.wsClient.delegate = self;
    [self.wsClient connectToServer:self.serverURL deviceId:self.deviceId];
}

// ======== WsClientDelegate ========

- (void)wsClientDidConnect:(WsClient *)client {
    _isConnected = YES;

    // 立即上报设备状态（含账号信息）
    NSMutableDictionary *status = [[self.deviceStatus collectStatus] mutableCopy];
    if ([AccountManager sharedManager].currentAccount) {
        status[@"current_account"] = [AccountManager sharedManager].currentAccount;
    }
    [client sendMessage:@{
        @"type": @"status",
        @"data": status
    }];

    // 启动定期心跳
    [self startHeartbeat];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.floatingPanel setConnected:YES];
    });

    // 连接后立即检测并上报当前账号
    [[AccountManager sharedManager] detectCurrentAccountWithCompletion:^(NSDictionary *account) {
        if (account) {
            [client sendMessage:@{
                @"type": @"account_update",
                @"data": account,
            }];
        }
    }];
}

- (void)wsClientDidDisconnect:(WsClient *)client error:(NSError *)error {
    _isConnected = NO;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.floatingPanel setConnected:NO];
    });

    // 自动重连（指数退避由 WsClient 内部处理）
}

- (void)wsClient:(WsClient *)client didReceiveMessage:(NSDictionary *)message {
    NSString *type = message[@"type"];
    if ([type isEqualToString:@"command"]) {
        // 执行指令
        __weak typeof(self) weakSelf = self;
        [self.cmdEngine executeCommand:message completion:^(NSDictionary *result) {
            [weakSelf.wsClient sendMessage:@{
                @"type": @"result",
                @"data": result
            }];
        }];
    } else if ([type isEqualToString:@"ping"]) {
        // 回复 pong
        [client sendMessage:@{@"type": @"pong"}];
    }
}

- (void)startHeartbeat {
    dispatch_async(self.workerQueue, ^{
        // 每 30 秒发一次心跳
        dispatch_source_t timer = dispatch_source_create(
            DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
            dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0));
        dispatch_source_set_timer(timer,
            dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC),
            30 * NSEC_PER_SEC, 5 * NSEC_PER_SEC);

        dispatch_source_set_event_handler(timer, ^{
            if (self.isConnected) {
                [self.wsClient sendMessage:@{@"type": @"ping"}];
                // 顺便上报状态（含账号信息）
                NSMutableDictionary *status = [[self.deviceStatus collectStatus] mutableCopy];
                if ([AccountManager sharedManager].currentAccount) {
                    status[@"current_account"] = [AccountManager sharedManager].currentAccount;
                }
                [self.wsClient sendMessage:@{
                    @"type": @"status",
                    @"data": status
                }];
            }
        });
        dispatch_resume(timer);
        // 保存 timer 防止释放
        objc_setAssociatedObject(self, @selector(startHeartbeat), timer,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

// ======== 浮动控制面板 ========

- (void)showFloatingPanel {
    if (self.floatingPanelVisible) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self _tryShowPanel:0];
    });
}

- (void)_tryShowPanel:(NSInteger)attempt {
    if (self.floatingPanelVisible) return;
    UIWindow *w = XN_ActiveWindow();
    if (w) {
        [self _showPanelOnTopWithScene:w.windowScene];
        return;
    }
    if (attempt < 15) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self _tryShowPanel:attempt + 1];
        });
    }
}

/// 替代方案：直接用 App Delegate 窗口添加红色诊断条（跳过 scene/XN_ActiveWindow）
- (void)_showDiagnosticBar {
    UIWindow *w = nil;
    id delegate = [UIApplication sharedApplication].delegate;
    if ([delegate respondsToSelector:@selector(window)]) {
        w = [delegate window];
    }
    if (!w) w = [UIApplication sharedApplication].keyWindow;
    if (!w) return;

    UIView *redBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w.bounds.size.width, 60)];
    redBar.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.85];
    redBar.tag = 99999;
    [w addSubview:redBar];

    UILabel *label = [[UILabel alloc] initWithFrame:redBar.bounds];
    label.text = @"XNOWER LOADED";
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont boldSystemFontOfSize:20];
    label.textAlignment = NSTextAlignmentCenter;
    [redBar addSubview:label];
}

/// 在独立的浮动窗口上显示面板（确保在最顶层，不会被 TikTok UI 遮挡）
- (void)_showPanelOnTopWithScene:(UIWindowScene *)scene {
    if (self.floatingPanelVisible) return;

    // 先显示诊断条（确认代码跑到了这里）
    [self _showDiagnosticBar];

    // 创建独立浮动窗口
    UIWindow *floatWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    if (@available(iOS 13, *)) {
        if (scene) {
            floatWindow.windowScene = scene;
        } else {
            // 尝试找任意 scene
            for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
                if ([s isKindOfClass:[UIWindowScene class]]) {
                    floatWindow.windowScene = (UIWindowScene *)s;
                    break;
                }
            }
        }
    }
    floatWindow.windowLevel = 3000;
    floatWindow.backgroundColor = [UIColor clearColor];
    floatWindow.hidden = NO;

    self.floatingFloatWindow = floatWindow;
    self.floatingPanel = [[XNFloatingPanel alloc] init];
    self.floatingPanel.delegate = self;
    [self.floatingPanel setDeviceId:self.deviceId];
    [self.floatingPanel setServerURL:self.serverURL];
    [self.floatingPanel setConnected:self.isConnected];
    [self.floatingPanel showInWindow:floatWindow];
    self.floatingPanelVisible = YES;

    NSLog(@"[XNOWER] Floating panel shown on dedicated window");
}

- (void)hideFloatingPanel {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.floatingPanel dismiss];
        self.floatingFloatWindow.hidden = YES;
        self.floatingFloatWindow = nil;
        self.floatingPanel = nil;
        self.floatingPanelVisible = NO;
    });
}

#pragma mark - XNFloatingPanelDelegate

- (void)floatingPanelDidTapLike:(XNFloatingPanel *)panel {
    [self.cmdEngine executeCommand:@{@"action": @"like"} completion:^(NSDictionary *result) {
        NSLog(@"[XNOWER] Like: %@", result[@"status"]);
    }];
}

- (void)floatingPanelDidTapFollow:(XNFloatingPanel *)panel {
    [self.cmdEngine executeCommand:@{@"action": @"follow"} completion:^(NSDictionary *result) {
        NSLog(@"[XNOWER] Follow: %@", result[@"status"]);
    }];
}

- (void)floatingPanelDidTapScrollDown:(XNFloatingPanel *)panel {
    [self.cmdEngine executeCommand:@{@"action": @"scroll_down"} completion:^(NSDictionary *result) {
        NSLog(@"[XNOWER] Scroll: %@", result[@"status"]);
    }];
}

- (void)floatingPanelDidTapScreenshot:(XNFloatingPanel *)panel {
    [self.cmdEngine executeCommand:@{@"action": @"screenshot"} completion:^(NSDictionary *result) {
        NSLog(@"[XNOWER] Screenshot: %@", result[@"status"]);
    }];
}

- (void)floatingPanelDidTapCollectFans:(XNFloatingPanel *)panel {
    [self.cmdEngine executeCommand:@{@"action": @"collect_fans", @"params": @{@"count": @20}}
                        completion:nil];
}

- (void)floatingPanelDidTapCollectVideos:(XNFloatingPanel *)panel {
    [self.cmdEngine executeCommand:@{@"action": @"collect_videos", @"params": @{@"count": @10}}
                        completion:nil];
}

- (void)floatingPanelDidTapAccountInfo:(XNFloatingPanel *)panel {
    // 检测并上报当前账号
    [[AccountManager sharedManager] detectCurrentAccountWithCompletion:^(NSDictionary *account) {
        if (account) {
            [self.wsClient sendMessage:@{
                @"type": @"account_update",
                @"data": account
            }];
        }
    }];
}

- (void)floatingPanelDidTapSmartBrowse:(XNFloatingPanel *)panel {
    [self.cmdEngine executeCommand:@{
        @"action": @"smart_browse",
        @"params": @{@"min_scrolls": @5, @"max_scrolls": @12,
                     @"min_delay": @3, @"max_delay": @8}
    } completion:^(NSDictionary *result) {
        NSLog(@"[XNOWER] Smart browse done: %@", result);
    }];
}

@end

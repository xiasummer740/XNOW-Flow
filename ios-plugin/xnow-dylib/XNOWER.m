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
#import <pthread.h>

// ======== 默认配置 ========
NSString *const kXnowDefaultServerURL = @"ws://192.129.210.52:8000";
NSString *const kXnowConfigKeyServerURL = @"XNOWER_ServerURL";
NSString *const kXnowConfigKeyEnabled = @"XNOWER_Enabled";
static NSString *const kXnowDeviceIdKey = @"XNOWER_DeviceID";

// ======== 静态实例 ========
static XNOWER *gSharedInstance = nil;

// ======== 启动由 XNStartup.m 的 +load 完成 ========

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
    NSLog(@"[XNOWER] 🚀 start() 已执行 — dylib 加载成功");

    // 诊断条：2秒后显示
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self _showDiagnosticBar];
    });

    // 浮窗：4秒后显示（仅 UI 面板，不启动后台服务）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self showFloatingPanel];
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
    if (self.floatingPanelVisible) {
        NSLog(@"[XNOWER] 浮窗已显示，跳过");
        return;
    }

    NSLog(@"[XNOWER] 触发浮窗显示...");
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _tryAttachPanel];
    });
}

/// 找到 TikTok 的 keyWindow 并直接加上浮窗（和诊断条同一策略，已被验证可靠）
- (void)_tryAttachPanel {
    if (self.floatingPanelVisible) return;

    UIWindow *targetWindow = nil;

    // 策略1: App Delegate 的 window
    id delegate = [UIApplication sharedApplication].delegate;
    if ([delegate respondsToSelector:@selector(window)]) {
        targetWindow = [delegate window];
        if (targetWindow && !targetWindow.hidden)
            NSLog(@"[XNOWER] 窗口来源: App Delegate");
    }

    // 策略2: keyWindow（iOS 16+ 仍可用）
    if (!targetWindow || targetWindow.hidden) {
        targetWindow = [UIApplication sharedApplication].keyWindow;
        if (targetWindow && !targetWindow.hidden)
            NSLog(@"[XNOWER] 窗口来源: keyWindow");
    }

    // 策略3: UIScene 遍历
    if (!targetWindow || targetWindow.hidden) {
        if (@available(iOS 13, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (![scene isKindOfClass:[UIWindowScene class]]) continue;
                UIWindowScene *ws = (UIWindowScene *)scene;
                for (UIWindow *w in ws.windows) {
                    if (!w.hidden && w.rootViewController) {
                        targetWindow = w;
                        break;
                    }
                }
                if (targetWindow) break;
            }
            if (targetWindow && !targetWindow.hidden)
                NSLog(@"[XNOWER] 窗口来源: UIScene");
        }
    }

    if (!targetWindow || targetWindow.hidden) {
        // 还没找到窗口，继续重试（最多20秒）
        static NSInteger retryCount = 0;
        retryCount++;
        NSLog(@"[XNOWER] 窗口未就绪，重试 %ld/20", (long)retryCount);
        if (retryCount < 20) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [self _tryAttachPanel];
            });
        } else {
            NSLog(@"[XNOWER] ⚠️ 窗口查找超时（20次重试均失败）");
            retryCount = 0;
        }
        return;
    }

    // 创建浮窗，直接加到目标窗口上（和诊断条 _showDiagnosticBar 同样的策略）
    self.floatingPanel = [[XNFloatingPanel alloc] init];
    self.floatingPanel.delegate = self;
    [self.floatingPanel setDeviceId:self.deviceId];
    [self.floatingPanel setServerURL:self.serverURL];
    [self.floatingPanel setConnected:self.isConnected];

    [targetWindow addSubview:self.floatingPanel];
    [targetWindow bringSubviewToFront:self.floatingPanel];
    self.floatingPanelVisible = YES;

    NSLog(@"[XNOWER] ✅ 浮窗已添加到窗口 (frame=%@)", NSStringFromCGRect(self.floatingPanel.frame));

    // 入场动画
    self.floatingPanel.transform = CGAffineTransformMakeScale(0.5, 0.5);
    self.floatingPanel.alpha = 0;
    [UIView animateWithDuration:0.3
                          delay:0.5
         usingSpringWithDamping:0.6
          initialSpringVelocity:0.8
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.floatingPanel.transform = CGAffineTransformIdentity;
        self.floatingPanel.alpha = 1;
    } completion:nil];
}

/// 诊断条：红色顶部条，确认代码已执行到此（dylib 已加载 + start 已运行）
- (void)_showDiagnosticBar {
    UIWindow *w = XN_ActiveWindow();
    if (!w) return;

    // 避免重复添加
    if ([w viewWithTag:99999]) return;

    CGFloat barHeight = 60;
    UIView *redBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w.bounds.size.width, barHeight)];
    redBar.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.85];
    redBar.tag = 99999;
    redBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [w addSubview:redBar];
    [w bringSubviewToFront:redBar];

    UILabel *label = [[UILabel alloc] initWithFrame:redBar.bounds];
    label.text = @"XNOWER LOADED";
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont boldSystemFontOfSize:20];
    label.textAlignment = NSTextAlignmentCenter;
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [redBar addSubview:label];

    NSLog(@"[XNOWER] ✅ 诊断条已显示 — dylib 加载 + start() 执行成功");
}

- (void)hideFloatingPanel {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.floatingPanel dismiss];
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

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
#import "AccountPool.h"
#import "AccountSwitcher.h"
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
@property (nonatomic, strong) UIWindow *overlayWindow;
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
        NSString *action = message[@"action"] ?: @"";

        if ([action isEqualToString:@"batch_login"]) {
            // === 批量登录 ===
            NSDictionary *params = message[@"params"] ?: @{};
            NSArray *accountIds = params[@"account_ids"] ?: @[];
            NSDictionary *credentials = message[@"credentials"] ?: @{};

            if (accountIds.count == 0) {
                [client sendMessage:@{@"type": @"result", @"data": @{@"action": @"batch_login", @"status": @"failed", @"message": @"未指定账号"}}];
                return;
            }

            // 1. 把下发的凭证存到本地 AccountPool
            for (NSString *aid in credentials) {
                NSDictionary *creds = credentials[aid];
                if (creds) [[AccountPool sharedPool] upsertAccount:creds];
            }

            // 2. 执行批量登录
            [[AccountSwitcher sharedSwitcher] batchLogin:accountIds completion:^(NSInteger done, NSInteger total, BOOL final, NSDictionary *result) {
                [client sendMessage:@{
                    @"type": @"result",
                    @"data": @{
                        @"action": @"batch_login",
                        @"status": final ? @"complete" : @"progress",
                        @"done": @(done),
                        @"total": @(total),
                        @"last_result": result ?: @{},
                    }
                }];
            }];
        } else {
            // === 普通指令 ===
            __weak typeof(self) weakSelf = self;
            [self.cmdEngine executeCommand:message completion:^(NSDictionary *result) {
                [weakSelf.wsClient sendMessage:@{
                    @"type": @"result",
                    @"data": result
                }];
            }];
        }
    } else if ([type isEqualToString:@"sync_accounts"]) {
        // 同步账号池到本地
        NSArray *accounts = message[@"accounts"] ?: @[];
        [[AccountPool sharedPool] syncAccounts:accounts];
        [client sendMessage:@{@"type": @"sync_accounts_ack", @"data": @{@"count": @(accounts.count)}}];
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

/// 用独立 UIWindow 显示浮窗（最高层级，TikTok 视图变化不影响）
- (void)_tryAttachPanel {
    if (self.floatingPanelVisible) return;

    // 获取当前活跃 UIWindowScene（iOS 13+ 必须用 scene 创建窗口）
    UIWindowScene *activeScene = nil;
    if (@available(iOS 13, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] &&
                scene.activationState == UISceneActivationStateForegroundActive) {
                activeScene = (UIWindowScene *)scene;
                break;
            }
        }
        // fallback: 任何可见 scene
        if (!activeScene) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    activeScene = (UIWindowScene *)scene;
                    break;
                }
            }
        }
    }

    // 创建独立 UIWindow（永远在最顶层，不依赖 TikTok 的视图层级）
    self.overlayWindow = nil;
    UIWindow *overlayWindow;
    if (@available(iOS 13, *)) {
        overlayWindow = [[UIWindow alloc] initWithWindowScene:activeScene];
    } else {
        overlayWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    }
    overlayWindow.windowLevel = UIWindowLevelStatusBar + 100;
    overlayWindow.backgroundColor = [UIColor clearColor];
    overlayWindow.userInteractionEnabled = YES;

    // 创建浮窗
    self.floatingPanel = [[XNFloatingPanel alloc] init];
    if (!self.floatingPanel) {
        NSLog(@"[XNOWER] ⚠️ 浮窗创建失败（alloc 返回 nil）");
        return;
    }
    self.floatingPanel.delegate = self;
    [self.floatingPanel setDeviceId:self.deviceId];
    [self.floatingPanel setServerURL:self.serverURL];
    [self.floatingPanel setConnected:self.isConnected];

    [overlayWindow addSubview:self.floatingPanel];
    overlayWindow.hidden = NO;  // 显示窗口
    self.overlayWindow = overlayWindow;
    self.floatingPanelVisible = YES;

    NSLog(@"[XNOWER] ✅ 浮窗独立窗口已创建 (frame=%@)", NSStringFromCGRect(self.floatingPanel.frame));

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
        self.overlayWindow.hidden = YES;
        self.overlayWindow = nil;
        self.floatingPanelVisible = NO;
    });
}

#pragma mark - XNFloatingPanelDelegate

/// 通过 HTTP API 向后端发送指令
- (void)_sendCommandToBackend:(NSString *)action params:(NSDictionary *)params {
    NSString *baseURL = self.serverURL ?: @"http://localhost:8000";
    // ws:// -> http:// 转换（手机存的 serverURL 可能是 ws:// 开头）
    baseURL = [baseURL stringByReplacingOccurrencesOfString:@"^ws(s)?://" withString:@"http$1://"
                                                    options:NSRegularExpressionSearch range:NSMakeRange(0, baseURL.length)];
    if (![baseURL hasPrefix:@"http"]) {
        baseURL = [NSString stringWithFormat:@"http://%@", baseURL];
    }
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/biz/v2/commands/report/", baseURL]];
    if (!url) { NSLog(@"[XNOWER] 无效URL: %@", baseURL); return; }

    NSDictionary *payload = @{
        @"action": action ?: @"",
        @"device_id": self.deviceId ?: @"unknown",
        @"params": params ?: @{},
    };
    NSError *jsonErr = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonErr];
    if (!jsonData) { NSLog(@"[XNOWER] JSON错误: %@", jsonErr); return; }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = jsonData;
    req.timeoutInterval = 10;

    [[[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
            NSLog(@"[XNOWER] 指令 %@: %@", action, e ? [@"失败: " stringByAppendingString:e.localizedDescription] : @"✅ 已发送");
        }] resume];
}

- (void)floatingPanelDidTapLike:(XNFloatingPanel *)panel {
    [self _sendCommandToBackend:@"like" params:nil];
    @try { [self.cmdEngine executeCommand:@{@"action": @"like"} completion:nil]; } @catch (id e) {}
}

- (void)floatingPanelDidTapFollow:(XNFloatingPanel *)panel {
    [self _sendCommandToBackend:@"follow" params:nil];
    @try { [self.cmdEngine executeCommand:@{@"action": @"follow"} completion:nil]; } @catch (id e) {}
}

- (void)floatingPanelDidTapScrollDown:(XNFloatingPanel *)panel {
    [self _sendCommandToBackend:@"scroll_down" params:nil];
    @try { [self.cmdEngine executeCommand:@{@"action": @"scroll_down"} completion:nil]; } @catch (id e) {}
}

- (void)floatingPanelDidTapScreenshot:(XNFloatingPanel *)panel {
    [self _sendCommandToBackend:@"screenshot" params:nil];
    @try { [self.cmdEngine executeCommand:@{@"action": @"screenshot"} completion:nil]; } @catch (id e) {}
}

- (void)floatingPanelDidTapCollectFans:(XNFloatingPanel *)panel {
    [self _sendCommandToBackend:@"collect_fans" params:@{@"count": @20}];
}

- (void)floatingPanelDidTapCollectVideos:(XNFloatingPanel *)panel {
    [self _sendCommandToBackend:@"collect_videos" params:@{@"count": @10}];
}

- (void)floatingPanelDidTapAccountInfo:(XNFloatingPanel *)panel {
    [self _sendCommandToBackend:@"account_info" params:nil];
}

- (void)floatingPanelDidTapSmartBrowse:(XNFloatingPanel *)panel {
    [self _sendCommandToBackend:@"smart_browse" params:@{@"min_scrolls": @5, @"max_scrolls": @12}];
}

@end

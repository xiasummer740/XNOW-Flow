// XNOWER.m
// XNOW iOS 注入插件 - 主入口 + 生命周期
// 作为 dylib 被 TikTok 加载后自动初始化

#import "XNOWER.h"
#import "WsClient.h"
#import "CommandEngine.h"
#import "DeviceStatus.h"
#import "TikTokHooks.h"
#import "XNURLProtocol.h"
#import "XNFloatingPanel.h"
#import "AccountManager.h"
#import "AccountPool.h"
#import "AccountSwitcher.h"
#import "XNWindowHelper.h"
#import <objc/runtime.h>
#import <pthread.h>

// ======== 默认配置 ========
NSString *const kXnowDefaultServerURL = @"wss://yunkong.taikon.top";
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
@property (nonatomic, strong) dispatch_source_t piggybackTimer;
@property (nonatomic, strong) dispatch_source_t heartbeatTimer;
@property (nonatomic, copy) NSString *deviceSecret;
@property (nonatomic, copy) NSString *licenseKey;
@property (nonatomic, copy) NSString *licenseExpiry;
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

        // 生成或恢复设备 ID（优先使用绑定时设置的）
        // 注意：XN_BindDeviceID 存的是"手机序号"(code，如 "1")，不是完整设备ID，
        // 必须拼上机器码短码，否则 device_id 会退化成纯 "1" 导致激活错绑。
        NSString *bindCode = [[NSUserDefaults standardUserDefaults]
                             stringForKey:@"XN_BindDeviceID"];
        if (bindCode.length > 0) {
            NSString *vendorID = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
            NSString *shortID = vendorID.length >= 8 ? [vendorID substringToIndex:8] :
                                 [NSUUID UUID].UUIDString;
            _deviceId = [NSString stringWithFormat:@"iphone_%@_%@", bindCode, shortID];
        } else {
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
        }

        // 生成/恢复设备共享密钥（设备端点鉴权用）
        NSString *savedSecret = [[NSUserDefaults standardUserDefaults] stringForKey:@"XN_DeviceSecret"];
        if (savedSecret.length == 0) {
            savedSecret = [NSUUID UUID].UUIDString;
            [[NSUserDefaults standardUserDefaults] setObject:savedSecret forKey:@"XN_DeviceSecret"];
        }
        _deviceSecret = savedSecret;

        // 开发者模式（发布时注释掉此行）
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"XN_DevMode"];

        // 注册 piggyback 指令通知
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_onPiggybackCommand:)
                                                     name:@"XNPiggybackCommand"
                                                   object:nil];

        // 设置账号上报回调（走 piggyback）
        __weak typeof(self) weakSelf = self;
        [[AccountManager sharedManager] setReportCallback:^(NSDictionary *msg) {
            [XNURLProtocol sendMessage:msg deviceId:weakSelf.deviceId];
        }];
    }
    return self;
}

- (void)start {
    NSLog(@"[XNOWER] 🚀 start() 已执行 — dylib 加载成功");

    // 只显示浮窗，不自动连 WS — BH TikTok 检测到外部连接会 exit()
    // 用户可在浮窗菜单中手动点击"连接到服务器"
    [self showFloatingPanel];
}

/// 添加操作日志（显示在左上角透明日志窗口）
- (void)addLog:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[XNOWER][Log] %@", msg);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.floatingPanel addLog:msg];
    });
}

- (void)stop {
    [self stopPiggybackPolling];
    [self stopHeartbeat];
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

    // 构建完整 URL（含 API ID 查询参数）
    NSString *baseURL = kXnowDefaultServerURL;
    NSString *apiId = [[NSUserDefaults standardUserDefaults] stringForKey:@"XN_BindAPIID"] ?: @"";
    NSString *devCode = [[NSUserDefaults standardUserDefaults] stringForKey:@"XN_BindDeviceID"] ?: @"";
    NSString *fullURL;
    if (apiId.length > 0) {
        fullURL = [NSString stringWithFormat:@"%@?api_id=%@&device_code=%@", baseURL, apiId, devCode];
    } else {
        fullURL = baseURL;
    }
    [self.wsClient connectToServer:fullURL deviceId:self.deviceId];
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

    // 连接后自动上报已保存的绑定信息
    NSString *bindDevId = [[NSUserDefaults standardUserDefaults] stringForKey:@"XN_BindDeviceID"] ?: @"";
    NSString *bindApiId = [[NSUserDefaults standardUserDefaults] stringForKey:@"XN_BindAPIID"] ?: @"";
    if (bindDevId.length > 0 && bindApiId.length > 0) {
        [client sendMessage:@{
            @"type": @"bind_info",
            @"data": @{@"device_code": bindDevId, @"api_id": bindApiId}
        }];
        [self addLog:[NSString stringWithFormat:@"已上报绑定信息(设备%@ API:%@)", bindDevId, bindApiId]];
    }

    // 连接后立即检测并上报当前账号
    [[AccountManager sharedManager] detectCurrentAccountWithCompletion:^(NSDictionary *account) {
        if (account) {
            [client sendMessage:@{
                @"type": @"account_update",
                @"data": account,
            }];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.floatingPanel setAccountInfo:account];
            });
        }
    }];
}

- (void)wsClientDidDisconnect:(WsClient *)client error:(NSError *)error {
    _isConnected = NO;

    [self addLog:@"❌ %@", [XNOWER _translateError:error.localizedDescription]];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.floatingPanel setConnected:NO];
    });
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
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.floatingPanel setAccountList:accounts];
        });
        [client sendMessage:@{@"type": @"sync_accounts_ack", @"data": @{@"count": @(accounts.count)}}];
    } else if ([type isEqualToString:@"ping"]) {
        // 回复 pong
        [client sendMessage:@{@"type": @"pong"}];
    }
}

// ======== Piggyback 指令处理（借TikTok网络栈通信） ========

/// 收到后端下发的指令（经 XNURLProtocol 通知）
- (void)_onPiggybackCommand:(NSNotification *)note {
    NSDictionary *cmd = note.userInfo[@"command"];
    if (![cmd isKindOfClass:[NSDictionary class]]) return;
    [self _executePiggybackCommand:cmd];
}

/// 执行指令并回传结果（浮窗显示操作日志）
/// 英文系统错误 → 中文（用户友好）
+ (NSString *)_translateError:(NSString *)msg {
    if (!msg) return @"连接断开";
    static NSDictionary *map = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"internet connection appears to be offline": @"网络连接不可用",
            @"offline": @"网络离线",
            @"timed out": @"连接超时",
            @"timeout": @"连接超时",
            @"cannot connect": @"无法连接服务器",
            @"connection refused": @"连接被拒绝",
            @"unable to resolve": @"无法解析地址",
            @"hostname could not be found": @"无法解析服务器地址",
            @"not connected": @"未连接",
            @"unauthorized": @"认证失败",
            @"invalid": @"无效",
            @"failed": @"失败",
            @"success": @"成功",
        };
    });
    NSString *lower = msg.lowercaseString;
    for (NSString *en in map) {
        if ([lower containsString:en]) return map[en];
    }
    return @"连接断开";
}

/// 指令英文名 → 中文显示名
+ (NSString *)_displayNameForAction:(NSString *)action {
    static NSDictionary *map = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"scroll_down": @"下滑", @"scroll_up": @"上滑",
            @"like": @"点赞", @"follow": @"关注", @"comment": @"评论",
            @"collect": @"收藏", @"screenshot": @"截图",
            @"collect_fans": @"采集粉丝", @"collect_videos": @"采集视频",
            @"collect_comments": @"采集评论", @"collect_live_users": @"采集直播用户",
            @"batch_like": @"批量点赞", @"batch_follow": @"批量关注", @"batch_comment": @"批量评论",
            @"batch_login": @"批量登录", @"switch_account": @"切换账号",
            @"get_account_info": @"获取账号信息", @"report_account": @"上报账号",
            @"edit_profile": @"修改资料", @"logout": @"退出登录",
            @"smart_browse": @"智能浏览", @"check_health": @"健康检查",
            @"go_back": @"返回", @"go_home": @"回首页", @"open_tab": @"切换页面",
            @"open_search": @"打开搜索", @"search_keyword": @"搜索关键词",
            @"open_user": @"打开用户", @"open_video": @"打开视频",
            @"refresh": @"刷新", @"share": @"分享", @"save_video": @"保存视频",
            @"send_dm": @"发送私信", @"send_card": @"发送名片", @"share_live": @"分享直播",
            @"post_video": @"发布视频", @"register_account": @"注册账号",
            @"nurture_tick": @"养号操作", @"nurture_stop": @"停止养号",
        };
    });
    NSString *cn = map[action];
    return cn ?: action;
}

- (void)_executePiggybackCommand:(NSDictionary *)cmd {
    NSString *type = cmd[@"type"] ?: @"command";
    if ([type isEqualToString:@"command"]) {
        NSString *action = cmd[@"action"] ?: @"";
        [self addLog:@"📲 收到指令: %@", [XNOWER _displayNameForAction:action]];

        if ([action isEqualToString:@"batch_login"]) {
            NSDictionary *params = cmd[@"params"] ?: @{};
            NSArray *accountIds = params[@"account_ids"] ?: @[];
            NSDictionary *credentials = cmd[@"credentials"] ?: @{};
            if (accountIds.count == 0) {
                [self addLog:@"❌ 批量登录: 未指定账号"];
                [XNURLProtocol sendMessage:@{
                    @"type": @"result",
                    @"data": @{@"action": @"batch_login", @"status": @"failed", @"message": @"未指定账号"}
                } deviceId:self.deviceId];
                return;
            }
            for (NSString *aid in credentials) {
                NSDictionary *creds = credentials[aid];
                if (creds) [[AccountPool sharedPool] upsertAccount:creds];
            }
            [[AccountSwitcher sharedSwitcher] batchLogin:accountIds completion:^(NSInteger done, NSInteger total, BOOL final, NSDictionary *result) {
                [self addLog:@"🔄 批量登录: %ld/%ld %@", (long)done, (long)total, final ? @"完成" : @"进行中"];
                [XNURLProtocol sendMessage:@{
                    @"type": @"result",
                    @"data": @{
                        @"action": @"batch_login",
                        @"status": final ? @"complete" : @"progress",
                        @"done": @(done),
                        @"total": @(total),
                        @"last_result": result ?: @{},
                    }
                } deviceId:self.deviceId];
            }];
        } else {
            // 普通指令
            NSString *actionCN = [XNOWER _displayNameForAction:action];
            [self addLog:@"⚙️ 执行: %@", actionCN];
            __weak typeof(self) weakSelf = self;
            [self.cmdEngine executeCommand:cmd completion:^(NSDictionary *result) {
                // CommandEngine 返回 status: success/failed；也兼容 success:YES/NO
                NSString *statusStr = [result[@"status"] isKindOfClass:[NSString class]] ? result[@"status"] : @"";
                BOOL ok = [statusStr isEqualToString:@"success"] ||
                          [statusStr isEqualToString:@"complete"] ||
                          [result[@"success"] boolValue];
                NSString *status = ok ? @"✅" : @"❌";
                if (result[@"message"]) {
                    [weakSelf addLog:@"%@ %@: %@", status, actionCN, result[@"message"]];
                } else {
                    [weakSelf addLog:@"%@ %@ 完成", status, actionCN];
                }
                [XNURLProtocol sendMessage:@{@"type": @"result", @"data": result}
                                  deviceId:weakSelf.deviceId];
            }];
        }
    } else if ([type isEqualToString:@"sync_accounts"]) {
        NSArray *accounts = cmd[@"accounts"] ?: @[];
        [[AccountPool sharedPool] syncAccounts:accounts];
        [self addLog:@"📥 同步账号: %lu 个", (unsigned long)accounts.count];
        [XNURLProtocol sendMessage:@{@"type": @"sync_accounts_ack", @"data": @{@"count": @(accounts.count)}}
                          deviceId:self.deviceId];
    } else if ([type isEqualToString:@"ping"]) {
        [XNURLProtocol sendMessage:@{@"type": @"pong"} deviceId:self.deviceId];
    }
}

/// 启动 piggyback 轮询（每 5 秒）— 先检查设备授权，未授权则弹激活视图
- (void)startPiggybackPolling {
    [self stopPiggybackPolling];
    __weak typeof(self) ws = self;
    [XNURLProtocol checkLicenseForDevice:self.deviceId completion:^(BOOL licensed, NSDictionary *info) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) s = ws;
            if (!s) return;
            if (!licensed) {
                s->_isConnected = NO;
                [s.floatingPanel setConnected:NO];
                [s addLog:@"⚠️ 设备未激活，请先输入卡密激活"];
                [s.floatingPanel showActivationView];
                return;
            }
            s->_isConnected = YES;
            [s.floatingPanel setConnected:YES];
            [s addLog:@"✅ 授权有效，开始轮询指令"];
            [s _startPollingTimer];
        });
    }];
}

/// 真正创建轮询定时器（授权通过后调用）
- (void)_startPollingTimer {
    [self stopPiggybackPolling];
    dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), 5 * NSEC_PER_SEC, 2 * NSEC_PER_SEC);
    __weak typeof(self) ws = self;
    dispatch_source_set_event_handler(t, ^{
        if (ws.isConnected) {
            [XNURLProtocol pollCommands:ws.deviceId];
        }
    });
    _piggybackTimer = t;
    dispatch_resume(t);
}

- (void)stopPiggybackPolling {
    if (_piggybackTimer) {
        dispatch_source_cancel(_piggybackTimer);
        _piggybackTimer = nil;
    }
}

- (void)startHeartbeat {
    // 先取消旧的心跳（防泄漏：每次重连不叠加多个timer）
    [self stopHeartbeat];

    dispatch_async(self.workerQueue, ^{
        dispatch_source_t timer = dispatch_source_create(
            DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
            dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0));
        dispatch_source_set_timer(timer,
            dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC),
            30 * NSEC_PER_SEC, 5 * NSEC_PER_SEC);

        __weak typeof(self) ws = self;
        dispatch_source_set_event_handler(timer, ^{
            typeof(self) s = ws;
            if (!s || !s.isConnected) return;
            // 走 piggyback 通道上报心跳 + 状态
            [XNURLProtocol sendMessage:@{@"type": @"ping"} deviceId:s.deviceId];
            NSMutableDictionary *status = [[s.deviceStatus collectStatus] mutableCopy];
            if ([AccountManager sharedManager].currentAccount) {
                status[@"current_account"] = [AccountManager sharedManager].currentAccount;
            }
            [XNURLProtocol sendMessage:@{@"type": @"status", @"data": status} deviceId:s.deviceId];
        });
        dispatch_resume(timer);
        self.heartbeatTimer = timer;
    });
}

- (void)stopHeartbeat {
    if (_heartbeatTimer) {
        dispatch_source_cancel(_heartbeatTimer);
        _heartbeatTimer = nil;
    }
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
    if ([AccountManager sharedManager].currentAccount) {
        [self.floatingPanel setAccountInfo:[AccountManager sharedManager].currentAccount];
    }

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
        // 保留 overlayWindow 用于监听摇一摇
        if (self.overlayWindow) {
            self.overlayWindow.hidden = NO;
            self.overlayWindow.windowLevel = UIWindowLevelStatusBar + 101;
            self.overlayWindow.backgroundColor = [UIColor clearColor];
            self.overlayWindow.userInteractionEnabled = NO;
            // 加一个透明视图接收摇一摇事件
            UIView *shakeView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, 1)];
            shakeView.backgroundColor = UIColor.clearColor;
            [self.overlayWindow addSubview:shakeView];
            [shakeView becomeFirstResponder];
        }
        self.floatingPanelVisible = NO;
    });
}

// L18: 摇一摇恢复浮窗 — XNOWER 是 NSObject 非 UIResponder，此方法不会收到
// motion 事件（死代码）。要恢复浮窗请重新打开 TikTok 或点击浮窗按钮。
// 如需要摇一摇，应在 overlayWindow 的自定义 UIWindow 子类中实现 motionBegan:。

#pragma mark - XNFloatingPanelDelegate

/// 通过 HTTP API 向后端发送指令（VPS 直连，Cloudflare 被封）
- (void)_sendCommandToBackend:(NSString *)action params:(NSDictionary *)params {
    // L17: 与 XNURLProtocol 共用后端常量（VPS 直连）
    extern NSString *const kXnowBackendHost;
    extern int const kXnowBackendPort;
    NSString *baseURL = [NSString stringWithFormat:@"http://%@:%d", kXnowBackendHost, kXnowBackendPort];
    // M5: 上报带设备密钥鉴权
    NSString *sec = self.deviceSecret ?: @"";
    NSString *reportPath = sec.length > 0 ?
        [NSString stringWithFormat:@"%@/api/biz/v2/commands/report/?secret=%@", baseURL, sec] :
        [NSString stringWithFormat:@"%@/api/biz/v2/commands/report/", baseURL];
    NSURL *url = [NSURL URLWithString:reportPath];
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

/// 调用后端激活卡密，成功后存储授权信息并回调浮窗
- (void)activateWithLicenseKey:(NSString *)key {
    if (key.length == 0) {
        [self addLog:@"❌ 请输入卡密"];
        return;
    }
    [self addLog:@"🔑 正在激活卡密…"];
    __weak typeof(self) weakSelf = self;
    [XNURLProtocol activateLicense:key
                          deviceId:self.deviceId
                              udid:[[[UIDevice currentDevice] identifierForVendor] UUIDString]
                        completion:^(NSDictionary *result, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) s = weakSelf;
            if (!s) return;
            if (error) {
                [s addLog:@"❌ 激活失败: %@", error.localizedDescription];
                [s.floatingPanel setActivated:NO expires:nil];
                return;
            }
            if ([result isKindOfClass:[NSDictionary class]]) {
                NSString *status = result[@"status"];
                NSString *expiry = result[@"expires_at"];
                BOOL ok = [status isKindOfClass:[NSString class]] &&
                          ([status isEqualToString:@"active"] ||
                           [status isEqualToString:@"success"] ||
                           [status isEqualToString:@"ok"] ||
                           [status isEqualToString:@"activated"]);
                if (ok || [expiry isKindOfClass:[NSString class]] && expiry.length > 0) {
                    s.licenseKey = key;
                    s.licenseExpiry = expiry ?: @"";
                    [[NSUserDefaults standardUserDefaults] setObject:key forKey:@"XN_ActivationCode"];
                    [[NSUserDefaults standardUserDefaults] setObject:s.licenseExpiry forKey:@"XN_LicenseExpiry"];
                    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"XN_Activated"];
                    [[NSUserDefaults standardUserDefaults] synchronize];
                    [s addLog:[NSString stringWithFormat:@"✅ 激活成功，有效期至 %@", s.licenseExpiry]];
                    [s.floatingPanel setActivated:YES expires:s.licenseExpiry];
                    return;
                }
            }
            [s addLog:@"❌ 激活失败，请检查卡密"];
            [s.floatingPanel setActivated:NO expires:nil];
        });
    }];
}

/// 浮窗激活视图确认 → 激活卡密
- (void)floatingPanel:(XNFloatingPanel *)panel didEnterLicenseKey:(NSString *)key {
    [self activateWithLicenseKey:key];
}

/// 浮窗绑定后台提交 → 存储本地 + piggyback 上报绑定信息
- (void)floatingPanel:(XNFloatingPanel *)panel didSubmitBindingWithCode:(NSString *)code apiId:(NSString *)apiId {
    if (code.length == 0 || apiId.length == 0) {
        [self addLog:@"❌ 绑定失败：设备编号和APIID不能为空"];
        return;
    }
    // 存储绑定信息
    [[NSUserDefaults standardUserDefaults] setObject:code forKey:@"XN_BindDeviceID"];
    [[NSUserDefaults standardUserDefaults] setObject:apiId forKey:@"XN_BindAPIID"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    // 更新设备 ID（使用手机序号）
    NSString *vendorID = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    NSString *shortID = vendorID.length >= 8 ? [vendorID substringToIndex:8] : [NSUUID UUID].UUIDString;
    _deviceId = [NSString stringWithFormat:@"iphone_%@_%@", code, shortID];
    [[NSUserDefaults standardUserDefaults] setObject:_deviceId forKey:kXnowDeviceIdKey];
    [self.floatingPanel setDeviceId:_deviceId];

    [self addLog:[NSString stringWithFormat:@"✅ 绑定成功 设备:%@ API:%@", code, apiId]];

    // 通过 piggyback 上报绑定信息
    [XNURLProtocol sendMessage:@{
        @"type": @"bind_info",
        @"data": @{@"device_code": code, @"api_id": apiId}
    } deviceId:_deviceId];
}

- (void)floatingPanelDidTapLike:(XNFloatingPanel *)panel {
    [self addLog:@"❤️ 点赞"];
    [self _sendCommandToBackend:@"like" params:nil];
    @try { [self.cmdEngine executeCommand:@{@"action": @"like"} completion:nil]; } @catch (id e) {}
}

- (void)floatingPanelDidTapFollow:(XNFloatingPanel *)panel {
    [self addLog:@"➕ 关注"];
    [self _sendCommandToBackend:@"follow" params:nil];
    @try { [self.cmdEngine executeCommand:@{@"action": @"follow"} completion:nil]; } @catch (id e) {}
}

- (void)floatingPanelDidTapScrollDown:(XNFloatingPanel *)panel {
    [self addLog:@"⬇️ 下滑"];
    [self _sendCommandToBackend:@"scroll_down" params:nil];
    @try { [self.cmdEngine executeCommand:@{@"action": @"scroll_down"} completion:nil]; } @catch (id e) {}
}

- (void)floatingPanelDidTapScreenshot:(XNFloatingPanel *)panel {
    [self addLog:@"📸 截图"];
    [self _sendCommandToBackend:@"screenshot" params:nil];
    @try { [self.cmdEngine executeCommand:@{@"action": @"screenshot"} completion:nil]; } @catch (id e) {}
}

- (void)floatingPanelDidTapCollectFans:(XNFloatingPanel *)panel {
    [self addLog:@"👥 采集粉丝(20)"];
    [self _sendCommandToBackend:@"collect_fans" params:@{@"count": @20}];
}

- (void)floatingPanelDidTapCollectVideos:(XNFloatingPanel *)panel {
    [self addLog:@"🎬 采集视频(10)"];
    [self _sendCommandToBackend:@"collect_videos" params:@{@"count": @10}];
}

- (void)floatingPanelDidTapAccountInfo:(XNFloatingPanel *)panel {
    // 绑定信息已存储，通过当前 WebSocket 上报给后端
    //（注意：绝不在此处创建/断开 WsClient — 之前的绑定闪退修复已证明这是雷区）
    if (self.wsClient && self.isConnected) {
        NSString *bindDevId = [[NSUserDefaults standardUserDefaults] stringForKey:@"XN_BindDeviceID"] ?: @"";
        NSString *bindApiId = [[NSUserDefaults standardUserDefaults] stringForKey:@"XN_BindAPIID"] ?: @"";
        [self.wsClient sendMessage:@{
            @"type": @"bind_info",
            @"data": @{@"device_code": bindDevId, @"api_id": bindApiId}
        }];
        [self addLog:[NSString stringWithFormat:@"已上报绑定信息(设备%@ API:%@)", bindDevId, bindApiId]];
    } else {
        [self addLog:@"绑定信息已保存（服务器未连接，稍后自动上报）"];
    }
}

- (void)floatingPanelDidTapConnectServer:(XNFloatingPanel *)panel {
    // 用户手动点击"连接到服务器" → 借TikTok网络栈（piggyback）
    [self addLog:@"正在检测服务器…"];
    __weak typeof(self) weakSelf = self;
    [XNURLProtocol checkBackendNow:^(BOOL ok) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) s = weakSelf;
            if (!s) return;
            if (ok) {
                s->_isConnected = YES;
                [s addLog:@"✅ 服务器可达，正在上报设备…"];
                [s.floatingPanel setConnected:YES];
                // 上报设备在线 + 开始轮询指令
                [XNURLProtocol reportOnline:s.deviceId];
                [s startPiggybackPolling];
            } else {
                s->_isConnected = NO;
                [s addLog:@"❌ 服务器不可达"];
                [s.floatingPanel setConnected:NO];
            }
        });
    }];
}

- (void)floatingPanelDidTapSmartBrowse:(XNFloatingPanel *)panel {
    [self addLog:@"🌐 智能浏览"];
    [self _sendCommandToBackend:@"smart_browse" params:@{@"min_scrolls": @5, @"max_scrolls": @12}];
}

// H4: 独立回调（之前错误映射到下滑/智能浏览）
- (void)floatingPanelDidTapClearData:(XNFloatingPanel *)panel {
    [self addLog:@"🗑️ 清理本地缓存数据…"];
    [[AccountPool sharedPool] clearAll];
    [[AccountManager sharedManager] clearAccount];
    [self addLog:@"✅ 数据已清理"];
}

- (void)floatingPanelDidTapDisconnect:(XNFloatingPanel *)panel {
    [self addLog:@"🔌 断开服务器连接"];
    [self stopPiggybackPolling];
    [self stopHeartbeat];
    _isConnected = NO;
    [self.floatingPanel setConnected:NO];
}

- (void)floatingPanelDidTapCollectLikes:(XNFloatingPanel *)panel {
    [self addLog:@"❤️ 采集点赞"];
    [self _sendCommandToBackend:@"collect_likes" params:@{@"count": @20}];
}

- (void)floatingPanelDidTapNurture:(XNFloatingPanel *)panel {
    [self addLog:@"🌱 养号"];
    [self _sendCommandToBackend:@"nurture_tick" params:@{@"min_scrolls": @5, @"max_scrolls": @12}];
}

- (void)floatingPanelDidTapDownloadVideo:(XNFloatingPanel *)panel {
    [self addLog:@"💾 下载无水印视频（需在视频页）"];
    [self _sendCommandToBackend:@"save_video" params:nil];
}

#pragma mark - 自动任务开关

- (void)floatingPanel:(XNFloatingPanel *)panel didToggleAutoLike:(BOOL)on {
    [self addLog:on ? @"🔁 开启自动点赞" : @"⏹ 关闭自动点赞"];
    [self _sendCommandToBackend:on ? @"auto_like_start" : @"auto_like_stop" params:@{@"enabled": @(on)}];
}

- (void)floatingPanel:(XNFloatingPanel *)panel didToggleAutoFollow:(BOOL)on {
    [self addLog:on ? @"🔁 开启自动关注" : @"⏹ 关闭自动关注"];
    [self _sendCommandToBackend:on ? @"auto_follow_start" : @"auto_follow_stop" params:@{@"enabled": @(on)}];
}

- (void)floatingPanel:(XNFloatingPanel *)panel didToggleAutoComment:(BOOL)on {
    [self addLog:on ? @"🔁 开启自动评论" : @"⏹ 关闭自动评论"];
    [self _sendCommandToBackend:on ? @"auto_comment_start" : @"auto_comment_stop" params:@{@"enabled": @(on)}];
}

- (void)floatingPanel:(XNFloatingPanel *)panel didToggleAutoBrowse:(BOOL)on {
    [self addLog:on ? @"🔁 开启自动浏览" : @"⏹ 关闭自动浏览"];
    [self _sendCommandToBackend:on ? @"auto_browse_start" : @"auto_browse_stop" params:@{@"enabled": @(on)}];
}

#pragma mark - 自动任务参数

- (void)floatingPanel:(XNFloatingPanel *)panel didChangeAutoLikeCount:(int)count delay:(int)delay {
    [self addLog:@"⚙️ 自动点赞设置: %d次/每%d秒", count, delay];
    [self _sendCommandToBackend:@"auto_like_config" params:@{@"count": @(count), @"delay": @(delay)}];
}

- (void)floatingPanel:(XNFloatingPanel *)panel didChangeAutoFollowCount:(int)count delay:(int)delay {
    [self addLog:@"⚙️ 自动关注设置: %d次/每%d秒", count, delay];
    [self _sendCommandToBackend:@"auto_follow_config" params:@{@"count": @(count), @"delay": @(delay)}];
}

- (void)floatingPanel:(XNFloatingPanel *)panel didChangeAutoCommentCount:(int)count delay:(int)delay text:(NSString *)text {
    [self addLog:@"⚙️ 自动评论设置: %d次/每%d秒", count, delay];
    [self _sendCommandToBackend:@"auto_comment_config" params:@{@"count": @(count), @"delay": @(delay), @"text": text ?: @""}];
}

- (void)floatingPanel:(XNFloatingPanel *)panel didChangeAutoBrowseMinScrolls:(int)min maxScrolls:(int)max minDelay:(int)minDelay maxDelay:(int)maxDelay {
    [self addLog:@"⚙️ 自动浏览设置: %d-%d次", min, max];
    [self _sendCommandToBackend:@"auto_browse_config" params:@{@"min_scrolls": @(min), @"max_scrolls": @(max), @"min_delay": @(minDelay), @"max_delay": @(maxDelay)}];
}

#pragma mark - 切换账号

- (void)floatingPanel:(XNFloatingPanel *)panel didSelectAccountId:(NSInteger)accountId {
    [self addLog:@"🔄 切换账号 #%ld…", (long)accountId];
    [[AccountSwitcher sharedSwitcher] switchToAccount:accountId completion:^(BOOL success, NSDictionary *result) {
        [self addLog:success ? @"✅ 切换账号 #%ld 成功" : @"❌ 切换账号 #%ld 失败", (long)accountId];
        NSLog(@"[XNOWER] 切换账号 %ld: %@", (long)accountId, success ? @"成功" : @"失败");
        if (self.wsClient) {
            [self.wsClient sendMessage:@{@"type": @"account_switch_result", @"data": @{
                @"account_id": @(accountId), @"success": @(success), @"result": result ?: @{},
            }}];
        }
    }];
}

- (void)floatingPanelDidRequestAccountList:(XNFloatingPanel *)panel {
    // 从本地 AccountPool 获取并展示
    NSArray *accounts = [[AccountPool sharedPool] allAccounts];
    [self.floatingPanel setAccountList:accounts];

    // 同时从服务器同步最新账号列表
    if (self.wsClient) {
        [self.wsClient sendMessage:@{@"type": @"request_accounts"}];
    }
}

- (void)floatingPanelDidTapAddNewAccount:(XNFloatingPanel *)panel {
    [self addLog:@"🧹 新增账号：清空登录态（无痕）"];
    [[AccountSwitcher sharedSwitcher] prepareNewAccount];
    // 回到 TikTok 首页，让用户走登录流程
    [self addLog:@"已进入全新无痕环境，请登录新账号。完成后点「备份当前账号」"];
}

- (void)floatingPanelDidTapBackupAccount:(XNFloatingPanel *)panel {
    NSInteger savedId = [[AccountSwitcher sharedSwitcher] backupCurrentAccount];
    if (savedId > 0) {
        [self addLog:@"✅ 已备份账号 #%ld 登录态", (long)savedId];
        [self _sendCommandToBackend:@"account_backed_up" params:@{@"account_id": @(savedId)}];
        // 刷新账号列表
        [self.floatingPanel setAccountList:[[AccountPool sharedPool] allAccounts]];
    } else {
        [self addLog:@"❌ 备份失败：未检测到当前登录账号"];
    }
}

@end

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
#import "DeviceIdentity.h"
#import "XNWindowHelper.h"
#import <objc/runtime.h>
#import <pthread.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>

// ======== 崩溃诊断 ========
// 未捕获 ObjC 异常 → 写文件；SIGSEGV/SIGABRT → 写标记文件。下次启动上报后端。
static NSString *XN_CrashDir(void) {
    NSString *home = NSHomeDirectory();
    if (home.length == 0) return NSTemporaryDirectory();
    return [home stringByAppendingPathComponent:@"Documents"];
}

static void XN_WriteCrashFile(NSString *name, NSString *content) {
    @try {
        NSString *dir = XN_CrashDir();
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        [content writeToFile:[dir stringByAppendingPathComponent:name] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } @catch (id e) {}
}

static void XN_UncaughtExceptionHandler(NSException *exception) {
    NSString *desc = [NSString stringWithFormat:@"UncaughtException %@: %@\n%@",
                      exception.name, exception.reason,
                      [[exception callStackSymbols] componentsJoinedByString:@"\n"]];
    XN_WriteCrashFile(@"xn_crash_exc.txt", desc);
    NSLog(@"[XNOWER][CRASH] %@", desc);
}

static void XN_SignalHandler(int sig) {
    // 写标记文件（优先 HOME/Documents，回退 TMPDIR——HOME 在注入环境下可能取不到）
    const char *home = getenv("HOME");
    const char *tmp = getenv("TMPDIR");
    char path[600];
    if (home) {
        snprintf(path, sizeof(path), "%s/Documents/xn_crash_sig_%d", home, sig);
        int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd >= 0) { const char *m = "signal"; write(fd, m, strlen(m)); close(fd); }
    }
    if (tmp) {
        snprintf(path, sizeof(path), "%s/xn_crash_sig_%d", tmp, sig);
        int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd >= 0) { const char *m = "signal"; write(fd, m, strlen(m)); close(fd); }
    }
    // 恢复默认处理并重抛信号，确保进程真正终止（不吞崩溃）
    signal(sig, SIG_DFL);
    raise(sig);
}

// ======== 默认配置 ========
NSString *const kXnowDefaultServerURL = @"wss://yunkong.taikon.top";
NSString *const kXnowConfigKeyServerURL = @"XNOWER_ServerURL";
NSString *const kXnowConfigKeyEnabled = @"XNOWER_Enabled";
NSString *const kXnowConfigKeyBuildVersion = @"XNOWER_BuildVersion";
static NSString *const kXnowConfigPlistName = @"xnower-config.plist";
static NSString *const kXnowDeviceIdKey = @"XNOWER_DeviceID";

// ======== 静态实例 ========
static XNOWER *gSharedInstance = nil;

// ======== 启动由 XNStartup.m 的 +load 完成 ========

// ======== 析构函数（dylib 卸载时） ========
__attribute__((destructor)) static void XNOWERUnload() {
    [[XNOWER sharedInstance] stop];
}

// ======== 可穿透浮窗窗口 ========
// overlayWindow 是全屏的，默认会拦截整个屏幕的触摸（点不在浮窗上也吃掉）。
// 重写 hitTest：只有点中浮窗子视图才响应，否则返回 nil 穿透给下面的 TikTok。
@interface XNPassThroughWindow : UIWindow
@end
@implementation XNPassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    // 若命中点是 window 自身（即没有任何子视图接收）→ 穿透给下面的 App
    if (hit == self) return nil;
    return hit;
}
@end

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
@property (nonatomic, strong) dispatch_source_t authRetryTimer;  // 未激活自动重连
@property (nonatomic, copy) NSString *deviceSecret;
@property (nonatomic, copy) NSString *licenseKey;
@property (nonatomic, copy) NSString *licenseExpiry;
@end

@implementation XNOWER

/// 读取打包时嵌入的配置 plist（含构建版本号）。路径: Payload/TikTok.app/xnower-config.plist
+ (NSDictionary *)_configPlistDictionary {
    NSArray *searchPaths = @[
        [[NSBundle mainBundle] pathForResource:kXnowConfigPlistName ofType:nil],
        [NSString stringWithFormat:@"%@/%@",
            [NSBundle mainBundle].bundlePath, kXnowConfigPlistName],
    ];
    for (NSString *path in searchPaths) {
        if (path && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
            NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:path];
            if (d) return d;
        }
    }
    return nil;
}

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

        // 构建版本号：优先读打包嵌入的 xnower-config.plist，回退 NSUserDefaults，再回退 dev
        _buildVersion = [[NSUserDefaults standardUserDefaults]
                          stringForKey:kXnowConfigKeyBuildVersion];
        if (_buildVersion.length == 0) {
            NSDictionary *plist = [XNOWER _configPlistDictionary];
            NSString *v = plist[kXnowConfigKeyBuildVersion];
            if ([v isKindOfClass:[NSString class]] && v.length > 0) {
                _buildVersion = v;
                [[NSUserDefaults standardUserDefaults] setObject:v forKey:kXnowConfigKeyBuildVersion];
            }
        }
        if (_buildVersion.length == 0) _buildVersion = @"dev";

        // 生成或恢复设备 ID —— 必须稳定（激活卡、授权检查、绑定后台用同一个 ID）。
        // 序号(device_code)不进入 deviceId，否则绑定前后 ID 变化导致激活的卡对不上。
        NSString *savedId = [[NSUserDefaults standardUserDefaults]
                              stringForKey:kXnowDeviceIdKey];
        if (savedId.length > 0) {
            // 旧格式（iphone_<code>_<shortID>）迁移：去掉序号段，恢复稳定格式
            if ([savedId hasPrefix:@"iphone_"] && [[savedId componentsSeparatedByString:@"_"] count] == 3) {
                NSArray *parts = [savedId componentsSeparatedByString:@"_"];
                _deviceId = [NSString stringWithFormat:@"iphone_%@", parts[2]];
                [[NSUserDefaults standardUserDefaults] setObject:_deviceId forKey:kXnowDeviceIdKey];
            } else {
                _deviceId = savedId;
            }
        } else {
            NSString *vendorID = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
            NSString *shortID = vendorID.length >= 8 ? [vendorID substringToIndex:8] :
                                 [NSUUID UUID].UUIDString;
            _deviceId = [NSString stringWithFormat:@"iphone_%@", shortID];
            [[NSUserDefaults standardUserDefaults] setObject:_deviceId forKey:kXnowDeviceIdKey];
        }

        // 生成/恢复设备共享密钥（设备端点鉴权用）
        NSString *savedSecret = [[NSUserDefaults standardUserDefaults] stringForKey:@"XN_DeviceSecret"];
        if (savedSecret.length == 0) {
            savedSecret = [NSUUID UUID].UUIDString;
            [[NSUserDefaults standardUserDefaults] setObject:savedSecret forKey:@"XN_DeviceSecret"];
        }
        _deviceSecret = savedSecret;

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

    // 崩溃诊断：捕获未处理异常 + 段错误，写文件下次启动上报
    NSSetUncaughtExceptionHandler(&XN_UncaughtExceptionHandler);
    signal(SIGSEGV, XN_SignalHandler);
    signal(SIGABRT, XN_SignalHandler);
    signal(SIGBUS, XN_SignalHandler);
    signal(SIGILL, XN_SignalHandler);

    // 显示浮窗
    [self showFloatingPanel];

    // 自动检测授权（piggyback 借 TikTok 网络栈，不连外部 WS，BH 检测不到）
    // 未激活设备打开 TikTok 自动弹激活浮窗，无需手动点"连接到服务器"
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self startPiggybackPolling];
        // 崩溃上报延迟到 8 秒（等 piggyback 注册完成，避免 3 秒时通道未就绪导致上报丢失）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self reportPendingCrash];
        });
    });
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

/// 启动诊断 + 崩溃上报（每次启动必发，验证通道 + 带出崩溃信息）
- (void)reportPendingCrash {
    @try {
        NSMutableArray *parts = [NSMutableArray array];

        // 1) 崩溃前最后执行的指令（对 SIGKILL/信号级崩溃也有效，只要指令没跑完标记就留着）
        NSString *lastAction = [[NSUserDefaults standardUserDefaults] stringForKey:@"XN_LastAction"];
        if (lastAction.length > 0) {
            [parts addObject:[NSString stringWithFormat:@"[last_action] %@", lastAction]];
        }

        // 2) 崩溃文件（异常详情 / 信号标记）— 检查 Documents + TMPDIR
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *dir in @[XN_CrashDir(), NSTemporaryDirectory()]) {
            NSArray *files = [fm contentsOfDirectoryAtPath:dir error:nil];
            for (NSString *f in files ?: @[]) {
                if (![f hasPrefix:@"xn_crash_"]) continue;
                NSString *path = [dir stringByAppendingPathComponent:f];
                NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"unknown";
                [parts addObject:[NSString stringWithFormat:@"[%@] %@", f, content]];
            }
        }

        // 3) 设备状态（是否已激活、设备ID）— 用于确认诊断链路
        BOOL activated = [[NSUserDefaults standardUserDefaults] boolForKey:@"XN_Activated"];
        NSString *info = parts.count ? [parts componentsJoinedByString:@"\n"] : @"ok";
        NSLog(@"[XNOWER] 启动诊断: activated=%d last_action=%@ crash=%@", activated, lastAction ?: @"-", info);
        [XNURLProtocol sendMessage:@{
            @"type": @"crash_report",
            @"data": @{
                @"crash": info,
                @"last_action": lastAction ?: @"",
                @"activated": @(activated),
            }
        } deviceId:self.deviceId];

        // 上报后清除崩溃文件（last_action 留到下次指令完成才清，崩溃信息已随本次上报带出）
        @try {
            for (NSString *dir in @[XN_CrashDir(), NSTemporaryDirectory()]) {
                NSArray *files = [fm contentsOfDirectoryAtPath:dir error:nil];
                for (NSString *f in files ?: @[]) {
                    if ([f hasPrefix:@"xn_crash_"]) {
                        [fm removeItemAtPath:[dir stringByAppendingPathComponent:f] error:nil];
                    }
                }
            }
        } @catch (id e) {}
    } @catch (id e) {}
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
        [self addLog:@"📋 操作：%@", [XNOWER _displayNameForAction:action]];

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
            // 普通指令 — 结构化日志：操作 → 结果 → 同步 → 下一步（小白可读）
            NSString *actionCN = [XNOWER _displayNameForAction:action];
            __weak typeof(self) weakSelf = self;
            [self.cmdEngine executeCommand:cmd completion:^(NSDictionary *result) {
                // CommandEngine 返回 status: success/failed；也兼容 success:YES/NO
                NSString *statusStr = [result[@"status"] isKindOfClass:[NSString class]] ? result[@"status"] : @"";
                BOOL ok = [statusStr isEqualToString:@"success"] ||
                          [statusStr isEqualToString:@"complete"] ||
                          [result[@"success"] boolValue];
                NSString *detail = [result[@"message"] isKindOfClass:[NSString class]] ? result[@"message"] : @"";
                if (ok) {
                    [weakSelf addLog:@"✅ %@成功%@", actionCN, detail.length ? [NSString stringWithFormat:@"：%@", detail] : @""];
                } else {
                    [weakSelf addLog:@"❌ %@失败：%@", actionCN, detail.length ? detail : @"请重试"];
                }
                [XNURLProtocol sendMessage:@{@"type": @"result", @"data": result}
                                  deviceId:weakSelf.deviceId
                                completion:^(BOOL ok, NSError *error) {
                    if (ok) {
                        [weakSelf addLog:@"↗️ 结果已同步云端"];
                    } else {
                        [weakSelf addLog:@"⚠️ 结果同步失败（网络问题，稍后会自动重试）"];
                    }
                    [weakSelf addLog:@"➡️ 下一步：等待下一条指令"];
                }];
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

/// 启动 piggyback 轮询（每 5 秒）— 用设备唯一标识 UID 检查授权。
/// 未激活 → 自动弹激活浮窗 + 每 5 秒自动重连重试（激活后自动恢复）。
- (void)startPiggybackPolling {
    [self stopPiggybackPolling];
    __weak typeof(self) ws = self;
    NSString *uid = [DeviceIdentity deviceUID];
    [XNURLProtocol checkLicenseForDevice:uid completion:^(BOOL licensed, NSDictionary *info) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) s = ws;
            if (!s) return;
            if (!licensed) {
                s->_isConnected = NO;
                [s.floatingPanel setConnected:NO];
                // 清除本地激活标志（防止旧备份残留导致跳过激活界面）
                [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"XN_Activated"];
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"XN_ActivationCode"];
                [[NSUserDefaults standardUserDefaults] synchronize];
                [s addLog:@"⚠️ 设备未激活，请先输入卡密激活"];
                [s.floatingPanel showActivationView];
                // 自动重连：每 5 秒重新检查授权，激活成功后自动恢复
                [s _scheduleAuthRetry];
                return;
            }
            s->_isConnected = YES;
            [s.floatingPanel setConnected:YES];
            // 修复：授权有效 → 自动激活（重装后本地标志被清，授权检查通过也应恢复激活）
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"XN_Activated"];
            if (info[@"key"]) {
                [[NSUserDefaults standardUserDefaults] setObject:info[@"key"] forKey:@"XN_ActivationCode"];
            }
            [[NSUserDefaults standardUserDefaults] synchronize];
            [s.floatingPanel setActivated:YES expires:info[@"expires_at"] ?: @""];
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
    [self stopAuthRetry];
}

/// 停止未激活自动重连
- (void)stopAuthRetry {
    if (_authRetryTimer) {
        dispatch_source_cancel(_authRetryTimer);
        _authRetryTimer = nil;
    }
}

/// 未激活时每 5 秒自动重连检查授权（激活后自动恢复）
- (void)_scheduleAuthRetry {
    [self stopAuthRetry];
    __weak typeof(self) ws = self;
    dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), 5 * NSEC_PER_SEC, 2 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(t, ^{
        typeof(self) s = ws;
        if (!s || s.isConnected) return;
        NSString *uid = [DeviceIdentity deviceUID];
        [XNURLProtocol checkLicenseForDevice:uid completion:^(BOOL licensed, NSDictionary *info) {
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) ss = ws;
                if (!ss) return;
                if (licensed) {
                    [ss stopAuthRetry];
                    ss->_isConnected = YES;
                    [ss.floatingPanel setConnected:YES];
                    [ss addLog:@"✅ 授权有效，开始轮询指令"];
                    [ss _startPollingTimer];
                }
                // 未激活继续等下一轮重试（浮窗保持激活界面）
            });
        }];
    });
    _authRetryTimer = t;
    dispatch_resume(t);
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
        overlayWindow = [[XNPassThroughWindow alloc] initWithWindowScene:activeScene];
    } else {
        overlayWindow = [[XNPassThroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    }
    overlayWindow.windowLevel = UIWindowLevelStatusBar + 100;
    overlayWindow.backgroundColor = [UIColor clearColor];
    overlayWindow.userInteractionEnabled = YES;  // 需 YES 让浮窗可点；穿透由 hitTest 处理

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

- (void)collapseFloatingPanel {
    [self.floatingPanel collapsePanel];
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
                          deviceId:[DeviceIdentity deviceUID]
                              udid:[DeviceIdentity deviceUID]
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

    // 设备 ID 保持稳定（不随序号变化）——序号存 device_code 字段上报，
    // 避免激活的卡绑在旧 deviceId 上导致授权对不上（设备身份必须稳定）。
    // 若当前 deviceId 还是 iphone_ 前缀且不包含序号，保持原样；否则确保稳定格式。
    if ([_deviceId hasPrefix:@"iphone_"] && ![_deviceId containsString:@"_"]) {
        // 已经是稳定格式（iphone_xxxx），无需改
    } else if (![_deviceId hasPrefix:@"iphone_"]) {
        // 异常 deviceId（如纯 "1"），重建稳定 ID
        NSString *vendorID = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
        NSString *shortID = vendorID.length >= 8 ? [vendorID substringToIndex:8] : [NSUUID UUID].UUIDString;
        _deviceId = [NSString stringWithFormat:@"iphone_%@", shortID];
        [[NSUserDefaults standardUserDefaults] setObject:_deviceId forKey:kXnowDeviceIdKey];
    }
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
    [self addLog:@"👥 采集粉丝(20)…"];
    [self _sendCommandToBackend:@"collect_fans" params:@{@"count": @20}];
    [self _runCollectLocally:@"collect_fans" count:20];
}

/// 停止采集（直播间粉丝/评论用户等）
- (void)floatingPanelDidTapStopCollect:(XNFloatingPanel *)panel {
    [self addLog:@"⏹ 停止采集..."];
    [self.cmdEngine executeCommand:@{@"action": @"nurture_stop"} completion:nil];
    [self _sendCommandToBackend:@"nurture_stop" params:@{}];
}

/// 开启实时翻译（私信页文案翻译成目标语言）
- (void)floatingPanelDidToggleTranslate:(XNFloatingPanel *)panel {
    NSString *lang = [[NSUserDefaults standardUserDefaults] stringForKey:@"XN_TranslateLang"] ?: @"中文";
    [self addLog:[NSString stringWithFormat:@"🈯 实时翻译已开启 → %@", lang]];
    // 通知后端开启翻译任务（由后端下发翻译指令，或设备端周期性检测私信文案）
    [self _sendCommandToBackend:@"toggle_translate" params:@{@"enabled": @YES, @"lang": lang}];
}

- (void)floatingPanelDidTapCollectVideos:(XNFloatingPanel *)panel {
    [self addLog:@"🎬 采集视频(10)…"];
    [self _sendCommandToBackend:@"collect_videos" params:@{@"count": @10}];
    [self _runCollectLocally:@"collect_videos" count:10];
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
    [self addLog:@"🌐 智能浏览…"];
    [self _sendCommandToBackend:@"smart_browse" params:@{@"min_scrolls": @5, @"max_scrolls": @12}];
    @try {
        [self.cmdEngine executeCommand:@{@"action": @"smart_browse", @"params": @{@"min_scrolls": @5, @"max_scrolls": @12}} completion:nil];
    } @catch (id e) {}
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
    [self addLog:@"❤️ 采集直播间点赞用户(20)…"];
    [self _sendCommandToBackend:@"collect_likes" params:@{@"count": @20}];
    [self _runCollectLocally:@"collect_likes" count:20];
}

/// 浮窗本地执行采集指令并上报结果（piggyback result 通道入库 collected_data）
- (void)_runCollectLocally:(NSString *)action count:(int)count {
    @try {
        [self.cmdEngine executeCommand:@{@"action": action, @"params": @{@"count": @(count)}} completion:^(NSDictionary *result) {
            [self addLog:@"✅ %@", result[@"message"] ?: @"采集完成"];
            if ([result[@"users"] isKindOfClass:[NSArray class]]) {
                [XNURLProtocol sendMessage:@{@"type": @"result", @"data": result} deviceId:self.deviceId];
            }
        }];
    } @catch (id e) {
        [self addLog:@"❌ 采集失败：%@", e];
    }
}

- (void)floatingPanelDidTapNurture:(XNFloatingPanel *)panel {
    // 旧 delegate 保留（面板已用直接菜单项），无额外处理
}

- (void)floatingPanelDidStartNurtureWithDuration:(int)seconds browseOnly:(BOOL)browseOnly {
    NSString *durStr = (seconds <= 0) ? @"24小时" : [NSString stringWithFormat:@"%d分钟", seconds / 60];
    NSString *modeStr = browseOnly ? @"只上滑浏览" : @"浏览+随机点赞/关注";
    [self addLog:[NSString stringWithFormat:@"🌱 养号已启动（%@，%@，点菜单可停止）", modeStr, durStr]];
    [self.cmdEngine startNurtureWithDuration:seconds browseOnly:browseOnly];
}

- (void)floatingPanelDidStopNurture {
    [self addLog:@"⏹ 养号已停止"];
    [self.cmdEngine stopNurture];
}

- (void)floatingPanelDidTapDownloadVideo:(XNFloatingPanel *)panel {
    [self addLog:@"💾 正在下载无水印视频..."];
    [self _sendCommandToBackend:@"save_video" params:nil];
    @try { [self.cmdEngine executeCommand:@{@"action": @"save_video"} completion:nil]; } @catch (id e) {}
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
    [self addLog:@"📦 正在检测当前账号并备份登录态..."];
    @try {
        // 复用 CommandEngine backup_account：导航个人页→网络捕获→UI扫描兜底→备份登录态
        [self.cmdEngine executeCommand:@{@"action": @"backup_account"} completion:^(NSDictionary *result) {
            BOOL ok = [result[@"status"] isEqualToString:@"success"];
            NSString *msg = result[@"message"] ?: (ok ? @"备份成功" : @"备份失败");
            [self addLog:@"%@ %@", ok ? @"✅" : @"❌", msg];
            if (ok) {
                [self.floatingPanel setAccountList:[[AccountPool sharedPool] allAccounts]];
                [self _sendCommandToBackend:@"account_backed_up" params:@{@"account_id": result[@"account_id"] ?: @(0)}];
            }
        }];
    } @catch (id e) {
        [self addLog:@"❌ 备份失败：%@", e];
    }
}

@end

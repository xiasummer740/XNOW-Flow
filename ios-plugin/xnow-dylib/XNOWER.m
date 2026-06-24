// XNOWER.m
// XNOW iOS 注入插件 - 主入口 + 生命周期
// 作为 dylib 被 TikTok 加载后自动初始化

#import "XNOWER.h"
#import "WsClient.h"
#import "CommandEngine.h"
#import "DeviceStatus.h"
#import "TikTokHooks.h"
#import "XNFloatingPanel.h"
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
    // dylib 被加载时自动运行，无需任何注入器
    // 延迟 2 秒启动，等 TikTok 初始化完毕
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

    // 立即上报设备状态
    NSDictionary *status = [self.deviceStatus collectStatus];
    [client sendMessage:@{
        @"type": @"status",
        @"data": status
    }];

    // 启动定期心跳
    [self startHeartbeat];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.floatingPanel setConnected:YES];
    });
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
                // 顺便上报状态
                NSDictionary *status = [self.deviceStatus collectStatus];
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
        UIWindow *keyWindow = XN_ActiveWindow();
        if (!keyWindow) return;

        self.floatingPanel = [[XNFloatingPanel alloc] init];
        self.floatingPanel.delegate = self;
        [self.floatingPanel setDeviceId:self.deviceId];
        [self.floatingPanel setServerURL:self.serverURL];
        [self.floatingPanel setConnected:self.isConnected];
        [self.floatingPanel showInWindow:keyWindow];
        self.floatingPanelVisible = YES;
    });
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

@end

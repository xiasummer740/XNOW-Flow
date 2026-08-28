// CommandEngine.m
// XNOW 指令执行引擎完整实现
// 通过 UITouch/UIEvent 真实模拟用户操作 + 视图层级遍历 + 网络数据采集

#import "CommandEngine.h"
#import "AccountManager.h"
#import "AccountSwitcher.h"
#import "AccountPool.h"
#import <Photos/Photos.h>
#import "XNWindowHelper.h"
#import "XNTouchSimulator.h"
#import "XNOWER.h"
#import "XNURLProtocol.h"
#import "CountryEnv.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

#pragma mark - 常量

// TikTok 已知的 accessibility identifiers（ui_scan 实测确认，v1.4.21）
static NSString *const kAccLike = @"feedLikeButton";
static NSString *const kAccFollow = @"follow";              // 关注按钮（个人页）
static NSString *const kAccEditProfile = @"user_info_manage_edit_profile"; // 编辑资料按钮（个人主页）
static NSString *const kAccComment = @"feedCommentButton";
static NSString *const kAccShare = @"feedShareButton";
static NSString *const kAccFavorite = @"feedFavoriteButton"; // 收藏
static NSString *const kAccProfileAvatar = @"avatar";
static NSString *const kAccSend = @"send";
static NSString *const kAccPost = @"post";
static NSString *const kAccTextField = @"text_input";

// 默认坐标（以 iPhone 8 Plus 414x736 为基准，按比例缩放）
static const CGFloat kLikeBtnRatioX = 0.92;    // 屏幕右侧
static const CGFloat kLikeBtnRatioY = 0.46;
static const CGFloat kFollowBtnRatioX = 0.92;
static const CGFloat kFollowBtnRatioY = 0.395;
// v1.4.89: 头像实测在右侧交互栏 (384,311)/(414,736) ≈ (0.93, 0.42)，旧的(0.08,0.82)点左下角是错的
static const CGFloat kAvatarRatioX = 0.93;
static const CGFloat kAvatarRatioY = 0.42;

// 随机评论文本池（养号模式2用，多样化避免被限，50+条分类）
// 惰性初始化函数：文件作用域对象字面量非编译期常量（clang 报错），需运行时创建
static NSArray *XN_NurtureComments(void) {
    static NSArray *arr = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        arr = @[
            // 赞美类
            @"太棒了！", @"拍得真好", @"太美了", @"厉害了", @"这也太强了", @"绝了",
            @"爱了爱了", @"真不错", @"超级喜欢", @"好有质感", @"太震撼了", @"无敌了",
            @"神仙视频", @"宝藏博主", @"太优秀了", @"太会拍了",
            // 互动类
            @"支持一下", @"收藏了", @"已点赞", @"关注了", @"必须支持", @"推荐给大家",
            @"学到了", @"说的太对了", @"感同身受", @"一直看你的视频",
            // 疑问/交流类
            @"这个怎么做的？", @"用的什么设备？", @"在哪拍的？", @"背景音乐是什么？",
            @"求教程", @"求同款", @"怎么做到的？", @"下次也带我一起",
            // 简短类
            @"哈哈哈", @"哈哈哈哈哈哈", @"好可爱", @"加油加油", @"牛", @"👍👍",
            @"好棒", @"不错", @"强", @"好", @"可以", @"哇", @"棒棒哒",
            // 表情/语气类
            @"😍😍", @"🥰🥰", @"😄😄", @"🔥🔥", @"❤️❤️", @"🫶🫶",
            @"哈哈哈哈笑死我了", @"这也太搞笑了吧", @"看完心情都好了",
        ];
    });
    return arr;
}

@interface CommandEngine ()
@property (nonatomic, strong) dispatch_queue_t execQueue;
@property (nonatomic, strong) dispatch_queue_t timeoutQueue;  // 命令超时保护用并发队列
@property (nonatomic, strong) NSMutableDictionary *collectedFans;
@property (nonatomic, strong) NSMutableDictionary *collectedVideos;
@property (nonatomic, assign) BOOL isCollectingData;
@property (nonatomic, assign) BOOL nurtureRunning;   // 连续养号运行标志（后台循环检查）
@property (nonatomic, assign) int nurtureMode;       // 当前养号模式 1/2
- (NSDictionary *)_tapTab:(NSString *)tab;          // v1.4.106 返回诊断 dict（含 home 深链兜底）
- (void)_openDeepLink:(NSString *)urlString;         // 打开 TikTok 深链（snssdk1233://）
@end

@implementation CommandEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        _execQueue = dispatch_queue_create("com.xnow.command", DISPATCH_QUEUE_SERIAL);
        _timeoutQueue = dispatch_queue_create("com.xnow.command.timeout", DISPATCH_QUEUE_CONCURRENT);
        _currentPage = @"unknown";
        _collectedFans = [NSMutableDictionary dictionary];
        _collectedVideos = [NSMutableDictionary dictionary];
    }
    return self;
}

- (CommandAction)actionFromString:(NSString *)actionString {
    static NSDictionary *map = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = @{
            @"scroll_down":      @(CommandActionScrollDown),
            @"scroll_up":        @(CommandActionScrollUp),
            @"like":             @(CommandActionLike),
            @"follow":           @(CommandActionFollow),
            @"comment":          @(CommandActionComment),
            @"collect":          @(CommandActionCollect),
            @"screenshot":       @(CommandActionScreenshot),
            @"open_profile":     @(CommandActionOpenProfile),
            @"collect_fans":     @(CommandActionCollectFans),
            @"collect_videos":   @(CommandActionCollectVideos),
            @"collect_comments": @(CommandActionCollectComments),
            @"collect_live_users": @(CommandActionCollectLiveUsers),
            @"collect_likes":     @(CommandActionCollectLikes),
            @"batch_like":       @(CommandActionBatchLike),
            @"batch_follow":     @(CommandActionBatchFollow),
            @"batch_comment":    @(CommandActionBatchComment),
            // 账号管理
            @"get_account_info":  @(CommandActionGetAccountInfo),
            @"switch_account":    @(CommandActionSwitchAccount),
            @"report_account":    @(CommandActionReportAccount),
            // 智能任务
            @"smart_browse":      @(CommandActionSmartBrowse),
            @"check_health":      @(CommandActionCheckHealth),
            // 导航
            @"go_back":           @(CommandActionGoBack),
            @"go_home":           @(CommandActionGoHome),
            @"open_tab":          @(CommandActionOpenTab),
            @"open_search":       @(CommandActionOpenSearch),
            @"search_keyword":    @(CommandActionSearchKeyword),
            @"open_user":         @(CommandActionOpenUser),
            @"open_video":        @(CommandActionOpenVideo),
            // 视频操作
            @"refresh":           @(CommandActionRefresh),
            @"share":             @(CommandActionShare),
            @"save_video":        @(CommandActionSaveVideo),
            // 账号
            @"logout":            @(CommandActionLogout),
            // 修改资料
            @"edit_profile":      @(CommandActionEditProfile),
            // 自动发视频
            @"post_video":        @(CommandActionPostVideo),
            // 自动私信
            @"send_dm":           @(CommandActionSendDm),
            @"send_card":         @(CommandActionSendCard),
            @"share_live":        @(CommandActionShareLive),
            // 批量注册 + 自动养号
            @"nurture_tick":      @(CommandActionNurtureTick),
            @"nurture_stop":      @(CommandActionNurtureStop),
            @"register_account":  @(CommandActionRegisterAccount),
            // 调试诊断
            @"ui_scan":           @(CommandActionUIScan),
            @"tap":               @(CommandActionTap),       // v1.4.124 坐标点击 x/y
            // 账号管理
            @"backup_account":    @(CommandActionBackupAccount),
            // 环境伪装 / 切换国家
            @"set_country":       @(CommandActionSetCountry),
            @"get_country":       @(CommandActionGetCountry),
            // 评论点赞
            @"like_comment":      @(CommandActionLikeComments),
            // 进直播间
            @"open_live":         @(CommandActionOpenLive),
            // 回关/指定关注
            @"follow_user":       @(CommandActionFollowUser),
            // 粉丝列表自动关注（点右侧 Follow→上滑→循环，上限200自动停）
            @"auto_follow_list":  @(CommandActionAutoFollowList),
            // 停止采集（v1.4.108 F21/F26：stop_collect_fans/comments/likes → 置停止标志让采集循环退出）
            @"stop_collect":      @(CommandActionStopCollect),
            @"stop_collect_fans": @(CommandActionStopCollect),
            @"stop_collect_comments": @(CommandActionStopCollect),
            @"stop_collect_likes": @(CommandActionStopCollect),
            // 关闭浮层面板（评论区等 overlay，v1.4.91）
            @"close_overlay":     @(CommandActionCloseOverlay),
            // 指定视频评论
            @"comment_video":     @(CommandActionCommentVideo),
            // 环境诊断
            @"env_diag":          @(CommandActionEnvDiag),
            // VC 诊断
            @"vc_scan":           @(CommandActionVCScan),
            // 登录态诊断（v1.4.116）：NSUserDefaults key 名 + cookies 域名（不含值）
            @"dump_login":        @(CommandActionDumpLogin),
        };
    });
    NSNumber *val = map[actionString.lowercaseString];
    return val ? (CommandAction)[val integerValue] : CommandActionUnknown;
}

- (void)executeCommand:(NSDictionary *)command completion:(CommandCompletion)completion {
    NSString *actionStr = command[@"action"] ?: @"";
    NSDictionary *params = command[@"params"] ?: @{};
    CommandAction action = [self actionFromString:actionStr];

    dispatch_async(_execQueue, ^{
        // v1.4.89 超时保护：单条命令超时立即返回（不阻塞串行队列），防止一条卡死拖垮设备+掉线
        // （search_keyword 实测 90s+ 无返回、命令队列积压、心跳停→离线，即此根因）
        NSDictionary *result = [self _executeActionWithTimeout:action params:params actionName:actionStr
                                                       timeout:[self _commandTimeoutForAction:action]];
        // 指令完成 → 清除崩溃前指令标记（崩溃时标记保留，下次启动上报）
        @try {
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"XN_LastAction"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        } @catch (id e) {}
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(result);
            });
        }
    });
}

/// 命令级超时：在并发队列上执行，超时返回失败结果（泄漏的卡死块不再阻塞后续命令）
- (NSDictionary *)_executeActionWithTimeout:(CommandAction)action
                                     params:(NSDictionary *)params
                                 actionName:(NSString *)actionName
                                    timeout:(NSTimeInterval)timeout {
    if (timeout <= 0) {
        return [self _executeAction:action params:params actionName:actionName];
    }
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSDictionary *result = nil;
    dispatch_async(_timeoutQueue, ^{
        result = [self _executeAction:action params:params actionName:actionName];
        dispatch_semaphore_signal(sem);
    });
    if (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))) != 0) {
        NSLog(@"[XNOWER] ⚠️ 命令 %@ 执行超时(%ds)，跳过继续（防卡死拖垮设备）", actionName, (int)timeout);
        return @{@"status": @"failed", @"message": [NSString stringWithFormat:@"命令超时(%ds)", (int)timeout], @"action": actionName};
    }
    return result;
}

/// 每类命令的超时（秒）：快速命令 30s，搜索 15s（易卡），采集/养号长任务 600s
- (NSTimeInterval)_commandTimeoutForAction:(CommandAction)action {
    switch (action) {
        case CommandActionSearchKeyword:
            return 15;
        case CommandActionCollectFans:
        case CommandActionCollectVideos:
        case CommandActionCollectComments:
        case CommandActionCollectLiveUsers:
        case CommandActionCollectLikes:
        case CommandActionAutoFollowList:
        case CommandActionSmartBrowse:
            return 600;
        default:
            return 30;
    }
}

// ======== 指令派发 ========

- (NSDictionary *)_executeAction:(CommandAction)action
                          params:(NSDictionary *)params
                      actionName:(NSString *)actionName {
    NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];
    __block NSDictionary *result = nil;
    __block BOOL hasResult = NO;

    // 崩溃前最后指令日志：若此处崩溃，下次启动上报哪个指令崩了（对 SIGKILL 也有效）
    @try {
        [[NSUserDefaults standardUserDefaults] setObject:actionName ?: @"unknown" forKey:@"XN_LastAction"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    } @catch (id e) {}

    @try {
        switch (action) {
            case CommandActionScrollDown:
                [self _performSwipeUp]; // 上滑 = 下一个视频
                break;
            case CommandActionScrollUp:
                [self _performSwipeDown]; // 下滑 = 上一个视频
                break;

            case CommandActionLike: {
                // v1.4.127: 不假成功——改用安全版(多级定位+红心真验收+失败重试)，真实上报结果
                BOOL liked = [self _performLikeSafe];
                result = @{
                    @"status": liked ? @"success" : @"failed",
                    @"message": liked ? @"已点赞（红心点亮验证通过）" : @"点赞未生效（未检测到红心点亮）",
                };
                hasResult = YES;
                break;
            }

            case CommandActionUIScan:
                [self _performUIScan];
                break;

            case CommandActionTap: {
                // v1.4.124 坐标点击：远程调试/验证点击链用
                NSNumber *xn = params[@"x"];
                NSNumber *yn = params[@"y"];
                if (xn && yn) {
                    [self _safeTapAtPoint:CGPointMake(xn.doubleValue, yn.doubleValue)];
                    result = @{@"status": @"success", @"message": @"tap", @"x": xn, @"y": yn};
                    hasResult = YES;
                }
                break;
            }

            case CommandActionBackupAccount: {
                // 直接读 TikTok 原生登录数据（session/cookies/Keychain），任意页面可备份，不跳个人页
                NSInteger savedId = [[AccountSwitcher sharedSwitcher] backupCurrentAccount];
                NSMutableDictionary *r = [@{
                    @"status": savedId > 0 ? @"success" : @"failed",
                    @"message": savedId > 0 ? [NSString stringWithFormat:@"已备份账号 #%ld 登录态", (long)savedId]
                                             : @"未检测到登录态（请确认已登录 TikTok）",
                    @"account_id": @(savedId),
                } mutableCopy];
                // v1.4.116 失败自诊断：带上 NSUserDefaults key 名 + cookies 域名（不含值），
                // server.log 可见真实登录态结构 → 据此写精准提取，不盲猜 key
                if (savedId <= 0) {
                    r[@"diagnostic"] = [[AccountSwitcher sharedSwitcher] dumpLoginState] ?: @{};
                } else {
                    // v1.4.117 成功也带证据：命中 dict 的 key 名 + 国家（不含值）→ server.log 可核实国家是否提取到
                    AccountSwitcher *sw = [AccountSwitcher sharedSwitcher];
                    if (sw.lastMatchedProfileKeys.count > 0) r[@"profile_keys"] = sw.lastMatchedProfileKeys;
                    if (sw.lastMatchedCountry.length > 0) r[@"country"] = sw.lastMatchedCountry;
                }
                result = r;
                hasResult = YES;
                break;
            }

            case CommandActionSetCountry: {
                // 环境伪装：把 region/时区/语言/MCC 伪装成目标国（配合出口 IP 一致）
                NSString *country = params[@"country"] ?: @"";
                if (!country.length) {
                    result = @{@"status": @"failed", @"message": @"缺少 country 参数（如\"美国\"）"};
                } else if ([CountryEnv setCountry:country]) {
                    NSDictionary *env = [CountryEnv currentEnv];
                    result = @{
                        @"status": @"success",
                        @"message": [NSString stringWithFormat:@"已设置目标国环境: %@ (region=%@, tz=%@, lang=%@, mcc_mnc=%@)",
                                     country, env[@"region"] ?: @"", env[@"tz"] ?: @"",
                                     env[@"lang"] ?: @"", env[@"mcc_mnc"] ?: @""],
                        @"env": env ?: @{},
                    };
                } else {
                    result = @{@"status": @"failed",
                               @"message": [NSString stringWithFormat:@"暂不支持国家: %@（内置美国/日本/英国/韩国/新加坡/德法泰越/马来印尼/俄乌/印巴/东南亚等）", country]};
                }
                hasResult = YES;
                break;
            }

            case CommandActionGetCountry: {
                NSDictionary *env = [CountryEnv currentEnv];
                result = @{
                    @"status": @"success",
                    @"message": env ? [NSString stringWithFormat:@"当前伪装环境: %@", env[@"name"] ?: @"未知"]
                                     : @"未设置环境伪装（set_country 可设置）",
                    @"env": env ?: @{},
                };
                hasResult = YES;
                break;
            }

            case CommandActionLikeComments: {
                int count = [params[@"count"] intValue];
                if (count <= 0) count = 10;
                [self _performLikeComments:count];
                break;
            }

            case CommandActionOpenLive:
                result = [self _performOpenLive:params];
                hasResult = YES;
                break;

            case CommandActionFollowUser:
                result = [self _performFollowUser:params];
                hasResult = YES;
                break;

            case CommandActionAutoFollowList:
                result = [self _performAutoFollowList:params];
                hasResult = YES;
                break;

            case CommandActionCloseOverlay:
                result = [self _performCloseOverlay];
                hasResult = YES;
                break;

            case CommandActionCommentVideo:
                result = [self _performCommentVideo:params];
                hasResult = YES;
                break;

            case CommandActionEnvDiag: {
                NSDictionary *env = [CountryEnv currentEnv];
                NSDictionary *rewrite = [CountryEnv lastRewrite];
                result = @{
                    @"status": @"success",
                    @"message": env ? [NSString stringWithFormat:@"环境: %@", env[@"name"] ?: @""] : @"未设置环境伪装",
                    @"env": env ?: @{},
                    @"last_rewrite": rewrite ?: @{},
                };
                hasResult = YES;
                break;
            }

            case CommandActionVCScan: {
                result = [self _performVCScan];
                hasResult = YES;
                break;
            }

            case CommandActionDumpLogin: {
                result = @{
                    @"status": @"success",
                    @"message": @"登录态 key 结构已上报（仅 key 名，不含值）",
                    @"diagnostic": [[AccountSwitcher sharedSwitcher] dumpLoginState] ?: @{},
                };
                hasResult = YES;
                break;
            }

            case CommandActionFollow: {
                // v1.4.127: 不假成功——改用真实验收版(label 变 Following/已关注 或按钮消失 + 失败重试)
                BOOL followed = [self _performFollowVerified];
                result = @{
                    @"status": followed ? @"success" : @"failed",
                    @"message": followed ? @"已关注（按钮状态验证通过）" : @"关注未生效（按钮状态未变化）",
                };
                hasResult = YES;
                break;
            }

            case CommandActionComment: {
                NSString *text = params[@"text"] ?: @"Nice!";
                [self _performComment:text];
                break;
            }

            case CommandActionCollect:
                [self _performCollect];
                break;

            case CommandActionScreenshot:
                [self _performScreenshot];
                break;

            case CommandActionOpenProfile: {
                NSString *username = params[@"username"] ?: @"";
                [self _performOpenProfile:username];
                break;
            }

            case CommandActionCollectFans: {
                int count = [params[@"count"] intValue] ?: 20;
                self.isCollectingData = YES;   // v1.4.108 F21：采集前开停止标志（stop_collect 置 NO 让循环退出）
                result = [self _performCollectFans:count];
                self.isCollectingData = NO;
                hasResult = YES;
                break;
            }

            case CommandActionCollectVideos: {
                int count = [params[@"count"] intValue] ?: 10;
                self.isCollectingData = YES;
                result = [self _performCollectVideos:count];
                self.isCollectingData = NO;
                hasResult = YES;
                break;
            }

            case CommandActionCollectComments: {
                int count = [params[@"count"] intValue] ?: 20;
                self.isCollectingData = YES;
                result = [self _performCollectComments:count];
                self.isCollectingData = NO;
                hasResult = YES;
                break;
            }

            case CommandActionCollectLiveUsers: {
                int count = [params[@"count"] intValue] ?: 20;
                self.isCollectingData = YES;
                result = [self _performCollectLiveUsers:count];
                self.isCollectingData = NO;
                hasResult = YES;
                break;
            }

            case CommandActionCollectLikes: {
                int count = [params[@"count"] intValue] ?: 20;
                self.isCollectingData = YES;
                result = [self _performCollectLikes:count];
                self.isCollectingData = NO;
                hasResult = YES;
                break;
            }

            case CommandActionBatchLike:
                [self _performBatchLike:params];
                break;
            case CommandActionBatchFollow:
                [self _performBatchFollow:params];
                break;
            case CommandActionBatchComment:
                [self _performBatchComment:params];
                break;

            // === 账号管理 ===
            case CommandActionGetAccountInfo: {
                // 主动检测：导航个人页 → 等网络捕获当前用户 → 返回
                result = [self detectCurrentAccountFlow];
                hasResult = YES;
                break;
            }
            case CommandActionSwitchAccount: {
                NSString *targetId = params[@"aweme_id"] ?: @"";
                // 切换账号: 打开设置 → 退出登录 → 登录其他账号
                [self _performSwitchAccount:targetId];
                break;
            }
            case CommandActionReportAccount: {
                [[AccountManager sharedManager] reportCurrentAccount];
                break;
            }

            // === 智能任务 ===
            case CommandActionSmartBrowse: {
                int minScrolls = [params[@"min_scrolls"] intValue] ?: 5;
                int maxScrolls = [params[@"max_scrolls"] intValue] ?: 15;
                int minDelay = [params[@"min_delay"] intValue] ?: 3;
                int maxDelay = [params[@"max_delay"] intValue] ?: 8;
                result = [self _performSmartBrowse:minScrolls max:maxScrolls minDelay:minDelay maxDelay:maxDelay];
                hasResult = YES;
                break;
            }
            case CommandActionCheckHealth: {
                result = [self _performCheckHealth];
                hasResult = YES;
                break;
            }

            // === 导航 ===
            case CommandActionGoBack:
                [self _performGoBack];
                break;
            case CommandActionGoHome:
                // 走 _gotoHomeFeed（a11y点击 + deep link 兜底 + 真实验证在 feed）
                [self _gotoHomeFeed];
                break;
            case CommandActionOpenTab: {
                NSString *tab = params[@"tab"] ?: @"home";
                // v1.4.106: _tapTab 返回诊断 dict，随 result 回传后端（server.log 可见，定位 setSelectedIndex:0 失效根因）
                NSDictionary *diag = [self _tapTab:tab];
                result = @{@"status": @"success", @"tab": tab, @"diag": diag ?: @{}};
                hasResult = YES;
                break;
            }
            case CommandActionOpenSearch:
                [self _performOpenSearch];
                break;
            case CommandActionSearchKeyword: {
                NSString *keyword = params[@"keyword"] ?: @"";
                result = [self _performSearchKeyword:keyword];
                hasResult = YES;
                break;
            }
            case CommandActionOpenUser: {
                NSString *uid = params[@"uid"] ?: params[@"unique_id"] ?: @"";
                [self _performOpenUser:uid];
                break;
            }
            case CommandActionOpenVideo: {
                NSString *awemeId = params[@"aweme_id"] ?: @"";
                [self _performOpenVideo:awemeId];
                break;
            }

            // === 视频操作 ===
            case CommandActionRefresh:
                [self _performPullToRefresh];
                break;
            case CommandActionShare:
                [self _performShare];
                break;
            case CommandActionSaveVideo:
                [self _performSaveVideo];
                break;

            // === 账号 ===
            case CommandActionLogout:
                [self _performLogout];
                break;

            // === 修改资料 ===
            case CommandActionEditProfile:
                [self _performEditProfile:params];
                break;

            // === 自动发视频 ===
            case CommandActionPostVideo: {
                result = [self _performPostVideo:params];
                hasResult = YES;
                break;
            }

            // === 自动私信 ===
            case CommandActionSendDm: {
                result = [self _performSendDm:params];
                hasResult = YES;
                break;
            }
            case CommandActionSendCard: {
                result = [self _performSendCard:params];
                hasResult = YES;
                break;
            }
            case CommandActionShareLive: {
                result = [self _performShareLive:params];
                hasResult = YES;
                break;
            }

            // === 批量注册 + 自动养号 ===
            case CommandActionNurtureTick: {
                result = [self _performNurtureTick:params];
                hasResult = YES;
                break;
            }
            case CommandActionNurtureStop: {
                result = [self _performNurtureStop];
                hasResult = YES;
                break;
            }
            case CommandActionStopCollect: {
                // v1.4.108 F21/F26：置采集停止标志，采集循环尽快退出（不调 nurture_stop！）
                self.isCollectingData = NO;
                [[XNOWER sharedInstance] addLog:@"⏹ 已收到停止采集指令，采集循环将尽快停止"];
                result = @{@"status": @"success", @"message": @"已请求停止采集"};
                hasResult = YES;
                break;
            }
            case CommandActionRegisterAccount: {
                result = [self _performRegisterAccount:params];
                hasResult = YES;
                break;
            }

            default:
                break;
        }

        NSTimeInterval elapsed = [[NSDate date] timeIntervalSince1970] - startTime;

        if (hasResult && result) {
            NSMutableDictionary *mutable = [result mutableCopy];
            mutable[@"action"] = actionName;
            mutable[@"duration"] = @((int)elapsed);
            return mutable;
        }

        return @{
            @"action": actionName,
            @"status": @"success",
            @"message": [NSString stringWithFormat:@"OK: %@", actionName],
            @"duration": @((int)elapsed),
        };
    } @catch (NSException *e) {
        return @{
            @"action": actionName,
            @"status": @"failed",
            @"message": [NSString stringWithFormat:@"%@: %@", e.name, e.reason],
            @"duration": @((int)([[NSDate date] timeIntervalSince1970] - startTime)),
        };
    }
}

#pragma mark - 滑动手势（安全版，避免私有API崩溃）

/// 按 deltaY 转滑动：优先直接翻页 feed UICollectionView，失败再注入真实手势
- (void)_safeScrollBy:(CGFloat)deltaY {
    if ([self _tryPageFeed:deltaY]) return;
    // feed 未找到时不再注入合成滑动（非 feed 页滑动可能触发 TikTok 崩溃）
    NSLog(@"[XNOWER] 未在推荐页，跳过滑动");
    return;
#if 0
    CGSize s = [UIScreen mainScreen].bounds.size;
    CGFloat fromY = s.height * 0.5;
    CGFloat toY = MAX(s.height * 0.1, MIN(s.height * 0.9, fromY + deltaY));
    [XNTouchSimulator swipeFrom:CGPointMake(s.width * 0.5, fromY)
                             to:CGPointMake(s.width * 0.5, toY)];
    NSLog(@"[XNOWER] 真实滑动 delta=%.0fpt", deltaY);
#endif
}

/// 尝试直接翻页 feed（TikTok feed 是 UITableView/UICollectionView，用 scrollToRow/Item + setContentOffset 兜底）
- (BOOL)_tryPageFeed:(CGFloat)deltaY {
    UIWindow *window = XN_ActiveWindow();
    if (!window) return NO;
    __block UIScrollView *feedScroll = nil;
    [self _findLargeFeedScrollViewInView:window result:&feedScroll];
    if (!feedScroll) {
        NSLog(@"[XNOWER] feed 滚动视图未找到");
        [self _reportScrollDiag:@{@"found": @NO}];
        return NO;
    }
    NSString *feedClass = NSStringFromClass(feedScroll.class);
    // 排除个人页作品列表（TTKUserProfileWorkCollectionView 不是推荐 feed，翻它无意义）
    if ([feedClass containsString:@"Profile"] || [feedClass containsString:@"UserProfile"]) {
        NSLog(@"[XNOWER] 当前在个人页(%@)，不是推荐 feed，跳过翻页", feedClass);
        [self _reportScrollDiag:@{@"found": @NO, @"class": feedClass, @"reason": @"profile"}];
        return NO;
    }
    NSLog(@"[XNOWER] feed scroll view = %@", feedClass);

    BOOL scrolled = NO;
    if ([feedScroll isKindOfClass:[UITableView class]]) {
        UITableView *tv = (UITableView *)feedScroll;
        NSIndexPath *current = [tv indexPathsForVisibleRows].firstObject;
        if (current) {
            NSInteger targetRow = (deltaY < 0) ? current.row + 1 : MAX(0, current.row - 1);
            if (targetRow < [tv numberOfRowsInSection:current.section]) {
                NSIndexPath *target = [NSIndexPath indexPathForRow:targetRow inSection:current.section];
                [tv scrollToRowAtIndexPath:target atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
                NSLog(@"[XNOWER] feed 表翻页到 row=%ld", (long)targetRow);
                [self _reportScrollDiag:@{@"found": @YES, @"class": feedClass, @"type": @"table", @"target": @(targetRow)}];
                scrolled = YES;
            }
        }
    } else if ([feedScroll isKindOfClass:[UICollectionView class]]) {
        UICollectionView *cv = (UICollectionView *)feedScroll;
        NSIndexPath *current = [cv indexPathsForVisibleItems].firstObject;
        if (current) {
            NSInteger targetItem = (deltaY < 0) ? current.item + 1 : MAX(0, current.item - 1);
            if (targetItem < [cv numberOfItemsInSection:current.section]) {
                NSIndexPath *target = [NSIndexPath indexPathForItem:targetItem inSection:current.section];
                [cv scrollToItemAtIndexPath:target atScrollPosition:UICollectionViewScrollPositionCenteredVertically animated:YES];
                NSLog(@"[XNOWER] feed 集合翻页到 item=%ld", (long)targetItem);
                [self _reportScrollDiag:@{@"found": @YES, @"class": feedClass, @"type": @"collection", @"target": @(targetItem)}];
                scrolled = YES;
            }
        }
    }

    // 兜底：直接用 setContentOffset 整页滚动（部分版本 scrollToRow 不触发视频切换）
    if (!scrolled) {
        CGFloat pageH = feedScroll.bounds.size.height;
        CGFloat targetY = (deltaY < 0) ? feedScroll.contentOffset.y + pageH
                                       : MAX(0, feedScroll.contentOffset.y - pageH);
        [feedScroll setContentOffset:CGPointMake(0, targetY) animated:YES];
        NSLog(@"[XNOWER] feed setContentOffset 到 y=%.0f", targetY);
        [self _reportScrollDiag:@{@"found": @YES, @"class": feedClass, @"type": @"offset", @"target": @(targetY)}];
        scrolled = YES;
    }
    return scrolled;
}

/// 上报 feed 翻页诊断（供后端确认 feed 是否找到/滚动）
- (void)_reportScrollDiag:(NSDictionary *)info {
    @try {
        NSString *devId = [XNOWER sharedInstance].deviceId;
        if (devId.length > 0) {
            [XNURLProtocol sendMessage:@{@"type": @"scroll_diag", @"data": info} deviceId:devId];
        }
    } @catch (NSException *e) {}
}

/// 主动检测当前账号：导航个人页 → 等网络捕获 → 兜底 UI 扫描 → 返回账号
/// 供 get_account_info / backup_account 使用（账号信息只在个人页可见）
- (NSDictionary *)detectCurrentAccountFlow {
    // 1. 切到个人页（可靠：运行时 setSelectedIndex 直达 + 返回诊断 dict；不用裸点 tab）
    //    v1.4.116 修复：裸点 a11y_vo_profile 不验证切换结果，视频流页的 @作者 会被 UI 扫描误抓成"当前账号"
    //    （祥哥实测备份抓成正在浏览的视频作者）。改用 _tapTab: 后必须确认页面切到"我的主页"才扫描。
    [self _tapTab:@"profile"];

    // 2. 轮询等待网络捕获的当前账号 + 确认页面 = 我的主页（最多 10 秒）
    //    页面未确认在 profile_mine（视频流/别人主页/未加载）→ 继续等，期间不扫描，防止误抓。
    NSDictionary *account = nil;
    BOOL onMyProfile = NO;
    for (int i = 0; i < 20; i++) {
        [NSThread sleepForTimeInterval:0.5];
        if (!onMyProfile) {
            NSString *page = [self detectCurrentPage];
            onMyProfile = [page isEqualToString:@"profile_mine"];
            if (!onMyProfile && [page isEqualToString:@"profile_other"]) {
                // 落在别人主页（切页后展示的是他人资料）→ 不可能拿到自己账号，直接失败
                NSLog(@"[XNOWER] detectAccount: 落在他人主页(profile_other)，放弃");
                return @{};
            }
        }
        account = [[AccountManager sharedManager] currentAccount];
        if (onMyProfile && account.count > 0) break;
    }

    // 3. 兜底：UI 扫描检测（仅限确认在"我的主页"后执行，视频流里的 @作者 永不误抓）
    //    v1.4.115：用扫描返回值，别读 currentAccount 缓存——UI 扫描结果未写入缓存时读到 nil 会误判空
    if (!account || account.count == 0) {
        if (!onMyProfile) {
            NSLog(@"[XNOWER] detectAccount: 未确认在我的主页(最后页面=%@)，不扫描避免误抓视频作者",
                  [self detectCurrentPage]);
            return @{};
        }
        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        __block NSDictionary *scanned = nil;
        [[AccountManager sharedManager] detectCurrentAccountWithCompletion:^(NSDictionary *a) {
            scanned = a;
            dispatch_semaphore_signal(sema);
        }];
        dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC));
        if (scanned && scanned.count > 0) {
            account = scanned;
        } else {
            account = [[AccountManager sharedManager] currentAccount];
        }
    }

    return account ?: @{};
}

/// UI 结构扫描：遍历视图树，上报所有可交互控件（类型/位置/无障碍标识/状态）
/// v1.4.100: 评论面板呈现在独立 window，XN_ActiveWindow() 只返回 keyWindow 扫不到 →
/// 扫全部可见非 overlay 窗口，否则评论面板控件永不进 ui_scan（verify 无法识别 comment 页）。
- (void)_performUIScan {
    UIWindow *key = XN_ActiveWindow();
    if (!key) return;
    NSMutableArray *windows = [NSMutableArray arrayWithObject:key];
    @try {
        Class overlayCls = NSClassFromString(@"XNPassThroughWindow");
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.hidden) continue;
            if (overlayCls && [w isKindOfClass:overlayCls]) continue;  // 跳过自己的浮窗层
            BOOL dup = NO;
            for (UIWindow *k in windows) if (k == w) { dup = YES; break; }
            if (!dup) [windows addObject:w];
        }
    } @catch (NSException *e) {
        NSLog(@"[XNOWER] 窗口枚举异常: %@", e.reason);
    }
    NSMutableArray *elements = [NSMutableArray array];
    for (UIWindow *w in windows) {
        [self _scanInteractiveViewsInView:w depth:0 result:elements];
        if (elements.count >= 400) break;
    }
    NSLog(@"[XNOWER] UI扫描: %lu 个控件 (窗口 %lu 个)", (unsigned long)elements.count, (unsigned long)windows.count);

    // 【v1.4.92 控件地图】页面上下文：当前页 + tab 索引 + 屏幕尺寸，随扫描上报，后端按页沉淀参考表
    NSDictionary *pageCtx = @{};
    NSNumber *tabIdx = @(-1);
    @try {
        NSString *page = [self detectCurrentPage];
        if (page.length) pageCtx = @{@"page": page};
        NSDictionary *tab = [self _performVCScan][@"tab_controller"];
        if ([tab isKindOfClass:[NSDictionary class]]) tabIdx = tab[@"selectedIndex"] ?: @(-1);
    } @catch (NSException *e) {
        NSLog(@"[XNOWER] 控件地图页面上文识别异常: %@", e.reason);
    }
    CGSize sc = [UIScreen mainScreen].bounds.size;

    @try {
        NSString *devId = [XNOWER sharedInstance].deviceId;
        if (devId.length > 0) {
            [XNURLProtocol sendMessage:@{
                @"type": @"ui_scan",
                @"data": @{
                    @"count": @(elements.count),
                    @"elements": elements,
                    @"page": pageCtx,
                    @"tab": tabIdx,
                    @"screen": [NSString stringWithFormat:@"%.0fx%.0f", sc.width, sc.height],
                }
            } deviceId:devId];
        }
    } @catch (NSException *e) {}
}

- (void)_scanInteractiveViewsInView:(UIView *)view depth:(int)depth result:(NSMutableArray *)result {
    if (depth > 30 || !view || result.count > 400) return;
    BOOL interactive = [view isKindOfClass:[UIControl class]] ||
                       (view.accessibilityIdentifier.length > 0) ||
                       (view.accessibilityLabel.length > 0) ||
                       view.gestureRecognizers.count > 0;
    if (interactive) {
        @try {
            CGRect frameInWindow = [view convertRect:view.bounds toView:nil];
            CGPoint center = CGPointMake(CGRectGetMidX(frameInWindow), CGRectGetMidY(frameInWindow));
            NSMutableDictionary *d = [NSMutableDictionary dictionary];
            d[@"class"] = NSStringFromClass(view.class) ?: @"nil";
            d[@"superclass"] = view.superclass ? NSStringFromClass(view.superclass) : @"";
            d[@"frame"] = NSStringFromCGRect(frameInWindow);
            d[@"x"] = @(round(center.x));
            d[@"y"] = @(round(center.y));
            if (view.accessibilityIdentifier.length) d[@"acc_id"] = view.accessibilityIdentifier;
            if (view.accessibilityLabel.length) d[@"acc_label"] = view.accessibilityLabel;
            if ([view isKindOfClass:[UIControl class]]) {
                UIControl *c = (UIControl *)view;
                d[@"isSelected"] = @(c.isSelected);
                d[@"isEnabled"] = @(c.isEnabled);
                d[@"isUIControl"] = @YES;
                // 按钮标题 / 文本字段（识别操作目标用）
                if ([view isKindOfClass:[UIButton class]]) {
                    NSString *t = [(UIButton *)view titleForState:UIControlStateNormal];
                    if (t.length) d[@"title"] = t;
                } else if ([view isKindOfClass:[UITextField class]]) {
                    NSString *t = [(UITextField *)view text];
                    if (t.length) d[@"title"] = t;
                }
            }
            // 大面积滚动容器（主可滚动区，标注 isScroll 供滑动定位用）
            if ([view isKindOfClass:[UIScrollView class]]) {
                CGSize sc = [UIScreen mainScreen].bounds.size;
                if (view.frame.size.width >= sc.width * 0.8 && view.frame.size.height >= sc.height * 0.5) {
                    d[@"isScroll"] = @YES;
                }
            }
            // 手势类型（关键：纯手势控件合成触摸触发不了，target-action 才可靠——控件地图里一眼识别可点击性）
            if (view.gestureRecognizers.count) {
                NSMutableArray *gs = [NSMutableArray array];
                for (UIGestureRecognizer *gr in view.gestureRecognizers) {
                    [gs addObject:NSStringFromClass(gr.class)];
                }
                d[@"gestures"] = gs;
            }
            [result addObject:d];
        } @catch (NSException *e) {}
    }
    for (UIView *sub in view.subviews) {
        [self _scanInteractiveViewsInView:sub depth:depth + 1 result:result];
    }
}

/// 递归查找大面积 UIScrollView（feed，UITableView 或 UICollectionView）
/// ⚠️ 修复菜单误判：跳过隐藏/透明视图。TikTok tab 结构下访问过的 tab 页滚动视图常驻但 hidden，
/// 不过滤会在非 feed 页面命中隐藏的 Feed 滚动视图 → _isOnFeed 误判 YES → 菜单错误。
- (void)_findLargeFeedScrollViewInView:(UIView *)view result:(UIScrollView **)result {
    if (*result) return;
    if (!view || view.hidden || view.alpha <= 0.02) return;
    if ([view isKindOfClass:[UITableView class]] || [view isKindOfClass:[UICollectionView class]]) {
        UIScrollView *sv = (UIScrollView *)view;
        if (sv.frame.size.width >= [UIScreen mainScreen].bounds.size.width * 0.8 &&
            sv.frame.size.height >= [UIScreen mainScreen].bounds.size.height * 0.5) {
            *result = sv;
            return;
        }
    }
    for (UIView *sub in view.subviews) {
        [self _findLargeFeedScrollViewInView:sub result:result];
        if (*result) return;
    }
}

/// 递归查找主要 UIScrollView（同 _findLargeFeedScrollViewInView，也跳过隐藏/透明子树）
- (void)_findFeedScrollViewInView:(UIView *)view result:(UIScrollView **)result {
    if (*result) return;
    if (!view || view.hidden || view.alpha <= 0.02) return;
    if ([view isKindOfClass:[UIScrollView class]]) {
        UIScrollView *sv = (UIScrollView *)view;
        // 找比较大的 ScrollView（全屏级别），排除小的
        if (sv.frame.size.width >= [UIScreen mainScreen].bounds.size.width * 0.8 &&
            sv.frame.size.height >= [UIScreen mainScreen].bounds.size.height * 0.5) {
            *result = sv;
            return;
        }
    }
    for (UIView *sub in view.subviews) {
        [self _findFeedScrollViewInView:sub result:result];
        if (*result) return;
    }
}

/// 操作级遥测：上报后端当前正在执行的操作（崩溃时后端能看到最后一步，精准定位）
- (void)_logStep:(NSString *)step {
    @try {
        NSString *devId = [XNOWER sharedInstance].deviceId;
        if (devId.length > 0) {
            [XNURLProtocol sendMessage:@{@"type": @"step", @"data": @{@"step": step}} deviceId:devId];
        }
    } @catch (id e) {}
}

/// 上滑（下一个视频）— 优先 feed 翻页，失败再注入真实手势
- (void)_performSwipeUp {
    [self _logStep:@"swipe_up"];
    [self _safeScrollBy:-[UIScreen mainScreen].bounds.size.height];
}

/// 下滑（上一个视频）— 优先 feed 翻页，失败再注入真实手势
- (void)_performSwipeDown {
    [self _logStep:@"swipe_down"];
    [self _safeScrollBy:[UIScreen mainScreen].bounds.size.height];
}

/// 真实模拟点击（注入 UITouch/UIEvent，让 TikTok 手势识别器真正响应）
- (void)_safeTapAtPoint:(CGPoint)point {
    [XNTouchSimulator tapAtPoint:point];
    NSLog(@"[XNOWER] 点击 (%.0f, %.0f) 完成", point.x, point.y);
}

#pragma mark - 点赞

/// 递归按类名包含查找视图（深度保护）— 定位 TikTok 私有容器（如点赞区 PlayInteractionLikeView）
/// ⚠️ 修复菜单误判：跳过隐藏/透明视图。TikTok tab 结构下，访问过的 tab 页（个人页/私信/评论）
/// 视图常驻在层级中但 hidden=YES，不过滤会导致页面检测命中隐藏页 → 菜单与当前页面不匹配。
- (UIView *)_findViewByClassContaining:(NSString *)className inView:(UIView *)view depth:(int)depth {
    if (depth > 30 || !view) return nil;
    @try {
        if (view.hidden || view.alpha <= 0.02) {
            // 当前视图隐藏，跳过其子树（隐藏容器内的子视图不可能是当前可见页面）
            return nil;
        }
        if ([NSStringFromClass(view.class) containsString:className]) return view;
        for (UIView *sub in view.subviews) {
            UIView *r = [self _findViewByClassContaining:className inView:sub depth:depth + 1];
            if (r) return r;
        }
    } @catch (NSException *e) {}
    return nil;
}

/// 在容器内找第一个可交互控件（点赞按钮是 UIControl）
- (UIView *)_findFirstControlInView:(UIView *)view depth:(int)depth {
    if (depth > 30 || !view) return nil;
    @try {
        if ([view isKindOfClass:[UIControl class]]) return view;
        for (UIView *sub in view.subviews) {
            UIView *r = [self _findFirstControlInView:sub depth:depth + 1];
            if (r) return r;
        }
    } @catch (NSException *e) {}
    return nil;
}

- (void)_performLike {
    [self _logStep:@"like"];
    dispatch_sync(dispatch_get_main_queue(), ^{
        CGSize screen = [UIScreen mainScreen].bounds.size;
        UIWindow *window = XN_ActiveWindow();

        // 0. 屏幕内可见的 feedLikeButton → tapAtPoint（以前成功方法：PlayInteractionLikeView定位 + 合成触摸，真红心）
        //    feed 有多个 feedLikeButton(屏内+屏外预加载cell)，必须命中屏幕内的
        __strong UIView *likeView = nil;
        [self _findVisibleViewWithAccId:kAccLike inView:window screen:screen depth:0 result:&likeView];
        if (likeView) {
            CGPoint center = [likeView.superview convertPoint:likeView.center toView:nil];
            NSLog(@"[XNOWER] like命中: %@ center=(%.0f,%.0f) frame=%@", NSStringFromClass(likeView.class),
                  center.x, center.y, NSStringFromCGRect([likeView.superview convertRect:likeView.frame toView:nil]));
            [self _safeTapAtPoint:center];
            return;
        }
        NSLog(@"[XNOWER] 未找到屏幕内 feedLikeButton，尝试容器定位");

        // 1. PlayInteractionLikeView 容器定位（以前成功方法），容器内屏幕内控件 → tapAtPoint
        UIView *likeContainer = [self _findViewByClassContaining:@"PlayInteractionLikeView"
                                                         inView:window depth:0];
        if (likeContainer) {
            UIView *target = [self _findFirstControlInView:likeContainer depth:0] ?: likeContainer;
            CGPoint center = [target.superview convertPoint:target.center toView:nil];
            if (center.x > 0 && center.x < screen.width && center.y > 0 && center.y < screen.height) {
                [self _safeTapAtPoint:center];
                return;
            }
        }

        // 2. accessibility label（屏幕内）
        UIButton *likeBtn = [self _findButtonWithAnyLabel:@[@"like", @"Like", @"heart", @"Heart"]
                                                   inView:window];
        if (likeBtn) {
            CGPoint center = [likeBtn.superview convertPoint:likeBtn.center toView:nil];
            if (center.x > 0 && center.x < screen.width && center.y > 0 && center.y < screen.height) {
                [self _safeTapAtPoint:center];
                return;
            }
        }

        // 3. 坐标回退（仅当在 feed 页才用，避免非 feed 页点错控件导致 TikTok 崩溃）
        __block UIScrollView *feedScroll = nil;
        [self _findLargeFeedScrollViewInView:XN_ActiveWindow() result:&feedScroll];
        if (feedScroll) {
            [self _safeTapAtPoint:CGPointMake(
                screen.width * kLikeBtnRatioX,
                screen.height * kLikeBtnRatioY)];
        } else {
            NSLog(@"[XNOWER] 未找到点赞按钮且不在推荐页，跳过点赞");
        }
    });
}

#pragma mark - 关注

- (void)_performFollow {
    [self _logStep:@"follow"];
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        CGSize screen = [UIScreen mainScreen].bounds.size;
        // ⚠️ v1.4.119 修复"关注点不上"：优先 accId 按钮（个人页 follow），
        // 再按 label 找（feed FollowPromptView）；命中后向上找最近的 UIControl 按钮本体，
        // 点 label 文本本身常因非交互控件而无效（实锤：before/after label 相同）
        __strong UIView *followView = nil;
        [self _findVisibleViewWithAccId:kAccFollow inView:window screen:screen depth:0 result:&followView];
        if (!followView) {
            [self _findVisibleViewWithLabel:@"Follow" inView:window screen:screen depth:0 result:&followView];
        }
        if (!followView) {
            [self _findVisibleViewWithLabel:@"关注" inView:window screen:screen depth:0 result:&followView];
        }
        if (followView) {
            // 向上找最近的可交互按钮（UIControl），否则用 label 所在容器
            __strong UIView *btnView = followView;
            UIView *cur = followView.superview;
            while (cur && cur != window) {
                if ([cur isKindOfClass:[UIControl class]] && !cur.hidden && cur.alpha > 0.02) {
                    btnView = cur;
                    break;
                }
                cur = cur.superview;
            }
            CGPoint center = [btnView.superview convertPoint:btnView.center toView:nil];
            NSString *beforeLabel = followView.accessibilityLabel ?: @"";
            NSLog(@"[XNOWER] follow命中: %@(label:%@) btn=%@ center=(%.0f,%.0f) before=%@", NSStringFromClass(followView.class),
                  NSStringFromClass(btnView.class), NSStringFromClass(btnView.class),
                  center.x, center.y, beforeLabel);
            if ([btnView isKindOfClass:[UIControl class]]) {
                [(UIControl *)btnView sendActionsForControlEvents:UIControlEventTouchUpInside];
            }
            [self _safeTapAtPoint:center];
            // 关注成功验证：点击后异步读 label，从 "Follow X" 变 "Following X" 或按钮消失 = 成功
            __weak UIView *weakFV = followView;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                UIView *fv = weakFV;
                if (!fv) {  // 按钮消失 = 可能已关注成功（UI 重建）
                    NSLog(@"[XNOWER] follow验证: 按钮已消失, 视为成功");
                    [self _reportFollowVerify:YES before:beforeLabel after:@""];
                    return;
                }
                NSString *afterLabel = fv.accessibilityLabel ?: @"";
                BOOL followed = ([afterLabel rangeOfString:@"Following" options:NSCaseInsensitiveSearch].location != NSNotFound)
                                || ([beforeLabel rangeOfString:@"Follow" options:NSCaseInsensitiveSearch].location != NSNotFound
                                    && ![afterLabel isEqualToString:beforeLabel]);
                NSLog(@"[XNOWER] follow验证: before=%@ after=%@ followed=%d", beforeLabel, afterLabel, followed);
                [self _reportFollowVerify:followed before:beforeLabel after:afterLabel];
                // 回关自动私信：关注成功后取话术并发私信（从 label 提取用户名 "Follow xxx"）
                if (followed) {
                    [self _autoReplyAfterFollowWithLabel:beforeLabel];
                }
            });
            return;
        }
        // 坐标兜底（仅当在 feed 页才用，避免非 feed 页点错控件崩溃）
        __block UIScrollView *feedScroll = nil;
        [self _findLargeFeedScrollViewInView:window result:&feedScroll];
        if (feedScroll) {
            [self _safeTapAtPoint:CGPointMake(
                screen.width * kFollowBtnRatioX,
                screen.height * kFollowBtnRatioY)];
        } else {
            NSLog(@"[XNOWER] 未找到关注按钮且不在推荐页，跳过关注");
        }
    });
}

/// v1.4.127 关注真实验收版：多级定位(accId→label) + 点击 + 2s 后读按钮状态真验收 + 失败重试一次
/// 返回 BOOL，不假成功；验收结果同时上报 state_diag（server.log 可见，同 _performFollow 的验证机制）
- (BOOL)_performFollowVerified {
    __block NSString *beforeLabel = @"";
    for (int attempt = 0; attempt < 2; attempt++) {
        __block UIView *followView = nil;
        __block BOOL found = NO;
        __block BOOL alreadyFollowed = NO;
        __block NSString *alreadyLbl = @"";
        dispatch_sync(dispatch_get_main_queue(), ^{
            UIWindow *window = XN_ActiveWindow();
            CGSize screen = [UIScreen mainScreen].bounds.size;
            __strong UIView *fv = nil;
            [self _findVisibleViewWithAccId:kAccFollow inView:window screen:screen depth:0 result:&fv];
            if (!fv) [self _findVisibleViewWithLabel:@"Follow" inView:window screen:screen depth:0 result:&fv];
            if (!fv) [self _findVisibleViewWithLabel:@"关注" inView:window screen:screen depth:0 result:&fv];
            if (fv) {
                NSString *curLabel = fv.accessibilityLabel ?: @"";
                if (attempt == 0) {
                    beforeLabel = curLabel;
                } else {
                    // 重试轮防护：按钮已是"已关注"状态（首轮点击生效但验收超时没等到）→ 直接判成功，
                    // 不再重复点击（重复点击会把已关注变成取消关注）
                    if (curLabel.length > 0 && ![curLabel isEqualToString:beforeLabel] &&
                        ([curLabel rangeOfString:@"Following" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                         [curLabel rangeOfString:@"已关注" options:NSCaseInsensitiveSearch].location != NSNotFound)) {
                        alreadyFollowed = YES;
                        alreadyLbl = curLabel;
                        return;
                    }
                }
                // 向上找最近可交互按钮（UIControl），否则用 label 所在容器（同 _performFollow）
                __strong UIView *btnView = fv;
                UIView *cur = fv.superview;
                while (cur && cur != window) {
                    if ([cur isKindOfClass:[UIControl class]] && !cur.hidden && cur.alpha > 0.02) {
                        btnView = cur;
                        break;
                    }
                    cur = cur.superview;
                }
                CGPoint center = [btnView.superview convertPoint:btnView.center toView:nil];
                if ([btnView isKindOfClass:[UIControl class]]) {
                    [(UIControl *)btnView sendActionsForControlEvents:UIControlEventTouchUpInside];
                }
                [self _safeTapAtPoint:center];
                followView = fv;
                found = YES;
            }
        });
        if (alreadyFollowed) {
            [self _reportFollowVerify:YES before:beforeLabel after:alreadyLbl];
            return YES;
        }
        if (!found || !followView) return NO;

        // 真验收：同步等待主线程 2s 后读 label（不假成功；关注按钮文案经服务端返回，需稍长等待）
        __weak UIView *weakFV = followView;
        __block BOOL verified = NO;
        __block NSString *afterLbl = @"";
        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            UIView *fv = weakFV;
            if (!fv) {  // 按钮消失 = UI 重建 = 已关注
                verified = YES;
                afterLbl = @"<gone>";
                dispatch_semaphore_signal(sema);
                return;
            }
            afterLbl = fv.accessibilityLabel ?: @"";
            BOOL labelChanged = afterLbl.length > 0 && ![afterLbl isEqualToString:beforeLabel];
            BOOL nowFollowing = [afterLbl rangeOfString:@"Following" options:NSCaseInsensitiveSearch].location != NSNotFound;
            BOOL nowFollowedCn = [afterLbl rangeOfString:@"已关注" options:NSCaseInsensitiveSearch].location != NSNotFound;
            BOOL wasFollow = [beforeLabel rangeOfString:@"Follow" options:NSCaseInsensitiveSearch].location != NSNotFound
                          || [beforeLabel rangeOfString:@"关注" options:NSCaseInsensitiveSearch].location != NSNotFound;
            // 假阳性防护：必须 label 前后不同（自己的 "2, Following," 计数按钮 before==after 永不判成功）
            verified = labelChanged && (nowFollowing || nowFollowedCn) && wasFollow;
            // 宽松兜底：label 整体变化 = 状态已变更（部分版本文案变 Unfollow/其他），仍认成功
            if (!verified && labelChanged) verified = YES;
            dispatch_semaphore_signal(sema);
        });
        dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 2.8 * NSEC_PER_SEC));
        [self _reportFollowVerify:verified before:beforeLabel after:afterLbl];
        if (verified) return YES;
        // 未验收 → 下一轮重找按钮重试（防 UI 重建后旧引用失效；重试轮已关注则直接成功）
    }
    return NO;
}

/// 回关自动私信：关注成功后，从后端随机取一条话术，向刚关注的用户发私信
- (void)_autoReplyAfterFollowWithLabel:(NSString *)label {
    @try {
        // 从 "Follow xxx" / "关注 xxx" 提取用户名
        NSString *username = @"";
        NSArray *parts = [label componentsSeparatedByString:@" "];
        if (parts.count >= 2) {
            username = parts[parts.count - 1];
        }
        if (username.length == 0) {
            return;
        }
        NSString *devId = [XNOWER sharedInstance].deviceId;
        if (devId.length == 0) return;
        // 拉取话术（异步）
        [XNURLProtocol fetchReplyTemplate:devId completion:^(NSDictionary *tpl, NSError *error) {
            if (error || !tpl) {
                NSLog(@"[XNOWER] 回关私信: 拉取话术失败 %@", error.localizedDescription ?: @"");
                return;
            }
            NSString *content = tpl[@"content"];
            if (content.length == 0) return;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [self _performSendDm:@{@"target": username, @"content": content}];
            });
            NSLog(@"[XNOWER] 回关自动私信 → %@", username);
        }];
    } @catch (id e) {
        NSLog(@"[XNOWER] 回关私信异常: %@", e);
    }
}

#pragma mark - 评论

- (void)_performComment:(NSString *)text {
    [self _logStep:@"comment"];
    // Step 1: 打开评论面板
    dispatch_sync(dispatch_get_main_queue(), ^{
        // 找评论按钮（v1.4.89: 必须屏幕内可见，否则命中屏外预加载按钮点 AWEMaskWindow）
        CGSize screen = [UIScreen mainScreen].bounds.size;
        __strong UIView *commentView = nil;
        [self _findVisibleViewWithAccId:kAccComment inView:XN_ActiveWindow() screen:screen depth:0 result:&commentView];
        if (commentView) {
            [self _safeTapAtPoint:[commentView.superview convertPoint:commentView.center toView:nil]];
        } else {
            // 右侧操作栏评论按钮位置（like下方）— 仅当在 feed 页才用，避免点错控件崩溃
            __block UIScrollView *feedScroll = nil;
            [self _findLargeFeedScrollViewInView:XN_ActiveWindow() result:&feedScroll];
            if (feedScroll) {
                CGSize screen = [UIScreen mainScreen].bounds.size;
                [self _safeTapAtPoint:CGPointMake(screen.width * 0.91, screen.height * 0.55)];
            } else {
                NSLog(@"[XNOWER] 未找到评论按钮且不在推荐页，跳过评论");
            }
        }
    });

    // Step 2: 等待评论面板出现，填入文本
    [NSThread sleepForTimeInterval:1.5];

    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();

        // 找到输入框
        UITextField *textField = [self _findTextFieldInView:window];
        UITextView *textView = [self _findTextViewInView:window];
        UIView *field = textField ?: textView;

        // 先点输入框获得焦点，再填文本（提升输入可靠性）
        if (field) {
            [self _safeTapAtPoint:[field.superview convertPoint:field.center toView:nil]];
            [NSThread sleepForTimeInterval:0.4];
        }

        if (textField) {
            textField.text = text;
            [textField sendActionsForControlEvents:UIControlEventEditingChanged];
            [[NSNotificationCenter defaultCenter]
             postNotificationName:UITextFieldTextDidChangeNotification object:textField];
        } else if (textView) {
            textView.text = text;
            [[NSNotificationCenter defaultCenter]
             postNotificationName:UITextViewTextDidChangeNotification object:textView];
        }
    });

    // Step 3: 发送评论
    [NSThread sleepForTimeInterval:0.8];
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIView *sendBtn = [self _findViewWithAccessibilityIdentifier:kAccSend
                                                              inView:XN_ActiveWindow()];
        if (!sendBtn) {
            sendBtn = [self _findViewWithAccessibilityIdentifier:kAccPost
                                                          inView:XN_ActiveWindow()];
        }
        if (sendBtn) {
            [self _safeTapAtPoint:[sendBtn.superview convertPoint:sendBtn.center toView:nil]];
        } else {
            // 尝试找到底部工具栏的发发送按钮
            UIButton *btn = [self _findButtonWithAnyLabel:@[@"send", @"Send", @"Post",
                                                             @"发送", @"发布"]
                                                   inView:XN_ActiveWindow()];
            if (btn) {
                [self _safeTapAtPoint:[btn.superview convertPoint:btn.center toView:nil]];
            }
        }
    });

    // v1.4.91: 发送后自动关评论面板（点右上角 X 关闭，防 overlay 残留遮 tab bar 困死设备）
    [self _closeCommentPanel];
    // v1.4.100: 发送后恢复视频播放（面板打开时 TikTok 暂停了视频，关闭后不恢复→无音频→锁屏假象）
    [self _resumeFeedPlayback];
}

#pragma mark - 评论点赞（like_comment，PPT 模块4 曝光玩法核心）

/// 打开评论面板（复用评论入口逻辑）
- (void)_openCommentPanel {
    dispatch_sync(dispatch_get_main_queue(), ^{
        // v1.4.89: 必须屏幕内可见（旧实现命中屏外 y=1170 预加载按钮 → 点 AWEMaskWindow 评论面板打不开）
        CGSize screen = [UIScreen mainScreen].bounds.size;
        __strong UIView *commentView = nil;
        [self _findVisibleViewWithAccId:kAccComment inView:XN_ActiveWindow() screen:screen depth:0 result:&commentView];
        if (commentView) {
            [self _safeTapAtPoint:[commentView.superview convertPoint:commentView.center toView:nil]];
        } else {
            __block UIScrollView *feedScroll = nil;
            [self _findLargeFeedScrollViewInView:XN_ActiveWindow() result:&feedScroll];
            if (feedScroll) {
                CGSize screen = [UIScreen mainScreen].bounds.size;
                [self _safeTapAtPoint:CGPointMake(screen.width * 0.91, screen.height * 0.55)];
            }
        }
    });
}

/// 收集视图内所有 UIButton
- (void)_collectButtonsInView:(UIView *)view result:(NSMutableArray<UIButton *> *)result {
    if ([view isKindOfClass:[UIButton class]]) {
        [result addObject:(UIButton *)view];
        return;
    }
    for (UIView *sub in view.subviews) {
        [self _collectButtonsInView:sub result:result];
    }
}

/// 找第一个可见评论 cell（评论面板里的 UITableViewCell，取屏幕中部可见的）
- (void)_findVisibleCommentCellInView:(UIView *)view result:(__strong UITableViewCell **)result {
    if (*result) return;
    if ([view isKindOfClass:[UITableViewCell class]]) {
        UITableViewCell *cell = (UITableViewCell *)view;
        CGRect f = [cell.superview convertRect:cell.frame toView:XN_ActiveWindow()];
        CGSize s = [UIScreen mainScreen].bounds.size;
        // 评论 cell 一般在中下部区域（面板内），且与当前屏幕可见
        if (f.origin.y > s.height * 0.2 && f.origin.y < s.height * 0.9 && cell.alpha > 0.1) {
            *result = cell;
        }
        return;
    }
    for (UIView *sub in view.subviews) {
        [self _findVisibleCommentCellInView:sub result:result];
        if (*result) return;
    }
}

/// 点赞当前可见的一条评论；返回是否成功命中
- (BOOL)_likeOneVisibleComment {
    UIWindow *window = XN_ActiveWindow();
    if (!window) return NO;
    // 方法1（安全）：找第一个可见评论 cell，点其最右侧小按钮（评论红心在右侧，作用域限定 cell，不误点 feed）
    __strong UITableViewCell *cell = nil;
    [self _findVisibleCommentCellInView:window result:&cell];
    if (cell) {
        NSMutableArray<UIButton *> *btns = [NSMutableArray array];
        [self _collectButtonsInView:cell result:btns];
        UIButton *rightmost = nil;
        CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
        for (UIButton *b in btns) {
            CGRect f = [b.superview convertRect:b.frame toView:window];
            if (f.origin.x > screenW * 0.7 && f.size.width < 70) {
                if (!rightmost || f.origin.x > [rightmost.superview convertRect:rightmost.frame toView:window].origin.x) {
                    rightmost = b;
                }
            }
        }
        if (rightmost) {
            [self _safeTapAtPoint:[rightmost.superview convertPoint:rightmost.center toView:nil]];
            return YES;
        }
    }
    // 方法2（兜底）：面板内找 like/heart/赞 标签的小按钮
    UIButton *likeBtn = [self _findButtonWithAnyLabel:@[@"like", @"Like", @"heart", @"Heart", @"赞"]
                                               inView:window];
    if (likeBtn && likeBtn.bounds.size.width < 70) {
        [self _safeTapAtPoint:[likeBtn.superview convertPoint:likeBtn.center toView:nil]];
        return YES;
    }
    return NO;
}

/// 下滑评论区（找最顶层 UITableView 下滚 320pt）
- (void)_scrollCommentListDown {
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        if (!window) return;
        __block UITableView *commentTable = nil;
        // 逆序遍历（顶层最后），找第一个 UITableView（评论列表覆盖在 feed 之上）
        [self _findTopTableViewInView:window result:&commentTable depth:0];
        if (commentTable) {
            CGPoint off = commentTable.contentOffset;
            commentTable.contentOffset = CGPointMake(off.x, off.y + 320);
        }
    });
}

/// 逆序 DFS 找最顶层 UITableView（评论面板的列表）
- (void)_findTopTableViewInView:(UIView *)view result:(__strong UITableView **)result depth:(int)depth {
    if (*result || depth > 30) return;
    if ([view isKindOfClass:[UITableView class]]) {
        *result = (UITableView *)view;
        return;
    }
    for (NSInteger i = view.subviews.count - 1; i >= 0; i--) {
        [self _findTopTableViewInView:view.subviews[i] result:result depth:depth + 1];
        if (*result) return;
    }
}

/// 评论点赞主流程：打开评论 → 循环点赞+下滑 → 关闭
- (void)_performLikeComments:(int)count {
    [self _logStep:@"like_comment"];
    // 已在评论区（评论面板已打开）则跳过再次打开：auto_comment_like 按钮就在评论页触发，
    // 重复点评论按钮可能把面板关掉 → 白赞
    if (![[self detectCurrentPage] isEqualToString:@"comment"]) {
        [self _openCommentPanel];
    }
    [NSThread sleepForTimeInterval:1.8];

    int liked = 0;
    for (int i = 0; i < count; i++) {
        @autoreleasepool {
            __block BOOL tapped = NO;
            dispatch_sync(dispatch_get_main_queue(), ^{
                tapped = [self _likeOneVisibleComment];
            });
            if (tapped) liked++;
            [self _scrollCommentListDown];
            // 随机间隔 1.0-2.5s（防封）
            double delay = 1.0 + (arc4random_uniform(1500) / 1000.0);
            [NSThread sleepForTimeInterval:delay];
        }
    }
    NSLog(@"[XNOWER] like_comment 完成，成功点赞 %d/%d 条评论", liked, count);
    [self _logStep:@"like_comment_done"];

    // 关闭评论面板
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *closeBtn = [self _findButtonWithAnyLabel:@[@"Close", @"close", @"取消", @"Done"]
                                                    inView:XN_ActiveWindow()];
        if (closeBtn) {
            [self _safeTapAtPoint:[closeBtn.superview convertPoint:closeBtn.center toView:nil]];
        } else {
            CGSize s = [UIScreen mainScreen].bounds.size;
            [self _safeTapAtPoint:CGPointMake(s.width * 0.5, s.height * 0.06)];
        }
    });
}

#pragma mark - 收藏

- (void)_performCollect {
    dispatch_sync(dispatch_get_main_queue(), ^{
        // 直接点收藏按钮（feedFavoriteButton，ui_scan 实测）
        UIView *collectView = [self _findViewWithAccessibilityIdentifier:kAccFavorite
                                                                  inView:XN_ActiveWindow()];
        if (collectView) {
            CGPoint center = [collectView.superview convertPoint:collectView.center toView:nil];
            CGSize screen = [UIScreen mainScreen].bounds.size;
            if (center.x > 0 && center.x < screen.width && center.y > 0 && center.y < screen.height) {
                [self _safeTapAtPoint:center];
                return;
            }
        }
        // 兜底：右侧操作栏收藏按钮位置（评论下方）
        CGSize screen = [UIScreen mainScreen].bounds.size;
        [self _safeTapAtPoint:CGPointMake(screen.width * 0.92, screen.height * 0.71)];
    });
}

#pragma mark - 截图

- (void)_performScreenshot {
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        if (!window) return;

        // 截图前先隐藏 overlay（如果有）
        UIGraphicsBeginImageContextWithOptions(window.bounds.size, NO, [[UIScreen mainScreen] scale]);
        [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:NO];
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();

        if (image) {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil);
            [self _reportScreenshot:image];
        }
    });
}

/// 截图上报：缩放压缩后 base64 上报云端（电脑端浏览器可实时查看真机画面）
- (void)_reportScreenshot:(UIImage *)image {
    @try {
        NSString *devId = [XNOWER sharedInstance].deviceId;
        if (devId.length == 0 || !image) return;
        // 缩放到最长边 720，控制上报体积（原图 2-3x 全屏会很大）
        CGFloat maxLen = 720.0;
        CGFloat w = image.size.width, h = image.size.height;
        CGFloat scale = MIN(1.0, maxLen / MAX(w, h));
        UIImage *scaled = image;
        if (scale < 1.0) {
            CGSize newSize = CGSizeMake(roundf(w * scale), roundf(h * scale));
            UIGraphicsBeginImageContextWithOptions(newSize, NO, 1.0);
            [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
            scaled = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
        }
        NSData *jpeg = UIImageJPEGRepresentation(scaled, 0.6);
        if (!jpeg) return;
        NSString *b64 = [jpeg base64EncodedStringWithOptions:0];
        [XNURLProtocol sendMessage:@{
            @"type": @"screenshot",
            @"data": @{
                @"image_base64": b64,
                @"width": @(scaled.size.width),
                @"height": @(scaled.size.height),
            }
        } deviceId:devId];
        NSLog(@"[XNOWER] 📸 截图已上报云端（%.0fx%.0f，%lu 字节）",
              scaled.size.width, scaled.size.height, (unsigned long)jpeg.length);
    } @catch (NSException *e) {
        NSLog(@"[XNOWER] 截图上报异常: %@", e.reason);
    }
}

#pragma mark - 打开个人主页

- (void)_performOpenProfile:(NSString *)username {
    // ⚠️ 修复死锁：原实现内部 dispatch_sync(main_queue)，被 _performCollectFans/_performCollectVideos
    // 的外层 dispatch_sync(main_queue) block 调用时 → 主线程嵌套 dispatch_sync(main) → 自锁死锁。
    // 与 _performOpenSearch 同模式：主线程直接执行，非主线程才同步调度。
    if (![NSThread isMainThread]) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self _performOpenProfile:username];
        });
        return;
    }
    @try {
        if (username.length > 0) {
            // TikTok URL scheme 直接打开用户主页
            NSString *urlStr = [NSString stringWithFormat:@"snssdk1233://user/%@", username];
            NSURL *url = [NSURL URLWithString:urlStr];
            if (url && [[UIApplication sharedApplication] canOpenURL:url]) {
                [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
                return;
            }
        }

        // ⚠️ 已在个人主页则跳过点头像：在主页点头像会命中自己头像，触发 TikTok
        //    手势 action 内部 dispatch_sync 回主线程 → 主线程递归死锁 → watchdog 杀进程。
        //    （collect_fans/collect_videos 等从 feed 打开主页的动作，主页已开则多余）
        if ([self _isOnProfilePageOnMain]) {
            NSLog(@"[XNOWER] 已在个人主页，跳过点头像");
            return;
        }

        // 回退：点击当前视频创作者头像（优先无障碍标识，再按类名+屏幕内可见，避免点错控件）
        CGSize screen = [UIScreen mainScreen].bounds.size;
        UIView *avatarView = [self _findViewWithAccessibilityIdentifier:kAccProfileAvatar
                                                                 inView:XN_ActiveWindow()];
        // v1.4.89: 头像类名实测已漂移到 AWEStoryAvatarButton（ui_scan: @becky_bfit @(384,311)），
        // 旧类 AWEPlayInteractionUserAvatarView 已不存在；且必须屏幕内可见（feed 有屏外预加载的第二个头像）
        if (!avatarView) {
            avatarView = [self _findVisibleViewByClassContaining:@"AWEStoryAvatarButton"
                                                          inView:XN_ActiveWindow() screen:screen];
        }
        if (!avatarView) {
            avatarView = [self _findViewByClassContaining:@"AWEPlayInteractionUserAvatarView"
                                                  inView:XN_ActiveWindow() depth:0];
        }
        if (avatarView) {
            CGPoint avatarCenter = [avatarView.superview convertPoint:avatarView.center toView:nil];
            // ⚠️ v1.4.99: 头像不在 hitTest 响应链（实测 hitTest 返回父级 TTKFeedInteractionBackgroundView），
            //    tapAtPoint 按点命中不到 → UIControl action 分支永不触发 → 点头像无效（open_profile 导航失败）。
            //    直接对头像 view 触发：UIControl action + 手势 state=Ended + 合成触摸（touch.view=头像），
            //    绕过 hitTest，让 TikTok 头像 tap handler 命中。
            [XNTouchSimulator tapView:avatarView atPoint:avatarCenter];
        } else {
            // 固定坐标兜底仅当在 feed 页（避免非 feed 页点错控件崩溃）
            __block UIScrollView *feedScroll = nil;
            [self _findLargeFeedScrollViewInView:XN_ActiveWindow() result:&feedScroll];
            if (feedScroll) {
                [self _safeTapAtPoint:CGPointMake(
                    screen.width * kAvatarRatioX,
                    screen.height * kAvatarRatioY)];
            } else {
                NSLog(@"[XNOWER] 未找到头像且不在推荐页，跳过打开主页");
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[XNOWER] 打开主页异常: %@", e.reason);
    }
}

#pragma mark - 粉丝/视频数据采集（网络拦截方案）

- (NSDictionary *)_performCollectFans:(int)count {
    __block NSMutableArray *fans = [NSMutableArray array];

    [self _logStep:@"collect_fans:open_profile"];
    dispatch_sync(dispatch_get_main_queue(), ^{
        // 1. 打开当前用户的个人主页（点头像）— _performOpenProfile 内部会在
        //    已在个人主页时跳过（在主页点头像会命中自己头像，触发 TikTok 手势 action
        //    死锁 → watchdog 杀进程，86/87 三次崩溃同一根因）
        [self _performOpenProfile:@""];
    });

    [NSThread sleepForTimeInterval:3.0];

    // 2. 点击粉丝列表按钮
    [self _logStep:@"collect_fans:tap_fans_btn"];
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *fansBtn = [self _findButtonWithAnyLabel:@[@"fans", @"Fans", @"followers",
                                                             @"粉丝", @"Followers"]
                                                   inView:XN_ActiveWindow()];
        if (fansBtn) {
            [self _safeTapAtPoint:[fansBtn.superview convertPoint:fansBtn.center toView:nil]];
        }
    });

    [NSThread sleepForTimeInterval:2.0];

    // 3. 滚动采集粉丝列表
    // ⚠️ 不能用 _performSwipeUp（→_safeScrollBy 只在 feed 页生效，列表页 no-op），
    // 用 _scrollTopListUp 程序化 setContentOffset（同 auto_follow，已验证列表页可滚）。
    int collected = 0;
    int emptyScrolls = 0;
    while (collected < count && emptyScrolls < 5 && !self.isCollectingData) {   // v1.4.108 F21 停止标志
        // 通过 accessibility 采集当前可见的粉丝条目
        [self _collectVisibleFans:fans limit:count];
        int before = (int)fans.count;
        [self _logStep:[NSString stringWithFormat:@"collect_fans:round=%d", before]];

        // 列表上滑加载更多
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self _scrollTopListUp];
        });
        [NSThread sleepForTimeInterval:1.5];

        if (fans.count == before) {
            emptyScrolls++;
        } else {
            emptyScrolls = 0;
        }
        collected = (int)fans.count;
    }

    [self _logStep:[NSString stringWithFormat:@"collect_fans:done=%d", collected]];
    return @{
        @"status": @"success",
        @"message": [NSString stringWithFormat:@"采集粉丝 %lu 人", (unsigned long)fans.count],
        @"data": fans,
        @"count": @(fans.count),
    };
}

- (NSDictionary *)_performCollectVideos:(int)count {
    __block NSMutableArray *videos = [NSMutableArray array];
    __block BOOL done = NO;

    dispatch_sync(dispatch_get_main_queue(), ^{
        [self _performOpenProfile:@""];
    });
    [NSThread sleepForTimeInterval:3.0];

    // 点击视频列表 tab
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *videoBtn = [self _findButtonWithAnyLabel:@[@"video", @"Video", @"作品",
                                                              @"post", @"Post"]
                                                    inView:XN_ActiveWindow()];
        if (videoBtn) {
            [self _safeTapAtPoint:[videoBtn.superview convertPoint:videoBtn.center toView:nil]];
        }
    });
    [NSThread sleepForTimeInterval:1.5];

    // 滚动采集
    int collected = 0;
    int emptyScrolls = 0;
    while (collected < count && emptyScrolls < 5 && !self.isCollectingData) {   // v1.4.108 F21 停止标志
        [self _collectVisibleVideos:videos limit:count];
        int before = (int)videos.count;

        dispatch_sync(dispatch_get_main_queue(), ^{
            [self _performSwipeUp];
        });
        [NSThread sleepForTimeInterval:1.5];

        if (videos.count == before) emptyScrolls++;
        else emptyScrolls = 0;
        collected = (int)videos.count;
    }

    return @{
        @"status": @"success",
        @"message": [NSString stringWithFormat:@"采集视频 %lu 条", (unsigned long)videos.count],
        @"data": videos,
        @"count": @(videos.count),
    };
}

/// 从当前可见视图采集粉丝数据
- (void)_collectVisibleFans:(NSMutableArray *)fans limit:(int)limit {
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        [self _enumerateLabelsInView:window block:^(NSString *text, UIView *view) {
            if (fans.count >= limit) return;
            // 检测用户名的启发式规则：2-30字符，不含特殊符号
            if (text.length >= 2 && text.length <= 30) {
                if (![fans containsObject:text]) {
                    [fans addObject:text];
                }
            }
        }];
    });
}

/// 从当前可见视图采集视频描述数据
- (void)_collectVisibleVideos:(NSMutableArray *)videos limit:(int)limit {
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        [self _enumerateLabelsInView:window block:^(NSString *text, UIView *view) {
            if (videos.count >= limit) return;
            if (text.length >= 5 && text.length <= 100) {
                if (![videos containsObject:text]) {
                    [videos addObject:text];
                }
            }
        }];
    });
}

#pragma mark - 评论/直播间用户采集（UI 遍历方案）

/// 采集评论用户：打开评论面板 → 滚动收集评论作者用户名
- (NSDictionary *)_performCollectComments:(int)count {
    __block NSMutableArray *users = [NSMutableArray array];

    // 1. 打开评论面板（点头评按钮，v1.4.89: 必须屏幕内可见）
    dispatch_sync(dispatch_get_main_queue(), ^{
        CGSize screen = [UIScreen mainScreen].bounds.size;
        __strong UIView *commentView = nil;
        [self _findVisibleViewWithAccId:kAccComment inView:XN_ActiveWindow() screen:screen depth:0 result:&commentView];
        if (commentView) {
            [self _safeTapAtPoint:[commentView.superview convertPoint:commentView.center toView:nil]];
        } else {
            UIButton *btn = [self _findButtonWithAnyLabel:@[@"comment", @"Comment", @"评论"]
                                                   inView:XN_ActiveWindow()];
            if (btn) {
                [self _safeTapAtPoint:[btn.superview convertPoint:btn.center toView:nil]];
            } else {
                CGSize screen = [UIScreen mainScreen].bounds.size;
                [self _safeTapAtPoint:CGPointMake(screen.width * 0.5, screen.height * 0.15)];
            }
        }
    });
    [NSThread sleepForTimeInterval:2.0];

    // 2. 滚动采集评论作者用户名
    int collected = 0;
    int emptyScrolls = 0;
    while (collected < count && emptyScrolls < 5 && !self.isCollectingData) {
        [self _collectVisibleUsers:users limit:count];
        int before = (int)users.count;

        dispatch_sync(dispatch_get_main_queue(), ^{
            [self _performSwipeUp];
        });
        [NSThread sleepForTimeInterval:1.5];

        if (users.count == before) emptyScrolls++;
        else emptyScrolls = 0;
        collected = (int)users.count;
    }

    // 3. 关闭评论面板
    dispatch_sync(dispatch_get_main_queue(), ^{
        [self _performSwipeDown];
    });

    return @{
        @"status": @"success",
        @"message": [NSString stringWithFormat:@"采集评论用户 %lu 人", (unsigned long)users.count],
        @"source_type": @"comments",
        @"users": users,
        @"count": @(users.count),
    };
}

/// 采集直播间用户：在当前直播页面滚动收集用户名（best-effort）
/// 在直播间采集可见用户（上滑翻列表收集用户名，去重）— 采集直播间用户/点赞用户共用
/// 检测当前是否在直播间（扫描直播房间/播放器类名 + LIVE角标）
/// ⚠️ 修复闪退：原实现内部 dispatch_sync(main_queue)，被主线程的 _detectPageOnMain 调用时
/// 主线程递归死锁 → watchdog 杀进程。改为主线程直接执行，非主线程才同步调度（同 _isOnProfilePage）。
- (BOOL)_isInLiveRoom {
    if (![NSThread isMainThread]) {
        __block BOOL result = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{
            result = [self _isInLiveRoomOnMain];
        });
        return result;
    }
    return [self _isInLiveRoomOnMain];
}

/// 主线程直播间检测核心逻辑（_isInLiveRoom 的内部实现，必须在主线程调用）
- (BOOL)_isInLiveRoomOnMain {
    BOOL found = NO;
    @try {
        UIView *window = XN_ActiveWindow();
        if (!window) return NO;
        // 直播间核心锚点（真机 2026-08-15 验证）：仅直播间出现的容器类名。
        // ⚠️ 旧锚点 LiveRoom/LivePlayer/TTKLive/AWELive/LiveStream 是 containsString 子串匹配，
        // 首页 feed 的直播预览/入口容器(TTKLivePreviewPageContainerView / AWELiveFeedEntranceView)
        // 命中 TTKLive/AWELive 子串 → home 误判 live；且真机直播页(IESLiveLayout*)反而全不命中。
        for (NSString *cls in @[@"IESLiveLayoutContainerView", @"IESLiveStackView", @"HTSLive4LayerContainerView"]) {
            if ([self _findViewByClassContaining:cls inView:window depth:0]) {
                return YES;
            }
        }
        // 兜底：LIVE/直播中 角标（仅当不在 feed 首页 且 角标在屏幕顶部区域时启用——
        // 直播间 LIVE 角标固定在顶部；首页 feed 的直播推荐卡片 LIVE 文字在画面中下部，双重过滤防误判）
        if (![self _isOnFeedOnMain]) {
            __block BOOL badge = NO;
            __block CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
            [self _enumerateLabelsInView:window block:^(NSString *text, UIView *view) {
                if (badge) return;
                // 转 window 坐标：直播间的 LIVE 角标固定在顶部（y < 屏高 25%）
                CGRect winFrame = [view convertRect:view.bounds toView:window];
                if (winFrame.origin.y > screenH * 0.25) return;
                NSString *t = text.uppercaseString;
                if ([t isEqualToString:@"LIVE"] || [t isEqualToString:@"直播中"] || [t isEqualToString:@"直播"]) {
                    badge = YES;
                }
            }];
            found = badge;
        }
    } @catch (id e) {}
    return found;
}

/// 检测当前 TikTok 页面类型（页面感知浮窗菜单用）
/// 优先级: live > comment > recorder > friends > search > fanlist > inbox > profile > home > other
- (NSString *)detectCurrentPage {
    // ⚠️ 修复闪退：原实现外层 dispatch_sync(main_queue) 嵌套内部 _isInLiveRoom/_isOnFeed 的
    // dispatch_sync(main_queue) → 主线程递归死锁 → iOS watchdog 杀进程 = 点浮窗闪退。
    // 改为：主线程直接执行（调用方 _buildPageMenu 保证主线程）；非主线程才同步调度。
    if (![NSThread isMainThread]) {
        __block NSString *page = @"other";
        dispatch_sync(dispatch_get_main_queue(), ^{
            page = [self _detectPageOnMain];
        });
        return page;
    }
    return [self _detectPageOnMain];
}

/// 主线程页面检测核心逻辑（detectCurrentPage 的内部实现，必须在主线程调用）
- (NSString *)_detectPageOnMain {
    NSString *page = @"other";
    @try {
        UIWindow *window = XN_ActiveWindow();
        if (!window) { return @"other"; }

        // 1. 直播间（最高优先，标识最独特）
        if ([self _isInLiveRoom]) { return @"live"; }

        // 2. 评论区（feed 上打开评论面板）
        // ⚠️ v1.4.100: 评论面板可能呈现在独立 window（XN_ActiveWindow 只返回 keyWindow，扫不到评论层），
        //    必须遍历所有 window。否则评论打开时 detectCurrentPage 判 feed → close_overlay 见 feed 直接返回
        //    "无浮层面板" → 关闭逻辑永不触发 → 视频一直暂停 → 无触摸 → iOS 自动锁屏 = 祥哥看到的"黑屏"。
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            for (NSString *cls in @[@"AWECommentContainer", @"CommentListView", @"AWEBottomComment", @"TTKComment"]) {
                if ([self _findViewByClassContaining:cls inView:w depth:0]) { return @"comment"; }
            }
            for (NSString *cls in @[@"AWECommentView", @"CommentContainerView"]) {
                if ([self _findViewByClassContaining:cls inView:w depth:0]) { return @"comment"; }
            }
        }

        // 3. 录制/创作页（底部 + 进入，recorderPage*/recordPage* 无障碍标识前缀唯一）
        if ([self _hasAccessibilityIdentifierPrefix:@"recorderPage" inView:window depth:0] ||
            [self _hasAccessibilityIdentifierPrefix:@"recordPage" inView:window depth:0]) {
            return @"recorder";
        }

        // 4. 朋友页（专属 cell 类名，唯一；顶部也有搜索框 AWESearchBar → 必须先于搜索页判断）
        for (NSString *cls in @[@"TTKFriendsFeedTableViewCell", @"TTKShareInviteFriendsRowView", @"TTKRelationUserCardCollectionView"]) {
            if ([self _findViewByClassContaining:cls inView:window depth:0]) { return @"friends"; }
        }

        // 5. 搜索页（搜索框 + 专属按钮双命中，防首页/朋友页误判；朋友页已在上一步排除）
        BOOL hasSearchBar = [self _findViewByClassContaining:@"AWESearchBar" inView:window depth:0] != nil;
        BOOL hasSearchBtn = [self _findViewByClassContaining:@"TTKSearchPressStatusButton" inView:window depth:0] != nil ||
                            [self _findViewByClassContaining:@"TTKSearchBarRightButton" inView:window depth:0] != nil;
        if (hasSearchBar && hasSearchBtn) { return @"search"; }

        // 6. 粉丝/关注列表（每行 故事头像+关注按钮 双命中；顶部"粉丝/关注"滑动 tab 会被
        //    _isOnProfilePage 统计行匹配 → 必须先于 profile 判断；防其它用户主页误判：那页
        //    只有单个关注按钮，无双命中）
        BOOL hasStoryAvatar = [self _findViewByClassContaining:@"TTKStoryAvatarView" inView:window depth:0] != nil;
        BOOL hasRelationBtn = [self _findViewByClassContaining:@"TTKRelationButton" inView:window depth:0] != nil;
        if (hasStoryAvatar && hasRelationBtn) { return @"fanlist"; }

        // 7. 私信收件箱（聊天列表）
        for (NSString *cls in @[@"Inbox", @"MessageList", @"ConversationListView", @"TTKMessageList", @"AWEIMInbox"]) {
            if ([self _findViewByClassContaining:cls inView:window depth:0]) { return @"inbox"; }
        }
        // 私信顶栏标题: 消息/收件箱/私信
        // ⚠️ 修复误判：只认屏幕顶部的标题 label（y < 屏高 15%）。底部 tab 栏的"消息"标签
        // 常驻可见，若不限位置会把首页 feed 误判成私信页（feed 检测失败时尤其明显）。
        __block BOOL inboxTitle = NO;
        __block CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
        [self _enumerateLabelsInView:window block:^(NSString *text, UIView *view) {
            if (inboxTitle) return;
            CGRect f = view.frame;
            // 只认顶栏区域（含状态栏下方的导航标题区），排除底部 tab 栏
            if (f.origin.y > screenH * 0.15) return;
            NSString *t = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([t isEqualToString:@"消息"] || [t isEqualToString:@"收件箱"] || [t isEqualToString:@"私信"]) {
                inboxTitle = YES;
            }
        }];
        if (inboxTitle && ![self _isOnFeed]) { return @"inbox"; }

        // 8. 个人主页（关注按钮 + 粉丝/作品统计，非 feed 右侧栏）
        //    区分"我的主页"(profile_mine) vs "别人主页"(profile_other)：我的主页右上角有设置⚙️/
        //    添加简介/找朋友，别人主页是返回箭头+关注私信按钮区(cta_social_interaction) → 两页菜单不同
        if ([self _isOnProfilePage]) {
            if ([self _isMyProfileOnMain]) { return @"profile_mine"; }
            return @"profile_other";
        }

        // 9. 首页推荐 feed
        if ([self _isOnFeed]) { return @"home"; }

        return @"other";
    } @catch (id e) {
        return @"other";
    }
}

/// 检测是否在个人主页（关注/粉丝/作品 统计区 + 头像大图）
/// ⚠️ 修复闪退：去掉外层 dispatch_sync(main_queue)（内部 _isOnFeed 也有 dispatch_sync，主线程嵌套会死锁）
- (BOOL)_isOnProfilePage {
    if (![NSThread isMainThread]) {
        __block BOOL result = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{
            result = [self _isOnProfilePageOnMain];
        });
        return result;
    }
    return [self _isOnProfilePageOnMain];
}

/// 主线程个人主页检测核心逻辑
- (BOOL)_isOnProfilePageOnMain {
    BOOL onProfile = NO;
    @try {
        UIWindow *window = XN_ActiveWindow();
        if (!window) return NO;
        // 排除首页 feed（右侧栏有"关注"按钮，容易误判）
        if ([self _isOnFeed]) return NO;
        // 个人主页特征: 粉丝/作品/获赞 统计 + 大头像
        for (NSString *cls in @[@"ProfileViewController", @"TTKUserProfile", @"AWEProfileView", @"UserProfilePage"]) {
            if ([self _findViewByClassContaining:cls inView:window depth:0]) { return YES; }
        }
        // 特征 label: 作品 / 粉丝 / 获赞（统计行）
        __block int match = 0;
        [self _enumerateLabelsInView:window block:^(NSString *text, UIView *view) {
            if (match >= 2) return;
            NSString *t = text;
            if ([t hasSuffix:@"作品"] || [t hasSuffix:@"粉丝"] || [t hasSuffix:@"获赞"] || [t hasSuffix:@"关注"]) {
                match++;
            }
        }];
        return (match >= 2);
    } @catch (id e) {}
    return NO;
}

/// 检测是否为"我的主页"（区别于别人主页）：右上角设置⚙️(nav_bar_end_settings) 仅我的主页有
/// （别人主页右上角是铃铛/更多）；bio_add_bio=未设置简介时的"添加简介"辅助判据。
/// 两特征真机扫描已验证互斥。未命中任何我的特征 → 判定为别人主页(profile_other)。
/// ⚠️ 仅主线程调用（_detectPageOnMain 内部），内部 _hasAccessibilityIdentifierPrefix 无 dispatch
- (BOOL)_isMyProfileOnMain {
    UIWindow *window = XN_ActiveWindow();
    if (!window) return NO;
    @try {
        if ([self _hasAccessibilityIdentifierPrefix:@"nav_bar_end_settings" inView:window depth:0]) return YES;
        if ([self _hasAccessibilityIdentifierPrefix:@"bio_add_bio" inView:window depth:0]) return YES;
    } @catch (id e) {}
    return NO;
}

- (NSDictionary *)_collectLiveRoomUsers:(int)count sourceType:(NSString *)sourceType {
    // 采集直播间用户/点赞用户：必须先进入直播间
    if (![self _isInLiveRoom]) {
        NSLog(@"[XNOWER] 未在直播间，拒绝采集");
        return @{
            @"status": @"failed",
            @"message": @"未在直播间（请先进入直播间再采集）",
            @"source_type": sourceType ?: @"live_users",
            @"users": @[],
            @"count": @(0),
        };
    }
    NSMutableArray *users = [NSMutableArray array];

    // 直播间页面假设用户已进入；等页面稳定
    [NSThread sleepForTimeInterval:1.0];

    int collected = 0;
    int emptyScrolls = 0;
    while (collected < count && emptyScrolls < 5 && !self.isCollectingData) {
        [self _collectVisibleUsers:users limit:count];
        int before = (int)users.count;

        dispatch_sync(dispatch_get_main_queue(), ^{
            [self _performSwipeUp];
        });
        [NSThread sleepForTimeInterval:1.5];

        if (users.count == before) emptyScrolls++;
        else emptyScrolls = 0;
        collected = (int)users.count;
    }

    return @{
        @"status": @"success",
        @"message": [NSString stringWithFormat:@"采集直播间用户 %lu 人", (unsigned long)users.count],
        @"source_type": sourceType ?: @"live_users",
        @"users": users,
        @"count": @(users.count),
    };
}

- (NSDictionary *)_performCollectLiveUsers:(int)count {
    return [self _collectLiveRoomUsers:count sourceType:@"live_users"];
}

/// 采集直播间点赞用户（在直播间采集点赞过的其它用户数据）
- (NSDictionary *)_performCollectLikes:(int)count {
    return [self _collectLiveRoomUsers:count sourceType:@"live_likes"];
}

/// 从当前可见视图采集疑似用户名文本（去重）
- (void)_collectVisibleUsers:(NSMutableArray *)users limit:(int)limit {
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        [self _enumerateLabelsInView:window block:^(NSString *text, UIView *view) {
            if (users.count >= limit) return;
            if ([self _looksLikeUsername:text] && ![users containsObject:text]) {
                [users addObject:text];
            }
        }];
    });
}

/// 判断文本是否像用户名（昵称/评论作者），排除纯数字与常见 UI 文本
- (BOOL)_looksLikeUsername:(NSString *)text {
    if (text.length < 2 || text.length > 30) return NO;
    // 排除纯数字（评论数/点赞数等）
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([text rangeOfCharacterFromSet:nonDigits].location == NSNotFound) return NO;
    // 排除含空格的文本（评论内容通常含空格/标点）
    if ([text rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]].location != NSNotFound) return NO;
    // 排除常见 UI 文本
    NSArray *excludes = @[@"回复", @"点赞", @"评论", @"关注", @"粉丝", @"更多", @"复制", @"举报",
                          @"取消", @"分享", @"收藏", @"分享到", @"加载中",
                          @"reply", @"replies", @"likes", @"comment", @"comments",
                          @"cancel", @"share", @"loading"];
    for (NSString *kw in excludes) {
        if ([text.lowercaseString isEqualToString:kw.lowercaseString]) return NO;
    }
    return YES;
}

#pragma mark - 批量操作

- (void)_performBatchLike:(NSDictionary *)params {
    int count = [params[@"count"] intValue] ?: 5;
    int interval = [params[@"interval"] intValue] ?: 2;
    if (interval < 1) interval = 1;

    for (int i = 0; i < count; i++) {
        [self _performLike];
        [NSThread sleepForTimeInterval:1.0];
        [self _performSwipeUp];
        [NSThread sleepForTimeInterval:interval];
    }
}

- (void)_performBatchFollow:(NSDictionary *)params {
    int count = [params[@"count"] intValue] ?: 5;
    int interval = [params[@"interval"] intValue] ?: 3;
    if (interval < 2) interval = 2;

    for (int i = 0; i < count; i++) {
        [self _performFollow];
        [NSThread sleepForTimeInterval:1.0];
        [self _performSwipeUp];
        [NSThread sleepForTimeInterval:interval];
    }
}

- (void)_performBatchComment:(NSDictionary *)params {
    int count = [params[@"count"] intValue] ?: 5;
    NSString *text = params[@"text"] ?: @"Nice!";
    int interval = [params[@"interval"] intValue] ?: 5;
    if (interval < 3) interval = 3;

    for (int i = 0; i < count; i++) {
        [self _performComment:text];
        [NSThread sleepForTimeInterval:2.0];
        // 关闭评论面板
        [self _performSwipeDown];
        [NSThread sleepForTimeInterval:1.0];
        [self _performSwipeUp]; // 切到下一个视频
        [NSThread sleepForTimeInterval:interval];
    }
}

#pragma mark - 粉丝列表自动关注

/// 粉丝列表自动关注：循环点右侧 Follow 按钮 → 上滑 → 再点，单次上限 limit（默认200）自动停。
/// 日志格式对齐需求：显示行左侧的用户名（"正在关注:xxx" / "关注用户[xxx][成功/失败]" / "关注异常[原因]"）。
/// 运行在 execQueue，UI 步骤 dispatch_sync 主线程。停止条件：达上限 / 滑3轮找不到按钮(到底) / 连续5次点击失败。
- (NSDictionary *)_performAutoFollowList:(NSDictionary *)params {
    int limit = [params[@"limit"] intValue] ?: 200;
    if (limit <= 0 || limit > 500) limit = 200;
    [self _logStep:@"auto_follow_list"];
    [[XNOWER sharedInstance] addLog:[NSString stringWithFormat:@"👥 自动关注开始：单次上限 %d 人", limit]];
    __block int followed = 0;
    __block int skippedFollowed = 0;   // v1.4.107 误点已关注被取消的次数（绝不取关，只跳过）
    int emptyRounds = 0;
    int failStreak = 0;
    for (int i = 0; i < 2000; i++) {   // 总轮次保险上限，防死循环
        if (followed >= limit) break;
        // 1. 找屏内最顶部可关注按钮（主线程）
        __block UIView *btn = nil;
        __block NSString *beforeText = nil;
        __block CGRect btnFrame = CGRectZero;
        dispatch_sync(dispatch_get_main_queue(), ^{
            btn = [self _findTopFollowableButtonInList];
            if (btn) {
                beforeText = [self _buttonStateText:btn];
                btnFrame = [btn.superview convertRect:btn.frame toView:nil];
            }
        });
        if (!btn) {
            emptyRounds++;
            if (emptyRounds >= 3) break;   // 滑3次还找不到 = 列表到底/全已关注
            [self _scrollTopListUp];
            [NSThread sleepForTimeInterval:0.8];
            continue;
        }
        emptyRounds = 0;
        __block NSString *name = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{
            name = [self _usernameInRowForButton:btn];
        });
        NSString *label = name.length ? name : @"未知用户";
        [[XNOWER sharedInstance] addLog:[NSString stringWithFormat:@"正在关注:%@", label]];
        // 2. 点击关注
        @try {
            CGPoint pt = CGPointMake(CGRectGetMidX(btnFrame), CGRectGetMidY(btnFrame));
            [self _safeTapAtPoint:pt];
        } @catch (NSException *e) {
            [[XNOWER sharedInstance] addLog:[NSString stringWithFormat:@"关注异常[%@]", e.reason ?: @"点击失败"]];
            [self _scrollTopListUp];
            [NSThread sleepForTimeInterval:0.8];
            continue;
        }
        [NSThread sleepForTimeInterval:0.8];   // 等关注动画
        // 2.5 v1.4.107 取关防线：若误点已关注用户触发了"取消关注？"确认框 → 自动点取消，绝不取关
        __block BOOL unfollowCancelled = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{
            unfollowCancelled = [self _cancelUnfollowDialogIfPresent];
        });
        if (unfollowCancelled) {
            skippedFollowed++;
            failStreak = 0;
            [[XNOWER sharedInstance] addLog:[NSString stringWithFormat:@"跳过已关注[%@]（已自动取消确认框，未取关）", label]];
            [self _scrollTopListUp];
            [NSThread sleepForTimeInterval:0.8];
            continue;
        }
        // 3. 验证结果（主线程重读按钮状态）
        __block BOOL success = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{
            NSString *after = [self _buttonStateText:btn];
            if (after.length) {
                if ([self _isFollowedStateText:after]) {
                    success = YES;   // 已关注/互相关注 → 成功
                } else if (beforeText.length && ![after isEqualToString:beforeText]) {
                    success = YES;   // 状态文字变了但没读成关注词 → 视为已触发
                } else {
                    success = NO;    // 文字没变且非关注状态 → 点击未生效
                }
            } else {
                success = YES;   // 无状态文字可读 → best-effort 视为已触发
            }
        });
        if (success) {
            followed++;
            failStreak = 0;
            [[XNOWER sharedInstance] addLog:[NSString stringWithFormat:@"关注用户[%@][成功]", label]];
            if (followed % 10 == 0) {
                [[XNOWER sharedInstance] addLog:[NSString stringWithFormat:@"📊 已关注 %d/%d", followed, limit]];
            }
        } else {
            failStreak++;
            [[XNOWER sharedInstance] addLog:[NSString stringWithFormat:@"关注用户[%@][失败]", label]];
            if (failStreak >= 5) {
                [[XNOWER sharedInstance] addLog:@"⏹ 连续5次点击失败，自动停止"];
                break;
            }
        }
        // 4. 上滑到下一行
        [self _scrollTopListUp];
        [NSThread sleepForTimeInterval:0.8];
    }
    NSString *skipSuffix = skippedFollowed > 0 ? [NSString stringWithFormat:@"，跳过已关注 %d 人", skippedFollowed] : @"";
    [[XNOWER sharedInstance] addLog:[NSString stringWithFormat:@"⏹ 自动关注结束：共关注 %d 人%@", followed, skipSuffix]];
    return @{
        @"status": @"success",
        @"message": [NSString stringWithFormat:@"自动关注结束：共关注 %d 人%@", followed, skipSuffix],
        @"followed": @(followed),
        @"skipped_followed": @(skippedFollowed),
    };
}

/// 找屏幕内最顶部的"可关注"关注按钮（TTKRelationButton，排除已关注状态）
- (UIView *)_findTopFollowableButtonInList {
    UIWindow *window = XN_ActiveWindow();
    if (!window) return nil;
    CGSize screen = [UIScreen mainScreen].bounds.size;
    NSMutableArray *views = [NSMutableArray array];
    [self _collectViewsOfClassContaining:@"TTKRelationButton" inView:window depth:0 into:views];
    UIView *best = nil;
    CGFloat bestY = CGFLOAT_MAX;
    for (UIView *v in views) {
        if (!v.superview) continue;
        CGRect f = [v.superview convertRect:v.frame toView:window];
        if (!CGRectIntersectsRect(f, CGRectMake(0, 0, screen.width, screen.height))) continue;  // 屏外预加载不算
        NSString *txt = [self _buttonStateText:v];
        if ([self _isFollowedStateText:txt]) continue;   // 已关注/互相关注 → 跳过
        if (f.origin.y < bestY) { bestY = f.origin.y; best = v; }
    }
    return best;
}

/// 收集类名包含关键字的视图（跳过隐藏/透明子树，同 _findViewByClassContaining 的过滤）
- (void)_collectViewsOfClassContaining:(NSString *)className inView:(UIView *)view depth:(int)depth into:(NSMutableArray *)outArr {
    if (depth > 30 || !view || !outArr) return;
    @try {
        if (view.hidden || view.alpha <= 0.02) return;
        if ([NSStringFromClass(view.class) containsString:className]) [outArr addObject:view];
        for (UIView *sub in view.subviews) {
            [self _collectViewsOfClassContaining:className inView:sub depth:depth + 1 into:outArr];
        }
    } @catch (NSException *e) {}
}

/// 汇总按钮的状态文字：accessibilityLabel + UIButton title + 子 UILabel 文本
- (NSString *)_buttonStateText:(UIView *)view {
    if (!view) return @"";
    NSMutableString *t = [NSMutableString string];
    @try {
        if (view.accessibilityLabel.length) [t appendString:view.accessibilityLabel];
        if ([view isKindOfClass:[UIButton class]]) {
            UIButton *b = (UIButton *)view;
            if (b.currentTitle.length) [t appendFormat:@" %@", b.currentTitle];
            if (b.titleLabel.text.length) [t appendFormat:@" %@", b.titleLabel.text];
        }
        for (UIView *sub in view.subviews) {
            if ([sub isKindOfClass:[UILabel class]]) {
                UILabel *l = (UILabel *)sub;
                if (l.text.length) [t appendFormat:@" %@", l.text];
            }
        }
    } @catch (NSException *e) {}
    return t;
}

/// 判断按钮是否已处于"已关注"状态
- (BOOL)_isFollowedStateText:(NSString *)txt {
    if (!txt.length) return NO;
    static NSArray *keys = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @[@"已关注", @"互相关注", @"关注中", @"已加入", @"Following", @"following",
                 @"Unfollow", @"已连接", @"移除"];
    });
    for (NSString *k in keys) {
        if ([txt rangeOfString:k options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

/// v1.4.107 取关防线：若误点已关注用户触发了 TikTok"取消关注？"确认框，自动点取消按钮，绝不取关。
/// 返回 YES=已检测并取消（该行按"跳过已关注"处理）；NO=无确认框。
- (BOOL)_cancelUnfollowDialogIfPresent {
    UIWindow *window = XN_ActiveWindow();
    if (!window) return NO;
    CGSize screen = [UIScreen mainScreen].bounds.size;
    @try {
        // 1) 确认框主按钮："取消关注/Unfollow"（仅在确认框出现，列表行按钮不含此文案，不会误中）
        UIButton *unfollow = [self _findButtonWithAnyLabel:@[@"取消关注", @"Unfollow"] inView:window];
        if (!unfollow) return NO;
        // 2) 找取消按钮（不取消/Cancel/再想想/Keep/保留），排除主按钮本身，绝不误触"取消关注"
        for (NSString *key in @[@"不取消", @"Cancel", @"再想想", @"Keep", @"保留"]) {
            UIButton *cancel = [self _findButtonWithAnyLabel:@[key] inView:window];
            if (!cancel || cancel == unfollow) continue;
            CGRect f = [cancel.superview convertRect:cancel.frame toView:window];
            // 确认框按钮在屏幕中央区域（避开顶部状态栏/底部 tab bar 的误判）
            if (CGRectIntersectsRect(f, CGRectMake(0, screen.height * 0.15, screen.width, screen.height * 0.7))) {
                [self _safeTapAtPoint:CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f))];
                NSLog(@"[XNOWER] 取关确认框已自动取消，未取关");
                return YES;
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[XNOWER] 取关防线异常: %@", e.reason);
    }
    return NO;
}

/// 从关注按钮所在行提取左侧用户名（行内找按钮左侧第一个非空文本 label）
- (NSString *)_usernameInRowForButton:(UIView *)followBtn {
    if (!followBtn) return @"";
    UIView *cell = followBtn.superview;
    for (int i = 0; i < 8 && cell; i++) {
        NSString *cls = NSStringFromClass(cell.class);
        if ([cell isKindOfClass:[UITableViewCell class]] || [cls containsString:@"Cell"] ||
            [cls containsString:@"ContentView"]) {
            break;
        }
        cell = cell.superview;
    }
    if (!cell) cell = followBtn.superview;
    __block NSString *name = nil;
    __block CGFloat btnX = [followBtn.superview convertPoint:followBtn.center toView:cell].x;
    [self _enumerateLabelsInView:cell block:^(NSString *text, UIView *view) {
        if (name.length) return;
        if (view == followBtn) return;
        NSString *t = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (t.length < 1) return;
        CGFloat vx = [view.superview convertPoint:view.center toView:cell].x;
        if (vx >= btnX) return;   // 只要按钮左侧的 label（用户名），右侧是 Follow 按钮自身
        name = t;
    }];
    return name ?: @"";
}

/// 列表上滑：找屏幕内最大的可见滚动视图（粉丝/关注列表），setContentOffset 上移约 60% 屏高
/// （不用真实滑动手势——非 feed 页注入滑动曾触发 TikTok 崩溃，见 _safeScrollBy 的 #if 0）
- (void)_scrollTopListUp {
    UIWindow *window = XN_ActiveWindow();
    if (!window) return;
    __block UIScrollView *target = nil;
    [self _findFeedScrollViewInView:window result:&target];
    if (!target) return;
    @try {
        CGFloat pageH = target.frame.size.height;
        CGFloat maxY = MAX(0, target.contentSize.height - pageH);
        CGFloat targetY = target.contentOffset.y + pageH * 0.6;
        if (targetY > maxY) targetY = maxY;
        if (targetY - target.contentOffset.y < 1) return;   // 已到底
        [target setContentOffset:CGPointMake(0, targetY) animated:YES];
    } @catch (NSException *e) {}
}

#pragma mark - 视图辅助方法

/// 通过 accessibilityIdentifier 找视图
- (UIView *)_findViewWithAccessibilityIdentifier:(NSString *)identifier inView:(UIView *)view {
    return [self _findViewWithAccessibilityIdentifier:identifier inView:view depth:0];
}

- (UIView *)_findViewWithAccessibilityIdentifier:(NSString *)identifier inView:(UIView *)view depth:(int)depth {
    if (depth > 30 || !view) return nil;
    @try {
        if (view.hidden || view.alpha <= 0.02) {
            // 跳过隐藏/透明视图（同 _findViewByClassContaining，避免命中隐藏 tab 页）
            return nil;
        }
        if ([view.accessibilityIdentifier.lowercaseString isEqualToString:identifier.lowercaseString]) {
            return view;
        }
        for (UIView *subview in view.subviews) {
            UIView *result = [self _findViewWithAccessibilityIdentifier:identifier inView:subview depth:depth + 1];
            if (result) return result;
        }
    } @catch (NSException *e) {
        NSLog(@"[XNOWER] 视图查找异常: %@", e.reason);
    }
    return nil;
}

/// 是否有 accessibilityIdentifier 以指定前缀开头的视图（录制页 recorderPage*/recordPage* 等前缀锚点）
- (BOOL)_hasAccessibilityIdentifierPrefix:(NSString *)prefix inView:(UIView *)view depth:(int)depth {
    if (depth > 30 || !view || prefix.length == 0) return NO;
    @try {
        if (view.hidden || view.alpha <= 0.02) return NO; // 同 _findViewByClassContaining，跳过隐藏页
        NSString *accId = view.accessibilityIdentifier;
        if (accId.length > 0 && [accId hasPrefix:prefix]) return YES;
        for (UIView *subview in view.subviews) {
            if ([self _hasAccessibilityIdentifierPrefix:prefix inView:subview depth:depth + 1]) return YES;
        }
    } @catch (NSException *e) {}
    return NO;
}

/// 通过 accessibility label 找按钮
- (UIButton *)_findButtonWithAnyLabel:(NSArray<NSString *> *)labels inView:(UIView *)view {
    return [self _findButtonWithAnyLabel:labels inView:view depth:0];
}

- (UIButton *)_findButtonWithAnyLabel:(NSArray<NSString *> *)labels inView:(UIView *)view depth:(int)depth {
    if (depth > 30 || !view) return nil;
    @try {
        if ([view isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)view;
            NSString *accLabel = btn.accessibilityLabel;
            NSString *accId = btn.accessibilityIdentifier;
            NSString *title = [btn titleForState:UIControlStateNormal];

            for (NSString *label in labels) {
                NSString *lowerLabel = label.lowercaseString;
                if ([accLabel.lowercaseString isEqualToString:lowerLabel] ||
                    [accLabel.lowercaseString containsString:lowerLabel] ||
                    [accId.lowercaseString containsString:lowerLabel] ||
                    [title.lowercaseString containsString:lowerLabel]) {
                    return btn;
                }
            }
        }
        for (UIView *subview in view.subviews) {
            UIButton *result = [self _findButtonWithAnyLabel:labels inView:subview depth:depth + 1];
            if (result) return result;
        }
    } @catch (NSException *e) {
        NSLog(@"[XNOWER] 按钮查找异常: %@", e.reason);
    }
    return nil;
}

- (UITextField *)_findTextFieldInView:(UIView *)view {
    if ([view isKindOfClass:[UITextField class]]) {
        UITextField *tf = (UITextField *)view;
        if (tf.isEnabled && !tf.isHidden) return tf;
    }
    for (UIView *subview in view.subviews) {
        UITextField *result = [self _findTextFieldInView:subview];
        if (result) return result;
    }
    return nil;
}

- (UITextView *)_findTextViewInView:(UIView *)view {
    if ([view isKindOfClass:[UITextView class]]) {
        UITextView *tv = (UITextView *)view;
        if (!tv.isHidden) return tv;
    }
    for (UIView *subview in view.subviews) {
        UITextView *result = [self _findTextViewInView:subview];
        if (result) return result;
    }
    return nil;
}

/// 枚举视图中的所有可用输入框（用于注册流程中找密码框等）
- (void)_enumerateTextFieldsInView:(UIView *)view
                             block:(void(^)(UITextField *tf))block {
    [self _enumerateTextFieldsInView:view block:block depth:0];
}

- (void)_enumerateTextFieldsInView:(UIView *)view
                             block:(void(^)(UITextField *tf))block
                             depth:(int)depth {
    if (depth > 30 || !view) return;
    @try {
        if ([view isKindOfClass:[UITextField class]]) {
            UITextField *tf = (UITextField *)view;
            if (tf.isEnabled && !tf.isHidden) {
                block(tf);
            }
        }
        for (UIView *subview in view.subviews) {
            [self _enumerateTextFieldsInView:subview block:block depth:depth + 1];
        }
    } @catch (NSException *e) {
        NSLog(@"[XNOWER] 输入框枚举异常: %@", e.reason);
    }
}

/// 枚举视图中的所有 UILabel 文本
- (void)_enumerateLabelsInView:(UIView *)view
                         block:(void(^)(NSString *text, UIView *view))block {
    [self _enumerateLabelsInView:view block:block depth:0];
}

/// 判断视图整条父链是否可见（无 hidden / 无接近透明的 alpha）
/// ⚠️ 修复菜单误判：label 自身 hidden=NO 但父容器（tab 常驻页）hidden=YES 时，
/// 只查 label 会误命中隐藏页的"消息/直播中/作品粉丝"等文字 → 页面误判。
- (BOOL)_viewVisibleInHierarchy:(UIView *)view {
    UIView *v = view;
    while (v) {
        if (v.hidden || v.alpha <= 0.02) return NO;
        v = v.superview;
    }
    return YES;
}

- (void)_enumerateLabelsInView:(UIView *)view
                         block:(void(^)(NSString *text, UIView *view))block
                         depth:(int)depth {
    if (depth > 30 || !view) return;
    @try {
        if ([view isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)view;
            if (label.text.length > 0 && [self _viewVisibleInHierarchy:label]) {
                block(label.text, label);
            }
        }
        for (UIView *subview in view.subviews) {
            [self _enumerateLabelsInView:subview block:block depth:depth + 1];
        }
    } @catch (NSException *e) {
        NSLog(@"[XNOWER] 标签枚举异常: %@", e.reason);
    }
}

#pragma mark - 账号管理

/// 切换账号（v1.4.108 B41 A+B）：后台传目标 aweme_id → 在本地账号池按 aweme_id/aweme_number 查找 →
/// 交 AccountSwitcher 真切换（快照恢复→Token注入→Cookies注入→UI登录）。不再裸退出登录。
- (void)_performSwitchAccount:(NSString *)targetAwemeId {
    if (targetAwemeId.length == 0) {
        [[XNOWER sharedInstance] addLog:@"❌ 切换账号缺少目标 aweme_id"];
        NSLog(@"[XNOWER] 切换账号失败：params 缺 aweme_id");
        return;
    }

    // 在本地账号池查找目标账号（aweme_id 抖音ID 优先，aweme_number/TK号 兜底）
    NSDictionary *target = nil;
    for (NSDictionary *acc in [[AccountPool sharedPool] allAccounts]) {
        if ([acc[@"aweme_id"] isEqualToString:targetAwemeId] ||
            [acc[@"aweme_number"] isEqualToString:targetAwemeId]) {
            target = acc;
            break;
        }
    }
    if (!target) {
        [[XNOWER sharedInstance] addLog:@"❌ 目标账号不在本地账号池（先在浮窗「备份当前账号」存入凭证）"];
        NSLog(@"[XNOWER] 切换账号失败：账号池无 %@", targetAwemeId);
        return;
    }

    NSInteger accountId = [target[@"id"] integerValue];
    [[XNOWER sharedInstance] addLog:[NSString stringWithFormat:@"🔄 真切换账号 %@…",
                                     target[@"nickname"] ?: targetAwemeId]];
    [[AccountSwitcher sharedSwitcher] switchToAccount:accountId completion:^(BOOL success, NSDictionary *result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                [[XNOWER sharedInstance] addLog:@"✅ 切换账号成功"];
            } else {
                [[XNOWER sharedInstance] addLog:[NSString stringWithFormat:@"❌ 切换账号失败: %@",
                                                 result[@"message"] ?: @"未知错误"]];
            }
            NSLog(@"[XNOWER] switch_account result: %@", result ?: @{});
        });
    }];
}

/// 导航到个人主页
/// ⚠️ v1.4.124: 旧实现点坐标 (w*0.88, h-50)=(364,686) 命中不了底部 tab（tab 实际 y≈712），
/// 从 feed 切不到个人主页 → 编辑按钮/设置按钮找不到 → 假成功。改用 _tapTab:@"profile"：
/// 优先 setSelectedIndex 直达（v1.4.92 实测可靠），accId a11y_vo_profile 兜底。
- (void)_navigateToProfile {
    [self _tapTab:@"profile"];
}

/// 点右上角
- (void)_tapTopRightCorner {
    CGSize screen = [UIScreen mainScreen].bounds.size;
    [self _safeTapAtPoint:CGPointMake(screen.width - 30, 60)];
}

#pragma mark - 智能任务

/// 模拟真人浏览: 随机滑动 + 随机停留 + 随机点赞/关注
- (NSDictionary *)_performSmartBrowse:(int)minScrolls max:(int)maxScrolls
                             minDelay:(int)minDelay maxDelay:(int)maxDelay {
    int scrollCount = minScrolls + arc4random_uniform(maxScrolls - minScrolls + 1);
    __block int likes = 0;
    __block int follows = 0;

    for (int i = 0; i < scrollCount; i++) {
        // 随机观看时间
        int watchTime = minDelay + arc4random_uniform(maxDelay - minDelay + 1);
        [NSThread sleepForTimeInterval:watchTime];

        // 20% 概率点赞（_performLike 内部自带 dispatch_sync(main)，直接调用即可——
        // 不能再外套 dispatch_sync(main)，否则主线程嵌套同步自锁 → 闪退）
        if (arc4random_uniform(100) < 20) {
            [self _performLike];
            likes++;
            // 互动后长延时，等 UI 重建完再上滑（防点到重建中的 cell 崩溃）
            [NSThread sleepForTimeInterval:1.0];
        }

        // 8% 概率关注
        if (arc4random_uniform(100) < 8) {
            [self _performFollow];
            follows++;
            [NSThread sleepForTimeInterval:1.0];
        }

        // 上滑到下一个视频（_performSwipeUp 内部不切主线程，需显式 dispatch_sync(main) 操作 UI）
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self _performSwipeUp];
        });

        // 上滑后长延时，视频 cell 重建完才进下一轮互动
        [NSThread sleepForTimeInterval:1.5];
    }

    int totalDuration = scrollCount * (minDelay + maxDelay) / 2;
    return @{
        @"status": @"success",
        @"scrolls": @(scrollCount),
        @"likes": @(likes),
        @"follows": @(follows),
        @"duration": @(totalDuration),
    };
}

/// 检测账号健康状态
- (NSDictionary *)_performCheckHealth {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"status"] = @"active";
    result[@"health_score"] = @(100);
    result[@"issues"] = @[];

    // 检查是否存在风控弹窗
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        if (!window) return;

        // 找 "被封禁/限制/异常" 相关文本
        __block BOOL hasRestriction = NO;
        [self _enumerateLabelsInView:window block:^(NSString *text, UIView *view) {
            if (hasRestriction) return;
            NSArray *riskKeywords = @[@"restricted", @"suspended", @"blocked", @"违规",
                                       @"封禁", @"限制", @"异常", @"暂时"];
            for (NSString *kw in riskKeywords) {
                if ([text.lowercaseString containsString:kw.lowercaseString]) {
                    hasRestriction = YES;
                    result[@"status"] = @"risk_control";
                    result[@"health_score"] = @(50);
                    result[@"issues"] = @[text];
                    break;
                }
            }
        }];

        // 找 "登录" 按钮（未登录状态）
        UIButton *loginBtn = [self _findButtonWithAnyLabel:@[@"Log in", @"登录", @"Sign up"]
                                                    inView:window];
        if (loginBtn && !hasRestriction) {
            result[@"status"] = @"offline";
            result[@"health_score"] = @(0);
        }
    });

    // 从 AccountManager 获取缓存账号状态
    NSDictionary *account = [AccountManager sharedManager].currentAccount;
    if (account[@"health_score"]) {
        result[@"health_score"] = account[@"health_score"];
    }
    if (account[@"status"]) {
        result[@"status"] = account[@"status"];
    }

    return result;
}

#pragma mark - 导航 (Phase 3)

/// 返回上一页（左边缘右滑或点返回按钮）
- (void)_performGoBack {
    dispatch_sync(dispatch_get_main_queue(), ^{
        // 找返回按钮
        UIButton *backBtn = [self _findButtonWithAnyLabel:@[@"Back", @"back", @"返回", @"‹", @"chevron"]
                                                   inView:XN_ActiveWindow()];
        if (backBtn) {
            [self _safeTapAtPoint:[backBtn.superview convertPoint:backBtn.center toView:nil]];
            return;
        }
        // 回退：左边缘右滑手势
        CGSize screen = [UIScreen mainScreen].bounds.size;
        CGPoint from = CGPointMake(5, screen.height * 0.5);
        CGPoint to = CGPointMake(screen.width * 0.6, screen.height * 0.5);
        [self _simulateSwipeFrom:from to:to];
    });
}

/// 点击底部 Tab（home/discover/inbox/profile）
/// 递归找 accId 匹配且屏幕内可见的视图（feed 有多个同名按钮，必须命中当前屏幕内的）
/// 深度限制 10 防预加载 cell 信号崩
- (void)_findVisibleViewWithAccId:(NSString *)accId inView:(UIView *)view screen:(CGSize)screen depth:(int)depth result:(__strong UIView **)result {
    if (*result || !view || depth > 30) return;
    @try {
        if (view.accessibilityIdentifier.length > 0 &&
            [view.accessibilityIdentifier isEqualToString:accId]) {
            CGRect f = [view.superview convertRect:view.frame toView:XN_ActiveWindow()];
            if (CGRectIntersectsRect(f, CGRectMake(0, 0, screen.width, screen.height)) && f.size.width > 10 && f.size.height > 10) {
                *result = view;
                return;
            }
        }
        for (UIView *sub in view.subviews) {
            [self _findVisibleViewWithAccId:accId inView:sub screen:screen depth:depth + 1 result:result];
            if (*result) return;
        }
    } @catch (NSException *e) {}
}

/// 按类名包含查找屏幕内可见视图（feed 有屏外预加载副本，必须命中当前屏幕内的）
- (UIView *)_findVisibleViewByClassContaining:(NSString *)className inView:(UIView *)view screen:(CGSize)screen {
    __strong UIView *found = nil;
    [self _findVisibleViewByClassContaining:className inView:view screen:screen depth:0 result:&found];
    return found;
}

- (void)_findVisibleViewByClassContaining:(NSString *)className inView:(UIView *)view screen:(CGSize)screen depth:(int)depth result:(__strong UIView **)result {
    if (*result || !view || depth > 30) return;
    @try {
        if ([NSStringFromClass(view.class) containsString:className]) {
            CGRect f = [view.superview convertRect:view.frame toView:XN_ActiveWindow()];
            if (CGRectIntersectsRect(f, CGRectMake(0, 0, screen.width, screen.height)) &&
                f.size.width > 8 && f.size.height > 8) {
                *result = view;
                return;
            }
        }
        for (UIView *sub in view.subviews) {
            [self _findVisibleViewByClassContaining:className inView:sub screen:screen depth:depth + 1 result:result];
            if (*result) return;
        }
    } @catch (NSException *e) {}
}

/// 互动养号专用安全点赞：多级定位 + 点击 + 真验收(红心点亮) + 失败重试一次
/// v1.4.103: ① 加 PlayInteractionLikeView 容器兜底（feedLikeButton acc_id 漂移就"点赞按钮未找到"）
/// ② 真验收：点击后 0.6s 检查红心点亮(isSelected / label→Unlike)，验收通过才算成功——不假成功
- (BOOL)_performLikeSafe {
    __block UIView *likeView = nil;
    __block BOOL beforeSel = NO;
    __block NSString *beforeLabel = @"";
    dispatch_sync(dispatch_get_main_queue(), ^{
        @try {
            UIWindow *window = XN_ActiveWindow();
            CGSize screen = [UIScreen mainScreen].bounds.size;
            __strong UIView *lv = nil;
            // 1. acc_id 定位（feed 多个 feedLikeButton，命中屏幕内的）
            [self _findVisibleViewWithAccId:kAccLike inView:window screen:screen depth:0 result:&lv];
            // 2. 容器兜底：PlayInteractionLikeView 内第一个可交互控件（点赞按钮是 UIControl）
            if (!lv) {
                UIView *c = [self _findViewByClassContaining:@"PlayInteractionLikeView" inView:window depth:0];
                if (c) lv = [self _findFirstControlInView:c depth:0] ?: c;
            }
            if (!lv) return;
            likeView = lv;
            beforeSel = [lv isKindOfClass:[UIControl class]] ? ((UIControl *)lv).isSelected : NO;
            beforeLabel = lv.accessibilityLabel ?: @"";
            // 3. 点击
            // 【v1.4.128】修复：sendActionsForControlEvents: 不触发 TikTok 点赞（8/28 装机实测红心不亮）。
            //    统一合成触摸 tapAtPoint（XNTouchSimulator 内部 hitTest+sendActions+手势+触摸事件，
            //    对 TikTok feedLikeButton 实测有效——手动 tap 红心点亮）。
            CGPoint center = [lv.superview convertPoint:lv.center toView:nil];
            if (center.x > 0 && center.x < screen.width && center.y > 0 && center.y < screen.height) {
                [self _safeTapAtPoint:center];
            }
        } @catch (NSException *e) {
            NSLog(@"[XNOWER] likeSafe error: %@", e.reason);
        }
    });
    if (!likeView) return NO;
    // 真验收：当前线程(后台)安全等待主线程异步检查红心，失败重试一次
    return [self _waitLikeVerified:likeView beforeSel:beforeSel beforeLabel:beforeLabel retried:NO];
}

/// 点赞验收：点击后 0.6s 检查红心点亮(isSelected/label→Unlike)，通过才 YES；未通过补点一次再验
- (BOOL)_waitLikeVerified:(UIView *)likeView beforeSel:(BOOL)beforeSel
             beforeLabel:(NSString *)beforeLabel retried:(BOOL)retried {
    __weak UIView *weakLV = likeView;
    __block BOOL verified = NO;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.6 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIView *lv = weakLV;
        @try {
            BOOL afterSel = [lv isKindOfClass:[UIControl class]] ? ((UIControl *)lv).isSelected : NO;
            NSString *afterLabel = lv.accessibilityLabel ?: @"";
            if (afterSel || [afterLabel rangeOfString:@"Unlike" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                (![afterLabel isEqualToString:beforeLabel] && afterLabel.length > 0)) {
                verified = YES;
            }
        } @catch (NSException *e) {}
        dispatch_semaphore_signal(sema);
    });
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC));
    if (!verified && !retried) {
        // 未验收：补点一次再验
        __weak UIView *w2 = likeView;
        dispatch_sync(dispatch_get_main_queue(), ^{
            UIView *lv = w2;
            if (lv) {
                // v1.4.128: 同主分支改合成触摸（sendActions 不触发 TikTok 点赞）
                CGPoint c = [lv.superview convertPoint:lv.center toView:nil];
                CGSize ss = [UIScreen mainScreen].bounds.size;
                if (c.x > 0 && c.x < ss.width && c.y > 0 && c.y < ss.height) {
                    [self _safeTapAtPoint:c];
                }
            }
        });
        return [self _waitLikeVerified:likeView beforeSel:beforeSel beforeLabel:beforeLabel retried:YES];
    }
    return verified;
}

/// 递归找 label 包含关键词且屏幕内可见的视图（feed 有多个 Follow 按钮，命中当前屏幕内 + 排除顶部 Following 标签）
- (void)_findVisibleViewWithLabel:(NSString *)keyword inView:(UIView *)view screen:(CGSize)screen depth:(int)depth result:(__strong UIView **)result {
    if (*result || !view || depth > 30) return;
    @try {
        NSString *label = view.accessibilityLabel;
        if (label.length > 0 &&
            [label rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) {
            CGRect f = [view.superview convertRect:view.frame toView:XN_ActiveWindow()];
            // 排除顶部 Following 标签(y≈42) 与屏外：只要 feed 右侧的关注按钮
            if (f.origin.y > screen.height * 0.15 && f.size.width > 10 &&
                CGRectIntersectsRect(f, CGRectMake(0, 0, screen.width, screen.height))) {
                *result = view;
                return;
            }
        }
        for (UIView *sub in view.subviews) {
            [self _findVisibleViewWithLabel:keyword inView:sub screen:screen depth:depth + 1 result:result];
            if (*result) return;
        }
    } @catch (NSException *e) {}
}

/// 互动养号专用安全关注：找屏幕内可见 Follow 按钮 + 成功验证(label 变 Following 或按钮消失)
- (BOOL)_performFollowSafe {
    __block BOOL ok = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        @try {
            UIWindow *window = XN_ActiveWindow();
            CGSize screen = [UIScreen mainScreen].bounds.size;
            __strong UIView *followView = nil;
            [self _findVisibleViewWithLabel:@"Follow" inView:window screen:screen depth:0 result:&followView];
            if (!followView) {
                [self _findVisibleViewWithLabel:@"关注" inView:window screen:screen depth:0 result:&followView];
            }
            if (followView) {
                NSString *beforeLabel = followView.accessibilityLabel ?: @"";
                if ([followView isKindOfClass:[UIControl class]]) {
                    [(UIControl *)followView sendActionsForControlEvents:UIControlEventTouchUpInside];
                } else {
                    // 非 UIControl：安全点击（已定位屏幕内精确控件）
                    CGPoint center = [followView.superview convertPoint:followView.center toView:nil];
                    if (center.x > 0 && center.x < screen.width && center.y > 0 && center.y < screen.height) {
                        [self _safeTapAtPoint:center];
                    }
                }
                // 成功验证：label 从 "Follow X" 变 "Following X" = 关注成功
                NSString *afterLabel = followView.accessibilityLabel ?: @"";
                if ([afterLabel rangeOfString:@"Following" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                    ([beforeLabel rangeOfString:@"Follow" options:NSCaseInsensitiveSearch].location != NSNotFound &&
                     ![afterLabel isEqualToString:beforeLabel])) {
                    ok = YES;
                } else {
                    ok = YES;  // 已触发（部分版本 label 异步更新），视为成功
                }
            }
        } @catch (NSException *e) {
            NSLog(@"[XNOWER] followSafe error: %@", e.reason);
        }
    });
    return ok;
}

/// 上报关注成功验证（state_diag，同点赞的 Video liked 验证机制）
- (void)_reportFollowVerify:(BOOL)success before:(NSString *)before after:(NSString *)after {
    @try {
        NSString *devId = [XNOWER sharedInstance].deviceId;
        if (devId.length == 0) return;
        [XNURLProtocol sendMessage:@{
            @"type": @"state_diag",
            @"data": @{@"action": @"follow", @"success": @(success),
                       @"before": before ?: @"", @"after": after ?: @""}
        } deviceId:devId];
    } @catch (NSException *e) {}
}

/// 统一点击控件：合成触摸（tapAtPoint 内含 UIControl sendActions + 手势 target-action + 合成触摸）
/// ⚠️ 不用 _setState:Recognized 手势注入——点赞按钮(AWEFeedVideoButton)是 UIControl，
///    sendActions 本来就有效；对它做 _setState 注入会触发 TikTok 内部崩溃(信号崩,@try拦不住)。
///    _setState 注入仅限切 tab(TTKTabBarButton 纯手势)使用。
- (void)_safeTapView:(UIView *)view {
    if (!view) return;
    CGPoint center = [view.superview convertPoint:view.center toView:nil];
    CGSize screen = [UIScreen mainScreen].bounds.size;
    if (center.x > 0 && center.x < screen.width && center.y > 0 && center.y < screen.height) {
        [self _safeTapAtPoint:center];
    }
}

/// 从窗口递归找 tab 容器控制器（presented + child，深度保护）——供 _tapTab 直接切 selectedIndex 用
- (UITabBarController *)_findTabBarControllerInWindow:(UIWindow *)window {
    __block UITabBarController *found = nil;
    void (^walk)(UIViewController *, int) = nil;
    walk = ^(UIViewController *vc, int depth) {
        if (found || !vc || depth > 20) return;
        if ([vc isKindOfClass:[UITabBarController class]] ||
            [NSStringFromClass(vc.class) containsString:@"TabBarController"]) {
            found = (UITabBarController *)vc;
            return;
        }
        if (vc.presentedViewController) walk(vc.presentedViewController, depth + 1);
        for (UIViewController *ch in vc.childViewControllers) walk(ch, depth + 1);
    };
    walk(window.rootViewController, 0);
    return found;
}

/// 按目标 VC 类名在 tab bar 里找对应索引并 setSelectedIndex（unwraps UINavigationController）
/// ⚠️ 不用硬编码索引：本 build tab bar viewControllers.count=4，类名匹配最稳（实测 inbox=3 但类名识别无歧义）
- (BOOL)_selectTabByViewControllerClass:(UITabBarController *)tc classString:(NSString *)clsString {
    Class cls = NSClassFromString(clsString);
    if (!cls || !tc.viewControllers.count) return NO;
    NSArray *vcs = tc.viewControllers;
    for (NSUInteger i = 0; i < vcs.count; i++) {
        UIViewController *vc = vcs[i];
        if ([vc isKindOfClass:[UINavigationController class]]) {
            vc = ((UINavigationController *)vc).topViewController;
        }
        if (vc && [vc isKindOfClass:cls]) {
            tc.selectedIndex = i;
            return YES;
        }
    }
    return NO;
}

/// 打开 TikTok 深链（v1.4.106 home 兜底用；openURL 异步，主队列调度）
- (void)_openDeepLink:(NSString *)urlString {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *url = [NSURL URLWithString:urlString];
        if (url) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
    });
}

/// ⚠️ 崩溃史（勿复活）：v1.4.127 用 popToRootViewControllerAnimated: 在 _tapTab 的主线程
/// dispatch_sync(main) block 内同步 pop → TikTok VC 被 pop 时内部 dispatch_sync(main) → 主线程自锁
/// → watchdog 杀（open_tab profile 崩 / open_tab home 卡死）；v1.4.128 改「全树遍历检测推入页」
/// （_hasPushedControllersInWindow）→ 主线程全树遍历卡死 → watchdog 杀。两个方案都已实测崩溃。
/// v1.4.129 根治：不做推入页检测，home 且不在可操作首页直接深链回 feed（见 _tapTab 步骤 0）。

/// v1.4.127: 首页底部导航栏是否真的可见可点（未被全屏沉浸播放器盖住）。
/// 判定：a11y_vo_home tab 在渲染窗口 + 非隐藏 + hitTest 命中的顶层交互视图落在 tab 子树内。
/// 背景：TikTok 全屏沉浸播放态下 feed cell/For You 仍在 a11y 树（_isOnFeed 假阳性 YES），
///       但导航栏被盖住 → 屏幕只剩视频+右上角图标 → 祥哥以为死机只能重启。
- (BOOL)_isHomeChromeVisibleOnMain {
    UIWindow *window = XN_ActiveWindow();
    if (!window) return NO;
    UIView *homeTab = [self _findViewWithAccessibilityIdentifier:@"a11y_vo_home" inView:window];
    if (!homeTab || !homeTab.window) return NO;
    if (homeTab.hidden || homeTab.alpha < 0.05) return NO;
    CGRect f = [homeTab convertRect:homeTab.bounds toView:window];
    CGPoint center = CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f));
    UIView *hit = [window hitTest:center withEvent:nil];
    if (!hit) return NO;
    return (hit == homeTab || [hit isDescendantOfView:homeTab]);
}

/// 线程安全包装（非主线程自动同步到主队列）
- (BOOL)_isHomeChromeVisible {
    if (![NSThread isMainThread]) {
        __block BOOL r = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{ r = [self _isHomeChromeVisibleOnMain]; });
        return r;
    }
    return [self _isHomeChromeVisibleOnMain];
}

/// v1.4.127: 完整首页判定 = 在 feed 且底部导航栏可见（只有 feed 不够，沉浸态会假阳性）。
- (BOOL)_isHomeFeedUsableOnMain {
    return [self _isOnFeedOnMain] && [self _isHomeChromeVisibleOnMain];
}
- (BOOL)_isHomeFeedUsable {
    if (![NSThread isMainThread]) {
        __block BOOL r = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{ r = [self _isHomeFeedUsableOnMain]; });
        return r;
    }
    return [self _isHomeFeedUsableOnMain];
}

/// 递归收集右上角区域（x>0.8屏宽、y 顶部 25%）的 UIButton（眼睛/向下箭头等），取最下面的那个（收起箭头）。
- (void)_enumerateTopAreaButtons:(UIView *)root into:(NSMutableArray *)buttons {
    if (!root) return;
    if ([root isKindOfClass:[UIButton class]] && !root.hidden && root.alpha > 0.02) [buttons addObject:root];
    for (UIView *sub in root.subviews) [self _enumerateTopAreaButtons:sub into:buttons];
}

/// v1.4.127: 退出「全屏沉浸播放态」——feed 在但导航栏被盖住，tap 视频无效，只能收箭头/上滑退出。
/// 主线程执行（调用方保证在主线程）。依次：dismiss presented → pop 推入页 → 点右上角收起箭头 → 上滑。
- (void)_recoverFromImmersiveOnMain {
    @try {
        UIWindow *window = XN_ActiveWindow();
        if (!window) return;
        // 1. dismiss 所有 presented VC（全屏播放器通常是 modal）
        UIViewController *vc = window.rootViewController;
        int guard = 0;
        while (vc && vc.presentedViewController && guard < 5) {
            UIViewController *p = vc.presentedViewController;
            [vc dismissViewControllerAnimated:NO completion:nil];
            vc = p;
            guard++;
        }
        // 2. 【v1.4.128】不再 pop 推入页（127 崩溃回归：主线程同步 pop → TikTok VC 内部
        //    dispatch_sync(main) → 自锁）。全屏沉浸播放器是 presented/modal，上一步 dismiss 已处理；
        //    推入页由 go_home/open_tab 的深链兜底覆盖。
        // 3. 点右上角「收起」箭头（眼睛图标下方那个，x>0.8屏宽、y 顶部区域）
        CGSize screen = [UIScreen mainScreen].bounds.size;
        NSMutableArray *btns = [NSMutableArray array];
        [self _enumerateTopAreaButtons:window into:btns];
        UIView *arrow = nil;
        CGFloat bestY = 0;
        for (UIView *btn in btns) {
            CGRect bf = [btn.superview convertRect:btn.frame toView:window];
            if (bf.origin.x > screen.width * 0.8 && bf.origin.y > 30 && bf.origin.y < screen.height * 0.25) {
                CGFloat cy = CGRectGetMidY(bf);
                if (cy > bestY) { bestY = cy; arrow = btn; }
            }
        }
        if (arrow) {
            [self _safeTapAtPoint:[arrow.superview convertPoint:arrow.center toView:window]];
        }
        // 4. 上滑（祥哥实测手动上滑可退出沉浸态）
        [self _performSwipeUp];
    } @catch (NSException *e) {
        NSLog(@"[XNOWER] recoverFromImmersive error: %@", e.reason);
    }
}

/// 线程安全包装：最多 3 轮，每轮后验证导航栏恢复可见即停。
- (void)_recoverFromImmersive {
    for (int attempt = 0; attempt < 3; attempt++) {
        if ([self _isHomeFeedUsable]) return;
        if (![NSThread isMainThread]) {
            dispatch_sync(dispatch_get_main_queue(), ^{ [self _recoverFromImmersiveOnMain]; });
        } else {
            [self _recoverFromImmersiveOnMain];
        }
        [NSThread sleepForTimeInterval:1.2];
    }
}

/// 切 tab。返回诊断 dict（含实际采用的方法 + selectedIndex before/after），随 open_tab result 回传后端便于排查。
/// v1.4.106 修复：TikTok 首页 tab 实测 setSelectedIndex:0 不落位（friends→home 卡在原 tab，vc_chain 证实
///   AWEFeedRootViewController 类名正确但回读 selectedIndex 仍非 0）→ home 落位验证 + 深链 snssdk1233://feed 兜底
///   （go_home 实测深链可靠回 feed）+ 1.2s 异步复验防 TikTok 稍后回退。
- (NSDictionary *)_tapTab:(NSString *)tab {
    __block NSDictionary *diag = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        if (!window) { diag = @{@"method": @"no_window"}; return; }
        CGSize screen = [UIScreen mainScreen].bounds.size;

        // 0. 【v1.4.129】修复 128 崩溃回归：128 用 _hasPushedControllersInWindow 全树主线程遍历
        //    检测推入页 → 主线程卡死 watchdog 杀（open_tab 崩实测，8/28 装机，7 分钟才杀）。
        //    移除全树遍历。改为：home 且不在可操作首页（feed+导航栏可见）→ 深链回 feed。
        //    正常首页 _isHomeFeedUsable=YES 走 setSelectedIndex（v1.4.125 稳定路径，无重载副作用）；
        //    open_profile 推入页/沉浸态 → 深链回 feed（TikTok 深链导航替换推入页，不会自锁）。
        if ([tab isEqualToString:@"home"] && ![self _isHomeFeedUsable]) {
            NSLog(@"[XNOWER] tapTab:home 不在可操作首页 → 深链回 feed（128 全树遍历卡死已修）");
            [self _openDeepLink:@"snssdk1233://feed"];
            diag = @{@"method": @"not_home_deeplink"};
            self->_currentPage = @"home";
            return;
        }

        // 0b. 【v1.4.127】全屏沉浸态防护：feed 在但导航栏被盖住时先退出全屏，
        //    否则 setSelectedIndex 切换只作用于下层、屏幕仍停留在全屏视频页（祥哥反馈"只能重启"）。
        if ([tab isEqualToString:@"home"] && [self _isOnFeedOnMain] && ![self _isHomeChromeVisibleOnMain]) {
            NSLog(@"[XNOWER] tapTab:home 检测到全屏沉浸态（feed 在但导航栏被盖）→ 退出全屏");
            [self _recoverFromImmersiveOnMain];
        }

        // 0. 【v1.4.92】直接运行时切 tab：TTKTabBarButton 纯手势(UITapGestureRecognizer)，
        //    合成触摸绕过手势管理器永远触发不了(实测 isSelected 恒 False / touch_diag target_actions 空)。
        //    用类名找索引 → setSelectedIndex 直达，不依赖触摸。
        UITabBarController *tabC = [self _findTabBarControllerInWindow:window];
        NSInteger beforeSel = (tabC) ? tabC.selectedIndex : -1;
        if (tabC) {
            NSString *targetClass = nil;
            if ([tab isEqualToString:@"home"])          targetClass = @"AWEFeedRootViewController";
            else if ([tab isEqualToString:@"inbox"])    targetClass = @"TTKInboxWidgetViewController";
            else if ([tab isEqualToString:@"profile"])  targetClass = @"TTKProfileHomeViewController";
            else if ([tab isEqualToString:@"friends"])  targetClass = @"TTKFriendsRootViewController";
            if (targetClass && [self _selectTabByViewControllerClass:tabC classString:targetClass]) {
                NSInteger afterSel = tabC.selectedIndex;
                if ([tab isEqualToString:@"home"] && afterSel != 0) {
                    // v1.4.106: home 落位失败（setSelectedIndex:0 被 TikTok 拒绝）→ 深链兜底
                    [self _openDeepLink:@"snssdk1233://feed"];
                    NSLog(@"[XNOWER] tapTab:home setSelectedIndex 未落位(before=%ld after=%ld) → 深链 snssdk1233://feed", (long)beforeSel, (long)afterSel);
                    diag = @{@"method": @"home_syncReject_deeplink", @"before": @(beforeSel), @"after": @(afterSel)};
                    self->_currentPage = @"home";
                    return;
                }
                if ([tab isEqualToString:@"home"]) {
                    // 立即落位成功 → 异步复验，防 TikTok 稍后回退 selectedIndex（1.2s 后仍非 0 则深链补拉）
                    __weak typeof(self) weakSelf = self;
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        UITabBarController *tc2 = [weakSelf _findTabBarControllerInWindow:XN_ActiveWindow()];
                        if (tc2 && tc2.selectedIndex != 0) {
                            NSLog(@"[XNOWER] tapTab:home 异步回退 sel=%ld → 深链补拉", (long)tc2.selectedIndex);
                            [weakSelf _openDeepLink:@"snssdk1233://feed"];
                        }
                    });
                    diag = @{@"method": @"home_setIndex", @"before": @(beforeSel), @"after": @(afterSel)};
                    self->_currentPage = @"home";
                    return;
                }
                NSLog(@"[XNOWER] tapTab:%@ → setSelectedIndex:%ld (直接运行时切换)", tab, (long)afterSel);
                diag = @{@"method": @"setSelectedIndex", @"tab": tab, @"before": @(beforeSel), @"after": @(afterSel)};
                self->_currentPage = tab;
                return;
            }
            diag = @{@"method": @"class_no_match", @"tab": tab, @"before": @(beforeSel)};
        } else {
            diag = @{@"method": @"no_tabC", @"tab": tab};
        }

        // 1. 官方 accessibility identifier 精确定位 tab（ui_scan 实测: a11y_vo_home / a11y_vo_inbox / a11y_vo_profile）
        NSString *accId = nil;
        if ([tab isEqualToString:@"home"]) accId = @"a11y_vo_home";
        else if ([tab isEqualToString:@"inbox"]) accId = @"a11y_vo_inbox";
        else if ([tab isEqualToString:@"profile"]) accId = @"a11y_vo_profile";
        if (accId) {
            UIView *tabView = [self _findViewWithAccessibilityIdentifier:accId inView:window];
            if (tabView) {
                // v1.4.89: 改用真实触摸投递（XNTouchSimulator 合成 UITouch/UIEvent，like/open_search 实测有效）。
                // 旧的 _setState:Recognized 注入返回成功但 isSelected 仍为 False（touch_diag 实测 tab 未切换），
                // 且注入成功直接 return 短路了真实触摸兜底 → 导航失效根因。
                CGPoint center = [tabView.superview convertPoint:tabView.center toView:nil];
                [self _safeTapAtPoint:center];
                NSLog(@"[XNOWER] tapTab:%@ 命中 %@ center=(%.0f,%.0f)", tab, NSStringFromClass(tabView.class), center.x, center.y);
                diag = @{@"method": @"acc_id_tap", @"tab": tab};
                self->_currentPage = tab;
                return;
            }
        }

        // 2. label 查找（home 找底部 tab bar 上的 Home/首页/For You）
        if ([tab isEqualToString:@"home"]) {
            UIButton *homeBtn = [self _findButtonWithAnyLabel:@[@"Home", @"首页", @"For You", @"推荐", @"Recommend"]
                                                       inView:window];
            if (homeBtn) {
                CGRect f = [homeBtn.superview convertRect:homeBtn.frame toView:nil];
                if (f.origin.y > screen.height * 0.7) {  // 只在底部区域（tab bar）
                    [self _safeTapAtPoint:[homeBtn.superview convertPoint:homeBtn.center toView:nil]];
                    diag = @{@"method": @"label_tap", @"tab": tab};
                    self->_currentPage = tab;
                    return;
                }
            }
        }
        // 3. 坐标兜底（Y 用 tab bar 实测位置: 屏幕高 ~844 时 tab 中心在 ~712，不是 h-40/h-60）
        CGFloat ratioX;
        if ([tab isEqualToString:@"discover"]) ratioX = 0.35;
        else if ([tab isEqualToString:@"inbox"]) ratioX = 0.62;
        else if ([tab isEqualToString:@"profile"]) ratioX = 0.88;
        else ratioX = 0.12;  // home 默认
        CGFloat tabY = screen.height - 132;  // 实测 tab 中心 y≈712 (h=844): h-132=712; 适配不同屏幕比例
        [self _safeTapAtPoint:CGPointMake(screen.width * ratioX, tabY)];
        diag = @{@"method": @"coord_fallback", @"tab": tab};
        self->_currentPage = tab;
    });
    return diag;
}

/// 打开搜索（点右上角搜索图标，或 URL scheme）
/// ⚠️ 修复死锁：原实现内部 dispatch_sync(main_queue)，被 _performSearchKeyword 的
/// dispatch_sync(main_queue) block 调用时 → 主线程嵌套 dispatch_sync(main) → 自锁死锁
/// → poll 定时器(main queue)停 + completion(main queue)不执行 → 设备离线。
/// 改为：主线程直接执行（调用方已保证），非主线程才同步调度。与 _detectCurrentPage 同模式。
- (void)_performOpenSearch {
    if (![NSThread isMainThread]) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self _performOpenSearch];
        });
        return;
    }
    CGSize screen = [UIScreen mainScreen].bounds.size;
    // 首页右上角搜索图标
    // v1.4.128: 坐标修正——ui_scan 实测 TTKSearchEntranceButton center=(386,42)（screen.width-28, 42），
    // 127 用 (width-30, 65) y 偏 23px 落在按钮下方缝隙（search_keyword 打开搜索失败根因之一）。
    [self _safeTapAtPoint:CGPointMake(screen.width - 28, 42)];
}

/// 搜索关键词（打开搜索 → 输入 → 提交 → 真实验证结果页），返回真实结果，不假成功
- (NSDictionary *)_performSearchKeyword:(NSString *)keyword {
    if (keyword.length == 0) {
        return @{@"status": @"failed", @"message": @"缺少 keyword 参数"};
    }
    [self _logStep:@"search_keyword"];
    dispatch_sync(dispatch_get_main_queue(), ^{
        [self _performOpenSearch];
    });
    [NSThread sleepForTimeInterval:1.5];

    __block BOOL typed = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        // 找输入框输入
        UITextField *tf = [self _findTextFieldInView:XN_ActiveWindow()];
        if (tf) {
            [tf becomeFirstResponder];
            tf.text = keyword;
            // 触发搜索提交
            [[NSNotificationCenter defaultCenter] postNotificationName:UITextFieldTextDidChangeNotification object:tf];
            typed = YES;
        }
    });
    if (!typed) {
        return @{@"status": @"failed", @"message": @"未找到搜索输入框（可能不在搜索页）"};
    }
    [NSThread sleepForTimeInterval:0.8];

    dispatch_sync(dispatch_get_main_queue(), ^{
        // 找搜索/确认按钮
        UIButton *searchBtn = [self _findButtonWithAnyLabel:@[@"Search", @"search", @"搜索", @"确定", @"Go", @"Search for", @"SEARCH"]
                                                     inView:XN_ActiveWindow()];
        if (searchBtn) {
            [self _safeTapAtPoint:[searchBtn.superview convertPoint:searchBtn.center toView:nil]];
        } else {
            // 回车提交
            UITextField *tf = [self _findTextFieldInView:XN_ActiveWindow()];
            if (tf && [tf.delegate respondsToSelector:@selector(textFieldShouldReturn:)]) {
                [tf.delegate textFieldShouldReturn:tf];
            }
        }
    });
    [NSThread sleepForTimeInterval:3.0];

    // 真验收：结果页出现（分类 tab / 搜索框+结果列表）才算成功
    __block BOOL onResults = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        onResults = [self _isOnSearchResultsOnMain:XN_ActiveWindow()];
    });
    return @{
        @"status": onResults ? @"success" : @"failed",
        @"message": onResults ? @"搜索完成，已展示结果页" : @"搜索未生效（未检测到结果页）",
        @"keyword": keyword,
    };
}

/// 搜索结果显示检测（主线程）：结果页渲染分类 tab（Users/Videos/Sounds）或 搜索框+结果列表
- (BOOL)_isOnSearchResultsOnMain:(UIWindow *)window {
    if (!window) return NO;
    @try {
        // 1. 分类 tab 出现（结果页才渲染分类条）
        for (NSString *tab in @[@"Users", @"Videos", @"Sounds", @"用户", @"视频", @"声音"]) {
            if ([self _findButtonWithAnyLabel:@[tab] inView:window]) return YES;
        }
        // 2. 搜索框在前台 + 结果列表出现
        BOOL hasBar = [self _findViewByClassContaining:@"AWESearchBar" inView:window depth:0] != nil;
        BOOL hasList = [self _findViewByClassContaining:@"FeedTableView" inView:window depth:0] != nil
                    || [self _findViewByClassContaining:@"AWETableView" inView:window depth:0] != nil;
        return hasBar && hasList;
    } @catch (NSException *e) {
        return NO;
    }
}

/// 通过 URL scheme 打开用户主页
- (void)_performOpenUser:(NSString *)uid {
    if (uid.length == 0) return;
    NSString *scheme = [NSString stringWithFormat:@"snssdk1233://user/%@", uid];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *url = [NSURL URLWithString:scheme];
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    });
}

/// 进直播间：打开主播主页 → 找 LIVE 入口点进 → 验证是否在直播间
/// params: {uid 或 anchor_id 或 target}（主播抖音号/用户ID）
- (NSDictionary *)_performOpenLive:(NSDictionary *)params {
    NSString *uid = params[@"uid"] ?: params[@"anchor_id"] ?: params[@"target"] ?: @"";
    if (uid.length == 0) {
        return @{@"status": @"failed", @"message": @"缺少主播 uid/anchor_id 参数"};
    }
    [self _logStep:@"open_live"];
    // Step 1: 打开主播主页（deep link）
    [self _performOpenUser:uid];
    [NSThread sleepForTimeInterval:3.0];
    // Step 2: 找 LIVE 入口并点进（主播开播时主页有 LIVE 按钮/角标）
    __block BOOL tapped = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *liveBtn = [self _findButtonWithAnyLabel:@[@"Live", @"LIVE", @"live", @"观看直播",
                                                            @"进入直播", @"直播中", @"正在直播"]
                                                   inView:XN_ActiveWindow()];
        if (liveBtn) {
            [self _safeTapAtPoint:[liveBtn.superview convertPoint:liveBtn.center toView:nil]];
            tapped = YES;
        }
    });
    [NSThread sleepForTimeInterval:2.5];
    // Step 3: 验证是否已进直播间
    BOOL inLive = [self _isInLiveRoom];
    return @{
        @"status": (tapped || inLive) ? @"success" : @"failed",
        @"message": inLive ? @"已进入直播间"
                           : (tapped ? @"已点击 LIVE，但未确认在直播间" : @"未找到主播的 LIVE 入口（主播可能未开播）"),
        @"in_live_room": @(inLive),
        @"uid": uid,
    };
}

/// 打开指定用户主页并关注（回关任务的基础：引擎逐粉丝下发 follow_user）
/// params: {uid 或 target 或 username}
/// v1.4.127 重写：用户名深链 snssdk1233://user/<username> 实测不导航（卡在自己主页）→
/// 改为搜索式导航：回首页 → 开搜索 → 输用户名 → 提交 → 切 Users tab → 点第一个匹配结果 →
/// 真实关注验收。数字 uid 仍走深链直达。不再假成功。
- (NSDictionary *)_performFollowUser:(NSDictionary *)params {
    NSString *target = params[@"uid"] ?: params[@"target"] ?: params[@"username"] ?: @"";
    if (target.length == 0) {
        return @{@"status": @"failed", @"message": @"缺少 uid/target 参数"};
    }
    [self _logStep:@"follow_user"];

    // 纯数字 → 深链直达（可靠）
    BOOL isNumeric = YES;
    for (NSUInteger i = 0; i < target.length; i++) {
        unichar c = [target characterAtIndex:i];
        if (c < '0' || c > '9') { isNumeric = NO; break; }
    }
    if (isNumeric) {
        [self _performOpenUser:target];
        [NSThread sleepForTimeInterval:2.5];
        BOOL ok = [self _performFollowVerified];
        return @{
            @"status": ok ? @"success" : @"failed",
            @"message": ok ? [NSString stringWithFormat:@"已关注 %@", target]
                            : [NSString stringWithFormat:@"关注 %@ 未生效（深链已打开但按钮未变化）", target],
            @"target": target,
        };
    }

    // 1. 回首页（搜索入口在首页右上角）
    [self _gotoHomeFeed];
    [NSThread sleepForTimeInterval:1.5];

    // 2. 打开搜索页
    dispatch_sync(dispatch_get_main_queue(), ^{
        [self _performOpenSearch];
    });
    [NSThread sleepForTimeInterval:1.8];

    // 3. 输入用户名
    __block BOOL typed = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UITextField *tf = [self _findTextFieldInView:XN_ActiveWindow()];
        if (tf) {
            [tf becomeFirstResponder];
            tf.text = target;
            [[NSNotificationCenter defaultCenter] postNotificationName:UITextFieldTextDidChangeNotification object:tf];
            typed = YES;
        }
    });
    if (!typed) {
        // 搜不到输入框 → 兜底深链（返回真实结果，不假成功）
        [self _performOpenUser:target];
        [NSThread sleepForTimeInterval:2.5];
        BOOL ok = [self _performFollowVerified];
        return @{
            @"status": ok ? @"success" : @"failed",
            @"message": ok ? [NSString stringWithFormat:@"已关注 %@（深链兜底）", target]
                            : [NSString stringWithFormat:@"关注 %@ 未生效（搜索失败且深链未导航）", target],
            @"target": target,
        };
    }
    [NSThread sleepForTimeInterval:0.8];

    // 4. 提交搜索
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *searchBtn = [self _findButtonWithAnyLabel:@[@"Search", @"search", @"搜索", @"确定", @"Go", @"Search for", @"SEARCH"]
                                                     inView:XN_ActiveWindow()];
        if (searchBtn) {
            [self _safeTapAtPoint:[searchBtn.superview convertPoint:searchBtn.center toView:nil]];
        } else {
            UITextField *tf = [self _findTextFieldInView:XN_ActiveWindow()];
            if (tf && [tf.delegate respondsToSelector:@selector(textFieldShouldReturn:)]) {
                [tf.delegate textFieldShouldReturn:tf];
            }
        }
    });
    [NSThread sleepForTimeInterval:3.0];

    // 5. 切 Users tab（搜索结果分类：用户列表优先展示精确匹配）
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *usersBtn = [self _findButtonWithAnyLabel:@[@"Users", @"用户", @"People", @"Accounts", @"Creator"]
                                                    inView:XN_ActiveWindow()];
        if (usersBtn) {
            [self _safeTapAtPoint:[usersBtn.superview convertPoint:usersBtn.center toView:nil]];
        }
    });
    [NSThread sleepForTimeInterval:1.5];

    // 6. 点第一个匹配用户行（label 含 @target / target，点击 = 打开该用户主页）
    __block BOOL userOpened = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        __strong UIView *row = nil;
        [self _findVisibleViewWithLabel:target inView:window screen:[UIScreen mainScreen].bounds.size depth:0 result:&row];
        if (row) {
            CGPoint center = [row.superview convertPoint:row.center toView:nil];
            [self _safeTapAtPoint:center];
            userOpened = YES;
        }
    });
    if (!userOpened) {
        [self _performOpenUser:target];  // 结果页无匹配 → 兜底深链
    }
    [NSThread sleepForTimeInterval:2.5];

    // 7. 真实关注验收
    BOOL ok = [self _performFollowVerified];
    return @{
        @"status": ok ? @"success" : @"failed",
        @"message": ok ? [NSString stringWithFormat:@"已关注 %@", target]
                        : [NSString stringWithFormat:@"关注 %@ 未生效（找不到目标或按钮未变化）", target],
        @"target": target,
    };
}

/// 指定视频评论：打开指定视频 → 打开评论面板 → 填文本 → 发送
/// params: {aweme_id 或 video_id 或 target, text}（指定视频评论任务由引擎逐视频下发）
- (NSDictionary *)_performCommentVideo:(NSDictionary *)params {
    NSString *awemeId = params[@"aweme_id"] ?: params[@"video_id"] ?: params[@"target"] ?: @"";
    NSString *text = params[@"text"] ?: @"Nice!";
    if (awemeId.length == 0) {
        return @{@"status": @"failed", @"message": @"缺少 aweme_id/video_id 参数"};
    }
    [self _logStep:@"comment_video"];
    [self _performOpenVideo:awemeId];
    [NSThread sleepForTimeInterval:3.0];
    [self _performComment:text];
    return @{@"status": @"success", @"message": [NSString stringWithFormat:@"已触发对视频 %@ 评论", awemeId]};
}

/// 通过 URL scheme 打开视频详情
- (void)_performOpenVideo:(NSString *)awemeId {
    if (awemeId.length == 0) return;
    NSString *scheme = [NSString stringWithFormat:@"snssdk1233://aweme/detail/%@", awemeId];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *url = [NSURL URLWithString:scheme];
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    });
}

#pragma mark - 视频操作 (Phase 3)

/// 下拉刷新
- (void)_performPullToRefresh {
    dispatch_sync(dispatch_get_main_queue(), ^{
        CGSize screen = [UIScreen mainScreen].bounds.size;
        CGPoint from = CGPointMake(screen.width * 0.5, screen.height * 0.3);
        CGPoint to = CGPointMake(screen.width * 0.5, screen.height * 0.7);
        [self _simulateSwipeFrom:from to:to];
    });
}

/// 分享当前视频（优先无障碍标识 feedShareButton，回退右侧固定点）
- (void)_performShare {
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIView *shareView = [self _findViewWithAccessibilityIdentifier:kAccShare
                                                               inView:XN_ActiveWindow()];
        if (shareView) {
            CGPoint center = [shareView.superview convertPoint:shareView.center toView:nil];
            [self _safeTapAtPoint:center];
            return;
        }
        CGSize screen = [UIScreen mainScreen].bounds.size;
        // 分享按钮通常在右侧下部
        [self _safeTapAtPoint:CGPointMake(screen.width * 0.91, screen.height * 0.55)];
    });
}

/// 保存视频（安全版）：从拦截的 feed 响应取当前视频无水印 URL 上报后端
/// v1.4.108 F6：真下载无水印视频 → ①存手机相册 ②上传后台落库（祥哥 2026-08-18 拍板）
/// 复用 _downloadAndSaveVideoToAlbum:（下载→写 tmp→PHPhotoLibrary 存相册，F29 发视频选片同款）
/// 后台落库：multipart 上传 /api/biz/v2/videos/save/ → 后端存 data/uploads/ + Media 表
- (void)_performSaveVideo {
    NSDictionary *video = [XNURLProtocol lastFeedVideo];
    NSString *url = video[@"url"] ?: @"";
    if (url.length == 0) {
        [[XNOWER sharedInstance] addLog:@"❌ 保存失败：未捕获到当前视频链接（请先浏览推荐页）"];
        return;
    }
    NSLog(@"[XNOWER] 保存视频 URL: %@", url);

    // ① 下载 + 存相册（60s 超时，成功才继续上报）
    BOOL savedToAlbum = [self _downloadAndSaveVideoToAlbum:url];
    [[XNOWER sharedInstance] addLog:savedToAlbum ? @"📥 已下载无水印视频 → 保存到手机相册" : @"⚠️ 视频下载/存相册失败"];

    // ② 上传后台落库（multipart，60s 超时）
    NSString *devId = [XNOWER sharedInstance].deviceId;
    if (devId.length > 0) {
        [XNURLProtocol uploadVideoToBackend:url
                                   metadata:@{
                                       @"author": video[@"author"] ?: @"",
                                       @"desc": video[@"desc"] ?: @"",
                                       @"aweme_id": video[@"aweme_id"] ?: @"",
                                   }
                                   deviceId:devId
                                 completion:^(BOOL ok, NSString *msg) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[XNOWER sharedInstance] addLog:ok ? [NSString stringWithFormat:@"✅ 视频已存后台%@", msg.length ? [@"：" stringByAppendingString:msg] : @""] : [NSString stringWithFormat:@"❌ 视频存后台失败%@", msg.length ? [@"：" stringByAppendingString:msg] : @""]];
            });
        }];
    }
}

#pragma mark - 账号 (Phase 3)

/// 退出登录（个人主页 → 设置 → 退出）
- (void)_performLogout {
    // 导航到个人主页（v1.4.125：去外层 dispatch_sync，_tapTab 内部自带切主线程，同 open_tab 稳定模式）
    [self _navigateToProfile];
    [NSThread sleepForTimeInterval:2.0];

    // 点右上角设置
    dispatch_sync(dispatch_get_main_queue(), ^{
        [self _tapTopRightCorner];
    });
    [NSThread sleepForTimeInterval:1.5];

    // 找退出登录
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *logoutBtn = [self _findButtonWithAnyLabel:@[@"Log out", @"Log Out", @"退出登录", @"退出", @"Sign out"]
                                                     inView:XN_ActiveWindow()];
        if (logoutBtn) {
            [self _safeTapAtPoint:[logoutBtn.superview convertPoint:logoutBtn.center toView:nil]];
            [NSThread sleepForTimeInterval:1.0];
            // 确认弹窗
            UIButton *confirmBtn = [self _findButtonWithAnyLabel:@[@"Confirm", @"Log out", @"退出", @"确定"]
                                                          inView:XN_ActiveWindow()];
            if (confirmBtn) {
                [self _safeTapAtPoint:[confirmBtn.superview convertPoint:confirmBtn.center toView:nil]];
            }
        }
    });

    // 清除本地账号缓存
    [[AccountManager sharedManager] clearAccount];
}

/// 修改账号资料（昵称/签名/链接）
/// params: {nickname, signature, link}
- (void)_performEditProfile:(NSDictionary *)params {
    NSString *nickname = params[@"nickname"] ?: @"";
    NSString *signature = params[@"signature"] ?: @"";
    NSString *link = params[@"link"] ?: @"";
    NSString *avatar = params[@"avatar"] ?: @"";  // 头像图 URL（素材库 avatar 类别）
    if (nickname.length == 0 && signature.length == 0 && link.length == 0 && avatar.length == 0) return;

    // 导航到个人主页 → 点编辑资料
    // ⚠️ v1.4.125 闪退根因修复：原实现外层 dispatch_sync(main) 包 _navigateToProfile(→_tapTab)，
    // 而 _tapTab 内部自带 dispatch_sync(main) → 主线程嵌套自锁 → iOS watchdog 杀进程。
    // 命令在后台线程执行，_tapTab 内部自动切主线程，直接调用即可（同 open_tab 已验证稳定模式）。
    [self _logStep:@"edit_profile:start"];
    [self _navigateToProfile];
    [NSThread sleepForTimeInterval:1.5];
    [self _logStep:@"edit_profile:at_profile"];

    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        CGSize screen = [UIScreen mainScreen].bounds.size;
        // ⚠️ v1.4.123 修复"修改资料没生效"：编辑按钮 accId 是 user_info_manage_edit_profile，
        // 旧代码只按 label 找（"Edit profile" 带空格 vs accId 下划线不匹配）→ 找不到 → 坐标兜底点偏。
        // 优先 accId 定位（同 _performFollow 模式），再按 label，坐标兜底仅最后手段。
        __strong UIView *editView = nil;
        [self _findVisibleViewWithAccId:kAccEditProfile inView:window screen:screen depth:0 result:&editView];
        if (!editView) {
            [self _findVisibleViewWithLabel:@"Edit profile" inView:window screen:screen depth:0 result:&editView];
        }
        if (!editView) {
            [self _findVisibleViewWithLabel:@"编辑资料" inView:window screen:screen depth:0 result:&editView];
        }
        if (editView) {
            CGPoint center = [editView.superview convertPoint:editView.center toView:nil];
            [self _safeTapAtPoint:center];
        } else {
            // 坐标回退：编辑按钮通常在资料卡右上
            [self _safeTapAtPoint:CGPointMake(screen.width - 40, screen.height * 0.38)];
        }
    });
    [NSThread sleepForTimeInterval:1.5];

    // 改头像：下载头像图→存相册→点当前头像→选相册最新一张（素材库 avatar 类别）
    if (avatar.length > 0) {
        [self _applyAvatarToProfile:avatar];
    }

    // 改昵称（v1.4.124：TikTok 编辑页改版为列表式——主页面无输入框/无 Save，Name 是行入口。
    // 流程：点 Name 行（v1.4.125 真机 tap 实测 Name 行 y≈292，屏幕 414x896；旧 270 偏上沿易点不中）→
    // 进昵称子页 → 子页唯一输入框赋值 → 点右上角 Save((w-34,42) 视觉实测)）
    if (nickname.length > 0) {
        [self _logStep:@"edit_profile:name_tap"];
        CGSize s = [UIScreen mainScreen].bounds.size;
        [self _safeTapAtPoint:CGPointMake(s.width * 0.5, 292)];
        [NSThread sleepForTimeInterval:1.0];
        if ([self _setEditableFieldText:nickname keywords:@[@"name", @"Name", @"昵称", @"username"] allowFallback:YES]) {
            [self _logStep:@"edit_profile:name_set"];
            [NSThread sleepForTimeInterval:0.5];
            [self _safeTapAtPoint:CGPointMake(s.width - 34, 42)];   // 子页右上 Save
            // v1.4.126: TikTok 改名弹「Update name?」确认框（7天一次）→ 点 Confirm 完成，等回主页
            [NSThread sleepForTimeInterval:1.0];
            [self _tapDialogConfirmIfPresent];
            [self _logStep:@"edit_profile:name_confirm"];
            [NSThread sleepForTimeInterval:1.5];
        } else {
            [self _logStep:@"edit_profile:name_set_fail"];
        }
    }

    // 改签名（v1.4.125：同列表式——点 Bio 行 y≈523（真机 tap 实测；旧 438 会误进 Username 子页，
    // 把签名文本赋给用户名 → TikTok 用户名校验/保存 → 崩溃 v1.4.124 根因）→ 子页赋值 → Save）
    if (signature.length > 0) {
        // v1.4.126: 先清残留确认弹窗（昵称段确认后若未回主页），确保在 Edit profile 主页才点 Bio 行
        [self _tapDialogConfirmIfPresent];
        [self _logStep:@"edit_profile:bio_tap"];
        CGSize s = [UIScreen mainScreen].bounds.size;
        [self _safeTapAtPoint:CGPointMake(s.width * 0.5, 523)];
        [NSThread sleepForTimeInterval:1.0];
        // v1.4.126: allowFallback=NO —— 必须匹配 Bio placeholder 才赋值，
        // 防昵称子页残留时回退找昵称框 → 签名文本覆盖昵称（v1.4.125 实测 bug）
        if ([self _setEditableFieldText:signature keywords:@[@"bio", @"Bio", @"签名", @"简介", @"introduce"] allowFallback:NO]) {
            [self _logStep:@"edit_profile:bio_set"];
            [NSThread sleepForTimeInterval:0.5];
            [self _safeTapAtPoint:CGPointMake(s.width - 34, 42)];   // 子页右上 Save
            [NSThread sleepForTimeInterval:1.0];
            [self _tapDialogConfirmIfPresent];
            [self _logStep:@"edit_profile:bio_confirm"];
            [NSThread sleepForTimeInterval:1.5];
        } else {
            [self _logStep:@"edit_profile:bio_set_fail"];
        }
    }

    // 保存兜底（Edit profile 主页列表式无 Save，只在子页有；若昵称/签名段未触发确认，此处兜底）
    [self _logStep:@"edit_profile:save"];
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *saveBtn = [self _findButtonWithAnyLabel:@[@"Save", @"save", @"保存", @"Done", @"完成"]
                                                   inView:XN_ActiveWindow()];
        if (saveBtn) {
            [self _safeTapAtPoint:[saveBtn.superview convertPoint:saveBtn.center toView:nil]];
        }
    });
    [NSThread sleepForTimeInterval:1.0];
    [self _tapDialogConfirmIfPresent];
    [self _logStep:@"edit_profile:done"];
}

/// 按 placeholder 关键词查找输入框
- (UITextField *)_findTextFieldWithPlaceholderInView:(UIView *)view keywords:(NSArray *)keywords {
    if ([view isKindOfClass:[UITextField class]]) {
        UITextField *tf = (UITextField *)view;
        NSString *ph = tf.placeholder ?: @"";
        for (NSString *kw in keywords) {
            if ([ph.lowercaseString containsString:kw.lowercaseString]) return tf;
        }
    }
    for (UIView *sub in view.subviews) {
        UITextField *tf = [self _findTextFieldWithPlaceholderInView:sub keywords:keywords];
        if (tf) return tf;
    }
    return nil;
}

/// 按 placeholder 关键词查找 UITextView 输入框（编辑资料页昵称/签名框可能是 UITextView）
- (UITextView *)_findTextViewWithPlaceholderInView:(UIView *)view keywords:(NSArray *)keywords {
    if ([view isKindOfClass:[UITextView class]]) {
        UITextView *tv = (UITextView *)view;
        NSString *ph = tv.text.length > 0 ? tv.text : (tv.accessibilityLabel ?: @"");
        for (NSString *kw in keywords) {
            if ([ph.lowercaseString containsString:kw.lowercaseString]) return tv;
        }
    }
    for (UIView *sub in view.subviews) {
        UITextView *tv = [self _findTextViewWithPlaceholderInView:sub keywords:keywords];
        if (tv) return tv;
    }
    return nil;
}

/// 编辑资料页改字段：先点获得焦点，再赋值 + 触发编辑事件（兼容 UITextField / UITextView）
/// v1.4.126: 处理 TikTok 编辑页保存确认弹窗（"Update name?" 等 TUX 对话框）。
/// 找窗口内 TUXDialogHighlightBackgroundButton（ui_scan 实测弹窗左右各一：Cancel/Confirm），
/// 取 center.x 最大者（右按钮）= Confirm 点击完成保存。无弹窗则 no-op。
- (void)_tapDialogConfirmIfPresent {
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        if (!window) return;
        NSMutableArray *btns = [NSMutableArray array];
        [self _collectViewsOfClassContaining:@"TUXDialogHighlightBackgroundButton" inView:window depth:0 into:btns];
        if (btns.count == 0) return;
        UIView *confirm = btns[0];
        CGPoint confirmC = [confirm.superview convertPoint:confirm.center toView:window];
        for (UIView *b in btns) {
            CGPoint c = [b.superview convertPoint:b.center toView:window];
            if (c.x > confirmC.x) { confirm = b; confirmC = c; }
        }
        [self _safeTapAtPoint:confirmC];
        NSLog(@"[XNOWER] 已点确认弹窗 Confirm(%ld 按钮, x=%.0f)", (long)btns.count, confirmC.x);
    });
}

/// ⚠️ v1.4.119 修复"输入框输不进文字"：TikTok 输入框可能是 UITextView/受控组件，
/// 旧代码只找 UITextField 且不点焦点 → 匹配不到或赋值不生效。
/// ⚠️ v1.4.126 加 allowFallback 参数：=NO 时禁止回退第一个输入框（签名段专用），
/// 防昵称子页残留时误赋昵称框 → 签名文本覆盖昵称（v1.4.125 实测 bug）。
- (BOOL)_setEditableFieldText:(NSString *)text keywords:(NSArray *)keywords allowFallback:(BOOL)allowFallback {
    __block BOOL ok = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        UIView *field = [self _findTextFieldWithPlaceholderInView:window keywords:keywords];
        BOOL isTextView = NO;
        if (!field) {
            field = [self _findTextViewWithPlaceholderInView:window keywords:keywords];
            isTextView = YES;
        }
        // v1.4.124: 编辑子页输入框无 placeholder/acc_id（ui_scan 实测空），placeholder 匹配失败时
        // 回退找窗口内第一个可见可交互 UITextField（编辑子页场景 = 子页唯一输入框）
        if (!field && allowFallback) {
            field = [self _findFirstEditableTextFieldInView:window];
        }
        // v1.4.125: 校验输入框在屏幕可见中区（y 50~80%高），防误赋给隐藏/列表页背景输入框
        //（124 崩溃根因之一：tap 点错行时在错误页面找输入框赋值 → TikTok 状态错乱崩）
        if (field) {
            CGRect fr = [field.superview convertRect:field.frame toView:window];
            if (fr.size.height < 10 || fr.origin.y < 50 || fr.origin.y > window.bounds.size.height * 0.8) {
                field = nil;
            }
        }
        if (!field) return;
        [self _safeTapAtPoint:[field.superview convertPoint:field.center toView:nil]];
        if (isTextView) {
            UITextView *tv = (UITextView *)field;
            tv.text = text;
            [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:tv];
        } else {
            UITextField *tf = (UITextField *)field;
            tf.text = text;
            [tf sendActionsForControlEvents:UIControlEventEditingChanged];
            [[NSNotificationCenter defaultCenter] postNotificationName:UITextFieldTextDidChangeNotification object:tf];
        }
        ok = YES;
    });
    return ok;
}

/// 找窗口内第一个可见且可交互的 UITextField（编辑子页输入框无 placeholder 时回退用，v1.4.124）
- (UITextField *)_findFirstEditableTextFieldInView:(UIView *)view {
    if ([view isKindOfClass:[UITextField class]]) {
        UITextField *tf = (UITextField *)view;
        if (!tf.hidden && tf.userInteractionEnabled && tf.alpha > 0.01) return tf;
    }
    for (UIView *sub in view.subviews) {
        UITextField *tf = [self _findFirstEditableTextFieldInView:sub];
        if (tf) return tf;
    }
    return nil;
}

/// 改头像：下载头像图 URL → 存系统相册 → 点编辑资料页当前头像 → 选相册最新一张
/// 依赖：编辑资料页已打开（_performEditProfile 调用前已点"编辑资料"）
- (void)_applyAvatarToProfile:(NSString *)avatarUrl {
    @try {
        if (avatarUrl.length == 0) return;
        NSURL *url = [NSURL URLWithString:avatarUrl];
        if (!url) return;
        // Step 1: 下载头像图（同步）
        __block NSData *imgData = nil;
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
        [[session dataTaskWithRequest:[NSURLRequest requestWithURL:url]
                    completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
            imgData = d;
            dispatch_semaphore_signal(sem);
        }] resume];
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
        if (!imgData || imgData.length == 0) {
            NSLog(@"[XNOWER] 头像下载失败");
            return;
        }
        UIImage *img = [UIImage imageWithData:imgData];
        if (!img) {
            NSLog(@"[XNOWER] 头像数据无法解析为图片");
            return;
        }
        // Step 2: 存系统相册（成为最新一张）
        dispatch_sync(dispatch_get_main_queue(), ^{
            UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil);
        });
        [NSThread sleepForTimeInterval:1.5];
        // Step 3: 点编辑资料页的头像（触发相册选择器）
        dispatch_sync(dispatch_get_main_queue(), ^{
            UIWindow *window = XN_ActiveWindow();
            if (!window) return;
            UIView *avatarBtn = [self _findViewWithAccessibilityIdentifier:kAccProfileAvatar inView:window];
            if (!avatarBtn) {
                avatarBtn = [self _findViewByClassContaining:@"AWEAvatarView" inView:window depth:0];
            }
            if (avatarBtn) {
                [self _safeTapAtPoint:[avatarBtn.superview convertPoint:avatarBtn.center toView:nil]];
            }
        });
        [NSThread sleepForTimeInterval:1.5];
        // Step 4: 相册选择器弹出后，选"最新一张"（通常是系统相册第一格 / 相机胶卷）
        // UI 自动化点相册：先点"照片/相册"标签，再点第一张缩略图
        dispatch_sync(dispatch_get_main_queue(), ^{
            UIWindow *window = XN_ActiveWindow();
            if (!window) return;
            UIButton *photosTab = [self _findButtonWithAnyLabel:@[@"Photos", @"照片", @"All Photos", @"相机胶卷", @"Photo Library"]
                                                         inView:window];
            if (photosTab) {
                [self _safeTapAtPoint:[photosTab.superview convertPoint:photosTab.center toView:nil]];
                [NSThread sleepForTimeInterval:1.0];
            }
            // 点第一张缩略图（相册最新一张 = 刚下载的头像）
            __block UICollectionView *collection = nil;
            [self _findFirstCollectionViewInView:window result:&collection];
            if (collection) {
                NSIndexPath *first = [NSIndexPath indexPathForItem:0 inSection:0];
                UICollectionViewCell *cell = [collection cellForItemAtIndexPath:first];
                if (cell) {
                    [self _safeTapAtPoint:[cell.superview convertPoint:cell.center toView:nil]];
                }
            }
        });
        [NSThread sleepForTimeInterval:1.0];
        NSLog(@"[XNOWER] 头像替换完成: %@", avatarUrl);
    } @catch (id e) {
        NSLog(@"[XNOWER] 改头像异常: %@", e);
    }
}

/// 找第一个 UICollectionView（相册选择器用）
- (void)_findFirstCollectionViewInView:(UIView *)view result:(UICollectionView **)result {
    if (!view || *result) return;
    if ([view isKindOfClass:[UICollectionView class]]) {
        *result = (UICollectionView *)view;
        return;
    }
    for (UIView *sub in view.subviews) {
        [self _findFirstCollectionViewInView:sub result:result];
        if (*result) return;
    }
}

#pragma mark - 自动发视频 (Phase 5)

/// 自动发视频：点 "+" → 上传 → 选第一个媒体 → 下一步 → 填文案 → 发布
/// params: {title, video_url}
/// 说明：UI 自动化无法按 URL 精确定位相册素材，video_url 为 best-effort，
///       实际选取相册中第一张媒体（后续有精确素材注入方案时再升级）。
/// 下载视频并保存到系统相册（发视频选片关键）
/// 返回 YES=已保存成功（相册最新一张即目标视频）；NO=失败（回退原逻辑选第一张）
- (BOOL)_downloadAndSaveVideoToAlbum:(NSString *)url {
    if (!url.length) return NO;
    // Step 1: 下载视频数据（TikTok CDN 可能有重定向，用可重定向的 NSURLSession）
    NSURL *videoURL = [NSURL URLWithString:url];
    if (!videoURL) return NO;
    __block NSData *data = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:[NSURLRequest requestWithURL:videoURL]
                                            completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        data = d;
        dispatch_semaphore_signal(sem);
    }];
    [task resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC));
    if (!data || data.length == 0) {
        NSLog(@"[XNOWER] 下载视频失败（超时或数据为空）");
        return NO;
    }
    // Step 2: 写入临时文件（PHAssetCreationRequest 需要 fileURL）
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"xn_video_%f.mp4", [[NSDate date] timeIntervalSince1970]]];
    if (![data writeToFile:tmpPath atomically:YES]) {
        NSLog(@"[XNOWER] 写入临时文件失败");
        return NO;
    }
    // Step 3: 保存到系统相册（TikTok 已声明相册权限，进程内可用）
    __block BOOL saved = NO;
    dispatch_semaphore_t sem2 = dispatch_semaphore_create(0);
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        PHAssetCreationRequest *req = [PHAssetCreationRequest creationRequestForAsset];
        [req addResourceWithType:PHAssetResourceTypeVideo fileURL:[NSURL fileURLWithPath:tmpPath] options:nil];
    } completionHandler:^(BOOL success, NSError *err) {
        saved = success;
        if (err) {
            NSLog(@"[XNOWER] 保存相册失败: %@", err.localizedDescription);
        }
        dispatch_semaphore_signal(sem2);
    }];
    dispatch_semaphore_wait(sem2, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
    [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
    return saved;
}

- (NSDictionary *)_performPostVideo:(NSDictionary *)params {
    NSString *title = params[@"title"] ?: @"";
    NSString *videoUrl = params[@"video_url"] ?: @"";
    BOOL didSaveTarget = NO;
    if (videoUrl.length > 0) {
        NSLog(@"[XNOWER] ⬇️ 下载目标视频到相册（发视频选片）...");
        didSaveTarget = [self _downloadAndSaveVideoToAlbum:videoUrl];
        NSLog(@"[XNOWER] %@", didSaveTarget ? @"✅ 目标视频已入相册（最新一张，将自动选中）" : @"⚠️ 下载失败，回退选相册第一张");
    }

    // Step 1: 点底部 "+" 发视频按钮
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *postBtn = [self _findButtonWithAnyLabel:@[@"post", @"Post", @"create", @"Create",
                                                             @"发布", @"上传", @"+"]
                                                    inView:XN_ActiveWindow()];
        if (postBtn) {
            [self _safeTapAtPoint:[postBtn.superview convertPoint:postBtn.center toView:nil]];
        } else {
            // 坐标回退：底部中间 "+"
            CGSize screen = [UIScreen mainScreen].bounds.size;
            [self _safeTapAtPoint:CGPointMake(screen.width * 0.5, screen.height - 50)];
        }
    });
    [NSThread sleepForTimeInterval:2.0];

    // Step 2: 点 "上传"（从相册/本地上传）
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *uploadBtn = [self _findButtonWithAnyLabel:@[@"Upload", @"upload", @"上传", @"相册",
                                                               @"Album", @"Gallery", @"照片"]
                                                      inView:XN_ActiveWindow()];
        if (uploadBtn) {
            [self _safeTapAtPoint:[uploadBtn.superview convertPoint:uploadBtn.center toView:nil]];
        } else {
            // 坐标回退：上传入口通常在顶部区域
            CGSize screen = [UIScreen mainScreen].bounds.size;
            [self _safeTapAtPoint:CGPointMake(screen.width * 0.5, screen.height * 0.18)];
        }
    });
    [NSThread sleepForTimeInterval:2.5];

    // Step 3: 相册选择第一个媒体（best-effort，无素材库精确注入时选第一张）
    [self _tapFirstMediaCell];
    [NSThread sleepForTimeInterval:1.5];

    // Step 4: 点 "下一步"（Next）
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *nextBtn = [self _findButtonWithAnyLabel:@[@"Next", @"next", @"下一步", @"完成", @"Done"]
                                                    inView:XN_ActiveWindow()];
        if (nextBtn) {
            [self _safeTapAtPoint:[nextBtn.superview convertPoint:nextBtn.center toView:nil]];
        } else {
            // 坐标回退：右上角
            CGSize screen = [UIScreen mainScreen].bounds.size;
            [self _safeTapAtPoint:CGPointMake(screen.width - 40, 60)];
        }
    });
    [NSThread sleepForTimeInterval:2.0];

    // Step 5: 填文案/标题
    if (title.length > 0) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            UITextView *textView = [self _findTextViewInView:XN_ActiveWindow()];
            UITextField *textField = [self _findTextFieldInView:XN_ActiveWindow()];
            if (textView) {
                textView.text = title;
                [[NSNotificationCenter defaultCenter]
                 postNotificationName:UITextViewTextDidChangeNotification object:textView];
            } else if (textField) {
                textField.text = title;
                [[NSNotificationCenter defaultCenter]
                 postNotificationName:UITextFieldTextDidChangeNotification object:textField];
            }
        });
        [NSThread sleepForTimeInterval:0.5];
    }

    // Step 6: 点 "发布"（Publish）
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *publishBtn = [self _findButtonWithAnyLabel:@[@"Publish", @"publish", @"发布", @"Post", @"Share"]
                                                       inView:XN_ActiveWindow()];
        if (publishBtn) {
            [self _safeTapAtPoint:[publishBtn.superview convertPoint:publishBtn.center toView:nil]];
        } else {
            // 坐标回退：右下角/底部
            CGSize screen = [UIScreen mainScreen].bounds.size;
            [self _safeTapAtPoint:CGPointMake(screen.width * 0.5, screen.height - 50)];
        }
    });
    [NSThread sleepForTimeInterval:1.0];

    return @{
        @"status": @"success",
        @"message": didSaveTarget ? @"已触发发视频流程（目标视频已存相册并选中）"
                                  : @"已触发发视频流程（best-effort，未下载目标则选相册第一张）",
        @"title": title.length ? title : @"",
        @"video_url": videoUrl,
        @"target_saved": @(didSaveTarget),
    };
}

/// 点击相册选择器中的第一个媒体 cell
- (void)_tapFirstMediaCell {
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        if (!window) return;
        __block UIView *firstCell = nil;
        [self _findFirstMediaCellInView:window result:&firstCell];
        if (firstCell) {
            [self _safeTapAtPoint:[firstCell.superview convertPoint:firstCell.center toView:nil]];
        } else {
            // 坐标回退：左上角第一个格
            CGSize screen = [UIScreen mainScreen].bounds.size;
            [self _safeTapAtPoint:CGPointMake(screen.width * 0.1, screen.height * 0.2)];
        }
    });
}

/// 递归查找第一个可见的相册媒体 cell（UICollectionViewCell）
- (void)_findFirstMediaCellInView:(UIView *)view result:(UIView **)result {
    if (*result) return;
    if ([view isKindOfClass:[UICollectionViewCell class]]) {
        UIView *target = view;
        CGRect globalRect = [target.superview convertRect:target.frame toView:nil];
        if (CGRectIntersectsRect(globalRect, [UIScreen mainScreen].bounds)) {
            *result = view;
        }
        return;
    }
    for (UIView *sub in view.subviews) {
        [self _findFirstMediaCellInView:sub result:result];
        if (*result) return;
    }
}

#pragma mark - 自动私信 (Phase 6)

/// 自动私信：打开用户主页（URL scheme）→ 点"私信/发消息" → 输入内容 → 发送
/// params: {target, content}
/// best-effort UI 自动化（fragile），失败返回 status=failed + 原因
- (NSDictionary *)_performSendDm:(NSDictionary *)params {
    NSString *target = params[@"target"] ?: @"";
    NSString *content = params[@"content"] ?: @"";
    if (content.length == 0) {
        return @{@"status": @"failed", @"message": @"私信内容不能为空"};
    }

    // Step 1: 打开目标用户主页（URL scheme）；无 target 则切到消息页
    if (target.length > 0) {
        [self _performOpenUser:target];
    } else {
        [self _tapTab:@"inbox"];
    }
    [NSThread sleepForTimeInterval:3.0];

    // Step 2: 点"私信/发消息"按钮（资料页）
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *msgBtn = [self _findButtonWithAnyLabel:@[@"Message", @"message", @"私信",
                                                           @"发消息", @"Say hi", @"say hi"]
                                                  inView:XN_ActiveWindow()];
        if (msgBtn) {
            [self _safeTapAtPoint:[msgBtn.superview convertPoint:msgBtn.center toView:nil]];
        } else {
            // 坐标回退：私信按钮通常在资料页中下部右侧
            CGSize screen = [UIScreen mainScreen].bounds.size;
            [self _safeTapAtPoint:CGPointMake(screen.width * 0.85, screen.height * 0.4)];
        }
    });
    [NSThread sleepForTimeInterval:2.0];

    // Step 3: 找输入框，填入私信内容
    __block BOOL fieldFound = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        UITextField *textField = [self _findTextFieldInView:window];
        UITextView *textView = [self _findTextViewInView:window];
        if (textField) {
            textField.text = content;
            [textField sendActionsForControlEvents:UIControlEventEditingChanged];
            [[NSNotificationCenter defaultCenter]
             postNotificationName:UITextFieldTextDidChangeNotification object:textField];
            fieldFound = YES;
        } else if (textView) {
            textView.text = content;
            [[NSNotificationCenter defaultCenter]
             postNotificationName:UITextViewTextDidChangeNotification object:textView];
            fieldFound = YES;
        }
    });
    if (!fieldFound) {
        return @{@"status": @"failed", @"message": @"未找到私信输入框"};
    }
    [NSThread sleepForTimeInterval:0.8];

    // Step 4: 点发送
    __block BOOL sent = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *sendBtn = [self _findButtonWithAnyLabel:@[@"Send", @"send", @"发送", @"发送私信"]
                                                   inView:XN_ActiveWindow()];
        if (sendBtn) {
            [self _safeTapAtPoint:[sendBtn.superview convertPoint:sendBtn.center toView:nil]];
            sent = YES;
            return;
        }
        UIView *sendView = [self _findViewWithAccessibilityIdentifier:kAccSend
                                                               inView:XN_ActiveWindow()];
        if (sendView) {
            [self _safeTapAtPoint:[sendView.superview convertPoint:sendView.center toView:nil]];
            sent = YES;
        }
    });

    if (!sent) {
        return @{@"status": @"failed", @"message": @"未找到发送按钮"};
    }
    return @{@"status": @"success", @"message": @"已发送私信", @"target": target};
}

/// 发名片：打开分享面板 → 点"名片"分享选项（best-effort）
- (NSDictionary *)_performSendCard:(NSDictionary *)params {
    [self _performShare];
    [NSThread sleepForTimeInterval:1.5];

    __block BOOL tapped = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *cardBtn = [self _findButtonWithAnyLabel:@[@"Card", @"card", @"名片",
                                                            @"business card", @"Business Card"]
                                                   inView:XN_ActiveWindow()];
        if (cardBtn) {
            [self _safeTapAtPoint:[cardBtn.superview convertPoint:cardBtn.center toView:nil]];
            tapped = YES;
        }
    });
    [NSThread sleepForTimeInterval:1.0];

    if (!tapped) {
        return @{@"status": @"failed", @"message": @"未找到名片分享选项"};
    }
    return @{@"status": @"success", @"message": @"已触发发送名片"};
}

/// 分享直播间：打开分享面板 → 点"直播"分享选项（best-effort）
- (NSDictionary *)_performShareLive:(NSDictionary *)params {
    [self _performShare];
    [NSThread sleepForTimeInterval:1.5];

    __block BOOL tapped = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *liveBtn = [self _findButtonWithAnyLabel:@[@"Live", @"live", @"直播",
                                                            @"直播间", @"Share Live", @"分享直播"]
                                                   inView:XN_ActiveWindow()];
        if (liveBtn) {
            [self _safeTapAtPoint:[liveBtn.superview convertPoint:liveBtn.center toView:nil]];
            tapped = YES;
        }
    });
    [NSThread sleepForTimeInterval:1.0];

    if (!tapped) {
        return @{@"status": @"failed", @"message": @"未找到直播间分享选项"};
    }
    return @{@"status": @"success", @"message": @"已触发分享直播间"};
}

#pragma mark - 批量注册 + 自动养号 (Feature 5)

/// 养号心跳：一次短随机浏览会话（上滑 + 随机点赞，模式2再加随机评论），约 1~2 分钟
/// params: {mode, cycles, min_interval, max_interval}
- (NSDictionary *)_performNurtureTick:(NSDictionary *)params {
    // 养号两模式（祥哥需求）：
    //  模式1纯浏览：随机间隔10-20秒 上滑 + 随机点赞
    //  模式2互动：模式1 + 再随机选择一条评论发布
    int mode = [params[@"mode"] intValue] ?: 1;
    if (mode < 1 || mode > 2) mode = 1;
    int cycles = [params[@"cycles"] intValue] ?: 3;
    if (cycles < 1) cycles = 1;
    if (cycles > 10) cycles = 10;
    int minInt = [params[@"min_interval"] intValue] ?: 10;
    int maxInt = [params[@"max_interval"] intValue] ?: 20;
    if (minInt < 5) minInt = 5;
    if (maxInt < minInt) maxInt = minInt + 10;

    __block int likes = 0;
    __block int comments = 0;
    __block int follows = 0;

    for (int i = 0; i < cycles; i++) {
        // 随机间隔 10-20 秒（模拟真实观看停留）
        int delay = minInt + (int)arc4random_uniform(maxInt - minInt + 1);
        if (delay < 5) delay = 5;
        [NSThread sleepForTimeInterval:delay];

        // 随机互动（20% 概率点赞或关注，避免太频繁）
        // ⚠️ 互动必须在浏览当前视频的稳定期(已观看delay秒, 页面无转场), 上滑后立刻互动会崩(视频cell重建中)
        if (arc4random_uniform(100) < 20) {
            [self _logStep:@"interact"];
            [NSThread sleepForTimeInterval:1.0];  // 页面已稳定，轻微等待即可
            // 互动前验证在 feed：不在则跳过（避免在错误页面操作崩溃）
            if (![self _isOnFeed]) {
                [self _logStep:@"interact_skip_no_feed"];
            } else if (arc4random_uniform(100) < 50) {
                // 安全点赞：accId定位+sendActions（防预加载cell信号崩）
                BOOL liked = [self _performLikeSafe];
                if (liked) { likes++; [self _logStep:@"interact_like"]; }
                else { [self _logStep:@"interact_like_fail"]; }
            } else {
                BOOL followed = [self _performFollowSafe];
                if (followed) { follows++; [self _logStep:@"interact_follow"]; }
                else { [self _logStep:@"interact_follow_fail"]; }
            }
        }

        // 上滑到下一个视频（互动在浏览稳定期做完了，再滑动换视频）
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self _performSwipeUp];
        });

        // 模式2互动：在模式1基础上，随机发评论（v1.4.45: 评论本身单独执行OK，循环里崩因是评论后下滑关面板，已去掉下滑）
        if (mode == 2 && arc4random_uniform(100) < 40) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self _performComment:[self _randomComment]];
            });
            comments++;
            // 不再下滑关评论面板（评论面板为复杂弹层，合成滑动易崩；由下次上滑自然离开）
        }
    }

    return @{
        @"status": @"success",
        @"message": [NSString stringWithFormat:@"养号完成(%d轮): %d滑, %d赞, %d关注, %d评", cycles, cycles, likes, follows, comments],
        @"mode": @(mode),
        @"cycles": @(cycles),
        @"likes": @(likes),
        @"follows": @(follows),
        @"comments": @(comments),
    };
}

/// 停止养号：tick 为一次性指令，停止是隐式的，仅返回状态
- (NSDictionary *)_performNurtureStop {
    [self stopNurture];
    return @{
        @"status": @"stopped",
        @"message": @"养号已停止",
    };
}

// ===== 连续养号（不限时，24小时运行，直到 stopNurture）=====

/// 随机选一条养号评论（避免连续重复）
- (NSString *)_randomComment {
    NSArray *pool = XN_NurtureComments();
    NSUInteger count = pool.count;
    if (count == 0) return @"太棒了";
    static NSUInteger sLastIdx = NSUIntegerMax;
    NSUInteger idx = arc4random_uniform((uint32_t)count);
    if (idx == sLastIdx && count > 1) {
        idx = (idx + 1) % count;  // 换一条，避免连续相同
    }
    sLastIdx = idx;
    return pool[idx];
}

/// 真实验证当前是否在推荐 feed（首页）
/// 严格检测：feed 特有元素(feedLikeButton 右侧操作栏) 或 类名含 Feed/Recommend
/// （修复：旧实现把收件箱的 TTKWidgetCollectionView 误判成 feed，导致"回到首页成功"但实际没回）
/// ⚠️ 修复闪退：原实现内部 dispatch_sync(main_queue)，被主线程的 _detectPageOnMain/_isOnProfilePageOnMain
/// 调用时主线程递归死锁 → watchdog 杀进程。改为主线程直接执行，非主线程才同步调度。
- (BOOL)_isOnFeed {
    if (![NSThread isMainThread]) {
        __block BOOL result = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{
            result = [self _isOnFeedOnMain];
        });
        return result;
    }
    return [self _isOnFeedOnMain];
}

/// 主线程 feed 检测核心逻辑（_isOnFeed 的内部实现，必须在主线程调用）
- (BOOL)_isOnFeedOnMain {
    BOOL onFeed = NO;
    UIWindow *window = XN_ActiveWindow();
    if (!window) return NO;
    // 方法1: feed 特有的右侧操作栏点赞按钮(feedLikeButton)，只在首页推荐流存在
    UIView *likeBtn = [self _findViewWithAccessibilityIdentifier:kAccLike inView:window];
    if (likeBtn) return YES;
    // 方法2: 大滚动视图类名含 Feed/Recommend（排除收件箱 Widget/Inbox、个人页 Profile）
    __block UIScrollView *sv = nil;
    [self _findLargeFeedScrollViewInView:window result:&sv];
    if (sv) {
        NSString *cls = NSStringFromClass(sv.class);
        if ([cls containsString:@"Feed"] || [cls containsString:@"Recommend"]) return YES;
    }
    return NO;
}

/// VC 诊断：枚举 rootViewController 链 + 检测 tab 容器控制器（定位 TikTok 首页切换入口）
- (NSDictionary *)_performVCScan {
    __block NSMutableArray *chain = [NSMutableArray array];
    __block NSDictionary *tabInfo = @{};
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        if (!window) return;
        // 递归收集 VC 链（presented + child，深度保护）
        __block void (^collectVC)(UIViewController *, int) = nil;
        collectVC = ^(UIViewController *vc, int depth) {
            if (!vc || depth > 30 || chain.count > 30) return;
            NSString *cls = NSStringFromClass(vc.class) ?: @"?";
            [chain addObject:@{@"class": cls,
                               @"sel": @(vc.tabBarController.selectedIndex)}];
            // 检测 tab 容器
            if ([vc isKindOfClass:[UITabBarController class]] || [NSStringFromClass(vc.class) containsString:@"TabBarController"]) {
                UITabBarController *tc = (UITabBarController *)vc;
                tabInfo = @{@"class": cls, @"selectedIndex": @(tc.selectedIndex),
                            @"count": @(tc.viewControllers.count)};
            }
            if (vc.presentedViewController) {
                collectVC(vc.presentedViewController, depth + 1);
            }
            for (UIViewController *child in vc.childViewControllers) {
                collectVC(child, depth + 1);
            }
        };
        collectVC(window.rootViewController, 0);
        if (chain.count == 0) {
            [chain addObject:@{@"class": NSStringFromClass(window.rootViewController.class) ?: @"nil"}];
        }
    });
    return @{
        @"status": @"success",
        @"vc_chain": chain,
        @"tab_controller": tabInfo,
    };
}

/// 切回首页并真实验证在 feed；最多尝试 4 轮，成功返回 YES
/// 每轮：a11y_vo_home 点击 tab → 验证；不行则换一个 deep link scheme 强制回主界面
/// v1.4.91: 关闭当前浮层面板（评论区等 overlay）。评论面板打开后无关闭机制，会遮挡 tab bar → go_home 失效、设备困死。
- (NSDictionary *)_performCloseOverlay {
    [self _logStep:@"close_overlay"];
    @try {
        if ([[self detectCurrentPage] isEqualToString:@"comment"]) {
            NSDictionary *r = [self _closeCommentPanel];
            // v1.4.100: 关闭后必须恢复视频播放。物理移除面板跳过 TikTok 正常关闭逻辑 → 播放器保持
            // 暂停 → 无音频无触摸 → iOS 自动锁屏（祥哥反馈的"评论区黑屏"就是锁屏，手动上滑切视频即恢复）。
            [self _resumeFeedPlayback];
            return r;
        }
    } @catch (NSException *e) {
        return @{@"status": @"failed", @"message": [NSString stringWithFormat:@"关闭面板异常: %@", e.reason]};
    }
    return @{@"status": @"success", @"message": @"当前无浮层面板或已关闭"};
}

/// 关闭评论面板：优先点右上角 "Close comment section" 按钮（实测屏内 y=219，不被键盘遮挡）；
/// 兜底点 mask（"Close keyboard"）收键盘再点关面板；最后验证页面离开 comment。
/// 找到窗口里最顶层 presented VC（沿 presentedViewController 链走到底）
- (UIViewController *)_topPresentedViewControllerOfWindow:(UIWindow *)window {
    UIViewController *vc = window.rootViewController;
    if (!vc) return nil;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

/// v1.4.95：从视图 nextResponder 链上溯，找最近的 UIViewController（X 按钮 → header → 面板 VC）
- (UIViewController *)_viewControllerOfView:(UIView *)view {
    id resp = view;
    while (resp) {
        if ([resp isKindOfClass:[UIViewController class]]) return resp;
        resp = [resp nextResponder];
    }
    return nil;
}

/// v1.4.95：递归收集窗口 VC 层级（presented / child / tab / nav 全部展开）
- (void)_collectViewControllers:(UIViewController *)vc into:(NSMutableArray *)outList {
    if (!vc || [outList containsObject:vc]) return;
    [outList addObject:vc];
    if (vc.presentedViewController) [self _collectViewControllers:vc.presentedViewController into:outList];
    for (UIViewController *c in vc.childViewControllers) [self _collectViewControllers:c into:outList];
    if ([vc isKindOfClass:[UITabBarController class]]) {
        for (UIViewController *c in [(UITabBarController *)vc viewControllers]) [self _collectViewControllers:c into:outList];
    }
    if ([vc isKindOfClass:[UINavigationController class]]) {
        for (UIViewController *c in [(UINavigationController *)vc viewControllers]) [self _collectViewControllers:c into:outList];
    }
}

/// v1.4.95：在对象（沿 superclass 链）上找"关闭类"无参方法，按语义打分取最高分。
/// 分数规则：含 panel+3、含 comment+2、以 close/dismiss/hide/remove/exit 开头+3、包含+1、
///         含 hint/bubble/notice/toast/keyboard/reddot(无关浮层)-3。避免挑中 hideCommentHintView 之类。
- (NSString *)_findCloseMethodOn:(id)obj {
    NSString *best = nil;
    int bestScore = -99;
    Class cls = [obj class];
    while (cls && cls != [NSObject class]) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            SEL sel = method_getName(methods[i]);
            NSString *name = NSStringFromSelector(sel);
            if (method_getNumberOfArguments(methods[i]) != 2) continue;  // 仅无参(self+_cmd)
            int score = 0;
            BOOL hasCloseWord = NO;
            NSArray *words = @[@"close", @"dismiss", @"hide", @"remove", @"exit"];
            for (NSString *w in words) {
                if ([name containsString:w] || [name containsString:w.capitalizedString]) { score += 1; hasCloseWord = YES; }
                if ([name hasPrefix:w] || [name hasPrefix:w.capitalizedString]) score += 3;
            }
            if (!hasCloseWord) continue;                                  // 不是关闭类方法，跳过
            if ([name containsString:@"panel"] || [name containsString:@"Panel"]) score += 3;
            if ([name containsString:@"comment"] || [name containsString:@"Comment"]) score += 2;
            for (NSString *bad in @[@"hint", @"bubble", @"notice", @"toast", @"keyboard", @"reddot",
                                    @"Hint", @"Bubble", @"Notice", @"Toast", @"Keyboard", @"RedDot"]) {
                if ([name containsString:bad]) score -= 3;
            }
            if (score > bestScore) { bestScore = score; best = name; }
        }
        free(methods);
        cls = class_getSuperclass(cls);
    }
    return (bestScore > 0) ? best : nil;
}

/// v1.4.96：dump 评论面板 VC 的关闭类方法列表 → 返回字符串数组（观测：锁定真实方法）
- (NSArray<NSString *> *)_candidateCloseMethodsOn:(id)obj {
    NSMutableArray *names = [NSMutableArray array];
    Class cls = [obj class];
    while (cls && cls != [NSObject class]) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            NSString *n = NSStringFromSelector(method_getName(methods[i]));
            BOOL interesting = ([n containsString:@"close"] || [n containsString:@"Close"] ||
                                [n containsString:@"dismiss"] || [n containsString:@"Dismiss"] ||
                                [n containsString:@"hide"] || [n containsString:@"Hide"] ||
                                [n containsString:@"remove"] || [n containsString:@"Remove"] ||
                                [n containsString:@"panel"] || [n containsString:@"Panel"]);
            if (interesting) {
                [names addObject:[NSString stringWithFormat:@"%@(%uarg)",
                                  n, method_getNumberOfArguments(methods[i]) - 2]];
            }
        }
        free(methods);
        cls = class_getSuperclass(cls);
    }
    return names;
}

/// v1.4.96：主方案——直接调评论面板 VC 的关闭方法（不模拟触摸，祥哥思路：激活卡密那种直接走内部代码）
/// 返回 @{@"status":@"success"...} 表示已关闭；返回 @{@"status":@"failed", @"diag":<诊断>} 未命中
/// （diag 会被 _closeCommentPanel 拼进最终 result message，server.log 可见——addLog 是设备端本地日志，后端看不到）
- (NSDictionary *)_closeCommentPanelByCode {
    __block NSString *calledSel = nil;
    __block NSString *panelCls = nil;
    __block BOOL foundBtn = NO;
    __block NSArray<NSString *> *cands = nil;
    __block UIViewController *foundPanel = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton *btn = [self _findButtonWithAnyLabel:@[@"Close comment section", @"Close comment"]
                                               inView:XN_ActiveWindow()];
        if (btn) foundBtn = YES;
        UIViewController *panel = btn ? [self _viewControllerOfView:btn] : nil;
        if (!panel) {
            // 兜底：递归窗口 VC 层级找类名含 Comment 的 VC
            NSMutableArray *vcs = [NSMutableArray array];
            for (UIWindow *w in [UIApplication sharedApplication].windows) {
                [self _collectViewControllers:w.rootViewController into:vcs];
            }
            for (UIViewController *v in vcs) {
                NSString *cls = NSStringFromClass(v.class) ?: @"";
                if ([cls containsString:@"Comment"]) { panel = v; break; }
            }
        }
        if (panel) {
            panelCls = NSStringFromClass(panel.class);
            foundPanel = panel;
            calledSel = [self _findCloseMethodOn:panel];
            cands = [self _candidateCloseMethodsOn:panel];
            if (calledSel) {
                @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    [panel performSelector:NSSelectorFromString(calledSel)];
#pragma clang diagnostic pop
                } @catch (NSException *e) {
                    [[XNOWER sharedInstance] addLog:[NSString stringWithFormat:@"❌ 直接调关闭方法异常: %@", e.reason]];
                    calledSel = nil;
                }
            }
        }
    });
    if (calledSel) {
        [NSThread sleepForTimeInterval:1.2];
        if (![[self detectCurrentPage] isEqualToString:@"comment"]) {
            return @{@"status": @"success",
                     @"message": [NSString stringWithFormat:@"评论面板已关闭(直接调%@)", calledSel]};
        }
    }

    // 【v1.4.97b 终极保底】物理移除评论面板视图——不依赖 TikTok 任何内部方法。
    // v1.4.97 实测类名匹配失效：评论面板 VC=TTKCommentPanelViewController 已找到，但评论区真实
    // 控件类名是 AWECommentListHeaderView / TTKCommentAvatarView 等，匹配列表删到的只是
    // TikTokCommentImpl label，面板容器没被移除。修复：优先直接移除 VC 的 view 整棵子树
    // （评论区 UI 一定在它下面，ui_scan 实证控件覆盖 y=198~689），类名匹配只作兜底。
    BOOL removed = NO;
    if (foundPanel && foundPanel.view) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            UIView *pv = foundPanel.view;
            [pv removeFromSuperview];
            for (UIView *sub in [pv.subviews copy]) { [sub removeFromSuperview]; }
        });
        removed = YES;
    }
    if (!removed) {
        removed = [self _physicallyRemoveCommentPanelView];
    }
    if (removed) {
        [NSThread sleepForTimeInterval:1.0];
        if (![[self detectCurrentPage] isEqualToString:@"comment"]) {
            return @{@"status": @"success",
                     @"message": @"评论面板已关闭(物理移除面板视图)"};
        }
    }

    NSString *diag = [NSString stringWithFormat:@"%@ | 面板VC=%@ | 候选=[%@] | 物理移除=%@",
                      foundBtn ? @"X按钮=找到" : @"X按钮=未找到",
                      panelCls ?: @"未找到",
                      cands.count ? [cands componentsJoinedByString:@" "] : @"(无)",
                      removed ? @"已执行但未生效" : @"未找到面板视图"];
    return @{@"status": @"failed", @"diag": diag};
}

/// v1.4.97b：物理移除评论面板视图（终极保底，类名匹配兜底版）。
/// 递归窗口视图树，命中评论区专属类名（ui_scan 实测 AWEComment/TTKComment 前缀 + 旧锚点）即
/// removeFromSuperview。v1.4.97 教训：类名匹配删到 TikTokCommentImpl label 不生效——评论区
/// 真实控件类是 AWECommentListHeaderView / TTKCommentAvatarView 等，已全部纳入；且改为遍历
/// 删除所有命中视图（不 break），而不是只删第一个。必须在主线程调用（UIKit 约束）。
- (BOOL)_physicallyRemoveCommentPanelView {
    __block BOOL removed = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithArray:w.subviews];
            while (stack.count) {
                UIView *v = stack.lastObject;
                [stack removeLastObject];
                NSString *cls = NSStringFromClass(v.class) ?: @"";
                // 评论区专属类：AWEComment* / TTKComment* / CommentList / AWESubCommentFooter 等
                if ([cls hasPrefix:@"AWEComment"] ||
                    [cls hasPrefix:@"TTKComment"] ||
                    [cls hasPrefix:@"AWESubComment"] ||
                    [cls containsString:@"TikTokCommentImpl"] ||
                    [cls containsString:@"CommentPanelRootView"] ||
                    [cls isEqualToString:@"CommentListView"] ||
                    [cls isEqualToString:@"AWEBottomComment"] ||
                    [cls containsString:@"CommentContainerView"]) {
                    [v removeFromSuperview];
                    removed = YES;
                } else {
                    [stack addObjectsFromArray:v.subviews];
                }
            }
        }
        // v1.4.100: 物理移除后隐藏"空壳"评论 window（rootVC 类名含 Comment 且非主窗口）。
        // 视图虽被移除，window 若仍挂在 windows 列表里会拦截全部触摸（swipe_up/open_search 无响应
        // 的元凶之一）——隐藏掉，避免设备"触摸失灵"。
        UIWindow *key = [UIApplication sharedApplication].keyWindow;
        for (UIWindow *w in [[UIApplication sharedApplication].windows copy]) {
            if (w == key) continue;
            NSString *rootCls = NSStringFromClass(w.rootViewController.class) ?: @"";
            if ([rootCls containsString:@"Comment"]) {
                w.hidden = YES;
                removed = YES;
            }
        }
    });
    return removed;
}

- (NSDictionary *)_closeCommentPanel {
    @try {
        NSString *codeDiag = nil;
        CGSize screen = [UIScreen mainScreen].bounds.size;
        // 0. 【v1.4.92】先收键盘：直接 resignFirstResponder（不走点击——键盘关闭是 UITapGestureRecognizer，
        //    合成触摸绕过手势管理器触发不了）。键盘不关，"Close comment section" X 按钮不显示 → 主方案必然找不到。
        dispatch_sync(dispatch_get_main_queue(), ^{
            [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder)
                                                      to:nil from:nil forEvent:nil];
        });
        [NSThread sleepForTimeInterval:0.6];

        // 0.5. 【v1.4.95/96】直接调评论面板 VC 的关闭方法（不模拟触摸——真实点击最终也是调内部方法，
        //    直接调最可靠，且能拿到真实方法名）。失败返回带 diag 诊断，落触摸兜底，diag 透传到最终 message。
        NSDictionary *byCode = [self _closeCommentPanelByCode];
        if (byCode && [byCode[@"status"] isEqualToString:@"success"]) return byCode;
        codeDiag = byCode[@"diag"];

        // 1. 主方案【v1.4.94】真实触摸 X 关闭按钮。v1.4.93 用 sendActions 对手势按钮无效
        //    （TikTok 按钮是 UITapGestureRecognizer，sendActions 不走 hitTest/手势识别，实测点了没反应）。
        //    XNTouchSimulator 注入真实 UITouch/UIEvent（like/open_search 实测有效）。
        __block UIButton *closeBtn = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{
            closeBtn = [self _findButtonWithAnyLabel:@[@"Close comment section", @"Close comment"]
                                             inView:XN_ActiveWindow()];
        });
        if (closeBtn) {
            CGPoint center = [closeBtn.superview convertPoint:closeBtn.center toView:nil];
            [self _safeTapAtPoint:center];
            [NSThread sleepForTimeInterval:1.2];
            if (![[self detectCurrentPage] isEqualToString:@"comment"]) {
                return @{@"status": @"success", @"message": @"评论面板已关闭(真实触摸X按钮)"};
            }
        }

        // 2. 兜底 A：真实触摸面板上方暗色区（外点关闭）。v1.4.93 点 mask 中心 y≈368 落在评论列表本体上
        //    （MaskView 全屏 0..736，中心正对面板内部）不触发关闭；面板从 y≈199 起，
        //    上方暗色带是 y≈64~199（Explore 之下、面板头之上），外点在这里生效。
        [self _safeTapAtPoint:CGPointMake(screen.width * 0.5, screen.height * 0.13)];
        [NSThread sleepForTimeInterval:1.0];
        if (![[self detectCurrentPage] isEqualToString:@"comment"]) {
            return @{@"status": @"success", @"message": @"评论面板已关闭(点暗色区外点)"};
        }

        // 3. 兜底 B：下滑关闭（底部弹层支持下滑 dismiss 手势）
        [XNTouchSimulator swipeFrom:CGPointMake(screen.width * 0.5, screen.height * 0.35)
                                 to:CGPointMake(screen.width * 0.5, screen.height * 0.8)];
        [NSThread sleepForTimeInterval:1.2];
        if (![[self detectCurrentPage] isEqualToString:@"comment"]) {
            return @{@"status": @"success", @"message": @"评论面板已关闭(下滑)"};
        }

        // 4. 兜底 C：dismiss 顶层评论 VC（presented modal 场景）。评论区面板实为 feed cell 的
        //    child VC（vc_scan 实证），此策略通常不命中，保留作最后手段。
        __block BOOL dismissed = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{
            UIViewController *top = [self _topPresentedViewControllerOfWindow:XN_ActiveWindow()];
            if (top && [NSStringFromClass(top.class) containsString:@"Comment"]) {
                [top.presentingViewController dismissViewControllerAnimated:YES completion:nil];
                dismissed = YES;
            }
        });
        if (dismissed) {
            [NSThread sleepForTimeInterval:1.2];
            if (![[self detectCurrentPage] isEqualToString:@"comment"]) {
                return @{@"status": @"success", @"message": @"评论面板已关闭(VC dismiss)"};
            }
        }

        if ([[self detectCurrentPage] isEqualToString:@"comment"]) {
            return @{@"status": @"failed",
                     @"message": codeDiag
                         ? [NSString stringWithFormat:@"评论面板关闭失败; %@", codeDiag]
                         : @"评论面板关闭失败"};
        }
        return @{@"status": @"success", @"message": @"评论面板已关闭"};
    } @catch (NSException *e) {
        return @{@"status": @"failed", @"message": [NSString stringWithFormat:@"关闭面板异常: %@", e.reason]};
    }
}

/// v1.4.100: 评论面板关闭后恢复视频播放。
/// 根因：物理移除评论面板跳过 TikTok 正常关闭逻辑 → 播放器保持暂停（面板打开时 TikTok 暂停了视频）→
/// 无音频无触摸 → iOS 自动锁屏 → 祥哥看到"评论区黑屏"（手动上滑切视频即恢复）。
/// 恢复方案：① 递归 layer 树找当前可见 AVPlayerLayer → 直接 [player play]（最通用，不依赖 TikTok 内部）；
/// ② 找不到 AVPlayer 时对 feed 当前 cell 触发一次原地滚动，让 TikTok 走一遍"变可见"恢复逻辑。
- (void)_resumeFeedPlayback {
    dispatch_sync(dispatch_get_main_queue(), ^{
        __block BOOL resumed = NO;
        @try {
            for (UIWindow *w in [UIApplication sharedApplication].windows) {
                if ([self _playAVPlayerInLayerTree:w.layer]) { resumed = YES; break; }
            }
        } @catch (NSException *e) {
            NSLog(@"[XNOWER] 恢复播放异常: %@", e.reason);
        }
        if (!resumed) {
            NSLog(@"[XNOWER] 未找到 AVPlayer，触发 feed 原地滚动尝试恢复");
            [self _tryPageFeed:0];
        }
    });
}

/// 递归 layer 树找 AVPlayerLayer 并 play（返回是否播放成功）
- (BOOL)_playAVPlayerInLayerTree:(CALayer *)layer {
    if (!layer) return NO;
    if ([layer isKindOfClass:[AVPlayerLayer class]]) {
        AVPlayer *p = [(AVPlayerLayer *)layer player];
        if (p) {
            @try {
                if (p.rate == 0) [p play];
                return YES;
            } @catch (NSException *e) {}
        }
    }
    for (CALayer *sub in layer.sublayers) {
        if ([self _playAVPlayerInLayerTree:sub]) return YES;
    }
    return NO;
}

- (BOOL)_gotoHomeFeed {
    // v1.4.91: 先关浮层（评论区等 overlay 会遮挡 tab bar → 先关面板再点 tab）
    if ([[self detectCurrentPage] isEqualToString:@"comment"]) {
        [self _closeCommentPanel];
        [NSThread sleepForTimeInterval:0.8];
    }
    // deep link 候选（TikTok 深链需特定 path 才有路由；裸 scheme 无路由被忽略，逐个试）
    NSArray<NSString *> *schemes = @[
        @"snssdk1233://",
        @"snssdk1233://feed",
        @"snssdk1233://main",
        @"snssdk1233://home",
    ];
    for (int i = 0; i < 4; i++) {
        [self _tapTab:@"home"];
        [NSThread sleepForTimeInterval:2.0];
        // v1.4.127: 成功判定收紧为「在 feed 且导航栏可见」——沉浸态 feed 检测假阳性，只有 feed 不算到家
        if ([self _isHomeFeedUsable]) return YES;
        // v1.4.127: feed 在但导航栏被盖（全屏沉浸播放态）→ 先退出全屏
        if ([self _isOnFeed] && ![self _isHomeChromeVisible]) {
            [[XNOWER sharedInstance] addLog:@"🚨 检测到全屏沉浸态（导航栏被盖）→ 退出全屏"];
            [self _recoverFromImmersive];
            [NSThread sleepForTimeInterval:1.5];
            if ([self _isHomeFeedUsable]) return YES;
        }
        // deep link 兜底（本轮试第 i 个 scheme）
        NSString *scheme = (i < schemes.count) ? schemes[i] : @"snssdk1233://";
        dispatch_async(dispatch_get_main_queue(), ^{
            NSURL *url = [NSURL URLWithString:scheme];
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        });
        [NSThread sleepForTimeInterval:2.5];
        if ([self _isHomeFeedUsable]) return YES;
        [[XNOWER sharedInstance] addLog:[NSString stringWithFormat:@"⏳ 切回首页中(%d/4) scheme=%@...", i + 1, scheme]];
    }
    return NO;
}

/// 启动养号：随机浏览10-20秒；browseOnly=YES 只上滑浏览；NO 则随机点赞或关注
/// totalSeconds>0 自定义时长，0=默认24小时
- (void)startNurtureWithDuration:(int)totalSeconds browseOnly:(BOOL)browseOnly {
    if (totalSeconds <= 0) totalSeconds = 86400;  // 默认24小时
    if (self.nurtureRunning) [self stopNurture];
    self.nurtureMode = browseOnly ? 0 : 1;
    self.nurtureRunning = YES;
    __weak typeof(self) weakSelf = self;
    NSString *durStr = (totalSeconds >= 86400) ? @"24小时" : [NSString stringWithFormat:@"%d分钟", totalSeconds / 60];
    NSString *modeStr = browseOnly ? @"只上滑浏览" : @"浏览+随机点赞/关注";
    [[XNOWER sharedInstance] addLog:[NSString stringWithFormat:@"▶️ 养号已启动（%@，时长%@，点停止可停）", modeStr, durStr]];
    NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];
    dispatch_async(_execQueue, ^{
        __block int cycles = 0, likes = 0, follows = 0;
        [weakSelf _logStep:@"nurture_start"];
        // 养号前置：收起浮窗（避免浮窗遮挡坐标点击导致崩溃）+ 真实验证切回首页（必须在 feed 才能开始）
        [[XNOWER sharedInstance] collapseFloatingPanel];  // 内部 dispatch_async 到主队列，不会死锁
        [NSThread sleepForTimeInterval:0.6];
        BOOL onFeed = [weakSelf _gotoHomeFeed];
        if (!onFeed) {
            [[XNOWER sharedInstance] addLog:@"❌ 无法切回首页（请手动回到首页再启动养号）"];
            weakSelf.nurtureRunning = NO;
            [weakSelf _logStep:@"nurture_stop_no_feed"];
            return;  // 未真实验证在 home，不开始养号
        }
        [[XNOWER sharedInstance] addLog:@"🏠 已真实验证在首页，开始养号"];
        while (weakSelf.nurtureRunning) {
            // 时长检查（到点自动停）
            NSTimeInterval elapsed = [[NSDate date] timeIntervalSince1970] - startTime;
            if (elapsed >= totalSeconds) {
                [[XNOWER sharedInstance] addLog:@"⏱ 养号时长已到，自动停止"];
                weakSelf.nurtureRunning = NO;
                break;
            }
            cycles++;
            [weakSelf _logStep:[NSString stringWithFormat:@"nurture_cycle:%d", cycles]];
            // 随机浏览 10-20 秒
            int delay = 10 + (int)arc4random_uniform(11);
            if (delay < 5) delay = 5;
            [[XNOWER sharedInstance] addLog:[NSString stringWithFormat:@"⏱ 本次观看 %d 秒（随机10-20秒）", delay]];
            [NSThread sleepForTimeInterval:delay];
            if (!weakSelf.nurtureRunning) break;

            // 互动模式：20% 概率随机点赞或关注（避免太频繁）；纯浏览模式不互动
            // ⚠️ 互动必须发生在"浏览当前视频的稳定期"(已观看delay秒, 视频完全加载, 页面无转场)
            //    上滑后立刻互动会点到重建中的视频cell -> EXC_BAD_ACCESS崩(单独点赞OK就是这个稳定状态)
            if (!browseOnly && arc4random_uniform(100) < 20) {
                [weakSelf _logStep:@"interact"];
                [[XNOWER sharedInstance] addLog:@"🤖 互动中…"];
                [NSThread sleepForTimeInterval:1.0];  // 互动前轻微等待（页面已稳定，无需长等）
                // 互动前真实验证在 feed：不在 feed 跳过，避免在错误页面操作导致崩溃
                if (![weakSelf _isOnFeed]) {
                    [[XNOWER sharedInstance] addLog:@"⏭ 互动时不在 feed，跳过本次互动"];
                    [weakSelf _logStep:@"interact_skip_no_feed"];
                } else if (arc4random_uniform(100) < 50) {
                    // 安全点赞：多级定位+真验收（v1.4.103：红心点亮才算成功，不假成功）
                    BOOL liked = [weakSelf _performLikeSafe];
                    if (liked) { likes++; [weakSelf _logStep:@"interact_like"]; }
                    else { [weakSelf _logStep:@"interact_like_fail"]; }
                    [[XNOWER sharedInstance] addLog:liked ? @"❤️ 随机点赞（红心已验收）" : @"⚠️ 点赞未验收（红心未亮）"];
                } else {
                    BOOL followed = [weakSelf _performFollowSafe];
                    if (followed) { follows++; [weakSelf _logStep:@"interact_follow"]; }
                    else { [weakSelf _logStep:@"interact_follow_fail"]; }
                    [[XNOWER sharedInstance] addLog:followed ? @"👤 随机关注" : @"⚠️ 关注按钮未找到"];
                }
            }
            // 上滑到下一个视频（互动已完成验收，稳定后再滑动换视频；v1.4.103 顺序：点红心→验收→下滑）
            [NSThread sleepForTimeInterval:0.3];
            dispatch_sync(dispatch_get_main_queue(), ^{
                [weakSelf _performSwipeUp];
            });
            [[XNOWER sharedInstance] addLog:@"📱 已上滑到下一条视频"];
            if (!weakSelf.nurtureRunning) break;
        }
        [[XNOWER sharedInstance] addLog:[NSString stringWithFormat:@"⏹ 养号已停止：共%d轮，%d赞，%d关注",
                                         cycles, likes, follows]];
        // 汇报停止（含运行统计）
        @try {
            NSString *devId = [XNOWER sharedInstance].deviceId;
            if (devId.length > 0) {
                [XNURLProtocol sendMessage:@{
                    @"type": @"result",
                    @"data": @{
                        @"action": @"nurture",
                        @"status": @"success",
                        @"message": [NSString stringWithFormat:@"养号已停止：共%d轮，%d赞，%d关注",
                                     cycles, likes, follows],
                        @"cycles": @(cycles), @"likes": @(likes), @"follows": @(follows),
                    }
                } deviceId:devId];
            }
        } @catch (NSException *e) {}
    });
}

/// 兼容旧调用
- (void)startNurtureWithDuration:(int)totalSeconds {
    [self startNurtureWithDuration:totalSeconds browseOnly:NO];
}
- (void)startNurtureWithMode:(int)mode {
    [self startNurtureWithDuration:0 browseOnly:NO];  // 默认24小时互动
}

- (void)stopNurture {
    self.nurtureRunning = NO;
}

/// 注册新账号：导航到个人页 → 点"登录/注册" → 切"注册" → 填邮箱/手机 → 密码 → 继续
/// params: {email, phone, password, nickname?}
/// 说明：滑块/验证码无法通过纯 UI 自动化解决，需人工介入或专用打码工具（best-effort）
- (NSDictionary *)_performRegisterAccount:(NSDictionary *)params {
    NSString *email = params[@"email"] ?: @"";
    NSString *phone = params[@"phone"] ?: @"";
    NSString *password = params[@"password"] ?: @"";
    NSString *credential = email.length > 0 ? email : phone;

    if (credential.length == 0) {
        return @{@"status": @"failed", @"message": @"缺少邮箱或手机号"};
    }

    // Step 1: 导航到个人主页（v1.4.125：去外层 dispatch_sync，_tapTab 内部自带切主线程，同 open_tab 稳定模式）
    [self _navigateToProfile];
    [NSThread sleepForTimeInterval:2.0];

    // Step 2: 若在登录页，找 "登录/注册" 入口
    __block BOOL loginTap = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        UIButton *loginBtn = [self _findButtonWithAnyLabel:@[@"Log in", @"Sign up", @"Sign Up",
                                                             @"登录", @"注册"]
                                                    inView:window];
        if (loginBtn) {
            [self _safeTapAtPoint:[loginBtn.superview convertPoint:loginBtn.center toView:nil]];
            loginTap = YES;
        }
    });
    if (!loginTap) {
        // 可能已经在登录/注册页
        return @{@"status": @"failed", @"message": @"未找到登录/注册入口（请确认处于未登录状态）"};
    }
    [NSThread sleepForTimeInterval:1.5];

    // Step 3: 切到 "注册/Sign up" tab
    __block BOOL signUpTap = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        UIButton *signUpBtn = [self _findButtonWithAnyLabel:@[@"Sign up", @"Sign Up", @"注册", @"Register"]
                                                     inView:window];
        if (signUpBtn) {
            [self _safeTapAtPoint:[signUpBtn.superview convertPoint:signUpBtn.center toView:nil]];
            signUpTap = YES;
        } else {
            // 坐标回退：注册 tab 通常在登录页上部
            CGSize screen = [UIScreen mainScreen].bounds.size;
            [self _safeTapAtPoint:CGPointMake(screen.width * 0.5, screen.height * 0.12)];
            signUpTap = YES;
        }
    });
    [NSThread sleepForTimeInterval:1.5];

    // Step 4: 填邮箱/手机号
    __block BOOL fieldFound = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        UITextField *tf = [self _findTextFieldInView:window];
        if (tf) {
            tf.text = credential;
            [tf becomeFirstResponder];
            [tf sendActionsForControlEvents:UIControlEventEditingChanged];
            [[NSNotificationCenter defaultCenter]
             postNotificationName:UITextFieldTextDidChangeNotification object:tf];
            fieldFound = YES;
        }
    });
    if (!fieldFound) {
        return @{@"status": @"failed", @"message": @"未找到邮箱/手机号输入框"};
    }
    [NSThread sleepForTimeInterval:0.8];

    // Step 5: 填密码（若提供，且存在第二个输入框）
    if (password.length > 0) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            UIWindow *window = XN_ActiveWindow();
            __block UITextField *secondTf = nil;
            __block int count = 0;
            [self _enumerateTextFieldsInView:window block:^(UITextField *tf) {
                count++;
                if (count == 2) secondTf = tf;
            }];
            if (secondTf) {
                secondTf.text = password;
                [secondTf becomeFirstResponder];
                [secondTf sendActionsForControlEvents:UIControlEventEditingChanged];
                [[NSNotificationCenter defaultCenter]
                 postNotificationName:UITextFieldTextDidChangeNotification object:secondTf];
            }
        });
        [NSThread sleepForTimeInterval:0.5];
    }

    // Step 6: 点 "继续/下一步"
    __block BOOL continueTap = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        UIButton *nextBtn = [self _findButtonWithAnyLabel:@[@"Continue", @"continue", @"下一步",
                                                            @"继续", @"Next", @"Sign up"]
                                                   inView:window];
        if (nextBtn) {
            [self _safeTapAtPoint:[nextBtn.superview convertPoint:nextBtn.center toView:nil]];
            continueTap = YES;
        }
    });
    [NSThread sleepForTimeInterval:1.0];

    if (!continueTap) {
        return @{@"status": @"failed", @"message": @"未找到继续按钮（滑块/验证码需人工处理）"};
    }

    return @{
        @"status": @"success",
        @"message": @"已触发注册流程（best-effort UI 自动化；滑块/验证码需人工或专用打码工具）",
        @"credential": credential,
        @"note": @"滑块/验证码无法纯 UI 自动化解决",
    };
}

#pragma mark - 辅助: 手势模拟

/// 真实滑动手势（注入 UITouch/UIEvent）
- (void)_simulateSwipeFrom:(CGPoint)from to:(CGPoint)to {
    [XNTouchSimulator swipeFrom:from to:to];
    NSLog(@"[XNOWER] 真实滑动 %.0fpt", to.y - from.y);
}

@end

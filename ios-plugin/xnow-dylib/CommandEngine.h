// CommandEngine.h
// XNOW 指令执行引擎 - 解析并执行后端下发的指令

#import <Foundation/Foundation.h>

typedef void(^CommandCompletion)(NSDictionary *result);

/// 支持的指令类型
typedef NS_ENUM(NSInteger, CommandAction) {
    CommandActionUnknown = 0,
    CommandActionScrollDown,
    CommandActionScrollUp,
    CommandActionLike,
    CommandActionFollow,
    CommandActionComment,
    CommandActionCollect,
    CommandActionScreenshot,
    CommandActionOpenProfile,
    CommandActionCollectFans,
    CommandActionCollectVideos,
    CommandActionCollectComments,
    CommandActionCollectLiveUsers,
    CommandActionCollectLikes,       // 采集直播间点赞用户
    CommandActionBatchLike,
    CommandActionBatchFollow,
    CommandActionBatchComment,

    // 账号管理 (Phase 1)
    CommandActionGetAccountInfo,
    CommandActionSwitchAccount,
    CommandActionReportAccount,

    // 智能任务 (Phase 2)
    CommandActionSmartBrowse,
    CommandActionCheckHealth,

    // 导航 (Phase 3)
    CommandActionGoBack,
    CommandActionGoHome,
    CommandActionOpenTab,       // params: tab = home/discover/inbox/profile
    CommandActionOpenSearch,
    CommandActionSearchKeyword, // params: keyword
    CommandActionOpenUser,      // params: uid / unique_id
    CommandActionOpenVideo,     // params: aweme_id

    // 视频操作 (Phase 3)
    CommandActionRefresh,       // 下拉刷新
    CommandActionShare,         // 分享当前视频
    CommandActionSaveVideo,     // 保存视频

    // 账号 (Phase 3)
    CommandActionLogout,        // 退出登录

    // 修改资料 (Phase 4)
    CommandActionEditProfile,   // params: nickname/signature/link

    // 自动发视频 (Phase 5)
    CommandActionPostVideo,     // params: title/video_url（best-effort UI 自动化）

    // 自动私信 (Phase 6)
    CommandActionSendDm,        // params: target/content（best-effort UI 自动化）
    CommandActionSendCard,      // params: target?（发名片，best-effort）
    CommandActionShareLive,     // params: target?（分享直播间，best-effort）

    // 批量注册 + 自动养号 (Feature 5)
    CommandActionNurtureTick,       // 养号心跳：一次短随机浏览会话（params: min_scrolls/max_scrolls/like_probability/follow_probability/comment_probability/browse_minutes）
    CommandActionNurtureStop,       // 停止养号（tick 为一次性指令，停止是隐式的）
    CommandActionRegisterAccount,   // 批量注册账号（params: email/phone/password，best-effort UI 自动化）

    // 调试诊断 (v1.4.17)
    CommandActionUIScan,            // 扫描当前 UI 结构上报（类型/位置/无障碍标识/状态）
    CommandActionTap,               // params: x/y —— 坐标点击（v1.4.124 远程调试用）

    // 账号管理 (v1.4.22)
    CommandActionBackupAccount,     // 备份当前账号登录态快照

    // 环境伪装 / 切换国家 (v1.4.53)
    CommandActionSetCountry,        // params: country（目标国家，如"美国"）；把 region/时区/语言/MCC 伪装成目标国
    CommandActionGetCountry,        // 读取当前伪装环境

    // 评论点赞 (v1.4.54) — PPT 模块4 曝光玩法核心
    CommandActionLikeComments,      // 打开评论面板，逐条点赞评论（params: count）

    // 进直播间 (v1.4.54) — PPT 模块3 直播间采集前置
    CommandActionOpenLive,          // 打开主播主页并进其直播间（params: uid/anchor_id）

    // 回关/指定关注 (v1.4.55) — PPT 模块8 全自动回关基础
    CommandActionFollowUser,        // 打开指定用户主页并关注（params: uid/target；回关任务由引擎逐粉丝下发）

    // 指定视频评论 (v1.4.55) — PPT 模块6
    CommandActionCommentVideo,      // 打开指定视频并评论（params: aweme_id/video_id, text；任务引擎逐视频下发）

    // 环境诊断 (v1.4.56) — 上报当前伪装环境 + 实际改写过的请求参数（验证 set_country 生效）
    CommandActionEnvDiag,

    // VC 诊断 (v1.4.61) — 上报 ViewController 链 + tab 控制器类名（定位 TikTok 首页切换入口）
    CommandActionVCScan,

    // 登录态诊断 (v1.4.116) — 上报 NSUserDefaults key 名 + cookies name/domain（不含值，隐私安全）
    CommandActionDumpLogin,

    // 粉丝列表自动关注 (v1.4.85) — 在粉丝/关注列表循环点右侧 Follow 按钮 → 上滑 → 再点，单次上限200自动停
    CommandActionAutoFollowList,

    // 关闭浮层面板 (v1.4.91) — 关闭评论区等 overlay（评论面板打开后无关闭机制，会遮挡 tab bar 导致 go_home 失效、设备困死）
    CommandActionCloseOverlay,

    // 停止采集 (v1.4.108) — F21/F26 修复：置 isCollectingData=NO，让采集循环（fans/videos/comments/likes）尽快退出
    CommandActionStopCollect,

    // 无障碍点击 (v1.4.134) — params: acc_id/label/x,y —— 按 accessibilityActivate 触发控件动作，
    // 走 VoiceOver 官方点按路径，完全绕过触摸管线（触摸盲区三层全拒后新方向）
    CommandActionAccClick,

    // 网络层点赞 (v1.4.135) — 交互选 C（纯网络层）：不复用触摸，直接构造 TikTok 点赞请求
    // 走 app 自己的会话/签名发 HTTP（params: aweme_id 可选，默认取当前 feed 第一条视频）
    CommandActionNetLike,

    // 网络路径探针 (v1.4.136) — 上报 NSURLProtocol 注册状态 / 命中计数 / 最近 URL / headers 捕获状态，
    // 一锤定音 TikTok 网络请求走哪条路（决定纯网络层会话材料来源）
    CommandActionNetDiag,

    // net_sniff (v1.4.138) — N 秒时间盒抓包：不管域名/层，记录期间所有观察到的请求 host+URL，
    // 摸清 TikTok 真实网络路径（params: seconds 默认 8）
    CommandActionNetSniff,
};

@interface CommandEngine : NSObject

/// 执行单条指令
- (void)executeCommand:(NSDictionary *)command completion:(CommandCompletion)completion;

/// 字符串转指令类型
- (CommandAction)actionFromString:(NSString *)actionString;

/// 当前 TikTok 页面类型（未知/推荐/关注/个人/视频详情等）
@property (nonatomic, copy) NSString *currentPage;

/// 检测当前页面类型，返回: home(推荐feed) / comment(评论区) / profile(个人主页) / live(直播间) / inbox(私信) / other
- (NSString *)detectCurrentPage;

/// 主动检测当前账号：导航个人页→等 /user/ 网络捕获→UI扫描兜底，返回账号资料字典（aweme_id/nickname/unique_id/头像等）
/// 供 get_account_info 与 backup_account（备份前资料为空时）共用
- (NSDictionary *)detectCurrentAccountFlow;

// ===== 连续养号（默认24小时，直到停止）=====
/// 启动养号：随机浏览10-20秒；browseOnly=YES 只上滑浏览，NO 随机点赞/关注；totalSeconds>0 自定义时长，0=24小时
- (void)startNurtureWithDuration:(int)totalSeconds browseOnly:(BOOL)browseOnly;
/// 兼容旧调用
- (void)startNurtureWithDuration:(int)totalSeconds;
- (void)startNurtureWithMode:(int)mode;
/// 停止连续养号
- (void)stopNurture;
/// 是否正在养号
@property (nonatomic, readonly) BOOL isNurtureRunning;
/// 当前养号模式（1/2）
@property (nonatomic, readonly) int nurtureMode;

@end

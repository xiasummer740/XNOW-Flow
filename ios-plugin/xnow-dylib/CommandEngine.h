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

    // 账号管理 (v1.4.22)
    CommandActionBackupAccount,     // 备份当前账号登录态快照
};

@interface CommandEngine : NSObject

/// 执行单条指令
- (void)executeCommand:(NSDictionary *)command completion:(CommandCompletion)completion;

/// 字符串转指令类型
- (CommandAction)actionFromString:(NSString *)actionString;

/// 当前 TikTok 页面类型（未知/推荐/关注/个人/视频详情等）
@property (nonatomic, copy) NSString *currentPage;

// ===== 连续养号（单模式，默认24小时，直到停止）=====
/// 启动养号：随机浏览10-20秒 + 随机点赞或关注；totalSeconds>0 自定义时长，0=默认24小时
- (void)startNurtureWithDuration:(int)totalSeconds;
/// 兼容旧调用
- (void)startNurtureWithMode:(int)mode;
/// 停止连续养号
- (void)stopNurture;
/// 是否正在养号
@property (nonatomic, readonly) BOOL isNurtureRunning;
/// 当前养号模式（1/2）
@property (nonatomic, readonly) int nurtureMode;

@end

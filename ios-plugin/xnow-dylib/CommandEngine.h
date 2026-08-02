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
};

@interface CommandEngine : NSObject

/// 执行单条指令
- (void)executeCommand:(NSDictionary *)command completion:(CommandCompletion)completion;

/// 字符串转指令类型
- (CommandAction)actionFromString:(NSString *)actionString;

/// 当前 TikTok 页面类型（未知/推荐/关注/个人/视频详情等）
@property (nonatomic, copy) NSString *currentPage;

@end

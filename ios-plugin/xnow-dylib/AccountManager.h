// AccountManager.h
// XNOW 账号管理器 — 检测、缓存、上报当前 TikTok 账号
//
// 检测策略（3层递进）:
//   1. 网络拦截: 从 TikTok API 响应的 user profile 数据提取
//   2. UI 解析: 遍历当前视图层找昵称标签（后备）
//   3. 登录状态: 检测登录按钮判断是否已登录

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AccountManager : NSObject

@property (class, readonly) AccountManager *sharedManager;

/// 当前缓存的账号信息:
/// {aweme_id, nickname, unique_id, followers, following_count, digg_count,
///  video_count, signature, avatar_url, health_score, status}
@property (nonatomic, readonly, nullable) NSDictionary *currentAccount;
@property (nonatomic, readonly) BOOL isLoggedIn;

/// 从 TikTok API 响应中提取账号数据（由 TikTokHooks 调用）
- (void)onTikTokAPIResponse:(NSDictionary *)json url:(NSString *)url;

/// 主动检测当前账号（遍历 UI，耗时操作）
- (void)detectCurrentAccountWithCompletion:(void(^)(NSDictionary *_Nullable account))completion;

/// 检测是否在登录页面
- (BOOL)detectLoginPage;

/// 清除当前缓存（退出登录后调用）
- (void)clearAccount;

/// 上报当前账号到 WebSocket
- (void)reportCurrentAccount;

/// 开始定期检测（默认每 60 秒）
- (void)startPeriodicDetection:(NSTimeInterval)interval;
- (void)stopPeriodicDetection;

@end

NS_ASSUME_NONNULL_END

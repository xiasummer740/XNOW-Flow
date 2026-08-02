// AccountSwitcher.h
// XNOW 账号切换引擎
//
// 策略（3 层递进）:
//   1. Token 注入: 直接写入 TikTok 的 NSUserDefaults/Keychain session key（秒切）
//   2. Cookies 注入: 通过 NSHTTPCookieStorage 注入 session cookies（重启后生效）
//   3. UI 自动化: 退出登录 → 输入密码 → 登录（后备，需验证码时弹通知）

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^SwitchCompletion)(BOOL success, NSDictionary *_Nullable result);

@interface AccountSwitcher : NSObject

@property (class, readonly) AccountSwitcher *sharedSwitcher;

/// 切换到指定账号
/// @param accountId 账号 ID（在 AccountPool 中）
/// @param completion 完成回调（result 含 status/message）
- (void)switchToAccount:(NSInteger)accountId completion:(nullable SwitchCompletion)completion;

/// 批量登录（按顺序逐个登录）
/// @param accountIds 账号 ID 数组
/// @param completion 每登录完一个回调一次，全部完成后 final 为 YES
- (void)batchLogin:(NSArray<NSNumber *> *)accountIds
        completion:(void(^)(NSInteger done, NSInteger total, BOOL final, NSDictionary *_Nullable result))completion;

/// 退出当前账号（清除 TikTok session 但不删除池中账号）
- (void)logoutCurrentAccount:(nullable SwitchCompletion)completion;

/// 验证当前 TikTok 是否已登录指定账号
/// @return @{isLoggedIn, accountId?, nickname?}
- (NSDictionary *)verifyCurrentLogin;

/// 备份当前登录账号的登录态快照（浮窗「备份」按钮）
/// @return 备份成功的账号 ID；无当前账号返回 0
- (NSInteger)backupCurrentAccount;

/// 新增账号：清空当前登录态（无痕），让用户登录全新账号
- (void)prepareNewAccount;

/// 重启 TikTok 进程（注入登录态生效）
- (void)restartApp;

@end

NS_ASSUME_NONNULL_END

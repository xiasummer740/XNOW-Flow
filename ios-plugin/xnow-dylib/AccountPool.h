// AccountPool.h
// XNOW 账号池 — 在设备本地管理多账号登录凭证
//
// 存储结构（NSUserDefaults）：
//   XN_AccountPool → JSON array:
//   [{id, nickname, aweme_number, password, cookies, token, status, last_used}]

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 账号在设备上的本地状态
typedef NS_ENUM(NSInteger, AccountStatus) {
    AccountStatusIdle = 0,       // 已存储，未使用
    AccountStatusLoggingIn,      // 登录中
    AccountStatusActive,         // 当前已登录
    AccountStatusFailed,         // 登录失败
    AccountStatusRiskControl,    // 风控
};

@interface AccountPool : NSObject

@property (class, readonly) AccountPool *sharedPool;

/// 所有账号
@property (nonatomic, readonly) NSArray<NSDictionary *> *allAccounts;

/// 当前活跃账号
@property (nonatomic, readonly, nullable) NSDictionary *activeAccount;

/// 账号数量
@property (nonatomic, readonly) NSInteger count;

// ======== 管理 ========

/// 从后端批量替换账号池（接收到 batch_login 指令时调用）
- (void)syncAccounts:(NSArray<NSDictionary *> *)accounts;

/// 添加或更新单个账号
- (void)upsertAccount:(NSDictionary *)account;

/// 新建本地账号（自动分配 id 并标记为活跃），返回新 id；失败返回 0
- (NSInteger)addLocalAccount:(NSDictionary *)account;

/// 删除账号
- (void)removeAccountWithId:(NSInteger)accountId;

/// 清空
- (void)clearAll;

// ======== 查询 ========

/// 按 ID 查找
- (nullable NSDictionary *)accountWithId:(NSInteger)accountId;

/// 按 TK号查找
- (nullable NSDictionary *)accountWithAwemeNumber:(NSString *)number;

/// 获取账号的登录凭证（解密后）
- (nullable NSDictionary *)credentialsForAccountId:(NSInteger)accountId;

// ======== 状态 ========

/// 标记为当前活跃
- (void)markActive:(NSInteger)accountId;

/// 清除当前活跃标记（不删池中账号）
- (void)clearActiveAccount;

/// 更新账号状态
- (void)updateStatus:(NSInteger)accountId status:(AccountStatus)status;

/// 是否有凭证可以自动登录
- (BOOL)hasCredentials:(NSInteger)accountId;

@end

NS_ASSUME_NONNULL_END

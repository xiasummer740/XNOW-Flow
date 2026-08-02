// AccountSnapshotter.h
// XNOW 账号登录态快照引擎
//
// 核心原理：每账号独立快照文件，切换时保存/恢复登录态。
// 捕获内容（全量，不依赖特定 key）：
//   1. NSUserDefaults 全量 dictionaryRepresentation（含 TikTok session/cookies/device 状态）
//   2. Keychain 所有 GenericPassword 条目（含 com.zhiliaoapp.musically）
//   3. NSHTTPCookieStorage 中 .tiktok.com 域所有 cookie
//
// 恢复 = 清空当前登录态 → 写入快照 → 调用方负责重启进程

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AccountSnapshotter : NSObject

@property (class, readonly) AccountSnapshotter *sharedSnapshotter;

/// 捕获当前登录态存入账号 accId 的快照文件
- (BOOL)saveSnapshotForAccount:(NSInteger)accId;

/// 读取账号 accId 的快照（nil = 无快照）
- (nullable NSDictionary *)loadSnapshotForAccount:(NSInteger)accId;

/// 恢复账号 accId 的登录态（先清空当前，再写入快照数据）
/// @return 是否有快照可恢复
- (BOOL)restoreSnapshotForAccount:(NSInteger)accId;

/// 清空当前登录态（无痕）：删 NSUserDefaults 相关 key + Keychain + cookies
- (void)clearCurrentState;

/// 删除所有账号快照
- (void)clearAllSnapshots;

/// 是否有账号 accId 的快照
- (BOOL)hasSnapshotForAccount:(NSInteger)accId;

/// 获取当前 NSUserDefaults 全量（调试用）
- (NSDictionary *)currentUserDefaultsDump;

@end

NS_ASSUME_NONNULL_END

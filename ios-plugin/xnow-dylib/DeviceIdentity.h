// DeviceIdentity.h
// XNOW 设备唯一标识 — Keychain 持久化 UUID（卸载不丢）
//
// 用途：授权卡密 / 设备身份的唯一稳定标识。
// 相比 device_id（会随编号/重装变化）和 IDFV（删除所有同开发者App后重装会变），
// Keychain 中持久化的 UUID 在 App 卸载重装后仍保持不变，是可靠的设备标识。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DeviceIdentity : NSObject

/// 获取设备唯一标识 UID（首次生成并存 Keychain，之后恒返回同一值）
+ (NSString *)deviceUID;

@end

NS_ASSUME_NONNULL_END

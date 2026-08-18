// DeviceIdentity.h
// XNOW 设备唯一标识 — Keychain 持久化 UUID
//
// ⚠️ 已弃用（v1.4.114）：注入 TikTok 场景实测 Keychain 在重装/重签后被清空，
// UID 三次重装三次变（451D→68D9→F8C0），用它做授权标识导致卡密失配。
// 授权/激活/机器码已统一改用 deviceId（XNOWER.deviceId = iphone_<IDFV前8位>，重装稳定）。
// 本类暂留：待 ISSUES #49「硬件 UDID(IOPlatformUUID) 能否拿到」拍板后复用或删除。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DeviceIdentity : NSObject

/// 获取设备唯一标识 UID（首次生成并存 Keychain，之后恒返回同一值）
+ (NSString *)deviceUID;

@end

NS_ASSUME_NONNULL_END

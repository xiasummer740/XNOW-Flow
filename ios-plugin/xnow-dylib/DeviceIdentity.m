// DeviceIdentity.m
// XNOW 设备唯一标识实现 — Keychain 持久化 UUID

#import "DeviceIdentity.h"
#import <Security/Security.h>

#define DI_LOG(fmt, ...) NSLog(@"[XNOWER][DeviceID] " fmt, ##__VA_ARGS__)

// Keychain 条目标识（同一设备卸载重装后 Keychain 数据保留）
static NSString *const kUIDKeychainService = @"com.xnow.device.uid";
static NSString *const kUIDKeychainAccount = @"device_uid";
// NSUserDefaults fallback key（Keychain 读取失败时兜底）
static NSString *const kUIDDefaultsKey = @"XN_DeviceUID";

@implementation DeviceIdentity

static NSString *gCachedUID = nil;

+ (NSString *)deviceUID {
    // 内存缓存（进程内只算一次）
    if (gCachedUID.length > 0) {
        return gCachedUID;
    }

    // 1. 优先读 Keychain（卸载重装后仍保留）
    NSString *uid = [self _readKeychainUID];
    if (uid.length == 0) {
        // 2. Keychain 没有 → 读 NSUserDefaults fallback
        uid = [[NSUserDefaults standardUserDefaults] stringForKey:kUIDDefaultsKey];
    }

    if (uid.length == 0) {
        // 3. 都没有 → 生成新 UUID 并双写（Keychain + UserDefaults）
        uid = [[NSUUID UUID] UUIDString];
        [self _writeKeychainUID:uid];
        [[NSUserDefaults standardUserDefaults] setObject:uid forKey:kUIDDefaultsKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        DI_LOG(@"✅ 已生成新设备 UID: %@", uid);
    } else if (![[NSUserDefaults standardUserDefaults] stringForKey:kUIDDefaultsKey]) {
        // 4. 只有 Keychain 有值 → 同步到 UserDefaults 兜底
        [[NSUserDefaults standardUserDefaults] setObject:uid forKey:kUIDDefaultsKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }

    gCachedUID = uid;
    return uid;
}

#pragma mark - Keychain 读写

+ (NSString *)_readKeychainUID {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kUIDKeychainService,
        (__bridge id)kSecAttrAccount: kUIDKeychainAccount,
        (__bridge id)kSecReturnData: (__bridge id)kSecReturnData,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status == errSecSuccess && result) {
        NSData *data = (__bridge_transfer NSData *)result;
        NSString *uid = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (uid.length > 0) {
            return uid;
        }
    }
    return nil;
}

+ (BOOL)_writeKeychainUID:(NSString *)uid {
    NSData *data = [uid dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kUIDKeychainService,
        (__bridge id)kSecAttrAccount: kUIDKeychainAccount,
    };
    // 先删旧的（幂等）
    SecItemDelete((__bridge CFDictionaryRef)query);

    NSDictionary *add = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kUIDKeychainService,
        (__bridge id)kSecAttrAccount: kUIDKeychainAccount,
        (__bridge id)kSecValueData: data,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlock,
    };
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    return status == errSecSuccess;
}

@end

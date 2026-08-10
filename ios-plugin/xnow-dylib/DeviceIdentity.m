// DeviceIdentity.m
// XNOW 设备唯一标识实现 — 硬件 UDID(IOPlatformUUID, 永不变) > Keychain > NSUUID
// 祥哥要求: 卡密绑定不变标识, 重装/清缓存不失效

#import "DeviceIdentity.h"
#import <Security/Security.h>
#import <IOKit/IOKitLib.h>

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

    NSString *uid = nil;

    // 1. 优先硬件 UDID（IOPlatformUUID，永不变，重装/清缓存/清Keychain都不变）← 祥哥要求
    uid = [self _hardwareUDID];
    if (uid.length > 0) {
        DI_LOG(@"✅ 使用硬件 UDID: %@", uid);
        gCachedUID = uid;
        return uid;
    }

    // 2. 硬件拿不到 → 读 Keychain（卸载重装后通常保留）
    uid = [self _readKeychainUID];
    if (uid.length == 0) {
        // 3. Keychain 没有 → 读 NSUserDefaults fallback
        uid = [[NSUserDefaults standardUserDefaults] stringForKey:kUIDDefaultsKey];
    }

    if (uid.length == 0) {
        // 4. 都没有 → 生成新 UUID 并双写（Keychain + UserDefaults）
        uid = [[NSUUID UUID] UUIDString];
        [self _writeKeychainUID:uid];
        [[NSUserDefaults standardUserDefaults] setObject:uid forKey:kUIDDefaultsKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        DI_LOG(@"✅ 已生成新设备 UID: %@", uid);
    } else if (![[NSUserDefaults standardUserDefaults] stringForKey:kUIDDefaultsKey]) {
        // 5. 只有 Keychain 有值 → 同步到 UserDefaults 兜底
        [[NSUserDefaults standardUserDefaults] setObject:uid forKey:kUIDDefaultsKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }

    gCachedUID = uid;
    return uid;
}

/// 硬件 UDID：IOPlatformUUID（IOKit，设备硬件级唯一标识，永不变）
/// iOS 沙盒 App 可能拿不到（需非沙盒/注入环境），拿不到返回 nil 回退 Keychain
+ (NSString *)_hardwareUDID {
    static NSString *hw = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        @try {
            // kIOMasterPortDefault 在 iOS 17 SDK 标记 unavailable，用 MACH_PORT_NULL(0) 等价绕过编译
            io_service_t svc = IOServiceGetMatchingService(MACH_PORT_NULL,
                                                          IOServiceMatching("IOPlatformExpertDevice"));
            if (svc) {
                CFTypeRef prop = IORegistryEntryCreateCFProperty(svc, CFSTR("IOPlatformUUID"),
                                                                 kCFAllocatorDefault, 0);
                IOObjectRelease(svc);
                if (prop && CFGetTypeID(prop) == CFStringGetTypeID()) {
                    hw = (__bridge_transfer NSString *)prop;
                } else if (prop) {
                    CFRelease(prop);
                }
            }
        } @catch (NSException *e) {
            DI_LOG(@"硬件UDID获取失败: %@", e.reason);
        }
        DI_LOG(@"IOPlatformUUID: %@", hw ?: @"(不可用, 沙盒限制)");
    });
    return hw;
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

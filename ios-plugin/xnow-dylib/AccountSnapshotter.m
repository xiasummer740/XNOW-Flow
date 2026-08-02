// AccountSnapshotter.m
// XNOW 账号登录态快照引擎实现

#import "AccountSnapshotter.h"
#import <UIKit/UIKit.h>
#import <Security/Security.h>

#define SNAP_LOG(fmt, ...) NSLog(@"[XNOWER][Snapshot] " fmt, ##__VA_ARGS__)

// TikTok Keychain 服务名（逆向识别）
static NSString *const kTKKeychainService = @"com.zhiliaoapp.musically";

@interface AccountSnapshotter ()
@property (nonatomic, strong) NSString *snapshotDir;
@end

@implementation AccountSnapshotter

static AccountSnapshotter *gShared = nil;

+ (AccountSnapshotter *)sharedSnapshotter {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gShared = [[self alloc] init];
    });
    return gShared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // Library/XNOW/snapshots/
        NSString *lib = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
        _snapshotDir = [lib stringByAppendingPathComponent:@"XNOW/snapshots"];
        [[NSFileManager defaultManager] createDirectoryAtPath:_snapshotDir
                                  withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return self;
}

#pragma mark - 快照文件路径

- (NSString *)_filePathForAccount:(NSInteger)accId {
    return [_snapshotDir stringByAppendingPathComponent:
            [NSString stringWithFormat:@"acc_%ld.plist", (long)accId]];
}

#pragma mark - 捕获当前登录态

/// 捕获 NSUserDefaults 全量
- (NSDictionary *)_captureUserDefaults {
    return [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
}

/// 捕获 Keychain 所有 GenericPassword 条目
- (NSArray *)_captureKeychain {
    NSMutableArray *items = [NSMutableArray array];
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
        (__bridge id)kSecReturnAttributes: (__bridge id)kSecReturnAttributes,
        (__bridge id)kSecReturnData: (__bridge id)kSecReturnData,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlock,
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status == errSecSuccess && result) {
        NSArray *arr = (__bridge NSArray *)result;
        for (NSDictionary *item in arr) {
            // 只保留可序列化的字段，跳过私有类型
            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            for (NSString *key in item) {
                id val = item[key];
                if ([val isKindOfClass:[NSString class]] || [val isKindOfClass:[NSData class]] || [val isKindOfClass:[NSNumber class]]) {
                    entry[key] = val;
                }
            }
            [items addObject:entry];
        }
        CFRelease(result);
        SNAP_LOG(@"捕获 Keychain %lu 条", (unsigned long)items.count);
    } else {
        SNAP_LOG(@"Keychain 捕获失败 status=%d", (int)status);
    }
    return items;
}

/// 捕获 .tiktok.com 域所有 cookies
- (NSArray *)_captureCookies {
    NSMutableArray *items = [NSMutableArray array];
    NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in storage.cookies) {
        NSString *domain = cookie.domain.lowercaseString;
        if ([domain containsString:@"tiktok"] || [domain containsString:@"byteoversea"]) {
            NSDictionary *props = @{
                @"name": cookie.name ?: @"",
                @"value": cookie.value ?: @"",
                @"domain": cookie.domain ?: @"",
                @"path": cookie.path ?: @"/",
                @"secure": @(cookie.secure),
                @"httpOnly": @(cookie.isHTTPOnly),
            };
            [items addObject:props];
        }
    }
    SNAP_LOG(@"捕获 cookies %lu 条", (unsigned long)items.count);
    return items;
}

- (BOOL)saveSnapshotForAccount:(NSInteger)accId {
    @try {
        NSDictionary *snapshot = @{
            @"version": @(1),
            @"user_defaults": [self _captureUserDefaults],
            @"keychain": [self _captureKeychain],
            @"cookies": [self _captureCookies],
            @"saved_at": [NSDate date].description,
        };
        BOOL ok = [snapshot writeToFile:[self _filePathForAccount:accId] atomically:YES];
        SNAP_LOG(@"账号 %ld 快照已保存%@", (long)accId, ok ? @"" : @"(失败)");
        return ok;
    } @catch (NSException *e) {
        SNAP_LOG(@"快照保存异常: %@", e.reason);
        return NO;
    }
}

#pragma mark - 读取快照

- (NSDictionary *)loadSnapshotForAccount:(NSInteger)accId {
    NSString *path = [self _filePathForAccount:accId];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    NSDictionary *snap = [NSDictionary dictionaryWithContentsOfFile:path];
    return snap;
}

- (BOOL)hasSnapshotForAccount:(NSInteger)accId {
    return [[NSFileManager defaultManager] fileExistsAtPath:[self _filePathForAccount:accId]];
}

#pragma mark - 恢复登录态

- (BOOL)restoreSnapshotForAccount:(NSInteger)accId {
    NSDictionary *snap = [self loadSnapshotForAccount:accId];
    if (!snap) return NO;

    // 1. 清空当前
    [self clearCurrentState];

    // 2. 恢复 NSUserDefaults
    NSDictionary *ud = snap[@"user_defaults"];
    if ([ud isKindOfClass:[NSDictionary class]]) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        // 先写入快照里的 key
        for (NSString *key in ud) {
            [defaults setObject:ud[key] forKey:key];
        }
        [defaults synchronize];
        SNAP_LOG(@"账号 %ld 恢复 NSUserDefaults %lu 个 key", (long)accId, (unsigned long)ud.count);
    }

    // 3. 恢复 Keychain
    NSArray *kc = snap[@"keychain"];
    if ([kc isKindOfClass:[NSArray class]]) {
        for (NSDictionary *entry in kc) {
            [self _restoreKeychainEntry:entry];
        }
        SNAP_LOG(@"账号 %ld 恢复 Keychain %lu 条", (long)accId, (unsigned long)kc.count);
    }

    // 4. 恢复 cookies
    NSArray *ck = snap[@"cookies"];
    if ([ck isKindOfClass:[NSArray class]]) {
        [self _restoreCookies:ck];
        SNAP_LOG(@"账号 %ld 恢复 cookies %lu 条", (long)accId, (unsigned long)ck.count);
    }

    return YES;
}

/// 恢复单条 Keychain（先删同 key 再新增）
- (void)_restoreKeychainEntry:(NSDictionary *)entry {
    NSString *account = entry[(__bridge NSString *)kSecAttrAccount];
    NSString *service = entry[(__bridge NSString *)kSecAttrService];
    NSData *valueData = entry[(__bridge NSString *)kSecValueData];

    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    query[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
    if (service) query[(__bridge id)kSecAttrService] = service;
    if (account) query[(__bridge id)kSecAttrAccount] = account;
    if (query.count > 1) {
        SecItemDelete((__bridge CFDictionaryRef)query);
    }

    if (valueData) {
        NSMutableDictionary *add = [NSMutableDictionary dictionary];
        add[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
        if (service) add[(__bridge id)kSecAttrService] = service;
        if (account) add[(__bridge id)kSecAttrAccount] = account;
        add[(__bridge id)kSecValueData] = valueData;
        add[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
        SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    }
}

/// 恢复 cookies
- (void)_restoreCookies:(NSArray *)cookies {
    NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSDictionary *props in cookies) {
        NSString *name = props[@"name"];
        NSString *value = props[@"value"];
        NSString *domain = props[@"domain"];
        NSString *path = props[@"path"] ?: @"/";
        if (!name || !value || !domain) continue;
        NSDictionary *propsDict = @{
            NSHTTPCookieName: name,
            NSHTTPCookieValue: value,
            NSHTTPCookieDomain: domain,
            NSHTTPCookiePath: path,
            NSHTTPCookieSecure: @([props[@"secure"] boolValue]),
        };
        NSHTTPCookie *cookie = [NSHTTPCookie cookieWithProperties:propsDict];
        if (cookie) [storage setCookie:cookie];
    }
}

#pragma mark - 清空当前登录态（无痕）

- (void)clearCurrentState {
    @try {
        // 1. 清除 NSUserDefaults 中 TikTok 相关 key（session/cookies/device 等）
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSDictionary *all = [defaults dictionaryRepresentation];
        for (NSString *key in all) {
            // 保留插件自己的 key（XN_*），清除其它（TikTok 的数据）
            if ([key hasPrefix:@"XN_"] || [key hasPrefix:@"xnow"]) continue;
            [defaults removeObjectForKey:key];
        }
        [defaults synchronize];

        // 2. 清除 cookies
        NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        for (NSHTTPCookie *cookie in storage.cookies) {
            [storage deleteCookie:cookie];
        }

        // 3. 清除 Keychain 中 TikTok 服务条目
        NSDictionary *query = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: kTKKeychainService,
        };
        SecItemDelete((__bridge CFDictionaryRef)query);

        SNAP_LOG(@"当前登录态已清空（无痕）");
    } @catch (NSException *e) {
        SNAP_LOG(@"清空登录态异常: %@", e.reason);
    }
}

- (void)clearAllSnapshots {
    [[NSFileManager defaultManager] removeItemAtPath:_snapshotDir error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:_snapshotDir
                              withIntermediateDirectories:YES attributes:nil error:nil];
    SNAP_LOG(@"已删除所有账号快照");
}

- (NSDictionary *)currentUserDefaultsDump {
    return [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
}

@end

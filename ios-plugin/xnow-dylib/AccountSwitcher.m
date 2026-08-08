// AccountSwitcher.m
// XNOW 账号切换引擎实现
//
// 切换策略（3 层递进）:
//   1. Token 注入（秒切，需逆向 TikTok 的 session key）
//   2. Cookies 注入（通过 NSHTTPCookieStorage）
//   3. UI 自动化登录（后备，CommandEngine）

#import "AccountSwitcher.h"
#import "AccountPool.h"
#import "AccountSnapshotter.h"
#import "CommandEngine.h"
#import "XNWindowHelper.h"
#import "XNTouchSimulator.h"
#import <UIKit/UIKit.h>

#define SW_LOG(fmt, ...) NSLog(@"[XNOWER][Switcher] " fmt, ##__VA_ARGS__)

// ======== TikTok Session Key 配置 ========
// 这些 key 需要通过逆向 TikTok 二进制确认
// TODO: 在真机测试后替换为实际 key
static NSString *const kTKUserDefaultsSessionKey = @"session_token";    // TikTok session token
static NSString *const kTKUserDefaultsCookiesKey = @"cookies_data";     // TikTok cookies
static NSString *const kTKKeychainService = @"com.zhiliaoapp.musically";

@interface AccountSwitcher ()
@property (nonatomic, strong) CommandEngine *cmdEngine;
@property (nonatomic, assign) BOOL isSwitching;  // 防止并发切换
@property (nonatomic, strong) dispatch_queue_t switchQueue;
@end

@implementation AccountSwitcher

static AccountSwitcher *gShared = nil;

+ (AccountSwitcher *)sharedSwitcher {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gShared = [[self alloc] init];
    });
    return gShared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cmdEngine = [[CommandEngine alloc] init];
        _switchQueue = dispatch_queue_create("com.xnow.switcher", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - Public API

- (void)switchToAccount:(NSInteger)accountId completion:(SwitchCompletion)completion {
    if (self.isSwitching) {
        if (completion) completion(NO, @{@"status": @"failed", @"message": @"正在切换中，请稍后"});
        return;
    }

    NSDictionary *account = [[AccountPool sharedPool] accountWithId:accountId];
    if (!account) {
        if (completion) completion(NO, @{@"status": @"failed", @"message": @"账号不存在"});
        return;
    }

    self.isSwitching = YES;
    [[AccountPool sharedPool] updateStatus:accountId status:AccountStatusLoggingIn];

    dispatch_async(_switchQueue, ^{
        __block NSDictionary *result = nil;

        // [多账号隔离] 切换前：保存当前登录态到当前活跃账号的快照
        NSDictionary *active = [[AccountPool sharedPool] activeAccount];
        NSInteger activeId = [active[@"id"] integerValue];
        if (activeId > 0 && activeId != accountId) {
            [[AccountSnapshotter sharedSnapshotter] saveSnapshotForAccount:activeId];
            SW_LOG(@"已保存当前账号 %ld 登录态快照", (long)activeId);
        }

        // [多账号隔离] 目标账号有快照 → 直接恢复登录态 + 重启（无需重新登录）
        if ([[AccountSnapshotter sharedSnapshotter] hasSnapshotForAccount:accountId]) {
            SW_LOG(@"账号 %@ 有快照，直接恢复登录态", account[@"nickname"]);
            [[AccountSnapshotter sharedSnapshotter] restoreSnapshotForAccount:accountId];
            [[AccountPool sharedPool] markActive:accountId];
            self.isSwitching = NO;
            if (completion) completion(YES, @{@"status": @"restored", @"message": @"已恢复账号登录态"});
            // 重启 TikTok 进程，让注入的登录态生效
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self restartApp];
            });
            return;
        }

        // 策略 1: Token 注入（最快，秒切）
        result = [self _tryTokenInjection:account];
        if (result && [result[@"success"] boolValue]) {
            SW_LOG(@"Token 注入成功 → 账号 %@", account[@"nickname"]);
            [[AccountPool sharedPool] markActive:accountId];
            self.isSwitching = NO;
            if (completion) completion(YES, result);
            return;
        }

        // 策略 2: Cookies 注入
        result = [self _tryCookieInjection:account];
        if (result && [result[@"success"] boolValue]) {
            SW_LOG(@"Cookies 注入成功 → 账号 %@", account[@"nickname"]);
            [[AccountPool sharedPool] markActive:accountId];
            self.isSwitching = NO;
            if (completion) completion(YES, result);
            return;
        }

        // 策略 3: UI 自动化登录（后备）
        SW_LOG(@"Token/Cookies 注入失败，降级到 UI 自动化登录");
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self _tryUILogin:account completion:^(BOOL success, NSDictionary *r) {
                if (success) {
                    [[AccountPool sharedPool] markActive:accountId];
                    [[AccountPool sharedPool] updateStatus:accountId status:AccountStatusActive];
                } else {
                    [[AccountPool sharedPool] updateStatus:accountId status:AccountStatusFailed];
                }
                self.isSwitching = NO;
                if (completion) completion(success, r);
            }];
        });
    });
}

/// 重启 TikTok 进程（iOS 无优雅重启，靠 SpringBoard 拉起）
- (void)restartApp {
    SW_LOG(@"重启 TikTok 进程（注入登录态生效）");
    exit(0);
}

/// 备份当前登录账号的登录态快照（浮窗「备份」按钮调用）
/// 直接读 TikTok 原生登录数据（NSUserDefaults session / cookies / Keychain），任意页面可备份，不依赖个人页检测
/// @return 备份成功的账号 ID；未检测到登录态返回 0
- (NSInteger)backupCurrentAccount {
    // 1. 检查是否已登录（原生登录态：session_token 或 tiktok cookies）
    NSDictionary *login = [self verifyCurrentLogin];
    if (![login[@"isLoggedIn"] boolValue]) {
        SW_LOG(@"备份失败：未检测到登录态（session/cookies 为空）");
        return 0;
    }

    // 2. 从原生 NSUserDefaults 提取账号资料（用户名/粉丝/关注/国家/头像）
    NSDictionary *profile = [self _extractProfileFromDefaults];

    // 3. 获取或新建账号记录（带完整资料）
    NSInteger activeId = [login[@"accountId"] integerValue];
    if (activeId <= 0) {
        activeId = [[AccountPool sharedPool] addLocalAccount:@{
            @"nickname": profile[@"nickname"] ?: @"账号",
            @"aweme_number": profile[@"unique_id"] ?: @"",
            @"followers": profile[@"followers"] ?: @(0),
            @"following_count": profile[@"following_count"] ?: @(0),
            @"act_country": profile[@"country"] ?: @"",
            @"avatar_url": profile[@"avatar_url"] ?: @"",
        }];
    }

    // 4. 保存快照（快照引擎会捕获 NSUserDefaults 全量 + Keychain + cookies）
    BOOL ok = [[AccountSnapshotter sharedSnapshotter] saveSnapshotForAccount:activeId];
    SW_LOG(@"备份账号 %ld 登录态%@ 资料:%@", (long)activeId, ok ? @"成功" : @"失败", profile[@"nickname"] ?: @"-");
    return ok ? activeId : 0;
}

/// 从 NSUserDefaults 全量数据里提取当前账号资料（TikTok 缓存了用户信息）
- (NSDictionary *)_extractProfileFromDefaults {
    @try {
        NSDictionary *dump = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];

        // 1) 优先找包含昵称的字典/JSON（递归一层，避免太深）
        for (NSString *key in dump) {
            id val = dump[key];
            NSDictionary *d = nil;
            if ([val isKindOfClass:[NSDictionary class]]) d = val;
            else if ([val isKindOfClass:[NSData class]]) {
                id obj = [NSJSONSerialization JSONObjectWithData:val options:0 error:nil];
                if ([obj isKindOfClass:[NSDictionary class]]) d = obj;
            } else if ([val isKindOfClass:[NSString class]] && [val hasPrefix:@"{"]) {
                id obj = [NSJSONSerialization JSONObjectWithData:[val dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
                if ([obj isKindOfClass:[NSDictionary class]]) d = obj;
            }
            if (!d || ![d[@"nickname"] isKindOfClass:[NSString class]]) continue;
            if (!d[@"followerCount"] && !d[@"followers"] && !d[@"uid"]) continue; // 要像账号而非普通dict

            NSDictionary *stats = d[@"stats"] ?: d[@"stat"] ?: @{};
            return @{
                @"nickname": d[@"nickname"] ?: @"",
                @"unique_id": d[@"uniqueId"] ?: d[@"unique_id"] ?: @"",
                @"followers": d[@"followerCount"] ?: d[@"followers"] ?: stats[@"followerCount"] ?: stats[@"followers"] ?: @(0),
                @"following_count": d[@"followingCount"] ?: d[@"following_count"] ?: stats[@"followingCount"] ?: @(0),
                @"country": d[@"region"] ?: d[@"country"] ?: @"",
                @"avatar_url": d[@"avatarLarger"] ?: d[@"avatar"] ?: d[@"avatar_url"] ?: @"",
            };
        }
    } @catch (id e) {}
    return @{};
}

/// 新增账号：清空当前登录态（无痕），让用户登录全新账号
- (void)prepareNewAccount {
    SW_LOG(@"准备新增账号：清空当前登录态（无痕）");
    [[AccountSnapshotter sharedSnapshotter] clearCurrentState];
    [[AccountPool sharedPool] clearActiveAccount];
}

- (void)batchLogin:(NSArray<NSNumber *> *)accountIds
        completion:(void (^)(NSInteger, NSInteger, BOOL, NSDictionary * _Nullable))completion {

    dispatch_async(_switchQueue, ^{
        NSInteger total = accountIds.count;
        __block NSInteger done = 0;

        for (NSNumber *aid in accountIds) {
            __block BOOL blockFinished = NO;
            [self switchToAccount:[aid integerValue] completion:^(BOOL success, NSDictionary *result) {
                done++;
                blockFinished = YES;
                if (completion) {
                    completion(done, total, done >= total, result);
                }
            }];

            // 等待当前切换完成（最多等 60 秒）
            for (int i = 0; i < 120 && !blockFinished; i++) {
                [NSThread sleepForTimeInterval:0.5];
            }

            // 切换后等待一下，让 TikTok 稳定
            [NSThread sleepForTimeInterval:3.0];
        }
    });
}

- (void)logoutCurrentAccount:(SwitchCompletion)completion {
    SW_LOG(@"退出当前账号");
    dispatch_async(dispatch_get_main_queue(), ^{
        // 尝试清除 NSUserDefaults 中的 session
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kTKUserDefaultsSessionKey];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kTKUserDefaultsCookiesKey];
        [[NSUserDefaults standardUserDefaults] synchronize];

        // 清除 cookies
        NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        for (NSHTTPCookie *cookie in storage.cookies) {
            [storage deleteCookie:cookie];
        }

        // 走 UI 退出流程（CommandEngine 已有 switch_account 的退出逻辑）
        @try {
            [self.cmdEngine executeCommand:@{
                @"action": @"switch_account",
                @"params": @{@"logout_only": @YES}
            } completion:^(NSDictionary *result) {
                SW_LOG(@"退出登录结果: %@", result);
                if (completion) completion(YES, result);
            }];
        } @catch (NSException *e) {
            SW_LOG(@"退出登录异常: %@", e.reason);
            if (completion) completion(NO, @{@"status": @"failed", @"message": e.reason});
        }
    });
}

- (NSDictionary *)verifyCurrentLogin {
    // 1. NSUserDefaults 里的 session token（TikTok 原生登录态）
    NSString *token = [[NSUserDefaults standardUserDefaults] stringForKey:kTKUserDefaultsSessionKey];
    if (token.length > 0) {
        return @{@"isLoggedIn": @YES, @"method": @"token"};
    }

    // 2. tiktok/byteoversea 域 cookies（有说明已登录）
    NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in storage.cookies) {
        NSString *domain = cookie.domain.lowercaseString;
        if ([domain containsString:@"tiktok"] || [domain containsString:@"byteoversea"]) {
            return @{@"isLoggedIn": @YES, @"method": @"cookie"};
        }
    }

    // 3. AccountPool activeAccount 兜底（切换过的账号）
    NSDictionary *active = [[AccountPool sharedPool] activeAccount];
    if (active) {
        return @{
            @"isLoggedIn": @YES,
            @"accountId": active[@"id"] ?: @(0),
            @"nickname": active[@"nickname"] ?: @"",
        };
    }

    return @{@"isLoggedIn": @NO};
}

#pragma mark - Injection Strategies

/// 策略 1: Token 注入 — 直接写入 TikTok 的 NSUserDefaults session key
- (NSDictionary *)_tryTokenInjection:(NSDictionary *)account {
    NSString *token = account[@"token"];
    if (token.length == 0) {
        return @{@"success": @NO, @"message": @"无 token 可注入"};
    }

    @try {
        // 写入 TikTok 的 session key
        [[NSUserDefaults standardUserDefaults] setObject:token forKey:kTKUserDefaultsSessionKey];

        // 同步到磁盘（确保即使 App 被杀也不丢失）
        [[NSUserDefaults standardUserDefaults] synchronize];

        SW_LOG(@"Token 已注入 NSUserDefaults[%@]", kTKUserDefaultsSessionKey);
        return @{@"success": @YES, @"message": @"Token 注入成功", @"method": @"token_injection"};
    } @catch (NSException *e) {
        SW_LOG(@"Token 注入失败: %@", e.reason);
        return @{@"success": @NO, @"message": e.reason};
    }
}

/// 策略 2: Cookies 注入 — 写入 NSHTTPCookieStorage
- (NSDictionary *)_tryCookieInjection:(NSDictionary *)account {
    NSString *cookiesStr = account[@"cookies"];
    if (cookiesStr.length == 0) {
        return @{@"success": @NO, @"message": @"无 cookies 可注入"};
    }

    @try {
        NSData *data = [cookiesStr dataUsingEncoding:NSUTF8StringEncoding];
        NSError *err = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
        if (!json && err) {
            // 尝试解析为 raw cookie string: "key=value; key2=value2"
            NSArray *parts = [cookiesStr componentsSeparatedByString:@";"];
            NSMutableDictionary *cookieDict = [NSMutableDictionary dictionary];
            for (NSString *part in parts) {
                NSArray *kv = [part componentsSeparatedByString:@"="];
                if (kv.count == 2) {
                    NSString *key = [kv[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    NSString *val = [kv[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    if (key.length > 0) cookieDict[key] = val;
                }
            }
            json = cookieDict;
        }

        if ([json isKindOfClass:[NSDictionary class]]) {
            NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
            NSDictionary *properties = @{
                NSHTTPCookieDomain: @".tiktok.com",
                NSHTTPCookiePath: @"/",
                NSHTTPCookieSecure: @"TRUE",
            };
            for (NSString *key in (NSDictionary *)json) {
                NSString *val = json[key];
                if ([val isKindOfClass:[NSString class]] && key.length > 0) {
                    NSMutableDictionary *props = [properties mutableCopy];
                    props[NSHTTPCookieName] = key;
                    props[NSHTTPCookieValue] = val;
                    NSHTTPCookie *cookie = [NSHTTPCookie cookieWithProperties:props];
                    if (cookie) {
                        [storage setCookie:cookie];
                    }
                }
            }
        }

        // 同时存一份到 NSUserDefaults
        [[NSUserDefaults standardUserDefaults] setObject:cookiesStr forKey:kTKUserDefaultsCookiesKey];
        [[NSUserDefaults standardUserDefaults] synchronize];

        SW_LOG(@"Cookies 注入完成");
        return @{@"success": @YES, @"message": @"Cookies 注入成功", @"method": @"cookie_injection"};
    } @catch (NSException *e) {
        SW_LOG(@"Cookies 注入失败: %@", e.reason);
        return @{@"success": @NO, @"message": e.reason};
    }
}

/// 策略 3: UI 自动化登录 — 通过 CommandEngine 模拟点击登录
- (void)_tryUILogin:(NSDictionary *)account completion:(SwitchCompletion)completion {
    NSString *password = account[@"password"];
    if (password.length == 0) {
        if (completion) completion(NO, @{@"status": @"failed", @"message": @"无密码，无法自动登录"});
        return;
    }

    // 复用 CommandEngine 的 switch_account 流程
    // 先退出当前账号（如果已登录）
    [self.cmdEngine executeCommand:@{
        @"action": @"switch_account",
        @"params": @{@"logout_only": @YES}
    } completion:^(NSDictionary *logoutResult) {
        SW_LOG(@"退出登录完成");

        // 延迟等待退出完成
        [NSThread sleepForTimeInterval:2.0];

        // 寻找登录按钮并点击
        dispatch_async(dispatch_get_main_queue(), ^{
            UIWindow *window = XN_ActiveWindow();
            if (!window) {
                if (completion) completion(NO, @{@"status": @"failed", @"message": @"无法获取窗口"});
                return;
            }

            // 点击 "Log in" / "登录" 按钮
            UIButton *loginBtn = [self _findLoginButtonInView:window];
            if (loginBtn) {
                CGPoint pt = [loginBtn.superview convertPoint:loginBtn.center toView:nil];
                [self _safeTapAtPoint:pt];
                SW_LOG(@"点击了登录按钮");
            }

            // 注意：到这里之后，如果 TikTok 要求验证码（短信/邮箱）
            // 自动流程无法继续，需要 App 弹通知让用户手动完成
            // 或者等后续实现 SMS 验证码自动读取

            if (completion) {
                completion(YES, @{
                    @"status": @"partial",
                    @"message": @"已退出当前账号并打开登录页。如有验证码请手动完成登录",
                    @"need_manual": @YES,
                });
            }
        });
    }];
}

#pragma mark - Helpers

- (UIButton *)_findLoginButtonInView:(UIView *)view {
    if ([view isKindOfClass:[UIButton class]]) {
        UIButton *btn = (UIButton *)view;
        NSString *title = [btn titleForState:UIControlStateNormal];
        NSString *acc = btn.accessibilityLabel;
        if ([title containsString:@"Log in"] || [title containsString:@"登录"] ||
            [acc containsString:@"Log in"] || [acc containsString:@"登录"]) {
            return btn;
        }
    }
    for (UIView *sub in view.subviews) {
        UIButton *found = [self _findLoginButtonInView:sub];
        if (found) return found;
    }
    return nil;
}

- (void)_safeTapAtPoint:(CGPoint)point {
    [XNTouchSimulator tapAtPoint:point];
}

@end

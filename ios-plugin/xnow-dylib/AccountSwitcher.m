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
#import "AccountManager.h"
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
@property (nonatomic, strong, readwrite) NSArray<NSString *> *lastMatchedProfileKeys;
@property (nonatomic, copy, readwrite) NSString *lastMatchedCountry;
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
    // 1. 提取账号资料：v1.4.116 底层直读优先（NSUserDefaults 深度递归 + uid_tt 消歧，任意页面可备份），
    //    再叠 AccountManager（/user/ 网络捕获）补充头像/粉丝数
    NSDictionary *profile = [self _extractProfileFromDefaults];
    NSDictionary *detected = [[AccountManager sharedManager] currentAccount];
    if (detected.count > 0) {
        profile = @{
            // v1.4.108 B41：存 aweme_id（抖音数字ID），后台 switch_account 用 aweme_id 匹配
            @"aweme_id": detected[@"aweme_id"] ?: profile[@"aweme_id"] ?: @"",
            @"nickname": detected[@"nickname"] ?: profile[@"nickname"] ?: @"",
            @"unique_id": detected[@"unique_id"] ?: profile[@"unique_id"] ?: @"",
            @"followers": detected[@"followers"] ?: profile[@"followers"] ?: @(0),
            @"following_count": detected[@"following_count"] ?: profile[@"following_count"] ?: @(0),
            @"country": detected[@"region"] ?: profile[@"country"] ?: @"",
            @"avatar_url": detected[@"avatar_url"] ?: profile[@"avatar_url"] ?: @"",
        };
    }

    // 1b. 底层直读仍空（TikTok 未在 NSUserDefaults 缓存当前账号，结构未知）→ 最后兜底：
    //     导航个人页触发 UI/网络捕获（v1.4.115 起已确认在"我的主页"才扫描，不会误抓视频作者）。
    //     v1.4.116 起此兜底仅在前两层（defaults / detected）都失败时触发。
    if (![profile[@"aweme_id"] length] && ![profile[@"unique_id"] length]) {
        SW_LOG(@"账号资料为空，导航个人页触发捕获...");
        NSDictionary *captured = [self.cmdEngine detectCurrentAccountFlow];
        if (captured.count > 0) {
            profile = @{
                @"aweme_id": captured[@"aweme_id"] ?: profile[@"aweme_id"] ?: @"",
                @"nickname": captured[@"nickname"] ?: profile[@"nickname"] ?: @"",
                @"unique_id": captured[@"unique_id"] ?: profile[@"unique_id"] ?: @"",
                @"followers": captured[@"followers"] ?: profile[@"followers"] ?: @(0),
                @"following_count": captured[@"following_count"] ?: profile[@"following_count"] ?: @(0),
                @"country": captured[@"region"] ?: profile[@"country"] ?: @"",
                @"avatar_url": captured[@"avatar_url"] ?: profile[@"avatar_url"] ?: @"",
            };
        }
    }

    // 1c. 诊断字段始终反映最终存储的国家（detected/captured 可能覆盖 defaults 提取值）
    self.lastMatchedCountry = profile[@"country"] ?: @"";

    // 2. 登录证明 = 拿到真实账号标识（@用户名 unique_id 或数字 aweme_id）。拿不到 → 明确失败，不落演示号
    NSString *awemeNum = profile[@"unique_id"] ?: @"";
    if ([awemeNum hasPrefix:@"@"]) awemeNum = [awemeNum substringFromIndex:1];  // 去 @ 前缀，统一存储
    if (!awemeNum.length && ![profile[@"aweme_id"] length]) {
        SW_LOG(@"备份失败：未检测到 TikTok 登录（捕获均无账号资料）");
        return 0;
    }

    // 3. 去重或新建账号记录（按 unique_id 匹配，绝不沿用 pool 演示 id）
    NSInteger activeId = 0;
    if (awemeNum.length) {
        NSDictionary *existing = [[AccountPool sharedPool] accountWithAwemeNumber:awemeNum];
        if (existing) {
            activeId = [existing[@"id"] integerValue];
            [[AccountPool sharedPool] upsertAccount:@{
                @"id": @(activeId),
                @"aweme_id": profile[@"aweme_id"] ?: @"",
                @"nickname": profile[@"nickname"] ?: @"账号",
                @"aweme_number": awemeNum,
                @"followers": profile[@"followers"] ?: @(0),
                @"following_count": profile[@"following_count"] ?: @(0),
                @"act_country": profile[@"country"] ?: @"",
                @"avatar_url": profile[@"avatar_url"] ?: @"",
            }];
            [[AccountPool sharedPool] markActive:activeId];
            SW_LOG(@"去重更新已有账号 #%ld", (long)activeId);
        }
    }
    if (activeId <= 0) {
        activeId = [[AccountPool sharedPool] addLocalAccount:@{
            @"aweme_id": profile[@"aweme_id"] ?: @"",
            @"nickname": profile[@"nickname"] ?: (awemeNum.length ? awemeNum : @"账号"),
            @"aweme_number": awemeNum,
            @"followers": profile[@"followers"] ?: @(0),
            @"following_count": profile[@"following_count"] ?: @(0),
            @"act_country": profile[@"country"] ?: @"",
            @"avatar_url": profile[@"avatar_url"] ?: @"",
        }];
    }

    // 4. 保存快照（快照引擎会捕获 NSUserDefaults 全量 + Keychain + cookies）
    BOOL ok = [[AccountSnapshotter sharedSnapshotter] saveSnapshotForAccount:activeId];
    SW_LOG(@"备份账号 %ld 登录态%@ 资料:%@", (long)activeId, ok ? @"成功" : @"失败", profile[@"nickname"] ?: awemeNum);
    return ok ? activeId : 0;
}

/// 从 NSUserDefaults 全量数据里提取当前账号资料（TikTok 缓存了用户信息）
/// v1.4.116 重写：深度递归扫所有嵌套 dict/JSON，找含账号标识的 dict；
/// 再用 cookie uid_tt（登录用户数字ID）消歧，只认"我"，不再误抓视频作者。
- (NSDictionary *)_extractProfileFromDefaults {
    @try {
        NSDictionary *dump = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
        NSMutableArray *cands = [NSMutableArray array];
        [self _collectAccountCandidates:dump depth:0 candidates:cands];
        if (!cands.count) return @{};

        // 登录用户数字ID（cookie uid_tt）→ 只认它匹配的候选，杜绝抓成视频作者
        NSString *selfUid = [self _selfUidFromCookies];
        NSDictionary *best = nil;
        if (selfUid.length > 0) {
            // 同 uid 可能缓存精简版+完整版多份 → 优先带国家字段/资料更全者（同账号，安全）
            for (NSDictionary *c in cands) {
                id uid = c[@"uid"] ?: c[@"aweme_id"] ?: c[@"user_id"];
                NSString *uidStr = [uid isKindOfClass:[NSNumber class]] ? [uid stringValue]
                                 : ([uid isKindOfClass:[NSString class]] ? uid : @"");
                if (uidStr.length && [uidStr isEqualToString:selfUid] && [self _betterCandidate:c vs:best]) best = c;
            }
        }
        // 无 uid_tt 或没匹配到 → 取资料最全者（此时才可能不准，但比瞎猜好）
        if (!best) {
            for (NSDictionary *c in cands) {
                if (!best || [self _profileCompleteness:c] > [self _profileCompleteness:best]) best = c;
            }
        }
        if (!best) return @{};

        // 诊断：记录命中 dict 的 key 名 + 国家（仅名字不含值，上报供定位真实国家字段）
        self.lastMatchedProfileKeys = [best allKeys];
        self.lastMatchedCountry = [self _extractCountryFromDict:best];

        NSDictionary *stats = [best[@"stats"] isKindOfClass:[NSDictionary class]] ? best[@"stats"]
                            : ([best[@"stat"] isKindOfClass:[NSDictionary class]] ? best[@"stat"] : @{});
        // NSNull 防护：统一把非字符串/非数字值归一为空，防止 profile 字典带 NSNull 传给下游崩溃
        return @{
            @"aweme_id": [best[@"aweme_id"] isKindOfClass:[NSString class]] ? best[@"aweme_id"]
                       : ([best[@"uid"] isKindOfClass:[NSString class]] ? best[@"uid"] : @""),
            @"nickname": [best[@"nickname"] isKindOfClass:[NSString class]] ? best[@"nickname"] : @"",
            @"unique_id": [best[@"uniqueId"] isKindOfClass:[NSString class]] ? best[@"uniqueId"]
                        : ([best[@"unique_id"] isKindOfClass:[NSString class]] ? best[@"unique_id"] : @""),
            @"followers": [best[@"followerCount"] isKindOfClass:[NSNumber class]] ? best[@"followerCount"]
                        : (best[@"followers"] ?: @(0)),
            @"following_count": [best[@"followingCount"] isKindOfClass:[NSNumber class]] ? best[@"followingCount"]
                              : ([best[@"following_count"] isKindOfClass:[NSNumber class]] ? best[@"following_count"] : @(0)),
            @"country": [self _extractCountryFromDict:best],
            @"avatar_url": [best[@"avatarLarger"] isKindOfClass:[NSString class]] ? best[@"avatarLarger"]
                         : ([best[@"avatar_larger"] isKindOfClass:[NSString class]] ? best[@"avatar_larger"]
                           : ([best[@"avatar"] isKindOfClass:[NSString class]] ? best[@"avatar"]
                             : ([best[@"avatar_url"] isKindOfClass:[NSString class]] ? best[@"avatar_url"] : @""))),
        };
    } @catch (id e) {}
    return @{};
}

/// 递归收集所有"账号形状"的字典（含 unique_id/uid/aweme_id/sec_uid 任一 + 资料字段）
- (void)_collectAccountCandidates:(id)value depth:(int)depth candidates:(NSMutableArray<NSDictionary *> *)candidates {
    if (depth > 5 || candidates.count >= 10) return;
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = (NSDictionary *)value;
        // TikTok JSON 反序列化常带 NSNull，取值统一判 class，防 nil/NSNull 崩溃
        NSString *uniq = [d[@"unique_id"] isKindOfClass:[NSString class]] ? d[@"unique_id"]
                       : ([d[@"uniqueId"] isKindOfClass:[NSString class]] ? d[@"uniqueId"] : @"");
        id uid = d[@"uid"] ?: d[@"aweme_id"] ?: d[@"user_id"];
        NSString *sec = [d[@"sec_uid"] isKindOfClass:[NSString class]] ? d[@"sec_uid"]
                      : ([d[@"secUid"] isKindOfClass:[NSString class]] ? d[@"secUid"] : @"");
        BOOL hasProfile = [d[@"nickname"] isKindOfClass:[NSString class]]
                       || [d[@"avatar_larger"] isKindOfClass:[NSString class]]
                       || [d[@"avatarLarger"] isKindOfClass:[NSString class]]
                       || d[@"followers"] != nil || d[@"follower_count"] != nil || d[@"followerCount"] != nil;
        if (hasProfile && (uniq.length > 0 || uid != nil || sec.length > 0)) {
            [candidates addObject:d];
        }
        for (id k in d) [self _collectAccountCandidates:d[k] depth:depth + 1 candidates:candidates];
    } else if ([value isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)value) [self _collectAccountCandidates:item depth:depth + 1 candidates:candidates];
    } else if ([value isKindOfClass:[NSData class]]) {
        NSData *data = (NSData *)value;
        if (data.length > 0 && data.length < 2 * 1024 * 1024) {   // 只解析 <2MB 的（防大缓存拖慢）
            id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([obj isKindOfClass:[NSDictionary class]] || [obj isKindOfClass:[NSArray class]]) {
                [self _collectAccountCandidates:obj depth:depth + 1 candidates:candidates];
            }
        }
    } else if ([value isKindOfClass:[NSString class]] && [value hasPrefix:@"{"]) {
        id obj = [NSJSONSerialization JSONObjectWithData:[value dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if ([obj isKindOfClass:[NSDictionary class]] || [obj isKindOfClass:[NSArray class]]) {
            [self _collectAccountCandidates:obj depth:depth + 1 candidates:candidates];
        }
    }
}

/// 账号 dict 资料完整度评分（无 uid_tt 匹配时取最高分）
- (int)_profileCompleteness:(NSDictionary *)d {
    int s = 0;
    if ([d[@"nickname"] isKindOfClass:[NSString class]] && [d[@"nickname"] length]) s += 3;
    if (([d[@"unique_id"] isKindOfClass:[NSString class]] && [d[@"unique_id"] length])
     || ([d[@"uniqueId"] isKindOfClass:[NSString class]] && [d[@"uniqueId"] length])) s += 3;
    if (d[@"followerCount"] || d[@"follower_count"] || d[@"followers"]) s += 1;
    if ([d[@"avatarLarger"] isKindOfClass:[NSString class]] || [d[@"avatar_larger"] isKindOfClass:[NSString class]]) s += 1;
    return s;
}

/// 从账号 dict 提取国家：TikTok 不同版本/缓存字段名不同，多键位尝试 + 类型安全（NSNull 跳过）
- (NSString *)_extractCountryFromDict:(NSDictionary *)d {
    if (![d isKindOfClass:[NSDictionary class]]) return @"";
    NSArray *keys = @[@"region", @"country", @"display_region", @"country_code",
                      @"region_code", @"ip_location", @"location", @"area"];
    for (NSString *k in keys) {
        id v = d[k];
        if ([v isKindOfClass:[NSString class]]) {
            NSString *s = [v stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (s.length) return s;
        } else if ([v isKindOfClass:[NSNumber class]]) {
            NSString *s = [v stringValue];
            if (s.length) return s;
        }
        // NSNull / 其他类型 → 试下一个键
    }
    return @"";
}

/// 同 uid 多缓存择优：带国家的 > 资料分高的（仅用于 uid 已匹配的同账号候选，杜绝误选他人）
- (BOOL)_betterCandidate:(NSDictionary *)c vs:(NSDictionary *)best {
    if (!best) return YES;
    BOOL cCountry = [self _extractCountryFromDict:c].length > 0;
    BOOL bCountry = [self _extractCountryFromDict:best].length > 0;
    if (cCountry != bCountry) return cCountry;
    return [self _profileCompleteness:c] > [self _profileCompleteness:best];
}

/// cookie 里的登录用户数字ID（TikTok 设置 uid_tt）——消歧：认"我"不认视频作者
- (NSString *)_selfUidFromCookies {
    @try {
        NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        for (NSHTTPCookie *cookie in storage.cookies) {
            NSString *name = cookie.name.lowercaseString;
            if ([name isEqualToString:@"uid_tt"] || [name isEqualToString:@"uid_tt_ss"]) {
                return cookie.value ?: @"";
            }
        }
    } @catch (id e) {}
    return @"";
}

/// 登录态诊断：NSUserDefaults key 名 + cookies name/domain（仅名字不含值，隐私安全）
- (NSDictionary *)dumpLoginState {
    @try {
        NSDictionary *dump = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
        NSArray *sorted = [[dump allKeys] sortedArrayUsingSelector:@selector(compare:)];
        NSMutableArray *keysOut = [NSMutableArray array];
        NSUInteger cap = 120;
        for (NSString *k in sorted) {
            if (keysOut.count >= cap) break;
            id v = dump[k];
            NSString *t = @"?";
            if ([v isKindOfClass:[NSString class]]) t = @"str";
            else if ([v isKindOfClass:[NSNumber class]]) t = @"num";
            else if ([v isKindOfClass:[NSDictionary class]]) t = @"dict";
            else if ([v isKindOfClass:[NSArray class]]) t = @"arr";
            else if ([v isKindOfClass:[NSData class]]) t = @"data";
            [keysOut addObject:[NSString stringWithFormat:@"%@:%@", k, t]];
        }
        NSMutableArray *cookiesOut = [NSMutableArray array];
        NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        for (NSHTTPCookie *c in storage.cookies) {
            NSString *d = c.domain.lowercaseString;
            if ([d containsString:@"tiktok"] || [d containsString:@"byteoversea"]) {
                [cookiesOut addObject:[NSString stringWithFormat:@"%@@%@", c.name ?: @"", c.domain ?: @""]];
            }
        }
        return @{
            @"userdefaults_keys": keysOut ?: @[],
            @"cookies": cookiesOut ?: @[],
            @"uid_tt": [self _selfUidFromCookies] ?: @"",
            @"login": [self verifyCurrentLogin] ?: @{},
            @"total_keys": @(dump.count),
        };
    } @catch (id e) {
        return @{@"error": [NSString stringWithFormat:@"%@", e]};
    }
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

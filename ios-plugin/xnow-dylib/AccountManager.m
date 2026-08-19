// AccountManager.m
// XNOW 账号管理器实现

#import "AccountManager.h"
#import "XNWindowHelper.h"
#import <UIKit/UIKit.h>

#define ACC_LOG(fmt, ...) NSLog(@"[XNOWER][Account] " fmt, ##__VA_ARGS__)

@interface AccountManager ()
@property (nonatomic, strong) NSDictionary *_currentAccount;
@property (nonatomic, strong) NSTimer *detectTimer;
// 上报回调 — 由 XNOWER 设置，用于发送 WebSocket 消息
@property (nonatomic, copy) void (^reportCallback)(NSDictionary *msg);
@end

@implementation AccountManager

static AccountManager *gShared = nil;

+ (AccountManager *)sharedManager {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gShared = [[self alloc] init];
    });
    return gShared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        __currentAccount = nil;
    }
    return self;
}

#pragma mark - 公开方法

- (NSDictionary *)currentAccount {
    return __currentAccount;
}

- (BOOL)isLoggedIn {
    return __currentAccount != nil && [__currentAccount[@"aweme_id"] length] > 0;
}

#pragma mark - API 拦截解析（Tier 1 — 最可靠）

- (void)onTikTokAPIResponse:(NSDictionary *)json url:(NSString *)url {
    // 只处理用户资料相关 API
    if (![url containsString:@"user"] && ![url containsString:@"profile"]) {
        return;
    }

    @try {
        // TikTok API 响应结构: { "data": { "user": { ... } } }
        // 不同版本可能不同，尝试多种路径
        NSDictionary *user = json[@"data"][@"user"]
                           ?: json[@"user"]
                           ?: json[@"data"][@"userInfo"]
                           ?: nil;
        if (!user) {
            // 也可能是列表中的用户
            NSArray *userList = json[@"data"][@"userList"]
                              ?: json[@"userList"]
                              ?: nil;
            if ([userList isKindOfClass:[NSArray class]] && userList.count > 0) {
                user = userList[0];
            }
        }
        if (!user) return;

        NSString *awemeId = [self _stringValue:user[@"id"]]
                          ?: [self _stringValue:user[@"uid"]]
                          ?: [self _stringValue:user[@"aweme_id"]];
        if (!awemeId) return;

        // 提取账号信息
        NSString *nickname = [self _stringValue:user[@"nickname"]];
        NSString *uniqueId = [self _stringValue:user[@"uniqueId"]]
                           ?: [self _stringValue:user[@"unique_id"]];
        NSString *signature = [self _stringValue:user[@"signature"]]
                            ?: [self _stringValue:user[@"desc"]];
        NSString *avatar = [self _stringValue:user[@"avatarLarger"]]
                         ?: [self _stringValue:user[@"avatar"]]
                         ?: [self _stringValue:user[@"avatar_url"]];

        // 统计信息可能在 stats 子对象中
        NSDictionary *stats = user[@"stats"] ?: user[@"stat"] ?: @{};
        int followers = [[self _numberValue:stats[@"followerCount"]
                                       ?: stats[@"followers"]
                                       ?: user[@"followerCount"]
                                       ?: @(0)] intValue];
        int following = [[self _numberValue:stats[@"followingCount"]
                                       ?: stats[@"followings"]
                                       ?: user[@"followingCount"]
                                       ?: @(0)] intValue];
        int diggs = [[self _numberValue:stats[@"diggCount"]
                                    ?: stats[@"heart"]
                                    ?: user[@"diggCount"]
                                    ?: @(0)] intValue];
        int videos = [[self _numberValue:stats[@"videoCount"]
                                     ?: user[@"videoCount"]
                                     ?: @(0)] intValue];

        // 构建账号信息字典
        NSDictionary *account = @{
            @"aweme_id": awemeId,
            @"nickname": nickname ?: @"",
            @"unique_id": uniqueId ?: @"",
            @"followers": @(followers),
            @"following_count": @(following),
            @"digg_count": @(diggs),
            @"video_count": @(videos),
            @"signature": signature ?: @"",
            @"avatar_url": avatar ?: @"",
            @"health_score": @(100),
            @"status": @"active",
        };

        // 更新缓存
        __currentAccount = account;
        ACC_LOG(@"检测到账号: %@ (%@) | 粉丝:%d", nickname ?: @"?", awemeId, followers);

        // 触发上报
        [self reportCurrentAccount];

    } @catch (NSException *e) {
        ACC_LOG(@"解析API响应异常: %@", e.reason);
    }
}

#pragma mark - UI 遍历检测（Tier 2 — 后备方案）

- (void)detectCurrentAccountWithCompletion:(void(^)(NSDictionary *))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // 先看缓存
        if (self.currentAccount) {
            if (completion) completion(self.currentAccount);
            return;
        }

        // v1.4.115：个人页异步加载，多扫几次（最多 5 秒），扫到 @用户名/昵称即停
        __block NSMutableDictionary *result = [NSMutableDictionary dictionary];
        for (int i = 0; i < 10; i++) {
            __block NSMutableDictionary *scanResult = [NSMutableDictionary dictionary];
            dispatch_sync(dispatch_get_main_queue(), ^{
                UIWindow *window = XN_ActiveWindow();
                if (!window) return;
                [self _findAccountLabelsInView:window result:scanResult];
            });
            if (scanResult.count > 0) { result = scanResult; break; }
            [NSThread sleepForTimeInterval:0.5];
        }

        // v1.4.115 修复：原判断 result[@"nickname"] 但提取函数从不写 nickname → __currentAccount 永不更新。
        // 改为任一路径命中（unique_id/@用户名 / nickname / aweme_id）即算检测到。
        if (result[@"nickname"] || result[@"unique_id"] || result[@"aweme_id"]) {
            __currentAccount = [result copy];
            ACC_LOG(@"UI检测到账号: %@", result[@"unique_id"] ?: result[@"nickname"]);
        }

        if (completion) completion(result.count > 0 ? result : nil);
    });
}

/// 遍历视图找账号相关的标签（个人页 UI 实测：@用户名在 AWEUserNameLabel，昵称在头像 accessibilityLabel "昵称, Profile photo,"）
/// v1.4.115：补 nickname/关注数的提取 + 支持 accessibilityLabel 的 @ 用户名（纯 UILabel.text 扫不到所有情况）
- (void)_findAccountLabelsInView:(UIView *)view result:(NSMutableDictionary *)result {
    if (result[@"unique_id"] && result[@"nickname"]) return; // 关键信息已齐

    NSString *accLabel = view.accessibilityLabel;
    NSString *labelText = ([view isKindOfClass:[UILabel class]]) ? ((UILabel *)view).text : nil;
    if (labelText.length == 0) labelText = nil;

    // 1. @用户名：UILabel.text 或 accessibilityLabel 以 @ 开头
    if (!result[@"unique_id"]) {
        NSString *at = nil;
        if (labelText.length > 0 && [labelText hasPrefix:@"@"]) at = labelText;
        else if (accLabel.length > 0 && [accLabel hasPrefix:@"@"]) at = accLabel;
        if (at.length > 0) result[@"unique_id"] = at;
    }

    // 2. 昵称：头像视图 accessibilityLabel "昵称, Profile photo," → 取逗号前首段
    if (!result[@"nickname"] && accLabel.length > 0 && [accLabel containsString:@"Profile photo"]) {
        NSString *first = [[accLabel componentsSeparatedByString:@","] firstObject];
        first = [first stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (first.length > 0) result[@"nickname"] = first;
    }

    // 3. 纯数字且长度 6-20 → 可能是抖音号/aweme_id
    if (labelText.length >= 6 && labelText.length <= 20 && [self _isNumeric:labelText]) {
        result[@"aweme_number"] = labelText;
        result[@"aweme_id"] = labelText;
    }

    // 4. 关注/粉丝数："0, Following," 形式（UIStackView accessibilityLabel）
    if (accLabel.length > 0) {
        NSArray *parts = [accLabel componentsSeparatedByString:@","];
        if (parts.count >= 2) {
            NSString *num = [parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSString *cat = [[parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
            if (cat.length && [num integerValue] >= 0 && [num integerValue] <= 99999999) {
                if ([cat hasPrefix:@"follower"]) result[@"followers"] = @([num integerValue]);
                else if ([cat hasPrefix:@"following"]) result[@"following_count"] = @([num integerValue]);
            }
        }
    }

    for (UIView *subview in view.subviews) {
        [self _findAccountLabelsInView:subview result:result];
    }
}

#pragma mark - 登录页面检测

- (BOOL)detectLoginPage {
    __block BOOL isLoginPage = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIWindow *window = XN_ActiveWindow();
        if (!window) return;

        // 检查是否有 "Log in" / "登录" 相关按钮
        UIButton *loginBtn = [self _findButtonWithTextInView:window texts:@[
            @"Log in", @"登录", @"Sign up", @"注册", @"Phone number", @"手机号"
        ]];
        if (loginBtn) {
            isLoginPage = YES;
        }
    });
    return isLoginPage;
}

/// 在视图树中找包含指定文本的按钮
- (UIButton *)_findButtonWithTextInView:(UIView *)view texts:(NSArray<NSString *> *)texts {
    if ([view isKindOfClass:[UIButton class]]) {
        UIButton *btn = (UIButton *)view;
        NSString *title = [btn titleForState:UIControlStateNormal];
        NSString *accLabel = btn.accessibilityLabel;
        for (NSString *t in texts) {
            if ([title containsString:t] || [accLabel containsString:t]) {
                return btn;
            }
        }
    }
    for (UIView *subview in view.subviews) {
        UIButton *found = [self _findButtonWithTextInView:subview texts:texts];
        if (found) return found;
    }
    return nil;
}

#pragma mark - 上报

- (void)reportCurrentAccount {
    if (!self.currentAccount) return;

    if (self.reportCallback) {
        self.reportCallback(@{
            @"type": @"account_update",
            @"data": self.currentAccount,
        });
    }
}

/// 清除缓存（退出登录后调用）
- (void)clearAccount {
    __currentAccount = nil;
    [self reportCurrentAccount];
}

/// 设置上报回调（由 XNOWER 在初始化时设置）
- (void)setReportCallback:(void (^)(NSDictionary *))callback {
    _reportCallback = callback;
}

#pragma mark - 定期检测

- (void)startPeriodicDetection:(NSTimeInterval)interval {
    [self stopPeriodicDetection];
    self.detectTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                         target:self
                                                       selector:@selector(_periodicDetect)
                                                       userInfo:nil
                                                        repeats:YES];
}

- (void)stopPeriodicDetection {
    [self.detectTimer invalidate];
    self.detectTimer = nil;
}

- (void)_periodicDetect {
    // 如果有 API 拦截到的数据，不需要主动检测
    // 只有在没有缓存时才主动检测
    if (!self.currentAccount) {
        [self detectCurrentAccountWithCompletion:^(NSDictionary *account) {
            if (account) {
                ACC_LOG(@"定期检测到账号");
            }
        }];
    }
}

#pragma mark - 工具方法

- (NSString *)_stringValue:(id)value {
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value isKindOfClass:[NSNumber class]]) return [value stringValue];
    return nil;
}

- (NSNumber *)_numberValue:(id)value {
    if ([value isKindOfClass:[NSNumber class]]) return value;
    if ([value isKindOfClass:[NSString class]]) {
        return @([value integerValue]);
    }
    return nil;
}

- (BOOL)_isNumeric:(NSString *)str {
    if (str.length == 0) return NO;
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    return [str rangeOfCharacterFromSet:nonDigits].location == NSNotFound;
}

@end

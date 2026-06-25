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

        __block NSMutableDictionary *result = [NSMutableDictionary dictionary];
        dispatch_sync(dispatch_get_main_queue(), ^{
            UIWindow *window = XN_ActiveWindow();
            if (!window) return;

            // 尝试找昵称: accessibilityLabel 含 "@" 的视图
            [self _findAccountLabelsInView:window result:result];
        });

        if (result[@"nickname"] && [result[@"nickname"] length] > 0) {
            __currentAccount = [result copy];
            ACC_LOG(@"UI检测到账号: %@", result[@"nickname"]);
        }

        if (completion) completion(result.count > 0 ? result : nil);
    });
}

/// 遍历视图找账号相关的标签
- (void)_findAccountLabelsInView:(UIView *)view result:(NSMutableDictionary *)result {
    if (result[@"nickname"]) return; // 已找到

    // UILabel 文本
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        NSString *text = label.text;
        if (text.length > 0 && !label.hidden && label.alpha > 0.1) {
            // 以 @ 开头 → 可能是用户名
            if ([text hasPrefix:@"@"]) {
                result[@"unique_id"] = text;
            }
            // 纯数字且长度 6-20 → 可能是抖音号
            if ([self _isNumeric:text] && text.length >= 6 && text.length <= 20) {
                result[@"aweme_number"] = text;
                result[@"aweme_id"] = text;
            }
        }
    }

    // accessibilityLabel
    NSString *accLabel = view.accessibilityLabel;
    if (accLabel.length > 0) {
        // 代理检测是否可点（登录按钮）
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

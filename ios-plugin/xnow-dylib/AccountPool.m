// AccountPool.m
// XNOW 账号池实现

#import "AccountPool.h"

static NSString *const kPoolKey = @"XN_AccountPool";
static NSString *const kActiveIdKey = @"XN_ActiveAccountId";

#define POOL_LOG(fmt, ...) NSLog(@"[XNOWER][Pool] " fmt, ##__VA_ARGS__)

@interface AccountPool ()
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *_accounts;
@end

@implementation AccountPool

static AccountPool *gShared = nil;

+ (AccountPool *)sharedPool {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gShared = [[self alloc] init];
    });
    return gShared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self _loadFromDisk];
    }
    return self;
}

#pragma mark - Persistence

- (void)_loadFromDisk {
    NSData *data = [[NSUserDefaults standardUserDefaults] objectForKey:kPoolKey];
    if (data) {
        NSError *err = nil;
        NSArray *arr = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
        if (arr && [arr isKindOfClass:[NSArray class]]) {
            __accounts = [NSMutableArray array];
            for (id item in arr) {
                if ([item isKindOfClass:[NSDictionary class]]) {
                    [__accounts addObject:[(NSDictionary *)item mutableCopy]];
                }
            }
        }
    }
    if (!__accounts) {
        __accounts = [NSMutableArray array];
    }
    POOL_LOG(@"从本地加载 %lu 个账号", (unsigned long)__accounts.count);
}

- (void)_saveToDisk {
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:__accounts options:0 error:&err];
    if (data) {
        [[NSUserDefaults standardUserDefaults] setObject:data forKey:kPoolKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    } else {
        POOL_LOG(@"保存失败: %@", err);
    }
}

#pragma mark - Public

- (NSArray<NSDictionary *> *)allAccounts {
    return [__accounts copy];
}

- (NSDictionary *)activeAccount {
    NSInteger activeId = [[NSUserDefaults standardUserDefaults] integerForKey:kActiveIdKey];
    if (activeId <= 0) return nil;
    return [self accountWithId:activeId];
}

- (NSInteger)count {
    return __accounts.count;
}

- (void)syncAccounts:(NSArray<NSDictionary *> *)accounts {
    [__accounts removeAllObjects];
    for (NSDictionary *acc in accounts) {
        NSMutableDictionary *m = [acc mutableCopy];
        if (!m[@"status"]) m[@"status"] = @"idle";
        [__accounts addObject:m];
    }
    [self _saveToDisk];
    POOL_LOG(@"同步 %lu 个账号到本地", (unsigned long)__accounts.count);
}

- (void)upsertAccount:(NSDictionary *)account {
    NSNumber *accId = account[@"id"];
    if (!accId) return;

    for (int i = 0; i < __accounts.count; i++) {
        if ([__accounts[i][@"id"] isEqualToNumber:accId]) {
            [__accounts[i] addEntriesFromDictionary:account];
            [self _saveToDisk];
            return;
        }
    }
    // 不存在则新增
    NSMutableDictionary *m = [account mutableCopy];
    if (!m[@"status"]) m[@"status"] = @"idle";
    [__accounts addObject:m];
    [self _saveToDisk];
}

- (void)removeAccountWithId:(NSInteger)accountId {
    [__accounts filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *acc, NSDictionary *bindings) {
        return [acc[@"id"] integerValue] != accountId;
    }]];
    [self _saveToDisk];
}

- (void)clearAll {
    [__accounts removeAllObjects];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kPoolKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kActiveIdKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    POOL_LOG(@"清空账号池");
}

- (NSDictionary *)accountWithId:(NSInteger)accountId {
    for (NSDictionary *acc in __accounts) {
        if ([acc[@"id"] integerValue] == accountId) return acc;
    }
    return nil;
}

- (NSDictionary *)accountWithAwemeNumber:(NSString *)number {
    for (NSDictionary *acc in __accounts) {
        if ([acc[@"aweme_number"] isEqualToString:number]) return acc;
    }
    return nil;
}

- (NSDictionary *)credentialsForAccountId:(NSInteger)accountId {
    NSDictionary *acc = [self accountWithId:accountId];
    if (!acc) return nil;

    NSMutableDictionary *creds = [NSMutableDictionary dictionary];
    if (acc[@"password"]) creds[@"password"] = acc[@"password"];
    if (acc[@"cookies"]) creds[@"cookies"] = acc[@"cookies"];
    if (acc[@"token"]) creds[@"token"] = acc[@"token"];
    return creds.count > 0 ? creds : nil;
}

- (void)markActive:(NSInteger)accountId {
    [[NSUserDefaults standardUserDefaults] setInteger:accountId forKey:kActiveIdKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self updateStatus:accountId status:AccountStatusActive];
}

- (void)updateStatus:(NSInteger)accountId status:(AccountStatus)status {
    for (NSMutableDictionary *acc in __accounts) {
        if ([acc[@"id"] integerValue] == accountId) {
            NSArray *names = @[@"idle", @"logging_in", @"active", @"failed", @"risk_control"];
            acc[@"status"] = (status >= 0 && status < names.count) ? names[status] : @"idle";
            acc[@"last_used"] = @([[NSDate date] timeIntervalSince1970]);
            [self _saveToDisk];
            return;
        }
    }
}

- (BOOL)hasCredentials:(NSInteger)accountId {
    NSDictionary *creds = [self credentialsForAccountId:accountId];
    return creds != nil;
}

@end

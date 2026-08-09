// CountryEnv.m
#import "CountryEnv.h"

static NSString *const kXNCountryEnvKey = @"XN_CountryEnv";

@implementation CountryEnv

/// 国家 -> 环境参数映射（region 码 / 时区 / 时区偏移秒 / 语言 / mcc_mnc）
+ (NSDictionary *)_envTable {
    static NSDictionary *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = @{
            @"美国":   @{@"region": @"US", @"tz": @"America/New_York",     @"tz_offset": @"-14400", @"lang": @"en", @"mcc_mnc": @"310410"},
            @"日本":   @{@"region": @"JP", @"tz": @"Asia/Tokyo",           @"tz_offset": @"32400",  @"lang": @"ja", @"mcc_mnc": @"44010"},
            @"英国":   @{@"region": @"GB", @"tz": @"Europe/London",        @"tz_offset": @"0",      @"lang": @"en", @"mcc_mnc": @"23420"},
            @"韩国":   @{@"region": @"KR", @"tz": @"Asia/Seoul",           @"tz_offset": @"32400",  @"lang": @"ko", @"mcc_mnc": @"45005"},
            @"新加坡": @{@"region": @"SG", @"tz": @"Asia/Singapore",       @"tz_offset": @"28800",  @"lang": @"en", @"mcc_mnc": @"52501"},
            @"台湾":   @{@"region": @"TW", @"tz": @"Asia/Taipei",          @"tz_offset": @"28800",  @"lang": @"zh-Hant", @"mcc_mnc": @"46692"},
            @"香港":   @{@"region": @"HK", @"tz": @"Asia/Hong_Kong",       @"tz_offset": @"28800",  @"lang": @"zh-Hant", @"mcc_mnc": @"45400"},
            @"德国":   @{@"region": @"DE", @"tz": @"Europe/Berlin",        @"tz_offset": @"3600",   @"lang": @"de", @"mcc_mnc": @"26201"},
            @"法国":   @{@"region": @"FR", @"tz": @"Europe/Paris",         @"tz_offset": @"3600",   @"lang": @"fr", @"mcc_mnc": @"20801"},
            @"泰国":   @{@"region": @"TH", @"tz": @"Asia/Bangkok",         @"tz_offset": @"25200",  @"lang": @"th", @"mcc_mnc": @"52001"},
            @"越南":   @{@"region": @"VN", @"tz": @"Asia/Ho_Chi_Minh",     @"tz_offset": @"25200",  @"lang": @"vi", @"mcc_mnc": @"45201"},
            @"马来西亚": @{@"region": @"MY", @"tz": @"Asia/Kuala_Lumpur",  @"tz_offset": @"28800",  @"lang": @"ms", @"mcc_mnc": @"50212"},
            @"印度尼西亚": @{@"region": @"ID", @"tz": @"Asia/Jakarta",     @"tz_offset": @"25200",  @"lang": @"id", @"mcc_mnc": @"51001"},
            @"菲律宾": @{@"region": @"PH", @"tz": @"Asia/Manila",          @"tz_offset": @"28800",  @"lang": @"en", @"mcc_mnc": @"51503"},
            @"澳大利亚": @{@"region": @"AU", @"tz": @"Australia/Sydney",   @"tz_offset": @"36000",  @"lang": @"en", @"mcc_mnc": @"50501"},
            @"加拿大": @{@"region": @"CA", @"tz": @"America/Toronto",      @"tz_offset": @"-14400", @"lang": @"en", @"mcc_mnc": @"302220"},
            @"巴西":   @{@"region": @"BR", @"tz": @"America/Sao_Paulo",   @"tz_offset": @"-10800", @"lang": @"pt", @"mcc_mnc": @"72402"},
            @"墨西哥": @{@"region": @"MX", @"tz": @"America/Mexico_City",  @"tz_offset": @"-21600", @"lang": @"es", @"mcc_mnc": @"33402"},
            @"西班牙": @{@"region": @"ES", @"tz": @"Europe/Madrid",        @"tz_offset": @"3600",   @"lang": @"es", @"mcc_mnc": @"21401"},
            @"意大利": @{@"region": @"IT", @"tz": @"Europe/Rome",          @"tz_offset": @"3600",   @"lang": @"it", @"mcc_mnc": @"22201"},
            @"荷兰":   @{@"region": @"NL", @"tz": @"Europe/Amsterdam",     @"tz_offset": @"3600",   @"lang": @"nl", @"mcc_mnc": @"20408"},
            @"俄罗斯": @{@"region": @"RU", @"tz": @"Europe/Moscow",        @"tz_offset": @"10800",  @"lang": @"ru", @"mcc_mnc": @"25001"},
            @"乌克兰": @{@"region": @"UA", @"tz": @"Europe/Kyiv",          @"tz_offset": @"7200",   @"lang": @"uk", @"mcc_mnc": @"25501"},
            @"印度":   @{@"region": @"IN", @"tz": @"Asia/Kolkata",         @"tz_offset": @"19800",  @"lang": @"en", @"mcc_mnc": @"40401"},
            @"巴基斯坦": @{@"region": @"PK", @"tz": @"Asia/Karachi",       @"tz_offset": @"18000",  @"lang": @"en", @"mcc_mnc": @"41001"},
            @"尼日利亚": @{@"region": @"NG", @"tz": @"Africa/Lagos",       @"tz_offset": @"3600",   @"lang": @"en", @"mcc_mnc": @"62120"},
            @"埃及":   @{@"region": @"EG", @"tz": @"Africa/Cairo",         @"tz_offset": @"7200",   @"lang": @"ar", @"mcc_mnc": @"60201"},
            @"南非":   @{@"region": @"ZA", @"tz": @"Africa/Johannesburg",  @"tz_offset": @"7200",   @"lang": @"en", @"mcc_mnc": @"65501"},
            @"沙特":   @{@"region": @"SA", @"tz": @"Asia/Riyadh",          @"tz_offset": @"10800",  @"lang": @"ar", @"mcc_mnc": @"42001"},
            @"阿联酋": @{@"region": @"AE", @"tz": @"Asia/Dubai",           @"tz_offset": @"14400",  @"lang": @"en", @"mcc_mnc": @"42402"},
        };
    });
    return s;
}

/// 国家中文名（含常见别名）-> 环境字典
+ (nullable NSDictionary *)envForCountry:(NSString *)countryName {
    if (!countryName.length) return nil;
    NSString *name = countryName;
    // 别名归一
    NSDictionary *alias = @{
        @"美区": @"美国", @"美西": @"美国", @"美东": @"美国", @"美国 🇺🇸": @"美国",
        @"迪拜": @"阿联酋", @"UAE": @"阿联酋", @"英国 🇬🇧": @"英国",
    };
    if (alias[name]) name = alias[name];
    return [self _envTable][name];
}

+ (nullable NSDictionary *)currentEnv {
    NSDictionary *env = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kXNCountryEnvKey];
    return (env && env.count) ? env : nil;
}

+ (BOOL)setCountry:(NSString *)countryName {
    NSDictionary *env = [self envForCountry:countryName];
    if (!env) return NO;
    NSMutableDictionary *stored = [env mutableCopy];
    stored[@"name"] = countryName;
    [[NSUserDefaults standardUserDefaults] setObject:stored forKey:kXNCountryEnvKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    return YES;
}

+ (void)clear {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kXNCountryEnvKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

/// 改写请求 query 里的 region 相关参数（只改已存在的，不新增，保守防抖）
+ (void)applyEnvToMutableRequest:(NSMutableURLRequest *)request {
    NSDictionary *env = [self currentEnv];
    if (!env) return;

    NSURL *url = request.URL;
    if (!url) return;
    NSURLComponents *comp = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSMutableArray<NSURLQueryItem *> *items = [comp.queryItems mutableCopy];
    if (!items) return;

    // 参数名 -> 环境字段（只处理已存在的参数）
    NSDictionary *fieldMap = @{
        @"device_region":      @"region",
        @"app_region":         @"region",
        @"sys_region":         @"region",
        @"region":             @"region",
        @"tz_name":            @"tz",
        @"timezone_offset":    @"tz_offset",
        @"app_language":       @"lang",
        @"sys_language":       @"lang",
        @"language":           @"lang",
        @"mcc_mnc":            @"mcc_mnc",
        @"carrier_region":     @"region",
    };

    BOOL changed = NO;
    static NSMutableDictionary *gLastRewrite = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ gLastRewrite = [NSMutableDictionary dictionary]; });
    [gLastRewrite removeAllObjects];
    for (NSUInteger i = 0; i < items.count; i++) {
        NSURLQueryItem *item = items[i];
        NSString *field = fieldMap[item.name];
        if (!field) continue;
        NSString *val = env[field];
        if (!val) continue;
        if (![item.value isEqualToString:val]) {
            items[i] = [NSURLQueryItem queryItemWithName:item.name value:val];
            gLastRewrite[item.name] = val;  // 记录改写快照（env_diag 诊断）
            changed = YES;
        }
    }
    if (changed) {
        comp.queryItems = items;
        request.URL = comp.URL;  // request 是 NSMutableURLRequest，直接改
    }
}

+ (NSDictionary *)lastRewrite {
    static NSMutableDictionary *gLastRewrite = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ gLastRewrite = [NSMutableDictionary dictionary]; });
    return [gLastRewrite copy];
}

@end

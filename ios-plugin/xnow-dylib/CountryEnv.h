// CountryEnv.h
// 环境伪装 — 国家环境参数映射与请求改写
// 用途：set_country 命令把设备上报的 region/时区/语言/MCC 伪装成目标国，
//       与出口 IP（加速器/小火箭）配合，形成一致的"目标国环境"。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CountryEnv : NSObject

/// 国家中文名 -> 环境字典 {region, tz, tz_offset, lang, mcc_mnc}
+ (nullable NSDictionary *)envForCountry:(NSString *)countryName;

/// 读取当前生效的环境（NSUserDefaults XN_CountryEnv），未设置返回 nil
+ (nullable NSDictionary *)currentEnv;

/// 设置目标国环境（解析 countryName 存 NSUserDefaults）；返回是否设置成功
+ (BOOL)setCountry:(NSString *)countryName;

/// 清除环境伪装
+ (void)clear;

/// 若已设置目标国，改写请求的 region 相关 query 参数（只改已存在的参数，保守不新增）
+ (void)applyEnvToMutableRequest:(NSMutableURLRequest *)request;

/// 最近一次改写过的请求参数快照（env_diag 诊断用）；未改写过返回 nil
+ (nullable NSDictionary *)lastRewrite;

@end

NS_ASSUME_NONNULL_END

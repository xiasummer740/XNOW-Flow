// TikTokHooks.h
// TikTok 运行时方法挂钩
// 通过 Objective-C runtime hook TikTok 关键方法实现监控和注入

#import <Foundation/Foundation.h>

@interface TikTokHooks : NSObject

/// 安装所有 hooks（应用启动时调用一次）
+ (void)installHooks;

/// v1.4.136 网络路径探针：记录最近观察到的 URL（XNOWURLProtocol 调用）
+ (void)_recordURL:(NSString *)url via:(NSString *)via;

/// v1.4.136 网络路径探针：XNOWURLProtocol 侧诊断（被询问/实际拦截计数 + 最近 URL）
+ (NSDictionary *)xnowURLProtocolNetDiag;

/// v1.4.136 网络路径探针：NSURLSession swizzle 侧诊断（命中计数 + 最近 URL）
+ (NSDictionary *)nsurlSessionNetDiag;

/// v1.4.138 net_sniff 时间盒抓包：开始（清空缓冲，开始记录所有 URL）
+ (void)sniffBegin;

/// v1.4.138 net_sniff 时间盒抓包：抓包期间记录一个 URL（三个观察点调用）
+ (void)sniffRecord:(NSString *)url;

/// v1.4.138 net_sniff 时间盒抓包：结束，按 host 聚合返回
+ (NSDictionary *)sniffCollect;

/// 缓存的 feed 视频列表（供 collect_videos / net_diag 使用）
+ (NSArray *)cachedVideos;

@end

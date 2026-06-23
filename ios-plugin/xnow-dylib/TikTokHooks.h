// TikTokHooks.h
// TikTok 运行时方法挂钩
// 通过 Objective-C runtime hook TikTok 关键方法实现监控和注入

#import <Foundation/Foundation.h>

@interface TikTokHooks : NSObject

/// 安装所有 hooks（应用启动时调用一次）
+ (void)installHooks;

@end

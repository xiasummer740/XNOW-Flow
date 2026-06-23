// DeviceStatus.h
// 设备状态采集器 - 采集并上报手机运行状态

#import <Foundation/Foundation.h>

@interface DeviceStatus : NSObject

/// 开始监控（启动定时采集）
- (void)startMonitoring;
/// 停止监控
- (void)stopMonitoring;
/// 采集当前设备状态
- (NSDictionary *)collectStatus;
/// 当前活跃应用
@property (nonatomic, copy) NSString *currentApp;
/// TikTok 版本号
@property (nonatomic, copy) NSString *tiktokVersion;

@end

// DeviceStatus.m
// 设备状态采集器实现

#import "DeviceStatus.h"
#import <UIKit/UIKit.h>
#import <sys/utsname.h>
#import <mach/mach.h>

@interface DeviceStatus ()
@property (nonatomic, strong) NSTimer *monitorTimer;
@end

@implementation DeviceStatus

- (instancetype)init {
    self = [super init];
    if (self) {
        _currentApp = @"TikTok";
        _tiktokVersion = @"--";
    }
    return self;
}

- (void)startMonitoring {
    // 不需要定时器，状态在心跳时按需采集
}

- (void)stopMonitoring {
    [self.monitorTimer invalidate];
    self.monitorTimer = nil;
}

- (NSDictionary *)collectStatus {
    UIDevice *device = [UIDevice currentDevice];

    // 电池
    [device setBatteryMonitoringEnabled:YES];
    float batteryLevel = device.batteryLevel;
    if (batteryLevel < 0) batteryLevel = 100; // 模拟器
    int batteryPercent = (int)(batteryLevel * 100);

    // 设备型号
    NSString *deviceModel = [self deviceModelName];

    // 内存使用
    int memoryUsage = [self _memoryUsagePercent];
    int diskUsage = [self _diskUsagePercent];

    // 信号强度（iOS 不提供公开 API，返回模拟值）
    int signalStrength = 4;

    return @{
        @"battery": @(batteryPercent),
        @"signal": @(signalStrength),
        @"memory": @(memoryUsage),
        @"disk": @(diskUsage),
        @"current_app": self.currentApp ?: @"TikTok",
        @"tiktok_version": self.tiktokVersion ?: @"--",
        @"device_model": deviceModel,
        @"ios_version": device.systemVersion ?: @"--",
        @"current_page": self.currentPage ?: @"unknown",
    };
}

- (NSString *)currentPage {
    // 通过 UIViewController 获取当前页面
    __block NSString *page = @"unknown";
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIViewController *top = [self _topViewController];
        if (top) {
            NSString *className = NSStringFromClass([top class]);
            if ([className containsString:@"Feed"] || [className containsString:@"Main"]) {
                page = @"feed";
            } else if ([className containsString:@"Profile"]) {
                page = @"profile";
            } else if ([className containsString:@"Comment"]) {
                page = @"comment";
            } else if ([className containsString:@"Search"]) {
                page = @"search";
            } else if ([className containsString:@"Video"] || [className containsString:@"Player"]) {
                page = @"video_detail";
            } else {
                page = className;
            }
        }
    });
    return page;
}

// ======== 辅助方法 ========

- (NSString *)deviceModelName {
    struct utsname systemInfo;
    uname(&systemInfo);
    return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding]
           ?: [[UIDevice currentDevice] model];
}

- (int)_memoryUsagePercent {
    mach_port_t host_port = mach_host_self();
    mach_msg_type_number_t host_size = sizeof(vm_statistics_data_t) / sizeof(integer_t);
    vm_size_t page_size;
    vm_statistics_data_t vm_stat;

    host_page_size(host_port, &page_size);
    if (host_statistics(host_port, HOST_VM_INFO,
                        (host_info_t)&vm_stat, &host_size) != KERN_SUCCESS) {
        return 50;
    }

    natural_t used = vm_stat.active_count + vm_stat.wire_count + vm_stat.inactive_count;
    natural_t total = used + vm_stat.free_count;
    return total > 0 ? (int)(used * 100 / total) : 50;
}

- (int)_diskUsagePercent {
    NSError *error = nil;
    NSDictionary *attrs = [[NSFileManager defaultManager]
                           attributesOfFileSystemForPath:NSHomeDirectory()
                           error:&error];
    if (error) return 50;

    NSNumber *total = attrs[NSFileSystemSize];
    NSNumber *free = attrs[NSFileSystemFreeSize];
    if (total && free) {
        long long used = [total longLongValue] - [free longLongValue];
        return (int)(used * 100 / [total longLongValue]);
    }
    return 50;
}

- (UIViewController *)_topViewController {
    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
    return [self _topFrom:root];
}

- (UIViewController *)_topFrom:(UIViewController *)vc {
    if (vc.presentedViewController) {
        return [self _topFrom:vc.presentedViewController];
    } else if ([vc isKindOfClass:[UINavigationController class]]) {
        return [self _topFrom:[(UINavigationController *)vc topViewController]];
    } else if ([vc isKindOfClass:[UITabBarController class]]) {
        return [self _topFrom:[(UITabBarController *)vc selectedViewController]];
    }
    return vc;
}

@end

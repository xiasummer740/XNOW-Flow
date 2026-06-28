// XNStartup.m
// 用 CFRunLoopTimer 替代 pthread + dispatch_async 触发启动
// 在 dylib 加载阶段 GCD 的 main queue 可能不可用
// CFRunLoop 初始化最早，是最可靠的延迟执行机制

#import "XNOWER.h"
#import <CoreFoundation/CoreFoundation.h>

@interface XNStartup : NSObject
@end

@implementation XNStartup

// libobjc 在 dyld add_image 时调用 +load
+ (void)load {
    // 用 CFRunLoopTimer 替代 pthread+dispatch_async
    // CFRunLoop 在进程早期就初始化了，比 GCD 更可靠
    CFRunLoopTimerRef timer = CFRunLoopTimerCreate(
        kCFAllocatorDefault,
        CFAbsoluteTimeGetCurrent() + 5.0,  // 5 秒后触发
        0, 0, 0,
        xnow_startup_callback,
        NULL
    );
    if (timer) {
        CFRunLoopAddTimer(CFRunLoopGetMain(), timer, kCFRunLoopCommonModes);
        CFRelease(timer);
    }
}

/// CFRunLoop 定时器回调
static void xnow_startup_callback(CFRunLoopTimerRef timer, void *info) {
    [[XNOWER sharedInstance] start];
}

@end

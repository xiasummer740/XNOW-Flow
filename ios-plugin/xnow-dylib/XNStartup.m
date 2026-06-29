// XNStartup.m
// 多层启动机制：保证在任意加载时机都能触发 start()
//
// 问题：dylib 被 dyld 加载时 +load 执行，此时 GCD/UIKit/runloop 可能未就绪
// 方案：+load 中创建 pthread 线程，等 5 秒后用 CFRunLoopPerformBlock 调度到主线程
//       CFRunLoopPerformBlock 不依赖 GCD，通过直接操作 runloop source 投递block
//       CFRunLoopWakeUp 确保主 runloop 立即处理该 block
//
// 历史尝试 & 失败原因:
//   - dispatch_async(main_queue)      → GCD 主队列在启动早期不可用
//   - CFRunLoopTimer                  → 必须等主 runloop 运行后才触发
//   - dispatch_after(global_queue)    → start() 在后台线程跑，UIKit 调用危险
//   - pthread + dispatch_async        → 5 秒后 GCD 主队列仍可能不服务 block
//   当前：pthread + CFRunLoopPerformBlock → 最可靠，不依赖 GCD/runloop 状态

#import "XNOWER.h"
#import <pthread.h>

@interface XNStartup : NSObject
@end

@implementation XNStartup

// libobjc 在 dyld add_image 时调用 +load
+ (void)load {
    // 方法1: pthread + CFRunLoopPerformBlock（主方案）
    static pthread_t thread;
    if (pthread_create(&thread, NULL, xnow_startup_thread, NULL) == 0) {
        pthread_detach(thread);
    }

    // 方法2: CFRunLoopTimer（备用，和 pthread 双保险）
    CFRunLoopTimerRef timer = CFRunLoopTimerCreate(
        kCFAllocatorDefault,
        CFAbsoluteTimeGetCurrent() + 7.0,
        0, 0, 0,
        xnow_startup_callback,
        NULL
    );
    if (timer) {
        CFRunLoopAddTimer(CFRunLoopGetMain(), timer, kCFRunLoopCommonModes);
        CFRelease(timer);
    }
}

/// 主方案: pthread 线程，等 app 就绪后用 CFRunLoopPerformBlock 调度到主线程
static void *xnow_startup_thread(void *arg) {
    sleep(5);  // 等 UIApplicationMain 完成 + UIKit 就绪

    // CFRunLoopPerformBlock 直接投递 block 到主 runloop
    // 不经过 GCD，不依赖 dispatch_main_queue 的状态
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopDefaultMode, ^{
        [[XNOWER sharedInstance] start];
    });

    // 唤醒主 runloop 立即处理我们投递的 block
    // 如果 runloop 正在休眠（等待事件），CFRunLoopWakeUp 会唤醒它
    CFRunLoopWakeUp(CFRunLoopGetMain());

    return NULL;
}

/// 备用方案: CFRunLoopTimer 回调（如果 +load 时 main runloop 已运行）
static void xnow_startup_callback(CFRunLoopTimerRef timer, void *info) {
    // 如果 pthread 已经触发过 start()，这里 [[XNOWER sharedInstance] start]
    // 再次调用是安全的（start 内部有 dispatch_once 等防护）
    [[XNOWER sharedInstance] start];
}

@end

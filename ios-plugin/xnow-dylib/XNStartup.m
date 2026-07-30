// XNStartup.m
// 双层启动机制 — 保证 dylib 加载后 start() 必执行
//
// 方案：+load 中同时启动两条路径（互备）:
//   1. pthread + CFRunLoopPerformBlock — 不依赖 GCD，最可靠
//   2. CFRunLoopTimer — 若主 runloop 已运行则直接触发
// 两条路径中先执行的触发 start()，后执行的被 dispatch_once 挡住

#import "XNOWER.h"
#import "XNURLProtocol.h"
#import <pthread.h>

@interface XNStartup : NSObject
@end

@implementation XNStartup

+ (void)load {
    NSLog(@"[XNOWER] +load 执行 — 启动双层启动机制");

    // 注册 NSURLProtocol — 用 TikTok 的网络栈做 piggyback 通信
    // 注册顺序: 先注册的优先处理，XNURLProtocol 只处理 feed/recommend，
    // 其他 TikTok 请求仍由 TikTokHooks 中的 XNOWURLProtocol 处理
    [NSURLProtocol registerClass:[XNURLProtocol class]];
    NSLog(@"[XNOWER] XNURLProtocol 已注册（piggyback 通信）");

    // 路径1: pthread 线程，2秒后用 CFRunLoopPerformBlock 投递到主线程
    static pthread_t thread;
    if (pthread_create(&thread, NULL, xnow_startup_thread, NULL) == 0) {
        pthread_detach(thread);
        NSLog(@"[XNOWER] pthread 启动线程已创建");
    } else {
        NSLog(@"[XNOWER] ⚠️ pthread 创建失败");
    }

    // 路径2: CFRunLoopTimer — 如果主 runloop 已经在运行，3秒后触发
    CFRunLoopTimerRef timer = CFRunLoopTimerCreate(
        kCFAllocatorDefault,
        CFAbsoluteTimeGetCurrent() + 3.0,
        0, 0, 0,
        xnow_startup_callback,
        NULL
    );
    if (timer) {
        CFRunLoopAddTimer(CFRunLoopGetMain(), timer, kCFRunLoopCommonModes);
        CFRelease(timer);
        NSLog(@"[XNOWER] CFRunLoopTimer 已注册（7秒后触发）");
    } else {
        NSLog(@"[XNOWER] ⚠️ CFRunLoopTimer 创建失败");
    }
}

/// 路径1: 后台线程 → 等 UIApplicationMain 完成 → CFRunLoopPerformBlock
static void *xnow_startup_thread(void *arg) {
    sleep(2);  // 等 UIKit 就绪

    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopDefaultMode, ^{
        NSLog(@"[XNOWER] ⏰ pthread → start() 触发");
        [[XNOWER sharedInstance] start];
    });

    CFRunLoopWakeUp(CFRunLoopGetMain());
    return NULL;
}

/// 路径2: CFRunLoopTimer 回调（备用，若主 runloop 已运行则先触发）
static void xnow_startup_callback(CFRunLoopTimerRef timer, void *info) {
    NSLog(@"[XNOWER] ⏰ CFRunLoopTimer → start() 触发");
    [[XNOWER sharedInstance] start];
}

@end

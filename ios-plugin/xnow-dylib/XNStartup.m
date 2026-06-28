// XNStartup.m
// 用 +load 替代 __attribute__((constructor)) 触发插件启动
// +load 由 libobjc 通过 dyld add_image 回调触发，不依赖 __mod_init_func

#import "XNOWER.h"
#import <pthread.h>

@interface XNStartup : NSObject
@end

@implementation XNStartup

// libobjc 在 dyld add_image 时调用 +load
// 它走的是 _dyld_register_func_for_add_image 回调，不是 __mod_init_func
+ (void)load {
    // 优先用 pthread 创建独立线程（最可靠，不依赖任何运行时系统）
    static pthread_t thread;
    if (pthread_create(&thread, NULL, xnow_startup_thread, NULL) == 0) {
        pthread_detach(thread);
    }
}

/// pthread 线程入口
static void *xnow_startup_thread(void *arg) {
    sleep(5);  // 等 UIApplicationMain 完成
    dispatch_async(dispatch_get_main_queue(), ^{
        [[XNOWER sharedInstance] start];
    });
    return NULL;
}

@end

//
//  MinimalTester.m — 最简 dylib，只写一个文件到 /tmp 证明被加载了
//
#import <Foundation/Foundation.h>

__attribute__((constructor)) static void MinimalLoad() {
    // 尝试写文件（不需要任何 framework）
    NSString *msg = @"XNOWER dylib loaded!\n";
    [msg writeToFile:@"/tmp/xnower_loaded.txt"
          atomically:YES
            encoding:NSUTF8StringEncoding
               error:nil];

    // 延时 5 秒再写一个，证明代码跑起来了
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSString *msg2 = @"XNOWER 5s after launch!\n";
        [msg2 writeToFile:@"/tmp/xnower_5s.txt"
               atomically:YES
                 encoding:NSUTF8StringEncoding
                    error:nil];
    });
}

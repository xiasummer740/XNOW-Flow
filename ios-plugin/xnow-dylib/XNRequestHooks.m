// XNRequestHooks.m
// XNOW 请求钩子（v1.4.141 net_request）— 路线 B 直取：hook 字节自研网络栈的请求模型
//
// 设计要点：
// 1. 用 method_setImplementation 替换请求模型类的 setter IMP（不是 swizzle 交换，
//    保留原 IMP 指针，先调原实现再记录 —— 不破坏 TikTok 请求构造）。
// 2. 只记录"构造请求时的调用序列"（setUrl/setMethod/setBody/setHeaders），不关联实例，
//    因为一次请求通常按 setUrl→setMethod→setHeaders→setBody 顺序构造，序列可读可拼。
// 3. 线程安全：setter 可在任意线程被调，全部 NSLock 保护；record 只用内存操作，绝不 I/O。
// 4. 时间盒模式：beginCapture 清空记录开始，captureCollect 停止并返回序列。
// 5. 记录上限 200 条防爆；value 截断控体积。

#import "XNRequestHooks.h"
#import <objc/runtime.h>

// XOR(0x5A) 解码：dylib 内不存 TikTok 私有类名明文，运行时还原（防反 hook 检测扫描 Swift 网络层命名空间）。
// noinline + volatile 三重保险：阻止 clang -O2 常量折叠——实测折叠会把解码结果当明文分块写进 __literals 常量池，
// 等于没混淆（v1.4.142 编译后 grep dylib 仍见 PNSFoundationImpl.PNSNetworkHTTP 碎片，根因在此）。
static NSString *xnDecodeXOR(const char *enc) __attribute__((noinline));
static NSString *xnDecodeXOR(const char *enc) {
    NSUInteger len = strlen(enc);
    volatile unsigned char key = 0x5A;
    NSMutableData *md = [NSMutableData dataWithLength:len];
    unsigned char *out = (unsigned char *)md.mutableBytes;
    const volatile unsigned char *p = (const volatile unsigned char *)enc;
    for (NSUInteger i = 0; i < len; i++) out[i] = (unsigned char)p[i] ^ key;
    return [[NSString alloc] initWithData:md encoding:NSUTF8StringEncoding];
}

static BOOL sInstalled = NO;
static BOOL sCaptureActive = NO;
static NSMutableArray *sRecords;      // [{op, value}]
static NSMutableDictionary *sCallCounts;  // op -> 累计次数（不管是否 capture 都计，看类活跃度）
static NSLock *sLock;

// 原 IMP（方法签名：setter 都是 (id, SEL, id...)）
static IMP orig_setUrl;
static IMP orig_setHttpMethod;
static IMP orig_setHttpBody;
static IMP orig_setAllHeaders;
static IMP orig_addHeader;

// 记录一条 op。capture 激活时进 records；calls 计数总是累加（类活跃度探针）。
static void xn_recordOp(NSString *op, NSString *value) {
    [sLock lock];
    sCallCounts[op] = @([sCallCounts[op] integerValue] + 1);
    if (sCaptureActive) {
        if (sRecords.count >= 200) [sRecords removeObjectAtIndex:0];
        [sRecords addObject:@{@"op": op, @"value": value ?: @""}];
    }
    [sLock unlock];
}

// 值转可读字符串：NSURL→absoluteString，NSData→utf8/base64，NSDictionary→key=value 行，其余 description。截断控体积。
static NSString *xn_value(id obj) {
    if (!obj) return @"";
    if ([obj isKindOfClass:[NSURL class]]) {
        NSString *s = [(NSURL *)obj absoluteString];
        return s.length > 600 ? [s substringToIndex:600] : s;
    }
    if ([obj isKindOfClass:[NSData class]]) {
        NSString *s = [[NSString alloc] initWithData:(NSData *)obj encoding:NSUTF8StringEncoding];
        if (s) return s.length > 1000 ? [s substringToIndex:1000] : s;
        NSString *b64 = [(NSData *)obj base64EncodedStringWithOptions:0];
        return b64.length > 400 ? [b64 substringToIndex:400] : b64;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableString *ms = [NSMutableString string];
        [(NSDictionary *)obj enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) {
            [ms appendFormat:@"%@=%@\n", k, v];
            if (ms.length >= 1400) { [ms deleteCharactersInRange:NSMakeRange(1400, ms.length - 1400)]; *stop = YES; }
        }];
        return ms;
    }
    NSString *s = [obj description];
    return s.length > 800 ? [s substringToIndex:800] : s;
}

// ── 替换后的 setter：先调原实现，再记录传入值 ──
static void xn_setUrl(id self, SEL _cmd, id url) {
    ((void (*)(id, SEL, id))orig_setUrl)(self, _cmd, url);
    NSString *u = [url isKindOfClass:[NSURL class]] ? [url absoluteString] : [url description];
    xn_recordOp(@"setUrl", u);
}
static void xn_setHttpMethod(id self, SEL _cmd, id method) {
    ((void (*)(id, SEL, id))orig_setHttpMethod)(self, _cmd, method);
    xn_recordOp(@"setMethod", method ? [method description] : @"");
}
static void xn_setHttpBody(id self, SEL _cmd, id body) {
    ((void (*)(id, SEL, id))orig_setHttpBody)(self, _cmd, body);
    xn_recordOp(@"setBody", xn_value(body));
}
static void xn_setAllHeaders(id self, SEL _cmd, id headers) {
    ((void (*)(id, SEL, id))orig_setAllHeaders)(self, _cmd, headers);
    xn_recordOp(@"setHeaders", xn_value(headers));
}
static void xn_addHeader(id self, SEL _cmd, id v, id k) {
    ((void (*)(id, SEL, id, id))orig_addHeader)(self, _cmd, v, k);
    xn_recordOp(@"addHeader", [NSString stringWithFormat:@"%@ = %@", k, v]);
}

// 替换类方法 IMP。找不到方法返回 NO（不炸）。
static BOOL xn_replaceIMP(Class cls, SEL sel, IMP newIMP, IMP *oldIMP) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NO;
    *oldIMP = method_getImplementation(m);
    method_setImplementation(m, newIMP);
    return YES;
}

@implementation XNRequestHooks

+ (void)install {
    if (sInstalled) return;
    Class cls = NSClassFromString(xnDecodeXOR("\x0a\x14\x09\x1c\x35\x2f\x34\x3e\x3b\x2e\x33\x35\x34\x13\x37\x2a\x36\x74\x0a\x14\x09\x14\x3f\x2e\x2d\x35\x28\x31\x12\x0e\x0e\x0a\x1c\x33\x36\x2e\x3f\x28\x08\x3f\x2b\x2f\x3f\x29\x2e"));
    if (!cls) {
        NSLog(@"[XNOW] 请求模型未加载，等下次再装");
        return;  // Swift 类懒加载，beginCapture 会再试
    }
    sLock = [NSLock new];
    sRecords = [NSMutableArray array];
    sCallCounts = [NSMutableDictionary dictionary];

    int ok = 0;
    if (xn_replaceIMP(cls, @selector(setUrl:), (IMP)xn_setUrl, &orig_setUrl)) ok++;
    if (xn_replaceIMP(cls, @selector(setHttpMethod:), (IMP)xn_setHttpMethod, &orig_setHttpMethod)) ok++;
    if (xn_replaceIMP(cls, @selector(setHttpBody:), (IMP)xn_setHttpBody, &orig_setHttpBody)) ok++;
    if (xn_replaceIMP(cls, @selector(setAllHTTPHeaderFields:), (IMP)xn_setAllHeaders, &orig_setAllHeaders)) ok++;
    if (xn_replaceIMP(cls, @selector(addValue:forHTTPHeaderField:), (IMP)xn_addHeader, &orig_addHeader)) ok++;
    sInstalled = ok > 0;
    NSLog(@"[XNOW] 请求钩子安装 %d/5", ok);
}

+ (void)beginCapture {
    if (!sInstalled) [self install];  // 类加载后再补装一次
    if (!sInstalled) return;
    [sLock lock];
    [sRecords removeAllObjects];
    [sCallCounts removeAllObjects];
    sCaptureActive = YES;
    [sLock unlock];
}

+ (NSDictionary *)captureCollect {
    [sLock lock];
    sCaptureActive = NO;
    NSDictionary *snap = @{
        @"installed": @(sInstalled),
        @"calls": [sCallCounts copy] ?: @{},
        @"records": [sRecords copy] ?: @[],
    };
    [sLock unlock];
    return snap;
}

@end

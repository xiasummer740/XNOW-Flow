// SocketHooks.m
// XNOW socket/TLS 钩子（v1.4.140 net_socket）— 路线 B 关键突破点
//
// 设计要点：
// 1. fishhook rebind POSIX socket + TLS 两层。SwiftNIO/任何网络栈最终都调 C 函数。
// 2. TLS 层 hook 拿到的 buf 是【解密后明文】→ 能看到完整 HTTP 请求（URL/headers/签名参数）。
// 3. 线程安全：hook 回调可在任意线程，全部走 NSLock 保护。
// 4. 绝不递归：recordData 只用内存操作（字典+锁），不用任何 I/O（NSLog/write/fprintf 都不碰）。
// 5. 时间盒模式：beginCapture 清空缓冲开始记录，captureCollect 停止并聚合。

#import "SocketHooks.h"
#import "fishhook.h"
#import <sys/socket.h>
#import <netdb.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <dlfcn.h>
#import <Security/Security.h>

// ── 原函数指针（rebind 后指向真实实现）──
static int (*orig_connect)(int, const struct sockaddr *, socklen_t);
static ssize_t (*orig_send)(int, const void *, size_t, int);
static ssize_t (*orig_sendto)(int, const void *, size_t, int, const struct sockaddr *, socklen_t);
static ssize_t (*orig_write)(int, const void *, size_t);
static ssize_t (*orig_recv)(int, void *, size_t, int);
static ssize_t (*orig_recvfrom)(int, void *, size_t, int, struct sockaddr *, socklen_t *);
static ssize_t (*orig_read)(int, void *, size_t);
static int (*orig_SSL_write)(void *, const void *, int);
static int (*orig_SSL_read)(void *, void *, int);
static OSStatus (*orig_SSLWrite)(void *, const void *, size_t *);
static OSStatus (*orig_SSLRead)(void *, void *, size_t *);

// ── 抓包状态 ──
static BOOL sCaptureActive = NO;
static NSMutableDictionary *sFdHost;    // fd(NSNumber) -> "host:port"
static NSMutableDictionary *sByHost;    // "host:port" -> {sent_bytes, recv_bytes, sends[], recvs[]}
static NSMutableArray *sConnects;       // 去重后的 connect 列表
static NSLock *sLock;

// fd 复用：关闭后 fd 可能被新连接复用。记录 [fd -> "host"] 但允许覆盖。
static void xnRecordConnect(int fd, const struct sockaddr *addr, socklen_t len) {
    if (!addr || len == 0) return;
    char host[NI_MAXHOST] = "", port[NI_MAXSERV] = "";
    if (getnameinfo(addr, len, host, sizeof(host), port, sizeof(port),
                    NI_NUMERICHOST | NI_NUMERICSERV) != 0) return;
    NSString *hp = [NSString stringWithFormat:@"%s:%s", host, port];
    [sLock lock];
    sFdHost[@(fd)] = hp;
    if (![sConnects containsObject:hp]) [sConnects addObject:hp];
    [sLock unlock];
}

// 数据样本：前 200 字节可打印 ASCII（非可打印→.），\r\n 转义。判断是否明文 HTTP 用。
static NSString *xnSample(const void *buf, size_t len) {
    size_t n = len < 200 ? len : 200;
    const unsigned char *p = buf;
    NSMutableString *s = [NSMutableString stringWithCapacity:n + 8];
    for (size_t i = 0; i < n; i++) {
        unsigned char c = p[i];
        if (c >= 32 && c < 127) [s appendFormat:@"%c", c];
        else if (c == '\r') [s appendString:@"<CR>"];
        else if (c == '\n') [s appendString:@"<LF>"];
        else [s appendString:@"."];
    }
    return s;
}

static void xnRecordData(int fd, NSString *dir, const void *buf, size_t len) {
    [sLock lock];
    if (!sCaptureActive || !buf || len == 0) { [sLock unlock]; return; }
    NSString *hp = sFdHost[@(fd)] ?: @"unknown";
    NSMutableDictionary *host = sByHost[hp];
    if (!host) {
        host = [NSMutableDictionary dictionaryWithDictionary:@{
            @"sent_bytes": @(0), @"recv_bytes": @(0),
            @"sends": [NSMutableArray array], @"recvs": [NSMutableArray array],
        }];
        sByHost[hp] = host;
    }
    BOOL isSend = [dir hasPrefix:@"send"];
    NSString *keyBytes = isSend ? @"sent_bytes" : @"recv_bytes";
    host[keyBytes] = @([host[keyBytes] longLongValue] + (long long)len);
    NSMutableArray *samples = isSend ? host[@"sends"] : host[@"recvs"];
    if (samples.count < 4) {  // 每 host 每方向最多 4 条样本，控体积
        [samples addObject:@{@"len": @(len), @"data": xnSample(buf, len)}];
    }
    [sLock unlock];
}

// TLS：从 SSL 对象拿底层 fd（BoringSSL/OpenSSL 有 SSL_get_fd；拿不到就归 "tls" 组）
static int xnSSLGetFD(const void *ssl) {
    if (!ssl) return -1;
    extern int SSL_get_fd(const void *ssl);
    static dispatch_once_t once;
    static int (*fp)(const void *);
    dispatch_once(&once, ^{ fp = dlsym(RTLD_DEFAULT, "SSL_get_fd"); });
    if (!fp) return -1;
    return fp(ssl);
}

// ── hook 实现 ──
static int my_connect(int fd, const struct sockaddr *addr, socklen_t len) {
    int r = orig_connect(fd, addr, len);
    xnRecordConnect(fd, addr, len);
    return r;
}
static ssize_t my_send(int fd, const void *buf, size_t len, int flags) {
    ssize_t r = orig_send(fd, buf, len, flags);
    xnRecordData(fd, @"send", buf, r > 0 ? (size_t)r : len);
    return r;
}
static ssize_t my_sendto(int fd, const void *buf, size_t len, int flags, const struct sockaddr *to, socklen_t tolen) {
    ssize_t r = orig_sendto(fd, buf, len, flags, to, tolen);
    if (to) xnRecordConnect(fd, to, tolen);
    xnRecordData(fd, @"send", buf, r > 0 ? (size_t)r : len);
    return r;
}
static ssize_t my_write(int fd, const void *buf, size_t len) {
    ssize_t r = orig_write(fd, buf, len);
    xnRecordData(fd, @"send", buf, r > 0 ? (size_t)r : len);
    return r;
}
static ssize_t my_recv(int fd, void *buf, size_t len, int flags) {
    ssize_t r = orig_recv(fd, buf, len, flags);
    if (r > 0) xnRecordData(fd, @"recv", buf, (size_t)r);
    return r;
}
static ssize_t my_recvfrom(int fd, void *buf, size_t len, int flags, struct sockaddr *from, socklen_t *fromlen) {
    ssize_t r = orig_recvfrom(fd, buf, len, flags, from, fromlen);
    if (r > 0) xnRecordData(fd, @"recv", buf, (size_t)r);
    return r;
}
static ssize_t my_read(int fd, void *buf, size_t len) {
    ssize_t r = orig_read(fd, buf, len);
    if (r > 0) xnRecordData(fd, @"recv", buf, (size_t)r);
    return r;
}
// BoringSSL/OpenSSL：buf 是解密后明文
static int my_SSL_write(void *ssl, const void *buf, int num) {
    int r = orig_SSL_write(ssl, buf, num);
    int fd = xnSSLGetFD(ssl);
    if (fd >= 0) xnRecordData(fd, @"send", buf, r > 0 ? (size_t)r : (size_t)num);
    else         xnRecordData(-1, @"send", buf, r > 0 ? (size_t)r : (size_t)num);
    return r;
}
static int my_SSL_read(void *ssl, void *buf, int num) {
    int r = orig_SSL_read(ssl, buf, num);
    int fd = xnSSLGetFD(ssl);
    if (r > 0) {
        if (fd >= 0) xnRecordData(fd, @"recv", buf, (size_t)r);
        else         xnRecordData(-1, @"recv", buf, (size_t)r);
    }
    return r;
}
// SecureTransport：无 fd 直取，归 "tls" 组
static OSStatus my_SSLWrite(void *ctx, const void *data, size_t *dataLength) {
    OSStatus r = orig_SSLWrite(ctx, data, dataLength);
    if (*dataLength > 0) xnRecordData(-1, @"send", data, *dataLength);
    return r;
}
static OSStatus my_SSLRead(void *ctx, void *data, size_t *dataLength) {
    OSStatus r = orig_SSLRead(ctx, data, dataLength);
    if (r == 0 && *dataLength > 0) xnRecordData(-1, @"recv", data, *dataLength);
    return r;
}

@implementation SocketHooks

+ (void)install {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sLock = [NSLock new];
        sFdHost = [NSMutableDictionary dictionary];
        sByHost = [NSMutableDictionary dictionary];
        sConnects = [NSMutableArray array];

        struct rebinding bindings[] = {
            {"connect",    (void *)my_connect,    (void **)&orig_connect},
            {"send",       (void *)my_send,       (void **)&orig_send},
            {"sendto",     (void *)my_sendto,     (void **)&orig_sendto},
            {"write",      (void *)my_write,      (void **)&orig_write},
            {"recv",       (void *)my_recv,       (void **)&orig_recv},
            {"recvfrom",   (void *)my_recvfrom,   (void **)&orig_recvfrom},
            {"read",       (void *)my_read,       (void **)&orig_read},
            {"SSL_write",  (void *)my_SSL_write,  (void **)&orig_SSL_write},
            {"SSL_read",   (void *)my_SSL_read,   (void **)&orig_SSL_read},
            {"SSLWrite",   (void *)my_SSLWrite,   (void **)&orig_SSLWrite},
            {"SSLRead",    (void *)my_SSLRead,    (void **)&orig_SSLRead},
        };
        rebind_symbols(bindings, sizeof(bindings) / sizeof(bindings[0]));
    });
}

+ (void)beginCapture {
    [sLock lock];
    [sByHost removeAllObjects];
    [sConnects removeAllObjects];
    sCaptureActive = YES;
    [sLock unlock];
}

+ (NSDictionary *)captureCollect {
    [sLock lock];
    sCaptureActive = NO;
    NSDictionary *snap = @{
        @"connects": [sConnects copy],
        @"by_host":  [sByHost copy],
    };
    [sLock unlock];
    return snap;
}

// v1.4.143 TLS 栈诊断探针（方向3）：SSL_* 符号是否在动态符号表 + fishhook 是否重绑成功。
// 若 SSL_write 返回 NULL → BoringSSL 静态链接进二进制、符号未导出 → fishhook 够不着（实测 0 命中根因）。
+ (NSDictionary *)tlsProbe {
    void *p1 = dlsym(RTLD_DEFAULT, "SSL_write");
    void *p2 = dlsym(RTLD_DEFAULT, "SSL_read");
    void *p3 = dlsym(RTLD_DEFAULT, "SSL_get_fd");
    void *p4 = dlsym(RTLD_DEFAULT, "SSLWrite");
    void *p5 = dlsym(RTLD_DEFAULT, "SSLRead");
    NSString *note;
    if (!p1) {
        note = @"SSL_write 不在动态符号表（静态链接内部，未导出）→ fishhook 够不着，符合 BoringSSL 静态链接推断";
    } else if (orig_SSL_write) {
        note = @"SSL_write 在动态符号表且 fishhook 已重绑，0 命中 = 调用点不走 PLT（内部 BL/内联直调）";
    } else {
        note = @"SSL_write 在动态符号表但 fishhook 重绑后 orig 为 NULL（rebind 未生效？）";
    }
    return @{
        @"SSL_write":  p1 ? [NSString stringWithFormat:@"%p", p1] : @"NULL",
        @"SSL_read":   p2 ? [NSString stringWithFormat:@"%p", p2] : @"NULL",
        @"SSL_get_fd": p3 ? [NSString stringWithFormat:@"%p", p3] : @"NULL",
        @"SSLWrite":   p4 ? [NSString stringWithFormat:@"%p", p4] : @"NULL",
        @"SSLRead":    p5 ? [NSString stringWithFormat:@"%p", p5] : @"NULL",
        @"orig_SSL_write": orig_SSL_write ? @"SET" : @"NULL",
        @"note": note,
    };
}

@end

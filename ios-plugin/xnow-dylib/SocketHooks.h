// SocketHooks.h
// XNOW socket/TLS 钩子（v1.4.140 net_socket）— 路线 B 关键突破点
// 背景：TikTok 43.7.0 纯 Swift 网络栈（Pumbaa + SwiftNIO），ObjC 层不可 hook（net_classes 实锤）。
// 但无论什么网络栈，最终都走 POSIX socket（C 函数）→ fishhook 可拦截。
// 若 TikTok 用 BoringSSL/nio-tls，SSL_write/SSL_read 拿到的是解密后明文 → 抓到完整请求（含签名）。

#import <Foundation/Foundation.h>

@interface SocketHooks : NSObject

/// 安装 socket/TLS 钩子（fishhook rebind，dispatch_once 幂等）。App 启动时或首次用时调用。
+ (void)install;

/// 开始时间盒抓包（清空缓冲，开始记录所有 socket/TLS 数据）
+ (void)beginCapture;

/// 结束抓包并返回聚合结果 {connects: [host:port], by_host: {host: {sent/recv bytes + samples}}}
+ (NSDictionary *)captureCollect;

/// v1.4.143 TLS 栈诊断探针：SSL_* 符号是否在动态符号表 + fishhook 是否重绑成功（定 BoringSSL 静态链接事实）
+ (NSDictionary *)tlsProbe;

@end

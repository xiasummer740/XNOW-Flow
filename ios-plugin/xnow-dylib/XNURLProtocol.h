// XNURLProtocol.h
// 轻量 NSURLProtocol — 用 TikTok 的网络栈通信
//
// 问题: BH TikTok 阻止了所有原始 socket 连接（即使 svc syscall），
//       但 TikTok 自己通过 URL Loading System 做的 HTTP 请求正常。
//
// 方案: 注册 NSURLProtocol 拦截 TikTok 的 HTTP 请求，
//       在拦截回调中用 NSURLSession (TikTok 的网络栈) 向我们的后端发请求。
//       NSURLProtocol 工作于 URL Loading System 层面，绕过 BH 的 socket 过滤。
//
// 用法: 在 XNStartup +load 中注册:
//       [NSURLProtocol registerClass:[XNURLProtocol class]];

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface XNURLProtocol : NSURLProtocol
@end

NS_ASSUME_NONNULL_END

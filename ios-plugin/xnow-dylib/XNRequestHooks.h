// XNRequestHooks.h
// XNOW 请求钩子（v1.4.141 net_request）— 路线 B 直取：hook 字节自研网络栈的请求模型
// 背景：net_socket 实锤 TikTok 主 API 走 Swift 自研栈（Pumbaa/PNSFoundation），TLS 层拿不到 HTTP 明文。
// 但 net_classes 发现请求模型类带完整请求属性（url/httpMethod/httpBody/allHTTPHeaderFields，@objc 暴露）
// → 替换 setter IMP，在 TikTok 构造请求瞬间拿到完整请求明文（URL/方法/headers/body/签名参数）。
// 安全：v1.4.142 起，TikTok 私有类名不再明文进 dylib（XOR 运行时解码），本类名也不含敏感子串。

#import <Foundation/Foundation.h>

@interface XNRequestHooks : NSObject

/// 安装请求模型钩子（替换 setter IMP，幂等）。类可能懒加载，beginCapture 时会补装。
+ (void)install;

/// 开始时间盒抓包（清空缓冲，开始记录请求构造调用序列）
+ (void)beginCapture;

/// 结束抓包并返回 {installed, calls: {setUrl:n,...}, records: [{op,value}]}
+ (NSDictionary *)captureCollect;

@end

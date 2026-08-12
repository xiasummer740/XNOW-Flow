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

/// 后端是否可达（最后一次检测结果）
+ (BOOL)isBackendReachable;

/// 手动立即检测后端连通性
+ (void)checkBackendNow:(void (^)(BOOL ok))completion;

/// 上报设备在线状态（POST /ws/{deviceId}）
+ (void)reportOnline:(NSString *)deviceId;

/// 发送消息到后端，响应可能带回指令
+ (void)sendMessage:(NSDictionary *)msg deviceId:(NSString *)deviceId;

/// 发送消息带完成回调（ok = 回传成功，供浮窗日志显示回传结果）
+ (void)sendMessage:(NSDictionary *)msg deviceId:(NSString *)deviceId
         completion:(void (^)(BOOL ok, NSError *error))completion;

/// 轮询指令（GET /ws/{deviceId}/poll）
+ (void)pollCommands:(NSString *)deviceId;

/// 激活卡密（POST /api/biz/v2/licenses/activate/）
+ (void)activateLicense:(NSString *)key deviceId:(NSString *)deviceId udid:(NSString *)udid
             completion:(void (^)(NSDictionary *result, NSError *error))completion;

/// 检查设备授权状态（GET /api/biz/v2/licenses/device/{deviceId}/）
+ (void)checkLicenseForDevice:(NSString *)deviceId
                   completion:(void (^)(BOOL licensed, NSDictionary *info))completion;

/// 最近一次拦截到的 feed 视频信息（从 feed/recommend 响应提取，供"下载无水印视频"使用）
/// 返回 @{url, author, desc, aweme_id}，无则 nil
+ (NSDictionary *)lastFeedVideo;

/// 回关自动私信：随机取一条激活话术（设备 secret 鉴权）
+ (void)fetchReplyTemplate:(NSString *)deviceId
                completion:(void (^)(NSDictionary *template, NSError *error))completion;

@end

NS_ASSUME_NONNULL_END

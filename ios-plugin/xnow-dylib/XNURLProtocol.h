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

/// v1.4.108 F6：上传无水印视频到后台落库（multipart，先下载 URL 再 POST /api/biz/v2/videos/save/）
+ (void)uploadVideoToBackend:(NSString *)url
                    metadata:(NSDictionary *)metadata
                    deviceId:(NSString *)deviceId
                  completion:(void (^)(BOOL ok, NSString *message))completion;

/// v1.4.108 F14：私信实时翻译（POST /api/biz/v2/translate/，设备 secret 走 header）
+ (void)translateText:(NSString *)text
           targetLang:(NSString *)targetLang
             deviceId:(NSString *)deviceId
           completion:(void (^)(NSString *translated, NSError *error))completion;

/// 激活卡密（POST /api/biz/v2/licenses/activate/）
+ (void)activateLicense:(NSString *)key deviceId:(NSString *)deviceId udid:(NSString *)udid
             completion:(void (^)(NSDictionary *result, NSError *error))completion;

/// 检查设备授权状态（GET /api/biz/v2/licenses/device/{deviceId}/）
+ (void)checkLicenseForDevice:(NSString *)deviceId
                   completion:(void (^)(BOOL licensed, NSDictionary *info))completion;

/// 最近一次拦截到的 feed 视频信息（从 feed/recommend 响应提取，供"下载无水印视频"使用）
/// 返回 @{url, author, desc, aweme_id}，无则 nil
+ (NSDictionary *)lastFeedVideo;

/// v1.4.135 网络层交互（纯网络层方案）：最近一次 feed 请求的 header（复用 app 会话/签名）
+ (NSDictionary *)lastFeedRequestHeaders;

/// v1.4.135 网络层交互：最近一次 feed 请求的 URL（复用真实 API 节点 host）
+ (NSString *)lastFeedRequestURL;

/// v1.4.136 网络路径探针：统一缓存 feed/recommend 请求的 header+URL
/// （XNURLProtocol.startLoading 与 NSURLSession swizzle 共用同一入口，避免优先级互相吞食漏缓存）
+ (void)cacheFeedRequestHeaders:(NSURLRequest *)request;

/// v1.4.136 网络路径探针：XNURLProtocol 侧诊断（被询问/实际拦截计数 + 最近 URL）
+ (NSDictionary *)netDiag;

/// 回关自动私信：随机取一条激活话术（设备 secret 鉴权）
+ (void)fetchReplyTemplate:(NSString *)deviceId
                completion:(void (^)(NSDictionary *template, NSError *error))completion;

@end

NS_ASSUME_NONNULL_END

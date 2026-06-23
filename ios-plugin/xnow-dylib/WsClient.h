// WsClient.h
// XNOW WebSocket 客户端 - 基于 NSURLSessionWebSocketTask
// 零外部依赖，适配 iOS 13+

#import <Foundation/Foundation.h>

@class WsClient;

@protocol WsClientDelegate <NSObject>
- (void)wsClientDidConnect:(WsClient *)client;
- (void)wsClientDidDisconnect:(WsClient *)client error:(NSError *)error;
- (void)wsClient:(WsClient *)client didReceiveMessage:(NSDictionary *)message;
@end

@interface WsClient : NSObject

@property (nonatomic, weak) id<WsClientDelegate> delegate;
@property (nonatomic, readonly) BOOL isConnected;

/// 连接到服务器
- (void)connectToServer:(NSString *)serverURL deviceId:(NSString *)deviceId;
/// 断开连接
- (void)disconnect;
/// 发送 JSON 消息
- (void)sendMessage:(NSDictionary *)message;
/// 发送原始字符串
- (void)sendString:(NSString *)string;

@end

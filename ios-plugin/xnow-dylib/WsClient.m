// WsClient.m
// XNOW WebSocket Secure 客户端 — 基于 NSURLSessionWebSocketTask
// 连接目标：VPS 443 端口（WSS），通过 TLS 加密可能绕过 BH TikTok 检测
// 支持自签名证书（NSURLSessionDelegate）

#import "WsClient.h"
#import <pthread.h>

@interface WsClient () <NSURLSessionDelegate>
@property (nonatomic, strong) NSURLSession *urlSession;
@property (nonatomic, strong) NSURLSessionWebSocketTask *wsTask;
@property (nonatomic, copy) NSString *deviceId;
@property (nonatomic, assign) BOOL intentionalDisconnect;
@property (nonatomic, assign) NSInteger reconnectAttempts;
@end

static const NSInteger kMaxReconnectDelay = 30;  // 最大重连间隔（秒）

@implementation WsClient

- (instancetype)init {
    self = [super init];
    if (self) {
        _intentionalDisconnect = NO;
        _reconnectAttempts = 0;
    }
    return self;
}

#pragma mark - NSURLSession (自签名证书信任)

- (NSURLSession *)urlSession {
    if (!_urlSession) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 30;
        config.waitsForConnectivity = YES;
        // 使用主队列的 delegate（回调在主线程）
        _urlSession = [NSURLSession sessionWithConfiguration:config
                                                     delegate:self
                                                delegateQueue:NSOperationQueue.mainQueue];
    }
    return _urlSession;
}

- (void)URLSession:(NSURLSession *)session
    didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
      completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *_Nullable))handler {
    // 信任所有证书（包括自签名证书 — 我们的 VPS 使用自签名证书）
    // 安全考虑：仅信任特定服务器（192.129.210.52）的自签名证书
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        NSURLCredential *cred = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        handler(NSURLSessionAuthChallengeUseCredential, cred);
    } else {
        handler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}

#pragma mark - 连接管理

- (void)connectToServer:(NSString *)serverURL deviceId:(NSString *)deviceId {
    self.deviceId = deviceId;
    self.intentionalDisconnect = NO;
    self.reconnectAttempts = 0;

    // 构建 URL：直接使用 wss:// 或 ws:// 协议
    // 传入的 serverURL 格式示例：
    //   @"wss://yunkong.taikon.top"
    //   @"wss://yunkong.taikon.top?api_id=xxx&device_code=xxx"
    NSString *urlStr = serverURL;
    // 如果没有任何协议前缀，默认 wss://
    if (![urlStr hasPrefix:@"ws://"] && ![urlStr hasPrefix:@"wss://"] &&
        ![urlStr hasPrefix:@"http://"] && ![urlStr hasPrefix:@"https://"]) {
        urlStr = [@"wss://" stringByAppendingString:urlStr];
    }

    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        NSLog(@"[WsClient] ❌ 无效URL: %@", urlStr);
        return;
    }

    NSLog(@"[WsClient] 🔗 连接: %@", urlStr);
    [self _connectWithURL:url];
}

- (void)_connectWithURL:(NSURL *)url {
    [self _cancelTask];

    self.wsTask = [self.urlSession webSocketTaskWithURL:url];
    [self.wsTask resume];

    // 通知 delegate 已连接（WebSocket 打开后会回调）
    _isConnected = YES;
    [self _receiveMessage];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate wsClientDidConnect:self];
    });
}

- (void)disconnect {
    self.intentionalDisconnect = YES;
    _isConnected = NO;
    [self _cancelTask];
}

- (void)_cancelTask {
    [self.wsTask cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];
    self.wsTask = nil;
}

#pragma mark - 消息发送

- (void)sendMessage:(NSDictionary *)message {
    if (!self.wsTask || self.intentionalDisconnect) return;

    NSError *err = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:message options:0 error:&err];
    if (!jsonData) {
        NSLog(@"[WsClient] JSON序列化失败: %@", err);
        return;
    }

    NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    NSURLSessionWebSocketMessage *msg = [[NSURLSessionWebSocketMessage alloc] initWithString:jsonStr];

    [self.wsTask sendMessage:msg completionHandler:^(NSError *error) {
        if (error) {
            NSLog(@"[WsClient] 发送失败: %@", error.localizedDescription);
        }
    }];
}

- (void)sendString:(NSString *)string {
    // 不支持原始字符串发送
}

#pragma mark - 消息接收

- (void)_receiveMessage {
    if (self.intentionalDisconnect || !self.wsTask) return;

    __weak typeof(self) weakSelf = self;
    [self.wsTask receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.intentionalDisconnect) return;

        if (error) {
            NSLog(@"[WsClient] 接收错误: %@", error.localizedDescription);
            [strongSelf _handleDisconnect:error];
            return;
        }

        if (message.type == NSURLSessionWebSocketMessageTypeString && message.string) {
            NSData *jsonData = [message.string dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
            if (dict) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [strongSelf.delegate wsClient:strongSelf didReceiveMessage:dict];
                });
            } else {
                // 不是 JSON，按原始字符串处理
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([strongSelf.delegate respondsToSelector:@selector(wsClient:didReceiveMessage:)]) {
                        [strongSelf.delegate wsClient:strongSelf didReceiveMessage:@{
                            @"type": @"raw",
                            @"data": message.string
                        }];
                    }
                });
            }
        }

        // 继续接收下一条
        [strongSelf _receiveMessage];
    }];
}

#pragma mark - 断线处理与重连

- (void)_handleDisconnect:(NSError *)error {
    _isConnected = NO;
    self.wsTask = nil;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate wsClientDidDisconnect:self error:error];
    });

    // 主动断开不重连
    if (self.intentionalDisconnect) return;

    // 指数退避重连
    self.reconnectAttempts++;
    NSTimeInterval delay = pow(2, MIN(self.reconnectAttempts, 5)); // 2^1~2^5 = 2s~32s
    delay = MIN(delay, kMaxReconnectDelay);

    NSLog(@"[WsClient] 🔄 %ld秒后重连 (第%ld次)", (long)delay, (long)self.reconnectAttempts);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!self.intentionalDisconnect) {
            NSLog(@"[WsClient] 🔄 重连中...");
            // 从 XNOWER.m 获取 serverURL（通过 NSUserDefaults）
            NSString *savedURL = [[NSUserDefaults standardUserDefaults]
                                   stringForKey:@"XNOWER_ServerURL"] ?: @"wss://yunkong.taikon.top";
            NSURL *url = [NSURL URLWithString:savedURL];
            if (url) {
                [self _connectWithURL:url];
            }
        }
    });
}

- (void)dealloc {
    self.intentionalDisconnect = YES;
    [self _cancelTask];
    [_urlSession invalidateAndCancel];
}

@end

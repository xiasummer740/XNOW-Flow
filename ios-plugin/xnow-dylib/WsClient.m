// WsClient.m
// XNOW WebSocket 客户端实现
// 基于 NSURLSessionWebSocketTask，支持自动重连（指数退避）

#import "WsClient.h"

@interface WsClient () <NSURLSessionDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionWebSocketTask *wsTask;
@property (nonatomic, copy) NSString *serverURL;
@property (nonatomic, copy) NSString *deviceId;
@property (nonatomic, assign) int reconnectAttempt;
@property (nonatomic, assign) BOOL intentionalDisconnect;
@property (nonatomic, strong) dispatch_queue_t socketQueue;
@end

static const int kMaxReconnectAttempts = 20;
static const int kBaseReconnectDelay = 2;  // seconds
static const int kHeartbeatInterval = 30;  // seconds

@implementation WsClient

- (instancetype)init {
    self = [super init];
    if (self) {
        _socketQueue = dispatch_queue_create("com.xnow.websocket", DISPATCH_QUEUE_SERIAL);
        _reconnectAttempt = 0;
        _intentionalDisconnect = NO;
    }
    return self;
}

- (void)connectToServer:(NSString *)serverURL deviceId:(NSString *)deviceId {
    self.serverURL = serverURL;
    self.deviceId = deviceId;
    self.intentionalDisconnect = NO;
    self.reconnectAttempt = 0;

    dispatch_async(_socketQueue, ^{
        [self _connectInternal];
    });
}

- (void)_connectInternal {
    // WebSocket URL: ws://server:port/ws/{deviceId}
    NSString *wsPath = [NSString stringWithFormat:@"%@/ws/%@", self.serverURL, self.deviceId];

    // 支持 http→ws / https→wss 自动转换
    NSString *finalURL = wsPath;
    if ([finalURL hasPrefix:@"http://"]) {
        finalURL = [finalURL stringByReplacingCharactersInRange:NSMakeRange(0, 4) withString:@"ws"];
    } else if ([finalURL hasPrefix:@"https://"]) {
        finalURL = [finalURL stringByReplacingCharactersInRange:NSMakeRange(0, 5) withString:@"wss"];
    } else if (![finalURL hasPrefix:@"ws://"] && ![finalURL hasPrefix:@"wss://"]) {
        finalURL = [NSString stringWithFormat:@"ws://%@", finalURL];
    }

    NSURL *url = [NSURL URLWithString:finalURL];
    if (!url) {
        [self _notifyDisconnectWithError:[NSError errorWithDomain:@"XNOWER"
                                                             code:-1 userInfo:@{NSLocalizedDescriptionKey:
                                                               [NSString stringWithFormat:@"Invalid URL: %@", finalURL]}]];
        return;
    }

    // 创建 session 配置（后台不保持连接，仅前台）
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForResource = 86400;  // 24h
    config.waitsForConnectivity = YES;

    self.session = [NSURLSession sessionWithConfiguration:config
                                                 delegate:self
                                            delegateQueue:nil];

    self.wsTask = [self.session webSocketTaskWithURL:url];
    [self.wsTask resume];

    // 开始监听消息
    [self _receiveNextMessage];
}

- (void)disconnect {
    self.intentionalDisconnect = YES;
    [self _cleanup];
}

- (void)_cleanup {
    [self.wsTask cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure
                         reason:nil];
    self.wsTask = nil;
    [self.session invalidateAndCancel];
    self.session = nil;
    _isConnected = NO;
}

// ======== 消息接收循环 ========

- (void)_receiveNextMessage {
    __weak typeof(self) weakSelf = self;
    [self.wsTask receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message,
                                                        NSError *error) {
        if (error) {
            [weakSelf _notifyDisconnectWithError:error];
            return;
        }

        if (message.type == NSURLSessionWebSocketMessageTypeString) {
            NSString *text = message.string;
            if (text && weakSelf) {
                // 尝试解析 JSON
                NSData *jsonData = [text dataUsingEncoding:NSUTF8StringEncoding];
                if (jsonData) {
                    NSError *parseError = nil;
                    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData
                                                                         options:0
                                                                           error:&parseError];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (dict && !parseError && weakSelf.delegate) {
                            [weakSelf.delegate wsClient:weakSelf didReceiveMessage:dict];
                        } else {
                            // 无效 JSON - 忽略
                        }
                    });
                }
            }
        }

        // 继续监听下一条（如果还在连接状态）
        if (weakSelf && weakSelf.wsTask.state == NSURLSessionTaskStateRunning) {
            [weakSelf _receiveNextMessage];
        }
    }];
}

// ======== 发送消息 ========

- (void)sendMessage:(NSDictionary *)message {
    if (!self.isConnected) return;

    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:message
                                                       options:0 error:&error];
    if (error || !jsonData) return;

    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    if (jsonString) {
        [self sendString:jsonString];
    }
}

- (void)sendString:(NSString *)string {
    if (!self.wsTask || self.wsTask.state != NSURLSessionTaskStateRunning) return;

    NSURLSessionWebSocketMessage *msg = [[NSURLSessionWebSocketMessage alloc] initWithString:string];
    [self.wsTask sendMessage:msg completionHandler:^(NSError *error) {
        if (error) {
            NSLog(@"[XNOWER] Send error: %@", error.localizedDescription);
        }
    }];
}

// ======== NSURLSessionDelegate ========

- (void)URLSession:(NSURLSession *)session
      webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask
      didOpenWithProtocol:(NSString *)protocol {
    _isConnected = YES;
    self.reconnectAttempt = 0;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate wsClientDidConnect:self];
    });
}

- (void)URLSession:(NSURLSession *)session
      webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask
      didCloseWithCode:(NSURLSessionWebSocketCloseCode)closeCode
      reason:(NSData *)reason {
    _isConnected = NO;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate wsClientDidDisconnect:self error:nil];
    });

    // 自动重连
    [self _scheduleReconnect];
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
      didCompleteWithError:(NSError *)error {
    _isConnected = NO;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate wsClientDidDisconnect:self error:error];
    });

    [self _scheduleReconnect];
}

// ======== 自动重连（指数退避） ========

- (void)_scheduleReconnect {
    if (self.intentionalDisconnect) return;
    if (self.reconnectAttempt >= kMaxReconnectAttempts) return;

    self.reconnectAttempt++;

    // 指数退避：2^n 秒，最大 60 秒
    int delay = MIN(kBaseReconnectDelay * (1 << (self.reconnectAttempt - 1)), 60);
    // 加一点随机抖动，防止多个设备同时重连
    int jitter = arc4random_uniform(5);
    delay += jitter;

    NSLog(@"[XNOWER] Reconnecting in %ds (attempt %d/%d)",
          delay, self.reconnectAttempt, kMaxReconnectAttempts);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   self.socketQueue, ^{
        if (!self.intentionalDisconnect) {
            [self _connectInternal];
        }
    });
}

- (void)_notifyDisconnectWithError:(NSError *)error {
    _isConnected = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate wsClientDidDisconnect:self error:error];
    });
    [self _scheduleReconnect];
}

@end

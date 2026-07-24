// WsClient.m
// XNOW HTTP轮询客户端 — 替代WebSocket，避开BH TikTok对持续连接的检测
// 原理：定时发送HTTP POST请求，服务器返回指令（轮询模式）
// 每次请求短连接，发完即断

#import "WsClient.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <netdb.h>
#import <pthread.h>

@interface WsClient ()
@property (nonatomic, copy) NSString *deviceId;
@property (nonatomic, copy) NSString *serverHost;
@property (nonatomic, assign) int serverPort;
@property (nonatomic, assign) BOOL intentionalDisconnect;
@property (nonatomic, strong) dispatch_queue_t pollQueue;
@property (nonatomic, assign) BOOL pollingActive;
// 缓存待发送的消息
@property (nonatomic, strong) NSMutableArray *pendingMessages;
@end

@implementation WsClient

- (instancetype)init {
    self = [super init];
    if (self) {
        _pollQueue = dispatch_queue_create("com.xnow.poll", DISPATCH_QUEUE_SERIAL);
        _pendingMessages = [NSMutableArray array];
        _intentionalDisconnect = NO;
        _pollingActive = NO;
    }
    return self;
}

- (void)connectToServer:(NSString *)serverURL deviceId:(NSString *)deviceId {
    self.deviceId = deviceId;
    _isConnected = YES;     // 标记为"已连接"以允许sendMessage
    self.intentionalDisconnect = NO;

    // 解析 host:port
    NSString *base = serverURL;
    if ([base hasPrefix:@"ws://"]) base = [base substringFromIndex:5];
    if ([base hasPrefix:@"wss://"]) base = [base substringFromIndex:6];
    NSRange sr = [base rangeOfString:@"/"];
    if (sr.location != NSNotFound) base = [base substringToIndex:sr.location];
    NSRange cr = [base rangeOfString:@":"];
    if (cr.location != NSNotFound) {
        _serverHost = [base substringToIndex:cr.location];
        _serverPort = [[base substringFromIndex:cr.location + 1] intValue];
    } else {
        _serverHost = base;
        _serverPort = 8000;
    }

    dispatch_async(_pollQueue, ^{
        // 先上报状态
        [self _sendToServer:@{
            @"type": @"status",
            @"data": @{@"device_id": deviceId ?: @"", @"connected": @YES}
        }];

        // 标记已连接，通知 delegate
        self.pollingActive = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate wsClientDidConnect:self];
        });

        // 启动轮询循环
        [self _pollLoop];
    });
}

- (void)disconnect {
    self.intentionalDisconnect = YES;
    self.pollingActive = NO;
    _isConnected = NO;
}

- (void)sendMessage:(NSDictionary *)message {
    if (!_isConnected) return;
    dispatch_async(_pollQueue, ^{
        [self _sendToServer:message];
    });
}

- (void)sendString:(NSString *)string {
    // 不支持原始字符串发送，通过 sendMessage
}

#pragma mark - HTTP Poll Loop

- (void)_pollLoop {
    // 每 5 秒轮询一次
    while (self.pollingActive && !self.intentionalDisconnect) {
        @autoreleasepool {
            // 发送所有积压消息
            for (NSDictionary *msg in self.pendingMessages) {
                [self _sendToServer:msg];
            }
            [self.pendingMessages removeAllObjects];

            // 轮询指令
            [self _pollForCommands];

            // 间隔 5 秒
            for (int i = 0; i < 50 && self.pollingActive && !self.intentionalDisconnect; i++) {
                usleep(100000); // 100ms × 50 = 5s
            }
        }
    }
    _isConnected = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate wsClientDidDisconnect:self error:nil];
    });
}

#pragma mark - TCP HTTP Client

- (void)_sendToServer:(NSDictionary *)payload {
    if (self.intentionalDisconnect) return;

    // 构建 JSON
    NSError *err = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&err];
    if (!jsonData) return;

    int sock = [self _connectSocket];
    if (sock < 0) return;

    NSString *body = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    NSString *request = [NSString stringWithFormat:
        @"POST /ws/%@ HTTP/1.1\r\n"
        @"Host: %@:%d\r\n"
        @"Content-Type: application/json\r\n"
        @"Content-Length: %lu\r\n"
        @"Connection: close\r\n"
        @"\r\n%@",
        self.deviceId ?: @"", self.serverHost, self.serverPort,
        (unsigned long)body.length, body];

    const char *reqC = [request UTF8String];
    size_t toSend = strlen(reqC);
    size_t sent = 0;
    while (sent < toSend) {
        ssize_t n = write(sock, reqC + sent, toSend - sent);
        if (n <= 0) break;
        sent += n;
    }

    // 读取响应（最多等 5 秒）
    struct timeval tv = {5, 0};
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    NSMutableData *respData = [NSMutableData data];
    char buf[4096];
    ssize_t n;
    while ((n = read(sock, buf, sizeof(buf))) > 0) {
        [respData appendBytes:buf length:n];
    }
    close(sock);

    // 解析响应
    NSString *resp = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];
    if ([resp containsString:@"HTTP/1.1 200"] || [resp containsString:@"HTTP/1.1 201"]) {
        // 查找 JSON body（在 \r\n\r\n 之后）
        NSRange headerEnd = [resp rangeOfString:@"\r\n\r\n"];
        if (headerEnd.location != NSNotFound) {
            NSString *bodyStr = [resp substringFromIndex:headerEnd.location + 4];
            NSData *bodyData = [bodyStr dataUsingEncoding:NSUTF8StringEncoding];
            if (bodyData) {
                NSDictionary *responseJSON = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:nil];
                [self _handleResponse:responseJSON];
            }
        }
    }
}

- (void)_pollForCommands {
    if (self.intentionalDisconnect) return;

    int sock = [self _connectSocket];
    if (sock < 0) return;

    NSString *request = [NSString stringWithFormat:
        @"GET /ws/%@/poll HTTP/1.1\r\n"
        @"Host: %@:%d\r\n"
        @"Connection: close\r\n"
        @"\r\n",
        self.deviceId ?: @"", self.serverHost, self.serverPort];

    const char *reqC = [request UTF8String];
    size_t toSend = strlen(reqC);
    size_t sent = 0;
    while (sent < toSend) {
        ssize_t n = write(sock, reqC + sent, toSend - sent);
        if (n <= 0) break;
        sent += n;
    }

    struct timeval tv = {5, 0};
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    NSMutableData *respData = [NSMutableData data];
    char buf[4096];
    ssize_t n;
    while ((n = read(sock, buf, sizeof(buf))) > 0) {
        [respData appendBytes:buf length:n];
    }
    close(sock);

    NSString *resp = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];
    if ([resp containsString:@"200"]) {
        NSRange headerEnd = [resp rangeOfString:@"\r\n\r\n"];
        if (headerEnd.location != NSNotFound) {
            NSString *bodyStr = [resp substringFromIndex:headerEnd.location + 4];
            NSData *bodyData = [bodyStr dataUsingEncoding:NSUTF8StringEncoding];
            if (bodyData) {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:nil];
                if (json && json[@"command"]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.delegate wsClient:self didReceiveMessage:json];
                    });
                }
            }
        }
    }
}

- (int)_connectSocket {
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) return -1;

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(self.serverPort);

    if (inet_pton(AF_INET, [self.serverHost UTF8String], &addr.sin_addr) != 1) {
        struct hostent *he = gethostbyname([self.serverHost UTF8String]);
        if (!he) { close(sock); return -1; }
        memcpy(&addr.sin_addr, he->h_addr_list[0], he->h_length);
    }

    struct timeval tv = {5, 0};
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(sock);
        return -1;
    }
    return sock;
}

- (void)_handleResponse:(NSDictionary *)json {
    if (!json) return;
    // 把服务端响应作为消息传给 delegate
    if (json[@"command"] || json[@"action"] || json[@"type"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate wsClient:self didReceiveMessage:json];
        });
    }
}

@end
// XNFloatingPanel.m
// XNOW 控制浮窗 - 美观半透明浮动操作面板实现

#import "XNFloatingPanel.h"
#import <objc/runtime.h>

#pragma mark - 常量

static const CGFloat kCollapsedSize = 56;
static const CGFloat kExpandedWidth = 280;
static const CGFloat kExpandedHeight = 420;
static const CGFloat kCornerRadius = 16;
static const CGFloat kButtonSize = 60;
static const CGFloat kMargin = 12;

// 品牌色
#define XN_COLOR(r,g,b) [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1]
#define XN_BRAND_COLOR XN_COLOR(108, 92, 231)     // 紫色主色
#define XN_ACCENT_COLOR XN_COLOR(0, 206, 201)     // 青绿强调色
#define XN_DARK_COLOR XN_COLOR(30, 30, 47)        // 深色背景
#define XN_CARD_COLOR XN_COLOR(255, 255, 255)     // 白色卡片

@interface XNFloatingPanel () {
    BOOL _isExpanded;
    BOOL _isDragging;
    CGPoint _dragStart;
    CGPoint _panelOrigin;
}

// 折叠状态
@property (nonatomic, strong) UIButton *badgeButton;
@property (nonatomic, strong) UIView *statusDot;

// 展开状态
@property (nonatomic, strong) UIView *panelContainer;
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *deviceIdLabel;
@property (nonatomic, strong) UILabel *serverLabel;

// 按钮
@property (nonatomic, strong) NSMutableArray *actionButtons;
@property (nonatomic, strong) UILabel *connectionDot;

@property (nonatomic, assign) BOOL isConnected;
@property (nonatomic, copy) NSString *panelDeviceId;
@property (nonatomic, copy) NSString *panelServerURL;

@end

@implementation XNFloatingPanel

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:CGRectMake(16, 120, kCollapsedSize, kCollapsedSize)];
    if (self) {
        _isExpanded = NO;
        _isConnected = NO;
        _actionButtons = [NSMutableArray array];
        [self _setupViews];
    }
    return self;
}

- (void)_setupViews {
    self.clipsToBounds = NO;
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 4);
    self.layer.shadowRadius = 12;
    self.layer.shadowOpacity = 0.3;

    // 添加拖动手势
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
                                    initWithTarget:self action:@selector(_handlePan:)];
    [self addGestureRecognizer:pan];

    // 点击手势
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
                                    initWithTarget:self action:@selector(_handleTap)];
    [self addGestureRecognizer:tap];

    [self _buildBadge];
}

#pragma mark - 折叠状态：圆形徽章

- (void)_buildBadge {
    self.badgeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.badgeButton.frame = CGRectMake(0, 0, kCollapsedSize, kCollapsedSize);
    self.badgeButton.backgroundColor = XN_BRAND_COLOR;
    self.badgeButton.layer.cornerRadius = kCollapsedSize / 2;
    self.badgeButton.clipsToBounds = YES;
    self.badgeButton.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    [self.badgeButton setTitle:@"X" forState:UIControlStateNormal];
    [self.badgeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self addSubview:self.badgeButton];

    // 状态指示点
    self.statusDot = [[UIView alloc] initWithFrame:CGRectMake(kCollapsedSize - 14, kCollapsedSize - 14, 12, 12)];
    self.statusDot.backgroundColor = [UIColor redColor];
    self.statusDot.layer.cornerRadius = 6;
    self.statusDot.layer.borderWidth = 2;
    self.statusDot.layer.borderColor = [UIColor whiteColor].CGColor;
    [self addSubview:self.statusDot];
}

#pragma mark - 展开状态：完整控制面板

- (void)_buildExpandedPanel {
    if (self.panelContainer) return;

    self.panelContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kExpandedWidth, kExpandedHeight)];
    self.panelContainer.layer.cornerRadius = kCornerRadius;
    self.panelContainer.clipsToBounds = YES;
    self.panelContainer.alpha = 0;
    [self addSubview:self.panelContainer];

    // 透明毛玻璃背景（极简半透明）
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular];
    self.blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.blurView.frame = self.panelContainer.bounds;
    self.blurView.alpha = 0.6;
    [self.panelContainer addSubview:self.blurView];

    // 极浅底色，保持透明感
    UIView *tintOverlay = [[UIView alloc] initWithFrame:self.panelContainer.bounds];
    tintOverlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.15];
    [self.panelContainer addSubview:tintOverlay];

    // === 头部 ===
    CGFloat y = 16;

    // 品牌 Logo 区域
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(kMargin, y, kExpandedWidth - 2*kMargin, 60)];
    [self.panelContainer addSubview:headerView];

    // Logo 圆形图标
    UIView *logoCircle = [[UIView alloc] initWithFrame:CGRectMake(0, 4, 44, 44)];
    logoCircle.backgroundColor = XN_BRAND_COLOR;
    logoCircle.layer.cornerRadius = 22;
    logoCircle.clipsToBounds = YES;
    [headerView addSubview:logoCircle];

    UILabel *logoLabel = [[UILabel alloc] initWithFrame:logoCircle.bounds];
    logoLabel.text = @"XN";
    logoLabel.font = [UIFont boldSystemFontOfSize:18];
    logoLabel.textColor = [UIColor whiteColor];
    logoLabel.textAlignment = NSTextAlignmentCenter;
    [logoCircle addSubview:logoLabel];

    // 标题
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(56, 4, 160, 24)];
    self.titleLabel.text = @"XNOWER";
    self.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    self.titleLabel.textColor = [UIColor whiteColor];
    [headerView addSubview:self.titleLabel];

    // 状态指示 + 文字
    self.connectionDot = [[UILabel alloc] initWithFrame:CGRectMake(56, 30, 160, 20)];
    self.connectionDot.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [self _updateStatusText];
    [headerView addSubview:self.connectionDot];

    // 关闭按钮
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(kExpandedWidth - kMargin - 36, 8, 36, 36);
    closeBtn.backgroundColor = [UIColor colorWithWhite:1 alpha:0.15];
    closeBtn.layer.cornerRadius = 18;
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [closeBtn setTintColor:[UIColor whiteColor]];
    [closeBtn addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [self.panelContainer addSubview:closeBtn];

    y += 68;

    // === 分割线 ===
    UIView *divider = [[UIView alloc] initWithFrame:CGRectMake(kMargin, y, kExpandedWidth - 2*kMargin, 1)];
    divider.backgroundColor = [UIColor colorWithWhite:1 alpha:0.15];
    [self.panelContainer addSubview:divider];

    y += 16;

    // === 操作按钮 2x3 网格 ===
    NSArray *buttons = @[
        @{@"icon": @"❤️", @"label": @"点赞", @"action": @"like"},
        @{@"icon": @"👤", @"label": @"关注", @"action": @"follow"},
        @{@"icon": @"⬆️", @"label": @"上滑", @"action": @"scroll"},
        @{@"icon": @"📸", @"label": @"截图", @"action": @"screenshot"},
        @{@"icon": @"👥", @"label": @"采粉", @"action": @"fans"},
        @{@"icon": @"🎬", @"label": @"采视频", @"action": @"videos"},
    ];

    CGFloat btnWidth = (kExpandedWidth - 4*kMargin) / 3;
    CGFloat btnHeight = btnWidth + 20;
    int col = 0, row = 0;

    for (NSDictionary *btnInfo in buttons) {
        CGFloat bx = kMargin + col * (btnWidth + kMargin);
        CGFloat by = y + row * (btnHeight + kMargin);
        UIView *btnView = [self _createActionButton:btnInfo frame:CGRectMake(bx, by, btnWidth, btnHeight)];
        [self.panelContainer addSubview:btnView];
        col++;
        if (col >= 3) { col = 0; row++; }
    }

    y += 3 * (btnHeight + kMargin) - kMargin + 16;

    // === 底部信息 ===
    UIView *divider2 = [[UIView alloc] initWithFrame:CGRectMake(kMargin, y, kExpandedWidth - 2*kMargin, 1)];
    divider2.backgroundColor = [UIColor colorWithWhite:1 alpha:0.15];
    [self.panelContainer addSubview:divider2];

    y += 12;

    self.deviceIdLabel = [[UILabel alloc] initWithFrame:CGRectMake(kMargin, y, kExpandedWidth - 2*kMargin, 16)];
    self.deviceIdLabel.font = [UIFont systemFontOfSize:11];
    self.deviceIdLabel.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    self.deviceIdLabel.text = self.panelDeviceId ? [NSString stringWithFormat:@"📱 ID: %@", self.panelDeviceId] : @"📱 ID: --";
    [self.panelContainer addSubview:self.deviceIdLabel];

    y += 18;

    self.serverLabel = [[UILabel alloc] initWithFrame:CGRectMake(kMargin, y, kExpandedWidth - 2*kMargin, 16)];
    self.serverLabel.font = [UIFont systemFontOfSize:10];
    self.serverLabel.textColor = [UIColor colorWithWhite:1 alpha:0.4];
    self.serverLabel.text = self.panelServerURL ? [NSString stringWithFormat:@"🔗 %@", self.panelServerURL] : @"🔗 --";
    [self.panelContainer addSubview:self.serverLabel];

    y += 18;

    // 版本
    UILabel *versionLabel = [[UILabel alloc] initWithFrame:CGRectMake(kMargin, y, kExpandedWidth - 2*kMargin, 12)];
    versionLabel.text = @"XNOWER v1.0 • iOS 注入插件";
    versionLabel.font = [UIFont systemFontOfSize:9];
    versionLabel.textColor = [UIColor colorWithWhite:1 alpha:0.3];
    versionLabel.textAlignment = NSTextAlignmentCenter;
    [self.panelContainer addSubview:versionLabel];
}

/// 创建单个操作按钮
- (UIView *)_createActionButton:(NSDictionary *)info frame:(CGRect)frame {
    UIView *view = [[UIView alloc] initWithFrame:frame];

    // 按钮背景
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake((frame.size.width - kButtonSize) / 2, 0, kButtonSize, kButtonSize);
    button.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    button.layer.cornerRadius = kButtonSize / 2;
    button.clipsToBounds = YES;
    button.titleLabel.font = [UIFont systemFontOfSize:26];
    [button setTitle:info[@"icon"] forState:UIControlStateNormal];
    button.userInteractionEnabled = YES;
    button.tag = [_actionButtons count];
    [button addTarget:self action:@selector(_actionButtonTapped:)
     forControlEvents:UIControlEventTouchUpInside];
    [view addSubview:button];

    // 标签
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, kButtonSize + 4, frame.size.width, 16)];
    label.text = info[@"label"];
    label.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    label.textColor = [UIColor colorWithWhite:1 alpha:0.8];
    label.textAlignment = NSTextAlignmentCenter;
    [view addSubview:label];

    return view;
}

- (void)_actionButtonTapped:(UIButton *)sender {
    NSString *action = @[@"like", @"follow", @"scroll", @"screenshot", @"fans", @"videos"][sender.tag];

    // 触觉反馈
    [self _hapticFeedback];

    // 按钮动画
    [UIView animateWithDuration:0.1 animations:^{
        sender.transform = CGAffineTransformMakeScale(0.85, 0.85);
        sender.backgroundColor = [UIColor colorWithWhite:1 alpha:0.25];
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.2 animations:^{
            sender.transform = CGAffineTransformIdentity;
            sender.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
        }];
    }];

    // 通知代理
    if ([action isEqualToString:@"like"]) {
        [self.delegate floatingPanelDidTapLike:self];
    } else if ([action isEqualToString:@"follow"]) {
        [self.delegate floatingPanelDidTapFollow:self];
    } else if ([action isEqualToString:@"scroll"]) {
        [self.delegate floatingPanelDidTapScrollDown:self];
    } else if ([action isEqualToString:@"screenshot"]) {
        [self.delegate floatingPanelDidTapScreenshot:self];
    } else if ([action isEqualToString:@"fans"]) {
        [self.delegate floatingPanelDidTapCollectFans:self];
    } else if ([action isEqualToString:@"videos"]) {
        [self.delegate floatingPanelDidTapCollectVideos:self];
    }

    // 操作后自动收起
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.8 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        [self _togglePanel];
    });
}

#pragma mark - 动画切换

- (void)_handleTap {
    [self _togglePanel];
}

- (void)_togglePanel {
    _isExpanded ? [self _collapsePanel] : [self _expandPanel];
}

- (void)_expandPanel {
    if (!self.panelContainer) [self _buildExpandedPanel];

    _isExpanded = YES;

    // 更新信息
    [self _updateStatusText];
    self.deviceIdLabel.text = self.panelDeviceId ? [NSString stringWithFormat:@"📱 ID: %@", self.panelDeviceId] : @"📱 ID: --";
    self.serverLabel.text = self.panelServerURL ? [NSString stringWithFormat:@"🔗 %@", self.panelServerURL] : @"🔗 --";

    // 展开动画
    CGFloat oldW = self.frame.size.width;
    CGFloat oldH = self.frame.size.height;

    // 从 badge 中心展开
    self.panelContainer.alpha = 1;
    self.panelContainer.transform = CGAffineTransformMakeScale(0.3, 0.3);

    self.frame = self.superview ?
        CGRectMake(self.frame.origin.x - (kExpandedWidth - oldW)/2,
                   self.frame.origin.y - (kExpandedHeight - oldH)/2 + 20,
                   kExpandedWidth, kExpandedHeight) :
        self.frame;

    self.badgeButton.alpha = 0;

    [UIView animateWithDuration:0.4
                          delay:0
         usingSpringWithDamping:0.7
          initialSpringVelocity:0.8
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.panelContainer.transform = CGAffineTransformIdentity;
        self.layer.shadowOpacity = 0.5;
    } completion:nil];
}

- (void)_collapsePanel {
    _isExpanded = NO;

    CGFloat cx = self.badgeButton.center.x;
    CGFloat cy = self.badgeButton.center.y;

    [UIView animateWithDuration:0.3
                          delay:0
         usingSpringWithDamping:0.8
          initialSpringVelocity:0.5
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self.panelContainer.alpha = 0;
        self.panelContainer.transform = CGAffineTransformMakeScale(0.5, 0.5);
        self.frame = CGRectMake(
            self.frame.origin.x + cx,
            self.frame.origin.y + cy,
            kCollapsedSize, kCollapsedSize);
        self.layer.shadowOpacity = 0.3;
    } completion:^(BOOL finished) {
        self.badgeButton.alpha = 1;
    }];
}

#pragma mark - 拖动

- (void)_handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self.superview];

    switch (pan.state) {
        case UIGestureRecognizerStateBegan:
            _isDragging = YES;
            _dragStart = self.center;
            [self _hapticFeedback];
            break;
        case UIGestureRecognizerStateChanged: {
            CGPoint newCenter = CGPointMake(_dragStart.x + translation.x,
                                            _dragStart.y + translation.y);
            // 限制在屏幕内
            CGFloat halfW = _isExpanded ? kExpandedWidth/2 : kCollapsedSize/2;
            CGFloat halfH = _isExpanded ? kExpandedHeight/2 : kCollapsedSize/2;
            newCenter.x = MAX(halfW, MIN([UIScreen mainScreen].bounds.size.width - halfW, newCenter.x));
            newCenter.y = MAX(50 + halfH,
                              MIN([UIScreen mainScreen].bounds.size.height - 100 - halfH, newCenter.y));
            self.center = newCenter;
            break;
        }
        case UIGestureRecognizerStateEnded:
            _isDragging = NO;
            break;
        default:
            break;
    }
}

#pragma mark - 公共方法

- (void)showInWindow:(UIWindow *)window {
    if (!window) return;
    [window addSubview:self];
    // 入场动画
    self.transform = CGAffineTransformMakeScale(0.5, 0.5);
    self.alpha = 0;
    [UIView animateWithDuration:0.3
                          delay:0.5
         usingSpringWithDamping:0.6
          initialSpringVelocity:0.8
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.transform = CGAffineTransformIdentity;
        self.alpha = 1;
    } completion:nil];
}

- (void)dismiss {
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 0;
        self.transform = CGAffineTransformMakeScale(0.3, 0.3);
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
    }];
}

- (void)setConnected:(BOOL)connected {
    _isConnected = connected;
    [self _updateStatusText];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusDot.backgroundColor = connected ?
            XN_ACCENT_COLOR : [UIColor redColor];
    });
}

- (void)setDeviceId:(NSString *)deviceId {
    _panelDeviceId = deviceId;
}

- (void)setServerURL:(NSString *)serverURL {
    _panelServerURL = serverURL;
}

- (void)_updateStatusText {
    if (self.connectionDot) {
        self.connectionDot.text = self.isConnected ?
            @"● 已连接" : @"○ 未连接";
        self.connectionDot.textColor = self.isConnected ?
            XN_ACCENT_COLOR : [UIColor colorWithWhite:0.7 alpha:1];
    }
}

#pragma mark - 辅助

- (void)_hapticFeedback {
    // 轻触反馈（iOS 10+）
    [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
}

@end

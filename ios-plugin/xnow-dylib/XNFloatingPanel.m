// XNFloatingPanel.m
// XNOW 控制浮窗 v2 — 三标签设计：账号信息 + 自动任务配置 + 手动操作

#import "XNFloatingPanel.h"
#import <objc/runtime.h>

#pragma mark - 常量

static const CGFloat kCollapsedSize = 56;
static const CGFloat kExpandedWidth = 300;
static const CGFloat kExpandedHeight = 500;
static const CGFloat kCornerRadius = 16;
static const CGFloat kButtonSize = 48;
static const CGFloat kMargin = 10;

#define XN_COLOR(r,g,b) [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1]
#define XN_BRAND_COLOR XN_COLOR(108, 92, 231)
#define XN_ACCENT_COLOR XN_COLOR(0, 206, 201)
#define XN_DARK_BG [UIColor colorWithRed:0.12 green:0.12 blue:0.18 alpha:0.92]
#define XN_CARD_BG [UIColor colorWithRed:1 green:1 blue:1 alpha:0.10]
#define XN_TEXT_COLOR [UIColor whiteColor]
#define XN_DIM_TEXT [UIColor colorWithWhite:1 alpha:0.5]
#define XN_ON_COLOR XN_COLOR(34, 197, 94)
#define XN_OFF_COLOR [UIColor colorWithWhite:1 alpha:0.25]

@interface XNFloatingPanel () {
    BOOL _isExpanded;
    BOOL _isDragging;
    CGPoint _dragStart;
    CGPoint _panelOrigin;
    int _currentTab; // 0=自动任务, 1=手动操作, 2=账号
}

// 折叠状态
@property (nonatomic, strong) UIButton *badgeButton;
@property (nonatomic, strong) UIView *statusDot;

// 展开状态
@property (nonatomic, strong) UIView *panelContainer;
@property (nonatomic, strong) UIVisualEffectView *blurView;

// 账号栏（所有标签页共用顶部）
@property (nonatomic, strong) UIView *accountBar;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *followerLabel;
@property (nonatomic, strong) UILabel *connLabel;
@property (nonatomic, strong) UIButton *switchAccountBtn;

// Tab 按钮
@property (nonatomic, strong) UIButton *tabAuto;
@property (nonatomic, strong) UIButton *tabManual;
@property (nonatomic, strong) UIButton *tabAccounts;
@property (nonatomic, strong) UIView *tabIndicator;

// 内容容器
@property (nonatomic, strong) UIScrollView *autoScrollView;
@property (nonatomic, strong) UIView *manualView;
@property (nonatomic, strong) UIScrollView *accountScrollView;

// 自动任务开关/参数
@property (nonatomic, strong) UISwitch *swAutoLike;
@property (nonatomic, strong) UISwitch *swAutoFollow;
@property (nonatomic, strong) UISwitch *swAutoComment;
@property (nonatomic, strong) UISwitch *swAutoBrowse;
@property (nonatomic, strong) UILabel *likeCountLabel, *likeDelayLabel;
@property (nonatomic, strong) UILabel *followCountLabel, *followDelayLabel;
@property (nonatomic, strong) UILabel *commentCountLabel, *commentDelayLabel;
@property (nonatomic, strong) UILabel *browseScrollLabel, *browseDelayLabel;
@property (nonatomic, assign) int likeCount, likeDelay;
@property (nonatomic, assign) int followCount, followDelay;
@property (nonatomic, assign) int commentCount, commentDelay;
@property (nonatomic, strong) NSString *commentText;
@property (nonatomic, assign) int browseMin, browseMax, browseMinD, browseMaxD;

// 手动操作按钮
@property (nonatomic, strong) NSMutableArray *actionButtons;

// 账号列表
@property (nonatomic, strong) NSArray *accountList;

// 数据
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
        _currentTab = 0;
        _actionButtons = [NSMutableArray array];
        _accountList = @[];
        _likeCount = 5; _likeDelay = 2;
        _followCount = 5; _followDelay = 3;
        _commentCount = 3; _commentDelay = 5;
        _commentText = @"Nice!";
        _browseMin = 5; _browseMax = 12; _browseMinD = 3; _browseMaxD = 8;
        [self _setupViews];
    }
    return self;
}

- (void)_setupViews {
    self.clipsToBounds = NO;
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 4);
    self.layer.shadowRadius = 12;
    self.layer.shadowOpacity = 0.4;

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
                                    initWithTarget:self action:@selector(_handlePan:)];
    [self addGestureRecognizer:pan];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
                                    initWithTarget:self action:@selector(_handleTap)];
    [self addGestureRecognizer:tap];

    [self _buildBadge];
}

#pragma mark - 折叠态：圆形徽章

- (void)_buildBadge {
    _badgeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _badgeButton.frame = CGRectMake(0, 0, kCollapsedSize, kCollapsedSize);
    _badgeButton.backgroundColor = XN_BRAND_COLOR;
    _badgeButton.layer.cornerRadius = kCollapsedSize / 2;
    _badgeButton.clipsToBounds = YES;
    _badgeButton.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    [_badgeButton setTitle:@"X" forState:UIControlStateNormal];
    [_badgeButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [_badgeButton addTarget:self action:@selector(_handleTap) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_badgeButton];

    _statusDot = [[UIView alloc] initWithFrame:CGRectMake(kCollapsedSize - 14, kCollapsedSize - 14, 12, 12)];
    _statusDot.backgroundColor = [UIColor redColor];
    _statusDot.layer.cornerRadius = 6;
    _statusDot.layer.borderWidth = 2;
    _statusDot.layer.borderColor = UIColor.whiteColor.CGColor;
    [self addSubview:_statusDot];
}

#pragma mark - 展开态：完整面板

- (void)_buildExpandedPanel {
    if (_panelContainer) return;

    _panelContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kExpandedWidth, kExpandedHeight)];
    _panelContainer.layer.cornerRadius = kCornerRadius;
    _panelContainer.clipsToBounds = YES;
    _panelContainer.alpha = 0;
    [self addSubview:_panelContainer];

    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    _blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    _blurView.frame = _panelContainer.bounds;
    [_panelContainer addSubview:_blurView];

    // === 账号栏（固定顶部） ===
    [self _buildAccountBar];

    // === Tab 按钮 ===
    [self _buildTabBar];

    // === 内容 ===
    [self _buildAutoTaskView];    // Tab 0
    [self _buildManualView];      // Tab 1
    [self _buildAccountListView]; // Tab 2

    [self _switchToTab:0];
}

- (void)_buildAccountBar {
    CGFloat y = 12;
    _accountBar = [[UIView alloc] initWithFrame:CGRectMake(kMargin, y, kExpandedWidth - 2*kMargin, 52)];
    [_panelContainer addSubview:_accountBar];

    // 头像
    _avatarView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 6, 40, 40)];
    _avatarView.backgroundColor = XN_BRAND_COLOR;
    _avatarView.layer.cornerRadius = 20;
    _avatarView.clipsToBounds = YES;
    _avatarView.contentMode = UIViewContentModeScaleAspectFill;
    _avatarView.image = nil;
    [_accountBar addSubview:_avatarView];

    UILabel *initials = [[UILabel alloc] initWithFrame:_avatarView.bounds];
    initials.text = @"X";
    initials.font = [UIFont boldSystemFontOfSize:16];
    initials.textColor = UIColor.whiteColor;
    initials.textAlignment = NSTextAlignmentCenter;
    [_avatarView addSubview:initials];

    // 昵称
    _nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(50, 6, 140, 18)];
    _nameLabel.text = @"未登录";
    _nameLabel.font = [UIFont boldSystemFontOfSize:14];
    _nameLabel.textColor = XN_TEXT_COLOR;
    [_accountBar addSubview:_nameLabel];

    // 粉丝数 + 连接状态
    _connLabel = [[UILabel alloc] initWithFrame:CGRectMake(50, 26, 100, 14)];
    _connLabel.font = [UIFont systemFontOfSize:10];
    _connLabel.textColor = XN_DIM_TEXT;
    [_accountBar addSubview:_connLabel];

    _followerLabel = [[UILabel alloc] initWithFrame:CGRectMake(150, 26, 80, 14)];
    _followerLabel.font = [UIFont systemFontOfSize:10];
    _followerLabel.textColor = XN_DIM_TEXT;
    _followerLabel.textAlignment = NSTextAlignmentRight;
    [_accountBar addSubview:_followerLabel];

    // 切换账号按钮
    _switchAccountBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _switchAccountBtn.frame = CGRectMake(kExpandedWidth - 2*kMargin - 60, 14, 60, 24);
    _switchAccountBtn.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    _switchAccountBtn.layer.cornerRadius = 12;
    [_switchAccountBtn setTitle:@"切换" forState:UIControlStateNormal];
    _switchAccountBtn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    [_switchAccountBtn setTintColor:XN_ACCENT_COLOR];
    [_switchAccountBtn addTarget:self action:@selector(_tapSwitchAccount) forControlEvents:UIControlEventTouchUpInside];
    [_accountBar addSubview:_switchAccountBtn];
}

- (void)_buildTabBar {
    CGFloat y = 68;
    CGFloat tabW = (kExpandedWidth - 2*kMargin) / 3;
    CGFloat tabH = 32;

    UIView *tabBar = [[UIView alloc] initWithFrame:CGRectMake(kMargin, y, kExpandedWidth - 2*kMargin, tabH)];
    tabBar.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    tabBar.layer.cornerRadius = tabH/2;
    tabBar.clipsToBounds = YES;
    [_panelContainer addSubview:tabBar];

    NSArray *titles = @[@"自动任务", @"手动操作", @"账号"];
    NSArray *btns = @[@"tabAuto", @"tabManual", @"tabAccounts"];
    SEL sel = @selector(_tabTapped:);

    for (int i = 0; i < 3; i++) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(i * tabW, 0, tabW, tabH);
        btn.tag = i;
        [btn setTitle:titles[i] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        [btn setTintColor:XN_DIM_TEXT];
        [btn addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
        [tabBar addSubview:btn];

        if (i == 0) _tabAuto = btn;
        else if (i == 1) _tabManual = btn;
        else _tabAccounts = btn;
    }

    _tabIndicator = [[UIView alloc] initWithFrame:CGRectMake(kMargin + 4, y + 2, tabW - 8, tabH - 4)];
    _tabIndicator.backgroundColor = XN_BRAND_COLOR;
    _tabIndicator.layer.cornerRadius = (tabH - 4) / 2;
    [_panelContainer addSubview:_tabIndicator];
}

- (void)_tabTapped:(UIButton *)sender {
    [self _switchToTab:(int)sender.tag];
}

- (void)_switchToTab:(int)tab {
    _currentTab = tab;
    CGFloat tabW = (kExpandedWidth - 2*kMargin) / 3;
    CGFloat y = 68;
    [UIView animateWithDuration:0.2 animations:^{
        CGRect f = self->_tabIndicator.frame;
        f.origin.x = kMargin + 4 + tab * tabW;
        self->_tabIndicator.frame = f;
    }];

    _autoScrollView.hidden = (tab != 0);
    _manualView.hidden = (tab != 1);
    _accountScrollView.hidden = (tab != 2);
}

#pragma mark - Tab 0: 自动任务配置

- (void)_buildAutoTaskView {
    CGFloat y = 104;
    _autoScrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, y, kExpandedWidth, kExpandedHeight - y - 20)];
    _autoScrollView.showsVerticalScrollIndicator = NO;
    [_panelContainer addSubview:_autoScrollView];

    UIView *content = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kExpandedWidth, 480)];
    [_autoScrollView addSubview:content];
    _autoScrollView.contentSize = content.frame.size;

    CGFloat cy = 4;
    cy = [self _addAutoTaskSection:content y:cy title:@"❤️ 自动点赞"
                          switch:_swAutoLike countLabel:_likeCountLabel delayLabel:_likeDelayLabel
                         count:_likeCount delay:_likeDelay
                    countAction:@selector(_likeCountChanged:) delayAction:@selector(_likeDelayChanged:)];

    cy = [self _addAutoTaskSection:content y:cy title:@"👤 自动关注"
                          switch:_swAutoFollow countLabel:_followCountLabel delayLabel:_followDelayLabel
                         count:_followCount delay:_followDelay
                    countAction:@selector(_followCountChanged:) delayAction:@selector(_followDelayChanged:)];

    cy = [self _addAutoTaskSection:content y:cy title:@"💬 自动评论"
                          switch:_swAutoComment countLabel:_commentCountLabel delayLabel:_commentDelayLabel
                         count:_commentCount delay:_commentDelay
                    countAction:@selector(_commentCountChanged:) delayAction:@selector(_commentDelayChanged:)];

    cy = [self _addAutoTaskSection:content y:cy title:@"🤖 智能浏览"
                          switch:_swAutoBrowse countLabel:_browseScrollLabel delayLabel:_browseDelayLabel
                         count:_browseMin delay:_browseMax
                    countAction:@selector(_browseScrollChanged:) delayAction:@selector(_browseDelayChanged:)];

    // 浏览参数说明
    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(kMargin, cy + 4, kExpandedWidth - 2*kMargin, 30)];
    hint.text = @"次数=最少-最多滑动 延时=观看视频秒数范围";
    hint.font = [UIFont systemFontOfSize:9];
    hint.textColor = XN_DIM_TEXT;
    hint.numberOfLines = 0;
    [content addSubview:hint];
}

- (CGFloat)_addAutoTaskSection:(UIView *)parent y:(CGFloat)y title:(NSString *)title
                        switch:(UISwitch *)sw countLabel:(UILabel *)countL delayLabel:(UILabel *)delayL
                         count:(int)count delay:(int)delay
                    countAction:(SEL)countAction delayAction:(SEL)delayAction {

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(kMargin, y, kExpandedWidth - 2*kMargin, 100)];
    card.backgroundColor = XN_CARD_BG;
    card.layer.cornerRadius = 10;
    [parent addSubview:card];

    // 标题 + 开关
    UILabel *titleL = [[UILabel alloc] initWithFrame:CGRectMake(12, 8, 160, 20)];
    titleL.text = title;
    titleL.font = [UIFont boldSystemFontOfSize:13];
    titleL.textColor = XN_TEXT_COLOR;
    [card addSubview:titleL];

    UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectMake(card.frame.size.width - 60, 6, 48, 24)];
    toggle.onTintColor = XN_BRAND_COLOR;
    toggle.transform = CGAffineTransformMakeScale(0.7, 0.7);
    [toggle addTarget:self action:@selector(_autoToggleChanged:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:toggle];

    // 存储开关引用
    if ([title containsString:@"点赞"]) _swAutoLike = toggle;
    else if ([title containsString:@"关注"]) _swAutoFollow = toggle;
    else if ([title containsString:@"评论"]) _swAutoComment = toggle;
    else if ([title containsString:@"浏览"]) _swAutoBrowse = toggle;

    // 参数调节
    CGFloat sx = 12, sy = 36;
    // 次数
    UILabel *cl = [[UILabel alloc] initWithFrame:CGRectMake(sx, sy, 50, 16)];
    cl.text = @"次数:";
    cl.font = [UIFont systemFontOfSize:10];
    cl.textColor = XN_DIM_TEXT;
    [card addSubview:cl];

    UILabel *cv = [[UILabel alloc] initWithFrame:CGRectMake(sx + 50, sy, 30, 16)];
    cv.text = @(count).stringValue;
    cv.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    cv.textColor = XN_TEXT_COLOR;
    [card addSubview:cv];

    UISlider *cs = [[UISlider alloc] initWithFrame:CGRectMake(sx + 80, sy, card.frame.size.width - sx - 92, 20)];
    cs.minimumValue = 1; cs.maximumValue = 50;
    cs.value = count;
    cs.minimumTrackTintColor = XN_BRAND_COLOR;
    cs.transform = CGAffineTransformMakeScale(0.8, 0.6);
    cs.tag = ([title containsString:@"点赞"] ? 0 : [title containsString:@"关注"] ? 1 : [title containsString:@"评论"] ? 2 : 3) * 2;
    [cs addTarget:self action:@selector(_sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:cs];

    // 延时
    CGFloat sy2 = sy + 24;
    UILabel *dl = [[UILabel alloc] initWithFrame:CGRectMake(sx, sy2, 50, 16)];
    dl.text = @"延时(秒):";
    dl.font = [UIFont systemFontOfSize:10];
    dl.textColor = XN_DIM_TEXT;
    [card addSubview:dl];

    UILabel *dv = [[UILabel alloc] initWithFrame:CGRectMake(sx + 62, sy2, 24, 16)];
    dv.text = @(delay).stringValue;
    dv.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    dv.textColor = XN_TEXT_COLOR;
    [card addSubview:dv];

    UISlider *ds = [[UISlider alloc] initWithFrame:CGRectMake(sx + 88, sy2, card.frame.size.width - sx - 100, 20)];
    ds.minimumValue = 1; ds.maximumValue = 30;
    ds.value = delay;
    ds.minimumTrackTintColor = XN_ACCENT_COLOR;
    ds.transform = CGAffineTransformMakeScale(0.8, 0.6);
    ds.tag = ([title containsString:@"点赞"] ? 0 : [title containsString:@"关注"] ? 1 : [title containsString:@"评论"] ? 2 : 3) * 2 + 1;
    [ds addTarget:self action:@selector(_sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:ds];

    // 存储标签引用
    if ([title containsString:@"点赞"]) { _likeCountLabel = cv; _likeDelayLabel = dv; }
    else if ([title containsString:@"关注"]) { _followCountLabel = cv; _followDelayLabel = dv; }
    else if ([title containsString:@"评论"]) { _commentCountLabel = cv; _commentDelayLabel = dv; }
    else if ([title containsString:@"浏览"]) { _browseScrollLabel = cv; _browseDelayLabel = dv; }

    return y + 108;
}

- (void)_autoToggleChanged:(UISwitch *)sender {
    if (sender == _swAutoLike) {
        [self.delegate floatingPanel:self didToggleAutoLike:sender.isOn];
    } else if (sender == _swAutoFollow) {
        [self.delegate floatingPanel:self didToggleAutoFollow:sender.isOn];
    } else if (sender == _swAutoComment) {
        [self.delegate floatingPanel:self didToggleAutoComment:sender.isOn];
    } else if (sender == _swAutoBrowse) {
        [self.delegate floatingPanel:self didToggleAutoBrowse:sender.isOn];
    }
}

- (void)_sliderChanged:(UISlider *)sender {
    int val = (int)round(sender.value);
    int idx = (int)sender.tag;
    int section = idx / 2;
    BOOL isCount = (idx % 2 == 0);

    switch (section) {
        case 0: // like
            if (isCount) { _likeCount = val; _likeCountLabel.text = @(val).stringValue; }
            else { _likeDelay = val; _likeDelayLabel.text = @(val).stringValue; }
            [self.delegate floatingPanel:self didChangeAutoLikeCount:_likeCount delay:_likeDelay];
            break;
        case 1: // follow
            if (isCount) { _followCount = val; _followCountLabel.text = @(val).stringValue; }
            else { _followDelay = val; _followDelayLabel.text = @(val).stringValue; }
            [self.delegate floatingPanel:self didChangeAutoFollowCount:_followCount delay:_followDelay];
            break;
        case 2: // comment
            if (isCount) { _commentCount = val; _commentCountLabel.text = @(val).stringValue; }
            else { _commentDelay = val; _commentDelayLabel.text = @(val).stringValue; }
            [self.delegate floatingPanel:self didChangeAutoCommentCount:_commentCount delay:_commentDelay text:_commentText];
            break;
        case 3: // browse
            if (isCount) {
                _browseMin = MIN(val, _browseMax);
                _browseMax = MAX(val, _browseMax);
                _browseScrollLabel.text = [NSString stringWithFormat:@"%d-%d", _browseMin, _browseMax];
            } else {
                _browseMinD = val;
                _browseMaxD = val + 3;
                _browseDelayLabel.text = [NSString stringWithFormat:@"%d-%d", _browseMinD, _browseMaxD];
            }
            [self.delegate floatingPanel:self didChangeAutoBrowseMinScrolls:_browseMin maxScrolls:_browseMax minDelay:_browseMinD maxDelay:_browseMaxD];
            break;
    }
}

#pragma mark - Tab 1: 手动操作

- (void)_buildManualView {
    CGFloat y = 104;
    _manualView = [[UIView alloc] initWithFrame:CGRectMake(0, y, kExpandedWidth, kExpandedHeight - y - 20)];
    [_panelContainer addSubview:_manualView];

    NSArray *buttons = @[
        @{@"icon": @"❤️", @"label": @"点赞", @"action": @"like"},
        @{@"icon": @"👤", @"label": @"关注", @"action": @"follow"},
        @{@"icon": @"⬆️", @"label": @"上滑", @"action": @"scroll"},
        @{@"icon": @"📸", @"label": @"截图", @"action": @"screenshot"},
        @{@"icon": @"👥", @"label": @"采粉", @"action": @"fans"},
        @{@"icon": @"🎬", @"label": @"采视频", @"action": @"videos"},
        @{@"icon": @"👤", @"label": @"账号", @"action": @"account"},
        @{@"icon": @"🤖", @"label": @"浏览", @"action": @"browse"},
    ];

    CGFloat bw = (kExpandedWidth - 3*kMargin) / 4;
    CGFloat bh = bw + 16;
    int col = 0, row = 0;
    CGFloat startY = 8;

    for (NSDictionary *info in buttons) {
        CGFloat bx = kMargin + col * (bw + kMargin/2);
        CGFloat by = startY + row * (bh + kMargin/2);
        UIView *v = [self _createActionButton:info frame:CGRectMake(bx, by, bw, bh)];
        [_manualView addSubview:v];
        col++;
        if (col >= 4) { col = 0; row++; }
    }

    // 底部信息
    CGFloat infoY = startY + 2 * (bh + kMargin/2) + 16;
    UILabel *devLabel = [[UILabel alloc] initWithFrame:CGRectMake(kMargin, infoY, kExpandedWidth - 2*kMargin, 14)];
    devLabel.font = [UIFont systemFontOfSize:9];
    devLabel.textColor = XN_DIM_TEXT;
    devLabel.text = [NSString stringWithFormat:@"📱 %@", _panelDeviceId ?: @"--"];
    [_manualView addSubview:devLabel];

    UILabel *verLabel = [[UILabel alloc] initWithFrame:CGRectMake(kMargin, infoY + 16, kExpandedWidth - 2*kMargin, 12)];
    verLabel.text = @"XNOWER v1.3.0 • iOS 注入插件";
    verLabel.font = [UIFont systemFontOfSize:8];
    verLabel.textColor = [UIColor colorWithWhite:1 alpha:0.25];
    verLabel.textAlignment = NSTextAlignmentCenter;
    [_manualView addSubview:verLabel];
}

- (UIView *)_createActionButton:(NSDictionary *)info frame:(CGRect)frame {
    UIView *view = [[UIView alloc] initWithFrame:frame];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    CGFloat bs = MIN(frame.size.width - 8, 44);
    button.frame = CGRectMake((frame.size.width - bs) / 2, 2, bs, bs);
    button.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    button.layer.cornerRadius = bs / 2;
    button.clipsToBounds = YES;
    button.titleLabel.font = [UIFont systemFontOfSize:22];
    [button setTitle:info[@"icon"] forState:UIControlStateNormal];
    button.tag = _actionButtons.count;
    [button addTarget:self action:@selector(_actionButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [view addSubview:button];
    [_actionButtons addObject:button];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, bs + 4, frame.size.width, 14)];
    label.text = info[@"label"];
    label.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    label.textColor = [UIColor colorWithWhite:1 alpha:0.7];
    label.textAlignment = NSTextAlignmentCenter;
    [view addSubview:label];

    return view;
}

- (void)_actionButtonTapped:(UIButton *)sender {
    NSArray *actions = @[@"like", @"follow", @"scroll", @"screenshot",
                          @"fans", @"videos", @"account", @"browse"];
    NSString *action = actions[sender.tag];

    // 动画反馈
    [UIView animateWithDuration:0.1 animations:^{
        sender.transform = CGAffineTransformMakeScale(0.85, 0.85);
        sender.backgroundColor = [UIColor colorWithWhite:1 alpha:0.25];
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.2 animations:^{
            sender.transform = CGAffineTransformIdentity;
            sender.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
        }];
    }];

    // 代理回调
    if ([action isEqualToString:@"like"]) [self.delegate floatingPanelDidTapLike:self];
    else if ([action isEqualToString:@"follow"]) [self.delegate floatingPanelDidTapFollow:self];
    else if ([action isEqualToString:@"scroll"]) [self.delegate floatingPanelDidTapScrollDown:self];
    else if ([action isEqualToString:@"screenshot"]) [self.delegate floatingPanelDidTapScreenshot:self];
    else if ([action isEqualToString:@"fans"]) [self.delegate floatingPanelDidTapCollectFans:self];
    else if ([action isEqualToString:@"videos"]) [self.delegate floatingPanelDidTapCollectVideos:self];
    else if ([action isEqualToString:@"account"]) [self.delegate floatingPanelDidTapAccountInfo:self];
    else if ([action isEqualToString:@"browse"]) [self.delegate floatingPanelDidTapSmartBrowse:self];
}

#pragma mark - Tab 2: 账号列表

- (void)_buildAccountListView {
    CGFloat y = 104;
    _accountScrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, y, kExpandedWidth, kExpandedHeight - y - 20)];
    _accountScrollView.showsVerticalScrollIndicator = NO;
    [_panelContainer addSubview:_accountScrollView];
}

- (void)_refreshAccountList {
    for (UIView *v in _accountScrollView.subviews) [v removeFromSuperview];

    UIView *content = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kExpandedWidth, 60 + _accountList.count * 52)];
    [_accountScrollView addSubview:content];
    _accountScrollView.contentSize = content.frame.size;

    CGFloat cy = 8;
    for (NSDictionary *acc in _accountList) {
        UIView *row = [self _createAccountRow:acc frame:CGRectMake(kMargin, cy, kExpandedWidth - 2*kMargin, 44)];
        [content addSubview:row];
        cy += 48;
    }

    if (_accountList.count == 0) {
        UILabel *empty = [[UILabel alloc] initWithFrame:CGRectMake(0, 24, kExpandedWidth, 20)];
        empty.text = @"暂无账号，请在后台导入";
        empty.font = [UIFont systemFontOfSize:11];
        empty.textColor = XN_DIM_TEXT;
        empty.textAlignment = NSTextAlignmentCenter;
        [content addSubview:empty];
    }
}

- (UIView *)_createAccountRow:(NSDictionary *)acc frame:(CGRect)frame {
    UIView *row = [[UIView alloc] initWithFrame:frame];
    row.backgroundColor = XN_CARD_BG;
    row.layer.cornerRadius = 8;
    row.tag = [acc[@"id"] integerValue];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_accountRowTapped:)];
    [row addGestureRecognizer:tap];

    UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(12, 8, 160, 16)];
    name.text = acc[@"nickname"] ?: @"?";
    name.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    name.textColor = XN_TEXT_COLOR;
    [row addSubview:name];

    UILabel *tk = [[UILabel alloc] initWithFrame:CGRectMake(12, 26, 100, 12)];
    tk.text = acc[@"aweme_number"] ?: @"";
    tk.font = [UIFont systemFontOfSize:9];
    tk.textColor = XN_DIM_TEXT;
    [row addSubview:tk];

    // 状态标记
    NSString *status = acc[@"status"] ?: @"idle";
    UIColor *statusColor = [status isEqualToString:@"active"] ? XN_ON_COLOR :
                           [status isEqualToString:@"risk_control"] ? [UIColor orangeColor] :
                           [UIColor colorWithWhite:1 alpha:0.3];
    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(frame.size.width - 28, 14, 8, 8)];
    dot.backgroundColor = statusColor;
    dot.layer.cornerRadius = 4;
    [row addSubview:dot];

    return row;
}

- (void)_accountRowTapped:(UITapGestureRecognizer *)tap {
    NSInteger accId = tap.view.tag;
    [self.delegate floatingPanel:self didSelectAccountId:accId];
}

- (void)_tapSwitchAccount {
    [self _switchToTab:2];
    [self.delegate floatingPanelDidRequestAccountList:self];
}

#pragma mark - 动画切换

- (void)_handleTap {
    if (_isExpanded) return;
    [self _expandPanel];
}

- (void)_togglePanel {
    _isExpanded ? [self _collapsePanel] : [self _expandPanel];
}

- (void)_expandPanel {
    if (!_panelContainer) [self _buildExpandedPanel];
    _isExpanded = YES;

    [self _updateUI];
    [self _refreshAccountList];

    CGFloat oldW = self.frame.size.width;
    CGFloat oldH = self.frame.size.height;

    _panelContainer.alpha = 1;
    _panelContainer.transform = CGAffineTransformMakeScale(0.3, 0.3);

    self.frame = self.superview ?
        CGRectMake(self.frame.origin.x - (kExpandedWidth - oldW)/2,
                   self.frame.origin.y - (kExpandedHeight - oldH)/2 + 20,
                   kExpandedWidth, kExpandedHeight) : self.frame;

    _badgeButton.alpha = 0;

    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.8
                        options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.panelContainer.transform = CGAffineTransformIdentity;
        self.layer.shadowOpacity = 0.5;
    } completion:nil];
}

- (void)_collapsePanel {
    _isExpanded = NO;
    CGFloat cx = self.badgeButton.center.x;
    CGFloat cy = self.badgeButton.center.y;

    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5
                        options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.panelContainer.alpha = 0;
        self.panelContainer.transform = CGAffineTransformMakeScale(0.5, 0.5);
        self.frame = CGRectMake(self.frame.origin.x + cx, self.frame.origin.y + cy,
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
            break;
        case UIGestureRecognizerStateChanged: {
            CGPoint newCenter = CGPointMake(_dragStart.x + translation.x, _dragStart.y + translation.y);
            CGFloat hw = _isExpanded ? kExpandedWidth/2 : kCollapsedSize/2;
            CGFloat hh = _isExpanded ? kExpandedHeight/2 : kCollapsedSize/2;
            newCenter.x = MAX(hw, MIN([UIScreen mainScreen].bounds.size.width - hw, newCenter.x));
            newCenter.y = MAX(50 + hh, MIN([UIScreen mainScreen].bounds.size.height - 100 - hh, newCenter.y));
            self.center = newCenter;
            break;
        }
        case UIGestureRecognizerStateEnded:
            _isDragging = NO;
            break;
        default: break;
    }
}

#pragma mark - 公共方法

- (void)showInWindow:(UIWindow *)window {
    if (!window) return;
    [window addSubview:self];
    self.transform = CGAffineTransformMakeScale(0.5, 0.5);
    self.alpha = 0;
    [UIView animateWithDuration:0.3 delay:0.5 usingSpringWithDamping:0.6 initialSpringVelocity:0.8
                        options:UIViewAnimationOptionCurveEaseOut animations:^{
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
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusDot.backgroundColor = connected ? XN_ACCENT_COLOR : [UIColor redColor];
        self.connLabel.text = connected ? @"● 已连接" : @"○ 未连接";
        self.connLabel.textColor = connected ? XN_ACCENT_COLOR : XN_DIM_TEXT;
    });
}

- (void)setDeviceId:(NSString *)deviceId {
    _panelDeviceId = deviceId;
}

- (void)setServerURL:(NSString *)serverURL {
    _panelServerURL = serverURL;
}

- (void)setAccountInfo:(NSDictionary *)account {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *name = account[@"nickname"] ?: account[@"unique_id"] ?: @"";
        if (name.length > 0) {
            self.nameLabel.text = name;
            NSString *followers = account[@"followers"] ?: account[@"fans_count"] ?: @(0);
            self.followerLabel.text = [NSString stringWithFormat:@"粉丝 %@", followers];
            // Try to load avatar
            NSString *url = account[@"avatar_url"];
            if (url.length > 0 && [NSURL URLWithString:url]) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    NSData *imgData = [NSData dataWithContentsOfURL:[NSURL URLWithString:url]];
                    if (imgData) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            self.avatarView.image = [UIImage imageWithData:imgData];
                        });
                    }
                });
            }
        } else {
            self.nameLabel.text = @"未登录";
            self.followerLabel.text = @"";
        }
    });
}

- (void)setConnectionQuality:(NSString *)quality {
    // Not used in new design — status represented by connector
}

- (void)setAccountList:(NSArray<NSDictionary *> *)accounts {
    _accountList = accounts;
    [self _refreshAccountList];
}

- (void)_updateUI {
    self.connLabel.text = _isConnected ? @"● 已连接" : @"○ 未连接";
    self.connLabel.textColor = _isConnected ? XN_ACCENT_COLOR : XN_DIM_TEXT;
}

@end

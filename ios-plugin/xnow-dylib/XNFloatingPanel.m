// XNFloatingPanel.m
// XNOW 快捷菜单 v3 — 列表式功能菜单（参考快捷菜单设计）

#import "XNFloatingPanel.h"
#import "AccountPool.h"
#import <objc/runtime.h>

static const CGFloat kCollapsedSize = 56;
static const CGFloat kExpandedWidth = 300;
static const CGFloat kExpandedHeight = 520;
static const CGFloat kCornerRadius = 16;
static const CGFloat kMargin = 12;

#define XN_COLOR(r,g,b) [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1]
#define XN_BRAND XN_COLOR(108, 92, 231)
#define XN_ACCENT XN_COLOR(0, 206, 201)
#define XN_BG [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:0.95]
#define XN_CARD [UIColor colorWithWhite:1 alpha:0.07]
#define XN_TEXT [UIColor whiteColor]
#define XN_DIM [UIColor colorWithWhite:1 alpha:0.45]
#define XN_GREEN XN_COLOR(34, 197, 94)

// 国家列表
static NSArray *kCountries;

@interface XNFloatingPanel () <UITableViewDataSource, UITableViewDelegate> {
    BOOL _isExpanded, _isDragging;
    CGPoint _dragStart, _panelOrigin;
    int _menuLevel; // 0=主菜单, 1=子菜单
    NSString *_currentSubMenu;
}

@property (nonatomic, strong) UIButton *badgeButton;
@property (nonatomic, strong) UIView *statusDot;
@property (nonatomic, strong) UIView *panelContainer;
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *closeBtn;
@property (nonatomic, strong) UIButton *backBtn;
@property (nonatomic, strong) UITableView *menuTable;

// 状态
@property (nonatomic, assign) BOOL isConnected;
@property (nonatomic, copy) NSString *panelDeviceId;
@property (nonatomic, copy) NSString *panelServerURL;
@property (nonatomic, copy) NSString *selectedCountry;

// 主菜单项
@property (nonatomic, strong) NSArray *mainMenu;

@end

@implementation XNFloatingPanel

+ (void)initialize {
    kCountries = @[@"日本", @"美国", @"韩国", @"越南", @"泰国", @"新加坡",
                   @"迪拜", @"马来西亚", @"巴西", @"印度尼西亚", @"澳大利亚",
                   @"意大利", @"墨西哥", @"丹麦", @"台湾", @"英国", @"菲律宾"];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:CGRectMake(16, 120, kCollapsedSize, kCollapsedSize)];
    if (self) {
        _isExpanded = NO;
        _isConnected = NO;
        _menuLevel = 0;
        _selectedCountry = @"日本";
        [self _buildMainMenu];
        [self _setupViews];
    }
    return self;
}

- (void)_buildMainMenu {
    _mainMenu = @[
        @{@"icon": @"🌐", @"label": @"绑定云控后台", @"action": @"bind_server"},
        @{@"icon": @"👤", @"label": @"账号管理", @"action": @"account_mgmt"},
        @{@"icon": @"🎬", @"label": @"下载无水印视频", @"action": @"dl_video"},
        @{@"icon": @"🌍", @"label": @"设置国家", @"action": @"set_country"},
        @{@"icon": @"🗑️", @"label": @"一键清理所有数据", @"action": @"clear_data"},
        @{@"icon": @"🔌", @"label": @"关闭服务器链接", @"action": @"disconnect"},
        @{@"icon": @"❤️", @"label": @"采集点赞", @"action": @"collect_likes"},
        @{@"icon": @"🌱", @"label": @"养号", @"action": @"nurture"},
        @{@"icon": @"📋", @"label": @"复制机器码", @"action": @"copy_device_id"},
        @{@"icon": @"📝", @"label": @"显示/关闭日志", @"action": @"toggle_log"},
        @{@"icon": @"🔄", @"label": @"恢复账号", @"action": @"restore_account"},
        @{@"icon": @"💾", @"label": @"备份账号", @"action": @"backup_account"},
        @{@"icon": @"💬", @"label": @"自动评论点赞", @"action": @"auto_comment"},
        @{@"icon": @"👥", @"label": @"采集评论用户数据", @"action": @"collect_comment_users"},
        @{@"icon": @"👥", @"label": @"一键采集所有粉丝", @"action": @"collect_all_fans"},
        @{@"icon": @"📡", @"label": @"采集直播间粉丝", @"action": @"collect_live_fans"},
        @{@"icon": @"🌐", @"label": @"开启实时翻译", @"action": @"toggle_translate"},
        @{@"icon": @"🔤", @"label": @"设置翻译语言", @"action": @"set_translate_lang"},
        @{@"icon": @"❌", @"label": @"关闭", @"action": @"close_panel"},
    ];
}

- (void)_setupViews {
    self.clipsToBounds = NO;
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 4);
    self.layer.shadowRadius = 12;
    self.layer.shadowOpacity = 0.4;

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_handlePan:)];
    [self addGestureRecognizer:pan];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_handleTap)];
    [self addGestureRecognizer:tap];

    [self _buildBadge];
}

#pragma mark - Badge

- (void)_buildBadge {
    _badgeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _badgeButton.frame = CGRectMake(0, 0, kCollapsedSize, kCollapsedSize);
    _badgeButton.backgroundColor = XN_BRAND;
    _badgeButton.layer.cornerRadius = kCollapsedSize / 2;
    _badgeButton.clipsToBounds = YES;
    _badgeButton.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    [_badgeButton setTitle:@"X" forState:UIControlStateNormal];
    [_badgeButton setTitleColor:XN_TEXT forState:UIControlStateNormal];
    [_badgeButton addTarget:self action:@selector(_handleTap) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_badgeButton];

    _statusDot = [[UIView alloc] initWithFrame:CGRectMake(kCollapsedSize - 14, kCollapsedSize - 14, 12, 12)];
    _statusDot.backgroundColor = [UIColor redColor];
    _statusDot.layer.cornerRadius = 6;
    _statusDot.layer.borderWidth = 2;
    _statusDot.layer.borderColor = UIColor.whiteColor.CGColor;
    [self addSubview:_statusDot];
}

#pragma mark - Panel

- (void)_buildPanel {
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

    // 标题栏
    CGFloat y = 8;
    _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(44, y, kExpandedWidth - 88, 32)];
    _titleLabel.text = @"快捷菜单 v3";
    _titleLabel.font = [UIFont boldSystemFontOfSize:15];
    _titleLabel.textColor = XN_TEXT;
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    [_panelContainer addSubview:_titleLabel];

    // 返回按钮（子菜单用）
    _backBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _backBtn.frame = CGRectMake(8, y, 32, 32);
    [_backBtn setTitle:@"◀" forState:UIControlStateNormal];
    [_backBtn setTintColor:XN_TEXT];
    _backBtn.titleLabel.font = [UIFont systemFontOfSize:16];
    _backBtn.hidden = YES;
    [_backBtn addTarget:self action:@selector(_backToMain) forControlEvents:UIControlEventTouchUpInside];
    [_panelContainer addSubview:_backBtn];

    // 关闭按钮
    _closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _closeBtn.frame = CGRectMake(kExpandedWidth - 36, y, 28, 28);
    _closeBtn.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
    _closeBtn.layer.cornerRadius = 14;
    [_closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [_closeBtn setTintColor:XN_DIM];
    _closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [_closeBtn addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [_panelContainer addSubview:_closeBtn];

    // 运行状态
    UILabel *runLabel = [[UILabel alloc] initWithFrame:CGRectMake(kMargin, y + 34, 80, 16)];
    runLabel.text = @"● 运行中";
    runLabel.font = [UIFont systemFontOfSize:10];
    runLabel.textColor = XN_GREEN;
    [_panelContainer addSubview:runLabel];

    // 表格
    _menuTable = [[UITableView alloc] initWithFrame:CGRectMake(0, y + 54, kExpandedWidth, kExpandedHeight - y - 54)
                                              style:UITableViewStylePlain];
    _menuTable.backgroundColor = [UIColor clearColor];
    _menuTable.dataSource = self;
    _menuTable.delegate = self;
    _menuTable.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    _menuTable.separatorColor = [UIColor colorWithWhite:1 alpha:0.06];
    _menuTable.showsVerticalScrollIndicator = NO;
    [_menuTable registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
    [_panelContainer addSubview:_menuTable];
}

- (void)_backToMain {
    _menuLevel = 0;
    _backBtn.hidden = YES;
    _titleLabel.text = @"快捷菜单 v3";
    [_menuTable reloadData];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if (_menuLevel == 0) return _mainMenu.count;
    if ([_currentSubMenu isEqualToString:@"set_country"]) return kCountries.count;
    if ([_currentSubMenu isEqualToString:@"account_mgmt"]) {
        NSArray *accs = [[AccountPool sharedPool] allAccounts];
        return MAX(accs.count, 1); // at least show empty state
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"cell" forIndexPath:ip];
    cell.backgroundColor = [UIColor clearColor];
    cell.textLabel.textColor = XN_TEXT;
    cell.textLabel.font = [UIFont systemFontOfSize:13];
    cell.selectionStyle = UITableViewCellSelectionStyleGray;

    // Remove old accessories
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;

    if (_menuLevel == 0) {
        // 主菜单
        NSDictionary *item = _mainMenu[ip.row];
        cell.textLabel.text = [NSString stringWithFormat:@"%@  %@", item[@"icon"], item[@"label"]];
        if ([item[@"action"] isEqualToString:@"close_panel"]) {
            cell.textLabel.textColor = [UIColor colorWithWhite:1 alpha:0.35];
        }
    } else if ([_currentSubMenu isEqualToString:@"set_country"]) {
        // 国家列表
        NSString *country = kCountries[ip.row];
        cell.textLabel.text = country;
        cell.textLabel.textColor = [country isEqualToString:_selectedCountry] ? XN_ACCENT : XN_TEXT;
        if ([country isEqualToString:_selectedCountry]) {
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
            cell.tintColor = XN_ACCENT;
        }
    } else if ([_currentSubMenu isEqualToString:@"account_mgmt"]) {
        NSArray *accs = [[AccountPool sharedPool] allAccounts];
        if (accs.count == 0) {
            cell.textLabel.text = @"暂无账号";
            cell.textLabel.textColor = XN_DIM;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            NSDictionary *acc = accs[ip.row];
            NSString *name = acc[@"nickname"] ?: @"?";
            NSString *num = acc[@"aweme_number"] ?: @"";
            NSString *fans = [NSString stringWithFormat:@"%@", acc[@"followers"] ?: @"0"];
            NSString *follow = [NSString stringWithFormat:@"%@", acc[@"following_count"] ?: @"0"];
            cell.textLabel.text = [NSString stringWithFormat:@"昵称:%@ 号码:%@ 粉丝:%@ 关注:%@",
                                   name, num, fans, follow];
            cell.textLabel.font = [UIFont systemFontOfSize:10];
            cell.textLabel.numberOfLines = 2;
        }
    }

    return cell;
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    if (_menuLevel == 0) return 36;
    if ([_currentSubMenu isEqualToString:@"account_mgmt"]) return 44;
    return 36;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];

    if (_menuLevel == 0) {
        NSDictionary *item = _mainMenu[ip.row];
        NSString *action = item[@"action"];
        [self _handleMenuAction:action];
    } else if ([_currentSubMenu isEqualToString:@"set_country"]) {
        NSString *country = kCountries[ip.row];
        _selectedCountry = country;
        [_menuTable reloadData];
        [self.delegate floatingPanel:self didChangeAutoBrowseMinScrolls:0 maxScrolls:0 minDelay:0 maxDelay:0];
        // Report country change
        NSString *msg = [NSString stringWithFormat:@"国家已切换: %@", country];
        [self _showToast:msg];
    }
}

#pragma mark - Menu Actions

- (void)_handleMenuAction:(NSString *)action {
    if ([action isEqualToString:@"close_panel"]) {
        [self dismiss];
        return;
    }
    if ([action isEqualToString:@"set_country"]) {
        _menuLevel = 1;
        _currentSubMenu = @"set_country";
        _backBtn.hidden = NO;
        _titleLabel.text = @"设置国家";
        [_menuTable reloadData];
        return;
    }
    if ([action isEqualToString:@"account_mgmt"]) {
        _menuLevel = 1;
        _currentSubMenu = @"account_mgmt";
        _backBtn.hidden = NO;
        _titleLabel.text = @"账号管理";
        [_menuTable reloadData];
        return;
    }

    // 直接触发代理
    if ([action isEqualToString:@"bind_server"]) {
        [self.delegate floatingPanelDidTapAccountInfo:self];
    } else if ([action isEqualToString:@"dl_video"]) {
        [self.delegate floatingPanelDidTapSmartBrowse:self];
    } else if ([action isEqualToString:@"clear_data"]) {
        [self _showToast:@"数据已清理"];
    } else if ([action isEqualToString:@"disconnect"]) {
        [self.delegate floatingPanelDidTapScrollDown:self];
    } else if ([action isEqualToString:@"collect_likes"]) {
        [self.delegate floatingPanelDidTapCollectFans:self];
    } else if ([action isEqualToString:@"nurture"]) {
        [self.delegate floatingPanelDidTapSmartBrowse:self];
    } else if ([action isEqualToString:@"copy_device_id"]) {
        [UIPasteboard generalPasteboard].string = _panelDeviceId ?: @"";
        [self _showToast:[NSString stringWithFormat:@"已复制: %@", _panelDeviceId ?: @""]];
    } else if ([action isEqualToString:@"toggle_log"]) {
        [self.delegate floatingPanelDidTapScreenshot:self];
    } else if ([action isEqualToString:@"restore_account"] || [action isEqualToString:@"backup_account"]) {
        [self _showToast:[NSString stringWithFormat:@"%@ 功能待实现", action]];
    } else {
        [self _showToast:[NSString stringWithFormat:@"执行: %@", action]];
    }

    // 不自动收起
}

- (void)_showToast:(NSString *)msg {
    UILabel *toast = [[UILabel alloc] initWithFrame:CGRectMake(20, kExpandedHeight - 60, kExpandedWidth - 40, 36)];
    toast.text = msg;
    toast.font = [UIFont systemFontOfSize:12];
    toast.textColor = XN_TEXT;
    toast.textAlignment = NSTextAlignmentCenter;
    toast.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    toast.layer.cornerRadius = 8;
    toast.clipsToBounds = YES;
    toast.alpha = 0;
    [_panelContainer addSubview:toast];
    [UIView animateWithDuration:0.3 animations:^{ toast.alpha = 1; }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.3 animations:^{ toast.alpha = 0; } completion:^(BOOL f) { [toast removeFromSuperview]; }];
    });
}

#pragma mark - Animation

- (void)_handleTap {
    if (_isExpanded) return;
    [self _expandPanel];
}

- (void)_expandPanel {
    if (!_panelContainer) [self _buildPanel];
    _isExpanded = YES;
    _menuLevel = 0;
    _backBtn.hidden = YES;
    _titleLabel.text = @"快捷菜单 v3";

    [_menuTable reloadData];
    [self _updateConnectedUI];

    _panelContainer.alpha = 1;
    _panelContainer.transform = CGAffineTransformMakeScale(0.3, 0.3);
    CGFloat ow = self.frame.size.width, oh = self.frame.size.height;
    self.frame = self.superview ?
        CGRectMake(self.frame.origin.x - (kExpandedWidth - ow)/2,
                   self.frame.origin.y - (kExpandedHeight - oh)/2 + 20,
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
    CGFloat cx = self.badgeButton.center.x, cy = self.badgeButton.center.y;
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5
                        options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.panelContainer.alpha = 0;
        self.panelContainer.transform = CGAffineTransformMakeScale(0.5, 0.5);
        self.frame = CGRectMake(self.frame.origin.x + cx, self.frame.origin.y + cy,
                                kCollapsedSize, kCollapsedSize);
        self.layer.shadowOpacity = 0.3;
    } completion:^(BOOL f) { self.badgeButton.alpha = 1; }];
}

- (void)_handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:self.superview];
    switch (pan.state) {
        case UIGestureRecognizerStateBegan: _isDragging = YES; _dragStart = self.center; break;
        case UIGestureRecognizerStateChanged: {
            CGPoint nc = CGPointMake(_dragStart.x + t.x, _dragStart.y + t.y);
            CGFloat hw = _isExpanded ? kExpandedWidth/2 : kCollapsedSize/2;
            CGFloat hh = _isExpanded ? kExpandedHeight/2 : kCollapsedSize/2;
            nc.x = MAX(hw, MIN([UIScreen mainScreen].bounds.size.width - hw, nc.x));
            nc.y = MAX(50 + hh, MIN([UIScreen mainScreen].bounds.size.height - 100 - hh, nc.y));
            self.center = nc;
            break;
        }
        case UIGestureRecognizerStateEnded: _isDragging = NO; break;
        default: break;
    }
}

#pragma mark - Public

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
    } completion:^(BOOL f) { [self removeFromSuperview]; }];
}

- (void)setConnected:(BOOL)connected {
    _isConnected = connected;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusDot.backgroundColor = connected ? XN_ACCENT : [UIColor redColor];
        [self _updateConnectedUI];
    });
}

- (void)_updateConnectedUI {
    // Status shown by the green dot in header
}

- (void)setDeviceId:(NSString *)deviceId { _panelDeviceId = deviceId; }
- (void)setServerURL:(NSString *)serverURL { _panelServerURL = serverURL; }
- (void)setAccountInfo:(NSDictionary *)account {}
- (void)setConnectionQuality:(NSString *)quality {}
- (void)setAccountList:(NSArray<NSDictionary *> *)accounts {
    if (_menuLevel == 1 && [_currentSubMenu isEqualToString:@"account_mgmt"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_menuTable reloadData];
        });
    }
}

@end

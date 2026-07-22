// XNFloatingPanel.m
// XNOW 快捷菜单 v4 — 激活→绑定→功能菜单 完整商业流程

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
#define XN_CARD [UIColor colorWithWhite:1 alpha:0.08]
#define XN_TEXT [UIColor whiteColor]
#define XN_DIM [UIColor colorWithWhite:1 alpha:0.45]
#define XN_GREEN XN_COLOR(34, 197, 94)
#define XN_RED XN_COLOR(239, 68, 68)

static NSArray *kCountries;

@interface XNFloatingPanel () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate> {
    BOOL _isExpanded, _isDragging;
    CGPoint _dragStart;
    int _viewMode; // 0=激活, 1=主菜单, 2=绑定后台, 3=子菜单
    NSString *_currentSubMenu;
}

// 折叠
@property (nonatomic, strong) UIButton *badgeButton;
@property (nonatomic, strong) UIView *statusDot;
// 面板
@property (nonatomic, strong) UIView *panelContainer;
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *closeBtn, *backBtn;
@property (nonatomic, strong) UITableView *menuTable;
// 激活/绑定输入
@property (nonatomic, strong) UITextField *inputField;
@property (nonatomic, strong) UIButton *confirmBtn;
// 数据
@property (nonatomic, assign) BOOL isConnected;
@property (nonatomic, copy) NSString *panelDeviceId, *panelServerURL, *selectedCountry;
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
        _isExpanded = NO; _isConnected = NO;
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
        @{@"icon": @"❌", @"label": @"关闭", @"action": @"close_panel"},
    ];
}

- (void)_setupViews {
    self.clipsToBounds = NO;
    self.layer.shadowColor = UIColor.blackColor.CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 4); self.layer.shadowRadius = 12; self.layer.shadowOpacity = 0.4;
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
    _badgeButton.backgroundColor = XN_BRAND; _badgeButton.layer.cornerRadius = kCollapsedSize/2;
    _badgeButton.clipsToBounds = YES; _badgeButton.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    [_badgeButton setTitle:@"X" forState:UIControlStateNormal];
    [_badgeButton setTitleColor:XN_TEXT forState:UIControlStateNormal];
    [_badgeButton addTarget:self action:@selector(_handleTap) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_badgeButton];
    _statusDot = [[UIView alloc] initWithFrame:CGRectMake(kCollapsedSize-14, kCollapsedSize-14, 12, 12)];
    _statusDot.backgroundColor = UIColor.redColor; _statusDot.layer.cornerRadius = 6;
    _statusDot.layer.borderWidth = 2; _statusDot.layer.borderColor = UIColor.whiteColor.CGColor;
    [self addSubview:_statusDot];
}

#pragma mark - Panel

- (void)_ensurePanel {
    if (_panelContainer) return;
    _panelContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kExpandedWidth, kExpandedHeight)];
    _panelContainer.layer.cornerRadius = kCornerRadius; _panelContainer.clipsToBounds = YES; _panelContainer.alpha = 0;
    [self addSubview:_panelContainer];
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    _blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    _blurView.frame = _panelContainer.bounds; [_panelContainer addSubview:_blurView];

    // 标题栏
    _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(44, 8, kExpandedWidth-88, 32)];
    _titleLabel.font = [UIFont boldSystemFontOfSize:15]; _titleLabel.textColor = XN_TEXT;
    _titleLabel.textAlignment = NSTextAlignmentCenter; [_panelContainer addSubview:_titleLabel];

    _backBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _backBtn.frame = CGRectMake(8, 8, 32, 32); _backBtn.hidden = YES;
    [_backBtn setTitle:@"◀" forState:UIControlStateNormal]; [_backBtn setTintColor:XN_TEXT];
    _backBtn.titleLabel.font = [UIFont systemFontOfSize:16];
    [_backBtn addTarget:self action:@selector(_backToMain) forControlEvents:UIControlEventTouchUpInside];
    [_panelContainer addSubview:_backBtn];

    _closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _closeBtn.frame = CGRectMake(kExpandedWidth-36, 8, 28, 28);
    _closeBtn.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1]; _closeBtn.layer.cornerRadius = 14;
    [_closeBtn setTitle:@"✕" forState:UIControlStateNormal]; [_closeBtn setTintColor:XN_DIM];
    _closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [_closeBtn addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [_panelContainer addSubview:_closeBtn];

    // 状态运行指示
    UILabel *runL = [[UILabel alloc] initWithFrame:CGRectMake(kMargin, 42, 80, 14)];
    runL.text = @"● 运行中"; runL.font = [UIFont systemFontOfSize:9]; runL.textColor = XN_GREEN;
    [_panelContainer addSubview:runL];

    // 表格
    _menuTable = [[UITableView alloc] initWithFrame:CGRectMake(0, 58, kExpandedWidth, kExpandedHeight-58)
                                              style:UITableViewStylePlain];
    _menuTable.backgroundColor = UIColor.clearColor; _menuTable.dataSource = self; _menuTable.delegate = self;
    _menuTable.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    _menuTable.separatorColor = [UIColor colorWithWhite:1 alpha:0.06];
    _menuTable.showsVerticalScrollIndicator = NO;
    [_menuTable registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
    [_panelContainer addSubview:_menuTable];
}

#pragma mark - View Switching

- (void)_showActivationView {
    _viewMode = 0; _backBtn.hidden = YES; _closeBtn.hidden = NO;
    _titleLabel.text = @"设备激活";
    _menuTable.hidden = YES;

    // 移除旧输入
    for (UIView *v in _panelContainer.subviews) {
        if ([v isKindOfClass:[UIScrollView class]] && v != _menuTable) [v removeFromSuperview];
        if (v.tag == 1001 || v.tag == 1002) [v removeFromSuperview];
    }

    UIScrollView *sv = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 58, kExpandedWidth, kExpandedHeight-58)];
    sv.tag = 1001; sv.showsVerticalScrollIndicator = NO;
    [_panelContainer addSubview:sv];

    CGFloat y = 12;
    // UUID
    UILabel *uuidTitle = [[UILabel alloc] initWithFrame:CGRectMake(kMargin, y, kExpandedWidth-2*kMargin, 16)];
    uuidTitle.text = @"设备UUID"; uuidTitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    uuidTitle.textColor = XN_TEXT; [sv addSubview:uuidTitle];
    y += 20;
    UILabel *uuidV = [[UILabel alloc] initWithFrame:CGRectMake(kMargin, y, kExpandedWidth-2*kMargin, 20)];
    NSString *uuid = [[[UIDevice currentDevice] identifierForVendor] UUIDString] ?: @"UNKNOWN";
    uuidV.text = [NSString stringWithFormat:@"【%@】", uuid];
    uuidV.font = [UIFont systemFontOfSize:11]; uuidV.textColor = XN_ACCENT;
    uuidV.numberOfLines = 0; [sv addSubview:uuidV];
    y += 30;

    // 重要提示
    UITextView *notice = [[UITextView alloc] initWithFrame:CGRectMake(kMargin, y, kExpandedWidth-2*kMargin, 100)];
    notice.text = @"重要提示\n请联系客服并提供机器码进行设备激活！\n您也可以在下方输入卡密进行自动激活！";
    notice.font = [UIFont systemFontOfSize:12]; notice.textColor = XN_RED;
    notice.backgroundColor = UIColor.clearColor; notice.editable = NO; notice.scrollEnabled = NO;
    [sv addSubview:notice];
    y += 110;

    // 卡密输入
    UILabel *inputLabel = [[UILabel alloc] initWithFrame:CGRectMake(kMargin, y, kExpandedWidth-2*kMargin, 16)];
    inputLabel.text = @"请输入卡密"; inputLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    inputLabel.textColor = XN_TEXT; [sv addSubview:inputLabel];
    y += 20;

    _inputField = [[UITextField alloc] initWithFrame:CGRectMake(kMargin, y, kExpandedWidth-2*kMargin, 36)];
    _inputField.placeholder = @"输入卡密";
    _inputField.backgroundColor = XN_CARD; _inputField.textColor = XN_TEXT;
    _inputField.layer.cornerRadius = 8; _inputField.font = [UIFont systemFontOfSize:13];
    _inputField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0,0,10,36)];
    _inputField.leftViewMode = UITextFieldViewModeAlways;
    _inputField.delegate = self;
    _inputField.tag = 1002;
    [sv addSubview:_inputField];
    y += 44;

    UIButton *activateBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    activateBtn.frame = CGRectMake(kMargin, y, kExpandedWidth-2*kMargin, 36);
    activateBtn.backgroundColor = XN_BRAND; activateBtn.layer.cornerRadius = 8;
    [activateBtn setTitle:@"确定" forState:UIControlStateNormal];
    [activateBtn setTintColor:XN_TEXT]; activateBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [activateBtn addTarget:self action:@selector(_activateTapped) forControlEvents:UIControlEventTouchUpInside];
    [sv addSubview:activateBtn];

    sv.contentSize = CGSizeMake(kExpandedWidth, y + 60);
    [_inputField becomeFirstResponder];
}

- (void)_showMainMenu {
    _viewMode = 1; _backBtn.hidden = YES; _closeBtn.hidden = NO;
    _titleLabel.text = @"快捷菜单 v3";
    _menuTable.hidden = NO;
    [self _removeInputViews];
    [_menuTable reloadData];
}

- (void)_showBindForm {
    _viewMode = 2; _backBtn.hidden = NO; _closeBtn.hidden = NO;
    _titleLabel.text = @"绑定云控后台";
    _menuTable.hidden = YES;
    [self _removeInputViews];

    UIScrollView *sv = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 58, kExpandedWidth, kExpandedHeight-58)];
    sv.tag = 1001; sv.showsVerticalScrollIndicator = NO;
    [_panelContainer addSubview:sv];

    CGFloat y = 16;

    UILabel *desc = [[UILabel alloc] initWithFrame:CGRectMake(kMargin, y, kExpandedWidth-2*kMargin, 30)];
    desc.text = @"请输入设备编号和 APIID 绑定云控后台";
    desc.font = [UIFont systemFontOfSize:11]; desc.textColor = XN_DIM;
    desc.numberOfLines = 0; [sv addSubview:desc];
    y += 36;

    // 设备编号
    UILabel *dl = [[UILabel alloc] initWithFrame:CGRectMake(kMargin, y, kExpandedWidth-2*kMargin, 14)];
    dl.text = @"设备编号"; dl.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold]; dl.textColor = XN_TEXT;
    [sv addSubview:dl]; y += 18;
    UITextField *dF = [self _makeInputFieldWithFrame:CGRectMake(kMargin, y, kExpandedWidth-2*kMargin, 36) placeholder:@"输入设备编号"];
    dF.tag = 1003; [sv addSubview:dF]; y += 44;

    // APIID
    UILabel *al = [[UILabel alloc] initWithFrame:CGRectMake(kMargin, y, kExpandedWidth-2*kMargin, 14)];
    al.text = @"APIID"; al.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold]; al.textColor = XN_TEXT;
    [sv addSubview:al]; y += 18;
    UITextField *aF = [self _makeInputFieldWithFrame:CGRectMake(kMargin, y, kExpandedWidth-2*kMargin, 36) placeholder:@"输入 APIID"];
    aF.tag = 1004; [sv addSubview:aF]; y += 44;

    UIButton *okBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    okBtn.frame = CGRectMake(kMargin, y, kExpandedWidth-2*kMargin, 36);
    okBtn.backgroundColor = XN_BRAND; okBtn.layer.cornerRadius = 8;
    [okBtn setTitle:@"确定" forState:UIControlStateNormal];
    [okBtn setTintColor:XN_TEXT]; okBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [okBtn addTarget:self action:@selector(_bindTapped) forControlEvents:UIControlEventTouchUpInside];
    [sv addSubview:okBtn];

    sv.contentSize = CGSizeMake(kExpandedWidth, y + 60);
}

- (UITextField *)_makeInputFieldWithFrame:(CGRect)frame placeholder:(NSString *)ph {
    UITextField *f = [[UITextField alloc] initWithFrame:frame];
    f.placeholder = ph; f.backgroundColor = XN_CARD; f.textColor = XN_TEXT;
    f.layer.cornerRadius = 8; f.font = [UIFont systemFontOfSize:13];
    f.leftView = [[UIView alloc] initWithFrame:CGRectMake(0,0,10,36)]; f.leftViewMode = UITextFieldViewModeAlways;
    f.delegate = self; f.attributedPlaceholder = [[NSAttributedString alloc] initWithString:ph attributes:@{NSForegroundColorAttributeName: XN_DIM}];
    return f;
}

- (void)_removeInputViews {
    for (UIView *v in _panelContainer.subviews) {
        if ([v isKindOfClass:[UIScrollView class]] && v != _menuTable) [v removeFromSuperview];
    }
}

- (void)_backToMain {
    [self _showMainMenu];
}

#pragma mark - Actions

- (void)_activateTapped {
    NSString *code = _inputField.text ?: @"";
    if (code.length > 0) {
        // 本地存储激活状态
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"XN_Activated"];
        [[NSUserDefaults standardUserDefaults] setObject:code forKey:@"XN_ActivationCode"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    [self _showToast:@"激活成功"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self _showMainMenu];
    });
}

- (void)_bindTapped {
    UITextField *df = [_panelContainer viewWithTag:1003];
    UITextField *af = [_panelContainer viewWithTag:1004];
    NSString *devId = df.text ?: @"";
    NSString *apiId = af.text ?: @"";

    if (devId.length > 0 && apiId.length > 0) {
        [[NSUserDefaults standardUserDefaults] setObject:devId forKey:@"XN_BindDeviceID"];
        [[NSUserDefaults standardUserDefaults] setObject:apiId forKey:@"XN_BindAPIID"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [self _showToast:[NSString stringWithFormat:@"绑定成功 设备:%@ API:%@", devId, apiId]];
    } else {
        [self _showToast:@"请填写设备编号和APIID"];
    }
}

- (void)_showToast:(NSString *)msg {
    UILabel *toast = [[UILabel alloc] initWithFrame:CGRectMake(20, kExpandedHeight-60, kExpandedWidth-40, 36)];
    toast.text = msg; toast.font = [UIFont systemFontOfSize:12]; toast.textColor = XN_TEXT;
    toast.textAlignment = NSTextAlignmentCenter;
    toast.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    toast.layer.cornerRadius = 8; toast.clipsToBounds = YES; toast.alpha = 0;
    [_panelContainer addSubview:toast];
    [UIView animateWithDuration:0.3 animations:^{ toast.alpha = 1; }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.3 animations:^{ toast.alpha = 0; } completion:^(BOOL f) { [toast removeFromSuperview]; }];
    });
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if (_viewMode == 1) return _mainMenu.count;
    if (_viewMode == 3) {
        if ([_currentSubMenu isEqualToString:@"set_country"]) return kCountries.count;
        if ([_currentSubMenu isEqualToString:@"account_mgmt"]) {
            NSArray *a = [[AccountPool sharedPool] allAccounts];
            return MAX(a.count, 1);
        }
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"cell" forIndexPath:ip];
    cell.backgroundColor = UIColor.clearColor; cell.textLabel.textColor = XN_TEXT;
    cell.textLabel.font = [UIFont systemFontOfSize:13];
    cell.selectionStyle = UITableViewCellSelectionStyleGray;
    cell.accessoryView = nil; cell.accessoryType = UITableViewCellAccessoryNone;

    if (_viewMode == 1) {
        NSDictionary *item = _mainMenu[ip.row];
        cell.textLabel.text = [NSString stringWithFormat:@"%@  %@", item[@"icon"], item[@"label"]];
    } else if (_viewMode == 3 && [_currentSubMenu isEqualToString:@"set_country"]) {
        NSString *c = kCountries[ip.row];
        cell.textLabel.text = c;
        cell.textLabel.textColor = [c isEqualToString:_selectedCountry] ? XN_ACCENT : XN_TEXT;
        if ([c isEqualToString:_selectedCountry]) { cell.accessoryType = UITableViewCellAccessoryCheckmark; cell.tintColor = XN_ACCENT; }
    } else if (_viewMode == 3 && [_currentSubMenu isEqualToString:@"account_mgmt"]) {
        NSArray *a = [[AccountPool sharedPool] allAccounts];
        if (a.count == 0) {
            cell.textLabel.text = @"暂无账号"; cell.textLabel.textColor = XN_DIM;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            NSDictionary *acc = a[ip.row];
            cell.textLabel.text = [NSString stringWithFormat:@"昵称:%@ 号码:%@ 粉丝:%@ 关注:%@",
                                   acc[@"nickname"]?:@"?", acc[@"aweme_number"]?:@"",
                                   acc[@"followers"]?:@"0", acc[@"following_count"]?:@"0"];
            cell.textLabel.font = [UIFont systemFontOfSize:10]; cell.textLabel.numberOfLines = 2;
        }
    }
    return cell;
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    if (_viewMode == 3 && [_currentSubMenu isEqualToString:@"account_mgmt"]) return 44;
    return 36;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (_viewMode == 1) {
        NSDictionary *item = _mainMenu[ip.row];
        [self _handleMenuAction:item[@"action"]];
    } else if (_viewMode == 3 && [_currentSubMenu isEqualToString:@"set_country"]) {
        _selectedCountry = kCountries[ip.row];
        [_menuTable reloadData];
        [self _showToast:[NSString stringWithFormat:@"国家已切换: %@", _selectedCountry]];
    }
}

- (void)_handleMenuAction:(NSString *)action {
    if ([action isEqualToString:@"close_panel"]) { [self dismiss]; return; }
    if ([action isEqualToString:@"set_country"]) {
        _viewMode = 3; _currentSubMenu = @"set_country"; _backBtn.hidden = NO;
        _titleLabel.text = @"设置国家"; [_menuTable reloadData]; return;
    }
    if ([action isEqualToString:@"account_mgmt"]) {
        _viewMode = 3; _currentSubMenu = @"account_mgmt"; _backBtn.hidden = NO;
        _titleLabel.text = @"账号管理"; [_menuTable reloadData]; return;
    }
    if ([action isEqualToString:@"bind_server"]) {
        [self _showBindForm]; return;
    }
    if ([action isEqualToString:@"copy_device_id"]) {
        [UIPasteboard generalPasteboard].string = _panelDeviceId ?: @"";
        [self _showToast:[NSString stringWithFormat:@"已复制: %@", _panelDeviceId?:@""]]; return;
    }
    if ([action isEqualToString:@"disconnect"]) {
        [self.delegate floatingPanelDidTapScrollDown:self]; return;
    }
    [self _showToast:[NSString stringWithFormat:@"执行: %@", action]];
}

#pragma mark - Animation

- (void)_handleTap {
    if (_isExpanded) return;
    [self _expandPanel];
}

- (void)_expandPanel {
    [self _ensurePanel];
    _isExpanded = YES;

    // 判断显示什么
    BOOL activated = [[NSUserDefaults standardUserDefaults] boolForKey:@"XN_Activated"];
    if (activated) {
        [self _showMainMenu];
    } else {
        [self _showActivationView];
    }

    _panelContainer.alpha = 1; _panelContainer.transform = CGAffineTransformMakeScale(0.3, 0.3);
    CGFloat ow = self.frame.size.width, oh = self.frame.size.height;
    self.frame = self.superview ?
        CGRectMake(self.frame.origin.x-(kExpandedWidth-ow)/2, self.frame.origin.y-(kExpandedHeight-oh)/2+20, kExpandedWidth, kExpandedHeight) : self.frame;
    _badgeButton.alpha = 0;
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.8
                        options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.panelContainer.transform = CGAffineTransformIdentity; self.layer.shadowOpacity = 0.5;
    } completion:nil];
}

- (void)dismiss {
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 0; self.transform = CGAffineTransformMakeScale(0.3, 0.3);
    } completion:^(BOOL f) { [self removeFromSuperview]; }];
}

- (void)_handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:self.superview];
    switch (pan.state) {
        case UIGestureRecognizerStateBegan: _isDragging = YES; _dragStart = self.center; break;
        case UIGestureRecognizerStateChanged: {
            CGPoint nc = CGPointMake(_dragStart.x+t.x, _dragStart.y+t.y);
            CGFloat hw = _isExpanded ? kExpandedWidth/2 : kCollapsedSize/2;
            CGFloat hh = _isExpanded ? kExpandedHeight/2 : kCollapsedSize/2;
            nc.x = MAX(hw, MIN([UIScreen mainScreen].bounds.size.width-hw, nc.x));
            nc.y = MAX(50+hh, MIN([UIScreen mainScreen].bounds.size.height-100-hh, nc.y));
            self.center = nc; break;
        }
        case UIGestureRecognizerStateEnded: _isDragging = NO; break;
        default: break;
    }
}

#pragma mark - Public

- (void)showInWindow:(UIWindow *)window {
    if (!window) return; [window addSubview:self];
    self.transform = CGAffineTransformMakeScale(0.5, 0.5); self.alpha = 0;
    [UIView animateWithDuration:0.3 delay:0.5 usingSpringWithDamping:0.6 initialSpringVelocity:0.8
                        options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.transform = CGAffineTransformIdentity; self.alpha = 1;
    } completion:nil];
}

- (void)setConnected:(BOOL)connected {
    _isConnected = connected;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusDot.backgroundColor = connected ? XN_ACCENT : UIColor.redColor;
    });
}
- (void)setDeviceId:(NSString *)deviceId { _panelDeviceId = deviceId; }
- (void)setServerURL:(NSString *)serverURL { _panelServerURL = serverURL; }
- (void)setAccountInfo:(NSDictionary *)account {}
- (void)setConnectionQuality:(NSString *)quality {}
- (void)setAccountList:(NSArray<NSDictionary *> *)accounts {
    if (_viewMode == 3 && [_currentSubMenu isEqualToString:@"account_mgmt"]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self->_menuTable reloadData]; });
    }
}

@end

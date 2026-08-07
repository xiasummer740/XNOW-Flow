// XNFloatingPanel.m
// XNOW 控制浮窗 v5 — Apple iOS 17 原生质感玻璃面板
// 视觉重构：真玻璃材质 + SF Symbols + 系统语义色 + InsetGrouped 列表 + 弹簧动画

#import "XNFloatingPanel.h"
#import "AccountPool.h"
#import "AccountManager.h"
#import <objc/runtime.h>

static const CGFloat kCollapsedSize = 56;       // 折叠徽章尺寸
static const CGFloat kExpandedWidth = 300;      // 展开面板宽度
static const CGFloat kExpandedHeight = 520;     // 展开面板高度
static const CGFloat kCornerRadius = 24;        // 大圆角 (iOS 17 风格)
static const CGFloat kHeaderHeight = 60;        // 标题栏高度
static const CGFloat kMargin = 16;              // 16pt 间距节奏
#define kHairline (1.0 / [UIScreen mainScreen].scale)   // 1px 细线

static NSArray *kCountries;

@interface XNFloatingPanel () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate> {
    BOOL _isExpanded, _isDragging;
    CGPoint _dragStart;
    CGPoint _collapsedCenter;   // 展开前保存的折叠中心（收起时恢复，避免面板位置漂移）
    BOOL _hasCollapsedCenter;
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
@property (nonatomic, strong) UIView *panelHeader;
@property (nonatomic, strong) UIView *statusPill;
@property (nonatomic, strong) UIView *statusDotView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UITableView *menuTable;
// 激活/绑定输入
@property (nonatomic, strong) UITextField *inputField;
@property (nonatomic, strong) UIButton *confirmBtn;
// 日志窗口
@property (nonatomic, strong) UIView *logView;
@property (nonatomic, strong) UITextView *logTextView;
@property (nonatomic, strong) NSMutableArray *logLines;
// 数据
@property (nonatomic, assign) BOOL isConnected;
@property (nonatomic, copy) NSString *panelDeviceId, *panelServerURL, *selectedCountry;
@property (nonatomic, strong) NSDictionary *panelAccount;
@property (nonatomic, copy) NSString *panelQuality;
@property (nonatomic, strong) NSArray *mainMenu;

@end

@implementation XNFloatingPanel

+ (void)initialize {
    kCountries = @[@"美国", @"日本", @"英国", @"韩国", @"越南", @"泰国",
                   @"新加坡", @"迪拜", @"马来西亚", @"巴西", @"印度尼西亚",
                   @"澳大利亚", @"意大利", @"墨西哥", @"丹麦", @"台湾", @"菲律宾",
                   @"德国", @"法国", @"西班牙", @"荷兰", @"瑞士", @"瑞典",
                   @"挪威", @"芬兰", @"比利时", @"奥地利", @"爱尔兰", @"葡萄牙",
                   @"希腊", @"土耳其", @"沙特", @"卡塔尔", @"阿曼", @"科威特",
                   @"印度", @"巴基斯坦", @"孟加拉", @"斯里兰卡", @"尼泊尔",
                   @"加拿大", @"墨西哥", @"阿根廷", @"智利", @"哥伦比亚",
                   @"秘鲁", @"南非", @"埃及", @"尼日利亚", @"肯尼亚",
                   @"俄罗斯", @"乌克兰", @"波兰", @"捷克", @"匈牙利",
                   @"罗马尼亚", @"保加利亚", @"克罗地亚", @"塞尔维亚"];
}

- (instancetype)initWithFrame:(CGRect)frame {
    // 默认右上角（状态栏下方两指位置）
    CGFloat rightX = [UIScreen mainScreen].bounds.size.width - kCollapsedSize - 12;
    CGFloat topY = 120;
    self = [super initWithFrame:CGRectMake(rightX, topY, kCollapsedSize, kCollapsedSize)];
    if (self) {
        // 强制深色语义色环境，使 labelColor / systemGroupedBackgroundColor 等解析为深色玻璃风格
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        _isExpanded = NO; _isConnected = NO;
        _selectedCountry = @"日本";
        _logLines = [NSMutableArray array];
        [self _buildMainMenu];
        [self _setupViews];
        [self _restoreSavedPosition];  // 恢复上次记忆的浮窗位置
    }
    return self;
}

#pragma mark - Menu Data

- (void)_buildMainMenu {
    // icon 为 SF Symbol 名称，保持 action 字符串与旧版完全一致
    _mainMenu = @[
        @{@"icon": @"network", @"label": @"绑定云控后台", @"action": @"bind_server"},
        @{@"icon": @"person.2.fill", @"label": @"账号管理", @"action": @"account_mgmt"},
        @{@"icon": @"square.and.arrow.down.fill", @"label": @"下载无水印视频", @"action": @"dl_video"},
        @{@"icon": @"globe", @"label": @"设置国家", @"action": @"set_country"},
        @{@"icon": @"trash.fill", @"label": @"一键清理所有数据", @"action": @"clear_data"},
        @{@"icon": @"power", @"label": @"关闭服务器链接", @"action": @"disconnect"},
        @{@"icon": @"heart.fill", @"label": @"采集点赞", @"action": @"collect_likes"},
        @{@"icon": @"leaf.fill", @"label": @"养号", @"action": @"nurture"},
        @{@"icon": @"doc.on.doc.fill", @"label": @"复制机器码", @"action": @"copy_device_id"},
        @{@"icon": @"doc.plaintext.fill", @"label": @"显示/关闭日志", @"action": @"toggle_log"},
        @{@"icon": @"xmark.circle.fill", @"label": @"关闭", @"action": @"close_panel"},
    ];
}

#pragma mark - Setup

- (void)_setupViews {
    self.clipsToBounds = NO;
    self.layer.shadowColor = UIColor.blackColor.CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 6);
    self.layer.shadowRadius = 16;
    self.layer.shadowOpacity = 0.35;
    [self _updateShadowPath];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_handlePan:)];
    [self addGestureRecognizer:pan];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_handleTap)];
    tap.cancelsTouchesInView = NO; // 不拦截表格点击
    [self addGestureRecognizer:tap];
    [self _buildBadge];
}

/// 为 self 设置与当前形态匹配的圆角阴影路径
- (void)_updateShadowPath {
    CGSize size = _isExpanded ? CGSizeMake(kExpandedWidth, kExpandedHeight) : CGSizeMake(kCollapsedSize, kCollapsedSize);
    CGFloat r = _isExpanded ? kCornerRadius : kCollapsedSize * 0.3;
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size.width, size.height) cornerRadius:r].CGPath;
}

#pragma mark - Badge

- (void)_buildBadge {
    _badgeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _badgeButton.frame = CGRectMake(0, 0, kCollapsedSize, kCollapsedSize);
    _badgeButton.backgroundColor = UIColor.clearColor;
    _badgeButton.layer.cornerRadius = kCollapsedSize * 0.3;
    _badgeButton.clipsToBounds = YES;

    // 玻璃材质背景（深色系统材质）
    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    blur.frame = _badgeButton.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    blur.userInteractionEnabled = NO;
    [_badgeButton addSubview:blur];

    // SF Symbol 图标（X = XNOW）
    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]];
    iconView.tintColor = [UIColor systemBlueColor];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.frame = CGRectInset(_badgeButton.bounds, kCollapsedSize * 0.26, kCollapsedSize * 0.26);
    iconView.userInteractionEnabled = NO;
    [_badgeButton addSubview:iconView];

    [_badgeButton addTarget:self action:@selector(_handleTap) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_badgeButton];

    // 在线状态圆点
    _statusDot = [[UIView alloc] initWithFrame:CGRectMake(kCollapsedSize - 15, kCollapsedSize - 15, 14, 14)];
    _statusDot.backgroundColor = [UIColor systemRedColor];
    _statusDot.layer.cornerRadius = 7;
    _statusDot.layer.borderWidth = 2;
    _statusDot.layer.borderColor = [UIColor whiteColor].CGColor;
    _statusDot.layer.shadowColor = UIColor.blackColor.CGColor;
    _statusDot.layer.shadowOpacity = 0.3;
    _statusDot.layer.shadowRadius = 2;
    _statusDot.layer.shadowOffset = CGSizeMake(0, 1);
    [self addSubview:_statusDot];
}

#pragma mark - Panel

- (void)_ensurePanel {
    if (_panelContainer) return;
    _panelContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kExpandedWidth, kExpandedHeight)];
    _panelContainer.layer.cornerRadius = kCornerRadius;
    _panelContainer.clipsToBounds = YES;
    _panelContainer.alpha = 0;
    _panelContainer.layer.borderWidth = kHairline;
    _panelContainer.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor; // 1px 高光描边
    // 统一深色底（毛玻璃渲染不佳时也保持一致，避免"打补丁"双底色）
    _panelContainer.backgroundColor = [UIColor colorWithWhite:0.09 alpha:0.94];
    [self addSubview:_panelContainer];

    // 玻璃材质
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark];
    _blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    _blurView.frame = _panelContainer.bounds;
    _blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_panelContainer addSubview:_blurView];

    // 标题栏
    _panelHeader = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kExpandedWidth, kHeaderHeight)];
    [_panelContainer addSubview:_panelHeader];

    _backBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _backBtn.frame = CGRectMake(10, 10, 40, 40);
    [_backBtn setImage:[UIImage systemImageNamed:@"chevron.left"] forState:UIControlStateNormal];
    _backBtn.tintColor = [UIColor labelColor];
    _backBtn.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
    _backBtn.layer.cornerRadius = 20;
    _backBtn.hidden = YES;
    [_backBtn addTarget:self action:@selector(_backToMain) forControlEvents:UIControlEventTouchUpInside];
    [_panelHeader addSubview:_backBtn];

    _closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _closeBtn.frame = CGRectMake(kExpandedWidth - 50, 10, 40, 40);
    [_closeBtn setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    _closeBtn.tintColor = [UIColor secondaryLabelColor];
    _closeBtn.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
    _closeBtn.layer.cornerRadius = 20;
    [_closeBtn addTarget:self action:@selector(_collapsePanel) forControlEvents:UIControlEventTouchUpInside];
    [_panelHeader addSubview:_closeBtn];

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(56, 12, kExpandedWidth - 112, 24)];
    _titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    _titleLabel.textColor = [UIColor labelColor];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.text = @"XNOW";
    [_panelHeader addSubview:_titleLabel];

    // 连接状态胶囊（圆点 + 文字）
    _statusPill = [[UIView alloc] initWithFrame:CGRectMake(0, 40, 120, 18)];
    _statusDotView = [[UIView alloc] initWithFrame:CGRectMake(0, 5, 8, 8)];
    _statusDotView.layer.cornerRadius = 4;
    _statusDotView.backgroundColor = [UIColor systemRedColor];
    [_statusPill addSubview:_statusDotView];
    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 0, 100, 18)];
    _statusLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    _statusLabel.textColor = [UIColor secondaryLabelColor];
    _statusLabel.numberOfLines = 1;
    _statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _statusLabel.text = @"未连接";
    [_statusPill addSubview:_statusLabel];
    [_panelHeader addSubview:_statusPill];
    [self _updateStatusUI];

    // 标题栏下细线
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0, kHeaderHeight, kExpandedWidth, kHairline)];
    sep.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    [_panelContainer addSubview:sep];

    // 菜单列表 — InsetGrouped 圆角分组卡片
    _menuTable = [[UITableView alloc] initWithFrame:CGRectMake(0, kHeaderHeight + 2, kExpandedWidth, kExpandedHeight - kHeaderHeight - 2)
                                              style:UITableViewStyleInsetGrouped];
    _menuTable.backgroundColor = UIColor.clearColor;
    _menuTable.dataSource = self;
    _menuTable.delegate = self;
    _menuTable.separatorStyle = UITableViewCellSeparatorStyleNone;
    _menuTable.showsVerticalScrollIndicator = NO;
    [_panelContainer addSubview:_menuTable];
}

#pragma mark - View Switching

- (void)_showActivationView {
    _viewMode = 0; _backBtn.hidden = YES; _closeBtn.hidden = NO;
    _titleLabel.text = @"设备激活";
    _menuTable.hidden = YES;
    [self _removeInputViews];

    UIScrollView *sv = [[UIScrollView alloc] initWithFrame:CGRectMake(0, kHeaderHeight + 2, kExpandedWidth, kExpandedHeight - kHeaderHeight - 2)];
    sv.tag = 1001; sv.showsVerticalScrollIndicator = NO;
    sv.alwaysBounceVertical = YES;
    [_panelContainer addSubview:sv];

    CGFloat m = kMargin;
    CGFloat w = kExpandedWidth - 2 * m;
    CGFloat y = 16;

    // UUID 卡片
    NSString *uuid = [[[UIDevice currentDevice] identifierForVendor] UUIDString] ?: @"UNKNOWN";
    UIView *uuidCard = [self _makeCardViewWithFrame:CGRectMake(m, y, w, 66)];
    UILabel *uuidTitle = [[UILabel alloc] initWithFrame:CGRectMake(14, 10, w - 28, 14)];
    uuidTitle.text = @"设备 UUID";
    uuidTitle.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    uuidTitle.textColor = [UIColor secondaryLabelColor];
    [uuidCard addSubview:uuidTitle];
    UILabel *uuidV = [[UILabel alloc] initWithFrame:CGRectMake(14, 28, w - 28, 30)];
    uuidV.text = uuid;
    uuidV.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    uuidV.textColor = [UIColor labelColor];
    uuidV.numberOfLines = 2;
    uuidV.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [uuidCard addSubview:uuidV];
    [sv addSubview:uuidCard];
    y += 66 + 14;

    // 重要提示（警告卡片）
    UIView *noticeCard = [self _makeCardViewWithFrame:CGRectMake(m, y, w, 92)];
    noticeCard.backgroundColor = [[UIColor systemYellowColor] colorWithAlphaComponent:0.10];
    UILabel *noticeTitle = [[UILabel alloc] initWithFrame:CGRectMake(14, 10, w - 28, 16)];
    noticeTitle.text = @"重要提示";
    noticeTitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    noticeTitle.textColor = [UIColor systemOrangeColor];
    [noticeCard addSubview:noticeTitle];
    UILabel *noticeBody = [[UILabel alloc] initWithFrame:CGRectMake(14, 30, w - 28, 54)];
    noticeBody.text = @"请联系客服并提供机器码进行设备激活！您也可以在下方输入卡密进行自动激活。";
    noticeBody.font = [UIFont systemFontOfSize:11];
    noticeBody.textColor = [UIColor secondaryLabelColor];
    noticeBody.numberOfLines = 0;
    [noticeCard addSubview:noticeBody];
    [sv addSubview:noticeCard];
    y += 92 + 16;

    // 卡密输入
    UILabel *inputLabel = [[UILabel alloc] initWithFrame:CGRectMake(m, y, w, 16)];
    inputLabel.text = @"输入卡密";
    inputLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    inputLabel.textColor = [UIColor labelColor];
    [sv addSubview:inputLabel];
    y += 22;

    _inputField = [self _makeInputFieldWithFrame:CGRectMake(m, y, w, 42) placeholder:@"输入卡密"];
    _inputField.tag = 1002;
    _inputField.autocorrectionType = UITextAutocorrectionTypeNo;
    [sv addSubview:_inputField];
    y += 54;

    UIButton *activateBtn = [self _makePrimaryButtonWithTitle:@"确定" action:@selector(_activateTapped)];
    activateBtn.frame = CGRectMake(m, y, w, 44);
    [sv addSubview:activateBtn];
    y += 44 + 16;

    sv.contentSize = CGSizeMake(kExpandedWidth, MAX(y, sv.bounds.size.height));
    [_inputField becomeFirstResponder];
}

- (void)_showMainMenu {
    _viewMode = 1; _backBtn.hidden = YES; _closeBtn.hidden = NO;
    _titleLabel.text = @"快捷菜单";
    _menuTable.hidden = NO;
    [self _removeInputViews];
    [_menuTable reloadData];
}

- (void)_showBindForm {
    _viewMode = 2; _backBtn.hidden = NO; _closeBtn.hidden = NO;
    _titleLabel.text = @"绑定云控后台";
    _menuTable.hidden = YES;
    [self _removeInputViews];

    UIScrollView *sv = [[UIScrollView alloc] initWithFrame:CGRectMake(0, kHeaderHeight + 2, kExpandedWidth, kExpandedHeight - kHeaderHeight - 2)];
    sv.tag = 1001; sv.showsVerticalScrollIndicator = NO;
    sv.alwaysBounceVertical = YES;
    [_panelContainer addSubview:sv];

    CGFloat m = kMargin;
    CGFloat w = kExpandedWidth - 2 * m;
    CGFloat y = 16;

    // 检查是否已绑定
    NSString *savedDev = [[NSUserDefaults standardUserDefaults] stringForKey:@"XN_BindDeviceID"];
    NSString *savedApi = [[NSUserDefaults standardUserDefaults] stringForKey:@"XN_BindAPIID"];
    BOOL alreadyBound = (savedDev.length > 0 && savedApi.length > 0);

    UILabel *desc = [[UILabel alloc] initWithFrame:CGRectMake(m, y, w, 34)];
    desc.text = alreadyBound ? @"已绑定，可修改设备编号和 APIID" : @"请输入设备编号和 APIID 绑定云控后台";
    desc.font = [UIFont systemFontOfSize:12];
    desc.textColor = [UIColor secondaryLabelColor];
    desc.numberOfLines = 0;
    [sv addSubview:desc];
    y += 40;

    // 设备编号（1-20）
    UILabel *dl = [[UILabel alloc] initWithFrame:CGRectMake(m, y, w, 16)];
    dl.text = @"设备编号（1-20）";
    dl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    dl.textColor = [UIColor labelColor];
    [sv addSubview:dl]; y += 22;
    UITextField *dF = [self _makeInputFieldWithFrame:CGRectMake(m, y, w, 42) placeholder:@"输入 1-20"];
    if (alreadyBound) dF.text = savedDev;
    dF.tag = 1003; dF.keyboardType = UIKeyboardTypeNumberPad;
    [sv addSubview:dF]; y += 54;

    // APIID
    UILabel *al = [[UILabel alloc] initWithFrame:CGRectMake(m, y, w, 16)];
    al.text = @"APIID（后台用户中心获取）";
    al.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    al.textColor = [UIColor labelColor];
    [sv addSubview:al]; y += 22;
    UITextField *aF = [self _makeInputFieldWithFrame:CGRectMake(m, y, w, 42) placeholder:@"输入后台分配的 API ID"];
    if (alreadyBound) aF.text = savedApi;
    aF.tag = 1004; aF.keyboardType = UIKeyboardTypeNumberPad;
    [sv addSubview:aF]; y += 54;

    UIButton *okBtn = [self _makePrimaryButtonWithTitle:@"确定" action:@selector(_bindTapped)];
    okBtn.frame = CGRectMake(m, y, w, 44);
    [sv addSubview:okBtn];
    y += 44 + 16;

    sv.contentSize = CGSizeMake(kExpandedWidth, MAX(y, sv.bounds.size.height));
}

- (UIView *)_makeCardViewWithFrame:(CGRect)frame {
    UIView *card = [[UIView alloc] initWithFrame:frame];
    card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    card.layer.cornerRadius = 14;
    card.layer.borderWidth = kHairline;
    card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.08].CGColor;
    return card;
}

- (UIButton *)_makePrimaryButtonWithTitle:(NSString *)title action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.backgroundColor = [UIColor systemBlueColor];
    b.layer.cornerRadius = 12;
    b.clipsToBounds = YES;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UITextField *)_makeInputFieldWithFrame:(CGRect)frame placeholder:(NSString *)ph {
    UITextField *f = [[UITextField alloc] initWithFrame:frame];
    f.placeholder = ph;
    f.backgroundColor = [UIColor tertiarySystemFillColor];
    f.textColor = [UIColor labelColor];
    f.layer.cornerRadius = 10;
    f.layer.borderWidth = kHairline;
    f.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.08].CGColor;
    f.font = [UIFont systemFontOfSize:14];
    f.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 42)];
    f.leftViewMode = UITextFieldViewModeAlways;
    f.delegate = self;
    f.attributedPlaceholder = [[NSAttributedString alloc] initWithString:ph attributes:@{NSForegroundColorAttributeName: [UIColor tertiaryLabelColor]}];
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
    if (code.length == 0) {
        [self _showToast:@"请输入卡密"];
        return;
    }
    // 交给 XNOWER 调后端激活接口
    if ([self.delegate respondsToSelector:@selector(floatingPanel:didEnterLicenseKey:)]) {
        [self.delegate floatingPanel:self didEnterLicenseKey:code];
    } else {
        [self _showToast:@"未配置激活处理器"];
    }
}

- (void)_bindTapped {
    UITextField *df = [_panelContainer viewWithTag:1003];
    UITextField *af = [_panelContainer viewWithTag:1004];
    NSString *devId = df.text ?: @"";
    NSString *apiId = af.text ?: @"";

    if (devId.length > 0 && apiId.length > 0) {
        // 交给 XNOWER 存本地 + piggyback 上报绑定信息
        if ([self.delegate respondsToSelector:@selector(floatingPanel:didSubmitBindingWithCode:apiId:)]) {
            [self.delegate floatingPanel:self didSubmitBindingWithCode:devId apiId:apiId];
        } else {
            [self _showToast:@"未配置绑定处理器"];
        }
        [self _backToMain];
    } else {
        [self _showToast:@"请填写设备编号和APIID"];
    }
}

- (void)_showToast:(NSString *)msg {
    UILabel *toast = [[UILabel alloc] initWithFrame:CGRectMake(24, kExpandedHeight - 72, kExpandedWidth - 48, 36)];
    toast.text = msg;
    toast.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    toast.textColor = [UIColor labelColor];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    toast.layer.cornerRadius = 18;
    toast.clipsToBounds = YES;
    toast.layer.borderWidth = kHairline;
    toast.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.10].CGColor;
    toast.alpha = 0;
    [_panelContainer addSubview:toast];
    [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5
                        options:UIViewAnimationOptionCurveEaseOut animations:^{ toast.alpha = 1; } completion:nil];
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
            // 账号列表 + 2 个操作按钮（新增账号 / 备份当前账号）
            NSArray *a = [[AccountPool sharedPool] allAccounts];
            return MAX(a.count, 1) + 2;
        }
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"];
    }
    // 统一 Apple 风格基础样式
    cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    cell.textLabel.textColor = [UIColor labelColor];
    cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    cell.textLabel.textAlignment = NSTextAlignmentLeft;
    cell.textLabel.numberOfLines = 1;
    cell.detailTextLabel.text = nil;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:11];
    cell.imageView.image = nil;
    cell.imageView.tintColor = [UIColor systemBlueColor];
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    if (_viewMode == 1) {
        NSDictionary *item = _mainMenu[ip.row];
        cell.imageView.image = [UIImage systemImageNamed:item[@"icon"]];
        NSString *action = item[@"action"];
        if ([action isEqualToString:@"close_panel"] || [action isEqualToString:@"clear_data"]) {
            cell.imageView.tintColor = [UIColor systemRedColor];
        } else if ([action isEqualToString:@"connect_server"]) {
            cell.imageView.tintColor = [UIColor systemGreenColor];
        } else {
            cell.imageView.tintColor = [UIColor systemBlueColor];
        }
        cell.textLabel.text = item[@"label"];
    } else if (_viewMode == 3 && [_currentSubMenu isEqualToString:@"set_country"]) {
        NSString *c = kCountries[ip.row];
        cell.textLabel.text = c;
        cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
        BOOL sel = [c isEqualToString:_selectedCountry];
        cell.textLabel.textColor = sel ? [UIColor systemBlueColor] : [UIColor labelColor];
        if (sel) { cell.accessoryType = UITableViewCellAccessoryCheckmark; cell.tintColor = [UIColor systemBlueColor]; }
    } else if (_viewMode == 3 && [_currentSubMenu isEqualToString:@"account_mgmt"]) {
        NSArray *a = [[AccountPool sharedPool] allAccounts];
        NSUInteger actionRow = MAX(a.count, 1);   // 操作按钮起始行
        if (ip.row >= actionRow) {
            // 操作按钮行
            if (ip.row == actionRow) {
                cell.textLabel.text = @"＋ 新增账号（无痕）";
                cell.textLabel.textColor = [UIColor systemBlueColor];
                cell.imageView.image = [UIImage systemImageNamed:@"plus.circle.fill"];
                cell.imageView.tintColor = [UIColor systemBlueColor];
            } else {
                cell.textLabel.text = @"📦 备份当前账号";
                cell.textLabel.textColor = [UIColor systemGreenColor];
                cell.imageView.image = [UIImage systemImageNamed:@"square.and.arrow.down.fill"];
                cell.imageView.tintColor = [UIColor systemGreenColor];
            }
        } else if (a.count == 0) {
            cell.textLabel.text = @"暂无账号";
            cell.textLabel.textColor = [UIColor secondaryLabelColor];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            NSDictionary *acc = a[ip.row];
            cell.textLabel.text = acc[@"nickname"] ?: @"未知账号";
            cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"号码:%@  粉丝:%@  关注:%@  国家:%@",
                                         acc[@"aweme_number"]?:@"", acc[@"followers"]?:@"0",
                                         acc[@"following_count"]?:@"0", acc[@"act_country"]?:@"—"];
            cell.detailTextLabel.numberOfLines = 1;
        }
    }
    return cell;
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    if (_viewMode == 3 && [_currentSubMenu isEqualToString:@"account_mgmt"]) return 60;
    if (_viewMode == 3 && [_currentSubMenu isEqualToString:@"set_country"]) return 44;
    return 52;
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
    } else if (_viewMode == 3 && [_currentSubMenu isEqualToString:@"account_mgmt"]) {
        NSArray *accounts = [[AccountPool sharedPool] allAccounts];
        NSUInteger actionRow = MAX(accounts.count, 1);   // 操作按钮起始行
        if (ip.row >= actionRow) {
            // 操作按钮：新增账号 / 备份当前账号
            if (ip.row == actionRow) {
                [self _promptAddNewAccount];
            } else {
                [self _promptBackupCurrentAccount];
            }
            return;
        }
        if (ip.row >= accounts.count) return;
        NSDictionary *acc = accounts[ip.row];
        [self _promptSwitchAccount:acc];
    }
}

/// 新增账号：清空登录态（无痕）→ 让用户登录全新账号
- (void)_promptAddNewAccount {
    NSArray *accounts = [[AccountPool sharedPool] allAccounts];
    if (accounts.count >= 20) {
        [self _showToast:@"已达 20 账号上限"];
        [self addLog:@"❌ 已达 20 账号上限"];
        return;
    }
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"新增账号"
        message:@"将清空当前登录态（无痕），进入全新登录页。请登录新账号，登录完成后点「备份当前账号」记录。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"开始无痕登录"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            if ([self.delegate respondsToSelector:@selector(floatingPanelDidTapAddNewAccount:)]) {
                [self.delegate floatingPanelDidTapAddNewAccount:self];
            }
            [self addLog:@"开始新增账号：无痕登录"];
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self _presentAlert:alert];
}

/// 备份当前登录账号的登录态快照
- (void)_promptBackupCurrentAccount {
    NSDictionary *current = [[AccountManager sharedManager] currentAccount];
    if (!current) {
        // 退回 AccountPool 活跃账号
        current = [[AccountPool sharedPool] activeAccount];
    }
    if (!current) {
        [self _showToast:@"未检测到当前登录账号"];
        [self addLog:@"❌ 备份失败：未检测到当前账号"];
        return;
    }
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"备份当前账号"
        message:[NSString stringWithFormat:@"将记录当前账号：%@ 的登录态，用于后续一键切换。", current[@"nickname"] ?: @"未知"]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"备份"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            if ([self.delegate respondsToSelector:@selector(floatingPanelDidTapBackupAccount:)]) {
                [self.delegate floatingPanelDidTapBackupAccount:self];
            }
            [self addLog:@"正在备份当前账号登录态..."];
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self _presentAlert:alert];
}

/// 养号子菜单（模式1纯浏览/模式2浏览+互动/停止，24小时不限时运行）
- (void)_promptNurtureMode {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"🌱 养号"
        message:@"选择养号模式（24小时不限时运行）"
        preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"模式1：纯浏览（随机10-20秒上滑）"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            if ([self.delegate respondsToSelector:@selector(floatingPanelDidStartNurtureMode:)]) {
                [self.delegate floatingPanelDidStartNurtureMode:1];
            }
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"模式2：浏览+互动（上滑+随机点赞/关注/评论）"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            if ([self.delegate respondsToSelector:@selector(floatingPanelDidStartNurtureMode:)]) {
                [self.delegate floatingPanelDidStartNurtureMode:2];
            }
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"⏹ 停止养号"
        style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            if ([self.delegate respondsToSelector:@selector(floatingPanelDidStopNurture)]) {
                [self.delegate floatingPanelDidStopNurture];
            }
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self _presentAlert:alert];
}

/// 统一弹 Alert（兼容多场景）
- (void)_presentAlert:(UIAlertController *)alert {
    UIWindow *topWin = nil;
    if (@available(iOS 13, *)) {
        for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
            if ([sc isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)sc;
                if (ws.activationState == UISceneActivationStateForegroundActive) {
                    topWin = ws.keyWindow ?: ws.windows.firstObject;
                    break;
                }
            }
        }
    }
    if (!topWin) topWin = UIApplication.sharedApplication.windows.firstObject;
    UIViewController *topVC = topWin.rootViewController;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;
    if (topVC) [topVC presentViewController:alert animated:YES completion:nil];
}

/// 弹出账号操作菜单 — 确认切换到所选账号
- (void)_promptSwitchAccount:(NSDictionary *)acc {
    NSString *nickname = acc[@"nickname"] ?: @"未知";
    NSInteger accId = [acc[@"id"] integerValue];
    NSString *msg = [NSString stringWithFormat:@"切换到账号：%@", nickname];

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"切换账号" message:msg
        preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"切换到此账号"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            if ([self.delegate respondsToSelector:@selector(floatingPanel:didSelectAccountId:)]) {
                [self.delegate floatingPanel:self didSelectAccountId:accId];
            }
            [self _showToast:[NSString stringWithFormat:@"正在切换到 %@…", nickname]];
            [self addLog:[NSString stringWithFormat:@"切换账号 → %@ (ID:%ld)", nickname, (long)accId]];
        }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    // 从顶层 VC 弹出（L19: 用 connectedScenes 兼容多场景，避免废弃 keyWindow）
    UIWindow *topWin = nil;
    if (@available(iOS 13, *)) {
        for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
            if ([sc isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)sc;
                if (ws.activationState == UISceneActivationStateForegroundActive) {
                    topWin = ws.keyWindow ?: ws.windows.firstObject;
                    break;
                }
            }
        }
    }
    if (!topWin) topWin = UIApplication.sharedApplication.windows.firstObject;
    UIViewController *topVC = topWin.rootViewController;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;
    if (topVC) [topVC presentViewController:alert animated:YES completion:nil];
}

- (void)_handleMenuAction:(NSString *)action {
    if ([action isEqualToString:@"close_panel"]) { [self dismiss]; return; }
    if ([action isEqualToString:@"set_country"]) {
        _viewMode = 3; _currentSubMenu = @"set_country"; _backBtn.hidden = NO;
        _titleLabel.text = @"设置国家"; [_menuTable reloadData]; return;
    }
    if ([action isEqualToString:@"account_mgmt"]) {
        _viewMode = 3; _currentSubMenu = @"account_mgmt"; _backBtn.hidden = NO;
        _titleLabel.text = @"账号管理"; [_menuTable reloadData];
        // 请求后端下发账号列表
        if ([self.delegate respondsToSelector:@selector(floatingPanelDidRequestAccountList:)]) {
            [self.delegate floatingPanelDidRequestAccountList:self];
        }
        return;
    }
    if ([action isEqualToString:@"bind_server"]) { [self _showBindForm]; return; }
    if ([action isEqualToString:@"connect_server"]) {
        [self addLog:@"正在连接服务器…"];
        if ([self.delegate respondsToSelector:@selector(floatingPanelDidTapConnectServer:)]) {
            [self.delegate floatingPanelDidTapConnectServer:self];
        }
        return;
    }
    if ([action isEqualToString:@"copy_device_id"]) {
        [UIPasteboard generalPasteboard].string = _panelDeviceId ?: @"";
        [self _showToast:[NSString stringWithFormat:@"已复制: %@", _panelDeviceId?:@""]];
        [self addLog:[NSString stringWithFormat:@"已复制设备码: %@", _panelDeviceId?:@""]];
        return;
    }
    // 映射到 CommandEngine 动作（正确回调）
    if ([action isEqualToString:@"clear_data"]) {
        [self addLog:@"清理数据中..."];
        [self.delegate floatingPanelDidTapClearData:self];
        return;
    }
    if ([action isEqualToString:@"disconnect"]) {
        [self addLog:@"断开服务器连接"];
        [self.delegate floatingPanelDidTapDisconnect:self];
        return;
    }
    if ([action isEqualToString:@"collect_likes"]) {
        [self addLog:@"开始采集点赞..."];
        [self.delegate floatingPanelDidTapCollectLikes:self];
        return;
    }
    if ([action isEqualToString:@"nurture"]) {
        [self _promptNurtureMode];
        return;
    }
    if ([action isEqualToString:@"dl_video"]) {
        [self addLog:@"下载无水印视频..."];
        [self.delegate floatingPanelDidTapDownloadVideo:self];
        return;
    }
    if ([action isEqualToString:@"toggle_log"]) {
        // 切换日志显示
        if (!self.logView && self.superview) {
            [self _createLogWindow];
        }
        self.logView.hidden = !self.logView.hidden;
        [self addLog:self.logView.hidden ? @"日志已隐藏" : @"日志已显示"];
        return;
    }
    // 其他: 采粉/采视频等
    if ([action isEqualToString:@"collect_comment_users"] || [action isEqualToString:@"collect_all_fans"] || [action isEqualToString:@"collect_live_fans"]) {
        [self addLog:[NSString stringWithFormat:@"开始%@...", action]];
        [self.delegate floatingPanelDidTapCollectFans:self];
        return;
    }
    if ([action isEqualToString:@"auto_comment"]) {
        [self addLog:@"启动自动评论点赞..."];
        [self.delegate floatingPanelDidTapSmartBrowse:self];
        return;
    }
    // 翻译功能预留
    if ([action isEqualToString:@"toggle_translate"] || [action isEqualToString:@"set_translate_lang"]) {
        [self addLog:[NSString stringWithFormat:@"翻译功能待实现"]];
        return;
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

    // 保存当前折叠中心（收起时恢复到展开前的位置，防止位置漂移到屏幕中间）
    _collapsedCenter = self.center;
    _hasCollapsedCenter = YES;

    // 判断显示什么：未激活必须优先显示激活界面（用户每次点开浮窗先输入卡密）
    BOOL activated = [[NSUserDefaults standardUserDefaults] boolForKey:@"XN_Activated"];
    if (activated) {
        [self _showMainMenu];
    } else {
        [self _showActivationView];
    }

    // 自动开启日志窗口（确保挂到当前 superview 并置顶）
    [self addLog:@"XNOWER 已启动"];
    if (!self.logView && self.superview) {
        [self _createLogWindow];
    } else if (self.logView && self.superview && self.logView.superview != self.superview) {
        [self.superview addSubview:self.logView];
        [self.superview bringSubviewToFront:self.logView];
    }

    CGFloat ow = self.frame.size.width, oh = self.frame.size.height;
    // 展开时向左移动，确保面板完全在屏幕内
    CGFloat ex = self.frame.origin.x - (kExpandedWidth - ow) + 8; // 右对齐+右边距8
    if (ex < 8) ex = 8; // 但不要超出左边
    CGFloat ey = self.frame.origin.y - (kExpandedHeight - oh)/2 + 20;
    if (ey < 40) ey = 40;
    CGFloat mh = [UIScreen mainScreen].bounds.size.height;
    if (ey + kExpandedHeight > mh - 20) ey = mh - kExpandedHeight - 20;
    self.frame = self.superview ? CGRectMake(ex, ey, kExpandedWidth, kExpandedHeight) : self.frame;
    self.layer.cornerRadius = kCornerRadius;
    [self _updateShadowPath];

    _badgeButton.alpha = 0;
    _statusDot.alpha = 0; // 徽章圆点随徽章一起隐藏
    _panelContainer.alpha = 1;
    _panelContainer.transform = CGAffineTransformMakeScale(0.3, 0.3);
    _panelContainer.transform = CGAffineTransformTranslate(_panelContainer.transform, 0, -10);
    [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.72 initialSpringVelocity:0.6
                        options:UIViewAnimationOptionCurveEaseOut animations:^{
        _panelContainer.transform = CGAffineTransformIdentity;
        self.layer.shadowOpacity = 0.5;
    } completion:nil];
}

/// 弹簧收起：展开面板缩回为折叠徽章（保留在窗口，可再次点开）
- (void)_collapsePanel {
    if (!_isExpanded) return;
    _isExpanded = NO;
    [self endEditing:YES];

    // 恢复到展开前的折叠位置（避免位置漂移到屏幕中间）
    CGFloat cx = _hasCollapsedCenter ? _collapsedCenter.x : self.center.x;
    CGFloat cy = _hasCollapsedCenter ? _collapsedCenter.y : self.center.y;
    self.frame = CGRectMake(0, 0, kCollapsedSize, kCollapsedSize);
    self.center = CGPointMake(cx, cy);
    CGFloat hw = kCollapsedSize/2, hh = kCollapsedSize/2;
    self.center = CGPointMake(MAX(hw, MIN([UIScreen mainScreen].bounds.size.width-hw, self.center.x)),
                              MAX(50+hh, MIN([UIScreen mainScreen].bounds.size.height-100-hh, self.center.y)));
    self.layer.cornerRadius = kCollapsedSize * 0.3;
    [self _updateShadowPath];

    _badgeButton.alpha = 0;
    [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0.4
                        options:UIViewAnimationOptionCurveEaseOut animations:^{
        _panelContainer.transform = CGAffineTransformMakeScale(0.3, 0.3);
        _panelContainer.alpha = 0;
        _badgeButton.alpha = 1;
        _statusDot.alpha = 1;
        self.layer.shadowOpacity = 0.35;
    } completion:nil];
}

- (void)dismiss {
    if (!self.superview) return;
    [self endEditing:YES];
    [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5
                        options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.alpha = 0;
        self.transform = CGAffineTransformMakeScale(0.4, 0.4);
    } completion:^(BOOL f) { [self removeFromSuperview]; }];
}

- (void)_handlePan:(UIPanGestureRecognizer *)pan {
    // M16: 展开时不拖拽（避免抢菜单滚动）
    if (_isExpanded) {
        pan.enabled = NO;
        pan.enabled = YES;
        return;
    }
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
        case UIGestureRecognizerStateEnded: {
            _isDragging = NO;
            // 记忆浮窗位置（下次启动恢复 + 收起时恢复此位置）
            _collapsedCenter = self.center;
            _hasCollapsedCenter = YES;
            [[NSUserDefaults standardUserDefaults] setDouble:self.center.x forKey:@"XN_PanelPosX"];
            [[NSUserDefaults standardUserDefaults] setDouble:self.center.y forKey:@"XN_PanelPosY"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            break;
        }
        default: break;
    }
}

/// 恢复上次保存的浮窗位置
- (void)_restoreSavedPosition {
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"XN_PanelPosX"] != nil) {
        CGFloat px = [[NSUserDefaults standardUserDefaults] doubleForKey:@"XN_PanelPosX"];
        CGFloat py = [[NSUserDefaults standardUserDefaults] doubleForKey:@"XN_PanelPosY"];
        // 边界保护（防止屏幕旋转/分辨率变化导致位置越界）
        CGFloat hw = kCollapsedSize / 2;
        CGFloat hh = kCollapsedSize / 2;
        px = MAX(hw, MIN([UIScreen mainScreen].bounds.size.width - hw, px));
        py = MAX(50 + hh, MIN([UIScreen mainScreen].bounds.size.height - 100 - hh, py));
        self.center = CGPointMake(px, py);
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
        [self _updateStatusUI];
    });
}

- (void)setDeviceId:(NSString *)deviceId { _panelDeviceId = deviceId; }
- (void)setServerURL:(NSString *)serverURL { _panelServerURL = serverURL; dispatch_async(dispatch_get_main_queue(), ^{ [self _updateStatusUI]; }); }
- (void)setAccountInfo:(NSDictionary *)account { _panelAccount = account; }
- (void)setConnectionQuality:(NSString *)quality { _panelQuality = quality; }

/// 显示设备激活视图（后端检测到未授权时由 XNOWER 调用）
- (void)showActivationView {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!_isExpanded) [self _expandPanel];
        [self _showActivationView];
    });
}

/// 激活结果回调：成功 → 隐藏激活视图并显示主菜单；失败 → 停留在激活视图
- (void)setActivated:(BOOL)activated expires:(NSString *)expires {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (activated) {
            if (expires.length > 0) {
                [self _showToast:[NSString stringWithFormat:@"✅ 激活成功 有效期至 %@", expires]];
            } else {
                [self _showToast:@"✅ 激活成功"];
            }
            [self _showMainMenu];
        } else {
            [self _showToast:@"❌ 激活失败，请检查卡密"];
            [self _showActivationView];
        }
    });
}

/// 统一刷新连接状态（折叠徽章圆点 + 面板状态胶囊）
- (void)_updateStatusUI {
    UIColor *c = _isConnected ? [UIColor systemGreenColor] : [UIColor systemRedColor];
    _statusDot.backgroundColor = c;
    if (!_statusPill) return;
    _statusDotView.backgroundColor = c;
    NSString *txt = _isConnected ? @"已连接" : @"未连接";
    if (_isConnected && _panelServerURL.length > 0) {
        txt = [txt stringByAppendingFormat:@" · %@", _panelServerURL];
    }
    _statusLabel.text = txt;
    CGSize maxSize = CGSizeMake(kExpandedWidth - 72, 18);
    CGSize s = [_statusLabel sizeThatFits:maxSize];
    _statusLabel.frame = CGRectMake(12, 0, s.width, 18);
    CGFloat pillW = 12 + s.width;
    _statusPill.frame = CGRectMake((kExpandedWidth - pillW)/2, 40, pillW, 18);
    _statusDotView.center = CGPointMake(6, 9);
}

#pragma mark - 日志窗口

- (void)addLog:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *ts = @"";
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateFormat = @"HH:mm:ss";
        ts = [df stringFromDate:[NSDate date]];
        NSString *line = [NSString stringWithFormat:@"[%@] %@", ts, message];
        [self.logLines addObject:line];
        if (self.logLines.count > 40) {
            [self.logLines removeObjectAtIndex:0];
        }
        // 更新日志视图 + 自动滚动到最新（最下方），保证最新日志可见
        if (self.logTextView) {
            self.logTextView.text = [self.logLines componentsJoinedByString:@"\n"];
            if (self.logTextView.text.length > 0) {
                [self.logTextView scrollRangeToVisible:NSMakeRange(self.logTextView.text.length - 1, 1)];
            }
        }
        // 如果没有日志窗口，创建一个透明浮窗
        if (!self.logView && self.superview) {
            [self _createLogWindow];
        }
        // 新日志亮起 → 短暂后恢复透明（不打扰看视频）
        if (self.logView) {
            self.logView.alpha = 0.9;
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_fadeLogWindow) object:nil];
            [self performSelector:@selector(_fadeLogWindow) withObject:nil afterDelay:4.0];
        }
    });
}

- (void)_fadeLogWindow {
    [UIView animateWithDuration:0.8 animations:^{
        self.logView.alpha = 0.65;   // 保持可读（之前 0.30 太浅看不清）
    }];
}

- (void)_createLogWindow {
    CGFloat logW = 190, logH = 110;
    self.logView = [[UIView alloc] initWithFrame:CGRectMake(8, 60, logW, logH)];
    self.logView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.25]; // 超薄透明底
    self.logView.layer.cornerRadius = 12;
    self.logView.clipsToBounds = YES;
    self.logView.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.logView.layer.borderWidth = kHairline;
    self.logView.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.08].CGColor;
    self.logView.userInteractionEnabled = NO;   // 触摸穿透，不挡操作

    self.logTextView = [[UITextView alloc] initWithFrame:CGRectInset(self.logView.bounds, 6, 6)];
    self.logTextView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.logTextView.backgroundColor = UIColor.clearColor;
    self.logTextView.textColor = [UIColor colorWithWhite:1 alpha:0.95]; // 高对比白字，清晰可读
    self.logTextView.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.logTextView.editable = NO;
    self.logTextView.scrollEnabled = YES;   // 开启滚动，最新日志始终可见
    self.logTextView.userInteractionEnabled = NO;
    self.logTextView.textContainerInset = UIEdgeInsetsMake(4, 4, 4, 4);
    self.logTextView.text = @"";
    [self.logView addSubview:self.logTextView];

    // 默认半透明，收到新日志才短暂亮起
    self.logView.alpha = 0.35;

    // 把日志窗口加到视图层级并置顶（否则不会显示）
    if (self.superview) {
        [self.superview addSubview:self.logView];
        [self.superview bringSubviewToFront:self.logView];
    }
}

#pragma mark - 显示/隐藏

- (void)show {
    // 重新添加到窗口
    UIWindow *keyWin = nil;
    if (@available(iOS 13, *)) {
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:UIWindowScene.class]) {
                UIWindowScene *ws = (UIWindowScene *)s;
                keyWin = ws.keyWindow ?: ws.windows.firstObject;
                if (keyWin) break;
            }
        }
    }
    if (!keyWin) keyWin = UIApplication.sharedApplication.keyWindow;
    if (keyWin) {
        [keyWin addSubview:self];
        [self showInWindow:keyWin];
    }
}

- (BOOL)isVisible {
    return self.superview != nil && self.alpha > 0;
}

- (void)setAccountList:(NSArray<NSDictionary *> *)accounts {
    if (_viewMode == 3 && [_currentSubMenu isEqualToString:@"account_mgmt"]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self->_menuTable reloadData]; });
    }
}

#pragma mark - 触摸穿透

/// 点击穿透：浮窗只拦截自身区域内的触摸，其余触摸穿透给 TikTok。
/// 根因：浮窗放在全屏 overlayWindow 上，若不穿透，窗口会拦截整个屏幕的点击
///（即使浮窗 view 只有 56x56，承载它的全屏窗口也挡住了下面的 TikTok）。
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // 浮窗不可见 → 全部穿透
    if (self.hidden || self.alpha <= 0.01) return nil;

    if (_isExpanded) {
        // 展开状态：面板区域正常响应（菜单/按钮）
        return [super hitTest:point withEvent:event];
    }

    // 收起状态：只响应徽章按钮（点徽章展开，点其它穿透）
    if (_badgeButton && !_badgeButton.hidden) {
        CGPoint p = [self convertPoint:point toView:_badgeButton];
        if ([_badgeButton pointInside:p withEvent:event]) {
            return _badgeButton;
        }
    }
    return nil;  // 浮窗区域外 → 穿透给 TikTok
}

@end

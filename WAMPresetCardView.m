#import "WAMPresetCardView.h"
#import "WAMPresetPreviewView.h"

static const CGFloat kCardInset   = 14;
static const CGFloat kPreviewH    = 156;
static const CGFloat kHeaderH     = 46;
static const CGFloat kCaptionH    = 14;
static const CGFloat kApplyH      = 42;

static UIColor *WAMButtonTitleColor(UIColor *bg) {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    [bg getRed:&r green:&g blue:&b alpha:&a];
    CGFloat lum = 0.2126*r + 0.7152*g + 0.0722*b;
    return (lum > 0.72) ? [UIColor colorWithWhite:0.12 alpha:1.0] : [UIColor whiteColor];
}

@implementation WAMPresetCardView {
    UILabel *_nameLabel;
    UILabel *_subtitleLabel;
    WAMPresetPreviewView *_listPreview;
    WAMPresetPreviewView *_chatPreview;
    UILabel *_listCaption;
    UILabel *_chatCaption;
    UIButton *_applyButton;
    UIButton *_deleteButton;
    UIButton *_renameButton;
}

- (instancetype)initWithPreset:(WAMPreset *)preset dark:(BOOL)dark {
    if ((self = [super initWithFrame:CGRectZero])) {
        _preset = preset;
        _darkAppearance = dark;
        _showsConvListPreview = YES;

        self.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
        self.layer.cornerRadius = 22;
        if (@available(iOS 13.0, *)) self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.10;
        self.layer.shadowRadius = 12;
        self.layer.shadowOffset = CGSizeMake(0, 5);

        _nameLabel = [UILabel new];
        _nameLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
        _nameLabel.textColor = [UIColor labelColor];
        [self addSubview:_nameLabel];

        _subtitleLabel = [UILabel new];
        _subtitleLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightMedium];
        _subtitleLabel.textColor = [UIColor secondaryLabelColor];
        [self addSubview:_subtitleLabel];

        _listPreview = [[WAMPresetPreviewView alloc] initWithPreset:preset style:WAMPreviewStyleConvList dark:dark];
        [self addSubview:_listPreview];
        _chatPreview = [[WAMPresetPreviewView alloc] initWithPreset:preset style:WAMPreviewStyleChat dark:dark];
        [self addSubview:_chatPreview];

        _listCaption = [self captionLabel:@"Conversation List"];
        _chatCaption = [self captionLabel:@"Chat"];
        [self addSubview:_listCaption];
        [self addSubview:_chatCaption];

        _applyButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _applyButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        [_applyButton setTitle:@"Apply" forState:UIControlStateNormal];
        _applyButton.clipsToBounds = YES;
        _applyButton.layer.cornerRadius = 16;
        if (@available(iOS 13.0, *)) _applyButton.layer.cornerCurve = kCACornerCurveContinuous;
        [_applyButton addTarget:self action:@selector(applyTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_applyButton];

        _deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _deleteButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        [_deleteButton setTitle:@"Delete" forState:UIControlStateNormal];
        [_deleteButton setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
        _deleteButton.hidden = YES;
        [_deleteButton addTarget:self action:@selector(deleteTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_deleteButton];

        _renameButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _renameButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        [_renameButton setTitle:@"Rename" forState:UIControlStateNormal];
        _renameButton.hidden = YES;
        [_renameButton addTarget:self action:@selector(renameTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_renameButton];

        [self applyContent];
    }
    return self;
}

- (UILabel *)captionLabel:(NSString *)text {
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold];
    l.textColor = [UIColor tertiaryLabelColor];
    l.textAlignment = NSTextAlignmentCenter;
    return l;
}

- (void)setPreset:(WAMPreset *)preset {
    _preset = preset;
    _listPreview.preset = preset;
    _chatPreview.preset = preset;
    [self applyContent];
    [self setNeedsLayout];
}

- (void)setDarkAppearance:(BOOL)dark {
    _darkAppearance = dark;
    _listPreview.darkAppearance = dark;
    _chatPreview.darkAppearance = dark;
    [self styleApplyButton];
}

- (void)setAccentColor:(UIColor *)accentColor {
    _accentColor = accentColor;
    [self styleApplyButton];
}

- (void)setApplied:(BOOL)applied {
    _applied = applied;
    [self styleApplyButton];
}

- (void)setExportMode:(BOOL)exportMode {
    _exportMode = exportMode;
    [self styleApplyButton];
}

- (void)styleApplyButton {
    if (_exportMode) {
        [_applyButton setTitle:@"Export" forState:UIControlStateNormal];
        _applyButton.enabled = YES;
        UIColor *bg = _accentColor ?: [_preset tintColorForDark:_darkAppearance];
        [_applyButton setBackgroundImage:[self imageWithColor:bg] forState:UIControlStateNormal];
        [_applyButton setTitleColor:WAMButtonTitleColor(bg) forState:UIControlStateNormal];
        return;
    }
    if (_applied) {
        [_applyButton setTitle:@"Applied" forState:UIControlStateNormal];
        UIColor *bg = [UIColor colorWithWhite:0.5 alpha:0.18];
        [_applyButton setBackgroundImage:[self imageWithColor:bg] forState:UIControlStateNormal];
        [_applyButton setTitleColor:[UIColor secondaryLabelColor] forState:UIControlStateNormal];
        _applyButton.enabled = NO;
        return;
    }
    [_applyButton setTitle:@"Apply" forState:UIControlStateNormal];
    _applyButton.enabled = YES;
    UIColor *bg = _accentColor ?: [_preset tintColorForDark:_darkAppearance];
    [_applyButton setBackgroundImage:[self imageWithColor:bg] forState:UIControlStateNormal];
    [_applyButton setTitleColor:WAMButtonTitleColor(bg) forState:UIControlStateNormal];
}

- (void)setShowsConvListPreview:(BOOL)shows {
    _showsConvListPreview = shows;
    _listPreview.hidden = !shows;
    _listCaption.hidden = !shows;
    [self setNeedsLayout];
}

- (void)setOnDelete:(void (^)(WAMPreset *))onDelete {
    _onDelete = [onDelete copy];
    _deleteButton.hidden = (onDelete == nil);
}

- (void)setOnRename:(void (^)(WAMPreset *))onRename {
    _onRename = [onRename copy];
    _renameButton.hidden = (onRename == nil);
    [self setNeedsLayout];
}

- (void)applyContent {
    _nameLabel.text = _preset.name;
    _subtitleLabel.text = _preset.subtitle;
    [self styleApplyButton];
}

- (UIImage *)imageWithColor:(UIColor *)color {
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(1,1)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [color setFill];
        [ctx fillRect:CGRectMake(0,0,1,1)];
    }];
}

+ (CGFloat)heightForWidth:(CGFloat)width showsConvList:(BOOL)showsConvList {
    return kCardInset + kHeaderH + 10 + kPreviewH + 4 + kCaptionH + 12 + kApplyH + kCardInset;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width;
    CGFloat inner = W - kCardInset*2;
    CGFloat y = kCardInset;

    CGFloat reserved = (_onRename ? 132 : (_onDelete ? 64 : 0));
    _nameLabel.frame = CGRectMake(kCardInset, y, inner - reserved, 22);
    _subtitleLabel.frame = CGRectMake(kCardInset, y + 22, inner, 16);
    y += kHeaderH + 10;

    if (_showsConvListPreview) {
        CGFloat gap = 10;
        CGFloat pw = (inner - gap) / 2;
        _listPreview.frame = CGRectMake(kCardInset, y, pw, kPreviewH);
        _chatPreview.frame = CGRectMake(kCardInset + pw + gap, y, pw, kPreviewH);
        _listCaption.frame = CGRectMake(kCardInset, y + kPreviewH + 4, pw, kCaptionH);
        _chatCaption.frame = CGRectMake(kCardInset + pw + gap, y + kPreviewH + 4, pw, kCaptionH);
    } else {
        _chatPreview.frame = CGRectMake(kCardInset, y, inner, kPreviewH);
        _chatCaption.frame = CGRectMake(kCardInset, y + kPreviewH + 4, inner, kCaptionH);
    }
    y += kPreviewH + 4 + kCaptionH + 12;

    _applyButton.frame = CGRectMake(kCardInset, y, inner, kApplyH);

    _deleteButton.frame = CGRectMake(W - kCardInset - 58, kCardInset - 2, 58, 24);
    _deleteButton.hidden = (_onDelete == nil);
    _renameButton.frame = CGRectMake(CGRectGetMinX(_deleteButton.frame) - 68, kCardInset - 2, 66, 24);
    _renameButton.hidden = (_onRename == nil);
}

- (void)applyTapped { if (_onApply) _onApply(_preset); }
- (void)deleteTapped { if (_onDelete) _onDelete(_preset); }
- (void)renameTapped { if (_onRename) _onRename(_preset); }

@end

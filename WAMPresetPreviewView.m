#import "WAMPresetPreviewView.h"

#pragma mark - Bubble path

static UIBezierPath *WAMPreviewBubblePath(CGSize size, BOOL tailRight) {
    CGFloat w = size.width, h = size.height;
    CGFloat k = MIN(1.0, (h / 2.0 - 1.0) / 17.0);
    if (k < 0.35) k = 0.35;
#define K(x) ((x) * k)
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(K(22), h)];
    [p addLineToPoint:CGPointMake(w - K(17), h)];
    [p addCurveToPoint:CGPointMake(w, h - K(17)) controlPoint1:CGPointMake(w - K(7.61), h)  controlPoint2:CGPointMake(w, h - K(7.61))];
    [p addLineToPoint:CGPointMake(w, K(17))];
    [p addCurveToPoint:CGPointMake(w - K(17), 0)  controlPoint1:CGPointMake(w, K(7.61))      controlPoint2:CGPointMake(w - K(7.61), 0)];
    [p addLineToPoint:CGPointMake(K(21), 0)];
    [p addCurveToPoint:CGPointMake(K(4), K(17))   controlPoint1:CGPointMake(K(11.61), 0)     controlPoint2:CGPointMake(K(4), K(7.61))];
    [p addLineToPoint:CGPointMake(K(4), h - K(11))];
    [p addCurveToPoint:CGPointMake(0, h)          controlPoint1:CGPointMake(K(4), h - K(1))  controlPoint2:CGPointMake(0, h)];
    [p addLineToPoint:CGPointMake(K(-0.05), h - K(0.01))];
    [p addCurveToPoint:CGPointMake(K(11.04), h - K(4.04)) controlPoint1:CGPointMake(K(4.07), h + K(0.43)) controlPoint2:CGPointMake(K(8.16), h - K(1.06))];
    [p addCurveToPoint:CGPointMake(K(22), h)      controlPoint1:CGPointMake(K(16), h)        controlPoint2:CGPointMake(K(19), h)];
    [p closePath];
#undef K
    if (tailRight) {
        [p applyTransform:CGAffineTransformMakeScale(-1, 1)];
        [p applyTransform:CGAffineTransformMakeTranslation(w, 0)];
    }
    return p;
}

#pragma mark - Pure blur

@interface WAMPureBlurView : UIVisualEffectView
@end
@implementation WAMPureBlurView
- (void)layoutSubviews {
    [super layoutSubviews];
    Class tintCls = NSClassFromString(@"_UIVisualEffectSubview");
    if (!tintCls) return;
    for (UIView *sub in [self.subviews copy]) {
        if ([sub isMemberOfClass:tintCls]) [sub removeFromSuperview];
    }
}
@end

#pragma mark - View

@implementation WAMPresetPreviewView {
    NSMutableArray<UIView *> *_content;
    UIView *_backdrop;
    UIImageView *_bgImage;
    UIVisualEffectView *_blurLayer;
    NSString *_cachedBgKey;
    UIImage *_cachedBg;
}

- (instancetype)initWithPreset:(WAMPreset *)preset style:(WAMPreviewStyle)style dark:(BOOL)dark {
    if ((self = [super initWithFrame:CGRectZero])) {
        _preset = preset;
        _style = style;
        _darkAppearance = dark;
        _content = [NSMutableArray array];
        self.clipsToBounds = YES;
        self.layer.cornerRadius = 18;
        if (@available(iOS 13.0, *)) self.layer.cornerCurve = kCACornerCurveContinuous;
        _backdrop = [UIView new];
        [self addSubview:_backdrop];
        _bgImage = [UIImageView new];
        _bgImage.contentMode = UIViewContentModeScaleAspectFill;
        _bgImage.clipsToBounds = YES;
        [self addSubview:_bgImage];
    }
    return self;
}

- (void)setPreset:(WAMPreset *)preset { _preset = preset; [self setNeedsLayout]; }
- (void)setStyle:(WAMPreviewStyle)style { _style = style; [self setNeedsLayout]; }
- (void)setDarkAppearance:(BOOL)dark { _darkAppearance = dark; [self setNeedsLayout]; }
- (void)refresh { [self setNeedsLayout]; [self layoutIfNeeded]; }

- (void)layoutSubviews {
    [super layoutSubviews];
    for (UIView *v in _content) [v removeFromSuperview];
    [_content removeAllObjects];
    _backdrop.frame = self.bounds;
    _bgImage.frame = self.bounds;
    if (!self.preset) return;

    BOOL convList = (self.style == WAMPreviewStyleConvList);
    NSString *key = [NSString stringWithFormat:@"%@|%d|%d|%dx%d", self.preset.identifier,
                     self.darkAppearance, convList, (int)self.bounds.size.width, (int)self.bounds.size.height];
    if (![key isEqualToString:_cachedBgKey]) {
        _cachedBg = WAMPresetPreviewBackgroundImage(self.preset, self.darkAppearance, convList, self.bounds.size);
        _cachedBgKey = key;
    }
    _bgImage.image = _cachedBg;
    _bgImage.hidden = (_cachedBg == nil);

    if (self.style == WAMPreviewStyleChat) [self layoutChat];
    else [self layoutConvList];
}

- (UILabel *)labelText:(NSString *)text color:(UIColor *)color size:(CGFloat)size weight:(UIFontWeight)weight {
    UILabel *l = [UILabel new];
    l.text = text;
    l.textColor = color;
    l.font = [UIFont systemFontOfSize:size weight:weight];
    return l;
}

#pragma mark Chat

- (void)layoutChat {
    BOOL dark = self.darkAppearance;
    WAMPreset *p = self.preset;
    _backdrop.backgroundColor = [p backgroundColorForDark:dark];

    [_blurLayer removeFromSuperview];
    _blurLayer = nil;
    BOOL blur = [p blurEnabledForDark:dark];

    CGFloat W = self.bounds.size.width, pad = 12;
    CGFloat maxBubbleW = W * 0.66;
    CGFloat y = 16;

    NSArray *rows = @[ @{@"t":@"Love this new look!", @"sent":@NO},
                       @{@"t":@"Right? About time.",       @"sent":@YES},
                       @{@"t":@"dev's lazy ngl", @"sent":@NO} ];

    for (NSDictionary *row in rows) {
        BOOL sent = [row[@"sent"] boolValue];
        UIColor *bubbleColor = sent ? [p sentColorForDark:dark] : [p receivedColorForDark:dark];
        UIColor *textColor   = sent ? [p sentTextColorForDark:dark] : [p receivedTextColorForDark:dark];

        UILabel *lbl = [self labelText:row[@"t"] color:textColor size:12.5 weight:UIFontWeightRegular];
        lbl.numberOfLines = 0;
        CGFloat textMaxW = maxBubbleW - 22;
        CGSize ts = [lbl sizeThatFits:CGSizeMake(textMaxW, 999)];
        CGFloat bw = MIN(maxBubbleW, ts.width + 22);
        CGFloat bh = ts.height + 14;
        CGFloat bx = sent ? (W - pad - bw) : pad;

        UIView *bubble = [[UIView alloc] initWithFrame:CGRectMake(bx, y, bw, bh)];
        CAShapeLayer *mask = [CAShapeLayer layer];
        mask.path = WAMPreviewBubblePath(CGSizeMake(bw, bh), sent).CGPath;
        bubble.layer.mask = mask;

        if (blur) {
            WAMPureBlurView *bv = [[WAMPureBlurView alloc]
                initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular]];
            bv.frame = bubble.bounds;
            bv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [bubble addSubview:bv];

            UIView *tint = [[UIView alloc] initWithFrame:bubble.bounds];
            tint.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            tint.backgroundColor = bubbleColor;
            [bubble addSubview:tint];
        } else {
            bubble.backgroundColor = bubbleColor;
        }

        lbl.frame = CGRectMake(sent ? 10 : 12, 7, bw - 22, ts.height);
        [bubble addSubview:lbl];
        [self addSubview:bubble];
        [_content addObject:bubble];
        y += bh + 8;
    }
}

#pragma mark Conversation list

- (void)layoutConvList {
    BOOL dark = self.darkAppearance;
    WAMPreset *p = self.preset;
    _backdrop.backgroundColor = [p backgroundColorForDark:dark];

    CGFloat W = self.bounds.size.width;
    CGFloat pad = 14;

    UILabel *title = [self labelText:@"Messages" color:[p titleColorForDark:dark] size:22 weight:UIFontWeightBold];
    title.frame = CGRectMake(pad, 12, W - pad*2, 28);
    [self addSubview:title];
    [_content addObject:title];

    UIColor *titleColor = [p titleColorForDark:dark];
    UIColor *previewColor = [p previewColorForDark:dark];
    UIColor *avatarColor = [p tintColorForDark:dark];

    NSArray *rows = @[ @{@"n":@"Joe",   @"m":@"Love this new look!"},
                       @{@"n":@"Bob", @"m":@"What do you wanna do tomorrow?"}];

    CGFloat rowH = 52, y = 48;
    for (NSDictionary *row in rows) {
        UIView *cell = [[UIView alloc] initWithFrame:CGRectMake(8, y, W - 16, rowH - 6)];
        cell.backgroundColor = [UIColor clearColor];

        UIView *avatar = [[UIView alloc] initWithFrame:CGRectMake(10, (rowH - 6 - 32)/2, 32, 32)];
        avatar.backgroundColor = avatarColor;
        avatar.layer.cornerRadius = 16;
        [cell addSubview:avatar];

        UILabel *name = [self labelText:row[@"n"] color:titleColor size:14 weight:UIFontWeightSemibold];
        name.frame = CGRectMake(52, 8, cell.bounds.size.width - 62, 18);
        [cell addSubview:name];

        UILabel *msg = [self labelText:row[@"m"] color:previewColor size:12.5 weight:UIFontWeightRegular];
        msg.frame = CGRectMake(52, 26, cell.bounds.size.width - 62, 16);
        [cell addSubview:msg];

        [self addSubview:cell];
        [_content addObject:cell];
        y += rowH;
    }
}

@end

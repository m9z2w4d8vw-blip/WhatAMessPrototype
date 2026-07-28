#import "WAMGradientBuilderController.h"
#import "WAMPresetModel.h"

@interface WAMGradientBuilderController () <UIColorPickerViewControllerDelegate>
@end

@implementation WAMGradientBuilderController {
    NSMutableArray<NSString *> *_stops;
    WAMGradientDirection _direction;
    UIView *_previewCard;
    CAGradientLayer *_previewGradient;
    UIStackView *_swatchRow;
    UISegmentedControl *_directionControl;
    UIButton *_addButton;
    UILabel *_hint;
    NSInteger _editingIndex;
}

- (instancetype)initWithStops:(NSArray<NSString *> *)stops {
    if ((self = [super init])) {
        _stops = [stops.count >= 2 ? stops : @[] mutableCopy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Gradient Background";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    if (_stops.count < 2) {
        NSArray *last = self.initialStops.count >= 2 ? self.initialStops : [WAMPresetStore lastGradientStops];
        _stops = [(last.count >= 2 ? last : @[@"#3A6FF0FF", @"#8A2BE2FF"]) mutableCopy];
        _direction = last.count >= 2 ? [WAMPresetStore lastGradientDirection] : WAMGradientDirectionDiagonal;
    } else {
        _direction = [WAMPresetStore lastGradientDirection];
    }

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self action:@selector(cancelTapped)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Set" style:UIBarButtonItemStyleDone
                                        target:self action:@selector(setTapped)];

    _previewCard = [UIView new];
    _previewCard.layer.cornerRadius = 20;
    if (@available(iOS 13.0, *)) _previewCard.layer.cornerCurve = kCACornerCurveContinuous;
    _previewCard.clipsToBounds = YES;
    _previewCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_previewCard];

    _previewGradient = [CAGradientLayer layer];
    [_previewCard.layer addSublayer:_previewGradient];

    _directionControl = [[UISegmentedControl alloc] initWithItems:@[@"Vertical", @"Diagonal", @"Horizontal"]];
    _directionControl.selectedSegmentIndex = (NSInteger)_direction;
    [_directionControl addTarget:self action:@selector(directionChanged:) forControlEvents:UIControlEventValueChanged];
    _directionControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_directionControl];

    _hint = [UILabel new];
    _hint.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _hint.textColor = [UIColor secondaryLabelColor];
    _hint.textAlignment = NSTextAlignmentCenter;
    _hint.numberOfLines = 0;
    _hint.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_hint];

    _swatchRow = [UIStackView new];
    _swatchRow.axis = UILayoutConstraintAxisHorizontal;
    _swatchRow.distribution = UIStackViewDistributionFillEqually;
    _swatchRow.spacing = 12;
    _swatchRow.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_swatchRow];

    _addButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_addButton setTitle:@"Add Color" forState:UIControlStateNormal];
    _addButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [_addButton addTarget:self action:@selector(addStop) forControlEvents:UIControlEventTouchUpInside];
    _addButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_addButton];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_previewCard.topAnchor constraintEqualToAnchor:g.topAnchor constant:20],
        [_previewCard.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:20],
        [_previewCard.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-20],
        [_previewCard.heightAnchor constraintEqualToConstant:260],

        [_directionControl.topAnchor constraintEqualToAnchor:_previewCard.bottomAnchor constant:18],
        [_directionControl.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:20],
        [_directionControl.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-20],

        [_hint.topAnchor constraintEqualToAnchor:_directionControl.bottomAnchor constant:18],
        [_hint.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:20],
        [_hint.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-20],

        [_swatchRow.topAnchor constraintEqualToAnchor:_hint.bottomAnchor constant:10],
        [_swatchRow.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:20],
        [_swatchRow.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-20],
        [_swatchRow.heightAnchor constraintEqualToConstant:62],

        [_addButton.topAnchor constraintEqualToAnchor:_swatchRow.bottomAnchor constant:16],
        [_addButton.centerXAnchor constraintEqualToAnchor:g.centerXAnchor],
    ]];

    [self rebuildSwatches];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _previewGradient.frame = _previewCard.bounds;
}

#pragma mark - Rendering

- (void)refreshPreview {
    NSMutableArray *cg = [NSMutableArray array];
    for (NSString *hex in _stops) [cg addObject:(id)(WAMColorFromHex(hex) ?: UIColor.grayColor).CGColor];
    _previewGradient.colors = cg;
    switch (_direction) {
        case WAMGradientDirectionVertical:
            _previewGradient.startPoint = CGPointMake(0.5, 0);   _previewGradient.endPoint = CGPointMake(0.5, 1); break;
        case WAMGradientDirectionHorizontal:
            _previewGradient.startPoint = CGPointMake(0, 0.5);   _previewGradient.endPoint = CGPointMake(1, 0.5); break;
        case WAMGradientDirectionDiagonal:
        default:
            _previewGradient.startPoint = CGPointMake(0, 0);     _previewGradient.endPoint = CGPointMake(1, 1);   break;
    }
    _addButton.enabled = (_stops.count < 5);
    _hint.text = (_stops.count > 2)
        ? @"Tap a color to change it · tap ✕ to remove"
        : @"Tap a color to change it";
}

- (void)rebuildSwatches {
    for (UIView *v in _swatchRow.arrangedSubviews) { [_swatchRow removeArrangedSubview:v]; [v removeFromSuperview]; }

    BOOL removable = (_stops.count > 2);
    for (NSInteger i = 0; i < (NSInteger)_stops.count; i++) {
        UIView *container = [UIView new];

        UIButton *sw = [UIButton buttonWithType:UIButtonTypeCustom];
        sw.tag = i;
        sw.backgroundColor = WAMColorFromHex(_stops[i]);
        sw.layer.cornerRadius = 12;
        if (@available(iOS 13.0, *)) sw.layer.cornerCurve = kCACornerCurveContinuous;
        sw.layer.borderWidth = 1;
        sw.layer.borderColor = [[UIColor separatorColor] CGColor];
        sw.translatesAutoresizingMaskIntoConstraints = NO;
        [sw addTarget:self action:@selector(swatchTapped:) forControlEvents:UIControlEventTouchUpInside];
        [container addSubview:sw];

        UIButton *del = [UIButton buttonWithType:UIButtonTypeCustom];
        del.tag = i;
        [del setTitle:@"✕" forState:UIControlStateNormal];
        del.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
        [del setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        del.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.85];
        del.layer.cornerRadius = 9;
        del.hidden = !removable;
        del.translatesAutoresizingMaskIntoConstraints = NO;
        [del addTarget:self action:@selector(removeStop:) forControlEvents:UIControlEventTouchUpInside];
        [container addSubview:del];

        [NSLayoutConstraint activateConstraints:@[
            [sw.topAnchor constraintEqualToAnchor:container.topAnchor constant:6],
            [sw.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [sw.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [sw.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],

            [del.topAnchor constraintEqualToAnchor:container.topAnchor],
            [del.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:4],
            [del.widthAnchor constraintEqualToConstant:18],
            [del.heightAnchor constraintEqualToConstant:18],
        ]];

        [_swatchRow addArrangedSubview:container];
    }
    [self refreshPreview];
}

#pragma mark - Actions

- (void)directionChanged:(UISegmentedControl *)sc {
    _direction = (WAMGradientDirection)sc.selectedSegmentIndex;
    [self refreshPreview];
}

- (void)swatchTapped:(UIButton *)sender {
    _editingIndex = sender.tag;
    UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
    picker.delegate = self;
    picker.selectedColor = WAMColorFromHex(_stops[_editingIndex]) ?: UIColor.grayColor;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)removeStop:(UIButton *)sender {
    NSInteger idx = sender.tag;
    if (_stops.count <= 2 || idx < 0 || idx >= (NSInteger)_stops.count) return;
    [_stops removeObjectAtIndex:idx];
    [self rebuildSwatches];
}

- (void)addStop {
    if (_stops.count >= 5) return;
    [_stops addObject:_stops.lastObject ?: @"#FFFFFFFF"];
    [self rebuildSwatches];
}

#pragma mark - Color picker

- (void)colorPickerViewController:(UIColorPickerViewController *)vc didSelectColor:(UIColor *)color continuously:(BOOL)continuously {
    if (_editingIndex < 0 || _editingIndex >= (NSInteger)_stops.count) return;
    _stops[_editingIndex] = WAMHexFromColor(color);
    UIView *container = _swatchRow.arrangedSubviews[_editingIndex];
    container.subviews.firstObject.backgroundColor = color;
    [self refreshPreview];
}

#pragma mark - Done

- (void)cancelTapped { if (self.onDone) self.onDone(nil, _direction); }

- (void)setTapped {
    [WAMPresetStore saveLastGradientStops:_stops direction:_direction];
    if (self.onDone) self.onDone([_stops copy], _direction);
}

@end

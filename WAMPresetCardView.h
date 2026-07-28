#import <UIKit/UIKit.h>
#import "WAMPresetModel.h"

@interface WAMPresetCardView : UIView
@property (nonatomic, strong) WAMPreset *preset;
@property (nonatomic, assign) BOOL darkAppearance;
@property (nonatomic, assign) BOOL showsConvListPreview;
@property (nonatomic, strong) UIColor *accentColor;
@property (nonatomic, assign) BOOL applied;
@property (nonatomic, assign) BOOL exportMode;
@property (nonatomic, copy)   void (^onApply)(WAMPreset *preset);
@property (nonatomic, copy)   void (^onDelete)(WAMPreset *preset);
@property (nonatomic, copy)   void (^onRename)(WAMPreset *preset);

- (instancetype)initWithPreset:(WAMPreset *)preset dark:(BOOL)dark;
+ (CGFloat)heightForWidth:(CGFloat)width showsConvList:(BOOL)showsConvList;
@end

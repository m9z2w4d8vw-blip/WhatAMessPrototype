#import <UIKit/UIKit.h>
#import "WAMPresetModel.h"

typedef NS_ENUM(NSUInteger, WAMPreviewStyle) {
    WAMPreviewStyleChat = 0,
    WAMPreviewStyleConvList,
};

@interface WAMPresetPreviewView : UIView
@property (nonatomic, strong) WAMPreset *preset;
@property (nonatomic, assign) WAMPreviewStyle style;
@property (nonatomic, assign) BOOL darkAppearance;

- (instancetype)initWithPreset:(WAMPreset *)preset style:(WAMPreviewStyle)style dark:(BOOL)dark;
- (void)refresh;
@end

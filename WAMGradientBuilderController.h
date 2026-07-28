#import <UIKit/UIKit.h>
#import "WAMPresetModel.h"

@interface WAMGradientBuilderController : UIViewController
@property (nonatomic, copy) NSArray<NSString *> *initialStops;
@property (nonatomic, copy) void (^onDone)(NSArray<NSString *> *stops, WAMGradientDirection direction);
- (instancetype)initWithStops:(NSArray<NSString *> *)stops;
@end

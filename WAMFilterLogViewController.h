#import <UIKit/UIKit.h>
#import "WAMFilterModel.h"

@interface WAMFilterLogViewController : UIViewController
@property (nonatomic, assign) BOOL showsDoneButton;
+ (UINavigationController *)wrappedForPresentation;
@end

#import <UIKit/UIKit.h>
#import "WAMFilterModel.h"

@interface WAMManageFilteringController : UIViewController
    <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>

@property (nonatomic, assign) BOOL showsDoneButton;
@property (nonatomic, copy)   void (^onChanged)(void);

+ (UINavigationController *)wrappedForPresentation;

@end

#import <UIKit/UIKit.h>
#import "WAMFilterModel.h"

// Shows the conversations matching one filter, as a sheet over the native list.
// Interim: in-place filtering of the conversation list needs the data source,
// which is not identified yet. Tapping a row opens the real thread.
@interface WAMFilterResultsController : UIViewController
    <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, assign) WAMFilter filter;

+ (UINavigationController *)wrappedForFilter:(WAMFilter)filter;

@end

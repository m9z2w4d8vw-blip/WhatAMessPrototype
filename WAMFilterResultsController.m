#import "WAMFilterResultsController.h"
#import "WAMManageFilteringController.h"
#import "WAMDebugLog.h"

@implementation WAMFilterResultsController {
    UITableView *_table;
    NSArray<NSDictionary *> *_rows;
}

+ (UINavigationController *)wrappedForFilter:(WAMFilter)filter {
    WAMFilterResultsController *vc = [WAMFilterResultsController new];
    vc.filter = filter;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    return nav;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [WAMFilterStore nameForFilter:self.filter];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(dismissSelf)];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Manage"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(openManage)];

    _table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _table.dataSource = self;
    _table.delegate = self;
    _table.rowHeight = 68;
    _table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_table];

    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)dismissSelf {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)openManage {
    WAMManageFilteringController *vc = [WAMManageFilteringController new];
    vc.showsDoneButton = NO;
    __weak typeof(self) weakSelf = self;
    vc.onChanged = ^{
        [weakSelf reload];
    };
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)reload {
    NSMutableArray *keep = [NSMutableArray array];
    for (NSDictionary *e in [WAMFilterStore roster]) {
        if ([WAMFilterStore shouldShowTitle:e[@"title"] underFilter:self.filter]) {
            [keep addObject:e];
        }
    }
    _rows = keep;
    WAMLog(@"ui", @"results sheet %@: %lu of %lu roster entries match",
           [WAMFilterStore nameForFilter:self.filter],
           (unsigned long)_rows.count, (unsigned long)[WAMFilterStore roster].count);
    [_table reloadData];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return _rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"row"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"row"];
        cell.detailTextLabel.numberOfLines = 2;
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    NSDictionary *e = _rows[ip.row];
    cell.textLabel.text = e[@"title"];
    cell.detailTextLabel.text = e[@"preview"];
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];

    NSString *title = _rows[ip.row][@"title"];

    // Open the real thread via the sms: scheme. No private API, and it works
    // for both saved contacts and raw numbers.
    NSMutableString *addr = [NSMutableString string];
    for (NSUInteger i = 0; i < title.length; i++) {
        unichar c = [title characterAtIndex:i];
        if ((c >= '0' && c <= '9') || c == '+') [addr appendFormat:@"%C", c];
    }
    if (!addr.length) {
        WAMLog(@"ui", @"cannot open '%@': no dialable address", title);
        UIAlertController *a = [UIAlertController
            alertControllerWithTitle:title
                             message:@"This sender has no phone number to open directly. Find it in the main list."
                      preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }

    NSURL *url = [NSURL URLWithString:[@"sms:" stringByAppendingString:addr]];
    WAMLog(@"ui", @"opening %@", url.absoluteString);
    [self dismissViewControllerAnimated:YES completion:^{
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
    if (_rows.count) return nil;
    return @"Nothing here yet. Senders are recorded as their rows appear in the main "
            "list, so scroll it once. You can also assign senders by hand under Manage.";
}

@end

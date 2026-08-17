#import "WAMManageFilteringController.h"

@interface WAMFilterPickerController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *senderTitle;
@property (nonatomic, copy) void (^onPicked)(WAMFilter filter);
@end

@implementation WAMFilterPickerController {
    UITableView *_table;
    NSArray<NSNumber *> *_options;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.senderTitle ?: @"Filter";
    _options = [WAMFilterStore assignableFilters];

    _table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _table.dataSource = self;
    _table.delegate = self;
    _table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_table];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return _options.count;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
    return @"Choosing None falls back to automatic detection: numeric short codes carrying a "
            "passcode land in 2FA, other unsaved numbers land in Unknown Senders.";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"opt"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"opt"];
    }

    WAMFilter f = (WAMFilter)[_options[ip.row] integerValue];
    cell.textLabel.text = [WAMFilterStore nameForFilter:f];
    cell.imageView.image = [UIImage systemImageNamed:[WAMFilterStore symbolForFilter:f]];

    BOOL isCurrent = ([WAMFilterStore assignedFilterForTitle:self.senderTitle] == f);
    cell.accessoryType = isCurrent ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;

    if (f == WAMFilterTransactionsOrders || f == WAMFilterTransactionsFinance ||
        f == WAMFilterTransactionsReminders) {
        cell.textLabel.text = [NSString stringWithFormat:@"Transactions · %@",
                               [WAMFilterStore nameForFilter:f]];
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    WAMFilter f = (WAMFilter)[_options[ip.row] integerValue];
    [WAMFilterStore setAssignedFilter:f forTitle:self.senderTitle];
    [WAMFilterStore postFilterChanged];
    if (self.onPicked) self.onPicked(f);
    [self.navigationController popViewControllerAnimated:YES];
}

@end

#pragma mark -

@implementation WAMManageFilteringController {
    UITableView *_table;
    UISearchBar *_search;
    NSArray<NSDictionary *> *_all;
    NSArray<NSDictionary *> *_shown;
    NSString *_query;
}

+ (UINavigationController *)wrappedForPresentation {
    WAMManageFilteringController *vc = [WAMManageFilteringController new];
    vc.showsDoneButton = YES;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    return nav;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Manage Filtering";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    UIBarButtonItem *add =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                      target:self
                                                      action:@selector(addManualSender)];

    if (self.showsDoneButton) {
        // Presented as a sheet from Messages: Done on the right, Add on the left.
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                          target:self
                                                          action:@selector(dismissSelf)];
        self.navigationItem.leftBarButtonItem = add;
    } else {
        // Pushed from Settings: leave the left side alone so the back button survives.
        self.navigationItem.rightBarButtonItem = add;
    }

    _search = [[UISearchBar alloc] init];
    _search.placeholder = @"Search numbers and names";
    _search.delegate = self;
    _search.searchBarStyle = UISearchBarStyleMinimal;
    _search.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _search.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_search];

    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _table.dataSource = self;
    _table.delegate = self;
    _table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    _table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_table];

    [NSLayoutConstraint activateConstraints:@[
        [_search.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_search.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [_search.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],

        [_table.topAnchor constraintEqualToAnchor:_search.bottomAnchor constant:4],
        [_table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)dismissSelf {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)reload {
    _all = [WAMFilterStore roster];
    [self applyQuery];
}

- (void)applyQuery {
    if (!_query.length) {
        _shown = _all;
    } else {
        NSString *needle = [_query lowercaseString];
        NSMutableString *needleDigits = [NSMutableString string];
        for (NSUInteger i = 0; i < needle.length; i++) {
            unichar c = [needle characterAtIndex:i];
            if (c >= '0' && c <= '9') [needleDigits appendFormat:@"%C", c];
        }

        NSMutableArray *out = [NSMutableArray array];
        for (NSDictionary *e in _all) {
            NSString *title = e[@"title"];
            if ([[title lowercaseString] rangeOfString:needle].location != NSNotFound) {
                [out addObject:e];
                continue;
            }
            if (needleDigits.length) {
                NSMutableString *titleDigits = [NSMutableString string];
                for (NSUInteger i = 0; i < title.length; i++) {
                    unichar c = [title characterAtIndex:i];
                    if (c >= '0' && c <= '9') [titleDigits appendFormat:@"%C", c];
                }
                if ([titleDigits rangeOfString:needleDigits].location != NSNotFound) {
                    [out addObject:e];
                }
            }
        }
        _shown = out;
    }
    [_table reloadData];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
    _query = text;
    [self applyQuery];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (void)addManualSender {
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"Add Sender"
                         message:@"Enter a phone number, short code, or contact name exactly as it appears in Messages."
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"+1 (555) 555-0100";
        tf.keyboardType = UIKeyboardTypeNamePhonePad;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *action) {
            NSString *t = [a.textFields.firstObject.text
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (!t.length) return;
            [WAMFilterStore recordSenderTitle:t preview:@""];
            [self reload];
            [self pushPickerForTitle:t];
        }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)pushPickerForTitle:(NSString *)title {
    WAMFilterPickerController *picker = [WAMFilterPickerController new];
    picker.senderTitle = title;
    __weak typeof(self) weakSelf = self;
    picker.onPicked = ^(WAMFilter f) {
        __strong typeof(self) s = weakSelf;
        [s reload];
        if (s.onChanged) s.onChanged();
    };
    [self.navigationController pushViewController:picker animated:YES];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return _shown.count;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    if (!_all.count) return nil;
    return [NSString stringWithFormat:@"%lu sender%@", (unsigned long)_shown.count,
            _shown.count == 1 ? @"" : @"s"];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
    if (!_all.count) {
        return @"No senders recorded yet. Open Messages and scroll the conversation list once — "
                "every conversation that comes on screen is added here. You can also add one by hand "
                "with the + button.";
    }
    return @"Tap a sender to move it into a filter. Swipe left to forget it. Senders with no "
            "assignment are categorised automatically.";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"sender"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"sender"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    NSDictionary *e = _shown[ip.row];
    NSString *title = e[@"title"];
    cell.textLabel.text = title;

    WAMFilter assigned = [WAMFilterStore assignedFilterForTitle:title];
    WAMFilter effective = [WAMFilterStore effectiveFilterForTitle:title];

    NSString *label = [WAMFilterStore nameForFilter:effective];
    if (effective == WAMFilterTransactionsOrders || effective == WAMFilterTransactionsFinance ||
        effective == WAMFilterTransactionsReminders) {
        label = [NSString stringWithFormat:@"Transactions · %@", label];
    }
    if (assigned == WAMFilterUnassigned) {
        cell.detailTextLabel.text = (effective == WAMFilterUnassigned)
            ? @"No filter"
            : [NSString stringWithFormat:@"%@ (automatic)", label];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    } else {
        cell.detailTextLabel.text = label;
        cell.detailTextLabel.textColor = [UIColor labelColor];
    }

    cell.imageView.image = [UIImage systemImageNamed:[WAMFilterStore symbolForFilter:effective]];
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [self pushPickerForTitle:_shown[ip.row][@"title"]];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {

    NSString *title = _shown[ip.row][@"title"];
    UIContextualAction *forget = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
                            title:@"Forget"
                          handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        [WAMFilterStore removeRosterEntryForTitle:title];
        [WAMFilterStore postFilterChanged];
        [self reload];
        done(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[forget]];
}

@end

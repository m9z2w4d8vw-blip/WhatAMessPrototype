#import "WAMFilterLogViewController.h"
#import "WAMDebugLog.h"

@implementation WAMFilterLogViewController {
    UITextView *_text;
    UILabel *_status;
    UISegmentedControl *_scope;
    NSString *_raw;
}

+ (UINavigationController *)wrappedForPresentation {
    WAMFilterLogViewController *vc = [WAMFilterLogViewController new];
    vc.showsDoneButton = YES;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    return nav;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Debug Log";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    UIBarButtonItem *share = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                             target:self
                             action:@selector(shareLog)];

    if (self.showsDoneButton) {
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                          target:self
                                                          action:@selector(dismissSelf)];
        self.navigationItem.leftBarButtonItem = share;
    } else {
        self.navigationItem.rightBarButtonItem = share;
    }

    _scope = [[UISegmentedControl alloc] initWithItems:@[@"All", @"hooks", @"nav", @"prefs", @"chat"]];
    _scope.selectedSegmentIndex = 0;
    [_scope addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    _scope.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_scope];

    _status = [UILabel new];
    _status.font = [UIFont systemFontOfSize:12];
    _status.textColor = [UIColor secondaryLabelColor];
    _status.textAlignment = NSTextAlignmentCenter;
    _status.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_status];

    _text = [UITextView new];
    _text.editable = NO;
    _text.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    _text.alwaysBounceVertical = YES;
    _text.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_text];

    UIToolbar *bar = [UIToolbar new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.items = @[
        [[UIBarButtonItem alloc] initWithTitle:@"Refresh" style:UIBarButtonItemStylePlain
                                       target:self action:@selector(reload)],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                     target:nil action:nil],
        [[UIBarButtonItem alloc] initWithTitle:@"Copy" style:UIBarButtonItemStylePlain
                                       target:self action:@selector(copyLog)],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                     target:nil action:nil],
        [[UIBarButtonItem alloc] initWithTitle:@"Hooks" style:UIBarButtonItemStylePlain
                                       target:self action:@selector(showHookSummary)],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                     target:nil action:nil],
        [[UIBarButtonItem alloc] initWithTitle:@"Clear" style:UIBarButtonItemStylePlain
                                       target:self action:@selector(clearLog)],
    ];
    [self.view addSubview:bar];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_scope.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [_scope.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
        [_scope.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],

        [_status.topAnchor constraintEqualToAnchor:_scope.bottomAnchor constant:6],
        [_status.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
        [_status.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],

        [_text.topAnchor constraintEqualToAnchor:_status.bottomAnchor constant:6],
        [_text.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [_text.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        [_text.bottomAnchor constraintEqualToAnchor:bar.topAnchor],

        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
    ]];

    [self reload];
}

- (void)dismissSelf {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)reload {
    _raw = [WAMDebugLog contents];

    NSString *shown = _raw;
    if (_scope.selectedSegmentIndex > 0) {
        NSString *needle = [NSString stringWithFormat:@"[%@]",
            [_scope titleForSegmentAtIndex:_scope.selectedSegmentIndex]];
        NSMutableArray *keep = [NSMutableArray array];
        for (NSString *line in [_raw componentsSeparatedByString:@"\n"]) {
            if ([line rangeOfString:needle].location != NSNotFound) [keep addObject:line];
        }
        shown = [keep componentsJoinedByString:@"\n"];
    }

    if (!shown.length) {
        shown = ([WAMDebugLog level] == WAMLogLevelOff)
            ? @"Logging is off.\n\nSet Log Level to Normal or higher in the Debugging section, "
               "reproduce the problem, then come back and Refresh."
            : @"No matching entries.\n\nOpen Messages, exercise the tweak, then Refresh.";
    }

    _text.text = shown;
    _status.text = [NSString stringWithFormat:@"%.1f KB · %ld lines · level %@ · %ld hooks seen",
                    [WAMDebugLog byteSize] / 1024.0,
                    (long)[WAMDebugLog lineCount],
                    [WAMDebugLog nameForLevel:[WAMDebugLog level]],
                    (long)[WAMDebugLog tracedSiteCount]];

    // Jump to the newest entries, which is what you actually want to read.
    if (_text.text.length > 1) {
        [_text scrollRangeToVisible:NSMakeRange(_text.text.length - 1, 1)];
    }
}

- (void)showHookSummary {
    _text.text = [WAMDebugLog hookSummary];
    _status.text = [NSString stringWithFormat:@"%ld instrumented hooks have fired",
                    (long)[WAMDebugLog tracedSiteCount]];
}

- (void)copyLog {
    [UIPasteboard generalPasteboard].string = _raw ?: @"";
    _status.text = @"Copied to clipboard";
}

- (void)shareLog {
    NSString *path = [WAMDebugLog path];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        _status.text = @"No log file on disk yet";
        return;
    }
    UIActivityViewController *av = [[UIActivityViewController alloc]
        initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
    av.popoverPresentationController.sourceView = self.view;
    av.popoverPresentationController.sourceRect =
        CGRectMake(self.view.bounds.size.width / 2, 40, 1, 1);
    [self presentViewController:av animated:YES completion:nil];
}

- (void)clearLog {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Clear log?"
                                                              message:nil
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *action) {
            [WAMDebugLog clear];
            [self reload];
        }]];
    [self presentViewController:a animated:YES completion:nil];
}

@end

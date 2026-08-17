#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "WAMFilterModel.h"
#import "WAMDebugLog.h"
#import "WAMManageFilteringController.h"

#define kWAMFilterButtonTag 0x57414D46
#define kWAMEmptyStateTag   0x57414D45

static BOOL gWAMFCompacting = NO;
static BOOL gWAMFReinjecting = NO;
static BOOL gWAMFDidCompact = NO;
static const void *kWAMFCanonRectKey  = &kWAMFCanonRectKey;
static const void *kWAMFTitleKey      = &kWAMFTitleKey;
static const void *kWAMFOwnedNavKey   = &kWAMFOwnedNavKey;
static const void *kWAMFLastShownKey  = &kWAMFLastShownKey;

static NSUInteger gWAMFInstallCount = 0;
static NSUInteger gWAMFReinjectCount = 0;

@interface CKConversationListCollectionViewController : UICollectionViewController
- (void)wamfInstallFilterButton;
- (UIMenu *)wamfBuildFilterMenu;
- (void)wamfSelectFilter:(NSNumber *)boxed;
- (void)wamfOpenManageFiltering;
- (void)wamfOpenRecentlyDeleted;
- (void)wamfCompactFilteredCells;
- (void)wamfRefreshForFilterChange;
@end

@interface UINavigationItem (WAMFilter)
- (void)wamfMarkOwned;
- (BOOL)wamfIsOwned;
- (BOOL)wamfHasFilterItem;
- (void)wamfReinjectFromSetter:(NSString *)which;
- (NSString *)wamfDescribeRightItems;
@end

@interface CKConversationListCollectionViewConversationCell : UICollectionViewCell
- (NSString *)wamfExtractTitle;
- (NSString *)wamfExtractPreview;
- (void)wamfApplyFilterVisibility;
@end

#pragma mark - Label harvesting

static void wamfCollectLabels(UIView *root, NSMutableArray<UILabel *> *out, int depth) {
    if (!root || depth > 8) return;
    for (UIView *v in root.subviews) {
        if ([v isKindOfClass:[UILabel class]]) {
            UILabel *l = (UILabel *)v;
            NSString *t = [l.text stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (t.length) [out addObject:l];
        }
        wamfCollectLabels(v, out, depth + 1);
    }
}

static UILabel *wamfTitleLabel(UIView *cell) {
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    wamfCollectLabels(cell, labels, 0);
    if (!labels.count) return nil;

    UILabel *best = nil;
    CGFloat bestSize = 0;
    CGFloat bestY = CGFLOAT_MAX;

    for (UILabel *l in labels) {
        CGRect f = [l convertRect:l.bounds toView:cell];
        CGFloat size = l.font.pointSize;
        if (size > bestSize + 0.5 || (fabs(size - bestSize) <= 0.5 && f.origin.y < bestY - 2)) {
            best = l;
            bestSize = size;
            bestY = f.origin.y;
        }
    }
    return best;
}

#pragma mark - Filter bar button item

static UIBarButtonItem *wamfMakeFilterItem(UIMenu *menu, WAMFilter active) {
    NSString *glyph = (active == WAMFilterAllMessages)
        ? @"line.3.horizontal.decrease.circle"
        : @"line.3.horizontal.decrease.circle.fill";

    UIImage *img = [UIImage systemImageNamed:glyph];
    if (!img) {
        WAMLog(@"nav", @"systemImageNamed:%@ returned nil, falling back", glyph);
        img = [UIImage systemImageNamed:@"line.3.horizontal"];
    }

    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:img
                                                            style:UIBarButtonItemStylePlain
                                                           target:nil
                                                           action:nil];
    item.tag = kWAMFilterButtonTag;
    item.accessibilityLabel = @"Filters";
    item.menu = menu;
    return item;
}

#pragma mark - UINavigationItem: keep our button alive

%hook UINavigationItem

%new
- (void)wamfMarkOwned {
    objc_setAssociatedObject(self, kWAMFOwnedNavKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (BOOL)wamfIsOwned {
    return [(NSNumber *)objc_getAssociatedObject(self, kWAMFOwnedNavKey) boolValue];
}

%new
- (BOOL)wamfHasFilterItem {
    for (UIBarButtonItem *i in self.rightBarButtonItems) {
        if (i.tag == kWAMFilterButtonTag) return YES;
    }
    return NO;
}

%new
- (NSString *)wamfDescribeRightItems {
    NSMutableArray *bits = [NSMutableArray array];
    for (UIBarButtonItem *i in self.rightBarButtonItems) {
        [bits addObject:[NSString stringWithFormat:@"<%@ tag=%ld label=%@ sysItem=%@>",
            NSStringFromClass([i class]), (long)i.tag,
            i.accessibilityLabel ?: (i.title ?: @"-"),
            i.image ? @"img" : @"none"]];
    }
    return bits.count ? [bits componentsJoinedByString:@" "] : @"(empty)";
}

%new
- (void)wamfReinjectFromSetter:(NSString *)which {
    if (gWAMFReinjecting) return;
    if (![self wamfIsOwned]) return;
    if (![WAMFilterStore filterButtonEnabled]) return;
    if ([self wamfHasFilterItem]) return;

    gWAMFReinjecting = YES;
    gWAMFReinjectCount++;

    WAMLog(@"nav", @"reinject #%lu after %@ -- items were: %@",
            (unsigned long)gWAMFReinjectCount, which, [self wamfDescribeRightItems]);

    WAMFilter active = [WAMFilterStore activeFilter];
    UIMenu *menu = objc_getAssociatedObject(self, @selector(wamfReinjectFromSetter:));
    UIBarButtonItem *filter = wamfMakeFilterItem(menu, active);

    NSMutableArray *items = [(self.rightBarButtonItems ?: @[]) mutableCopy];
    [items addObject:filter];
    self.rightBarButtonItems = items;

    WAMLog(@"nav", @"reinject #%lu done -- items now: %@",
            (unsigned long)gWAMFReinjectCount, [self wamfDescribeRightItems]);

    gWAMFReinjecting = NO;
}

- (void)setRightBarButtonItems:(NSArray<UIBarButtonItem *> *)items animated:(BOOL)animated {
    %orig;
    [self wamfReinjectFromSetter:@"setRightBarButtonItems:animated:"];
}

- (void)setRightBarButtonItems:(NSArray<UIBarButtonItem *> *)items {
    %orig;
    [self wamfReinjectFromSetter:@"setRightBarButtonItems:"];
}

- (void)setRightBarButtonItem:(UIBarButtonItem *)item animated:(BOOL)animated {
    %orig;
    [self wamfReinjectFromSetter:@"setRightBarButtonItem:animated:"];
}

- (void)setRightBarButtonItem:(UIBarButtonItem *)item {
    %orig;
    [self wamfReinjectFromSetter:@"setRightBarButtonItem:"];
}

%end

#pragma mark - Darwin bridge

static void wamfFilterChangedCallback(CFNotificationCenterRef center, void *observer,
                                      CFStringRef name, const void *object,
                                      CFDictionaryRef userInfo) {
    WAMLogInvalidateCache();
    dispatch_async(dispatch_get_main_queue(), ^{
        WAMLog(@"darwin", @"notification received, rebroadcasting in-process");
        [[NSNotificationCenter defaultCenter] postNotificationName:@"WAMFilterChangedInProcess"
                                                           object:nil];
    });
}

static void wamfEnsureDarwinObservers(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        WAMLog(@"life", @"registering darwin observers; logging to %@", [WAMDebugLog path]);
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            (CFNotificationCallback)wamfFilterChangedCallback,
            CFSTR(kWAMFilterChangedName), NULL,
            CFNotificationSuspensionBehaviorCoalesce);

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            (CFNotificationCallback)wamfFilterChangedCallback,
            CFSTR("com.oakstheawesome.whatamessprefs/prefsChanged"), NULL,
            CFNotificationSuspensionBehaviorCoalesce);
    });
}

#pragma mark - Cell

%hook CKConversationListCollectionViewConversationCell

%new
- (NSString *)wamfExtractTitle {
    UILabel *l = wamfTitleLabel(self);
    NSString *t = [l.text stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return t.length ? t : nil;
}

%new
- (NSString *)wamfExtractPreview {
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    wamfCollectLabels(self, labels, 0);
    UILabel *title = wamfTitleLabel(self);

    NSString *best = nil;
    CGFloat cellWidth = self.bounds.size.width;

    for (UILabel *l in labels) {
        if (l == title) continue;
        CGRect f = [l convertRect:l.bounds toView:self];
        if (cellWidth > 1 && CGRectGetMaxX(f) > cellWidth * 0.86) continue;
        NSString *t = l.text;
        if (t.length > best.length) best = t;
    }
    return best;
}

%new
- (void)wamfApplyFilterVisibility {
    WAMFilter active = [WAMFilterStore activeFilter];

    NSString *title = [self wamfExtractTitle];
    if (title.length) {
        objc_setAssociatedObject(self, kWAMFTitleKey, title, OBJC_ASSOCIATION_COPY_NONATOMIC);
        [WAMFilterStore recordSenderTitle:title preview:[self wamfExtractPreview]];
    } else {
        title = objc_getAssociatedObject(self, kWAMFTitleKey);
    }

    if (active == WAMFilterAllMessages || ![WAMFilterStore filterButtonEnabled]) {
        if (self.hidden) {
            self.hidden = NO;
            self.userInteractionEnabled = YES;
        }
        return;
    }

    BOOL show = title.length ? [WAMFilterStore shouldShowTitle:title underFilter:active] : NO;

    NSNumber *last = objc_getAssociatedObject(self, kWAMFLastShownKey);
    if (!last || last.boolValue != show) {
        objc_setAssociatedObject(self, kWAMFLastShownKey, @(show), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        WAMLog(@"cell", @"%@ title=%@ effective=%@ under=%@",
                show ? @"SHOW" : @"HIDE",
                title ?: @"(none)",
                [WAMFilterStore describeFilter:[WAMFilterStore effectiveFilterForTitle:title]],
                [WAMFilterStore describeFilter:active]);
    }

    if (self.hidden != !show) {
        self.hidden = !show;
        self.userInteractionEnabled = show;
    }
}

- (void)setFrame:(CGRect)frame {
    if (!gWAMFCompacting && frame.size.height > 1) {
        objc_setAssociatedObject(self, kWAMFCanonRectKey,
            [NSValue valueWithCGRect:frame], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    %orig;
}

- (void)layoutSubviews {
    %orig;
    [self wamfApplyFilterVisibility];
}

- (void)prepareForReuse {
    %orig;
    objc_setAssociatedObject(self, kWAMFTitleKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
    self.hidden = NO;
    self.userInteractionEnabled = YES;
}

%end

#pragma mark - Conversation list controller

%hook CKConversationListCollectionViewController

- (void)viewDidLoad {
    %orig;
    wamfEnsureDarwinObservers();
    WAMLog(@"life", @"viewDidLoad %@ navItem=%p filterButtonEnabled=%d activeFilter=%@",
           NSStringFromClass([self class]), self.navigationItem,
           (int)[WAMFilterStore filterButtonEnabled],
           [WAMFilterStore describeFilter:[WAMFilterStore activeFilter]]);
    [self wamfInstallFilterButton];

    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(wamfRefreshForFilterChange)
            name:@"WAMFilterChangedInProcess"
          object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    WAMLog(@"life", @"viewWillAppear navItem=%p hasFilter=%d editing=%d",
            self.navigationItem, (int)[self.navigationItem wamfHasFilterItem], (int)self.isEditing);
    [self wamfInstallFilterButton];
}

- (void)viewDidLayoutSubviews {
    %orig;

    // Safety net: if Messages swapped in a brand new UINavigationItem, the setter
    // hook has nothing marked to reinject into, so re-install from scratch.
    UINavigationItem *nav = self.navigationItem;
    if (nav) {
        BOOL enabled = [WAMFilterStore filterButtonEnabled];
        BOOL present = [nav wamfHasFilterItem];

        // Heartbeat so silence is never ambiguous: if the button is absent we
        // want to know whether it is because prefs disabled it or because
        // something stripped it.
        WAMLogEvery(3.0, @"nav", @"layout state: enabled=%d present=%d owned=%d items=%@",
                    (int)enabled, (int)present, (int)[nav wamfIsOwned],
                    [nav wamfDescribeRightItems]);

        if (enabled && !present) {
            WAMLog(@"nav", @"layout self-heal: button missing (owned=%d) -- reinstalling",
                   (int)[nav wamfIsOwned]);
            [self wamfInstallFilterButton];
        }
    }

    [self wamfCompactFilteredCells];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"WAMFilterChangedInProcess" object:nil];
    %orig;
}

%new
- (void)wamfRefreshForFilterChange {
    WAMLog(@"life", @"refreshForFilterChange filter=%@",
            [WAMFilterStore describeFilter:[WAMFilterStore activeFilter]]);
    [self wamfInstallFilterButton];

    UICollectionView *cv = self.collectionView;
    if (!cv) return;

    gWAMFCompacting = YES;
    for (UIView *v in cv.subviews) {
        if (![v isKindOfClass:%c(CKConversationListCollectionViewConversationCell)]) continue;
        NSValue *canon = objc_getAssociatedObject(v, kWAMFCanonRectKey);
        if (canon) v.frame = [canon CGRectValue];
        v.hidden = NO;
        v.userInteractionEnabled = YES;
    }
    gWAMFCompacting = NO;

    for (UIView *v in cv.subviews) {
        if ([v isKindOfClass:%c(CKConversationListCollectionViewConversationCell)]) {
            [(CKConversationListCollectionViewConversationCell *)v wamfApplyFilterVisibility];
        }
    }

    [self wamfCompactFilteredCells];
    [cv setNeedsLayout];
}

%new
- (void)wamfInstallFilterButton {
    UINavigationItem *item = self.navigationItem;
    if (!item) {
        WAMLog(@"nav", @"install skipped: navigationItem is nil");
        return;
    }

    BOOL enabled = [WAMFilterStore filterButtonEnabled];
    NSString *before = [item wamfDescribeRightItems];
    WAMLog(@"nav", @"install attempt: enabled=%d navItem=%p owned=%d hasItem=%d before=%@",
           (int)enabled, item, (int)[item wamfIsOwned],
           (int)[item wamfHasFilterItem], before);

    NSMutableArray *items = [(item.rightBarButtonItems ?: @[]) mutableCopy];
    NSUInteger removed = 0;
    for (UIBarButtonItem *existing in [items copy]) {
        if (existing.tag == kWAMFilterButtonTag) {
            [items removeObject:existing];
            removed++;
        }
    }

    if (!enabled) {
        gWAMFReinjecting = YES;
        item.rightBarButtonItems = items;
        gWAMFReinjecting = NO;
        objc_setAssociatedObject(item, kWAMFOwnedNavKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        WAMLog(@"nav", @"filter button disabled in prefs; removed %lu, items now: %@",
                (unsigned long)removed, [item wamfDescribeRightItems]);
        return;
    }

    WAMFilter active = [WAMFilterStore activeFilter];
    UIMenu *menu = [self wamfBuildFilterMenu];
    UIBarButtonItem *filter = wamfMakeFilterItem(menu, active);

    // Stash the menu on the nav item so a setter-triggered reinject can rebuild
    // the button without needing the view controller.
    objc_setAssociatedObject(item, @selector(wamfReinjectFromSetter:), menu,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [item wamfMarkOwned];

    // rightBarButtonItems is ordered right-to-left, so appending puts us
    // immediately to the LEFT of the compose button.
    [items addObject:filter];

    gWAMFReinjecting = YES;
    item.rightBarButtonItems = items;
    gWAMFReinjecting = NO;

    gWAMFInstallCount++;
    WAMLog(@"nav", @"install #%lu active=%@ removedStale=%lu\n    before: %@\n    after:  %@",
            (unsigned long)gWAMFInstallCount, [WAMFilterStore describeFilter:active],
            (unsigned long)removed, before, [item wamfDescribeRightItems]);
}

%new
- (UIMenu *)wamfBuildFilterMenu {
    WAMFilter active = [WAMFilterStore activeFilter];

    UIAction * (^make)(WAMFilter) = ^UIAction *(WAMFilter f) {
        NSString *name = [WAMFilterStore nameForFilter:f];
        UIImage *img = [UIImage systemImageNamed:[WAMFilterStore symbolForFilter:f]];
        UIAction *a = [UIAction actionWithTitle:name image:img identifier:nil
                                       handler:^(__kindof UIAction *action) {
            [self wamfSelectFilter:@(f)];
        }];
        a.state = (f == active) ? UIMenuElementStateOn : UIMenuElementStateOff;
        if (f != WAMFilterAllMessages) {
            NSInteger n = [WAMFilterStore countForFilter:f];
            if (n > 0) a.subtitle = [NSString stringWithFormat:@"%ld sender%@", (long)n, n == 1 ? @"" : @"s"];
        }
        return a;
    };

    UIMenu *transactions = [UIMenu menuWithTitle:@"Transactions"
        image:[UIImage systemImageNamed:@"tag"]
        identifier:nil
        options:0
        children:@[ make(WAMFilterTransactions),
                    make(WAMFilterTransactionsOrders),
                    make(WAMFilterTransactionsFinance),
                    make(WAMFilterTransactionsReminders) ]];

    UIAction *recentlyDeleted = [UIAction actionWithTitle:@"Recently Deleted"
        image:[UIImage systemImageNamed:@"trash"]
        identifier:nil
        handler:^(__kindof UIAction *action) {
            [self wamfOpenRecentlyDeleted];
        }];

    UIAction *manage = [UIAction actionWithTitle:@"Manage Filtering"
        image:nil
        identifier:nil
        handler:^(__kindof UIAction *action) {
            [self wamfOpenManageFiltering];
        }];

    UIMenu *manageSection = [UIMenu menuWithTitle:@""
                                            image:nil
                                       identifier:nil
                                          options:UIMenuOptionsDisplayInline
                                         children:@[manage]];

    NSArray *top = @[
        make(WAMFilterAllMessages),
        make(WAMFilterUnknownSenders),
        transactions,
        make(WAMFilterTwoFactor),
        make(WAMFilterPromotions),
        make(WAMFilterSpam),
        recentlyDeleted,
    ];

    UIMenu *topSection = [UIMenu menuWithTitle:@""
                                         image:nil
                                    identifier:nil
                                       options:UIMenuOptionsDisplayInline
                                      children:top];

    return [UIMenu menuWithTitle:@"" children:@[topSection, manageSection]];
}

%new
- (void)wamfSelectFilter:(NSNumber *)boxed {
    WAMLog(@"menu", @"user picked %@",
            [WAMFilterStore describeFilter:(WAMFilter)[boxed integerValue]]);
    [WAMFilterStore setActiveFilter:(WAMFilter)[boxed integerValue]];
    [WAMFilterStore postFilterChanged];
    [self wamfRefreshForFilterChange];
}

%new
- (void)wamfOpenManageFiltering {
    WAMLog(@"ui", @"opening Manage Filtering (roster=%lu)",
            (unsigned long)[WAMFilterStore roster].count);
    UINavigationController *nav = [WAMManageFilteringController wrappedForPresentation];
    WAMManageFilteringController *root = (WAMManageFilteringController *)nav.viewControllers.firstObject;
    root.onChanged = ^{
        [WAMFilterStore postFilterChanged];
    };
    [self presentViewController:nav animated:YES completion:nil];
}

%new
- (void)wamfOpenRecentlyDeleted {
    WAMLog(@"ui", @"Recently Deleted requested");
    NSArray *candidates = @[@"showRecentlyDeleted", @"_showRecentlyDeleted",
                            @"presentRecentlyDeleted", @"showRecentlyDeletedMessages",
                            @"openRecentlyDeleted"];
    for (NSString *name in candidates) {
        SEL sel = NSSelectorFromString(name);
        if ([self respondsToSelector:sel]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            WAMLog(@"ui", @"invoking system selector %@", name);
            [self performSelector:sel];
            #pragma clang diagnostic pop
            return;
        }
    }

    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"Recently Deleted"
                         message:@"This build could not find the system Recently Deleted view on this "
                                  "iOS version. Use Edit in the top left, then Show Recently Deleted."
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

%new
- (void)wamfCompactFilteredCells {
    UICollectionView *cv = self.collectionView;
    if (!cv) return;

    Class cellCls = %c(CKConversationListCollectionViewConversationCell);
    if (!cellCls) return;

    WAMFilter active = [WAMFilterStore activeFilter];
    BOOL filtering = ([WAMFilterStore filterButtonEnabled] && active != WAMFilterAllMessages);

    NSMutableArray<UIView *> *cells = [NSMutableArray array];
    for (UIView *v in cv.subviews) {
        if ([v isKindOfClass:cellCls]) [cells addObject:v];
    }

    UILabel *empty = (UILabel *)[self.view viewWithTag:kWAMEmptyStateTag];

    if (!filtering) {
        if (!gWAMFDidCompact) {
            empty.hidden = YES;
            return;
        }
        gWAMFDidCompact = NO;
        WAMLog(@"compact", @"filter cleared -- restoring %lu canonical frames",
               (unsigned long)cells.count);
        if (cells.count) {
            gWAMFCompacting = YES;
            for (UIView *cell in cells) {
                NSValue *canon = objc_getAssociatedObject(cell, kWAMFCanonRectKey);
                if (canon && !CGRectEqualToRect(cell.frame, [canon CGRectValue])) {
                    cell.frame = [canon CGRectValue];
                }
            }
            gWAMFCompacting = NO;
        }
        empty.hidden = YES;
        return;
    }

    [cells sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        NSValue *va = objc_getAssociatedObject(a, kWAMFCanonRectKey);
        NSValue *vb = objc_getAssociatedObject(b, kWAMFCanonRectKey);
        CGFloat ya = va ? [va CGRectValue].origin.y : a.frame.origin.y;
        CGFloat yb = vb ? [vb CGRectValue].origin.y : b.frame.origin.y;
        if (ya < yb) return NSOrderedAscending;
        if (ya > yb) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    CGFloat cursor = CGFLOAT_MAX;
    for (UIView *cell in cells) {
        NSValue *canon = objc_getAssociatedObject(cell, kWAMFCanonRectKey);
        if (!canon) continue;
        cursor = MIN(cursor, [canon CGRectValue].origin.y);
    }
    if (cursor == CGFLOAT_MAX) return;

    NSInteger shown = 0;
    gWAMFDidCompact = YES;
    gWAMFCompacting = YES;
    for (UIView *cell in cells) {
        NSValue *canon = objc_getAssociatedObject(cell, kWAMFCanonRectKey);
        if (!canon) continue;
        CGRect r = [canon CGRectValue];
        if (cell.hidden) continue;
        r.origin.y = cursor;
        if (!CGRectEqualToRect(cell.frame, r)) cell.frame = r;
        cursor += r.size.height;
        shown++;
    }
    gWAMFCompacting = NO;

    static NSInteger prevShown = -1;
    static NSInteger prevTotal = -1;
    if (shown != prevShown || (NSInteger)cells.count != prevTotal) {
        prevShown = shown;
        prevTotal = (NSInteger)cells.count;
        WAMLog(@"compact", @"filter=%@ cells=%lu shown=%ld startY=%.1f",
                [WAMFilterStore describeFilter:active],
                (unsigned long)cells.count, (long)shown, cursor);
    }

    if (shown == 0) {
        if (!empty) {
            empty = [[UILabel alloc] init];
            empty.tag = kWAMEmptyStateTag;
            empty.numberOfLines = 0;
            empty.textAlignment = NSTextAlignmentCenter;
            empty.font = [UIFont systemFontOfSize:15];
            empty.textColor = [UIColor secondaryLabelColor];
            empty.translatesAutoresizingMaskIntoConstraints = NO;
            [self.view addSubview:empty];
            [NSLayoutConstraint activateConstraints:@[
                [empty.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
                [empty.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-40],
                [empty.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:0.72],
            ]];
        }
        empty.text = [NSString stringWithFormat:
            @"Nothing loaded in %@.\n\nScroll the list to load more conversations, or assign senders "
             "to this filter in Manage Filtering.", [WAMFilterStore nameForFilter:active]];
        empty.hidden = NO;
        [self.view bringSubviewToFront:empty];
    } else {
        empty.hidden = YES;
    }
}

%end


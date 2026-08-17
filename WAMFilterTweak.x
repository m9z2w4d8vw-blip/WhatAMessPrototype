#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <stdlib.h>
#import <objc/message.h>
#import "WAMFilterModel.h"
#import "WAMDebugLog.h"
#import "WAMManageFilteringController.h"

#define kWAMFilterButtonTag 0x57414D46

static BOOL gWAMFReinjecting = NO;
static const void *kWAMFTitleKey      = &kWAMFTitleKey;
static const void *kWAMFOwnedNavKey   = &kWAMFOwnedNavKey;

static NSUInteger gWAMFInstallCount = 0;
static NSUInteger gWAMFReinjectCount = 0;

@protocol WAMSnapshot <NSObject>
- (NSArray *)sectionIdentifiers;
- (NSArray *)itemIdentifiersInSectionWithIdentifier:(id)sectionIdentifier;
- (void)deleteItemsWithIdentifiers:(NSArray *)identifiers;
@end

@interface CKConversationListCollectionViewController : UICollectionViewController
- (void)wamfInstallFilterButton;
- (UIMenu *)wamfBuildFilterMenu;
- (void)wamfSelectFilter:(NSNumber *)boxed;
- (void)wamfOpenManageFiltering;
- (void)wamfOpenRecentlyDeleted;
- (void)wamfRefreshForFilterChange;
- (void)wamfDumpRuntimeShape;

// Real API, confirmed by the runtime dump on iOS 17.0
- (id)conversationForItemIdentifier:(id)identifier;
- (NSUInteger)filterMode;
- (id)generateSnapshot;
- (void)applyConversationListSnapshot:(id)snapshot
                 animatingDifferences:(BOOL)animate
                           completion:(void (^)(void))completion;

- (NSString *)wamfNameForConversation:(id)conversation;
- (id)wamfFilterSnapshot:(id)snapshot;
- (void)wamfReapplyFilteredSnapshot;
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
    // Roster recording only. Hiding cells and rewriting their frames does not
    // work: the collection view owns geometry and recycles cells, so anything
    // written here is reverted on the next layout pass. Filtering has to happen
    // at the data source; see wamfDumpRuntimeShape.
    NSString *title = [self wamfExtractTitle];
    if (!title.length) return;

    objc_setAssociatedObject(self, kWAMFTitleKey, title, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [WAMFilterStore recordSenderTitle:title preview:[self wamfExtractPreview]];
}

- (void)layoutSubviews {
    %orig;
    [self wamfApplyFilterVisibility];
}

- (void)prepareForReuse {
    %orig;
    objc_setAssociatedObject(self, kWAMFTitleKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
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

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [self wamfDumpRuntimeShape];
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
    [self wamfReapplyFilteredSnapshot];
}

%new
- (NSString *)wamfNameForConversation:(id)conversation {
    if (!conversation) return nil;
    static NSArray *sels = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sels = @[@"displayName", @"name", @"title", @"roomName",
                 @"effectiveDisplayName", @"primaryRecipientDisplayName"];
    });
    for (NSString *name in sels) {
        SEL sel = NSSelectorFromString(name);
        if (![conversation respondsToSelector:sel]) continue;
        id value = ((id (*)(id, SEL))objc_msgSend)(conversation, sel);
        if ([value isKindOfClass:[NSString class]] && [(NSString *)value length]) {
            return (NSString *)value;
        }
    }
    return nil;
}

%new
- (id)wamfFilterSnapshot:(id)snapshot {
    if (!snapshot) return snapshot;
    if (![WAMFilterStore filterButtonEnabled]) return snapshot;
    if (![self respondsToSelector:@selector(conversationForItemIdentifier:)]) return snapshot;

    // Messages has its own filter modes (recently deleted, junk, unknown
    // senders). When one is active, leave the snapshot completely alone.
    if ([self respondsToSelector:@selector(filterMode)] && [self filterMode] != 0) {
        WAMLogV(@"snap", @"skipped: native filterMode=%lu", (unsigned long)[self filterMode]);
        return snapshot;
    }

    WAMFilter active = [WAMFilterStore activeFilter];
    id<WAMSnapshot> snap = (id<WAMSnapshot>)snapshot;
    if (![snap respondsToSelector:@selector(sectionIdentifiers)]) return snapshot;

    NSMutableArray *drop = [NSMutableArray array];
    NSUInteger total = 0, resolved = 0;

    for (id section in [snap sectionIdentifiers]) {
        for (id item in [snap itemIdentifiersInSectionWithIdentifier:section]) {
            total++;
            id conversation = [self conversationForItemIdentifier:item];
            if (!conversation) continue;

            NSString *name = [self wamfNameForConversation:conversation];
            if (!name.length) continue;
            resolved++;

            // The snapshot is a complete list, so this finally gives us a full
            // roster instead of only the rows that happened to be on screen.
            [WAMFilterStore recordSenderTitle:name preview:nil];

            if (![WAMFilterStore shouldShowTitle:name underFilter:active]) {
                [drop addObject:item];
            }
        }
    }

    if (drop.count) {
        [snap deleteItemsWithIdentifiers:drop];
    }
    WAMLog(@"snap", @"filter=%@ items=%lu resolved=%lu dropped=%lu",
           [WAMFilterStore describeFilter:active],
           (unsigned long)total, (unsigned long)resolved, (unsigned long)drop.count);
    return snapshot;
}

%new
- (void)wamfReapplyFilteredSnapshot {
    if (![self respondsToSelector:@selector(generateSnapshot)]) return;
    if (![self respondsToSelector:@selector(applyConversationListSnapshot:animatingDifferences:completion:)]) return;

    id snapshot = [self generateSnapshot];
    if (!snapshot) return;
    WAMLog(@"snap", @"reapplying for filter=%@",
           [WAMFilterStore describeFilter:[WAMFilterStore activeFilter]]);
    [self applyConversationListSnapshot:snapshot animatingDifferences:YES completion:nil];
}

- (id)generateSnapshot {
    id snapshot = %orig;
    return [self wamfFilterSnapshot:snapshot];
}

- (void)applyConversationListSnapshot:(id)snapshot
                 animatingDifferences:(BOOL)animate
                           completion:(void (^)(void))completion {
    id filtered = [self wamfFilterSnapshot:snapshot];
    %orig(filtered, animate, completion);
}

%new
- (void)wamfDumpRuntimeShape {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        UICollectionView *cv = self.collectionView;

        WAMLog(@"shape", @"controller=%@", NSStringFromClass([self class]));
        WAMLog(@"shape", @"collectionView=%@ dataSource=%@ delegate=%@ layout=%@",
               cv ? NSStringFromClass([cv class]) : @"(nil)",
               cv.dataSource ? NSStringFromClass([cv.dataSource class]) : @"(nil)",
               cv.delegate ? NSStringFromClass([cv.delegate class]) : @"(nil)",
               cv.collectionViewLayout ? NSStringFromClass([cv.collectionViewLayout class]) : @"(nil)");
        WAMLog(@"shape", @"sections=%ld items0=%ld",
               (long)(cv ? [cv numberOfSections] : -1),
               (long)(cv && [cv numberOfSections] > 0 ? [cv numberOfItemsInSection:0] : -1));

        NSArray *needles = @[@"conversation", @"chat", @"datasource", @"snapshot", @"item",
                             @"filter", @"list", @"reload", @"cell", @"unknown", @"pinned"];

        // Every ivar on the controller: this is where the conversation array lives.
        unsigned int ivarCount = 0;
        Ivar *ivars = class_copyIvarList([self class], &ivarCount);
        NSMutableArray *ivarNames = [NSMutableArray array];
        for (unsigned int i = 0; i < ivarCount; i++) {
            const char *nm = ivar_getName(ivars[i]);
            const char *ty = ivar_getTypeEncoding(ivars[i]);
            [ivarNames addObject:[NSString stringWithFormat:@"%s:%s", nm ?: "?", ty ?: "?"]];
        }
        if (ivars) free(ivars);
        WAMLog(@"shape", @"controller ivars (%u): %@",
               ivarCount, [ivarNames componentsJoinedByString:@" "]);

        // Controller methods matching anything conversation-shaped.
        unsigned int mCount = 0;
        Method *methods = class_copyMethodList([self class], &mCount);
        NSMutableArray *hits = [NSMutableArray array];
        for (unsigned int i = 0; i < mCount; i++) {
            NSString *sel = NSStringFromSelector(method_getName(methods[i]));
            NSString *lower = [sel lowercaseString];
            for (NSString *n in needles) {
                if ([lower rangeOfString:n].location != NSNotFound) {
                    [hits addObject:sel];
                    break;
                }
            }
        }
        if (methods) free(methods);
        WAMLog(@"shape", @"controller methods %u total, %lu interesting:",
               mCount, (unsigned long)hits.count);
        for (NSString *sel in hits) {
            WAMLog(@"shape", @"  ctrl -[%@]", sel);
        }

        // If the data source is a separate object (diffable, etc.), dump it too.
        id ds = cv.dataSource;
        if (ds && ds != self) {
            unsigned int dCount = 0;
            Method *dMethods = class_copyMethodList([ds class], &dCount);
            NSMutableArray *dHits = [NSMutableArray array];
            for (unsigned int i = 0; i < dCount; i++) {
                [dHits addObject:NSStringFromSelector(method_getName(dMethods[i]))];
            }
            if (dMethods) free(dMethods);
            WAMLog(@"shape", @"dataSource %@ methods (%u): %@",
                   NSStringFromClass([ds class]), dCount,
                   [dHits componentsJoinedByString:@" "]);

            unsigned int dIvarCount = 0;
            Ivar *dIvars = class_copyIvarList([ds class], &dIvarCount);
            NSMutableArray *dIvarNames = [NSMutableArray array];
            for (unsigned int i = 0; i < dIvarCount; i++) {
                [dIvarNames addObject:@(ivar_getName(dIvars[i]) ?: "?")];
            }
            if (dIvars) free(dIvars);
            WAMLog(@"shape", @"dataSource ivars (%u): %@",
                   dIvarCount, [dIvarNames componentsJoinedByString:@" "]);
        }

        WAMLog(@"shape", @"---- end runtime shape ----");
    });
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
    WAMFilter picked = (WAMFilter)[boxed integerValue];
    WAMLog(@"menu", @"user picked %@", [WAMFilterStore describeFilter:picked]);

    [WAMFilterStore setActiveFilter:picked];
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

%end


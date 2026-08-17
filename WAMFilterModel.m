#import "WAMFilterModel.h"
#import "WAMDebugLog.h"
#import <stdlib.h>
#import <sys/syslimits.h>

static NSString *WAMFJBRoot(void) {
    static NSString *root = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        char buf[PATH_MAX];
        root = realpath("/var/jb", buf) ? [NSString stringWithUTF8String:buf] : @"";
    });
    return root;
}

static NSString *WAMFPrefsPath(void) {
    return [WAMFJBRoot() stringByAppendingString:
        @"/var/mobile/Library/Preferences/com.oakstheawesome.whatamessprefs.plist"];
}

// These are read from -layoutSubviews of every conversation cell, so hitting
// the plist each time meant dozens of synchronous disk reads per second while
// scrolling. Cache in memory and invalidate explicitly.
static NSMutableDictionary *gPrefsCache = nil;

void WAMFilterInvalidatePrefsCache(void) {
    gPrefsCache = nil;
}

static NSMutableDictionary *WAMFRead(void) {
    if (!gPrefsCache) {
        NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:WAMFPrefsPath()];
        if (!d.count) {
            d = [NSMutableDictionary dictionaryWithContentsOfFile:
                 @"/var/mobile/Library/Preferences/com.oakstheawesome.whatamessprefs.plist"];
        }
        gPrefsCache = d ?: [NSMutableDictionary new];
    }
    return gPrefsCache;
}

static void WAMFWrite(NSDictionary *prefs) {
    if (prefs != gPrefsCache) gPrefsCache = [prefs mutableCopy];
    NSString *path = WAMFPrefsPath();
    NSString *dir = [path stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                             withIntermediateDirectories:YES attributes:nil error:nil];
    [prefs writeToFile:path atomically:YES];
}

static BOOL gRosterDirty = NO;
static NSString *const kAssignmentsKey = @"filterAssignments";
static NSString *const kRosterKey      = @"filterRoster";
static NSString *const kActiveKey      = @"filterActiveSelection";
static NSString *const kEnabledKey     = @"isFilterButtonEnabled";

@implementation WAMFilterStore

#pragma mark - Toggle

+ (BOOL)filterButtonEnabled {
    id v = WAMFRead()[kEnabledKey];
    return v ? [v boolValue] : YES;
}

#pragma mark - Active selection

+ (WAMFilter)activeFilter {
    id v = WAMFRead()[kActiveKey];
    WAMFilter f = v ? (WAMFilter)[v integerValue] : WAMFilterAllMessages;
    if (f == WAMFilterRecentlyDeleted || f == WAMFilterUnassigned) return WAMFilterAllMessages;
    return f;
}

+ (void)setActiveFilter:(WAMFilter)filter {
    WAMLog(@"store", @"setActiveFilter %@ (was %@)",
            [self describeFilter:filter], [self describeFilter:[self activeFilter]]);
    NSMutableDictionary *p = WAMFRead();
    p[kActiveKey] = @(filter);
    WAMFWrite(p);
}

#pragma mark - Keying

+ (NSString *)keyForTitle:(NSString *)title {
    NSString *raw = [title stringByTrimmingCharactersInSet:
                     [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!raw.length) return nil;

    NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
    BOOL hasLetter = ([raw rangeOfCharacterFromSet:letters].location != NSNotFound);

    if (!hasLetter) {
        NSMutableString *digits = [NSMutableString string];
        for (NSUInteger i = 0; i < raw.length; i++) {
            unichar c = [raw characterAtIndex:i];
            if (c >= '0' && c <= '9') [digits appendFormat:@"%C", c];
        }
        if (digits.length > 10) {
            digits = [[digits substringFromIndex:digits.length - 10] mutableCopy];
        }
        if (digits.length) return [@"n:" stringByAppendingString:digits];
    }

    NSString *lower = [raw lowercaseString];
    NSMutableString *clean = [NSMutableString string];
    for (NSUInteger i = 0; i < lower.length; i++) {
        unichar c = [lower characterAtIndex:i];
        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) [clean appendFormat:@"%C", c];
    }
    if (!clean.length) return nil;
    return [@"c:" stringByAppendingString:clean];
}

#pragma mark - Assignments

+ (WAMFilter)assignedFilterForTitle:(NSString *)title {
    NSString *k = [self keyForTitle:title];
    if (!k) return WAMFilterUnassigned;
    NSDictionary *map = WAMFRead()[kAssignmentsKey];
    if (![map isKindOfClass:[NSDictionary class]]) return WAMFilterUnassigned;
    id v = map[k];
    return v ? (WAMFilter)[v integerValue] : WAMFilterUnassigned;
}

+ (void)setAssignedFilter:(WAMFilter)filter forTitle:(NSString *)title {
    NSString *k = [self keyForTitle:title];
    WAMLog(@"store", @"setAssignedFilter %@ for title=%@ key=%@",
            [self describeFilter:filter], title, k ?: @"(nil)");
    if (!k) return;
    NSMutableDictionary *p = WAMFRead();
    NSMutableDictionary *map = [(NSDictionary *)p[kAssignmentsKey] mutableCopy] ?: [NSMutableDictionary new];
    if (filter == WAMFilterUnassigned) {
        [map removeObjectForKey:k];
    } else {
        map[k] = @(filter);
    }
    p[kAssignmentsKey] = map;
    WAMFWrite(p);
}

#pragma mark - Heuristics

+ (WAMFilter)detectedFilterForTitle:(NSString *)title preview:(NSString *)preview {
    NSString *raw = [title stringByTrimmingCharactersInSet:
                     [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!raw.length) return WAMFilterUnassigned;

    BOOL hasLetter = ([raw rangeOfCharacterFromSet:[NSCharacterSet letterCharacterSet]].location != NSNotFound);
    if (hasLetter) return WAMFilterUnassigned;

    NSMutableString *digits = [NSMutableString string];
    for (NSUInteger i = 0; i < raw.length; i++) {
        unichar c = [raw characterAtIndex:i];
        if (c >= '0' && c <= '9') [digits appendFormat:@"%C", c];
    }

    BOOL shortCode = (digits.length >= 3 && digits.length <= 8);

    if (shortCode && preview.length) {
        NSString *lower = [preview lowercaseString];
        NSArray *needles = @[@"code", @"passcode", @"passcodes", @"verification", @"verify",
                             @"one-time", @"one time", @"otp", @"2fa", @"authenticat",
                             @"security code", @"login", @"log in", @"sign-in", @"sign in"];
        for (NSString *n in needles) {
            if ([lower rangeOfString:n].location != NSNotFound) return WAMFilterTwoFactor;
        }
        NSRegularExpression *re = [NSRegularExpression
            regularExpressionWithPattern:@"(^|[^0-9])[0-9]{4,8}([^0-9]|$)"
                                 options:0 error:nil];
        if ([re numberOfMatchesInString:preview options:0 range:NSMakeRange(0, preview.length)] > 0) {
            return WAMFilterTwoFactor;
        }
    }

    return WAMFilterUnknownSenders;
}

+ (WAMFilter)effectiveFilterForTitle:(NSString *)title {
    WAMFilter assigned = [self assignedFilterForTitle:title];
    if (assigned != WAMFilterUnassigned) return assigned;

    NSString *k = [self keyForTitle:title];
    NSString *preview = nil;
    if (k) {
        NSDictionary *roster = WAMFRead()[kRosterKey];
        if ([roster isKindOfClass:[NSDictionary class]]) {
            NSDictionary *e = roster[k];
            if ([e isKindOfClass:[NSDictionary class]]) preview = e[@"preview"];
        }
    }
    return [self detectedFilterForTitle:title preview:preview];
}

#pragma mark - Matching

+ (BOOL)filter:(WAMFilter)active matchesEffective:(WAMFilter)effective {
    if (active == WAMFilterAllMessages) return YES;

    // Inbox: real conversations only. Everything the classifier or the user has
    // marked as transactional, 2FA, promotional or spam is excluded.
    if (active == WAMFilterInbox) {
        switch (effective) {
            case WAMFilterTwoFactor:
            case WAMFilterTransactions:
            case WAMFilterTransactionsOrders:
            case WAMFilterTransactionsFinance:
            case WAMFilterTransactionsReminders:
            case WAMFilterPromotions:
            case WAMFilterSpam:
                return NO;
            default:
                return YES;
        }
    }

    if (active == WAMFilterTransactions) {
        return (effective == WAMFilterTransactions ||
                effective == WAMFilterTransactionsOrders ||
                effective == WAMFilterTransactionsFinance ||
                effective == WAMFilterTransactionsReminders);
    }

    return (active == effective);
}

+ (BOOL)shouldShowTitle:(NSString *)title underFilter:(WAMFilter)active {
    if (active == WAMFilterAllMessages) return YES;
    return [self filter:active matchesEffective:[self effectiveFilterForTitle:title]];
}

#pragma mark - Roster

+ (void)flushPendingRoster {
    if (!gRosterDirty) return;
    gRosterDirty = NO;
    WAMLog(@"store", @"flushing roster to disk");
    WAMFWrite(WAMFRead());
}

+ (void)recordSenderTitle:(NSString *)title preview:(NSString *)preview {
    NSString *k = [self keyForTitle:title];
    if (!k) return;

    NSMutableDictionary *p = WAMFRead();
    NSMutableDictionary *roster = [(NSDictionary *)p[kRosterKey] mutableCopy] ?: [NSMutableDictionary new];
    NSDictionary *existing = roster[k];

    NSString *newPreview = preview.length ? preview : (existing[@"preview"] ?: @"");
    if (newPreview.length > 140) newPreview = [newPreview substringToIndex:140];

    if ([existing isKindOfClass:[NSDictionary class]] &&
        [existing[@"title"] isEqualToString:title] &&
        [existing[@"preview"] isEqualToString:newPreview]) {
        return;
    }

    WAMLogV(@"store", @"roster record key=%@ title=%@", k, title);

    roster[k] = @{
        @"title":   title ?: @"",
        @"preview": newPreview,
        @"seen":    @([NSDate timeIntervalSinceReferenceDate]),
    };
    p[kRosterKey] = roster;

    // Coalesce: a scroll touches many cells, and each disk write on the main
    // thread is what made the list stutter.
    gRosterDirty = YES;
    static BOOL scheduled = NO;
    if (!scheduled) {
        scheduled = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            scheduled = NO;
            [WAMFilterStore flushPendingRoster];
        });
    }
}

+ (NSArray<NSDictionary *> *)roster {
    NSDictionary *roster = WAMFRead()[kRosterKey];
    if (![roster isKindOfClass:[NSDictionary class]]) return @[];

    NSMutableArray *out = [NSMutableArray array];
    for (NSString *k in roster) {
        NSDictionary *e = roster[k];
        if (![e isKindOfClass:[NSDictionary class]]) continue;
        NSString *title = e[@"title"];
        if (![title isKindOfClass:[NSString class]] || !title.length) continue;
        [out addObject:@{
            @"key":     k,
            @"title":   title,
            @"preview": e[@"preview"] ?: @"",
            @"seen":    e[@"seen"] ?: @0,
        }];
    }

    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"seen"] compare:a[@"seen"]];
    }];
    return out;
}

+ (NSInteger)countForFilter:(WAMFilter)filter {
    if (filter == WAMFilterAllMessages) return 0;
    NSInteger n = 0;
    for (NSDictionary *e in [self roster]) {
        if ([self filter:filter matchesEffective:[self effectiveFilterForTitle:e[@"title"]]]) n++;
    }
    return n;
}

+ (void)removeRosterEntryForTitle:(NSString *)title {
    NSString *k = [self keyForTitle:title];
    if (!k) return;
    NSMutableDictionary *p = WAMFRead();
    NSMutableDictionary *roster = [(NSDictionary *)p[kRosterKey] mutableCopy] ?: [NSMutableDictionary new];
    NSMutableDictionary *map = [(NSDictionary *)p[kAssignmentsKey] mutableCopy] ?: [NSMutableDictionary new];
    [roster removeObjectForKey:k];
    [map removeObjectForKey:k];
    p[kRosterKey] = roster;
    p[kAssignmentsKey] = map;
    WAMFWrite(p);
}

#pragma mark - Presentation

+ (NSString *)nameForFilter:(WAMFilter)filter {
    switch (filter) {
        case WAMFilterAllMessages:           return @"Messages";
        case WAMFilterInbox:                 return @"Inbox";
        case WAMFilterUnknownSenders:        return @"Unknown Senders";
        case WAMFilterTwoFactor:             return @"2FA";
        case WAMFilterTransactions:          return @"Transactions";
        case WAMFilterTransactionsOrders:    return @"Orders";
        case WAMFilterTransactionsFinance:   return @"Finance";
        case WAMFilterTransactionsReminders: return @"Reminders";
        case WAMFilterPromotions:            return @"Promotions";
        case WAMFilterSpam:                  return @"Spam";
        case WAMFilterRecentlyDeleted:       return @"Recently Deleted";
        case WAMFilterUnassigned:            return @"None";
    }
    return @"None";
}

+ (NSString *)symbolForFilter:(WAMFilter)filter {
    switch (filter) {
        case WAMFilterAllMessages:           return @"message";
        case WAMFilterInbox:                 return @"tray";
        case WAMFilterUnknownSenders:        return @"person.crop.circle.badge.questionmark";
        case WAMFilterTwoFactor:             return @"lock.shield";
        case WAMFilterTransactions:          return @"tag";
        case WAMFilterTransactionsOrders:    return @"shippingbox";
        case WAMFilterTransactionsFinance:   return @"creditcard";
        case WAMFilterTransactionsReminders: return @"bell";
        case WAMFilterPromotions:            return @"megaphone";
        case WAMFilterSpam:                  return @"xmark.bin";
        case WAMFilterRecentlyDeleted:       return @"trash";
        case WAMFilterUnassigned:            return @"circle.dashed";
    }
    return @"circle.dashed";
}

+ (NSArray<NSNumber *> *)assignableFilters {
    return @[
        @(WAMFilterUnassigned),
        @(WAMFilterUnknownSenders),
        @(WAMFilterTwoFactor),
        @(WAMFilterTransactionsOrders),
        @(WAMFilterTransactionsFinance),
        @(WAMFilterTransactionsReminders),
        @(WAMFilterTransactions),
        @(WAMFilterPromotions),
        @(WAMFilterSpam),
    ];
}

+ (NSString *)describeFilter:(WAMFilter)filter {
    return [NSString stringWithFormat:@"%@(%ld)", [self nameForFilter:filter], (long)filter];
}

+ (void)postFilterChanged {
    WAMLog(@"store", @"posting filterChanged darwin notification");
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR(kWAMFilterChangedName), NULL, NULL, YES);
}

@end

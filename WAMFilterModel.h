#import <UIKit/UIKit.h>
#import "WAMDebugLog.h"

#define kWAMFilterChangedName "com.oakstheawesome.whatamessprefs/filterChanged"

typedef NS_ENUM(NSInteger, WAMFilter) {
    WAMFilterAllMessages             = 0,
    WAMFilterInbox                   = 10,
    WAMFilterUnknownSenders          = 1,
    WAMFilterTwoFactor               = 2,
    WAMFilterTransactions            = 3,
    WAMFilterTransactionsOrders      = 4,
    WAMFilterTransactionsFinance     = 5,
    WAMFilterTransactionsReminders   = 6,
    WAMFilterPromotions              = 7,
    WAMFilterSpam                    = 8,
    WAMFilterRecentlyDeleted         = 9,
    WAMFilterUnassigned              = 100,
};

void WAMFilterInvalidatePrefsCache(void);

@interface WAMFilterStore : NSObject

+ (BOOL)filterButtonEnabled;

+ (WAMFilter)activeFilter;
+ (void)setActiveFilter:(WAMFilter)filter;

+ (NSString *)keyForTitle:(NSString *)title;

+ (WAMFilter)assignedFilterForTitle:(NSString *)title;
+ (void)setAssignedFilter:(WAMFilter)filter forTitle:(NSString *)title;

+ (WAMFilter)detectedFilterForTitle:(NSString *)title preview:(NSString *)preview;
+ (WAMFilter)effectiveFilterForTitle:(NSString *)title;

+ (BOOL)filter:(WAMFilter)active matchesEffective:(WAMFilter)effective;
+ (BOOL)shouldShowTitle:(NSString *)title underFilter:(WAMFilter)active;

+ (void)recordSenderTitle:(NSString *)title preview:(NSString *)preview;
+ (void)flushPendingRoster;
+ (NSArray<NSDictionary *> *)roster;
+ (NSInteger)countForFilter:(WAMFilter)filter;
+ (void)removeRosterEntryForTitle:(NSString *)title;

+ (NSString *)nameForFilter:(WAMFilter)filter;
+ (NSString *)symbolForFilter:(WAMFilter)filter;
+ (NSArray<NSNumber *> *)assignableFilters;

+ (void)postFilterChanged;

+ (NSString *)describeFilter:(WAMFilter)filter;

@end

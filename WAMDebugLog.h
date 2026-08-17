#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, WAMLogLevel) {
    WAMLogLevelOff      = 0,
    WAMLogLevelNormal   = 1,  // lifecycle, prefs, decisions, first call of each hook, periodic counters
    WAMLogLevelVerbose  = 2,  // + per-call detail for the interesting paths
    WAMLogLevelFirehose = 3,  // + every call of every hooked method
};

// One of these exists per instrumented callsite, created lazily by WAMTrace.
typedef struct WAMTraceSite {
    const char *name;
    unsigned long total;
    unsigned long sinceFlush;
    struct WAMTraceSite *next;
    int registered;
} WAMTraceSite;

WAMLogLevel WAMLogLevelCurrent(void);
void WAMLogInvalidateCache(void);
void WAMLogWrite(NSString *category, NSString *message);
void WAMLogTraceSite(WAMTraceSite *site);

#define WAMLog(cat, fmt, ...) \
    do { \
        if (WAMLogLevelCurrent() >= WAMLogLevelNormal) { \
            WAMLogWrite((cat), [NSString stringWithFormat:(fmt), ##__VA_ARGS__]); \
        } \
    } while (0)

#define WAMLogV(cat, fmt, ...) \
    do { \
        if (WAMLogLevelCurrent() >= WAMLogLevelVerbose) { \
            WAMLogWrite((cat), [NSString stringWithFormat:(fmt), ##__VA_ARGS__]); \
        } \
    } while (0)

#define WAMTrace(nm) \
    do { \
        static WAMTraceSite _wamSite = { (nm), 0, 0, NULL, 0 }; \
        WAMLogTraceSite(&_wamSite); \
    } while (0)

// Throttled: emits at most once every `secs` per callsite. For state that is
// useful to see periodically but sits on a layout or per-frame path.
#define WAMLogEvery(secs, cat, fmt, ...) \
    do { \
        if (WAMLogLevelCurrent() >= WAMLogLevelNormal) { \
            static NSTimeInterval _wamLast = 0; \
            NSTimeInterval _wamNow = [NSDate timeIntervalSinceReferenceDate]; \
            if (_wamNow - _wamLast >= (secs)) { \
                _wamLast = _wamNow; \
                WAMLogWrite((cat), [NSString stringWithFormat:(fmt), ##__VA_ARGS__]); \
            } \
        } \
    } while (0)

@interface WAMDebugLog : NSObject

+ (NSString *)path;
+ (NSString *)rotatedPath;
+ (NSString *)contents;
+ (unsigned long long)byteSize;
+ (NSInteger)lineCount;
+ (void)clear;

+ (WAMLogLevel)level;
+ (void)setLevel:(WAMLogLevel)level;
+ (NSString *)nameForLevel:(WAMLogLevel)level;

+ (NSString *)hookSummary;
+ (NSInteger)tracedSiteCount;
+ (void)logEnvironment;

@end

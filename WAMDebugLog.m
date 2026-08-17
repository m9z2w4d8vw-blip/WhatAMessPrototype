#import "WAMDebugLog.h"
#import <UIKit/UIKit.h>
#import <os/lock.h>
#import <stdlib.h>
#import <sys/syslimits.h>

#pragma mark - Paths (self-contained: this file must not depend on the rest of the tweak)

static NSString *WAMDLJBRoot(void) {
    static NSString *root = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        char buf[PATH_MAX];
        root = realpath("/var/jb", buf) ? [NSString stringWithUTF8String:buf] : @"";
    });
    return root;
}

static NSString *WAMDLDataDir(void) {
    return [WAMDLJBRoot() stringByAppendingString:
        @"/var/mobile/Library/Preferences/com.oakstheawesome.whatamessprefs"];
}

static NSString *WAMDLPrefsPath(void) {
    return [WAMDLDataDir() stringByAppendingString:@".plist"];
}

static NSString *WAMDLLogPath(void) {
    return [WAMDLDataDir() stringByAppendingPathComponent:@"whatamess_debug.log"];
}

static NSMutableDictionary *WAMDLReadPrefs(void) {
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:WAMDLPrefsPath()];
    if (!d.count) {
        d = [NSMutableDictionary dictionaryWithContentsOfFile:
             @"/var/mobile/Library/Preferences/com.oakstheawesome.whatamessprefs.plist"];
    }
    return d ?: [NSMutableDictionary new];
}

static NSString *const kLevelKey = @"wamDebugLogLevel";
static const unsigned long long kMaxBytes = 2 * 1024 * 1024;

#pragma mark - Level, cached so the hot paths stay cheap

static WAMLogLevel gLevel = WAMLogLevelNormal;
static NSTimeInterval gLevelCheckedAt = 0;

void WAMLogInvalidateCache(void) {
    gLevelCheckedAt = 0;
}

WAMLogLevel WAMLogLevelCurrent(void) {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - gLevelCheckedAt > 2.0) {
        gLevelCheckedAt = now;
        id v = WAMDLReadPrefs()[kLevelKey];
        gLevel = v ? (WAMLogLevel)[v integerValue] : WAMLogLevelNormal;
        if (gLevel < WAMLogLevelOff) gLevel = WAMLogLevelOff;
        if (gLevel > WAMLogLevelFirehose) gLevel = WAMLogLevelFirehose;
    }
    return gLevel;
}

#pragma mark - Writing

static dispatch_queue_t WAMDLQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("com.oakstheawesome.whatamess.log", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

void WAMLogWrite(NSString *category, NSString *message) {
    if (!message) return;

    static NSDateFormatter *fmt = nil;
    static NSString *proc = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [NSDateFormatter new];
        fmt.dateFormat = @"HH:mm:ss.SSS";
        proc = [NSProcessInfo processInfo].processName ?: @"?";
    });

    NSString *line = [NSString stringWithFormat:@"%@ %@ [%@] %@\n",
                      [fmt stringFromDate:[NSDate date]], proc, category ?: @"-", message];

    NSLog(@"[WhatAMess][%@] %@", category ?: @"-", message);

    dispatch_async(WAMDLQueue(), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *path = WAMDLLogPath();
        [fm createDirectoryAtPath:[path stringByDeletingLastPathComponent]
      withIntermediateDirectories:YES attributes:nil error:nil];

        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
        if (attrs && [attrs fileSize] > kMaxBytes) {
            NSString *rotated = [path stringByAppendingString:@".1"];
            [fm removeItemAtPath:rotated error:nil];
            [fm moveItemAtPath:path toPath:rotated error:nil];
        }
        if (![fm fileExistsAtPath:path]) {
            [[NSData data] writeToFile:path atomically:YES];
        }

        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) return;
        @try {
            [fh seekToEndOfFile];
            [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        } @catch (NSException *e) {
        } @finally {
            [fh closeFile];
        }
    });
}

#pragma mark - Trace sites

static os_unfair_lock gSiteLock = OS_UNFAIR_LOCK_INIT;
static WAMTraceSite *gSiteHead = NULL;
static NSInteger gSiteCount = 0;
static NSTimeInterval gLastFlush = 0;

static void WAMDLFlushCountersLocked(void) {
    NSMutableArray *bits = [NSMutableArray array];
    for (WAMTraceSite *s = gSiteHead; s; s = s->next) {
        if (s->sinceFlush == 0) continue;
        [bits addObject:[NSString stringWithFormat:@"%s=%lu", s->name, s->sinceFlush]];
        s->sinceFlush = 0;
    }
    if (!bits.count) return;

    // Busiest first, so a truncated line still says something useful.
    [bits sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSInteger ia = [[a componentsSeparatedByString:@"="].lastObject integerValue];
        NSInteger ib = [[b componentsSeparatedByString:@"="].lastObject integerValue];
        if (ia > ib) return NSOrderedAscending;
        if (ia < ib) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    NSArray *head = bits.count > 40 ? [bits subarrayWithRange:NSMakeRange(0, 40)] : bits;
    WAMLogWrite(@"hooks", [NSString stringWithFormat:@"%lu active in last window: %@%@",
        (unsigned long)bits.count, [head componentsJoinedByString:@" "],
        bits.count > 40 ? @" ..." : @""]);
}

void WAMLogTraceSite(WAMTraceSite *site) {
    WAMLogLevel level = WAMLogLevelCurrent();
    if (level == WAMLogLevelOff || !site) return;

    site->total++;
    site->sinceFlush++;

    if (!site->registered) {
        os_unfair_lock_lock(&gSiteLock);
        if (!site->registered) {
            site->registered = 1;
            site->next = gSiteHead;
            gSiteHead = site;
            gSiteCount++;
            os_unfair_lock_unlock(&gSiteLock);
            WAMLogWrite(@"trace", [NSString stringWithFormat:@"first call: %s", site->name]);
        } else {
            os_unfair_lock_unlock(&gSiteLock);
        }
    }

    if (level >= WAMLogLevelFirehose) {
        WAMLogWrite(@"call", [NSString stringWithFormat:@"%s #%lu", site->name, site->total]);
    }

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - gLastFlush > 5.0) {
        if (os_unfair_lock_trylock(&gSiteLock)) {
            if (now - gLastFlush > 5.0) {
                gLastFlush = now;
                WAMDLFlushCountersLocked();
            }
            os_unfair_lock_unlock(&gSiteLock);
        }
    }
}

#pragma mark - Public surface

@implementation WAMDebugLog

+ (NSString *)path { return WAMDLLogPath(); }
+ (NSString *)rotatedPath { return [WAMDLLogPath() stringByAppendingString:@".1"]; }

+ (NSString *)contents {
    NSString *s = [NSString stringWithContentsOfFile:WAMDLLogPath()
                                            encoding:NSUTF8StringEncoding error:nil];
    return s ?: @"";
}

+ (unsigned long long)byteSize {
    NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:WAMDLLogPath() error:nil];
    return a ? [a fileSize] : 0;
}

+ (NSInteger)lineCount {
    NSString *s = [self contents];
    if (!s.length) return 0;
    return [[s componentsSeparatedByString:@"\n"] count] - 1;
}

+ (void)clear {
    [[NSFileManager defaultManager] removeItemAtPath:WAMDLLogPath() error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:[self rotatedPath] error:nil];
}

+ (WAMLogLevel)level {
    id v = WAMDLReadPrefs()[kLevelKey];
    return v ? (WAMLogLevel)[v integerValue] : WAMLogLevelNormal;
}

+ (void)setLevel:(WAMLogLevel)level {
    NSMutableDictionary *p = WAMDLReadPrefs();
    p[kLevelKey] = @(level);
    NSString *dir = [WAMDLPrefsPath() stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                             withIntermediateDirectories:YES attributes:nil error:nil];
    [p writeToFile:WAMDLPrefsPath() atomically:YES];
    WAMLogInvalidateCache();
}

+ (NSString *)nameForLevel:(WAMLogLevel)level {
    switch (level) {
        case WAMLogLevelOff:      return @"Off";
        case WAMLogLevelNormal:   return @"Normal";
        case WAMLogLevelVerbose:  return @"Verbose";
        case WAMLogLevelFirehose: return @"Firehose";
    }
    return @"Normal";
}

+ (NSInteger)tracedSiteCount {
    os_unfair_lock_lock(&gSiteLock);
    NSInteger n = gSiteCount;
    os_unfair_lock_unlock(&gSiteLock);
    return n;
}

+ (NSString *)hookSummary {
    NSMutableArray *rows = [NSMutableArray array];
    os_unfair_lock_lock(&gSiteLock);
    for (WAMTraceSite *s = gSiteHead; s; s = s->next) {
        [rows addObject:[NSString stringWithFormat:@"%8lu  %s", s->total, s->name]];
    }
    os_unfair_lock_unlock(&gSiteLock);

    if (!rows.count) return @"No instrumented hook has fired in this process yet.";
    [rows sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [b compare:a options:NSNumericSearch];
    }];
    return [NSString stringWithFormat:@"%lu hooks fired\n\n%@",
            (unsigned long)rows.count, [rows componentsJoinedByString:@"\n"]];
}

+ (void)logEnvironment {
    NSProcessInfo *pi = [NSProcessInfo processInfo];
    WAMLogWrite(@"env", [NSString stringWithFormat:
        @"WhatAMess filter prototype loaded | process=%@ pid=%d ios=%@ jbroot=%@ level=%@",
        pi.processName, (int)pi.processIdentifier,
        [[UIDevice currentDevice] systemVersion],
        WAMDLJBRoot().length ? WAMDLJBRoot() : @"(rootful)",
        [self nameForLevel:[self level]]]);
    WAMLogWrite(@"env", [NSString stringWithFormat:@"log file: %@", WAMDLLogPath()]);
}

@end

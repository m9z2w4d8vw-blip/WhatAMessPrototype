#import "WAMDebugLog.h"
#import <UIKit/UIKit.h>
#import <os/lock.h>
#import <fcntl.h>
#import <unistd.h>
#import <sys/stat.h>
#import <sys/time.h>
#import <time.h>
#import <string.h>
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

static NSString *WAMDLCallLogPath(void) {
    return [WAMDLDataDir() stringByAppendingPathComponent:@"whatamess_calls.log"];
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

static WAMLogLevel gLevel = WAMLogLevelOff;
static NSTimeInterval gLevelCheckedAt = 0;

void WAMLogInvalidateCache(void) {
    gLevelCheckedAt = 0;
}

WAMLogLevel WAMLogLevelCurrent(void) {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - gLevelCheckedAt > 2.0) {
        gLevelCheckedAt = now;
        id v = WAMDLReadPrefs()[kLevelKey];
        gLevel = v ? (WAMLogLevel)[v integerValue] : WAMLogLevelOff;
        if (gLevel < WAMLogLevelOff) gLevel = WAMLogLevelOff;
        if (gLevel > WAMLogLevelFirehose) gLevel = WAMLogLevelFirehose;
    }
    return gLevel;
}

#pragma mark - Writing


static os_unfair_lock gWriteLock = OS_UNFAIR_LOCK_INIT;
static int gLogFD = -1;
static unsigned long long gWritten = 0;

// Synchronous, append-mode write(2) on a cached descriptor.
// This is deliberately NOT dispatch_async: if the process dies, anything still
// sitting on a queue is lost, which is exactly the log you needed. A single
// write syscall is also cheaper than reopening NSFileHandle per line.
static void WAMDLOpenLocked(void) {
    if (gLogFD >= 0) return;
    NSString *path = WAMDLLogPath();
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                             withIntermediateDirectories:YES attributes:nil error:nil];
    gLogFD = open([path fileSystemRepresentation], O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (gLogFD >= 0) {
        struct stat st;
        gWritten = (fstat(gLogFD, &st) == 0) ? (unsigned long long)st.st_size : 0;
    }
}

static int gCallFD = -1;
static unsigned long long gCallWritten = 0;
static const unsigned long long kMaxCallBytes = 4 * 1024 * 1024;

static void WAMDLOpenCallsLocked(void) {
    if (gCallFD >= 0) return;
    NSString *path = WAMDLCallLogPath();
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                             withIntermediateDirectories:YES attributes:nil error:nil];
    gCallFD = open([path fileSystemRepresentation], O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (gCallFD >= 0) {
        struct stat st;
        gCallWritten = (fstat(gCallFD, &st) == 0) ? (unsigned long long)st.st_size : 0;
    }
}

static void WAMDLRotateCallsLocked(void) {
    if (gCallFD >= 0) { close(gCallFD); gCallFD = -1; }
    NSString *path = WAMDLCallLogPath();
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:[path stringByAppendingString:@".1"] error:nil];
    [fm moveItemAtPath:path toPath:[path stringByAppendingString:@".1"] error:nil];
    gCallWritten = 0;
    WAMDLOpenCallsLocked();
}

static void WAMDLRotateLocked(void) {
    if (gLogFD >= 0) {
        close(gLogFD);
        gLogFD = -1;
    }
    NSString *path = WAMDLLogPath();
    NSString *rotated = [path stringByAppendingString:@".1"];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:rotated error:nil];
    [fm moveItemAtPath:path toPath:rotated error:nil];
    gWritten = 0;
    WAMDLOpenLocked();
}

void WAMLogWrite(NSString *category, NSString *message) {
    if (!message) return;

    static NSString *proc = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        proc = [NSProcessInfo processInfo].processName ?: @"?";
    });

    // NSDateFormatter is not safe to share across threads; format the clock by hand.
    struct timeval tv;
    gettimeofday(&tv, NULL);
    time_t secs = tv.tv_sec;
    struct tm tmv;
    localtime_r(&secs, &tmv);

    NSString *line = [NSString stringWithFormat:@"%02d:%02d:%02d.%03d %@ [%@] %@\n",
                      tmv.tm_hour, tmv.tm_min, tmv.tm_sec, (int)(tv.tv_usec / 1000),
                      proc, category ?: @"-", message];

    NSLog(@"[WhatAMess][%@] %@", category ?: @"-", message);

    const char *bytes = [line UTF8String];
    if (!bytes) return;
    size_t len = strlen(bytes);

    // Per-call traces go to a separate file. Upstream's
    // applyCustomColorsToCKLabelsInView: alone can fire 18,000 times in five
    // seconds, which used to rotate every [nav] and [life] line out of existence.
    BOOL isCallTrace = [category isEqualToString:@"call"];

    os_unfair_lock_lock(&gWriteLock);
    if (isCallTrace) {
        WAMDLOpenCallsLocked();
        if (gCallFD >= 0) {
            ssize_t n = write(gCallFD, bytes, len);
            if (n > 0) gCallWritten += (unsigned long long)n;
            if (gCallWritten > kMaxCallBytes) WAMDLRotateCallsLocked();
        }
    } else {
        WAMDLOpenLocked();
        if (gLogFD >= 0) {
            ssize_t n = write(gLogFD, bytes, len);
            if (n > 0) gWritten += (unsigned long long)n;
            if (gWritten > kMaxBytes) WAMDLRotateLocked();
        }
    }
    os_unfair_lock_unlock(&gWriteLock);
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
        // One runaway site must not drown the trace. Above the threshold a site
        // is counted but no longer printed per call; the 5s summary still has it.
        static const unsigned long kFloodLimit = 400;
        if (site->sinceFlush <= kFloodLimit) {
            WAMLogWrite(@"call", [NSString stringWithFormat:@"%s #%lu", site->name, site->total]);
        } else if (site->sinceFlush == kFloodLimit + 1) {
            WAMLogWrite(@"call", [NSString stringWithFormat:
                @"%s exceeded %lu calls this window -- per-call logging suppressed, see [hooks] summary",
                site->name, kFloodLimit]);
        }
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
    [[NSFileManager defaultManager] removeItemAtPath:WAMDLCallLogPath() error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:
        [WAMDLCallLogPath() stringByAppendingString:@".1"] error:nil];
    os_unfair_lock_lock(&gWriteLock);
    if (gCallFD >= 0) { close(gCallFD); gCallFD = -1; gCallWritten = 0; }
    if (gLogFD >= 0) { close(gLogFD); gLogFD = -1; gWritten = 0; }
    os_unfair_lock_unlock(&gWriteLock);
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

// Foundation-only: UIDevice is not safe to touch from a dylib constructor.
static NSString *WAMDLOSVersionString(void) {
    NSOperatingSystemVersion v = [NSProcessInfo processInfo].operatingSystemVersion;
    return [NSString stringWithFormat:@"%ld.%ld.%ld",
            (long)v.majorVersion, (long)v.minorVersion, (long)v.patchVersion];
}

+ (void)logEnvironment {
    NSProcessInfo *pi = [NSProcessInfo processInfo];
    WAMLogWrite(@"env", [NSString stringWithFormat:
        @"WhatAMess filter prototype loaded | process=%@ pid=%d ios=%@ jbroot=%@ level=%@",
        pi.processName, (int)pi.processIdentifier,
        WAMDLOSVersionString(),
        WAMDLJBRoot().length ? WAMDLJBRoot() : @"(rootful)",
        [self nameForLevel:[self level]]]);
    WAMLogWrite(@"env", [NSString stringWithFormat:@"log file: %@", WAMDLLogPath()]);
}

@end

// XFinderNowPlaying.dylib — the Now Playing reader, hosted by /usr/bin/perl (B6).
//
// Why a dylib in perl, measured on macOS 27.0 (26A428), 2026-10-10:
//   * mediaremoted answers MRMediaRemoteGetNowPlayingInfo with NOTHING for an ordinary process while a
//     player is active (`entitlements=0` in its log), but with the full dictionary for the same call
//     made inside Apple-signed /usr/bin/perl (`entitlements=264241664`, bundle id com.apple.perl).
//     Since macOS 15.4 reading needs com.apple.mediaremote.now-playing-read-access, which a third-party
//     app cannot hold. SENDING commands (play/pause/next) works from the app itself, so only reading
//     lives here.
//   * The adapter is EVENT-DRIVEN: it registers for MediaRemote's change notifications and prints one
//     JSON line per change. Measured: one notification per track/pause/resume, 0.04 s CPU over 13 s,
//     ~18 MB RSS for the perl host. No polling anywhere.
//   * Artwork arrives in a LATER notification than the metadata (measured: first dict without bytes,
//     then one with 865 B image/jpeg), so artwork is emitted whenever its identifier changes.
//   * The constructor only registers and returns (blocking inside dlopen deadlocks dyld); the perl
//     host sleeps. A reader thread watches stdin and exits the process on EOF, so a dead XFinder can
//     never leave an orphan helper behind.
//
// Protocol (stdout, one JSON object per line):
//   {"t":"hello","v":1}
//   {"t":"np","empty":true}                                     — nothing is playing / client gone
//   {"t":"np","title":…,"artist":…,"album":…,"duration":…,"elapsed":…,"rate":…,"ts":…,
//    "playing":true|false,"pid":…,"artworkId":…,"artworkMime":…,"artwork":"<base64>"}  — artwork only when new
// Build: clang -fblocks -shared -o XFinderNowPlaying.dylib nowplaying-adapter.c -framework CoreFoundation
// Host:  /usr/bin/perl -e 'use DynaLoader; DynaLoader::dl_load_file($ARGV[0],0) or die; 1 while select(undef,undef,undef,3600)' <dylib>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <dispatch/dispatch.h>
#include <CoreFoundation/CoreFoundation.h>

typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*GetBoolFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*GetPIDFn)(dispatch_queue_t, void (^)(int));
typedef void (*RegisterFn)(dispatch_queue_t);

static GetInfoFn getInfo;
static GetBoolFn getIsPlaying;
static GetPIDFn getPID;
static dispatch_queue_t queue;          // serial: every callback, every print
static char *lastArtworkID;             // artwork is emitted only when this changes

#define KEY(name) CFSTR("kMRMediaRemoteNowPlayingInfo" name)

// ---- output helpers -------------------------------------------------------------------------

static void emitEscaped(const char *s) {
    for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
        switch (*p) {
        case '"':  fputs("\\\"", stdout); break;
        case '\\': fputs("\\\\", stdout); break;
        case '\n': fputs("\\n", stdout); break;
        case '\r': fputs("\\r", stdout); break;
        case '\t': fputs("\\t", stdout); break;
        default:
            if (*p < 0x20) fprintf(stdout, "\\u%04x", *p);
            else fputc(*p, stdout);
        }
    }
}

static int cfStringToUTF8(CFStringRef s, char **out) {
    if (!s || CFGetTypeID(s) != CFStringGetTypeID()) return 0;
    CFIndex max = CFStringGetMaximumSizeForEncoding(CFStringGetLength(s), kCFStringEncodingUTF8) + 1;
    char *buf = malloc((size_t)max);
    if (!buf) return 0;
    if (!CFStringGetCString(s, buf, max, kCFStringEncodingUTF8)) { free(buf); return 0; }
    *out = buf;
    return 1;
}

static void emitStringField(CFDictionaryRef d, CFStringRef key, const char *json) {
    char *s = NULL;
    if (cfStringToUTF8(CFDictionaryGetValue(d, key), &s)) {
        fprintf(stdout, ",\"%s\":\"", json); emitEscaped(s); fputc('"', stdout);
        free(s);
    }
}

static void emitNumberField(CFDictionaryRef d, CFStringRef key, const char *json) {
    CFTypeRef v = CFDictionaryGetValue(d, key);
    double x = 0;
    if (v && CFGetTypeID(v) == CFNumberGetTypeID() && CFNumberGetValue(v, kCFNumberDoubleType, &x))
        fprintf(stdout, ",\"%s\":%.3f", json, x);
}

static void emitBase64(const unsigned char *data, long n) {
    static const char T[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    for (long i = 0; i < n; i += 3) {
        unsigned v = (unsigned)data[i] << 16;
        if (i + 1 < n) v |= (unsigned)data[i + 1] << 8;
        if (i + 2 < n) v |= (unsigned)data[i + 2];
        fputc(T[(v >> 18) & 63], stdout);
        fputc(T[(v >> 12) & 63], stdout);
        fputc(i + 1 < n ? T[(v >> 6) & 63] : '=', stdout);
        fputc(i + 2 < n ? T[v & 63] : '=', stdout);
    }
}

// ---- the snapshot -------------------------------------------------------------------------

static void emitSnapshot(CFDictionaryRef d, Boolean playing, int pid) {
    if (!d || CFDictionaryGetCount(d) == 0) {
        fputs("{\"t\":\"np\",\"empty\":true}\n", stdout);
        fflush(stdout);
        return;
    }
    fputs("{\"t\":\"np\"", stdout);
    emitStringField(d, KEY("Title"), "title");
    emitStringField(d, KEY("Artist"), "artist");
    emitStringField(d, KEY("Album"), "album");
    emitNumberField(d, KEY("Duration"), "duration");
    emitNumberField(d, KEY("ElapsedTime"), "elapsed");
    emitNumberField(d, KEY("PlaybackRate"), "rate");
    CFTypeRef ts = CFDictionaryGetValue(d, KEY("Timestamp"));
    if (ts && CFGetTypeID(ts) == CFDateGetTypeID())
        fprintf(stdout, ",\"ts\":%.3f", CFDateGetAbsoluteTime(ts) + kCFAbsoluteTimeIntervalSince1970);
    fprintf(stdout, ",\"playing\":%s,\"pid\":%d", playing ? "true" : "false", pid);

    char *artID = NULL;
    cfStringToUTF8(CFDictionaryGetValue(d, KEY("ArtworkIdentifier")), &artID);
    CFTypeRef art = CFDictionaryGetValue(d, KEY("ArtworkData"));
    if (art && CFGetTypeID(art) == CFDataGetTypeID() && CFDataGetLength(art) > 0) {
        char fallback[32];
        if (!artID) { snprintf(fallback, sizeof fallback, "len:%ld", (long)CFDataGetLength(art)); artID = strdup(fallback); }
        fputs(",\"artworkId\":\"", stdout); emitEscaped(artID); fputc('"', stdout);
        emitStringField(d, KEY("ArtworkMIMEType"), "artworkMime");
        if (!lastArtworkID || strcmp(lastArtworkID, artID) != 0) {
            fputs(",\"artwork\":\"", stdout);
            emitBase64(CFDataGetBytePtr(art), (long)CFDataGetLength(art));
            fputc('"', stdout);
            free(lastArtworkID); lastArtworkID = strdup(artID);
        }
    } else if (artID) {
        fputs(",\"artworkId\":\"", stdout); emitEscaped(artID); fputc('"', stdout);
    }
    free(artID);
    fputs("}\n", stdout);
    fflush(stdout);
}

/// Read everything inside the first callback — the dictionary is released when that block returns
/// (a probe that kept the pointer across the nested calls died with a PAC exception).
static void snapshot(void) {
    getInfo(queue, ^(CFDictionaryRef d) {
        CFDictionaryRef kept = d ? CFRetain(d) : NULL;
        getIsPlaying(queue, ^(Boolean playing) {
            getPID(queue, ^(int pid) {
                emitSnapshot(kept, playing, pid);
                if (kept) CFRelease(kept);
            });
        });
    });
}

static void onChange(CFNotificationCenterRef c, void *observer, CFNotificationName name,
                     const void *object, CFDictionaryRef userInfo) {
    snapshot();
}

// ---- lifetime -----------------------------------------------------------------------------

static void *watchStdin(void *unused) {
    char buf[256];
    for (;;) {
        ssize_t n = read(STDIN_FILENO, buf, sizeof buf);
        if (n <= 0) _exit(0);              // the parent closed the pipe (or died): leave with it
    }
    return NULL;
}

__attribute__((constructor)) static void start(void) {
    void *h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!h) { fputs("{\"t\":\"error\",\"reason\":\"dlopen\"}\n", stdout); fflush(stdout); _exit(2); }
    getInfo = (GetInfoFn)dlsym(h, "MRMediaRemoteGetNowPlayingInfo");
    getIsPlaying = (GetBoolFn)dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    getPID = (GetPIDFn)dlsym(h, "MRMediaRemoteGetNowPlayingApplicationPID");
    RegisterFn reg = (RegisterFn)dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications");
    if (!getInfo || !getIsPlaying || !getPID || !reg) {
        fputs("{\"t\":\"error\",\"reason\":\"symbols\"}\n", stdout); fflush(stdout); _exit(2);
    }
    queue = dispatch_queue_create("com.xfinder.nowplaying", DISPATCH_QUEUE_SERIAL);

    const char *names[] = {
        "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
    };
    CFNotificationCenterRef center = CFNotificationCenterGetLocalCenter();
    for (size_t i = 0; i < sizeof names / sizeof *names; i++) {
        CFStringRef *sym = dlsym(h, names[i]);
        CFStringRef name = sym ? *sym : CFStringCreateWithCString(NULL, names[i], kCFStringEncodingUTF8);
        CFNotificationCenterAddObserver(center, NULL, onChange, name, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    reg(queue);

    pthread_t t;
    pthread_create(&t, NULL, watchStdin, NULL);
    pthread_detach(t);

    dispatch_async(queue, ^{ fputs("{\"t\":\"hello\",\"v\":1}\n", stdout); fflush(stdout); });
    snapshot();                              // the baseline: what is playing right now
}

// Time and duration text.
#import "format.h"

NSString* Clock(long long ms, bool ceilSecs) {
    if (ms < 0) ms = 0;
    long long s = ceilSecs ? (ms + 999) / 1000 : ms / 1000;
    long long h = s / 3600, m = (s / 60) % 60, sec = s % 60;
    if (h > 0) return [NSString stringWithFormat:@"%lld:%02lld:%02lld", h, m, sec];
    return [NSString stringWithFormat:@"%02lld:%02lld", m, sec];
}
// stats row: no leading zero on minutes (0:42, 12:05, 1:02:03)
NSString* StatClock(long long ms) {
    NSString* c = Clock(ms, false);
    if (c.length == 5 && [c characterAtIndex:0] == '0') c = [c substringFromIndex:1];
    return c;
}
NSString* ShortDur(long long minutes) {
    if (minutes >= 60) {
        if (minutes % 60) return [NSString stringWithFormat:@"%lldh %lldm", minutes / 60, minutes % 60];
        return [NSString stringWithFormat:@"%lldh", minutes / 60];
    }
    return [NSString stringWithFormat:@"%lld min", minutes];
}

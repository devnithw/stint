// Time and duration text.
#pragma once
#import "app.h"

NSString* Clock(long long ms, bool ceilSecs);  // 05:42, 1:02:03
NSString* StatClock(long long ms);             // stats row: no leading zero on minutes (0:42, 12:05, 1:02:03)
NSString* ShortDur(long long minutes);         // 45 min, 2h, 2h 5m

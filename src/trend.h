// Focus trend: focused time per day, and the week view that charts it.
#pragma once
#import "app.h"

void TrendAdd(long long ms);  // called from Tick with the focus time that just passed
void TrendSave();
void DrawTrend(CGFloat W, CGFloat H);

#ifdef STINT_SNAPSHOT
void TrendSample(const long long mins[2][7]);  // minutes for this week and last, Monday first
#endif

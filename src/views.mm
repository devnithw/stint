// Card sizes and drawing dispatch for every view.
#import "views.h"
#import "trend.h"

void CardSize(View v, CGFloat& w, CGFloat& h) {
    if (v == V_COMPACT) { w = 206; h = 56; }
    else if (v == V_SETUP || v == V_TREND) { w = 280; h = 428; }
    else { w = 280; h = 220; }
}
NSSize WinSize(View v) {
    CGFloat cw, ch; CardSize(v, cw, ch);
    return NSMakeSize(ceil(cw + 2 * SH), ceil(ch + 2 * SH));
}

// Draws the card for view `v` into G, at the origin.
void DrawView(View v, CGFloat w, CGFloat h) {
    if (v == V_MAIN) DrawMain(w, h);
    else if (v == V_COMPACT) DrawCompact(w, h);
    else if (v == V_TREND) DrawTrend(w, h);
    else DrawSetup(w, h);
}

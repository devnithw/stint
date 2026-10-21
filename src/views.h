// The cards: main (view_main.mm), compact (view_main.mm), setup (view_setup.mm), trend (trend.mm).
// Each Draw* draws into G at the origin and registers its hit zones.
#pragma once
#import "app.h"

void CardSize(View v, CGFloat& w, CGFloat& h);
NSSize WinSize(View v);                         // card plus shadow margin
void DrawView(View v, CGFloat w, CGFloat h);

void DrawMain(CGFloat W, CGFloat H);
void DrawCompact(CGFloat W, CGFloat H);
void DrawBar(CGFloat x, CGFloat y, CGFloat w, CGFloat h, bool big);  // the segmented session bar

// setup rows (Z_DEC0 + i / Z_INC0 + i)
struct Row { NSString* label; int* val; int lo, hi; };
Row Rows(int i);
void DrawSetup(CGFloat W, CGFloat H);

// Drawing primitives, embedded fonts and text, on top of Core Graphics and Core Text.
// The canvas is flipped (y grows downward) and everything draws into G.
#pragma once
#import "app.h"

extern CGContextRef G;  // valid only while the canvas is drawing

void SetFill(Col c);
void SetStroke(Col c, CGFloat w, bool round);
void FillRR(Col c, CGFloat x, CGFloat y, CGFloat w, CGFloat h, CGFloat r);   // rounded rects
void StrokeRR(Col c, CGFloat lw, CGFloat x, CGFloat y, CGFloat w, CGFloat h, CGFloat r);
void ClipRR(CGFloat x, CGFloat y, CGFloat w, CGFloat h, CGFloat r);
void FillEllipse(Col c, CGFloat x, CGFloat y, CGFloat w, CGFloat h);
void StrokeEllipse(Col c, CGFloat lw, CGFloat x, CGFloat y, CGFloat w, CGFloat h);
void Line(Col c, CGFloat lw, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2, bool round = false);
void Poly(Col c, CGFloat lw, const CGPoint* p, int n, bool closed);  // round-capped polyline
void FillPoly(Col c, const CGPoint* p, int n);

// Text. `which` picks the Inter weight: 0 = time (bold display), 1 = semibold, 2 = body.
// Widths are glyph-ink bounds.
enum { AL_L, AL_C, AL_R };
CGFloat TextW(NSString* s, int which, CGFloat size);
CGFloat Text(NSString* s, int which, CGFloat size, CGFloat x, CGFloat baseline, Col c, int align = AL_L);  // returns drawn width

void LoadFonts();  // embedded Inter weights; falls back to the system font

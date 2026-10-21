// Building blocks shared by the views: the card, the end-of-block blink, buttons, hit zones.
#import "widgets.h"
#import "gfx.h"
#import "icons.h"

using std::min;
using std::max;

void AddZone(int id, CGFloat x, CGFloat y, CGFloat w, CGFloat h) { A.zones.push_back({id, CGRectMake(x, y, w, h)}); }

static CGGradientRef CardGradient() {
    static CGGradientRef g = nullptr;
    if (!g) {
        Col s[3] = {Hex(0x1E2537), Hex(0x161B27), Hex(0x10141D)};
        CGFloat comps[12], pos[3] = {0, 0.45, 1};
        for (int i = 0; i < 3; i++) { comps[i * 4] = s[i].r; comps[i * 4 + 1] = s[i].g; comps[i * 4 + 2] = s[i].b; comps[i * 4 + 3] = 1; }
        CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        g = CGGradientCreateWithColorComponents(cs, comps, pos, 3);
        CGColorSpaceRelease(cs);
    }
    return g;
}

void DrawCard(CGFloat w, CGFloat h, CGFloat r) {
    for (int i = 9; i >= 1; i--) {
        CGFloat e = i * 1.5;
        FillRR(ARGB(6, 0, 0, 0), -e, -e + 4, w + 2 * e, h + 2 * e, r + e);
    }
    CGContextSaveGState(G);
    ClipRR(0, 0, w, h, r);
    CGContextDrawLinearGradient(G, CardGradient(), CGPointMake(0, -1), CGPointMake(0, h + 1), 0);
    CGContextRestoreGState(G);
    StrokeRR(ARGB(30, 255, 255, 255), 1, 0.5, 0.5, w - 1, h - 1, r - 0.5);
}

void DrawBlink(CGFloat w, CGFloat h, CGFloat r) {
    if (!A.blinking) return;
    CGFloat t = (CGFloat)(Now() - A.blinkStart);
    // two pulses: 0-380ms and 560-940ms
    CGFloat a = 0;
    if (t < 380) a = sin(M_PI * t / 380);
    else if (t >= 560 && t < 940) a = sin(M_PI * (t - 560) / 380);
    if (a <= 0) return;
    FillRR(ARGB((int)(150 * a), 0x2D, 0x8C, 0xFF), 0, 0, w, h, r);
    StrokeRR(ARGB((int)(230 * a), 255, 255, 255), 2, 1, 1, w - 2, h - 2, r - 1);
}

void CircleButton(int id, CGFloat cx, CGFloat cy, CGFloat r, int icon, CGFloat iconSize) {
    bool hot = A.hover == id;
    FillEllipse(hot ? P::circleHot : P::circle, cx - r, cy - r, 2 * r, 2 * r);
    if (icon == 2)  // ring for "done" state
        StrokeEllipse(ARGB(120, 0x3D, 0x8B, 0xFF), 1.5, cx - r + 1, cy - r + 1, 2 * r - 2, 2 * r - 2);
    Icon(icon, cx + (icon == 0 ? iconSize * 0.05 : 0), cy, iconSize, P::circleIcon);
    AddZone(id, cx - r, cy - r, 2 * r, 2 * r);
}

void IconButton(int id, int icon, CGFloat cx, CGFloat cy) {
    bool hot = A.hover == id;
    if (hot) FillRR(P::chipHot, cx - 11, cy - 11, 22, 22, 7);
    Icon(icon, cx, cy, 12, hot ? P::text : P::sub);
    AddZone(id, cx - 11, cy - 11, 22, 22);
}

// Vector icons for the buttons, drawn with the gfx primitives.
#import "icons.h"
#import "gfx.h"

using std::min;
using std::max;

void Icon(int kind, CGFloat cx, CGFloat cy, CGFloat s, Col c) {
    // s = icon box size (points)
    CGFloat lw = max(1.5, s * 0.13);
    CGFloat h = s / 2;
    switch (kind) {
    case 0: { // play
        CGPoint pts[3] = {{cx - h * 0.55, cy - h * 0.8}, {cx + h * 0.85, cy}, {cx - h * 0.55, cy + h * 0.8}};
        FillPoly(c, pts, 3); Poly(c, s * 0.12, pts, 3, true); break; }
    case 1: { // pause
        CGFloat w = s * 0.2, hh = s * 0.8;
        FillRR(c, cx - s * 0.3, cy - hh / 2, w, hh, w / 2);
        FillRR(c, cx + s * 0.1, cy - hh / 2, w, hh, w / 2); break; }
    case 2: { // check
        CGPoint pts[3] = {{cx - h * 0.75, cy + h * 0.02}, {cx - h * 0.2, cy + h * 0.58}, {cx + h * 0.8, cy - h * 0.6}};
        Poly(c, s * 0.15, pts, 3, false); break; }
    case 3: case 6: { // restart / reset: clockwise arrow, open at the top right
        CGFloat r = h * 0.72;
        cy += lw * 0.4;  // the arrowhead rises above the ring; nudge down to sit optically centred
        SetStroke(c, lw, true);
        CGContextBeginPath(G);
        CGContextAddArc(G, cx, cy, r, -30 * M_PI / 180, 270 * M_PI / 180, 0);  // clockwise on the flipped canvas
        CGContextStrokePath(G);
        // arrowhead on the top end, pointing along the direction of travel (right)
        CGFloat ex = cx, ey = cy - r, len = lw * 2.1, half = lw * 1.35;
        CGPoint tri[3] = {{ex - len * 0.35, ey - half}, {ex + len * 0.65, ey}, {ex - len * 0.35, ey + half}};
        FillPoly(c, tri, 3);
        Poly(c, lw * 0.5, tri, 3, true);  // soften the corners
        break; }
    case 4: { // skip next
        CGPoint pts[3] = {{cx - h * 0.7, cy - h * 0.7}, {cx + h * 0.35, cy}, {cx - h * 0.7, cy + h * 0.7}};
        FillPoly(c, pts, 3);
        Line(c, lw, cx + h * 0.65, cy - h * 0.7, cx + h * 0.65, cy + h * 0.7, true); break; }
    case 5: { // sliders (setup)
        Line(c, lw, cx - h * 0.8, cy - h * 0.4, cx + h * 0.8, cy - h * 0.4, true);
        Line(c, lw, cx - h * 0.8, cy + h * 0.4, cx + h * 0.8, cy + h * 0.4, true);
        CGFloat k = s * 0.16;
        FillEllipse(c, cx + h * 0.3 - k, cy - h * 0.4 - k, 2 * k, 2 * k);
        FillEllipse(c, cx - h * 0.3 - k, cy + h * 0.4 - k, 2 * k, 2 * k); break; }
    case 7: { // compact (shrink): two inward corners
        CGFloat o = h * 0.75, i = h * 0.15;
        CGPoint a1[3] = {{cx - o, cy - i * 2.2}, {cx - i, cy - i}, {cx - i * 2.2, cy - o}};
        CGPoint a2[3] = {{cx + o, cy + i * 2.2}, {cx + i, cy + i}, {cx + i * 2.2, cy + o}};
        Poly(c, lw, a1, 3, false); Poly(c, lw, a2, 3, false); break; }
    case 8: { // close
        CGFloat o = h * 0.6;
        Line(c, lw, cx - o, cy - o, cx + o, cy + o, true);
        Line(c, lw, cx - o, cy + o, cx + o, cy - o, true); break; }
    case 9: { // expand: two outward corners
        CGFloat o = h * 0.75, k = h * 0.55;
        CGPoint a1[3] = {{cx - o, cy - o + k}, {cx - o, cy - o}, {cx - o + k, cy - o}};
        CGPoint a2[3] = {{cx + o, cy + o - k}, {cx + o, cy + o}, {cx + o - k, cy + o}};
        Poly(c, lw, a1, 3, false); Poly(c, lw, a2, 3, false);
        Line(c, lw, cx - o, cy - o, cx - h * 0.1, cy - h * 0.1, true);
        Line(c, lw, cx + o, cy + o, cx + h * 0.1, cy + h * 0.1, true); break; }
    case 10: { // minus
        Line(c, lw, cx - h * 0.55, cy, cx + h * 0.55, cy, true); break; }
    case 11: { // plus
        Line(c, lw, cx - h * 0.55, cy, cx + h * 0.55, cy, true);
        Line(c, lw, cx, cy - h * 0.55, cx, cy + h * 0.55, true); break; }
    case 12: { // trend: three rising bars
        CGFloat base = cy + h * 0.7;
        Line(c, lw, cx - h * 0.62, base, cx - h * 0.62, cy + h * 0.2, true);
        Line(c, lw, cx, base, cx, cy - h * 0.25, true);
        Line(c, lw, cx + h * 0.62, base, cx + h * 0.62, cy - h * 0.7, true); break; }
    }
}

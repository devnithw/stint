// Drawing primitives, embedded fonts and text, on top of Core Graphics and Core Text.
#import "gfx.h"

using std::min;
using std::max;

CGContextRef G = nullptr;   // valid only while the canvas is drawing

void SetFill(Col c) {
    CGColorRef k = CGColorCreateSRGB(c.r, c.g, c.b, c.a);
    CGContextSetFillColorWithColor(G, k); CGColorRelease(k);
}
void SetStroke(Col c, CGFloat w, bool round) {
    CGColorRef k = CGColorCreateSRGB(c.r, c.g, c.b, c.a);
    CGContextSetStrokeColorWithColor(G, k); CGColorRelease(k);
    CGContextSetLineWidth(G, w);
    CGContextSetLineCap(G, round ? kCGLineCapRound : kCGLineCapButt);
    CGContextSetLineJoin(G, round ? kCGLineJoinRound : kCGLineJoinMiter);
}
static void RR(CGFloat x, CGFloat y, CGFloat w, CGFloat h, CGFloat r) {
    if (w <= 0 || h <= 0) return;
    r = min(r, min(w, h) / 2);
    CGRect rc = CGRectMake(x, y, w, h);
    if (r < 0.5) { CGContextAddRect(G, rc); return; }
    CGPathRef p = CGPathCreateWithRoundedRect(rc, r, r, nullptr);
    CGContextAddPath(G, p); CGPathRelease(p);
}
void FillRR(Col c, CGFloat x, CGFloat y, CGFloat w, CGFloat h, CGFloat r) {
    CGContextBeginPath(G); RR(x, y, w, h, r); SetFill(c); CGContextFillPath(G);
}
void StrokeRR(Col c, CGFloat lw, CGFloat x, CGFloat y, CGFloat w, CGFloat h, CGFloat r) {
    CGContextBeginPath(G); RR(x, y, w, h, r); SetStroke(c, lw, false); CGContextStrokePath(G);
}
void ClipRR(CGFloat x, CGFloat y, CGFloat w, CGFloat h, CGFloat r) {
    CGContextBeginPath(G); RR(x, y, w, h, r); CGContextClip(G);
}
void FillEllipse(Col c, CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    SetFill(c); CGContextFillEllipseInRect(G, CGRectMake(x, y, w, h));
}
void StrokeEllipse(Col c, CGFloat lw, CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    SetStroke(c, lw, false); CGContextStrokeEllipseInRect(G, CGRectMake(x, y, w, h));
}
void Line(Col c, CGFloat lw, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2, bool round) {
    SetStroke(c, lw, round);
    CGContextBeginPath(G); CGContextMoveToPoint(G, x1, y1); CGContextAddLineToPoint(G, x2, y2);
    CGContextStrokePath(G);
}
void Poly(Col c, CGFloat lw, const CGPoint* p, int n, bool closed) {  // round-capped polyline
    SetStroke(c, lw, true);
    CGContextBeginPath(G); CGContextAddLines(G, p, n);
    if (closed) CGContextClosePath(G);
    CGContextStrokePath(G);
}
void FillPoly(Col c, const CGPoint* p, int n) {
    SetFill(c);
    CGContextBeginPath(G); CGContextAddLines(G, p, n); CGContextClosePath(G); CGContextFillPath(G);
}

// ---- text (Core Text; widths are glyph-ink bounds)

static CTFontRef Font(int which, CGFloat size) {
    long long key = which * 1000000LL + llround(size * 100);
    auto it = A.fonts.find(key);
    if (it != A.fonts.end()) return it->second;
    CTFontRef f = A.fontDesc[which] ? CTFontCreateWithFontDescriptor(A.fontDesc[which], size, nullptr) : nullptr;
    if (!f) {  // fallback: system font with tabular digits
        NSFontWeight wt = which == 0 ? NSFontWeightBold : which == 1 ? NSFontWeightSemibold : NSFontWeightRegular;
        f = (CTFontRef)CFBridgingRetain([NSFont monospacedDigitSystemFontOfSize:size weight:wt]);
    }
    A.fonts[key] = f;
    return f;
}
static CTLineRef MakeLine(NSString* s, int which, CGFloat size) {
    NSDictionary* attrs = @{(id)kCTFontAttributeName: (__bridge id)Font(which, size),
                            (id)kCTForegroundColorFromContextAttributeName: @YES};
    NSAttributedString* as = [[NSAttributedString alloc] initWithString:s attributes:attrs];
    return CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)as);
}
static CGFloat LineW(CTLineRef l) {
    CGRect b = CTLineGetBoundsWithOptions(l, kCTLineBoundsUseGlyphPathBounds);
    return b.origin.x + b.size.width;
}
CGFloat TextW(NSString* s, int which, CGFloat size) {
    if (!s.length) return 0;
    CTLineRef l = MakeLine(s, which, size);
    CGFloat w = LineW(l); CFRelease(l);
    return w;
}
// returns drawn width
CGFloat Text(NSString* s, int which, CGFloat size, CGFloat x, CGFloat baseline, Col c, int align) {
    if (!s.length) return 0;
    CTLineRef l = MakeLine(s, which, size);
    CGFloat w = LineW(l);
    if (align == AL_C) x -= w / 2; else if (align == AL_R) x -= w;
    SetFill(c);
    CGContextSetTextMatrix(G, CGAffineTransformMakeScale(1, -1));  // the canvas is flipped (y down)
    CGContextSetTextPosition(G, x, baseline);
    CTLineDraw(l, G);
    CFRelease(l);
    return w;
}

void LoadFonts() {
    // Inter weights ship in Contents/Resources/fonts (or ./fonts next to an unbundled binary).
    NSString* names[3] = {@"StintInterTime", @"StintInterSemi", @"StintInterBody"};
    NSArray* dirs = @[[[NSBundle mainBundle].resourcePath stringByAppendingPathComponent:@"fonts"],
                      [[[NSBundle mainBundle].executablePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"fonts"]];
    for (int i = 0; i < 3; i++) {
        for (NSString* d in dirs) {
            NSURL* u = [NSURL fileURLWithPath:[d stringByAppendingPathComponent:[names[i] stringByAppendingString:@".ttf"]]];
            CFArrayRef ds = CTFontManagerCreateFontDescriptorsFromURL((__bridge CFURLRef)u);
            if (ds && CFArrayGetCount(ds) > 0) A.fontDesc[i] = (CTFontDescriptorRef)CFRetain(CFArrayGetValueAtIndex(ds, 0));
            if (ds) CFRelease(ds);
            if (A.fontDesc[i]) break;
        }
    }
    if (!A.fontDesc[0] || !A.fontDesc[1] || !A.fontDesc[2]) {  // all or nothing, so weights stay consistent
        for (auto& d : A.fontDesc) { if (d) CFRelease(d); d = nullptr; }
    }
}

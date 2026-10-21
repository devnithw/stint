// Stint — a tiny floating focus timer for macOS.
// Single-file Cocoa + Core Graphics app. Build with build.sh.
//
// Concepts
//   Session : the whole plan you start (e.g. 4 rounds).
//   Round   : one Focus block, followed by a Break block (none after the last round).
//   Block   : a single Focus / Break / Long break segment shown in the bar.
//   Extra   : time you keep going after a block's timer hits zero (the stopwatch).

#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>
#include <algorithm>
#include <cmath>
#include <ctime>
#include <map>
#include <vector>
#include <unistd.h>
using std::min;
using std::max;

// ---------------------------------------------------------------- constants
static const CGFloat SH = 18;            // shadow margin (points)
static NSString* const kShowNote = @"io.github.devnithw.stint.show";  // sent by a second launch
enum { K_FOCUS = 0, K_BREAK = 1, K_LONG = 2 };
enum View { V_MAIN, V_COMPACT, V_SETUP };

enum {
    Z_NONE = 0, Z_MAIN, Z_SKIP, Z_RESET, Z_SETUP, Z_COMPACT, Z_CLOSE,
    Z_DEC0 = 20, Z_INC0 = 30, Z_TOG0 = 40, Z_CANCEL = 50, Z_START
};
enum {
    M_TOGGLE = 100, M_DONE, M_SKIP, M_RESET, M_SETUP, M_COMPACT, M_TOP, M_FOCUS, M_SHOWHIDE, M_EXIT
};

// ---------------------------------------------------------------- palette
struct Col { CGFloat r, g, b, a; };
static Col ARGB(int a, int r, int g, int b) { return {r / 255.0, g / 255.0, b / 255.0, a / 255.0}; }
static Col Hex(unsigned rgb, int a = 255) { return ARGB(a, (rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255); }
static Col WithA(Col c, int a) { c.a = a / 255.0; return c; }

namespace P {
    const Col text = ARGB(255, 255, 255, 255);
    const Col sub = ARGB(255, 0x8C, 0x94, 0xA6);
    const Col dim = ARGB(255, 0x6F, 0x78, 0x8C);
    const Col soft = ARGB(255, 0xD5, 0xDA, 0xE4);
    const Col blue = ARGB(255, 0x2D, 0x8C, 0xFF);
    const Col blueText = ARGB(255, 0x5A, 0xA8, 0xFF);
    const Col circle = ARGB(255, 0x1C, 0x3A, 0x6B);
    const Col circleHot = ARGB(255, 0x25, 0x48, 0x82);
    const Col circleIcon = ARGB(255, 0x3D, 0x8B, 0xFF);
    const Col chip = ARGB(255, 0x1C, 0x26, 0x38);
    const Col chipHot = ARGB(255, 0x27, 0x33, 0x4A);
}

// ---------------------------------------------------------------- data
struct Cfg {
    int focus = 20, brk = 5, rounds = 4, longBrk = 15, longEvery = 0;
    bool autoCont = false, openFocus = true;
};
struct Block {
    int kind; int round;
    long long dur; long long elapsed;
    bool alerted; bool done;
};
struct Zone { int id; CGRect r; };

struct App {
    NSPanel* win = nil;
    NSView* canvas = nil;
    NSStatusItem* tray = nil;
    NSMenu* menu = nil;
    id activity = nil;             // keeps App Nap from throttling the timer while running
    View view = V_MAIN;
    View backView = V_MAIN;
    bool prefCompact = false;
    bool topmost = true;
    bool hidden = false;

    Cfg cfg, edit;
    std::vector<Block> blocks;
    int idx = 0;
    bool running = false;
    bool started = false;
    unsigned long long lastTick = 0;

    // ui
    std::vector<Zone> zones;
    int hover = Z_NONE, pressed = Z_NONE;
    bool inside = false;
    bool dragging = false, dragMoved = false;
    NSPoint dragStart{}, winStart{};
    unsigned long long blinkStart = 0;
    bool blinking = false;
    int repeatZone = Z_NONE; int repeatCount = 0;
    long long lastShownSec = -1;
    NSTimer* tTick = nil;
    NSTimer* tAnim = nil;
    NSTimer* tRepeat = nil;

    CTFontDescriptorRef fontDesc[3] = {};    // embedded Inter weights (time, semi, body)
    std::map<long long, CTFontRef> fonts;    // cache by (which, size)
} A;

// ---------------------------------------------------------------- helpers
static unsigned long long Now() { return clock_gettime_nsec_np(CLOCK_MONOTONIC) / 1000000ULL; }

static NSString* Clock(long long ms, bool ceilSecs) {
    if (ms < 0) ms = 0;
    long long s = ceilSecs ? (ms + 999) / 1000 : ms / 1000;
    long long h = s / 3600, m = (s / 60) % 60, sec = s % 60;
    if (h > 0) return [NSString stringWithFormat:@"%lld:%02lld:%02lld", h, m, sec];
    return [NSString stringWithFormat:@"%02lld:%02lld", m, sec];
}
// stats row: no leading zero on minutes (0:42, 12:05, 1:02:03)
static NSString* StatClock(long long ms) {
    NSString* c = Clock(ms, false);
    if (c.length == 5 && [c characterAtIndex:0] == '0') c = [c substringFromIndex:1];
    return c;
}
static NSString* ShortDur(long long minutes) {
    if (minutes >= 60) {
        if (minutes % 60) return [NSString stringWithFormat:@"%lldh %lldm", minutes / 60, minutes % 60];
        return [NSString stringWithFormat:@"%lldh", minutes / 60];
    }
    return [NSString stringWithFormat:@"%lld min", minutes];
}

// ---- drawing primitives (thin Core Graphics helpers)
static CGContextRef G = nullptr;   // valid only while the canvas is drawing

static void SetFill(Col c) {
    CGColorRef k = CGColorCreateSRGB(c.r, c.g, c.b, c.a);
    CGContextSetFillColorWithColor(G, k); CGColorRelease(k);
}
static void SetStroke(Col c, CGFloat w, bool round) {
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
static void FillRR(Col c, CGFloat x, CGFloat y, CGFloat w, CGFloat h, CGFloat r) {
    CGContextBeginPath(G); RR(x, y, w, h, r); SetFill(c); CGContextFillPath(G);
}
static void StrokeRR(Col c, CGFloat lw, CGFloat x, CGFloat y, CGFloat w, CGFloat h, CGFloat r) {
    CGContextBeginPath(G); RR(x, y, w, h, r); SetStroke(c, lw, false); CGContextStrokePath(G);
}
static void ClipRR(CGFloat x, CGFloat y, CGFloat w, CGFloat h, CGFloat r) {
    CGContextBeginPath(G); RR(x, y, w, h, r); CGContextClip(G);
}
static void FillEllipse(Col c, CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    SetFill(c); CGContextFillEllipseInRect(G, CGRectMake(x, y, w, h));
}
static void StrokeEllipse(Col c, CGFloat lw, CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    SetStroke(c, lw, false); CGContextStrokeEllipseInRect(G, CGRectMake(x, y, w, h));
}
static void Line(Col c, CGFloat lw, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2, bool round = false) {
    SetStroke(c, lw, round);
    CGContextBeginPath(G); CGContextMoveToPoint(G, x1, y1); CGContextAddLineToPoint(G, x2, y2);
    CGContextStrokePath(G);
}
static void Poly(Col c, CGFloat lw, const CGPoint* p, int n, bool closed) {  // round-capped polyline
    SetStroke(c, lw, true);
    CGContextBeginPath(G); CGContextAddLines(G, p, n);
    if (closed) CGContextClosePath(G);
    CGContextStrokePath(G);
}
static void FillPoly(Col c, const CGPoint* p, int n) {
    SetFill(c);
    CGContextBeginPath(G); CGContextAddLines(G, p, n); CGContextClosePath(G); CGContextFillPath(G);
}

// ---- text (Core Text; widths are glyph-ink bounds)
enum { AL_L, AL_C, AL_R };
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
static CGFloat TextW(NSString* s, int which, CGFloat size) {
    if (!s.length) return 0;
    CTLineRef l = MakeLine(s, which, size);
    CGFloat w = LineW(l); CFRelease(l);
    return w;
}
// returns drawn width
static CGFloat Text(NSString* s, int which, CGFloat size, CGFloat x, CGFloat baseline, Col c, int align = AL_L) {
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

// ---------------------------------------------------------------- settings
// Stored with NSUserDefaults (~/Library/Preferences/<bundle id>.plist).
static int PrefInt(NSString* k, int def) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:k];
    return [v respondsToSelector:@selector(intValue)] ? [v intValue] : def;
}
static void PrefPut(NSString* k, int v) { [[NSUserDefaults standardUserDefaults] setInteger:v forKey:k]; }
static void LoadSettings() {
    Cfg& c = A.cfg;
    c.focus = std::clamp(PrefInt(@"focus", 20), 1, 180);
    c.brk = std::clamp(PrefInt(@"break", 5), 1, 60);
    c.rounds = std::clamp(PrefInt(@"rounds", 4), 1, 12);
    c.longBrk = std::clamp(PrefInt(@"longBreak", 15), 1, 90);
    c.longEvery = std::clamp(PrefInt(@"longEvery", 0), 0, 12);
    c.autoCont = PrefInt(@"autoContinue", 0) != 0;
    c.openFocus = PrefInt(@"openFocusSettings", 1) != 0;
    A.topmost = PrefInt(@"topmost", 1) != 0;
    A.prefCompact = PrefInt(@"compact", 0) != 0;
}
static void SaveSettings() {
    Cfg& c = A.cfg;
    PrefPut(@"focus", c.focus); PrefPut(@"break", c.brk); PrefPut(@"rounds", c.rounds);
    PrefPut(@"longBreak", c.longBrk); PrefPut(@"longEvery", c.longEvery);
    PrefPut(@"autoContinue", c.autoCont); PrefPut(@"openFocusSettings", c.openFocus);
    PrefPut(@"topmost", A.topmost); PrefPut(@"compact", A.prefCompact);
    if (A.win) {  // window top-left, in Cocoa screen coordinates
        NSRect f = A.win.frame;
        PrefPut(@"x", (int)lround(f.origin.x)); PrefPut(@"top", (int)lround(NSMaxY(f))); PrefPut(@"hasPos", 1);
    }
}

// ---------------------------------------------------------------- session logic
static std::vector<Block> BuildPlan(const Cfg& c) {
    std::vector<Block> v;
    for (int r = 1; r <= c.rounds; r++) {
        v.push_back({K_FOCUS, r, c.focus * 60000LL, 0, false, false});
        if (r < c.rounds) {
            bool lng = c.longEvery > 0 && r % c.longEvery == 0;
            v.push_back({lng ? K_LONG : K_BREAK, r, (lng ? c.longBrk : c.brk) * 60000LL, 0, false, false});
        }
    }
    return v;
}
static bool Complete() { return A.idx >= (int)A.blocks.size(); }
static Block* Cur() { return Complete() ? nullptr : &A.blocks[A.idx]; }
static bool Over() { Block* b = Cur(); return b && b->elapsed >= b->dur; }
static long long FocusedMs() {
    long long t = 0;
    for (int i = 0; i < (int)A.blocks.size() && i <= A.idx; i++)
        if (A.blocks[i].kind == K_FOCUS) t += A.blocks[i].elapsed;
    return t;
}
static long long ExtraMs() {
    long long t = 0;
    for (int i = 0; i < (int)A.blocks.size() && i <= A.idx; i++)
        if (A.blocks[i].kind == K_FOCUS) t += max(0LL, A.blocks[i].elapsed - A.blocks[i].dur);
    return t;
}
static int RoundsDone() {
    int n = 0;
    for (auto& b : A.blocks) if (b.kind == K_FOCUS && b.done) n++;
    return n;
}

static void Render();
static void UpdateTray();
static void DoAction(int id);

static NSTimer* Every(double secs, void (^fn)(void)) {
    NSTimer* t = [NSTimer timerWithTimeInterval:secs repeats:YES block:^(NSTimer*) { fn(); }];
    t.tolerance = secs * 0.1;
    [[NSRunLoop mainRunLoop] addTimer:t forMode:NSRunLoopCommonModes];  // keeps ticking while a menu is open
    return t;
}
static void Kill(NSTimer* __strong& t) { [t invalidate]; t = nil; }

// Opens the Focus pane in System Settings.
// It does not start or stop a Focus itself.
static void OpenFocusSettings() {
    NSWorkspace* ws = [NSWorkspace sharedWorkspace];
    if (![ws openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.Focus-Settings.extension"]])
        [ws openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.notifications"]];
}

static void StartBlink() {
    A.blinking = true; A.blinkStart = Now();
    if (!A.tAnim) A.tAnim = Every(1 / 60.0, ^{
        if (Now() - A.blinkStart > 960) { A.blinking = false; Kill(A.tAnim); }
        Render();
    });
}

static void ResetSession(bool run) {
    A.blocks = BuildPlan(A.cfg);
    A.idx = 0; A.running = false; A.started = false;
    A.lastTick = Now();
    if (run) {
        A.running = true; A.started = true;
        if (A.cfg.openFocus) OpenFocusSettings();
    }
}
static void SetRunning(bool on) {
    if (Complete()) return;
    if (on && !A.started) {
        A.started = true;
        if (A.cfg.openFocus) OpenFocusSettings();
    }
    A.running = on; A.lastTick = Now();
}
static void Advance() {
    if (Complete()) return;
    A.blocks[A.idx].done = true;
    A.idx++;
    A.started = true;
    if (Complete()) A.running = false;
    A.lastTick = Now();
}

static void Tick() {
    unsigned long long n = Now();
    long long d = (long long)(n - A.lastTick);
    A.lastTick = n;
    if (!A.running || Complete()) return;
    Block& b = A.blocks[A.idx];
    b.elapsed += d;
    if (b.elapsed >= b.dur && !b.alerted) {
        b.alerted = true;
        StartBlink();
        if (A.cfg.autoCont) {
            long long spill = b.elapsed - b.dur;
            b.elapsed = b.dur;
            Advance();
            if (!Complete()) { A.running = true; A.blocks[A.idx].elapsed = spill; }
        }
    }
}

static void UpdateActivity() {
    NSProcessInfo* pi = [NSProcessInfo processInfo];
    bool want = A.running && !Complete();
    if (want && !A.activity)
        A.activity = [pi beginActivityWithOptions:NSActivityUserInitiatedAllowingIdleSystemSleep reason:@"Focus timer running"];
    else if (!want && A.activity) { [pi endActivity:A.activity]; A.activity = nil; }
}

// ---------------------------------------------------------------- icons
static void Icon(int kind, CGFloat cx, CGFloat cy, CGFloat s, Col c) {
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
    }
}

// ---------------------------------------------------------------- drawing
static void AddZone(int id, CGFloat x, CGFloat y, CGFloat w, CGFloat h) { A.zones.push_back({id, CGRectMake(x, y, w, h)}); }

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

static void DrawCard(CGFloat w, CGFloat h, CGFloat r) {
    for (int i = 9; i >= 1; i--) {
        CGFloat e = i * 1.7;
        FillRR(ARGB(9, 0, 0, 0), -e, -e + 5, w + 2 * e, h + 2 * e, r + e);
    }
    CGContextSaveGState(G);
    ClipRR(0, 0, w, h, r);
    CGContextDrawLinearGradient(G, CardGradient(), CGPointMake(0, -1), CGPointMake(0, h + 1), 0);
    CGContextRestoreGState(G);
    StrokeRR(ARGB(30, 255, 255, 255), 1, 0.5, 0.5, w - 1, h - 1, r - 0.5);
}

static void DrawBlink(CGFloat w, CGFloat h, CGFloat r) {
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

struct SegColors { Col fill, border; };
static SegColors SegFuture(int k) { return k == K_FOCUS ? SegColors{Hex(0x163A73), Hex(0x24539F)} : SegColors{Hex(0x12384A), Hex(0x1F5E75)}; }
static SegColors SegDone(int k) { return k == K_FOCUS ? SegColors{Hex(0x1F56AE), Hex(0x2C68C9)} : SegColors{Hex(0x1A6A86), Hex(0x2687A6)}; }

// Lays out segments across [x, x+w]; returns x positions & widths
static void LayoutSegs(const std::vector<Block>& v, CGFloat x, CGFloat w, CGFloat gap, std::vector<CGFloat>& xs, std::vector<CGFloat>& ws) {
    int n = (int)v.size();
    xs.assign(n, 0); ws.assign(n, 0);
    if (!n) return;
    CGFloat avail = w - gap * (n - 1);
    CGFloat minW = max(3.0, min(9.0, avail / n * 0.6));
    std::vector<bool> fixed(n, false);
    // iterative: pin tiny segments to minW, distribute the rest proportionally
    for (int pass = 0; pass < 4; pass++) {
        double freeDur = 0; CGFloat freeW = avail;
        for (int i = 0; i < n; i++) { if (fixed[i]) freeW -= minW; else freeDur += (double)v[i].dur; }
        bool changed = false;
        for (int i = 0; i < n; i++) {
            if (fixed[i]) { ws[i] = minW; continue; }
            ws[i] = (CGFloat)(freeW * v[i].dur / max(1.0, freeDur));
            if (ws[i] < minW) { fixed[i] = true; changed = true; }
        }
        if (!changed) break;
    }
    CGFloat cx = x;
    for (int i = 0; i < n; i++) { xs[i] = cx; cx += ws[i] + gap; }
}

static void Hatch(CGFloat x, CGFloat y, CGFloat w, CGFloat h, CGFloat r, Col base, Col stripe) {
    FillRR(base, x, y, w, h, r);
    CGContextSaveGState(G);
    ClipRR(x, y, w, h, r);
    for (CGFloat sx = x - h; sx < x + w + h; sx += 6.5) Line(stripe, 2.2, sx, y + h, sx + h, y);
    CGContextRestoreGState(G);
}

static void DrawBar(CGFloat x, CGFloat y, CGFloat w, CGFloat h, bool big) {
    CGFloat pad = big ? 4 : 0, gap = big ? 3 : 2;
    if (big) {
        FillRR(Hex(0x0E2347), x, y, w, h, 13);
        StrokeRR(Hex(0x2A64C4, 200), 1.2, x + 0.6, y + 0.6, w - 1.2, h - 1.2, 12.5);
    }
    std::vector<CGFloat> xs, ws;
    LayoutSegs(A.blocks, x + pad, w - 2 * pad, gap, xs, ws);
    CGFloat sy = y + pad, sh = h - 2 * pad;
    for (int i = 0; i < (int)A.blocks.size(); i++) {
        const Block& b = A.blocks[i];
        CGFloat r = min(big ? 8.0 : 4.0, ws[i] / 2);
        bool cur = i == A.idx;
        if (i < A.idx) {
            SegColors c = SegDone(b.kind);
            FillRR(c.fill, xs[i], sy, ws[i], sh, r);
            StrokeRR(c.border, 1, xs[i] + .5, sy + .5, ws[i] - 1, sh - 1, r);
        } else if (cur) {
            bool fb = b.kind == K_FOCUS;
            Col base = fb ? Hex(0x2563C8) : Hex(0x1C7E9E);
            Col stripe = fb ? Hex(0x3A86F5) : Hex(0x33AACD);
            Col solid = fb ? Hex(0x2F7DF2) : Hex(0x27A0C6);
            Hatch(xs[i], sy, ws[i], sh, r, base, stripe);
            CGFloat p = (CGFloat)min(1.0, (double)b.elapsed / max(1LL, b.dur));
            if (p > 0) {
                CGContextSaveGState(G);
                ClipRR(xs[i], sy, ws[i], sh, r);
                CGContextClipToRect(G, CGRectMake(xs[i], sy, ws[i] * p, sh));
                SetFill(solid); CGContextFillRect(G, CGRectMake(xs[i], sy, ws[i], sh));
                CGContextRestoreGState(G);
            }
            StrokeRR(ARGB(120, 255, 255, 255), 1, xs[i] + .5, sy + .5, ws[i] - 1, sh - 1, r);
        } else {
            SegColors c = SegFuture(b.kind);
            FillRR(c.fill, xs[i], sy, ws[i], sh, r);
            StrokeRR(c.border, 1, xs[i] + .5, sy + .5, ws[i] - 1, sh - 1, r);
        }
    }
    if (big && !Complete()) {
        const Block& b = A.blocks[A.idx];
        CGFloat p = (CGFloat)min(1.0, (double)b.elapsed / max(1LL, b.dur));
        CGFloat px = xs[A.idx] + ws[A.idx] * p;
        px = std::clamp(px, x + 3, x + w - 3);
        Line(P::text, 2, px, y - 4, px, y + h - 3);

        // callout pill
        NSString* label = b.kind == K_FOCUS ? @"Focus" : b.kind == K_LONG ? @"Long break" : @"Break";
        NSString* num = [NSString stringWithFormat:@"%d", b.round];
        CGFloat tw = TextW(label, 1, 14);
        CGFloat pw = 10 + 17 + 6 + tw + 12, phh = 25;
        CGFloat pcx = std::clamp(px, x + pw / 2, x + w - pw / 2);
        CGFloat pxl = pcx - pw / 2, pyt = y - 34;
        FillRR(P::blue, pxl, pyt, pw, phh, 9);
        CGFloat tx = std::clamp(px, pxl + 10, pxl + pw - 10);
        CGPoint tri[3] = {{tx - 6, pyt + phh - 0.5}, {tx + 6, pyt + phh - 0.5}, {tx, pyt + phh + 6}};
        FillPoly(P::blue, tri, 3);
        CGFloat ncx = pxl + 10 + 8.5, ncy = pyt + phh / 2;
        FillEllipse(P::text, ncx - 8.5, ncy - 8.5, 17, 17);
        Text(num, 0, 11, ncx, ncy + 4, P::blue, AL_C);
        Text(label, 1, 14, ncx + 8.5 + 6, ncy + 5, P::text);
    }
}

static void CircleButton(int id, CGFloat cx, CGFloat cy, CGFloat r, int icon, CGFloat iconSize) {
    bool hot = A.hover == id;
    FillEllipse(hot ? P::circleHot : P::circle, cx - r, cy - r, 2 * r, 2 * r);
    if (icon == 2)  // ring for "done" state
        StrokeEllipse(ARGB(120, 0x3D, 0x8B, 0xFF), 1.5, cx - r + 1, cy - r + 1, 2 * r - 2, 2 * r - 2);
    Icon(icon, cx + (icon == 0 ? iconSize * 0.05 : 0), cy, iconSize, P::circleIcon);
    AddZone(id, cx - r, cy - r, 2 * r, 2 * r);
}

static int MainIcon() {
    if (Complete()) return 3;
    if (Over()) return 2;
    return A.running ? 1 : 0;
}

static void IconButton(int id, int icon, CGFloat cx, CGFloat cy) {
    bool hot = A.hover == id;
    if (hot) FillRR(P::chipHot, cx - 11, cy - 11, 22, 22, 7);
    Icon(icon, cx, cy, 12, hot ? P::text : P::sub);
    AddZone(id, cx - 11, cy - 11, 22, 22);
}

static void DrawMain(CGFloat W, CGFloat H) {
    DrawCard(W, H, 28);
    Block* b = Cur();
    NSString *big, *sub;
    Col bigC = P::text;
    if (!b) {
        big = Clock(FocusedMs(), false);
        sub = @"focused · session complete";
    } else if (b->elapsed >= b->dur) {
        big = [@"+" stringByAppendingString:Clock(b->elapsed - b->dur, false)];
        bigC = P::blueText;
        sub = b->kind == K_FOCUS ? @"Time's up · extra focus" : @"Break's over · extra break";
    } else {
        big = Clock(b->dur - b->elapsed, true);
        NSString* what = b->kind == K_FOCUS ? @"focus" : b->kind == K_LONG ? @"long break" : @"break";
        if (!A.started) sub = [NSString stringWithFormat:@"Ready · %d × %d min focus", A.cfg.rounds, A.cfg.focus];
        else if (!A.running) { sub = [@"Paused · " stringByAppendingString:what]; bigC = WithA(P::text, 150); }
        else sub = [@"Left for " stringByAppendingString:what];
    }
    CGFloat bigSize = 48;
    while (bigSize > 30 && TextW(big, 0, bigSize) > W - 20 - 70) bigSize -= 2;
    Text(big, 0, bigSize, 19, 64, bigC);
    Text(sub, 2, 14, 20, 88, P::sub);
    CircleButton(Z_MAIN, W - 20 - 21, 44, 21, MainIcon(), 17);

    DrawBar(20, 134, W - 40, 44, true);

    // stats row
    CGFloat by = 204;
    NSString* f = StatClock(FocusedMs());
    NSString* e = [@"+" stringByAppendingString:StatClock(ExtraMs())];
    CGFloat x = 20;
    x += Text(@"Focused", 2, 12, x, by, P::dim) + 5;
    x += Text(f, 1, 12, x, by, P::soft) + 14;
    if (A.inside) {
        CGFloat ix = W - 20 - 9;
        IconButton(Z_CLOSE, 8, ix, by - 4); ix -= 24;
        IconButton(Z_COMPACT, 7, ix, by - 4); ix -= 24;
        IconButton(Z_SETUP, 5, ix, by - 4); ix -= 24;
        IconButton(Z_RESET, 6, ix, by - 4); ix -= 24;
        if (!Complete()) IconButton(Z_SKIP, 4, ix, by - 4);
    } else {
        x += Text(@"Extra", 2, 12, x, by, P::dim) + 5;
        x += Text(e, 1, 12, x, by, ExtraMs() > 0 ? P::blueText : P::soft);
        int total = A.cfg.rounds;
        NSString* r = Complete() ? [NSString stringWithFormat:@"%d/%d rounds", RoundsDone(), total]
                                 : [NSString stringWithFormat:@"Round %d/%d", A.blocks[A.idx].round, total];
        if (x + 10 <= W - 20 - TextW(r, 2, 12)) Text(r, 2, 12, W - 20, by, P::dim, AL_R);  // drop it if the times run long
    }
    DrawBlink(W, H, 28);
}

static void DrawCompact(CGFloat W, CGFloat H) {
    DrawCard(W, H, H / 2);
    CircleButton(Z_MAIN, 28, H / 2, 18, MainIcon(), 14);
    Block* b = Cur();
    NSString* big; Col c = P::text; NSString* lab = @"";
    if (!b) { big = Clock(FocusedMs(), false); lab = @"Done"; }
    else if (b->elapsed >= b->dur) { big = [@"+" stringByAppendingString:Clock(b->elapsed - b->dur, false)]; c = P::blueText; }
    else { big = Clock(b->dur - b->elapsed, true); if (A.started && !A.running) c = WithA(P::text, 150); }
    if (b) lab = [NSString stringWithFormat:@"%@ %d/%d", b->kind == K_FOCUS ? @"Focus" : @"Break", b->round, A.cfg.rounds];
    // the time gets the room left by the label (or the expand button): shrink it, then drop the label
    CGFloat right = (A.inside ? W - 24 - 11 : W - 18 - TextW(lab, 2, 11.5)) - 8;
    CGFloat bigSize = 25;
    while (bigSize > 19 && 55 + TextW(big, 0, bigSize) > right) bigSize -= 1;
    Text(big, 0, bigSize, 55, 36, c);
    if (A.inside) IconButton(Z_COMPACT, 9, W - 24, H / 2);
    else if (55 + TextW(big, 0, bigSize) <= right) Text(lab, 2, 11.5, W - 18, 32, P::sub, AL_R);
    // thin progress line along the bottom
    CGFloat px = 56, pw = W - 56 - 22, py = H - 9;
    FillRR(Hex(0x1F2A40), px, py, pw, 3, 1.5);
    double prog = b ? min(1.0, (double)b->elapsed / max(1LL, b->dur)) : 1;
    if (prog > 0) FillRR(b && b->kind != K_FOCUS ? Hex(0x27A0C6) : P::blue, px, py, (CGFloat)(pw * prog), 3, 1.5);
    DrawBlink(W, H, H / 2);
}

struct Row { NSString* label; int* val; int lo, hi; };
static Row Rows(int i) {
    Cfg& e = A.edit;
    switch (i) {
    case 0: return {@"Focus", &e.focus, 1, 180};
    case 1: return {@"Break", &e.brk, 1, 60};
    case 2: return {@"Rounds", &e.rounds, 1, 12};
    case 3: return {@"Long break", &e.longBrk, 1, 90};
    default: return {@"Long break every", &e.longEvery, 0, 12};
    }
}
static NSString* RowValue(int i) {
    int v = *Rows(i).val;
    if (i == 2) return [NSString stringWithFormat:@"%d", v];
    if (i == 4) {
        if (v == 0) return @"off";
        if (v == 1) return @"1 round";
        return [NSString stringWithFormat:@"%d rounds", v];
    }
    return [NSString stringWithFormat:@"%d min", v];
}

static void Toggle(int id, CGFloat x, CGFloat cy, bool on) {
    CGFloat w = 38, h = 22;
    bool hot = A.hover == id;
    FillRR(on ? (hot ? Hex(0x4A9CFF) : P::blue) : (hot ? Hex(0x34405A) : Hex(0x2A3346)), x, cy - h / 2, w, h, h / 2);
    CGFloat kx = on ? x + w - h + 3 : x + 3;
    FillEllipse(on ? P::text : P::sub, kx, cy - h / 2 + 3, h - 6, h - 6);
}

static void DrawSetup(CGFloat W, CGFloat H) {
    DrawCard(W, H, 26);
    Text(@"New session", 1, 18, 20, 40, P::text);
    Text(@"Focus blocks with breaks in between", 2, 12, 20, 58, P::sub);
    for (int i = 0; i < 5; i++) {
        CGFloat cy = 90 + i * 36;
        Row r = Rows(i);
        bool disabled = (i == 3 && A.edit.longEvery == 0);
        Text(r.label, 2, 14, 20, cy + 5, disabled ? P::dim : P::soft);
        int dz = Z_DEC0 + i, iz = Z_INC0 + i;
        CGFloat dx = 166, ix = W - 32;
        FillEllipse(A.hover == dz ? P::chipHot : P::chip, dx - 13, cy - 13, 26, 26);
        FillEllipse(A.hover == iz ? P::chipHot : P::chip, ix - 13, cy - 13, 26, 26);
        Icon(10, dx, cy, 12, *r.val > r.lo ? P::text : P::dim);
        Icon(11, ix, cy, 12, *r.val < r.hi ? P::text : P::dim);
        AddZone(dz, dx - 14, cy - 14, 28, 28);
        AddZone(iz, ix - 14, cy - 14, 28, 28);
        NSString* v = RowValue(i);
        CGFloat fs = 14;
        while (fs > 10 && TextW(v, 1, fs) > (ix - dx - 30)) fs -= 0.5;
        Text(v, 1, fs, (dx + ix) / 2, cy + 5, disabled ? P::dim : P::text, AL_C);
    }
    NSString* tl[2] = {@"Auto-continue to next block", @"Open Focus settings on start"};
    bool tv[2] = {A.edit.autoCont, A.edit.openFocus};
    for (int i = 0; i < 2; i++) {
        CGFloat cy = 272 + i * 32;
        Text(tl[i], 2, 13.5, 20, cy + 5, P::soft);
        Toggle(Z_TOG0 + i, W - 20 - 38, cy, tv[i]);
        AddZone(Z_TOG0 + i, 14, cy - 15, W - 28, 30);
    }
    // plan preview
    std::vector<Block> saved = A.blocks; int savedIdx = A.idx;
    A.blocks = BuildPlan(A.edit); A.idx = -1;
    DrawBar(20, 324, W - 40, 12, false);
    long long total = 0, foc = 0;
    for (auto& b : A.blocks) { total += b.dur / 60000; if (b.kind == K_FOCUS) foc += b.dur / 60000; }
    A.blocks.swap(saved); A.idx = savedIdx;
    NSString* tt = [NSString stringWithFormat:@"Total %@ · %@ focus", ShortDur(total), ShortDur(foc)];
    Text(tt, 2, 12, 20, 356, P::sub);

    // buttons
    CGFloat by = 372, bh = 36;
    FillRR(A.hover == Z_CANCEL ? P::chipHot : P::chip, 20, by, 92, bh, 12);
    Text(@"Cancel", 1, 14, 20 + 46, by + bh / 2 + 5, P::soft, AL_C);
    AddZone(Z_CANCEL, 20, by, 92, bh);
    FillRR(A.hover == Z_START ? Hex(0x4A9CFF) : P::blue, 120, by, W - 140, bh, 12);
    Text(@"Start session", 1, 14, 120 + (W - 140) / 2, by + bh / 2 + 5, P::text, AL_C);
    AddZone(Z_START, 120, by, W - 140, bh);
    DrawBlink(W, H, 26);
}

static void CardSize(View v, CGFloat& w, CGFloat& h) {
    if (v == V_COMPACT) { w = 206; h = 56; }
    else if (v == V_SETUP) { w = 280; h = 428; }
    else { w = 280; h = 220; }
}
static NSSize WinSize(View v) {
    CGFloat cw, ch; CardSize(v, cw, ch);
    return NSMakeSize(ceil(cw + 2 * SH), ceil(ch + 2 * SH));
}

// Keeps the card on the screen it mostly sits on (the shadow margin may hang off the edge).
static NSRect ClampToWork(NSRect f) {
    NSScreen* best = nil; CGFloat bestArea = 0, bestDist = INFINITY;
    NSPoint c = NSMakePoint(NSMidX(f), NSMidY(f));
    for (NSScreen* s in [NSScreen screens]) {
        NSRect i = NSIntersectionRect(s.frame, f);
        CGFloat area = i.size.width * i.size.height;
        CGFloat dist = hypot(NSMidX(s.frame) - c.x, NSMidY(s.frame) - c.y);
        if (area > bestArea || (bestArea == 0 && area == 0 && dist < bestDist)) { best = s; bestArea = area; bestDist = dist; }
    }
    if (!best) best = [NSScreen mainScreen];
    if (!best) return f;
    NSRect a = best.visibleFrame;
    CGFloat xlo = NSMinX(a) - SH, xhi = max(xlo, NSMaxX(a) - f.size.width + SH);
    CGFloat yhi = NSMaxY(a) - f.size.height + SH, ylo = min(yhi, NSMinY(a) - SH);  // top edge wins
    f.origin.x = std::clamp(f.origin.x, xlo, xhi);
    f.origin.y = std::clamp(f.origin.y, ylo, yhi);
    return f;
}

static void Render() { [A.canvas display]; }  // synchronous, so hit zones are current on return

static void SetView(View v) {
    A.view = v; A.hover = Z_NONE;
    NSRect f = A.win.frame; NSSize s = WinSize(v);
    NSRect n = ClampToWork(NSMakeRect(f.origin.x, NSMaxY(f) - s.height, s.width, s.height));  // keep top-left
    [A.win setFrame:n display:NO];
    Render();
}

// ---------------------------------------------------------------- menu bar item & menu
static void UpdateTray() {
    Block* b = Cur();
    NSString* t;
    if (!b) t = @"session complete";
    else if (b->elapsed >= b->dur) t = [NSString stringWithFormat:@"+%@ extra", Clock(b->elapsed - b->dur, false)];
    else t = [NSString stringWithFormat:@"%@%@%@", Clock(b->dur - b->elapsed, true),
              b->kind == K_FOCUS ? @" focus" : @" break", A.running ? @"" : @" (paused)"];
    A.tray.button.toolTip = [@"Stint — " stringByAppendingString:t];
}

// Template image echoing the app icon: a ring with one dim quadrant and a centre dot.
static NSImage* TrayImage() {
    NSImage* img = [NSImage imageWithSize:NSMakeSize(18, 18) flipped:YES drawingHandler:^BOOL(NSRect) {
        CGContextRef c = [NSGraphicsContext currentContext].CGContext;
        CGFloat cx = 9, cy = 9, r = 5.6;
        CGContextSetLineWidth(c, 2.6);
        CGContextSetRGBStrokeColor(c, 0, 0, 0, 0.35);
        CGContextAddArc(c, cx, cy, r, M_PI, 1.5 * M_PI, 0); CGContextStrokePath(c);
        CGContextSetRGBStrokeColor(c, 0, 0, 0, 1);
        CGContextAddArc(c, cx, cy, r, -0.5 * M_PI, M_PI, 0); CGContextStrokePath(c);
        CGContextSetRGBFillColor(c, 0, 0, 0, 1);
        CGContextFillEllipseInRect(c, CGRectMake(cx - 1.7, cy - 1.7, 3.4, 3.4));
        return YES;
    }];
    [img setTemplate:YES];  // `template` is a C++ keyword, so no dot syntax here
    img.accessibilityDescription = @"Stint";
    return img;
}

static void AddItem(NSMenu* m, NSString* title, int tag, bool enabled, bool checked, id target) {
    NSMenuItem* it = [[NSMenuItem alloc] initWithTitle:title action:@selector(menuAction:) keyEquivalent:@""];
    it.tag = tag; it.target = target; it.enabled = enabled;
    it.state = checked ? NSControlStateValueOn : NSControlStateValueOff;
    [m addItem:it];
}
static void FillMenu(NSMenu* m, id target) {
    [m removeAllItems];
    m.autoenablesItems = NO;
    bool comp = Complete();
    AddItem(m, A.running ? @"Pause" : (A.started ? @"Resume" : @"Start"), M_TOGGLE, !comp, false, target);
    AddItem(m, Over() ? @"Finish block  ✓" : @"Skip to next block", M_SKIP, !comp, false, target);
    AddItem(m, @"Restart session", M_RESET, true, false, target);
    [m addItem:[NSMenuItem separatorItem]];
    AddItem(m, @"New session…", M_SETUP, true, false, target);
    AddItem(m, @"Compact view", M_COMPACT, true, A.view == V_COMPACT, target);
    AddItem(m, @"Always on top", M_TOP, true, A.topmost, target);
    AddItem(m, @"Open Focus Settings", M_FOCUS, true, false, target);
    AddItem(m, A.hidden ? @"Show widget" : @"Hide widget", M_SHOWHIDE, true, false, target);
    [m addItem:[NSMenuItem separatorItem]];
    AddItem(m, @"Quit Stint", M_EXIT, true, false, target);
}

static void OpenSetup() {
    if (A.view == V_SETUP) return;
    A.backView = A.view;
    A.edit = A.cfg;
    SetView(V_SETUP);
}

static void ApplyTopmost() {
    A.win.level = A.topmost ? NSFloatingWindowLevel : NSNormalWindowLevel;
    if (!A.hidden) [A.win orderFrontRegardless];
}
static void ShowWidget() { A.hidden = false; [A.win orderFrontRegardless]; Render(); }
static void HideWidget() { A.hidden = true; [A.win orderOut:nil]; }
static void Quit() { SaveSettings(); [NSApp terminate:nil]; }

static void DoAction(int id) {
    switch (id) {
    case Z_MAIN:
        if (Complete()) ResetSession(false);
        else if (Over()) Advance();
        else SetRunning(!A.running);
        break;
    case Z_SKIP: Advance(); break;
    case Z_RESET: ResetSession(false); break;
    case Z_SETUP: OpenSetup(); return;
    case Z_COMPACT:
        A.prefCompact = A.view != V_COMPACT;
        SetView(A.prefCompact ? V_COMPACT : V_MAIN); SaveSettings(); return;
    case Z_CLOSE: Quit(); return;
    case Z_TOG0: A.edit.autoCont = !A.edit.autoCont; break;
    case Z_TOG0 + 1: A.edit.openFocus = !A.edit.openFocus; break;
    case Z_CANCEL: SetView(A.backView == V_SETUP ? V_MAIN : A.backView); return;
    case Z_START:
        A.cfg = A.edit; ResetSession(true); SaveSettings();
        SetView(A.prefCompact ? V_COMPACT : V_MAIN); UpdateTray(); return;
    default:
        if (id >= Z_DEC0 && id < Z_DEC0 + 5) { Row r = Rows(id - Z_DEC0); *r.val = max(r.lo, *r.val - 1); }
        else if (id >= Z_INC0 && id < Z_INC0 + 5) { Row r = Rows(id - Z_INC0); *r.val = min(r.hi, *r.val + 1); }
        break;
    }
    Render(); UpdateTray();
}

static void Command(int id) {
    switch (id) {
    case M_TOGGLE: SetRunning(!A.running); break;
    case M_SKIP: Advance(); break;
    case M_RESET: ResetSession(false); break;
    case M_SETUP: if (A.hidden) ShowWidget(); OpenSetup(); return;
    case M_COMPACT: DoAction(Z_COMPACT); return;
    case M_TOP: A.topmost = !A.topmost; ApplyTopmost(); SaveSettings(); break;
    case M_FOCUS: OpenFocusSettings(); break;
    case M_SHOWHIDE: if (A.hidden) ShowWidget(); else HideWidget(); break;
    case M_EXIT: Quit(); return;
    }
    Render(); UpdateTray();
}

static int HitZone(NSPoint p) {
    CGPoint l = CGPointMake(p.x - SH, p.y - SH);
    for (auto it = A.zones.rbegin(); it != A.zones.rend(); ++it)
        if (CGRectContainsPoint(it->r, l)) return it->id;
    return Z_NONE;
}
static bool IsStepper(int id) { return (id >= Z_DEC0 && id < Z_DEC0 + 5) || (id >= Z_INC0 && id < Z_INC0 + 5); }

static void RepeatFire() {
    if (A.repeatZone != Z_NONE && A.pressed == A.repeatZone && A.hover == A.repeatZone) {
        DoAction(A.repeatZone);
        if (++A.repeatCount == 1) { Kill(A.tRepeat); A.tRepeat = Every(0.07, ^{ RepeatFire(); }); }
    } else Kill(A.tRepeat);
}

// ---------------------------------------------------------------- window & input
@interface StintPanel : NSPanel
@end
@implementation StintPanel
- (BOOL)canBecomeKeyWindow { return NO; }   // never steals focus from the app you are working in
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface StintView : NSView
@end
@implementation StintView {
    NSTrackingArea* _track;
    CGFloat _scroll;
}
- (BOOL)isFlipped { return YES; }            // y grows downward
- (BOOL)isOpaque { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent*)e { return YES; }
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_track) [self removeTrackingArea:_track];
    _track = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                          options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
                                                  NSTrackingActiveAlways | NSTrackingInVisibleRect
                                            owner:self userInfo:nil];
    [self addTrackingArea:_track];
}
- (void)drawRect:(NSRect)dirty {
    G = [NSGraphicsContext currentContext].CGContext;
    CGContextClearRect(G, self.bounds);
    CGContextSaveGState(G);
    CGContextSetShouldSmoothFonts(G, false);
    CGContextTranslateCTM(G, SH, SH);
    A.zones.clear();
    CGFloat cw, ch; CardSize(A.view, cw, ch);
    if (A.view == V_MAIN) DrawMain(cw, ch);
    else if (A.view == V_COMPACT) DrawCompact(cw, ch);
    else DrawSetup(cw, ch);
    CGContextRestoreGState(G);
    G = nullptr;
}
- (NSPoint)local:(NSEvent*)e { return [self convertPoint:e.locationInWindow fromView:nil]; }

- (void)mouseMoved:(NSEvent*)e {
    if (A.dragging) {
        NSPoint c = [NSEvent mouseLocation];
        CGFloat dx = c.x - A.dragStart.x, dy = c.y - A.dragStart.y;
        if (fabs(dx) > 2 || fabs(dy) > 2) A.dragMoved = true;
        [A.win setFrameOrigin:NSMakePoint(A.winStart.x + dx, A.winStart.y + dy)];
        return;
    }
    NSPoint p = [self local:e];
    bool wasInside = A.inside;
    A.inside = true;
    int z = HitZone(p);
    if (z != A.hover || !wasInside) {
        A.hover = z;
        Render();
        z = HitZone(p);  // zones can change on first hover (icons appear)
        if (z != A.hover) { A.hover = z; Render(); }
    }
    [(A.hover != Z_NONE ? [NSCursor pointingHandCursor] : [NSCursor arrowCursor]) set];
}
- (void)mouseDragged:(NSEvent*)e { [self mouseMoved:e]; }
- (void)mouseEntered:(NSEvent*)e { [self mouseMoved:e]; }
- (void)mouseExited:(NSEvent*)e {
    if (A.dragging) return;
    A.inside = false; A.hover = Z_NONE; Render();
    [[NSCursor arrowCursor] set];
}
- (void)mouseDown:(NSEvent*)e {
    if (e.modifierFlags & NSEventModifierFlagControl) { [self rightMouseDown:e]; return; }
    if (!A.topmost) [A.win orderFrontRegardless];
    int z = HitZone([self local:e]);
    if (e.clickCount >= 2 && e.clickCount % 2 == 0) {  // double-click
        if (z == Z_NONE && A.view != V_SETUP) DoAction(Z_COMPACT);
        else if (IsStepper(z)) DoAction(z);
        return;
    }
    A.pressed = z;
    if (z == Z_NONE) {
        A.dragging = true; A.dragMoved = false;
        A.dragStart = [NSEvent mouseLocation];
        A.winStart = A.win.frame.origin;
    } else if (IsStepper(z)) {
        DoAction(z);
        A.repeatZone = z; A.repeatCount = 0;
        Kill(A.tRepeat); A.tRepeat = Every(0.38, ^{ RepeatFire(); });
    }
}
- (void)mouseUp:(NSEvent*)e {
    NSPoint p = [self local:e];
    if (A.dragging) {
        A.dragging = false;
        NSRect f = A.win.frame, c = ClampToWork(f);
        if (!NSEqualRects(f, c)) [A.win setFrame:c display:NO];
        if (A.dragMoved) SaveSettings();
        if (!NSPointInRect([self convertPoint:[A.win mouseLocationOutsideOfEventStream] fromView:nil], self.bounds)) {
            A.inside = false; A.hover = Z_NONE; Render();
        }
    } else {
        int z = HitZone(p);
        if (z == A.pressed && z != Z_NONE && !IsStepper(z)) DoAction(z);
    }
    A.pressed = Z_NONE; A.repeatZone = Z_NONE; Kill(A.tRepeat);
}
- (void)scrollWheel:(NSEvent*)e {
    if (A.view != V_SETUP) return;
    CGFloat dy = e.isDirectionInvertedFromDevice ? -e.scrollingDeltaY : e.scrollingDeltaY;  // physical direction
    int steps = 0;
    if (e.hasPreciseScrollingDeltas) {  // trackpad: one step per 12pt of travel
        if (e.phase == NSEventPhaseBegan) _scroll = 0;
        _scroll += dy;
        while (_scroll >= 12) { steps++; _scroll -= 12; }
        while (_scroll <= -12) { steps--; _scroll += 12; }
    } else steps = dy > 0 ? 1 : dy < 0 ? -1 : 0;
    CGFloat ly = [self local:e].y - SH;
    int row = (int)floor((ly - 72) / 36);
    if (row < 0 || row >= 5) return;
    for (int i = 0; i < abs(steps); i++) DoAction((steps > 0 ? Z_INC0 : Z_DEC0) + row);
}
- (void)rightMouseDown:(NSEvent*)e {
    FillMenu(A.menu, NSApp.delegate);
    [NSMenu popUpContextMenu:A.menu withEvent:e forView:self];
}
@end

// ---------------------------------------------------------------- startup
static void LoadFonts() {
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

@interface StintDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@end
@implementation StintDelegate
- (void)menuAction:(NSMenuItem*)it { Command((int)it.tag); }
- (void)menuNeedsUpdate:(NSMenu*)m { FillMenu(m, self); }

- (void)applicationDidFinishLaunching:(NSNotification*)n {
    LoadFonts();
    LoadSettings();
    ResetSession(false);

    A.view = A.prefCompact ? V_COMPACT : V_MAIN;
    NSSize s = WinSize(A.view);
    NSRect f;
    if (PrefInt(@"hasPos", 0)) f = NSMakeRect(PrefInt(@"x", 0), PrefInt(@"top", 0) - s.height, s.width, s.height);
    else {
        NSRect wa = [NSScreen mainScreen].visibleFrame;
        f = NSMakeRect(NSMaxX(wa) - s.width - 8, NSMaxY(wa) - 8 - s.height, s.width, s.height);
    }
    f = ClampToWork(f);

    A.win = [[StintPanel alloc] initWithContentRect:f
                                          styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                            backing:NSBackingStoreBuffered defer:NO];
    A.win.opaque = NO;
    A.win.backgroundColor = [NSColor clearColor];
    A.win.hasShadow = NO;                  // the card draws its own soft shadow
    A.win.hidesOnDeactivate = NO;
    A.win.releasedWhenClosed = NO;
    A.win.acceptsMouseMovedEvents = YES;
    A.win.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary |
                               NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorIgnoresCycle;
    A.canvas = [[StintView alloc] initWithFrame:NSMakeRect(0, 0, f.size.width, f.size.height)];
    A.win.contentView = A.canvas;

    Render();
    ApplyTopmost();

    A.menu = [[NSMenu alloc] init];
    NSMenu* trayMenu = [[NSMenu alloc] init];
    trayMenu.delegate = self;
    A.tray = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    A.tray.button.image = TrayImage();
    A.tray.menu = trayMenu;
    UpdateTray();

    A.tTick = Every(0.2, ^{
        Tick();
        long long sec = 0;
        if (Block* b = Cur()) sec = b->elapsed / 1000 + A.idx * 100000LL; else sec = -2;
        if (sec != A.lastShownSec) { A.lastShownSec = sec; if (!A.blinking) Render(); UpdateTray(); }
        UpdateActivity();
    });

    // pause on sleep
    [[NSWorkspace sharedWorkspace].notificationCenter addObserverForName:NSWorkspaceWillSleepNotification object:nil
        queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification*) {
            if (A.running) { Tick(); A.running = false; Render(); UpdateTray(); }
        }];
    // displays added, removed or rearranged
    [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidChangeScreenParametersNotification object:nil
        queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification*) {
            [A.win setFrame:ClampToWork(A.win.frame) display:NO]; Render();
        }];
    // a second launch asks this instance to show itself
    [[NSDistributedNotificationCenter defaultCenter] addObserverForName:kShowNote object:nil
        queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification*) { ShowWidget(); ApplyTopmost(); }];
}
- (BOOL)applicationShouldHandleReopen:(NSApplication*)app hasVisibleWindows:(BOOL)flag {
    ShowWidget(); ApplyTopmost();
    return NO;
}
- (void)applicationWillTerminate:(NSNotification*)n { SaveSettings(); }
@end

#ifdef STINT_SNAPSHOT
// Test build only: renders each view offscreen to PNGs (2x) so the drawing can be checked without a screen.
static void Snap(NSString* path) {
    NSSize s = WinSize(A.view);
    int W = (int)s.width * 2, H = (int)s.height * 2;
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    G = CGBitmapContextCreate(nullptr, W, H, 8, 0, cs, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGContextTranslateCTM(G, 0, H); CGContextScaleCTM(G, 2, -2);  // flipped, like the canvas
    CGContextTranslateCTM(G, SH, SH);
    A.zones.clear();
    CGFloat cw, ch; CardSize(A.view, cw, ch);
    if (A.view == V_MAIN) DrawMain(cw, ch); else if (A.view == V_COMPACT) DrawCompact(cw, ch); else DrawSetup(cw, ch);
    CGImageRef img = CGBitmapContextCreateImage(G);
    NSData* png = [[[NSBitmapImageRep alloc] initWithCGImage:img] representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [png writeToFile:path atomically:YES];
    CGImageRelease(img); CGContextRelease(G); CGColorSpaceRelease(cs); G = nullptr;
}
int main(int argc, const char* argv[]) {
    @autoreleasepool {
        NSString* dir = argc > 1 ? @(argv[1]) : @".";
        LoadFonts();
        printf("embedded fonts: %s\n", A.fontDesc[0] ? "yes" : "no (system fallback)");
        A.cfg = Cfg(); ResetSession(false);
        A.view = V_MAIN; Snap([dir stringByAppendingPathComponent:@"1-ready.png"]);
        A.started = A.running = true; A.blocks[0].elapsed = 7 * 60000 + 23000;
        Snap([dir stringByAppendingPathComponent:@"2-running.png"]);
        A.inside = true; A.hover = Z_SETUP; Snap([dir stringByAppendingPathComponent:@"3-hover.png"]);
        A.inside = false; A.hover = Z_NONE;
        A.blocks[0].elapsed = A.blocks[0].dur; A.blocks[0].alerted = true; Advance(); A.blocks[1].elapsed = A.blocks[1].dur + 95000;
        Snap([dir stringByAppendingPathComponent:@"4-overtime.png"]);
        A.view = V_COMPACT; Snap([dir stringByAppendingPathComponent:@"5-compact.png"]);
        A.blocks[1].elapsed = A.blocks[1].dur + 3723000; Snap([dir stringByAppendingPathComponent:@"5b-compact-hour.png"]);
        A.blocks[1].elapsed = 2 * 60000; Snap([dir stringByAppendingPathComponent:@"5c-compact-normal.png"]);
        A.view = V_SETUP; A.edit = A.cfg; A.edit.longEvery = 2; A.hover = Z_START;
        Snap([dir stringByAppendingPathComponent:@"6-setup.png"]);
        A.view = V_MAIN; A.hover = Z_NONE;
        while (!Complete()) { A.blocks[A.idx].elapsed = A.blocks[A.idx].dur; Advance(); }
        Snap([dir stringByAppendingPathComponent:@"7-complete.png"]);
    }
    return 0;
}
#else
int main(int argc, const char* argv[]) {
    @autoreleasepool {
        // single instance: hand over to the running copy
        NSString* bid = [NSBundle mainBundle].bundleIdentifier;
        if (bid) {
            for (NSRunningApplication* r in [NSRunningApplication runningApplicationsWithBundleIdentifier:bid]) {
                if (r.processIdentifier != getpid()) {
                    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:kShowNote object:nil
                                                                                 userInfo:nil deliverImmediately:YES];
                    return 0;
                }
            }
        }
        NSApplication* app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyAccessory;  // no Dock icon
        StintDelegate* d = [[StintDelegate alloc] init];
        app.delegate = d;
        [app run];
    }
    return 0;
}
#endif

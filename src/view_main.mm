// The main card, the compact pill, and the segmented session bar they share with setup.
#import "views.h"
#import "format.h"
#import "gfx.h"
#import "session.h"
#import "widgets.h"

using std::min;
using std::max;

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

void DrawBar(CGFloat x, CGFloat y, CGFloat w, CGFloat h, bool big) {
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

static int MainIcon() {
    if (Complete()) return 3;
    if (Over()) return 2;
    return A.running ? 1 : 0;
}

void DrawMain(CGFloat W, CGFloat H) {
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
        IconButton(Z_TREND, 12, ix, by - 4); ix -= 24;
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

void DrawCompact(CGFloat W, CGFloat H) {
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

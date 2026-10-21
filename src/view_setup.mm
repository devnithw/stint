// The setup card: session plan steppers, toggles, preview and start.
#import "views.h"
#import "format.h"
#import "gfx.h"
#import "icons.h"
#import "session.h"
#import "widgets.h"

using std::min;
using std::max;

Row Rows(int i) {
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

void DrawSetup(CGFloat W, CGFloat H) {
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

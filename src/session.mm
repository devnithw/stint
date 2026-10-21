// Session logic: the plan of blocks, the clock that advances it, and the timers that drive it.
#import "session.h"
#import "trend.h"
#import "window.h"

using std::min;
using std::max;

std::vector<Block> BuildPlan(const Cfg& c) {
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
bool Complete() { return A.idx >= (int)A.blocks.size(); }
Block* Cur() { return Complete() ? nullptr : &A.blocks[A.idx]; }
bool Over() { Block* b = Cur(); return b && b->elapsed >= b->dur; }
long long FocusedMs() {
    long long t = 0;
    for (int i = 0; i < (int)A.blocks.size() && i <= A.idx; i++)
        if (A.blocks[i].kind == K_FOCUS) t += A.blocks[i].elapsed;
    return t;
}
long long ExtraMs() {
    long long t = 0;
    for (int i = 0; i < (int)A.blocks.size() && i <= A.idx; i++)
        if (A.blocks[i].kind == K_FOCUS) t += max(0LL, A.blocks[i].elapsed - A.blocks[i].dur);
    return t;
}
int RoundsDone() {
    int n = 0;
    for (auto& b : A.blocks) if (b.kind == K_FOCUS && b.done) n++;
    return n;
}

NSTimer* Every(double secs, void (^fn)(void)) {
    NSTimer* t = [NSTimer timerWithTimeInterval:secs repeats:YES block:^(NSTimer*) { fn(); }];
    t.tolerance = secs * 0.1;
    [[NSRunLoop mainRunLoop] addTimer:t forMode:NSRunLoopCommonModes];  // keeps ticking while a menu is open
    return t;
}
void Kill(NSTimer* __strong& t) { [t invalidate]; t = nil; }

// Opens the Focus pane in System Settings.
// It does not start or stop a Focus itself.
void OpenFocusSettings() {
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

void ResetSession(bool run) {
    A.blocks = BuildPlan(A.cfg);
    A.idx = 0; A.running = false; A.started = false;
    A.lastTick = Now();
    if (run) {
        A.running = true; A.started = true;
        if (A.cfg.openFocus) OpenFocusSettings();
    }
}
void SetRunning(bool on) {
    if (Complete()) return;
    if (on && !A.started) {
        A.started = true;
        if (A.cfg.openFocus) OpenFocusSettings();
    }
    A.running = on; A.lastTick = Now();
}
void Advance() {
    if (Complete()) return;
    A.blocks[A.idx].done = true;
    A.idx++;
    A.started = true;
    if (Complete()) A.running = false;
    A.lastTick = Now();
}

void Tick() {
    unsigned long long n = Now();
    long long d = (long long)(n - A.lastTick);
    A.lastTick = n;
    if (!A.running || Complete()) return;
    Block& b = A.blocks[A.idx];
    b.elapsed += d;
    if (b.kind == K_FOCUS) TrendAdd(d);
    if (b.elapsed >= b.dur && !b.alerted) {
        b.alerted = true;
        StartBlink();
        [[NSSound soundNamed:@"Glass"] play];  // bell when the block's time is up
        if (A.cfg.autoCont) {
            long long spill = b.elapsed - b.dur;
            b.elapsed = b.dur;
            Advance();
            if (!Complete()) { A.running = true; A.blocks[A.idx].elapsed = spill; }
        }
    }
}

void UpdateActivity() {
    NSProcessInfo* pi = [NSProcessInfo processInfo];
    bool want = A.running && !Complete();
    if (want && !A.activity)
        A.activity = [pi beginActivityWithOptions:NSActivityUserInitiatedAllowingIdleSystemSleep reason:@"Focus timer running"];
    else if (!want && A.activity) { [pi endActivity:A.activity]; A.activity = nil; }
}

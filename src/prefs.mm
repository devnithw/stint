// Settings, stored with NSUserDefaults (~/Library/Preferences/<bundle id>.plist).
#import "prefs.h"

int PrefInt(NSString* k, int def) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:k];
    return [v respondsToSelector:@selector(intValue)] ? [v intValue] : def;
}
static void PrefPut(NSString* k, int v) { [[NSUserDefaults standardUserDefaults] setInteger:v forKey:k]; }
void LoadSettings() {
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
void SaveSettings() {
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

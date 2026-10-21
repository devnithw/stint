// What each button (Z_*) and menu item (M_*) does.
#import "actions.h"
#import "prefs.h"
#import "session.h"
#import "tray.h"
#import "views.h"
#import "window.h"

using std::min;
using std::max;

void DoAction(int id) {
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
    case Z_TREND: SetView(V_TREND); return;
    case Z_BACK: SetView(V_MAIN); return;
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

void Command(int id) {
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

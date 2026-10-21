// The menu bar item: icon, tooltip, and the menu shared with the right-click popup.
#import "tray.h"
#import "format.h"
#import "session.h"

void UpdateTray() {
    Block* b = Cur();
    NSString* t;
    if (!b) t = @"session complete";
    else if (b->elapsed >= b->dur) t = [NSString stringWithFormat:@"+%@ extra", Clock(b->elapsed - b->dur, false)];
    else t = [NSString stringWithFormat:@"%@%@%@", Clock(b->dur - b->elapsed, true),
              b->kind == K_FOCUS ? @" focus" : @" break", A.running ? @"" : @" (paused)"];
    A.tray.button.toolTip = [@"Stint — " stringByAppendingString:t];
}

// Template image echoing the app icon: a ring with one dim quadrant and a centre dot.
NSImage* TrayImage() {
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
void FillMenu(NSMenu* m, id target) {
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

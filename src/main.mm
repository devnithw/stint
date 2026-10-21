// Stint — a tiny floating focus timer for macOS.
// Cocoa + Core Graphics app; each module's header says what it holds. Build with build.sh.
//
// Concepts
//   Session : the whole plan you start (e.g. 4 rounds).
//   Round   : one Focus block, followed by a Break block (none after the last round).
//   Block   : a single Focus / Break / Long break segment shown in the bar.
//   Extra   : time you keep going after a block's timer hits zero (the stopwatch).


#import "actions.h"
#import "gfx.h"
#import "prefs.h"
#import "session.h"
#import "tray.h"
#import "trend.h"
#import "views.h"
#import "window.h"
#include <unistd.h>

static NSString* const kShowNote = @"local.stint.show";  // sent by a second launch

App A;

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
            if (A.running) { Tick(); A.running = false; TrendSave(); Render(); UpdateTray(); }
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
- (void)applicationWillTerminate:(NSNotification*)n { SaveSettings(); TrendSave(); }
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
    DrawView(A.view, cw, ch);
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
        A.inside = true; A.hover = Z_TREND; Snap([dir stringByAppendingPathComponent:@"8-hover-trend.png"]);
        A.inside = false; A.hover = Z_NONE;
        long long mins[2][7] = {{95, 140, 60, 180, 120, 30, 0}, {80, 110, 150, 90, 200, 45, 20}};
        TrendSample(mins);
        A.view = V_TREND; Snap([dir stringByAppendingPathComponent:@"9-trend.png"]);
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

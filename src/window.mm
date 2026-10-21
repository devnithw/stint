// The floating panel and its canvas: view switching, placement on screen, mouse and scroll input.
#import "window.h"
#import "actions.h"
#import "gfx.h"
#import "prefs.h"
#import "session.h"
#import "tray.h"
#import "views.h"

using std::min;
using std::max;

// Keeps the card on the screen it mostly sits on (the shadow margin may hang off the edge).
NSRect ClampToWork(NSRect f) {
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

void Render() { [A.canvas display]; }  // synchronous, so hit zones are current on return

void SetView(View v) {
    A.view = v; A.hover = Z_NONE;
    NSRect f = A.win.frame; NSSize s = WinSize(v);
    NSRect n = ClampToWork(NSMakeRect(f.origin.x, NSMaxY(f) - s.height, s.width, s.height));  // keep top-left
    [A.win setFrame:n display:NO];
    Render();
}

void OpenSetup() {
    if (A.view == V_SETUP) return;
    A.backView = A.view;
    A.edit = A.cfg;
    SetView(V_SETUP);
}

void ApplyTopmost() {
    A.win.level = A.topmost ? NSFloatingWindowLevel : NSNormalWindowLevel;
    if (!A.hidden) [A.win orderFrontRegardless];
}
void ShowWidget() { A.hidden = false; [A.win orderFrontRegardless]; Render(); }
void HideWidget() { A.hidden = true; [A.win orderOut:nil]; }
void Quit() { SaveSettings(); [NSApp terminate:nil]; }

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

@implementation StintPanel
- (BOOL)canBecomeKeyWindow { return NO; }   // never steals focus from the app you are working in
- (BOOL)canBecomeMainWindow { return NO; }
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
    DrawView(A.view, cw, ch);
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
        if (z == Z_NONE && (A.view == V_MAIN || A.view == V_COMPACT)) DoAction(Z_COMPACT);
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

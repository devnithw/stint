// Shared by every module: constants, palette, the data model, and the one global app state `A`.
//
// Concepts
//   Session : the whole plan you start (e.g. 4 rounds).
//   Round   : one Focus block, followed by a Break block (none after the last round).
//   Block   : a single Focus / Break / Long break segment shown in the bar.
//   Extra   : time you keep going after a block's timer hits zero (the stopwatch).
#pragma once
#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>
#include <algorithm>
#include <cmath>
#include <ctime>
#include <map>
#include <vector>

// ---------------------------------------------------------------- constants
static const CGFloat SH = 18;            // shadow margin (points)
enum { K_FOCUS = 0, K_BREAK = 1, K_LONG = 2 };
enum View { V_MAIN, V_COMPACT, V_SETUP, V_TREND };

enum {
    Z_NONE = 0, Z_MAIN, Z_SKIP, Z_RESET, Z_SETUP, Z_COMPACT, Z_CLOSE, Z_TREND, Z_BACK,
    Z_DEC0 = 20, Z_INC0 = 30, Z_TOG0 = 40, Z_CANCEL = 50, Z_START
};
enum {
    M_TOGGLE = 100, M_DONE, M_SKIP, M_RESET, M_SETUP, M_COMPACT, M_TOP, M_FOCUS, M_SHOWHIDE, M_EXIT
};

// ---------------------------------------------------------------- palette
struct Col { CGFloat r, g, b, a; };
constexpr Col ARGB(int a, int r, int g, int b) { return {r / 255.0, g / 255.0, b / 255.0, a / 255.0}; }
constexpr Col Hex(unsigned rgb, int a = 255) { return ARGB(a, (rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255); }
constexpr Col WithA(Col c, int a) { c.a = a / 255.0; return c; }

namespace P {
    inline constexpr Col text = ARGB(255, 255, 255, 255);
    inline constexpr Col sub = ARGB(255, 0x8C, 0x94, 0xA6);
    inline constexpr Col dim = ARGB(255, 0x6F, 0x78, 0x8C);
    inline constexpr Col soft = ARGB(255, 0xD5, 0xDA, 0xE4);
    inline constexpr Col blue = ARGB(255, 0x2D, 0x8C, 0xFF);
    inline constexpr Col blueText = ARGB(255, 0x5A, 0xA8, 0xFF);
    inline constexpr Col circle = ARGB(255, 0x1C, 0x3A, 0x6B);
    inline constexpr Col circleHot = ARGB(255, 0x25, 0x48, 0x82);
    inline constexpr Col circleIcon = ARGB(255, 0x3D, 0x8B, 0xFF);
    inline constexpr Col chip = ARGB(255, 0x1C, 0x26, 0x38);
    inline constexpr Col chipHot = ARGB(255, 0x27, 0x33, 0x4A);
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
};
extern App A;  // defined in main.mm

inline unsigned long long Now() { return clock_gettime_nsec_np(CLOCK_MONOTONIC) / 1000000ULL; }

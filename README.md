# Stint (Pomodoro Timer)

<img width="1896" height="1392" alt="Stint-screens-3x" src="https://github.com/user-attachments/assets/38aeb5a9-e402-4da7-be57-ce35750cd6de" />


A tiny floating Pomodoro focus timer. Stint pairs a customizable Pomodoro countdown with an overtime stopwatch, so you can finish your thought without losing track of how long you have worked.

> Mac version port of original app by [@SpiderNavi](https://github.com/SpiderNavi/stint) 

## Features

- **[NEW]** Weekly focus trend: this week's total, a Monday-to-Sunday breakdown, and a chart against last week.
- Movable, always-on-top floating timer with a compact pill view.
- Customizable focus periods, breaks, rounds, and periodic long breaks.
- Overtime stopwatch after the countdown reaches zero.
- Total focused time and extra time counters.
- Menu bar icon and a right-click menu. No Dock icon.
- Stays visible on every Space and over full-screen apps.
- Never takes keyboard focus away from the app you are working in.
- Pauses automatically when the Mac goes to sleep.
- Embedded Inter fonts with tabular digits for a steady countdown.
- Remembers settings, window position, and compact-view preference.

The default plan is **20 minutes focus / 5 minutes break × 4 rounds**.

## Build and run

### 1. Install the Xcode Command Line Tools

The full Xcode app is not needed. In Terminal:

```sh
xcode-select --install
```

Skip this if `clang --version` already prints a version.

### 2. Clone and build

```sh
git clone https://github.com/devnithw/stint.git
cd stint
sh build.sh
```

The script compiles a universal binary, draws the app icon, copies the fonts, and assembles `build/Stint.app`. It takes a few seconds.

### 3. Run

```sh
open build/Stint.app
```

The timer card appears near the top-right corner of the screen, and the Stint icon appears in the menu bar.

To install it, move the app to Applications:

```sh
mv build/Stint.app /Applications/
```

### Updating

Quit Stint first (menu bar icon → **Quit Stint**), then:

```sh
cd stint
git pull
sh build.sh
```

If you installed it in `/Applications`, move the new build over the old one.

## How it works

A **session** is the complete plan. A **round** contains a focus block followed by a break; the final round has no trailing break. A **block** is a focus, break, or long-break segment. **Extra** is the time spent beyond a block's countdown.

Click the main round button to start or pause. When the countdown ends, the card blinks twice and begins counting overtime; click the check button to advance. With auto-continue enabled, Stint advances automatically instead.

Drag the card to reposition it. Hover to reveal skip, restart, setup, compact, and close controls. Double-click the card to toggle compact mode. In the setup view, scroll over a row to change its value.

Right-click (or Control-click) the card, or click the menu bar icon, for the full menu:

| Menu item | Action |
| --- | --- |
| Start / Pause / Resume | Toggle the timer |
| Skip to next block / Finish block | Move to the next block |
| Restart session | Reset the current plan |
| New session… | Open the setup view |
| Compact view | Switch between the card and the pill |
| Always on top | Keep the widget above other windows |
| Open Focus Settings | Open the Focus pane in System Settings |
| Hide widget / Show widget | Hide the card while the timer keeps running |
| Quit Stint | Save settings and quit |

Hover over the menu bar icon to see the time remaining.

## Settings

Settings are saved with the standard macOS preferences system under the identifier `local.stint`. To view them:

```sh
defaults read local.stint
```

To reset everything, including the window position, quit Stint and run:

```sh
defaults delete local.stint
```

## Uninstall

Quit Stint, delete `Stint.app`, and optionally run the `defaults delete` command above. Remove it from Login Items if you added it there.

## Troubleshooting

- **`xcrun: error: invalid active developer path`**: the Command Line Tools are missing or were removed by a macOS update. Run `xcode-select --install` again.
- **Opening the app again does nothing**: Stint is already running. The second launch brings the existing widget forward. If you hid it, use the menu bar icon → **Show widget**.
- **Text uses the system font instead of Inter**: the files in `Stint.app/Contents/Resources/fonts` are missing. Rebuild with `sh build.sh`.

## Development

| Path | Purpose |
| --- | --- |
| `build.sh` | Builds `build/Stint.app`, or the snapshot test build |
| `src/` | Application source (Objective-C++, Cocoa, Core Graphics, Core Text), listed below |
| `resources/Info.plist` | App bundle metadata (identifier, version, no Dock icon) |
| `resources/fonts/` | Embedded Inter subsets and the Inter license |
| `tools/makeicon.m` | Draws the app icon at every size during the build |
| `tools/prepfonts.py` | Optional: regenerates the font subsets |
| `build/` | Build output, not tracked by git; safe to delete |

Each `.mm` file in `src/` has a header (`.h`) that declares what other files may use, with a one-line summary at the top:

| Module | Holds |
| --- | --- |
| `app.h` | Constants, view and button ids, palette, data model, and the global app state `A` |
| `main.mm` | App startup and delegate, the snapshot test entry point |
| `session` | Session plan, the clock (`Tick`), start, pause, skip, and reset |
| `actions` | What each button (`Z_*`) and menu item (`M_*`) does |
| `window` | The floating panel, view switching, placement, and mouse and scroll input |
| `tray` | Menu bar icon, tooltip, and menu |
| `views.h` | Card sizes and drawing dispatch for every view (`views.mm`) |
| `view_main.mm` | Main card, compact pill, and the segmented session bar |
| `view_setup.mm` | Setup card |
| `trend` | Daily focus totals and the weekly trend card |
| `widgets` | Shared card pieces: background, blink, buttons, hit zones |
| `gfx` | Drawing primitives, fonts, and text |
| `icons` | Button icons |
| `format` | Time and duration text |
| `prefs` | Settings storage |

To add a view, add it to `View` in `app.h`, draw it in its own file, and register it in `views.mm`. To add a button, add a `Z_*` id in `app.h`, draw it with `IconButton`, and handle it in `actions.mm`. To add a source file, add it to `SRC` in `build.sh`. To change the version number, edit `CFBundleShortVersionString` in `resources/Info.plist`.

To check the drawing without launching the app, use the snapshot build. It renders every view to PNG files at 2× scale (in `build/snaps/` by default):

```sh
sh build.sh snap
```

The prepared font files are already included, so Python is not needed for a normal build. `tools/prepfonts.py` requires FontTools and the original Inter Regular, SemiBold, and Inter Display Bold TTF files. It writes into `fonts/` under the current directory, so run it from `resources/`:

```sh
cd resources
python3 ../tools/prepfonts.py /path/to/inter-ttf-folder
```

## Project background

Created by Navindu Karunarathna with AI-assisted development. The original idea was a small, silent timer that stays visible while working, supports flexible focus/break plans, and measures time spent continuing beyond the planned focus block. The interface was subsequently updated to use embedded Inter fonts.

Stint was first written as a Windows (Win32 + GDI+) app. This repository now contains the macOS port, which keeps the same timer logic, layout, and fonts. The original Windows source is still available in the repository history, in the source archive added in commit `beb4a5e`.

The macOS build has been built and run on macOS 26 on Apple silicon. The Intel part of the universal binary is built but has not been tested on an Intel Mac.

## Font license

Inter is distributed under the SIL Open Font License 1.1; see [resources/fonts/Inter-LICENSE.txt](resources/fonts/Inter-LICENSE.txt). No separate application-source license has been selected.

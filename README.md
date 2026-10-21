# Stint (Pomodoro Timer)

<img width="1896" height="1392" alt="Stint-screens-3x" src="https://github.com/user-attachments/assets/38aeb5a9-e402-4da7-be57-ce35750cd6de" />


A tiny floating focus timer for macOS. Stint pairs a customizable Pomodoro countdown with an overtime stopwatch, so you can finish your thought without losing track of how long you have worked.

It is a native Cocoa app in a single source file, with no dependencies beyond the Xcode Command Line Tools. It runs on macOS 11 (Big Sur) or later, on both Apple silicon and Intel Macs.

## Features

- Movable, always-on-top floating timer with a compact pill view.
- Customizable focus periods, breaks, rounds, and periodic long breaks.
- Silent double-blink when a block ends.
- Overtime stopwatch after the countdown reaches zero.
- Total focused time and extra time counters.
- Optional automatic progression between blocks.
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
cd stint/src
sh build.sh
```

The script compiles a universal binary, draws the app icon, copies the fonts, and assembles `src/Stint.app`. It takes a few seconds.

### 3. Run

```sh
open Stint.app
```

The timer card appears near the top-right corner of the screen, and the Stint icon appears in the menu bar.

To install it, move the app to Applications:

```sh
mv Stint.app /Applications/
```

### Start at login (optional)

Open **System Settings → General → Login Items & Extensions**, click **+** under *Open at Login*, and choose `Stint.app`.

### Updating

Quit Stint first (menu bar icon → **Quit Stint**), then:

```sh
cd stint
git pull
cd src
sh build.sh
```

If you installed it in `/Applications`, move the new build over the old one.

### Copying the app to another Mac

Building from source on each Mac is the simplest option, because locally built apps open without warnings.

`build.sh` signs the app ad hoc, not with an Apple Developer ID. If you copy a built `Stint.app` to another Mac (AirDrop, download, chat), macOS Gatekeeper will block it on first launch. To open it anyway, go to **System Settings → Privacy & Security** and click **Open Anyway** next to the Stint message. Only do this for a build you trust. Distributing Stint to other people properly needs a Developer ID signature and Apple notarization.

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

## macOS Focus

Stint can open the Focus pane in System Settings when a session starts, so you can turn on Do Not Disturb or another Focus. It does not start or stop a Focus itself. Turn off **Open Focus settings on start** in the setup view if you don't want this.

## Settings

Settings are saved with the standard macOS preferences system under the identifier `io.github.devnithw.stint`. To view them:

```sh
defaults read io.github.devnithw.stint
```

To reset everything, including the window position, quit Stint and run:

```sh
defaults delete io.github.devnithw.stint
```

## Uninstall

Quit Stint, delete `Stint.app`, and optionally run the `defaults delete` command above. Remove it from Login Items if you added it there.

## Troubleshooting

- **`xcrun: error: invalid active developer path`**: the Command Line Tools are missing or were removed by a macOS update. Run `xcode-select --install` again.
- **Opening the app again does nothing**: Stint is already running. The second launch brings the existing widget forward. If you hid it, use the menu bar icon → **Show widget**.
- **Text uses the system font instead of Inter**: the files in `Stint.app/Contents/Resources/fonts` are missing. Rebuild with `sh build.sh`.

## Development

Everything lives in `src/`:

| Path | Purpose |
| --- | --- |
| `stint.mm` | Application source (Objective-C++, Cocoa, Core Graphics, Core Text) |
| `build.sh` | Builds `Stint.app` |
| `mac/Info.plist` | App bundle metadata (identifier, version, no Dock icon) |
| `mac/makeicon.m` | Draws the app icon at every size during the build |
| `fonts/` | Embedded Inter subsets and the Inter license |
| `prepfonts.py` | Optional: regenerates the font subsets |

The source is organised top to bottom as session logic, drawing, window and input handling, and startup. To change the version number, edit `CFBundleShortVersionString` in `mac/Info.plist`.

To check the drawing without launching the app, build the snapshot mode. It renders the main, compact, and setup views to PNG files at 2× scale:

```sh
cd src
clang++ -std=c++17 -fobjc-arc -DSTINT_SNAPSHOT stint.mm -o stint_snap -framework Cocoa -framework CoreText
mkdir -p /tmp/stint-snap
./stint_snap /tmp/stint-snap
```

The prepared font files are already included, so Python is not needed for a normal build. `prepfonts.py` requires FontTools and the original Inter Regular, SemiBold, and Inter Display Bold TTF files.

## Project background

Created by Navindu Karunarathna with AI-assisted development. The original idea was a small, silent timer that stays visible while working, supports flexible focus/break plans, and measures time spent continuing beyond the planned focus block. The interface was subsequently updated to use embedded Inter fonts.

Stint was first written as a Windows (Win32 + GDI+) app. This repository now contains the macOS port, which keeps the same timer logic, layout, and fonts. The original Windows source is still available in the repository history, in the source archive added in commit `beb4a5e`.

The macOS build has been built and run on macOS 26 on Apple silicon. The Intel part of the universal binary is built but has not been tested on an Intel Mac.

## Font license

Inter is distributed under the SIL Open Font License 1.1; see [src/fonts/Inter-LICENSE.txt](src/fonts/Inter-LICENSE.txt). No separate application-source license has been selected.

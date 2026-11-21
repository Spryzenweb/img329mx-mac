# IMG-329MX for macOS

Native macOS app for the IMG-329MX mouse (YJX-CHIP). It replaces the Windows-only
`IMG-329MX-V1.2.2.exe` configurator. Built with SwiftUI + IOKit HID, no Wine.

## Build

```bash
./build.sh
```

Output: `build/IMG-329MX.app` (universal, ad-hoc signed). Requires Xcode command line tools.

Preview the UI without the mouse:

```bash
build/IMG-329MX.app/Contents/MacOS/IMG-329MX --demo --page keys   # home, keys, dpi, macros, lighting, settings, log
```

## Features

- Button remapping for all 8 buttons: mouse, DPI, report rate, media, macOS/Windows shortcuts,
  recorded key combos, macros, disable
- Macro editor with live keyboard recording, editable delays, mouse clicks and scrolling
  (stored locally, uploaded on save)
- DPI: 6 stages (50–26000, step 50), active stage
- Polling rate: 125 / 250 / 500 / 1000 Hz
- Lighting: off, 7 colors, color cycle, breathing; sleep timeout
- LOD (1 / 2 mm), debounce (0–20 ms), ripple control, angle snap, motion sync
- Scroll direction, e-sports mode
- Battery, charging state, firmware version, live DPI-button updates
- "Günlük" page shows raw HID traffic for debugging

Settings can only be changed over USB or the 2.4 GHz dongle; they stay in the mouse when you switch to Bluetooth.

## Protocol

See [PROTOCOL.md](PROTOCOL.md).

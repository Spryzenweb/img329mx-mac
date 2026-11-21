# IMG-329MX HID protocol

Recovered by static analysis of `DeviceDriver.exe` (IMG-329MX Software 1.2.2, Inno Setup
installer) with radare2 + r2ghidra. Addresses refer to that binary.

## Transport

| Mode | VID | PID | Interface |
|---|---|---|---|
| USB cable | `A8A4` | `2255` | MI_02, usage page `FF01`, usage `0010` |
| 2.4 GHz dongle | `A8A5` | `2255` | MI_02, usage page `FF01`, usage `0010` |

64-byte output and input reports, report ID 0.

`config.xml` declares `device_type="101"`. The exe has two protocol families and picks by
device type: `< 201` uses the `0x55` protocol below (`fcn.0043b570`); `>= 201` uses a
different group-based protocol (`fcn.0043cbd0`) that this mouse does not use.

## Framing

```
request : 55 <cmd> <b2> <chk> <data[4..63]>
response: AA <cmd> ...
chk     = sum(packet[4..63]) & 0xFF      (fcn.0043b570 @ 0x43b5c0)
```

The exe waits for `AA` at byte 0 (1000 ms timeout, up to 3 tries).

## Commands

`p` = profile index, 0-based (the exe defaults to profile 1, so `p = 0`).

| cmd | request | response | exe |
|---|---|---|---|
| `03` version | `55 03 00 chk` | `AA 03`, ASCII `YJX.co.mouse…` from byte 8, version digits at 23..25 | `0x40c290` |
| `30` battery | `55 30 A5 chk 2E 00 00 p` | `[8]` percent, `[9]` charging | `0x42b2b0` |
| `0E` read config | `55 0E A5 chk 2E 00 00 p 00` | config block, layout below | `0x429350` |
| `0F` write config | `55 0F AE chk 2E 00 00 p p` + config block | `AA 0F` | `0x42ab00` |
| `21` lighting | `55 21 A5 chk 03 00 00 p 00 00 mode` | `AA 21` | `0x416850` |
| `22` DPI stage | `55 22 AE chk 03 00 00 p 00 00 stage dpiLo dpiHi` | `AA 22` | `0x42a870` |
| `23` report rate | `55 23 AE chk 03 00 00 p 00 00 rate` | `AA 23` | `0x42aa00` |
| `08` read keys | `55 08 A5 chk 20 00 00 p` | 8 × 4-byte key entries from byte 8 | `0x429350` |
| `09` write keys | `55 09 A5 chk 20 00 00 p` + 8 × 4-byte entries from byte 8 | `AA 09` | `0x42a610` (writes profiles 0..4) |
| `0D` macro data | `55 0D 00 chk len offLo offHi 00` + up to 56 bytes from byte 8 | `AA 0D` | `0x429dd0` |
| `10` macro commit | `55 10 A5 chk` | `AA 10` | `0x429dd0` |

## Config block (`0E` response / `0F` request)

| byte | field | values |
|---|---|---|
| 9 | light mode | 0 off, 1 red, 2 green, 3 blue, 4 cyan, 5 yellow, 6 purple, 7 white, 8 color cycle, 9 breathing (combobox data @ `0x42e336`) |
| 10 | report rate | 1=125, 2=250, 3=500, 4=1000 Hz |
| 11 | stage count | exe always writes 6 |
| 12 | active DPI stage | 1-based |
| 13..24 | DPI × 6 | uint16 LE, 50..26000 |
| 25..47 | unused | the exe writes per-stage RGB here, but this mouse always reads back zeros |
| 48 | scroll direction | 0 forward, 1 reverse |
| 49 | lift-off distance | 1 = 1 mm, 2 = 2 mm |
| 50 | sensor bits | `0x10` ripple control, `0x01` angle snap, `0x20` motion sync |
| 51 | debounce | ms, 0..20 |
| 52 | sleep | minutes (1, 3, 5, 10, 20, 30, 60); `FF` = never (factory value) |
| 53 | e-sports mode | 1 off, 2 on |

## Unsolicited input (`AA FA`)

Polled by the exe every 200 ms (`fcn.0042b490`). `byte[8]` selects the event:

| byte 8 | meaning |
|---|---|
| `10` | DPI button: `[9]` stage (1-based), `[10]` report rate |
| `11` | light mode `[9]` |
| `D0` | battery: `[9]` percent, `[10]` charging |
| `50` / `60` | handled elsewhere, meaning not confirmed |

Reports where `[2] == [3] == 0x38` are ignored, as are reports with `[9]` or `[10] == 0xFF`.

## Key entries (`08` / `09`)

Slots: 0 left, 1 right, 2 middle, 3 back, 4 forward, 5 DPI button, 6 wheel up, 7 wheel down.
Factory: `20 01`, `20 02`, `20 04`, `20 08`, `20 10`, `21 55`, `21 38 01`, `21 38 FF`.

| entry | function |
|---|---|
| `20 mask` | mouse button (`01` L, `02` R, `04` M, `08` back, `10` forward); `20 01 02` double click |
| `21 38 01` / `21 38 FF` | wheel up / down |
| `21 55` | factory DPI button |
| `F0 01 01/02/03` | DPI + / − / cycle |
| `F0 02 01/02/03` | report rate + / − / cycle |
| `10 mods usage` | keyboard; `mods` is the HID modifier byte (1 Ctrl, 2 Shift, 4 Alt, 8 GUI) |
| `30 lo hi` | consumer usage (e.g. `CD` play/pause, `E9` volume up) |
| `70 idx count mode` | macro; mode 0 = `count` times, 2 = repeat while held, 3 = repeat until any key |
| `00 …` | disabled |

## Macro memory (`0D` / `10`)

Up to `0x1080` bytes. Bytes 0..63 are 32 × uint16 LE offsets, one per macro, pointing at that macro's
first event; events start at `0x40`. Each event is 4 bytes `delayLo delayHi flags code`, where the delay
(ms) is waited after the event:

| flags | event | code |
|---|---|---|
| `42` / `02` | key down / up | HID usage |
| `41` / `01` | modifier down / up | HID usage `E0..E7` |
| `43` / `03` | mouse button down / up | button mask |
| `44` | wheel | `01` up, `FF` down |
| `46` | move | (not used here) |

The last event of each macro has `flags | 0x80`; an empty macro is `00 00 80 00`. The buffer is sent in
56-byte chunks with `0D` (byte 4 = length, 5..6 = offset), then `10` commits. There is no read command,
so the macOS app keeps the macros in `~/Library/Application Support/IMG-329MX/macros.json`.

## Bluetooth

Over Bluetooth the mouse enumerates as VID `2717` / PID `32B0` and exposes only the standard mouse,
keyboard and consumer collections, with no `FF01` interface. `config.xml` lists only the USB and 2.4 GHz
modes, and the exe has no Bluetooth code path, so settings can only be changed over USB or the dongle.

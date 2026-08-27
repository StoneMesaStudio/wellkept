# Wellkept — the Hardware section: findings and decisions

Working document, 2026-08-27. Eleven agents researched what a Mac can honestly report about
itself; the drive finding below was then **re-verified by hand**, because the two research teams
contradicted each other on it and the whole section hangs on the answer.

## What was measured on this Mac (M3, macOS 26)

| Thing | Verdict |
|---|---|
| **Drive wear** | ❌ **Not readable on Apple Silicon.** `IONVMeSMARTUserClient` returns `kIOReturnUnsupported` (0xe00002c7) against `AppleANS3CGv2Controller`. No wear keys anywhere in the IORegistry, none in `system_profiler`. One research agent claimed to have read 1% used / 42 TB written; that claim did not survive a hand-written C probe. **What we get is Apple's own verdict — `S.M.A.R.T. status: Verified` — and nothing else.** Intel Macs with real NVMe/SATA are a separate, untested case. |
| **Battery** | ✅ Readable, no permission. But Apple's own percentage (95% here) cannot be recomputed from the readable numbers (90–93%). Apple's figure is smoothed and stored. |
| **Temperature** | ⚠️ Readable without permission, through an undocumented route that can close in any macOS update. Moved 62 → 79 → 58 °C in three minutes on an idle-ish machine. **Nobody, Apple included, publishes what is too hot.** |
| **Thermal pressure** | ✅ `ProcessInfo.thermalState` — public, cheap, honest. Never moved even with all cores pinned. |
| **Memory pressure** | ✅ Readable, and it is the loudest true finding on this Mac: 8 GB installed, 1.4 GB swapped, **macOS force-quit three apps in eight days to free memory.** |
| **Crashes / panics** | ⚠️ ~8 days of history only. 108 files here, of which 74 are performance notices where nothing crashed. Kernel panics are readable only by administrator accounts — **by account type, not by Full Disk Access, and no permission fixes it.** |
| **Disk speed** | ⚠️ Read speed repeats to within 1.3%. Write speed swung 1,500 → 3,200 MB/s in an hour. macOS filed a report against the benchmark for exceeding the ~2 GB/day write budget it allows a well-behaved app. |
| **Full Disk Access** | ✅ **Nothing in Hardware needs it.** The section works completely for someone who taps "Finish later". |

## Asked of John

| # | Question | Answer |
|---|---|---|
| 1 | Tell someone their Mac is near the end of Apple's security updates? | |
| 2 | Ship for Intel untested, or Apple Silicon only until someone can test one? | |
| 3 | Does the demo Mac — the one in every screenshot — look healthy, or have problems? | |

## Decided without asking

- **The August-approved drive line is dead.** "94% life remaining, roughly 3 years at your
  current rate" cannot be built: the number does not exist on Apple Silicon, and the years half
  was arithmetic on a manufacturer's guess. The drive row says what Apple says, plus capacity,
  model and connection.
- **No temperature in degrees.** Report only whether macOS itself says the Mac is running hot,
  and start keeping our own record so the app can eventually say "hotter than usual for this Mac".
  The section sentence drops the word temperature.
- **Memory is promoted to a headline row.** "macOS closed 3 of your apps last week to free
  memory" is the one memory fact a person already recognises, because they watched it happen.
- **App crashes move to Apps.** Hardware keeps only kernel panics and unexpected restarts of the
  whole machine. Safari quitting says nothing about the machine's health, and 108 files of noise
  would make a healthy Mac look alarming.
- **Battery prints Apple's number**, always, and that becomes the app-wide rule: wherever Apple
  shows the same figure, we show Apple's. Anything more exact goes behind Options.
- **Worn but working is never a problem.** An old battery past its rated cycles states that
  plainly and the section stays Good. A warning nothing can clear teaches people to ignore us.
- **The speed test is its own button inside Options.** One 256 MB write, only on a press, never
  on a schedule, with a line saying what it writes. Read speed as a firm number, write speed as
  approximate. No shipped table of expected speeds — compare only against this Mac's own history.
- **A fixed row order, never sorted.** Drive · Battery · Memory · Restarts · Speed. Worst-first
  is right for findings and wrong for a fixed panel that would otherwise shuffle between runs.
- **A "what this Mac is" block at the top** — name, model, chip, memory, drive, in use since.
  Inventory, not diagnosis: it can never say Needs attention.
- **One house sentence for anything we could not read**, in two versions: "this Mac does not
  report it" and "we were not allowed to look" — only the second gets a button.
- **Copy for a repair shop shows exactly what it is about to paste**, serials included, before
  it goes on the clipboard.
- **Wellkept starts keeping its own record of every reading from first launch.** It cannot be
  back-filled, macOS keeps only days, and at least four honest sentences depend on it. It is
  added to the uninstaller's manifest the day it is created.
- **Virtual machines are detected and say so.** Every reading inside one is fiction.
- **Hardware reports one row up to Overview**, not one per finding.
- **No daily automatic check in this version.** The app quits when its window closes and there is
  no background piece. It checks on launch, and the Help page says exactly that.
- Rows are built label-above-number from the start, because a two-column table breaks at 200% text.
- **Not an administrator** → the restarts row says so; it is the one thing no permission fixes.

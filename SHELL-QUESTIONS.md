# Wellkept — the shell: full question set

Working document, 2026-08-26. Assembled by 12 agents from the build plan, `~/Sites/DESIGN.md`,
the Wellkept memory bank, and the six sibling Swift apps. It was never meant to be read start to
finish — the questions were put a few at a time, in this order, and the answers recorded here.

## Two corrections found while mining

1. **Scout (`~/Sites/scout`) is the plumbing template, not Lode or Waypoint.** It is the only
   shipped, unsandboxed, notarized, Developer-ID, direct-download macOS app in the house. It
   already has `bin/release.sh` (hardened-runtime check → notarytool → stapler → DMG),
   `App/Uninstaller.swift`, `App/Permissions.swift` and SMAppService register/unregister.
   Lode and Waypoint stay design law; Scout is plumbing law.
2. **Bundle id is `studio.stonemesa.wellkept`**, not the personal reverse-DNS id the build plan
   assumed. Verified: scout=`studio.stonemesa.scout`, lode=`studio.stonemesa.tessera`,
   travel=`studio.stonemesa.waypoint`. Only the three older App Store apps still carry the
   pre-studio prefix, and nothing new does.

---

## A. Scope and first run

| # | Question | Recommendation | Answer |
|---|---|---|---|
| A1 | Will anyone but the developer run this first version? | The developer only, for now | **No — the developer only.** Placeholder wording is acceptable in the shell |
| A2 | Welcome page before anything, or land straight on Overview? | One short page, once | **Yes — welcome page** |
| A3 | Permissions asked in a setup flow, or when a section needs them? | When needed | **SETUP FLOW** (the recommendation was overruled, 2026-08-26). The shell owns a real onboarding flow: welcome → permissions one at a time → land on Overview. Every step needs a skip that counts as an answer, and a way to re-run it from Help |
| A4 | Does the app remember what it found last time? | Yes, with the date | **Remember** |
| A5 | Does setup run again after an update or reinstall? | No | **No — unless the app was uninstalled first, then yes.** Uninstall removes the "setup finished" mark along with everything else |

## B. The window

| # | Question | Recommendation | Answer |
|---|---|---|---|
| B1 | Opening size, and how small can it be dragged? | ~1,100 × 760; floor ~1,020 × 640 | **Claude decides** (decided 2026-08-26 — explicitly handed to Claude to settle alone). Set to 1,100 × 760 opening, 1,020 × 640 floor |
| B2 | Normal title bar, or none with the name in the sidebar? | Normal | **Normal title bar** |
| B3 | Seven sections do nothing yet: finished face with the verb greyed, or "not built yet"? | Finished face | **Finished face**, real verb greyed, one line underneath saying it is coming |
| B4 | Overview: all seven every time, or only what needs you? | Only what needs you | **Only what needs you** |
| B5 | Does Overview have its own button, and is it "Check my Mac"? | Yes and yes | **Yes and yes.** "Check my Mac" is the app's main verb |
| B6 | What Overview says on a clean Mac | "Everything looks fine" + the date | **"Everything looks fine" + date — AND an audit trail** (decided 2026-08-26): the clean state must also show what was actually checked, for reassurance. Never a score |
| B7 | Red counts on sidebar rows? | No | **No** |
| B8 | Closing the window: quit, or stay running? | Quit until a menu-bar icon exists | **Quit while there is no menu-bar icon; once the icon exists and is on, closing hides instead.** The rule the user learns: if the icon is there, the app is still there |
| B9 | Full screen allowed, and does content spread on a big display? | Full screen yes; column stays 700 pt, centred | |

## C. Permissions and trust

| # | Question | Recommendation | Answer |
|---|---|---|---|
| C1 | Refused Full Disk Access — keep working reduced, or park? | Keep working | **Keep working**, each section says plainly what it could not see |
| C2 | May Overview say "fine" when it could not see everything? | No | **No.** The headline says it could not check everything and names what it missed |
| C3 | Where does "a permission is off" live? | Row in Overview + a line in the affected section | **Agreed, no stripe** — and, decided 2026-08-26, it must say plainly that the results are compromised, carry a link to turn the permission on, and explain as much as it needs to. Explanation here is wanted, not clutter |
| C4 | Background helper installed in the shell, or when a feature needs root? | Wait | **Wait.** Setup asks for Full Disk Access with a working "Finish later"; the helper is never mentioned until a feature needs root. **The shell ships no helper code** |
| C5 | Does the app ever raise a refused permission again on its own? | Never | **Never** |
| C6 | Uninstall: what does it touch? | — | **Ask the user about quarantine at uninstall: restore, or move to a location of their choosing** (decided 2026-08-26 — never decide it for them, never leave it buried). Remove settings. **Never touch backups**, just say where they are |
| C7 | Does anything leave the Mac? | — | **Nothing leaves unless the user presses something, except the update check.** Named on the welcome page. Update checking necessarily tells each vendor a copy exists here — unavoidable, so say it. Crowdsourced stability reports stay deferred to v2 |

> ⚠️ **C7 was superseded on 2026-08-27.** The absolute "nothing leaves your Mac" wording was
> Claude's invention and it was struck. What the promise is actually about: not scraping user
> data, not violating privacy, not collecting contact information for marketing. Information that
> leaves the computer to benefit the person's experience and the app's functionality is disclosed
> and optional — **inform and consent**. The shape is now: say what is never done, then name every
> departure with its switch and its cost. The
> canonical sentences live in `Core/Sources/WellkeptCore/Privacy.swift` and nowhere else. See
> `APPS-QUESTIONS.md`, question 1.

## D. Look

| # | Question | Recommendation | Answer |
|---|---|---|---|
| D1 | System font, or Avenir like Lode and Waypoint? | — | **Avenir default, system font selectable in Settings** (decided 2026-08-26). Already the house pattern: Lode `App/Support/Theme.swift:331` and Waypoint `App/Shared/Theme.swift:221` both read `fontFamily` defaulting to "Avenir". Port it, including the Avenir button and segmented-control replacements — native controls ignore a custom font. Avoid Waypoint's wiring bug (`WaypointSettings.swift:31`): the setting was consulted app-wide and settable nowhere |
| D2 | One bronze, or a quiet colour per section? | One bronze | **One bronze** |
| D3 | Where bronze actually appears | — | **Selected sidebar row · the main button · section headings. Nothing else** |
| D4 | Ship petrol and slate on day one, or bronze only? | Bronze only | **Bronze only** |
| D5 | Check the stethoscope icon at Dock and 16-pt sizes before the shell ships with it? | Yes — it has never been tested small | |

## E. Words (the vocabulary every screen inherits)

| # | Question | Recommendation | Answer |
|---|---|---|---|
| E1 | The word for a thing Wellkept finds | — | **"Problem"** (decided 2026-08-26 — plainer than "issue"). Used ONLY where something is actually wrong. Things Wellkept merely reveals — a large folder, an old file — are never called problems and get no collective noun |
| E2 | The status words for a section | — | **Good · Needs attention · Not checked** |
| E3 | The name beside the Apple logo (About…, Hide…, Quit…) | "Wellkept" | |
| E4 | The seven one-line section sentences | Claude drafts all seven, the words get edited on review | |

## F. Settings and help

| # | Question | Recommendation | Answer |
|---|---|---|---|
| F1 | What is in Settings on day one? | — | **Appearance · colour strength · text size · Permissions page** (each permission listed with a button to the right pane in System Settings). Nothing else |
| F2 | What is in the Help menu on day one? | — | **Wellkept Help · Report an Issue · Support this project · (separator) Uninstall Wellkept** |
| F3 | Real help text now, or when sections work? | — | **A short real page now:** what it is, what it never does, how to remove it |
| F4 | Where do downloads and release notes live? | — | **Page on stonemesastudio.com; file on GitHub Releases** (matches Scout). The updater bakes this address in permanently |
| F5 | Public repo from the first commit? | Yes | **Yes** |

## G. Raised late, worth asking

| # | Question | Recommendation | Answer |
|---|---|---|---|
| G1 | A switch that fills the seven sections with invented sample results? | Yes | **Yes — build it.** Pattern exists in Scout `App/DemoData.swift` |
| G2 | Where do "Ignore"d things go, and how are they taken back? | Its own list in Settings, restorable | |
| G5 | **The app's own log** — raised 2026-08-26: the dated history of every check Wellkept has ever run exists, but NOT on Overview. Where does it live? | Undecided — park until a section needs it | |
| G3 | Can the health report be printed, saved or sent? | — | **Save as PDF and Print**, once Overview has content |
| G4 | Command-Q while a check is running | Stop and quit; nothing is ever mid-write in v1 | |

---

## Decided without asking (technical)

- `studio.stonemesa.wellkept`; helper `studio.stonemesa.wellkept.Helper` if it ever ships.
- XcodeGen `project.yml` only, `.xcodeproj` gitignored; `WellkeptCore` SwiftPM package;
  scheme explicitly declared with a wired test action (Lode shipped 19 builds whose gate
  never ran a test because the scheme was auto-generated).
- Swift 6, strict concurrency complete, hardened runtime, no sandbox, String Catalog from
  commit one, macOS 14 deployment target, built with Xcode 26, re-checked on macOS 27.
- Hand-rolled sidebar in an `HStack` with a fixed `.frame(width:)` — both design-law apps do
  this and it sidesteps the centred-detail-band bug. System materials underneath so macOS 27
  restyles it free.
- Port verbatim: Lode's `Space.swift`, the `AppearanceMode`/`AppearanceHost`/`\.palette` half
  of `Palette.swift`, `ColorMath.swift`, `StableScrollView`; Waypoint's `EmptyStateView`;
  Lode's `ColorRuleGuardTests` **before the first view file exists**.
- Text Size scales type **and** the outer spacing steps (DESIGN.md §14.1) — cheap now,
  near-impossible to retrofit across seven faces.
- One `.sheet` / one `.alert` / one `.fileImporter` slot on the root, routed by an
  `Identifiable` enum; all navigation state hoisted above the `.id(typeKey)` boundary.
- Every `x-apple.systempreferences:` deep link in one file — macOS 27 is exactly the release
  that renames those anchors.
- Uninstall order fixed by macOS: `unregister()` → leftovers → trash the bundle last.
  Never `sfltool resetbtm`; it wipes every app on the machine.
- Preferences and stored state written through one manifest the uninstaller reads, so the
  uninstaller cannot go stale when a section adds a file.
- Persisted enum raw values permanent and separate from user-visible labels from commit one.
- Sparkle 2.9.x via SwiftPM, EdDSA key in Keychain before the first release; compare bundle
  version against the registered helper at every launch.
- Copy Scout's `bin/rebuild-and-launch.sh` + `make-launcher.sh` (Desktop applet, refuses a
  build whose signature is wrong — an unsigned build gets no Full Disk Access and would
  cheerfully report a healthy Mac) and Waypoint's ViewShots harness + `bin/make-shots.sh`.
- `bin/preflight.sh` as the union of the four drifted house copies.
- Permission and helper flows tested on a clean VM, never on a machine carried across years of
  macOS upgrades: grants and helper state accumulated there are not what a new user has.
- No widget, daemon or menu-bar-extra target in the shell; shapes reserved in `project.yml`.

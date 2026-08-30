# Wellkept — the Apps section: findings and decisions

2026-08-27. Six agents, all read-only, measured on this Mac (M3, macOS 26.6.2, 31 apps).
Uninstalling is **not** in this round — nothing is ever deleted, and the quarantine engine does
not exist yet. Apps ships read-only, like Hardware and Security.

## What the measurements killed

| Planned feature | Verdict |
|---|---|
| **Sparkle appcasts** — the plan's headline update mechanism, described there as covering "most non-MAS Mac software" | ❌ **Covers 1 app out of 29 here.** Of six real vendor feeds fetched, three refused an unknown checker outright (403/400/404) and the two that worked disagree about which entry is newest — BBEdit's lists a 2011 version first, Hazel's mixes two products so "newest" is a paid upgrade. **Dropped.** That was bad research in the plan, not a decision anyone made. |
| **CVE matching** — "an old app with a known vulnerability gets a specific named warning" | ❌ **Not buildable.** Of five ordinary Mac apps checked against the US vulnerability database, two are absent entirely, one lists nothing newer than a decade ago, and one confuses a code editor with its plugins. Mostly silent and occasionally wrong is the worst combination. |
| **Abandoned apps** at a 2-year threshold | ⚠️ **No reliable source.** "When the developer last shipped" needs the App Store (9 of 31 apps) or Sparkle (1). "Apps you have not opened" reports nothing at all for 6 of 31 — including Keynote and Teams, both demonstrably run. At the 2-year threshold this Mac produces an empty list. |
| **Gatekeeper assessment** (`spctl`) | ⛔ **Banned.** 3 minutes 9 seconds for 29 apps, and it is slow *because* it asks Apple about each app without a local ticket — checking your apps would report your apps to Apple. Reading who signed an app takes 1.3 seconds and answers the question better. |
| **Verifying signatures** | ⛔ 11 of 31 apps "fail" — 8 purely because Finder tags were added, one because LibreOffice writes cache files inside itself on first run. **Not one has been tampered with.** We read who signed an app; we never claim to verify it. |

## The honest coverage number

31 apps installed. 24 in scope (6 are TestFlight builds, Safari ships with macOS). **A real
current version is obtainable for 13 — 54%.** Strip Apple's own apps and Xcode and the
third-party rate is **8 of 19, 42%**. This Mac flatters the number. "Covers most of a normal
Applications folder" is not true and is not to be said anywhere in the app or its site.

## Numbers a naive tool would print, and why they are wrong

- **422 bundles.** 294 are macOS itself, 81 are Xcode build products and Automator droplets in the
  home folder, 12 under /Library, 7 nested inside other apps. The number a person recognises is
  **31**. Take LaunchServices' line on what is an app; never re-derive it from file paths.
- **108 crash files → ZERO real app crashes**, once Apple's own telemetry, iOS Simulator
  internals, performance notices where nothing crashed, and reports apps file about themselves
  while still running are removed.
- **7.6 GB of "leftovers" → about 350 MB genuinely orphaned.** 95% belongs to software running
  right now. Six "orphaned browser profiles" belong to an extension that is installed and working.
- **Chrome looks two versions behind and is current.** Google ships to a percentage of users at a
  time; the version at the top of their public list was serving to nobody.
- **Apple's own store says Pages is 15.3 while the installed copy says 15.3.1.** A plain
  "is it different" test calls 3 of 9 App Store apps outdated and advises downgrading Pages,
  Numbers and Keynote.

## Two live examples of why we do not sweep

- `~/Library/Application Support/Herd` has no app, no Spotlight entry, and looks like textbook
  dead weight. **It is a working PHP and Composer install, in daily use.** "No app owns it" does not
  mean "nothing needs it".
- Chrome's provable files come to 5.8 MB. The real figure is about 5.9 GB, in a folder called
  "Google" that matches neither the app's name nor its identifier. A single "this app and
  everything it owns" total would be a guess dressed as a fact.

## Decided

| # | Question | Decision |
|---|---|---|
| 1 | Update checking, and the "Nothing leaves your Mac" wording | **The absolute promise was Claude's wording, and it was struck 2026-08-27.** The thing being promised is about not scraping user data, not violating privacy, not collecting contact information for marketing: no data is collected and sold. Information that leaves the computer to benefit the person's experience and the app's functionality is disclosed and optional — and, exactly like refusing Full Disk Access, switching it off costs functionality. **Inform and consent**, not an absolute. So: update checking ships. The welcome page says what is never done — no collection, no selling, no account, no marketing — and names each thing that does leave, with a switch. |
| 2 | A hardcoded list of ~15 makers' version pages | **No — skipped, and disclosed** (2026-08-27). Makers release updates frequently, so a hardcoded list of their version pages is a standing maintenance promise, and that is a responsibility we are not taking on. Coverage drops from 13 apps to about 9 on this Mac, and the section says so plainly rather than implying it looked everywhere. |
| 3 | Abandoned apps as a finding | **Dropped.** Shown as plain facts on the app's own line, where a blank is harmless and nothing is being accused. |

## Decided without asking

- **Five fixed rows**, never re-sorted: Everything installed · macOS · Updates · Apps that stopped
  working · Removed apps that left things behind. A "what is installed" block above them.
- **Only real apps are listed**: /Applications, ~/Applications, /Applications/Utilities and
  /System/Applications. The other 391 bundles are one line behind Options.
- **Safari is added by hand.** It is absent from Apple's own inventory — a symlink into the
  Preboot Cryptex with restricted/hidden flags — and it is the 4th most-launched app here.
- **Intel-only apps are a plain labelled fact on the app's line**, no countdown, no "will stop
  working", never a problem colour. This cuts the other way from the Hardware ruling on security
  updates, deliberately: nothing about a Rosetta app is a security matter, macOS 26.4 already
  warns at launch, and only the developer can act.
- **Apps never turns Overview amber this round.** Without vulnerability data we can never say an
  old app is dangerous, and a version behind is not something wrong.
- **The Overview line always carries its denominator**: "4 of the 13 apps we could check have a
  newer version", never a bare count that hides the 11 we could not check.
- **The self-updating list survives that "no" to the maker list, and the distinction is the
  maintenance cost.** A vendor version endpoint breaks often — a changed URL or format means a
  wrong answer or none — which is the responsibility that was declined. A list of apps *known to update
  themselves* changes rarely (an app seldom stops self-updating) and fails soft. Keep the second,
  drop the first.
- **Update checking is inform-and-consent, not silently on.** The first time Apps runs it says
  what checking involves — asking Apple and a few makers whether a newer version exists — and
  offers to do it or not. The answer is remembered and lives in Settings. Not a wall, not a
  default nobody was told about.
- **A short list of self-updating apps ships** (Chrome, Firefox, VS Code, Claude and the like) so
  their rows say "keeps itself up to date" rather than "cannot be checked". Opposite messages;
  collapsing them makes a working Mac look neglected.
- **Version comparison is never a plain `!=`.** 13 of 18 apps carry a hazard: "02.06.00.51",
  dates-as-versions, Apple's marketing string lagging the shipped one. Where the comparison is not
  confident, the row says we could not tell rather than guessing.
- **Apps does not run on launch.** The inventory call alone takes 7–8 seconds.
- ⚠️ **CORRECTED 2026-08-27: the leftovers row DOES need Full Disk Access.** A build agent walking
  `~/Library/Containers` and `~/Library/Group Containers` raised the macOS *"would like to access
  data from other apps"* prompt on a real screen — attributed to Xcode, because the code was running
  under the test harness. That gate is real and it applies to Wellkept too.
  **So: Wellkept never touches another app's container unless Full Disk Access is already granted.**
  Without it the leftovers row reports the house sentence and offers the button; with it, the row
  works. Everything else in Apps — the inventory, versions, update checks, crashes — still needs no
  permission at all. **Wellkept must never be the cause of that prompt**: an unexplained dialog from
  a background process is the exact trust failure this product exists to avoid.
- **Leftovers are shown for removed apps only, and never totalled as one number.** The removal
  half waits for quarantine; the hooks are named now so this screen is not torn up later.

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
  dead weight. **It is John's PHP and Composer.** "No app owns it" does not mean "nothing needs it".
- Chrome's provable files come to 5.8 MB. The real figure is about 5.9 GB, in a folder called
  "Google" that matches neither the app's name nor its identifier. A single "this app and
  everything it owns" total would be a guess dressed as a fact.

## Asked of John

| # | Question | Answer |
|---|---|---|
| 1 | Does update checking ship this round, and is it on or off by default — and approve the replacement wording for "Nothing leaves your Mac"? | |
| 2 | Ship a hardcoded list of ~15 app makers' version pages, and accept updating it as a chore on every release? | |
| 3 | Abandoned apps: drop as a finding and show "last opened" / "last released" as plain facts instead? | |

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
- **A short list of self-updating apps ships** (Chrome, Firefox, VS Code, Claude and the like) so
  their rows say "keeps itself up to date" rather than "cannot be checked". Opposite messages;
  collapsing them makes a working Mac look neglected.
- **Version comparison is never a plain `!=`.** 13 of 18 apps carry a hazard: "02.06.00.51",
  dates-as-versions, Apple's marketing string lagging the shipped one. Where the comparison is not
  confident, the row says we could not tell rather than guessing.
- **Apps does not run on launch.** The inventory call alone takes 7–8 seconds.
- **Nothing in Apps needs Full Disk Access**, so it works completely for someone who tapped
  "Finish later". Only the uninstaller, later, will need it.
- **Leftovers are shown for removed apps only, and never totalled as one number.** The removal
  half waits for quarantine; the hooks are named now so this screen is not torn up later.

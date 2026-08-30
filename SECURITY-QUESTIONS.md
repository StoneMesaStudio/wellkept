# Wellkept — the Security section: findings and decisions

2026-08-27. Six agents, all read-only. ⛔ Note for future rounds: an earlier run put a system
password box on the screen of the machine being measured, with `sfltool dumpbtm`. Banned, along
with everything else that can raise an authorization dialog. **If a fact needs elevation, that is
the finding.**

## What was measured (M3, macOS 26.6.2, English, administrator account)

| Thing | Verdict |
|---|---|
| **Who can watch you** | ⚠️ **Without Full Disk Access this screen is empty, not partial.** 11 of 12 permissions read exactly zero; only Location reads without it. This is the strongest true reason to grant FDA, and setup was selling it on storage. |
| **Firewall** | ✅ `system_profiler SPFirewallDataType -json` — on/off, stealth, logging, the whole per-app allow list, one call, no dialog. The preference file every article names is **gone in macOS 26**. |
| **Boot & system protection** | ✅ `SPiBridgeDataType -json` + `csr_check()`. Unprivileged, no dialog. Apple-silicon only — **untested on Intel, which we ship to.** |
| **What macOS already found** | ⚠️ `OSLogStore` from inside a signed app — verified working, no entitlement, no shelling out. But the window is **about 14 days and set by how chatty the Mac has been**, and it is invisible to non-administrator accounts. Takes ~6 seconds: the slowest read in the app. |
| **Login Items & Extensions** | ❌ Apple's own list is gated behind root + a tool that raises a password box. We build our own from the startup files and **say plainly it can differ from Apple's**. |
| **FileVault** | ⚠️ We can say the door is locked. We cannot say whether there is a key, or who can unlock it — both need an admin password. |
| **Sharing services** | ⚠️ **We can prove one is ON. We can never prove one is off.** Never print "off" for Screen Sharing, Remote Login or Remote Management. |
| **Lockdown Mode** | ❌ No readable state anywhere. That row says "this Mac does not report it", never "off". |
| **emond · periodic** | ❌ Gone entirely in macOS 26. Shipping those checks would mean two rows that always say clean because there is nothing to find. |

**What a real, ordinary Mac produced on the day of this research:** a sharing service listening and
reachable on the local network · a shared folder with guest access · one XProtect Remediator plugin
cancelled part-way through that morning's scan. None is a crisis, and the copy has to read that way.
Two browser extensions installed deliberately, and wanted, could both read every site visited — which
is the point of that row: the answer is usually "this is fine, and you should know about it".

## Two bugs found in code already shipped — **both fixed 2026-08-27**

1. **`BatteryReader.swift:555` compares Apple's English words.** `system_profiler` **localises its
   values** — and French collapses "Fair" and "Poor" both to *Réparation recommandée*, so normal
   wear and service-recommended become indistinguishable in both directions. The keys are safe;
   only the values are translated. Read keys, and where a value must be compared, reverse-map it
   through the reporter's own world-readable `Localizable.loctable`.
   **Fixed:** `App/Support/AppleWords.swift` does the reverse map and is shared with the Security
   readers. Where a language genuinely collapses two meanings, it returns the ambiguity; the
   battery row takes the safer reading and says the doubt out loud.
2. **`Unreadable.stillComplete` is true only for `.notReported`.** Every root-only Security fact
   is `.notPermitted`, which sets `CheckRecord.complete = false` — on 100% of Macs, including a
   flawless one. Overview would say "I could not see everything" for ever, with no way to clear
   it. **That is the warning-nobody-can-clear the whole app exists to avoid.** Needs a third
   state: refused-but-you-could-grant-it (incomplete, with a button) versus nothing-can-grant-this
   (complete, no button).
   **Fixed:** `Unreadable` now has three cases — `.notReported`, `.notPermitted` (Full Disk
   Access: incomplete, with a button) and `.notGrantable` (macOS reserves it for an administrator
   or for nobody: complete, no button). Raw values were **added, not renumbered**. Kernel panics
   and memory reports on a standard account moved to `.notGrantable`.

## Settled — 2026-08-27

| # | Question | Decision |
|---|---|---|
| 1 | Malware scan this round, or after quarantine exists? | **After.** A scan that finds something today has nowhere to put it. |
| 2 | Startup items and browser extensions in Security now, or wait for Apps? | **Now**, as two read-only rows. Apps reuses the work later. |
| 3 | The nine amber conditions — anything to strike? | **Keep all nine**: FileVault off · firewall off · Gatekeeper weakened · system protection off · boot security reduced · automatic security updates off · automatic login on · an app holding camera/mic/screen whose signature no longer matches what was approved · a permission still held by an app that is no longer installed. Everything else is a plain fact with no colour. |

## Decided without asking

- **Row order, fixed, never sorted:** Protections · Who can watch you · What starts on its own ·
  Browser extensions · What can reach this Mac · What macOS has already found.
- **A "what is protecting this Mac" block at the top** — FileVault, system protection, Gatekeeper,
  secure boot, XProtect data version and when it last updated. Inventory, never a verdict.
- **The screen is labelled for what it lists** — camera, microphone, screen and control — not
  "Who can watch you". Same rows, different temperature: that title tells someone they are being
  watched before they have read a line, and for almost everyone nothing is wrong.
- **Good never stands alone.** It always carries its scope and its window: "the protections we can
  see are on; macOS found nothing in the last 12 days." **The word "safe" never appears as a
  verdict** — we are not watching in real time and must not imply it.
- **FileVault off** states the fact, links Apple's pane, and puts the recovery-key sentence in the
  row itself, because we cannot tell whether a key exists. Never the words "you should". It is the
  only advice in the app that can cost someone every file they own.
- **Managed Macs are detected** (enrolment reads free and unprivileged). Every imperative is
  dropped, organisation-set rows are labelled as such, and **a management fact is never a
  problem**. Otherwise a health check becomes an accusation about someone's employer aimed at a
  person who cannot act on it.
- **Full Disk Access refused → the watch screen collapses to one sentence**, and Location is
  hidden too. One populated row surrounded by refusals reads as "we checked and found almost
  nothing", which is the thing we promised never to say.
- **Count real startup items, never files.** Two of the seven startup files on this Mac are empty
  stubs Google left behind; a tool that counts files says "Google runs 2 things at login" and
  nothing runs. That is exactly the scare other cleaners sell.
- **Setup's Full Disk Access ask now leads with camera, microphone and screen**, with storage
  second. It is the only permission the app ever asks for and the wording decides whether people
  grant it. "Finish later" is untouched.
- **Security does not run on launch.** Its log query is ~6 seconds, the slowest read in the app.
  It runs on a press, and shows that it is still looking.
- **Wellkept holds Full Disk Access, so Wellkept appears in its own list.** Say so rather than
  filter ourselves out.
- **"Some scanners did not finish" is the ordinary case**, not an alarm — one of ~20 plugins was
  mid-flight on a clean Mac today. The copy treats it as ordinary.
- Drop emond and periodic. Keep LaunchAgents/Daemons, login items, cron, configuration profiles.
- Every `x-apple.systempreferences:` link stays in the one file it already lives in.

## Still untested, and named rather than discovered

- Not one line of this research ran on a **standard (non-administrator) account** — the account
  type on exactly the family and work Macs this section is for.
- The whole boot-security block is **Apple-silicon only** and nobody has run any of it on Intel,
  which we decided to ship to.
- A new Full Disk Access grant **does not apply to an already-running app** — macOS offers
  "Quit & Reopen". Someone who taps Finish later, grants it, and comes back finds the section
  still saying it was not allowed. It reads as a broken app, and the app is right.

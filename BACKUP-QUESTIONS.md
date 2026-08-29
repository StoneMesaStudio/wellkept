# Wellkept — the Backup section: findings and the verdict

2026-08-29. Six agents. **Nothing was written to any drive**, no volume was created or modified,
and Time Machine was not touched.

## The verdict, and how John changed it

**The research verdict was: a backup engine cannot honestly ship in version one.** The reason was
never effort and never the privileged helper — it was that **no restore has ever been performed**,
and there was no hardware to perform one on.

⭐ **John removed that blocker on 2026-08-29 by agreeing to buy a spare drive and rehearse a real
restore. So the engine IS built** — with the rehearsal as the gate before it is offered to anybody.
Everything below stands as the reason that gate exists.

- **No restore has ever been performed**, and the claim the whole design rests on — that Migration
  Assistant accepts a data-only APFS volume — is **unverified, with evidence against it**: Apple's
  own string inside Migration Assistant reads *"Volume does not contain an installation of macOS or
  OS X."*
- **The whole-Mac backup is impossible unprivileged**: 320,465 of the 361,714 files outside the home
  folder are root-owned, and an ordinary program cannot set an owner (`lchown` returns `EPERM`).
- **Without Full Disk Access a backup contains no mail, no messages, no photos, no contacts, no
  Safari data and no Trash** — not partial, *nothing* — and macOS refuses **silently, with no
  error**. That is the list of things people actually restore.
- **Half a backup is worse than none.** It converts a risk somebody knows about into a belief they
  never check.

**What ships regardless, and what the section leads with**: the shell already said it, written
before any of this research — *"Check whether your files are backed up, and what is not covered."*
Time Machine's real state, what is not covered, and the printed Recovery Plan are all measured and
none of it is untested. **They are also the only part that helps John today**, so they are built
first and the engine is built behind them.

## Decided without asking: the privileged helper stays closed

It buys **less than the plan assumed**, and the accounting is now precise:

| What we thought it unlocked | What is actually true |
|---|---|
| Creating the destination volume | **Not needed.** If the person erases the drive as APFS in Disk Utility, the whole drive already *is* that volume. Choosing "APFS (Encrypted)" hands us encryption at rest with no code from us. |
| Hourly backups and backup-on-connect | **Not needed.** That is a **Login Item**, not a helper — `SMAppService.agent`, no password, no root, listed in System Settings ▸ Login Items where it can be switched off. **The plan conflated "needs a background piece" with "needs root"; they are unrelated.** |
| Copying the system files | True — and **every file still unreadable even with permission granted is machine bookkeeping**: daemon databases, temp caches, Spotlight indexes, mail spools. **Not one document, photo, or installed app.** `/Applications` reads fine today. |

## Corrected: what is actually wrong with this Mac's backup

**I told John on 2026-08-28 that "Time Machine cannot reach JDS Backup". That was misleading.**
Verified directly today:

- `AutoBackup = 0` — **automatic backups are switched off.**
- The destination *is* configured, and the drive is simply **not plugged in** (`/Volumes` holds only
  Macintosh HD).
- Last successful backup: **25 August**. Four backups in three months.

**"Your backup is off and nobody told you" is both truer and more useful than "your backup is
broken."** It is also exactly the finding this section exists to produce.

## The measurements

| Finding | Consequence |
|---|---|
| **Inside the home folder, 586,642 of 586,643 files are the user's own.** A copy there is byte-and-metadata perfect. | The engine, when it is built, backs up the home folder. |
| **72.2 GB of this Mac's files are in the cloud and not on the disk** — 65.4 GB of `~/Documents/Media` (Desktop & Documents syncing) plus 6.5 GB of Google Drive. | Backing them up means downloading 72 GB onto a Mac with 95 GB free. **Time Machine has the same hole and never mentions it.** Name and skip, never download by default. |
| **One line is the safety net against the worst failure.** With the dataless-materialise policy off, a copy of a cloud-only file **fails outright** rather than writing an empty one. | The engine cannot produce a backup that looks complete and is not. ⚠️ A zero-byte cloud file "succeeds", so completeness is judged by the file flag, never the return code. |
| **Change detection is cheap and unprivileged** — 120,426 changes replayed from Apple's own journal in 5.2 seconds, none dropped. Full walk fallback: 34 seconds for 991,153 files. | Not the hard part. |
| **`copyfile` is lossless for xattrs, ACLs, resource forks, flags and compression** — but loses the creation date, launders the download-provenance tag, inflates sparse files (500 MB became 500 MB of real blocks) and ignores hard links. **All four are repairable with one extra unprivileged call each.** | The copy is solvable. The restore is not, yet. |
| **The recorded snapshot fallback is dead twice over**: mounting a snapshot needs root, and `tmutil localsnapshot` only works on volumes already in a Time Machine set — so on a Mac with no destination it produces nothing. | **Strike it from the plan.** |
| **macOS 26 moved the FileVault recovery key out of Apple escrow into the Passwords app.** "I can get it back with my Apple ID" is no longer true. | Wellkept can never read the key — but it can make the person press Show and write it down **while the Mac still works**. Nobody else says this. |
| **Migration Assistant refuses a backup made on a newer macOS than the machine being restored to.** | The printed plan records the macOS version and is **reprinted when it changes**. It is a document with a lifetime. |
| **On Apple silicon, Recovery never reads an installer from your backup drive** — it downloads its own. The 18.4 GB installer helps in exactly one case: another working Mac and bad internet. | Do not ship an installer on the drive by default. |
| **`~/Library/CloudStorage/GoogleDrive-…` is indistinguishable from a local folder** by every test this app uses — same filesystem, same device as `~/Documents`. Reading it timed out and killed a scan. | Had it succeeded it would have downloaded the whole Drive. Detect it by name and refuse. |
| **"Time Machine copies serially" is out of date** — macOS 26's backupd is parallel. It still gives away ~42% of throughput to throttling and runs on efficiency cores. | Do not put the serial claim anywhere a reviewer can read it. |

## Asked of John

| # | Question | Answer |
|---|---|---|
| 1 | Defer the copier to phase two? | **No — build it** (John, 2026-08-29). The deferral was conditional on never being able to test a restore, and he removed that condition by answering 3. **The gate is a real erase-and-restore rehearsal on real hardware, not a green test suite.** Nothing in the engine is offered to anybody until that rehearsal has been walked. |
| 2 | Take a Login Item? | **Yes** (John, 2026-08-29). A small part of Wellkept that keeps running quietly — `SMAppService.agent`, **no password, no root**, listed in System Settings ▸ Login Items where it can be switched off, and off is still a complete app. It does three things: back up hourly while the drive is connected, start a backup the moment the drive is plugged in, and notice when it has been nine days. **This ends "the app quits when its window closes"** — that sentence must come out of the Help page and anywhere else it appears. ⚠️ **Untested and load-bearing:** if that piece does not inherit the app's Full Disk Access, anything it does on a schedule would silently skip mail, messages and photos. **Prove it before it copies anything.** |
| 3 | A spare drive and an afternoon for a real erase-and-restore rehearsal? | **Yes** (John, 2026-08-29). **This is the gate**, in writing. Not a passing test suite — a real drive, a real backup, a real Migration Assistant restore. His existing drive is not usable: it holds 489 GB of Time Machine backups and is the only backup he has. |

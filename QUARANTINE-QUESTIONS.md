# Wellkept — the quarantine engine: findings and decisions

2026-08-28. Six agents, measured on throwaway files in a scratch directory; nothing real was
touched. This is the piece every remaining destructive action depends on, and the one place where
being wrong loses somebody's files.

## The findings that decide the design

| Finding | Consequence |
|---|---|
| **Quarantine frees zero bytes.** Measured: setting aside 391 MB across 100,000 files moved free space by **−8 KiB**. A same-volume move re-points an inode; the bytes never leave the disk. | Storage may **never** say "freed" or "reclaimed" after a quarantine. A person checks About This Mac within a minute and is right to distrust everything else we say. |
| **There is exactly one safe move: rename on the same volume.** Atomic, instant regardless of size, and it preserves everything measured — creation date, mode, ownership, ACLs, every xattr, resource fork, BSD flags, compression, sparseness, inode. **Every copy-based alternative loses something**: `clonefile` drops ACLs; `copyfile` loses the creation date and launders the download-provenance xattr. | **The store lives on the same volume as the file, always. Cross-volume quarantine is not supported.** Every hazard found — hard-link splitting, sparse files inflating 6,000×, partial copies, hours behind a progress bar, running out of space mid-batch — exists only on the cross-volume path. |
| **The macOS Trash cannot be the holding pen.** Finder's Put Back lives in an undocumented `.DS_Store` blob, and trashing several files quickly leaves only the **first** with a working Put Back (Apple radar open ten years). | We keep our own store and our own record. |
| **Everything unmovable is knowable before trying**, with no root and no dialog: `lstat().st_flags` gives the restricted/immutable/datavault/dataless flags, `statfs().f_flags` gives read-only. | A path blocklist goes stale every macOS release; flags travel with the file. Never guess by path. |
| **The obvious same-volume test is wrong.** `st_dev` is identical for the sealed System volume and the writable Data volume, and Foundation calls both "Macintosh HD" — even for `/System/Library`. | Only `statfs()` and `f_mntfromname` separate them. |
| **A symlinked parent component is the failure class that ends the product** — deleting through `Caches → RealAppSupport` destroys the real file. | `renamex_np` with `RENAME_NOFOLLOW_ANY` refuses with `ELOOP` instead of following. Scanning is already safe; the move half was not. |
| **Plain `rename(2)` silently destroys whatever occupies the destination.** | `RENAME_EXCL` refuses instead. A collision, a re-run batch, or a restore into a re-used path would otherwise destroy the exact file the engine exists to protect. |
| **Path strings are not identity here.** The filesystem is case-insensitive *and* normalisation-insensitive: `CaseTest.txt` is found at `casetest.TXT`, and an NFD spelling opens the NFC file. | A record holding only a path is not holding an identity. |
| **Moving a file a running program holds open succeeds silently** and the program keeps writing into the quarantined copy. Nothing errors; the app breaks hours later on its next open-by-path. | Check what is open before moving, and say so. |
| **Without a privileged helper**, quarantine reaches the home folder and `/Applications` (root:admin, group-writable — so the ordinary uninstall case works) and essentially nothing else. | `/Library` and its LaunchDaemons are out of reach this round, and the row says so. |
| **Free space is an estimate even after a real delete** — this Mac carries a local Time Machine snapshot whose blocks stay allocated. | Never promise a figure. Measure before and after and report what actually came back. |
| **Every documented catastrophe in this field shares one shape: the target was chosen by something other than identity.** Adobe deleted the alphabetically-first hidden folder at the disk root. Pearcleaner's orphan detector matched vendor names and flagged live data. Apple Music deleted 122 GB of local originals because a cloud copy was inferred. | Identity, never name. Never "no app claims it, so it is dead". |

## Fixed on the spot

**The ledger was written with a truncate-in-place.** `StorageManifest.write` used a plain
`write(to:)`: a badly-timed crash left half a JSON array, which decodes to nothing — every
quarantined file orphaned with no record of where it came from, while every screen said quarantine
was empty. Now `.atomic`. Committed 2026-08-28 before anything else was built on it.

**Still open in that file:** `records()` returns `[]` for a permissions failure, a corrupt ledger
and a fresh install alike — which breaks the app's own "never report zero because we could not
look" rule in the one place where zero means somebody's files are unaccounted for.

## Decided

| # | Question | Decision |
|---|---|---|
| 1 | At thirty days, what actually happens? | **30 CALENDAR days**, not days-the-app-was-open (decided 2026-08-28), **and the user chooses**: *auto-delete at 30 days* or *manual delete at 30 days*, set in Settings. Manual is the default. Note the one wrinkle: with no background piece, "auto" can only act the next time Wellkept is opened, and it says what it removed. That is still the user's own standing instruction, not the app acting unbidden, which is why it does not break "nothing changes the Mac on a schedule". |
| 2 | iCloud files — refuse outright, or allow with a warning? | **Allow, with the warning** (decided 2026-08-28): one line, *"This also removes it from your iPhone and iPad."* Refusing would block the most ordinary finding in the product on any Mac with Desktop & Documents sync on. |
| 3 | What does Storage say when 40 GB is set aside and free space does not move? | **Never the word "freed".** Before: "Set aside 40 GB. Nothing is deleted and no space comes back until you empty the quarantine." After: a permanent row — "40 GB set aside — oldest is 12 days old" — with the Empty button on it. The real number is measured after the delete, never promised before. |

## What quarantine actually is, settled 2026-08-28

The question that reframes the feature: why would anybody press this button? What is the context?

**Quarantine is not "free up space". It frees nothing.** It is the first half of deleting
something, with a month to change your mind. The sequence is: set it aside → nothing on the Mac
changes size → empty the quarantine → the space comes back.

Two consequences the screens must carry:
- **If the disk is full today, quarantine is the wrong button.** Wanting the space back now means
  quarantine and then empty, deliberately, in one sitting. Storage has to say that rather than let
  somebody quarantine 40 GB and watch nothing happen.
- **The iCloud warning is really about the gap.** For those thirty days the file is off the
  person's other devices while still occupying space on the Mac. That is the fact worth knowing
  before pressing the button, and it is what the one line is for.

**Open, deliberately deferred to the Storage section:** machine junk and a person's own files are
not the same act. Junk is a genuine set-it-aside-and-forget-it. A 12 GB video the person picked is
a deliberate two-step delete. The two should probably not read identically on the Storage face,
and that is settled there rather than guessed here.

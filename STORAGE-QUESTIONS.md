# Wellkept — the Storage section: findings and decisions

2026-08-28. Six agents, reading only, measured on this Mac. **This is the first section that
offers to touch anything**, and the biggest in the product.

## Two side effects of the research itself, disclosed

1. **Reading files updated their "last accessed" date.** 2,012 files now read as accessed today.
   Nothing of the owner's content changed and no file moved — but it is a change to filesystem
   metadata, and the promise was read-only. **The consequence for the product is real:** that date
   can never be used to find "old files", because our own scan would poison it. If we ever want it,
   it must be captured in the first pass before anything is opened.
2. **Comparing files pulled 524 of them down from iCloud**, turning a 36-second scan into over nine
   minutes and using the owner's bandwidth to fill the disk we are meant to be emptying. There is a
   one-line flag that makes such a read fail instantly instead, and it works. **Wellkept must set
   it on every read, always.**

## Something true about this Mac, right now

**Time Machine cannot reach "JDS Backup"**, and one local snapshot from **25 August** is stuck as a
result. Verified: `tmutil listlocalsnapshots /` returns exactly one, dated 2026-08-25.

**The measured consequence:** deleting any file on this Mac older than 25 August 06:25 frees
**zero bytes** — not because of quarantine, but because the snapshot still references those blocks.
How much space a delete returns now depends on the file's age: written today, 98% comes back;
yesterday, 74%; May, 12%; a July video folder, 3.6%.

Wellkept is the only tool that can tell somebody this. It is also why our numbers will look
pessimistic beside everyone else's.

## The measurements that decide the build

| Finding | Consequence |
|---|---|
| **Free space has two answers, 68 GB apart.** Finder says 179 GB; `df`, `du` and our own scan all say 111 GB. The gap is space macOS is holding back — 27 GB of iCloud documents it would evict, caches, and that snapshot. | Whichever we show, we disagree with something. See question 1. |
| **"How big is it" and "what would I get back" are different true numbers, up to 150× apart.** `~/Documents/Media` reads **80 GB** by name, **14.8 GB** on the disk, **0.5 GB** recoverable today. | The face carries **two** numbers, never one. |
| **The size every other disk tool shows is wrong by 56% here**, and unstable — it swung 11% between runs minutes apart. Size-on-disk moved 0.2%. | We show size on disk. |
| **15,593 files in the home folder look like 72 GB and occupy zero bytes** — they are in iCloud. | Sorting "largest files" the obvious way puts files that are not here at the top. |
| **A full scan takes about 12 seconds**, not minutes. | Be honest rather than theatrical, and never promise a time — the first scan after a restart has never been measured. |
| **Never scan from `/`.** It counts the disk twice and reports 501 GB used on a 494 GB drive. | Scan the Data volume. |
| **A 1.3 GB audiobook is sitting in `~/Library/Caches` right now**, filed under a store number. | Any cleaner that treats "Caches" as a category deletes somebody's audiobooks. **Location is not evidence.** The classifier decides per item. |
| **"Older than 30 days" is not a safety net.** Measured, it picks the audiobook first and protects only 4% of Xcode build output. | It survives as an annoyance filter — "do not make me re-download something I used this week" — and **never as the reason anything is ticked**. |
| **The Herd trap is live on this machine.** A 90 MB folder in Application Support with no app, no receipt, no Spotlight entry, untouched 4.5 months: every orphan heuristic fires at once, and it is the owner's PHP. | Identity, never absence of evidence. |
| **Without Full Disk Access, 54 folders in the home directory cannot be read** — including the Trash and the Photos library, usually the two biggest wins. | Say "I was not allowed to look". Never a zero. |
| **Duplicates are a tidiness finding, not a space finding.** In `~/Documents` the whole prize is 387 MB across 633 separate judgement calls; across the home folder, 12,021 groups, **94% inside project folders where deleting one breaks a build**. | Never sold as a way to free space. |
| **There is no honest way to pick which duplicate is "the original".** Four real pairs here each defeat a different rule — including a photo whose dates a past copy destroyed, so "keep the oldest" picks the wrong one. | We never choose. |
| **On APFS two "copies" may be one file.** A clone shares its blocks: deleting one frees nothing. | A clone pair is not a duplicate and must not be counted as one. |
| **30 GB of iOS simulator runtimes cannot be quarantined at all** — root-owned, read-only disk images, so no 30-day undo is possible. | Report them; offer no button. |
| **"Last opened" is blank for 61% of large files here**, and 123 files in one sample share one timestamp stamped by a batch job. | A fact on a row. Never a finding. **Never** "you haven't opened this in seven years". |
| **The numbers will never add up.** Our scan of live files totals 244 GB; macOS says 357 GB is used. The missing 113 GB is the snapshot, the folders we could not read, and filesystem overhead. | Every competitor invents an "Other" slice to hide this. **We name it and explain it.** |

## Asked of John

| # | Question | Answer |
|---|---|---|
| 1 | Lead with 111 GB (true, 68 GB below Finder) or 179 GB (agrees with Finder)? | |
| 2 | Should setting aside machine junk and setting aside one of your own big files look and behave differently? | **Yes — two ceremonies, same four verbs.** Junk: tick a batch, one press, done, and the row afterwards says "13 GB set aside". A person's own file: one at a time, **never pre-ticked**, with a sheet stating the arithmetic before the press — "this will not make your Mac emptier today; to get the 12 GB back you also have to empty the quarantine" — and both buttons on that sheet. |
| 3 | Cut "similar photos" from version one? | **Cut.** The metric cannot separate two useful frames from two near-identical ones; Apple already ships duplicate detection inside Photos and it merges rather than deletes; and touching a Photos library from outside is how libraries get corrupted. Byte-identical photos are still found by the ordinary duplicate finder. |
| 4 | Does Storage say the Time Machine snapshot problem out loud, even though Backup does not exist yet? | **Yes** — one flat line on the face, no button. It is the reason almost nothing here frees space, so leaving it out would make our own numbers look broken. |

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Darwin
import Foundation
import WellkeptCore

//  Scanner.swift
//  Wellkept — App/Storage
//
//  ⭐ **The one walk. Everything else in the Storage section reads what this produced.**
//
//  It goes over the Data volume once, records what it saw, and hands back aggregate facts plus a
//  stream of entries. It classifies nothing: `Origin` — machine junk or a person's own files — is
//  somebody else's decision, and `Entry` deliberately has no field for it. What this file owns is
//  narrower, and it is the part everything downstream depends on being right: **which bytes are
//  actually on this disk, whose name they are counted under, and what we were not allowed to see.**
//
//  ## ⚠️ The measurements this file is built around
//
//  Taken by hand on an M3 running macOS 26.6.2, read-only, 2026-08-28. Most were taken while
//  writing this file; the rest come from `STORAGE-QUESTIONS.md`.
//
//  1. **Asking Foundation for the iCloud keys makes the walk four times slower.** Measured over
//     200,886 files in `~/Sites`: the key set below takes **6.0 s**, and adding
//     `.isUbiquitousItemKey` — or `.ubiquitousItemDownloadingStatusKey`, either one alone — takes
//     **24.8 s**. That is about 92 µs per file spent asking a daemon something a `stat` already
//     answers. Neither key is fetched here. See `cloudStanding(datalessFlags:mightNotBeHere:)`.
//  2. **A file that is not on this Mac is `SF_DATALESS`, and the flag is the only proof.** Four
//     measured iCloud photos read `flags=0x40000060`, `st_blocks=0`, `st_size=2.9 MB`. **A
//     sparse file reads the same in every respect except the flag** — a 100 MB sparse file made for
//     the test reads `blocks=0, size=104857600, flags=0x0`. So "a size but no blocks" is the cheap
//     candidate test and the flag is the answer. Deciding on the numbers alone would file somebody's
//     sparse disk image under "in iCloud, using no space here", and then offer to set aside a file
//     that is very much here.
//  3. **A hard link counted twice is worth real money.** `~/Sites` totals **13.11 GB** when every
//     name is counted and **12.65 GB** by `du`, which counts each inode once — 460 MB of difference
//     inside one folder. Deduplication here is by volume and inode, and only inodes whose link
//     count is above one are remembered, so the set stays small.
//  4. **An APFS clone is two inodes sharing one set of blocks, and this walk counts it twice.**
//     Verified with `cp -c`: two files, different inodes, `st_blocks=392` each, one copy on the
//     disk. `du` counts it twice as well. There is no cheap syscall that separates a clone from a
//     real second copy — `ATTR_CMNEXT_CLONEID` looked like the answer and is not: once either half
//     is written to, two files that are **not** clones of each other came back carrying the same
//     id. So this is stated rather than fixed. See `Survey.honestyNotes`.
//  5. **The `descend` check costs about 17 µs a folder** — `lstat` 1.2, `statfs` 0.7, the volume
//     UUID 5.2, the parent-chain walk 8.9, measured over 4,000 real folders. It is called on every
//     directory anyway. A second, faster copy of the policy living in this file is precisely what
//     `ScanPolicy` says not to build, and 17 µs is a cheap price on the one question where being
//     wrong destroys somebody's files.
//  6. **Foundation's enumerator beats a hand-rolled `readdir` + `fstatat` loop** — 6.0 s against
//     6.9 s on the same 200,886 files, because it batches through `getattrlistbulk` underneath.
//     The hand-rolled version was written first and thrown away.
//  7. **Without Full Disk Access, 54 folders in this home directory cannot be read** — including
//     the Trash and the Photos library, usually the two biggest wins on any Mac. Every one of them
//     is collected by name. **Never a zero.**
//  8. **⚠️ A full scan is about a minute, not twelve seconds.** Measured end to end on this Mac
//     with this code, optimised build: **56.7 s** for **983,868 files and 234,340 folders** across
//     the five roots. The twelve seconds in `STORAGE-QUESTIONS.md` is `du` on the home folder
//     alone — a third of the files, no policy check at any folder, and no entry built for anything.
//     The gap is not waste: 234,340 `descend` calls is about 7 s of it, and it is the check that
//     keeps the walk out of somebody's mail. **Nothing may print a time**, and progress matters
//     more than it would have at twelve seconds. See `ScanPolicy.Running`.
//  9. **The same run: 142.55 GB accounted for, 39.62 GB of it recoverable today, 68 folders
//     refused.** Every one of the refused folders — Documents, Desktop, the Trash, the Photos
//     library, iCloud Drive's own folder — is refused for want of Full Disk Access, and **every
//     dataless file on this Mac lives inside one of them**. So the walk reported no iCloud holding
//     at all, which is the correct answer to what it was allowed to see and the wrong answer about
//     the Mac. It is also why "I was not allowed to look" is a sentence and never a zero.
//
//  ## ⭐ What this file will not do
//
//  - **It never reads a file's contents.** Not once, not for a hash, not for a comparison. The
//    duplicate finder is the only thing in the section with a reason to, and `ScanPolicy` is what
//    lets it.
//  - **It never asks for the last-accessed date.** Our own research scan rewrote 2,012 of them.
//  - **It never starts at `/`.** That counts the disk twice: 501 GB used on a 494 GB drive.
//  - **It never decides `Origin`.** `Entry` has no such field, so a scanner that "just marks the
//    caches" cannot exist without somebody adding the field on purpose and being seen doing it.

// MARK: - The walk

enum Scanner {

    // MARK: ── ⭐ Where it goes ────────────────────────────────────────────────────────────────

    /// ⭐ **The five places on the Data volume, in everyday spelling.**
    ///
    /// Named rather than discovered, and named the way a person and `ScanPolicy` both spell them.
    /// The alternative — walking `/System/Volumes/Data` itself — is one line shorter and quietly
    /// unsafe: every path underneath then reads `/System/Volumes/Data/Users/ada/…`, while every
    /// entry in `ScanPolicy.neverOffered` is written `Library/Mail`, `.Trash`, `Library/Keychains`.
    /// Not one of them would match, and the scan would offer buttons on somebody's mail.
    ///
    /// Verified 2026-08-28: all five report `/dev/disk3s5`, the Data volume. Any that does not
    /// exist, or that turns out to be on another disk, is dropped by `descend` rather than guessed
    /// at.
    ///
    /// ⚠️ `/Users` rather than the home folder, because it also covers `/Users/Shared` and every
    /// other account on the Mac — which we cannot read, and which is then **reported** as a place
    /// we could not read instead of vanishing out of the arithmetic.
    static func roots(home: URL = StorageManifest.home()) -> [URL] {
        let named = [
            "/Users",        // everybody's home folders, this one included
            "/Applications", // the apps
            "/Library",      // support, caches and logs shared by every account
            "/opt",          // Homebrew and friends
            "/usr/local",    // the older third-party prefix
        ]
        let volume = Movable.volume(of: ScanPolicy.root(home: home).path(percentEncoded: false))
        return named
            .map { URL(filePath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
            .filter { ScanPolicy.descend(into: $0, stayingOn: volume, home: home).isAllowed }
    }

    /// Why the walk does not simply start at the volume's own mount point.
    static let whyNotTheVolumeItself =
        "Every path under /System/Volumes/Data is spelled differently from the one a person sees, "
        + "so no rule about the Trash, the mail or the keychains would match."

    /// ⚠️ **The keys, and the two that are missing on purpose.**
    ///
    /// This is `ScanPolicy.resourceKeys` — the section's declared set — minus two, plus two. Never
    /// a different idea of what a size is.
    ///
    /// - **Added**: `.fileIdentifierKey`, the inode, which is half of `ItemIdentity` and the only
    ///   way to count a hard link once; and `.linkCountKey`, which is how we know to look.
    /// - **Left out**: `.isUbiquitousItemKey` and `.ubiquitousItemDownloadingStatusKey`. Either one
    ///   alone takes the walk from 6.0 s to 24.8 s (measurement 1), and `st_flags` answers the same
    ///   question for nothing. `.contentAccessDateKey` is absent from both sets and always will be.
    static let keys: Set<URLResourceKey> = ScanPolicy.resourceKeys
        .subtracting([.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        .union([.fileIdentifierKey, .linkCountKey])

    // MARK: ── What one run is asked to do ───────────────────────────────────────────────────────

    /// The whole instruction for one walk, so that nothing adjustable lives inside the walk itself.
    struct Plan: Sendable, Hashable {

        /// Where to start. Overlapping roots are safe — no inode is ever counted twice.
        let roots: [URL]

        let home: URL

        /// ⭐ **The snapshot standing, read once before the walk and applied to every file.**
        ///
        /// This is what makes "how big is it" and "what would I get back" two numbers instead of
        /// one. The default is `.couldNotBeRead`, which promises that **nothing** comes back: a
        /// walk nobody handed a reading to under-promises rather than over-promises.
        let snapshots: SnapshotStanding

        /// ⚠️ Hidden files are **included** by default. Skipping them under-reports a project by
        /// most of its weight, since `.git` is usually the largest thing in a source folder.
        let includeHidden: Bool

        /// How deep folder totals are kept. Depth counts from each root: `/Users` is 0,
        /// `/Users/ada` is 1, `/Users/ada/Documents` is 2.
        let folderDepth: Int

        /// A package deeper than `folderDepth` is still recorded when it is at least this big. A
        /// Photos library or a Logic project is one thing to a person wherever it happens to sit.
        let notableFolderBytes: Int64

        /// How many of the largest things to keep. Everything else is counted and forgotten, which
        /// is what keeps a walk of a million files inside a few megabytes of memory.
        let largestKept: Int

        init(roots: [URL],
             home: URL = StorageManifest.home(),
             snapshots: SnapshotStanding = .couldNotBeRead,
             includeHidden: Bool = true,
             folderDepth: Int = 3,
             notableFolderBytes: Int64 = 50_000_000,
             largestKept: Int = 200) {
            self.roots = roots
            self.home = home
            self.snapshots = snapshots
            self.includeHidden = includeHidden
            self.folderDepth = folderDepth
            self.notableFolderBytes = notableFolderBytes
            self.largestKept = max(1, largestKept)
        }

        /// The ordinary plan: the whole Data volume, with the snapshot standing applied.
        static func wholeDisk(home: URL = StorageManifest.home(),
                              snapshots: SnapshotStanding = .couldNotBeRead) -> Plan {
            Plan(roots: Scanner.roots(home: home), home: home, snapshots: snapshots)
        }

        var enumerationOptions: FileManager.DirectoryEnumerationOptions {
            includeHidden ? ScanPolicy.walkOptionsIncludingHidden : ScanPolicy.walkOptions
        }

        /// The one or two places on the refusal list that are not even measured — macOS itself and
        /// the system's own bookkeeping. Taken from `ScanPolicy`, worked out once per walk instead
        /// of asked of every folder, because asking costs a dozen string comparisons and there are
        /// a hundred thousand folders.
        var placesNotEvenMeasured: [String] {
            ScanPolicy.neverOffered
                .filter { !$0.stillMeasured }
                .map { $0.place.hasPrefix("/")
                        ? $0.place
                        : home.appending(path: $0.place).path(percentEncoded: false) }
        }
    }

    // MARK: ── ⭐ One thing the walk saw ─────────────────────────────────────────────────────────

    /// ⭐ **One entry, with both numbers already on it, and no field for whose it is.**
    ///
    /// `bytes` is a `Bytes` — size on disk *and* what would come back today — worked out against
    /// the plan's snapshot standing at the moment the entry was seen. There is no initialiser that
    /// takes a single figure, so nothing downstream can build a row out of half the truth.
    struct Entry: Sendable, Hashable, Identifiable {

        /// Volume plus inode. ⚠️ A path is not an identity on this filesystem.
        let identity: ItemIdentity

        /// As the filesystem spelled it on the way past. Never the thing an action is decided on —
        /// that is `identity`, and the engine checks it again before it moves anything.
        let path: String

        let name: String
        let kind: ItemKind

        /// ⭐ Both numbers: what it takes up, and what a delete would return today.
        let bytes: Bytes

        /// ⚠️ **What it looks like, which is not a size we stand behind.** Kept for exactly one
        /// purpose: 15,593 files on this Mac look like 72 GB and occupy nothing, and the gap between
        /// this and `bytes.onDisk` is how the section knows to say so.
        let apparentBytes: Int64

        let cloudStanding: CloudStanding

        /// Last changed — the date the recoverable arithmetic was done against.
        let modifiedOn: Date?

        /// How many names this inode has. Above one means a hard link.
        let linkCount: Int

        /// ⭐ **False when these blocks were already counted under another name.** A hard link's
        /// second name is a real thing worth showing, and its bytes are not a second helping.
        let countsTowardTheTotal: Bool

        /// Depth below the root it was found under: 1 for a root's own children.
        let depth: Int

        var id: String { "\(identity.volumeDevice)#\(identity.inode)#\(path)" }

        var isFolder: Bool { kind == .folder || kind == .bundle }

        /// Whether Storage may draw a button on this at all. Asked when a row is built rather than
        /// stored, because the answer costs a dozen string comparisons and a walk sees half a
        /// million things.
        func mayBeOffered(home: URL = StorageManifest.home()) -> Bool {
            ScanPolicy.mayOfferToActOn(path, home: home)
        }

        /// ⚠️ **`origin` defaults to `.yours`, for the same reason it does on `Item` itself.** A
        /// caller who forgets the argument produces something nobody may pre-tick and nobody may
        /// sweep, which is the safe direction to be wrong in.
        func item(origin: Origin = .yours,
                  reason: String,
                  handling: Handling = .notCheckedYet,
                  lastOpenedOn: Date? = nil) -> Item {
            Item(identity: identity,
                 path: path,
                 name: name,
                 bytes: bytes,
                 kind: kind,
                 origin: origin,
                 cloudStanding: cloudStanding,
                 handling: handling,
                 modifiedOn: modifiedOn,
                 lastOpenedOn: lastOpenedOn,
                 reason: reason)
        }
    }

    // MARK: ── A folder, totalled ────────────────────────────────────────────────────────────────

    /// A folder and everything under it, rolled up as the walk left it.
    ///
    /// This is what the row "what is using the space" is built from, and it carries both numbers for
    /// the same reason every other total does: one measured media folder is **14.8 GB on disk** and
    /// **0.5 GB back today**, and a face showing one of those is a face telling half the truth.
    struct FolderTotal: Sendable, Hashable, Identifiable {
        let identity: ItemIdentity
        let path: String
        let name: String
        let depth: Int
        let isPackage: Bool
        let bytes: Bytes
        /// How many files are inside it, at any depth.
        let files: Int
        let modifiedOn: Date?

        var id: String { path }

        func item(origin: Origin = .yours,
                  reason: String,
                  handling: Handling = .notCheckedYet) -> Item {
            Item(identity: identity,
                 path: path,
                 name: name,
                 bytes: bytes,
                 kind: isPackage ? .bundle : .folder,
                 origin: origin,
                 handling: handling,
                 modifiedOn: modifiedOn,
                 reason: reason)
        }
    }

    // MARK: ── What we did not see ───────────────────────────────────────────────────────────────

    /// One place the walk did not go, and why.
    ///
    /// A refusal a person could lift and a place we chose not to enter both live here, and they are
    /// told apart by `why.makesTheRunIncomplete` rather than by whoever reads the list.
    struct Refused: Sendable, Hashable, Identifiable {
        let path: String
        /// What a person would call it — "your Trash", "your Photos library" — falling back to the
        /// folder's own name, which is still a place somebody can picture.
        let name: String
        let why: ScanPolicy.SkipReason

        var id: String { path }

        /// Whether a person could do something about it.
        var couldBeLifted: Bool { why.makesTheRunIncomplete }
    }

    // MARK: ── How it says where it has got to ───────────────────────────────────────────────────

    /// ⚠️ **A place, never a percentage, and never a time.** The first scan after a restart has
    /// never been measured, so a countdown would be a guess with a clock face on it.
    struct Progress: Sendable, Hashable {
        let place: String
        let thingsSeen: Int
        let measured: SizeOnDisk

        /// The line under the button. `ScanPolicy.Running.at` is the section's one wording for it.
        var sentence: String { ScanPolicy.Running.at(place) }
    }

    // MARK: ── ⭐ What one walk produced ────────────────────────────────────────────────────────

    /// Everything one walk found, in the shape the rest of the section needs it.
    ///
    /// The three things `StorageReport.init` asks for — `measured`, `refused`, `cloudHolding` — are
    /// all here, so a report built from a survey names its own gap without anybody remembering to.
    struct Survey: Sendable, Hashable {

        /// ⭐ Both numbers, for everything walked.
        let bytes: Bytes

        let files: Int
        let folders: Int

        /// How many names were seen whose blocks had already been counted under another name.
        let namesSharingBlocks: Int

        /// Things that were there when the folder was listed and gone by the time we looked. A
        /// number, never a refusal: a build finishing mid-scan is not a permission problem.
        let vanished: Int

        /// The files that are not on this Mac at all.
        let cloudHolding: CloudHolding

        /// Every place the walk did not go, with its reason.
        let refusals: [Refused]

        /// Folder totals, largest on disk first.
        let folderTotals: [FolderTotal]

        /// The largest things, by **size on disk**, largest first.
        ///
        /// ⭐ Sorting on size on disk is what keeps the 15,593 iCloud files off the top of this
        /// list. They occupy nothing here, so they sort where they belong — at the bottom, with no
        /// filter anywhere that somebody could forget to apply.
        let largest: [Entry]

        /// ⚠️ Whether the walking thread really was holding cloud files where they are. `false`
        /// means the one line that stops a scan downloading somebody's photo library did not take.
        /// Nothing here opens a file, so nothing was pulled down either way — but it is a fact worth
        /// carrying rather than assuming.
        let heldCloudFilesWhereTheyAre: Bool

        /// True when the walk was asked to stop before it finished. **Its totals are then a floor,
        /// not an answer**, and nothing may present them as complete.
        let stoppedEarly: Bool

        let roots: [String]
        let ranFor: TimeInterval
        let ranAt: Date

        /// ⭐ What the scan accounted for. The figure `StorageReport` measures its gap against.
        var measured: SizeOnDisk { bytes.onDisk }

        /// ⭐ **The places we were not allowed to read, in the section's own type.**
        ///
        /// Named, never counted into silence. `sawEverything` only where there is genuinely nothing
        /// to report.
        var unreadable: UnreadablePlaces {
            let refused = refusals.filter(\.couldBeLifted)
            guard !refused.isEmpty else { return .sawEverything }
            var seen = Set<String>()
            let notable = refused
                .map(\.name)
                .filter { seen.insert($0).inserted }
                .prefix(3)
            return UnreadablePlaces(count: refused.count,
                                    notable: Array(notable),
                                    why: .notPermitted)
        }

        /// Every place skipped for a reason nobody can lift — macOS itself, another disk, a
        /// snapshot, our own store. Worth a line in Options; never a caveat on the face.
        var skippedOnPurpose: [Refused] { refusals.filter { !$0.couldBeLifted } }

        /// Whether this run saw what it set out to see.
        var complete: Bool { !stoppedEarly && unreadable.stillComplete }

        /// ⚠️ **What this total is known to get wrong, and in which direction.**
        ///
        /// Both errors push the same way: `measured` comes out a little **larger** than the bytes
        /// really are, which makes the named gap a little **smaller** than it really is. Neither is
        /// hidden and neither is guessed at. Every competitor's answer to this is a slice labelled
        /// "Other", which is a number with the explanation taken off.
        var honestyNotes: [String] {
            var notes = [
                "Two files that share their blocks — an APFS clone — are counted twice, the same "
                + "way the disk tools built into macOS count them.",
                "A folder's own few kilobytes are not counted; only what is inside it is.",
            ]
            if namesSharingBlocks == 1 {
                notes.append("One file has a second name on this disk and is counted once.")
            } else if namesSharingBlocks > 1 {
                notes.append("\(namesSharingBlocks.formatted()) files have more than one name on "
                           + "this disk and are each counted once.")
            }
            return notes
        }

        /// ⭐ **The difference between what macOS says is used and what this walk accounted for.**
        ///
        /// `StorageReport` computes the same thing in its own initialiser, from the same two
        /// figures, and there is no way to build a report without it. This is here for the caller
        /// that wants the sentence before it has rows to put around it — measured on one real Mac,
        /// 389.87 GB used against 142.98 GB walked, and the sentence names the snapshot and the
        /// refused folders instead of drawing a slice labelled "Other".
        func gap(against freeSpace: FreeSpacePicture) -> MeasuredGap {
            MeasuredGap(used: freeSpace.used,
                        measured: measured,
                        placesRefused: unreadable.count,
                        hasSnapshot: !freeSpace.snapshots.isEmpty)
        }

        /// The folder totals a person would recognise: largest on disk first, capped. The ones
        /// Storage would never offer to touch are still here, because their size is worth knowing
        /// even where the button is not ours to draw.
        func biggestFolders(_ limit: Int = 12) -> [FolderTotal] {
            Array(folderTotals.prefix(limit))
        }
    }

    // MARK: - ⭐ Running it

    /// ⭐ **The walk. Synchronous, one thread, and it does not return until it is done or stopped.**
    ///
    /// - Parameters:
    ///   - plan: where to go, and what to keep.
    ///   - stop: asked every 512 entries. Returning `true` ends the walk and sets `stoppedEarly`.
    ///   - onEntry: every entry, in walk order, exactly once. **This is the seam the rest of the
    ///     section hangs off** — the junk classifier, the largest-files list and the duplicate
    ///     finder all observe this one pass rather than each opening the disk again.
    ///   - onProgress: at most eight times a second, and only ever with a place name on it.
    ///
    /// ⭐ **`ScanPolicy.prepareThisThread()` is called here, first, before anything is looked at.**
    /// It is per thread and not per process, so it belongs at the top of the function that does the
    /// looking rather than somewhere a caller has to remember.
    @discardableResult
    static func walk(_ plan: Plan,
                     stop: () -> Bool = { false },
                     onEntry: (Entry) -> Void = { _ in },
                     onProgress: (Progress) -> Void = { _ in }) -> Survey {

        let heldCloudFiles = ScanPolicy.prepareThisThread()
        let startedAt = Date()

        var state = State(plan: plan)
        var stopped = false

        for root in plan.roots where !stopped {
            stopped = visit(root: root, plan: plan, state: &state,
                            stop: stop, onEntry: onEntry, onProgress: onProgress)
        }

        return state.finish(plan: plan,
                            heldCloudFiles: heldCloudFiles,
                            stoppedEarly: stopped,
                            ranFor: Date().timeIntervalSince(startedAt),
                            ranAt: startedAt)
    }

    /// The same walk, off the main thread, and genuinely cancellable.
    ///
    /// ⚠️ The cancellation handler is not decoration. A detached task does **not** inherit
    /// cancellation from the task that awaited it, so without `withTaskCancellationHandler` a person
    /// pressing Cancel would watch the button change while the disk carried on being walked.
    static func survey(_ plan: Plan,
                       onProgress: @escaping @Sendable (Progress) -> Void = { _ in }) async -> Survey {
        let task = Task.detached(priority: .userInitiated) {
            walk(plan, stop: { Task.isCancelled }, onProgress: onProgress)
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    // MARK: - One root

    /// Walks one root. Returns `true` when the walk was stopped.
    private static func visit(root: URL,
                              plan: Plan,
                              state: inout State,
                              stop: () -> Bool,
                              onEntry: (Entry) -> Void,
                              onProgress: (Progress) -> Void) -> Bool {

        let rootPath = root.path(percentEncoded: false)

        // The volume is read once per root and carried. `descend` guarantees the walk never leaves
        // it, so reading it half a million times would be half a million syscalls asked the same
        // question.
        guard let volume = Movable.volume(of: rootPath) else {
            state.refuse(path: rootPath, why: .notPermitted, home: plan.home)
            return false
        }
        if let why = ScanPolicy.descend(into: root, stayingOn: volume, home: plan.home).reason {
            state.refuse(path: rootPath, why: why, home: plan.home)
            return false
        }

        state.openRoot(root, volume: volume)

        // ⚠️ The error handler is the only way this walk finds out it was refused a folder. Without
        // it, the enumerator steps silently over the Trash and the Photos library and the total
        // comes back smaller with nothing to say about it — a zero, where the true answer is "I was
        // not allowed to look".
        let notes = state.notes
        let home = plan.home
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: plan.enumerationOptions,
            errorHandler: { url, error in
                notes.note(url.path(percentEncoded: false), error: error, home: home)
                return true
            })
        else {
            state.refuse(path: rootPath, why: .notPermitted, home: plan.home)
            return false
        }

        let notEvenMeasured = plan.placesNotEvenMeasured
        // ⚠️ Which level of folder is worth naming while it runs. One below the root, except under
        // `/Users`, where the first level is an account name — "Looking in ada" tells nobody
        // anything, and "Looking in Documents" tells them exactly where the scan is.
        let placeDepth = rootPath == "/Users" ? 2 : 1
        var seen = 0
        var lastProgress = Date()

        for case let url as URL in walker {
            seen += 1
            if seen & 0x1FF == 0, stop() {
                state.close(downTo: 0, plan: plan)
                return true
            }

            let depth = walker.level
            state.close(downTo: depth, plan: plan)

            guard let reading = read(url, depth: depth, volume: volume, plan: plan) else {
                state.notes.vanished += 1
                continue
            }

            if reading.entry.isFolder {
                if let why = ScanPolicy.descend(into: url, stayingOn: volume, home: home).reason {
                    walker.skipDescendants()
                    state.refuse(path: reading.entry.path, why: why, home: home)
                    continue
                }
                // ⚠️ The places Storage will not even weigh — macOS itself, and the system's own
                // bookkeeping. Everything else on the refusal list is still sized: being unable to
                // offer a button is not a reason to pretend a folder has no weight.
                if Movable.isInside(reading.entry.path, any: notEvenMeasured) {
                    walker.skipDescendants()
                    continue
                }
                state.push(reading, depth: depth)
                onEntry(reading.entry)
                if depth == placeDepth { state.place = reading.entry.name }
            } else {
                onEntry(state.add(reading))
            }

            if seen & 0x7FF == 0 {
                let now = Date()
                if now.timeIntervalSince(lastProgress) >= 0.12 {
                    lastProgress = now
                    onProgress(state.progress)
                }
            }
        }

        state.close(downTo: 0, plan: plan)
        return false
    }

    // MARK: - Reading one thing

    /// What one entry's resource values came to, before it is folded into anything.
    private struct Reading {
        let entry: Entry
        let isPackage: Bool
        let onDisk: Int64
        let recoverable: Int64
    }

    private static func read(_ url: URL, depth: Int, volume: VolumeReading, plan: Plan) -> Reading? {
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }

        // ⚠️ Foundation hands back a directory's path with a trailing slash and a file's without
        // one, so `/Users/ada` and `/Users/ada/` would be two spellings of one folder on the same
        // screen — and two different keys anywhere a path is used as one.
        var path = url.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }

        let isDirectory = values.isDirectory ?? false
        let isLink = values.isSymbolicLink ?? false
        let isPackage = values.isPackage ?? false

        // ⚠️ `.totalFileAllocatedSizeKey` is the size on disk: blocks actually allocated, after
        // compression, after sparseness. `.fileSizeKey` is what the file claims. On one real Mac the
        // claimed figure is wrong by 56% and moved 11% between two runs minutes apart; the
        // allocated figure moved 0.2%. Directories publish neither, which is why a folder's own few
        // kilobytes go uncounted — see `Survey.honestyNotes`.
        let onDisk = Int64(values.totalFileAllocatedSize ?? 0)
        let apparent = Int64(values.fileSize ?? 0)

        var inode = values.fileIdentifier.map { UInt64($0) }
        var links = values.linkCount ?? 1
        var flags: UInt32 = 0
        var modified = values.contentModificationDate

        // ⭐ One `lstat`, and only where something is missing or the size signature says this may be
        // a file that is not here at all. On this Mac that is 15,593 files out of half a million, so
        // the flag is read where it decides something and nowhere else. See measurement 2.
        let mightNotBeHere = onDisk == 0 && apparent > 0
        if inode == nil || mightNotBeHere {
            var status = stat()
            guard lstat(path, &status) == 0 else { return nil }
            inode = inode ?? UInt64(status.st_ino)
            links = values.linkCount ?? Int(status.st_nlink)
            flags = status.st_flags
            if modified == nil {
                modified = Date(timeIntervalSince1970: TimeInterval(status.st_mtimespec.tv_sec))
            }
        }
        // An entry whose identity could not be established is dropped rather than given a made-up
        // one. A record whose identity is a guess is a record that can act on a different file from
        // the one somebody was shown.
        guard let inode else { return nil }

        let itemKind = kind(isDirectory: isDirectory,
                            isLink: isLink,
                            isPackage: isPackage,
                            name: url.lastPathComponent)

        let bytes = plan.snapshots.bytes(onDisk: SizeOnDisk(onDisk), modifiedOn: modified)

        let entry = Entry(identity: ItemIdentity(volumeUUID: volume.uuid,
                                                 volumeDevice: volume.device,
                                                 inode: inode),
                          path: path,
                          name: url.lastPathComponent,
                          kind: itemKind,
                          bytes: bytes,
                          apparentBytes: apparent,
                          cloudStanding: cloudStanding(datalessFlags: flags,
                                                       mightNotBeHere: mightNotBeHere),
                          modifiedOn: modified,
                          linkCount: links,
                          countsTowardTheTotal: true,
                          depth: depth)

        return Reading(entry: entry,
                       isPackage: isPackage,
                       onDisk: onDisk,
                       recoverable: bytes.recoverableToday.bytes)
    }

    // MARK: ── ⭐ Is it even here ────────────────────────────────────────────────────────────────

    /// ⭐ **Whether the bytes are on this Mac, decided by the kernel flag and never by the numbers.**
    ///
    /// The cheap half first: a file with a size and no blocks *might* not be here. Then the answer:
    /// `SF_DATALESS`, which macOS sets on a placeholder for a file that lives in the cloud.
    ///
    /// ⚠️ **The two look identical without the flag.** Measured 2026-08-28: four real
    /// iCloud photos read `blocks=0, size=2.9 MB, flags=0x40000060`; a 100 MB sparse file made for
    /// the test reads `blocks=0, size=104857600, flags=0x0`. Deciding on the numbers alone would
    /// file somebody's sparse disk image under "in iCloud, using no space here" — and then offer to
    /// set aside a file that is very much here.
    ///
    /// `.bothPlaces` — downloaded here **and** synced — is deliberately not decided in the walk. It
    /// costs `.isUbiquitousItemKey`, which takes the scan from 6 seconds to 25, and the only thing
    /// it changes is a warning line shown before a press. `Movable` establishes it at press time,
    /// when it is already reading the one file it is about to move.
    static func cloudStanding(datalessFlags flags: UInt32, mightNotBeHere: Bool) -> CloudStanding {
        guard mightNotBeHere, flags & Movable.dataless != 0 else { return .onThisMac }
        return .inTheCloudOnly
    }

    /// What a thing structurally is. ⚠️ Presentation only — nothing about safety reads this.
    static func kind(isDirectory: Bool, isLink: Bool, isPackage: Bool, name: String) -> ItemKind {
        if isLink { return .link }
        if diskImageExtensions.contains((name as NSString).pathExtension.lowercased()) {
            return .diskImage
        }
        if isDirectory { return isPackage ? .bundle : .folder }
        return .file
    }

    static let diskImageExtensions: Set<String> = ["dmg", "sparseimage", "sparsebundle", "iso"]

    // MARK: - The running total

    /// The one mutable thing in a walk. A `struct` held `inout`, so there is no shared state and no
    /// lock: the walk is deliberately one thread doing one thing.
    private struct State {

        /// A folder still being filled in. The stack is the path from the root down to wherever the
        /// walk currently is, so a file's bytes are added to its own folder in constant time and
        /// each folder folds into its parent exactly once, as it closes.
        struct OpenFolder {
            let identity: ItemIdentity
            let path: String
            let name: String
            let depth: Int
            let isPackage: Bool
            let modifiedOn: Date?
            var onDisk: Int64 = 0
            var recoverable: Int64 = 0
            var files: Int = 0
        }

        /// Refusals and vanishings, in a reference type because Foundation's error handler is an
        /// escaping closure and cannot be handed an `inout`.
        final class Notes {
            var refusals: [Refused] = []
            var vanished = 0

            func note(_ path: String, error: Error, home: URL) {
                // A file that was listed and then removed before we looked at it is a build
                // finishing, not a permission problem. Counted, never presented as a refusal.
                let error = error as NSError
                let gone = (error.domain == NSCocoaErrorDomain
                            && error.code == NSFileReadNoSuchFileError)
                        || (error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT))
                if gone { vanished += 1; return }

                add(Refused(path: path,
                            name: Scanner.friendlyName(for: path, home: home),
                            why: .notPermitted))
            }

            func add(_ refused: Refused) {
                guard !refusals.contains(where: { $0.path == refused.path }) else { return }
                refusals.append(refused)
            }
        }

        let notes = Notes()
        let keep: Int

        var openFolders: [OpenFolder] = []
        var finished: [FolderTotal] = []
        var largest: [Entry] = []
        var largestFloor: Int64 = 0

        var onDisk: Int64 = 0
        var recoverable: Int64 = 0
        var files = 0
        var folders = 0

        var cloudFiles = 0
        var cloudApparent: Int64 = 0

        /// ⚠️ Only inodes with more than one name are remembered. On a Mac with half a million
        /// files that is a set of a few thousand rather than of half a million.
        var linkedInodes = Set<UInt64>()
        var namesSharingBlocks = 0

        var place = ""
        var thingsSeen = 0

        init(plan: Plan) { keep = plan.largestKept }

        var progress: Progress {
            Progress(place: place.isEmpty ? "this Mac's disk" : place,
                     thingsSeen: thingsSeen,
                     measured: SizeOnDisk(onDisk))
        }

        mutating func openRoot(_ root: URL, volume: VolumeReading) {
            let path = root.path(percentEncoded: false)
            var status = stat()
            let inode = lstat(path, &status) == 0 ? UInt64(status.st_ino) : 0
            openFolders = [OpenFolder(identity: ItemIdentity(volumeUUID: volume.uuid,
                                                             volumeDevice: volume.device,
                                                             inode: inode),
                                      path: path,
                                      name: root.lastPathComponent,
                                      depth: 0,
                                      isPackage: false,
                                      modifiedOn: nil)]
            place = root.lastPathComponent
        }

        mutating func push(_ reading: Reading, depth: Int) {
            folders += 1
            thingsSeen += 1
            openFolders.append(OpenFolder(identity: reading.entry.identity,
                                          path: reading.entry.path,
                                          name: reading.entry.name,
                                          depth: depth,
                                          isPackage: reading.isPackage,
                                          modifiedOn: reading.entry.modifiedOn))
        }

        /// ⭐ One file. This is where a hard link stops being counted twice — and where the entry
        /// handed on to observers is told which of its two names it was.
        mutating func add(_ reading: Reading) -> Entry {
            files += 1
            thingsSeen += 1

            var entry = reading.entry
            if entry.cloudStanding == .inTheCloudOnly {
                cloudFiles += 1
                cloudApparent += entry.apparentBytes
            }

            if entry.linkCount > 1, !linkedInodes.insert(entry.identity.inode).inserted {
                namesSharingBlocks += 1
                entry = Entry(identity: entry.identity,
                              path: entry.path,
                              name: entry.name,
                              kind: entry.kind,
                              bytes: entry.bytes,
                              apparentBytes: entry.apparentBytes,
                              cloudStanding: entry.cloudStanding,
                              modifiedOn: entry.modifiedOn,
                              linkCount: entry.linkCount,
                              countsTowardTheTotal: false,
                              depth: entry.depth)
                return entry
            }

            onDisk += reading.onDisk
            recoverable += reading.recoverable
            if !openFolders.isEmpty {
                openFolders[openFolders.count - 1].onDisk += reading.onDisk
                openFolders[openFolders.count - 1].recoverable += reading.recoverable
                openFolders[openFolders.count - 1].files += 1
            }
            remember(entry, onDisk: reading.onDisk)
            return entry
        }

        /// The largest things, kept without sorting half a million entries. The list is allowed to
        /// grow to four times its size and is then cut back, which costs one sort per few thousand
        /// large files instead of one insertion per file.
        mutating func remember(_ entry: Entry, onDisk: Int64) {
            guard onDisk > largestFloor || largest.count < keep else { return }
            largest.append(entry)
            guard largest.count >= keep * 4 else { return }
            largest.sort { $0.bytes.onDisk > $1.bytes.onDisk }
            largest.removeLast(largest.count - keep)
            largestFloor = largest.last?.bytes.onDisk.bytes ?? 0
        }

        /// Close every folder at or below `depth`, folding each into its parent as it goes.
        mutating func close(downTo depth: Int, plan: Plan) {
            while let top = openFolders.last, top.depth >= depth, openFolders.count > 1 {
                openFolders.removeLast()
                record(top, plan: plan)
                openFolders[openFolders.count - 1].onDisk += top.onDisk
                openFolders[openFolders.count - 1].recoverable += top.recoverable
                openFolders[openFolders.count - 1].files += top.files
            }
            if depth == 0, openFolders.count == 1, let root = openFolders.last {
                openFolders.removeLast()
                record(root, plan: plan)
            }
        }

        mutating func record(_ folder: OpenFolder, plan: Plan) {
            let worthKeeping = folder.depth <= plan.folderDepth
                || (folder.isPackage && folder.onDisk >= plan.notableFolderBytes)
            guard worthKeeping else { return }
            finished.append(FolderTotal(
                identity: folder.identity,
                path: folder.path,
                name: folder.name,
                depth: folder.depth,
                isPackage: folder.isPackage,
                // ⭐ The two figures were summed apart and are put together here, which is the only
                // way `Bytes` can be built: there is no arithmetic anywhere that turns one of them
                // into the other.
                bytes: Bytes(onDisk: SizeOnDisk(folder.onDisk),
                             recoverableToday: .all(of: SizeOnDisk(folder.recoverable))),
                files: folder.files,
                modifiedOn: folder.modifiedOn))
        }

        mutating func refuse(path: String, why: ScanPolicy.SkipReason, home: URL) {
            notes.add(Refused(path: path,
                              name: Scanner.friendlyName(for: path, home: home),
                              why: why))
        }

        func finish(plan: Plan,
                    heldCloudFiles: Bool,
                    stoppedEarly: Bool,
                    ranFor: TimeInterval,
                    ranAt: Date) -> Survey {
            var top = largest.sorted { $0.bytes.onDisk > $1.bytes.onDisk }
            if top.count > plan.largestKept { top.removeLast(top.count - plan.largestKept) }

            return Survey(
                bytes: Bytes(onDisk: SizeOnDisk(onDisk),
                             recoverableToday: .all(of: SizeOnDisk(recoverable))),
                files: files,
                folders: folders,
                namesSharingBlocks: namesSharingBlocks,
                vanished: notes.vanished,
                cloudHolding: CloudHolding(files: cloudFiles, apparentBytes: cloudApparent),
                refusals: notes.refusals,
                folderTotals: finished.sorted { $0.bytes.onDisk > $1.bytes.onDisk },
                largest: top,
                heldCloudFilesWhereTheyAre: heldCloudFiles,
                stoppedEarly: stoppedEarly,
                roots: plan.roots.map { $0.path(percentEncoded: false) },
                ranFor: ranFor,
                ranAt: ranAt)
        }
    }

    // MARK: - What to call a place

    /// ⭐ **"your Trash", not "54 folders".**
    ///
    /// A count means nothing to anybody. The name comes from `ScanPolicy.neverOffered` where there
    /// is one — that list already carries the person's own words for the places that matter most —
    /// and falls back to the folder's own name otherwise.
    static func friendlyName(for path: String, home: URL = StorageManifest.home()) -> String {
        if let refusal = ScanPolicy.refusal(for: path, home: home) { return refusal.name }
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }
}

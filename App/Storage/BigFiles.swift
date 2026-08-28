// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import CoreServices
import Darwin
import Foundation
import WellkeptCore

//  BigFiles.swift
//  Wellkept — App/Storage
//
//  ⭐ **Reveal, size, sort. Nothing here is ever ticked, and nothing here is ever swept.**
//
//  This is the row for a person's own files, and it is the row the whole product exists to get
//  right. Every commercial cleaner turns this list into a proposal — a column of checkboxes already
//  ticked, a green button, and a number that implies somebody has done something wrong by owning a
//  video. Wellkept's answer is a list.
//
//  Three separate mechanisms make that true, and none of them is this file remembering to be
//  careful: `Origin` defaults to `.yours`, `Item.mayBePreSelected` is false for anything that is
//  `.yours`, and `StorageRow.preSelected` returns `[]` for `.yourOwnFiles` whatever the items claim.
//
//  ## ⚠️ The four measurements that shaped it
//
//  1. **Sort by size on disk, never by apparent size.** 15,593 files in this home folder look like
//     72 GB by name and occupy nothing at all — they are iCloud placeholders. A "largest first"
//     list built on the claimed size puts a column of files that are not here above the things
//     actually filling the drive. They are counted once, in `CloudHolding`, and left off the list.
//  2. **"How big is it" and "what would I get back" are different true numbers.**
//     `~/Documents/Media`: 14.8 GB on disk, **0.5 GB back today**, because a stuck Time Machine
//     snapshot still references the older blocks. Every row carries both, and the arithmetic is
//     `SnapshotStanding.recoverable(onDisk:modifiedOn:)` — done per file and summed, never applied
//     to a folder's total in one go.
//  3. **"Last opened" is blank for 61% of large files here**, and 123 files in one sample share a
//     single timestamp a batch job stamped on them. It is read, it is printed as a plain fact on
//     the row, and it is **never** a finding. The sentence "you have not opened this in seven
//     years" is not in this app at any threshold. See `lastOpened(_:)`.
//  4. **30 GB of iOS simulator runtimes cannot be set aside at all** — root-owned read-only disk
//     images, so no thirty-day undo could exist for them. They are on the list, with their size,
//     and with `Handling.cannot(...)` so that no button is drawn. See
//     `measuredPlacesOutsideTheHomeFolder`.
//
//  ## Two lists, because they answer two questions
//
//  `items` is the biggest single things — files, packages taken whole, and the places we will never
//  offer to touch. `places` is where the weight sits, one and two levels under the home folder.
//  They are kept apart because merging them double-counts: a 14.8 GB folder and the 3 GB video
//  inside it are the same bytes twice, and one list holding both is a list whose column cannot be
//  added up.

// MARK: - ⭐ The walk

/// **One walk, obeying one policy, shared by this file and `Duplicates.swift`.**
///
/// It lives here rather than in a third file because it is the same walk: `Duplicates` needs every
/// file's size and cloud standing before it can pick candidates, and `BigFiles` needs exactly that
/// and nothing more. Two walks would be two chances to disagree with `ScanPolicy`.
///
/// ⚠️ **It asks `ScanPolicy.descend` before entering any folder and decides nothing itself.** The
/// one structural judgement it makes is that a package, and a folder on the refusal list, are
/// **rolled up into a single entry** rather than opened. That is what stops the list filling with
/// the 200,000 files inside `Xcode.app`, and with somebody's individual mail messages.
enum StorageWalk {

    // MARK: What one thing looked like

    /// One thing the walk reported: a file, a package taken whole, or a refused place taken whole.
    ///
    /// It deliberately carries **no identity**. Establishing one costs an `lstat` per file and a
    /// scan sees hundreds of thousands; the handful that reach a screen get theirs from
    /// `identify(_:)` at the end. A path is not an identity, and nothing here acts on one.
    struct Entry: Sendable, Hashable {
        let path: String
        let name: String
        let kind: ItemKind

        /// ⭐ Allocated blocks. The number the section shows.
        let onDisk: SizeOnDisk

        /// ⭐ What would come back today, after the snapshot arithmetic. For a rolled-up folder
        /// this is the sum of its files' answers, never the folder's own date applied to the whole.
        let recoverableToday: Recoverable

        /// ⚠️ What it claims by name. Kept to spot the iCloud placeholders and to bucket duplicate
        /// candidates by content length, and never printed as a size we stand behind.
        let apparentBytes: Int64

        let modifiedOn: Date?
        let cloudStanding: CloudStanding

        /// Set when this is a place `ScanPolicy` will never offer to touch, taken whole so its size
        /// can still be reported. `why` is what the row says instead of a button.
        let refusal: ScanPolicy.Refusal?

        /// How deep under the walk's root it sits. The root itself is 0.
        let depth: Int

        var bytes: Bytes { Bytes(onDisk: onDisk, recoverableToday: recoverableToday) }
        var isRefused: Bool { refusal != nil }
    }

    /// One folder and everything under it, reported after its children have been counted.
    struct Folder: Sendable, Hashable, Identifiable {
        let path: String
        /// What to call it, relative to the root it was found under: `Documents/Media`.
        let name: String
        let onDisk: SizeOnDisk
        let recoverableToday: Recoverable
        let files: Int
        let depth: Int

        var id: String { path }
        var bytes: Bytes { Bytes(onDisk: onDisk, recoverableToday: recoverableToday) }
    }

    /// What a whole walk added up to.
    struct Outcome: Sendable, Hashable {
        let total: SizeOnDisk
        let recoverableToday: Recoverable
        let filesSeen: Int
        let cloudFiles: Int
        let cloudApparentBytes: Int64
        let refusedCount: Int
        let refusedNotable: [String]

        var bytes: Bytes { Bytes(onDisk: total, recoverableToday: recoverableToday) }

        /// ⚠️ **Never a zero for a place we were refused.** See `UnreadablePlaces`.
        var refused: UnreadablePlaces {
            refusedCount == 0
                ? .sawEverything
                : UnreadablePlaces(count: refusedCount,
                                   notable: Array(refusedNotable.prefix(3)),
                                   why: .notPermitted)
        }

        var cloudHolding: CloudHolding {
            CloudHolding(files: cloudFiles, apparentBytes: cloudApparentBytes)
        }
    }

    // MARK: Running it

    /// **The walk.** Blocking from beginning to end, so it belongs on a detached task.
    ///
    /// ⚠️ **`prepareThisThread()` is called here rather than left to the caller.** It is per thread,
    /// not per process, and forgetting it is not a bug a test would catch — it shows up as 524 files
    /// coming down over somebody's internet and a 36-second scan taking nine minutes.
    ///
    /// ⚠️ **Names are listed with `contentsOfDirectory(atPath:)`, which asks the filesystem for
    /// nothing but names.** The variant that prefetches resource values would stat every child,
    /// including the folder macOS raises a privacy dialog for **on the attempt**. Each child is
    /// tested by string first, and only measured once it has been cleared.
    ///
    /// ⚠️ **`ScanPolicy.descend` is asked about folders, not about every file.** It re-walks the
    /// whole parent chain looking for a symbolic link, which is the right check on the way into a
    /// folder and 3.2 million redundant `lstat`s if it is asked once per file. A file is reached
    /// only through folders that have already passed, so the only reading it still needs is whether
    /// it is itself a link — and that arrives free with the sizes.
    ///
    /// - Returns: `nil` if the run was cancelled. A partial total is not a shorter answer, it is a
    ///   wrong one, and the first thing anybody would do with it is put it on a screen.
    @discardableResult
    static func walk(from roots: [URL],
                     home: URL = StorageManifest.home(),
                     snapshots: SnapshotStanding = .none,
                     folderDepth: Int = 2,
                     isCancelled: () -> Bool = { Task.isCancelled },
                     progress: (String) -> Void = { _ in },
                     folder: (Folder) -> Void = { _ in },
                     visit: (Entry) -> Void) -> Outcome? {

        ScanPolicy.prepareThisThread()

        let manager = FileManager.default
        var total = SizeOnDisk.zero
        var totalBack = Recoverable.nothing
        var filesSeen = 0
        var cloudFiles = 0
        var cloudApparent: Int64 = 0
        var refusedCount = 0
        var refusedNotable: [String] = []
        var cancelled = false
        var stepsSinceCheck = 0

        func stillRunning() -> Bool {
            stepsSinceCheck += 1
            if stepsSinceCheck >= 256 {
                stepsSinceCheck = 0
                if isCancelled() { cancelled = true }
            }
            return !cancelled
        }

        func noteRefusal(_ path: String, fallback: String) {
            refusedCount += 1
            let friendly = ScanPolicy.refusal(for: path, home: home)?.name ?? fallback
            if refusedNotable.count < 8, !refusedNotable.contains(friendly) {
                refusedNotable.append(friendly)
            }
        }

        /// Sums one folder, reporting entries as it goes, and hands back its own subtree total.
        ///
        /// Recursive because a folder's size is only known once its children's are, and the depth a
        /// filesystem allows is bounded by `PATH_MAX` — a few hundred levels — long before a stack
        /// is.
        func sum(directory url: URL,
                 scanVolume: VolumeReading?,
                 rootPath: String,
                 depth: Int,
                 listing: Bool) -> (onDisk: SizeOnDisk, back: Recoverable, files: Int) {

            guard stillRunning() else { return (.zero, .nothing, 0) }

            let path = url.path(percentEncoded: false)
            let names: [String]
            do {
                names = try manager.contentsOfDirectory(atPath: path)
            } catch {
                // ⚠️ A folder we were refused is counted and named. It is never reported as a zero,
                // which would read as "there is nothing in your Trash".
                noteRefusal(path, fallback: (path as NSString).lastPathComponent)
                return (.zero, .nothing, 0)
            }

            if listing, depth <= 1 {
                progress(ScanPolicy.Running.at(place(of: path, under: rootPath)))
            }

            var onDisk = SizeOnDisk.zero
            var back = Recoverable.nothing
            var files = 0

            for name in names {
                guard stillRunning() else { break }
                let child = url.appending(path: name, directoryHint: .notDirectory)
                let childPath = child.path(percentEncoded: false)

                // ⛔ **Pure string work, before anything touches the child.** For another app's
                // sandboxed data macOS raises its dialog on the attempt, so even a `stat` is too
                // late. Nothing below this line runs for those folders.
                if ScanPolicy.isAnotherAppsData(childPath, home: home) { continue }

                guard let values = try? child.resourceValues(forKeys: ScanPolicy.resourceKeys)
                else { continue }

                // A symbolic link is never followed and never counted: following one leaves the
                // volume, loops, or counts the same folder twice under a second name.
                if values.isSymbolicLink == true { continue }

                let isDirectory = values.isDirectory ?? false
                let apparent = Int64(values.fileSize ?? 0)
                let allocated = SizeOnDisk(Int64(values.totalFileAllocatedSize
                                                 ?? values.fileAllocatedSize ?? 0))
                let modified = values.contentModificationDate
                let standing = cloudStanding(values, onDisk: allocated, apparent: apparent)

                if standing == .inTheCloudOnly {
                    // ⚠️ Counted once, here, and left off every list. It occupies nothing, so
                    // there is no room to be had from it and no button to draw on it.
                    cloudFiles += 1
                    cloudApparent += apparent
                    continue
                }

                if !isDirectory {
                    let mine = snapshots.recoverable(onDisk: allocated, modifiedOn: modified)
                    onDisk = onDisk + allocated
                    back = back + mine
                    files += 1
                    if listing {
                        visit(Entry(path: childPath,
                                    name: name,
                                    kind: kind(for: name, isDirectory: false, isPackage: false),
                                    onDisk: allocated,
                                    recoverableToday: mine,
                                    apparentBytes: apparent,
                                    modifiedOn: modified,
                                    cloudStanding: standing,
                                    refusal: nil,
                                    depth: depth + 1))
                    }
                    continue
                }

                // ── A folder. The policy decides, then one of three things happens.

                let verdict = ScanPolicy.descend(into: child, stayingOn: scanVolume, home: home)
                if case let .no(why) = verdict {
                    if why.makesTheRunIncomplete { noteRefusal(childPath, fallback: name) }
                    continue
                }

                // 1. A place we will never offer to touch. Taken whole, or skipped entirely.
                if let refusal = ScanPolicy.refusal(for: childPath, home: home) {
                    guard refusal.stillMeasured else { continue }
                    let inside = sum(directory: child, scanVolume: scanVolume, rootPath: rootPath,
                                     depth: depth + 1, listing: false)
                    onDisk = onDisk + inside.onDisk
                    back = back + inside.back
                    files += inside.files
                    if listing, !inside.onDisk.isZero {
                        visit(Entry(path: childPath, name: refusal.name, kind: .folder,
                                    onDisk: inside.onDisk, recoverableToday: inside.back,
                                    apparentBytes: inside.onDisk.bytes, modifiedOn: modified,
                                    cloudStanding: .onThisMac, refusal: refusal, depth: depth + 1))
                    }
                    continue
                }

                // 2. A package. One thing to a person, so one thing here — never 200,000 of them.
                if values.isPackage == true {
                    let inside = sum(directory: child, scanVolume: scanVolume, rootPath: rootPath,
                                     depth: depth + 1, listing: false)
                    onDisk = onDisk + inside.onDisk
                    back = back + inside.back
                    files += inside.files
                    if listing, !inside.onDisk.isZero {
                        visit(Entry(path: childPath, name: name,
                                    kind: kind(for: name, isDirectory: true, isPackage: true),
                                    onDisk: inside.onDisk, recoverableToday: inside.back,
                                    apparentBytes: inside.onDisk.bytes, modifiedOn: modified,
                                    cloudStanding: standing, refusal: nil, depth: depth + 1))
                    }
                    continue
                }

                // 3. An ordinary folder. Walk into it.
                let inside = sum(directory: child, scanVolume: scanVolume, rootPath: rootPath,
                                 depth: depth + 1, listing: listing)
                onDisk = onDisk + inside.onDisk
                back = back + inside.back
                files += inside.files

                if listing, depth + 1 <= folderDepth, !inside.onDisk.isZero {
                    folder(Folder(path: childPath,
                                  name: place(of: childPath, under: rootPath),
                                  onDisk: inside.onDisk,
                                  recoverableToday: inside.back,
                                  files: inside.files,
                                  depth: depth + 1))
                }
            }

            return (onDisk, back, files)
        }

        for root in roots {
            guard !cancelled else { break }
            let rootPath = root.path(percentEncoded: false)
            guard ScanPolicy.descend(into: root, stayingOn: nil, home: home).isAllowed else { continue }
            let scanVolume = Movable.volume(of: rootPath)
            let result = sum(directory: root, scanVolume: scanVolume, rootPath: rootPath,
                             depth: 0, listing: true)
            total = total + result.onDisk
            totalBack = totalBack + result.back
            filesSeen += result.files
        }

        guard !cancelled, !isCancelled() else { return nil }

        return Outcome(total: total,
                       recoverableToday: totalBack,
                       filesSeen: filesSeen,
                       cloudFiles: cloudFiles,
                       cloudApparentBytes: cloudApparent,
                       refusedCount: refusedCount,
                       refusedNotable: refusedNotable)
    }

    /// Everything under one folder, summed and nothing else — for a place that is measured and
    /// never opened on a screen. `nil` when the run was cancelled.
    static func total(of url: URL,
                      home: URL = StorageManifest.home(),
                      snapshots: SnapshotStanding = .none,
                      isCancelled: () -> Bool = { Task.isCancelled }) -> Bytes? {
        walk(from: [url], home: home, snapshots: snapshots, folderDepth: 0,
             isCancelled: isCancelled) { _ in }?.bytes
    }

    // MARK: The small readings

    /// ⚠️ **Whether the bytes are actually here.** A placeholder claims a size and occupies nothing,
    /// and the claimed size is the one number in this section that must never be sorted on.
    static func cloudStanding(_ values: URLResourceValues,
                              onDisk: SizeOnDisk,
                              apparent: Int64) -> CloudStanding {
        guard values.isUbiquitousItem == true else { return .onThisMac }
        if values.ubiquitousItemDownloadingStatus == .notDownloaded { return .inTheCloudOnly }
        // The belt to that status's braces: a downloaded file occupies blocks, and one claiming a
        // size while occupying none is a placeholder whatever the status field says.
        if onDisk.isZero, apparent > 0 { return .inTheCloudOnly }
        return .bothPlaces
    }

    /// What a thing structurally is. Deliberately not a taxonomy of purpose — see `ItemKind`.
    static func kind(for name: String, isDirectory: Bool, isPackage: Bool) -> ItemKind {
        let lower = name.lowercased()
        if lower.hasSuffix(".dmg") || lower.hasSuffix(".sparsebundle")
            || lower.hasSuffix(".sparseimage") || lower.hasSuffix(".iso") {
            return .diskImage
        }
        if isPackage { return .bundle }
        return isDirectory ? .folder : .file
    }

    /// What to call a place in a sentence: `Documents/Media`, or the folder's own name when it is
    /// not under the root the walk started from.
    static func place(of path: String, under root: String) -> String {
        guard path.count > root.count, path.hasPrefix(root) else {
            return (path as NSString).lastPathComponent
        }
        let tail = String(path.dropFirst(root.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return tail.isEmpty ? (path as NSString).lastPathComponent : tail
    }

    // MARK: Identity, established once, at the end

    /// ⭐ Volume plus inode, from the engine's own reading. `nil` when the thing has gone — which is
    /// ordinary on a live Mac, and is why every list here is built with a `continue`.
    static func identify(_ path: String) -> ItemIdentity? {
        guard let reading = Movable.read(URL(filePath: path)) else { return nil }
        return ItemIdentity(volumeUUID: reading.volume.uuid,
                            volumeDevice: reading.volume.device,
                            inode: reading.inode)
    }
}

// MARK: - ⭐ The person's own files

enum BigFiles {

    // MARK: The two numbers that bound the list

    /// How many things reach the screen. A list nobody scrolls to the end of has stopped being a
    /// list; a person who wants the 41st can sort their own folder in the Finder.
    static let howManyToList = 40

    /// ⚠️ Nothing under this is called large, whatever else is on the disk. A "largest files" list
    /// whose smallest entry is 300 KB has told somebody their Mac is tidy in the least useful
    /// possible way — and has put a 300 KB text file of theirs in front of them beside a button.
    static let smallestWorthShowing = SizeOnDisk(20_000_000)

    /// How many places the row names behind Options.
    static let howManyPlaces = 8

    /// One place the weight sits. **A picture, not a proposal**: there is no button on a `Place`,
    /// and no field on it that could carry one.
    struct Place: Sendable, Hashable, Identifiable {
        let path: String
        let name: String
        let bytes: Bytes
        let files: Int

        var id: String { path }

        /// `Documents/Media — 14.8 GB on disk, 0.5 GB comes back today`
        var sentence: String { "\(name) — \(bytes.sentence)" }

        var detail: DetailPair { DetailPair(name, bytes.text) }
    }

    /// What one run produced.
    struct Answer: Sendable, Hashable {

        /// ⭐ Largest first, **by size on disk**. Never pre-selected: `Origin.yours` and
        /// `StorageTopic.yourOwnFiles` each make that impossible on their own.
        let items: [Item]

        /// Where the weight sits, one and two levels down. Largest first.
        let places: [Place]

        /// Everything the walk accounted for, both numbers. This is what `StorageReport.measured`
        /// wants from this section.
        let total: Bytes

        let filesSeen: Int

        /// The files that look enormous and are not here.
        let cloudHolding: CloudHolding

        let refused: UnreadablePlaces

        let row: StorageRow

        /// What the listed things add up to — a different number from `total`, and never printed
        /// as if it were the same one.
        var listed: Bytes { Bytes.sum(items.map(\.bytes)) }
    }

    // MARK: The words

    /// ⚠️ **The reason on every row, and it is a description rather than an accusation.**
    ///
    /// A person's own file is on this screen because it is large. That is the whole finding, and
    /// dressing it up — "unused", "old", "taking up space" — is the thing this product is not.
    enum Says {

        static let whyTheseAreListed =
            "These are your own files, largest first. Nothing here is chosen for you and nothing "
            + "here is a problem — it is a list of where the room went."

        static func because(_ onDisk: SizeOnDisk) -> String {
            "\(onDisk.text) on disk. It is on this list because it is large, and for no other reason."
        }

        /// The sentence for something we show and will never offer a button on.
        static func becauseWeWillNotTouchIt(_ refusal: ScanPolicy.Refusal) -> String {
            refusal.why
        }

        static func nothingIsBigEnough(_ floor: SizeOnDisk) -> String {
            "Nothing of yours is over \(floor.text)."
        }

        /// ⚠️ **Never "you have not opened this in seven years".** Blank for 61% of large files on
        /// this Mac, and 123 files in one sample carry a single date a batch job stamped on them.
        static let whyLastOpenedIsOnlyAFact =
            "Spotlight records when a file was last opened, but it is blank for most large files, "
            + "and one batch job can stamp hundreds of them with the same date. It is printed as a "
            + "fact and it is never a reason."

        static let howThisIsSorted =
            "By what each thing occupies on the disk, not by the size it claims."
    }

    // MARK: Running it

    /// **The whole read.** Blocking — about twelve seconds on this Mac's home folder — so it belongs
    /// on a detached task and never where a window is waiting to draw. `nil` if it was cancelled.
    ///
    /// - Parameters:
    ///   - roots: what to walk. The home folder by default: a person's own files are what this row
    ///     is, and the machine's own are `.machineJunk`'s business.
    ///   - elsewhere: places off the home folder worth a size and never a button. By default every
    ///     absolute entry on `ScanPolicy.neverOffered` that is still measured, which is where the
    ///     30 GB of iOS simulator runtimes on this Mac comes from.
    ///   - snapshots: the local Time Machine snapshots, which decide the second number on every
    ///     row. Read for real when not supplied.
    static func read(roots: [URL]? = nil,
                     home: URL = StorageManifest.home(),
                     elsewhere: [URL]? = nil,
                     snapshots: SnapshotStanding? = nil,
                     listing: Int = howManyToList,
                     smallest: SizeOnDisk = smallestWorthShowing,
                     isCancelled: () -> Bool = { Task.isCancelled },
                     progress: (String) -> Void = { _ in }) -> Answer? {

        let held = snapshots ?? FreeSpace.localSnapshots(on: ScanPolicy.root(home: home))
        let starts = roots ?? [home]

        var candidates: [StorageWalk.Entry] = []
        var folders: [StorageWalk.Folder] = []

        guard let outcome = StorageWalk.walk(from: starts,
                                             home: home,
                                             snapshots: held,
                                             folderDepth: 2,
                                             isCancelled: isCancelled,
                                             progress: progress,
                                             folder: { folders.append($0) },
                                             visit: { entry in
            // ⭐ The floor is applied here rather than at the end, so a Mac with 400,000 files does
            // not build a 400,000-element array in order to throw away 399,960 of it.
            guard entry.onDisk >= smallest else { return }
            candidates.append(entry)
        }) else { return nil }

        // ⭐ Sorted on size **on disk**. See measurement 1 in the file note.
        candidates.sort { $0.onDisk > $1.onDisk }

        var items: [Item] = []
        for entry in candidates {
            guard items.count < listing else { break }
            guard let made = item(for: entry, snapshots: held) else { continue }
            items.append(made)
        }

        for made in placesOffTheHomeFolder(elsewhere ?? measuredPlacesOutsideTheHomeFolder(),
                                           home: home, snapshots: held, smallest: smallest,
                                           isCancelled: isCancelled) {
            items.append(made)
        }

        items.sort { $0.bytes.onDisk > $1.bytes.onDisk }
        if items.count > listing { items.removeSubrange(listing...) }

        let biggestPlaces = folders
            .sorted { $0.onDisk > $1.onDisk }
            .prefix(howManyPlaces)
            .map { Place(path: $0.path, name: $0.name, bytes: $0.bytes, files: $0.files) }

        return Answer(items: items,
                      places: Array(biggestPlaces),
                      total: outcome.bytes,
                      filesSeen: outcome.filesSeen,
                      cloudHolding: outcome.cloudHolding,
                      refused: outcome.refused,
                      row: row(items: items,
                               places: Array(biggestPlaces),
                               total: outcome.bytes,
                               filesSeen: outcome.filesSeen,
                               cloudHolding: outcome.cloudHolding,
                               refused: outcome.refused,
                               smallest: smallest))
    }

    /// One entry turned into a row on a screen, with its identity established and its Spotlight
    /// date read. `nil` when it has gone since the walk, which is ordinary on a live Mac.
    static func item(for entry: StorageWalk.Entry, snapshots: SnapshotStanding) -> Item? {
        guard let identity = StorageWalk.identify(entry.path) else { return nil }

        let handling: Handling = entry.refusal.map { Handling.cannot($0.why) } ?? .notCheckedYet
        let reason = entry.refusal.map(Says.becauseWeWillNotTouchIt) ?? Says.because(entry.onDisk)

        return Item(identity: identity,
                    path: entry.path,
                    name: entry.name,
                    bytes: entry.bytes,
                    kind: entry.kind,
                    // ⭐ A person's own. Never ticked, never swept — and it is the default, so an
                    // edit that drops this argument still produces the safe answer.
                    origin: .yours,
                    cloudStanding: entry.cloudStanding,
                    handling: handling,
                    modifiedOn: entry.modifiedOn,
                    lastOpenedOn: lastOpened(entry.path),
                    reason: reason)
    }

    /// The measured-but-never-offered places outside the home folder, as rows with no button.
    static func placesOffTheHomeFolder(_ urls: [URL],
                                       home: URL,
                                       snapshots: SnapshotStanding,
                                       smallest: SizeOnDisk,
                                       isCancelled: () -> Bool = { Task.isCancelled }) -> [Item] {
        var made: [Item] = []
        for url in urls {
            let path = url.path(percentEncoded: false)
            guard let refusal = ScanPolicy.refusal(for: path, home: home), refusal.stillMeasured,
                  ScanPolicy.descend(into: url, stayingOn: nil, home: home).isAllowed,
                  let bytes = StorageWalk.total(of: url, home: home, snapshots: snapshots,
                                                isCancelled: isCancelled),
                  bytes.onDisk >= smallest,
                  let identity = StorageWalk.identify(path)
            else { continue }

            made.append(Item(identity: identity,
                             path: path,
                             name: refusal.name,
                             bytes: bytes,
                             kind: .folder,
                             origin: .yours,
                             cloudStanding: .onThisMac,
                             // ⚠️ No button. One that fails when pressed teaches a person that this
                             // app's buttons are decorative.
                             handling: .cannot(refusal.why),
                             reason: Says.becauseWeWillNotTouchIt(refusal)))
        }
        return made
    }

    /// ⚠️ **Spotlight's `kMDItemLastUsedDate`, and never the filesystem's access time.** Our own
    /// research scan rewrote 2,012 access times by reading the files, so that field records us.
    ///
    /// Blank for 61% of the large files on this Mac. A blank is absent from `Item.lineFacts` rather
    /// than drawn as a dash, because a blank is not a value.
    static func lastOpened(_ path: String) -> Date? {
        guard let item = MDItemCreate(nil, path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    /// The absolute entries on the refusal list that are still worth a size. On this Mac that is the
    /// 30 GB of iOS simulator runtimes, which cannot be set aside at all.
    static func measuredPlacesOutsideTheHomeFolder() -> [URL] {
        ScanPolicy.neverOffered
            .filter { $0.place.hasPrefix("/") && $0.stillMeasured }
            .map { URL(filePath: $0.place) }
    }

    // MARK: The row

    static func row(items: [Item],
                    places: [Place],
                    total: Bytes,
                    filesSeen: Int,
                    cloudHolding: CloudHolding,
                    refused: UnreadablePlaces,
                    smallest: SizeOnDisk = smallestWorthShowing) -> StorageRow {

        var details = places.map(\.detail)
        details.append(DetailPair("Files counted", filesSeen.formatted()))
        if !items.isEmpty {
            details.append(DetailPair("The \(items.count) largest",
                                      Bytes.sum(items.map(\.bytes)).text))
        }
        if !cloudHolding.isEmpty { details.append(cloudHolding.detailPair) }
        details.append(DetailPair("How this list is sorted", Says.howThisIsSorted))
        details.append(DetailPair("Last opened", Says.whyLastOpenedIsOnlyAFact))

        let headline = items.first.map {
            "\($0.name) is your largest, at \($0.bytes.onDisk.text) on disk."
        } ?? Says.nothingIsBigEnough(smallest)

        return StorageRow(topic: .yourOwnFiles,
                          headline: headline,
                          measure: total,
                          count: items.isEmpty ? nil : items.count,
                          reason: Says.whyTheseAreListed,
                          items: items,
                          details: details,
                          refused: refused)
    }
}

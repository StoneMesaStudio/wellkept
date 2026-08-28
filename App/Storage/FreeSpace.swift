// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import WellkeptCore

//  FreeSpace.swift
//  Wellkept — App/Storage
//
//  ⭐ **The two answers to "how much room is left", and the arithmetic John approved.**
//
//  ## The measurement this file exists because of
//
//  Taken on this Mac, 2026-08-28, from the same volume in the same second:
//
//  | Reading | Bytes | What it means |
//  |---|---|---|
//  | `volumeAvailableCapacityKey` | 109,754,851,328 — **109.8 GB** | Room that is genuinely not in use |
//  | `volumeAvailableCapacityForImportantUsageKey` | 177,859,575,022 — **177.9 GB** | What Finder prints |
//  | `volumeAvailableCapacityForOpportunisticUsageKey` | 101,606,440,495 — 101.6 GB | Room for downloads that can wait |
//
//  **68.1 GB apart, and both numbers are correct.** Finder's answers a different question: how much
//  room macOS believes it *could* make under pressure — iCloud files it would remove from this Mac,
//  caches it would empty, snapshots it would thin.
//
//  ⚠️ **Finder's figure is not a number arithmetic works on.** Delete 12 GB and it does not rise by
//  12, because the purgeable pool moves underneath. That is why `FreeSpacePicture.finderShows` is a
//  `FinderFigure` — a type with a private byte count, no operators, and one named subtraction.
//
//  ## John's ruling, 2026-08-28
//
//  > *"Lead with the real one. Ours has to add up. So: the real number leads, with Finder's printed
//  > underneath and one line saying what the difference is. We are not contradicting Finder, we are
//  > explaining it, which is the one thing no other tool on the Mac does."*
//
//  ## The snapshot, which is why our figures look pessimistic
//
//  Time Machine cannot reach this Mac's backup drive, so one local snapshot from **25 August
//  06:25:03** is stuck. Verified: `tmutil listlocalsnapshots /` returns exactly one. While it is
//  there, deleting any file older than that moment returns **zero bytes** — the blocks are still
//  referenced.
//
//  The whole model is four lines in `SnapshotStanding.recoverable(onDisk:modifiedOn:)`, in
//  `WellkeptCore`, so it can be tested without a disk. This file only does the reading.
//
//  ## What this file may never do
//
//  - **Never promise a figure before a delete.** `estimate(...)` is named that way on purpose, and
//    the real number is taken by `measuring(_:)`, before and after, and reported as what happened.
//  - **Never mix the two free-space readings in one calculation.** The type system enforces it;
//    this comment is here for whoever tries to work around the type system.
//  - **Never say space was returned by setting something aside.** It never is: 391 MB across
//    100,000 files moved free space by −8 KiB.

// MARK: - Reading the disk

enum FreeSpace {

    // MARK: The volume

    /// ⚠️ **Never `/`.** Measured 2026-08-28: a scan started at the root counts the disk twice and
    /// reports 501 GB used on a 494 GB drive, because the Data volume is reachable both directly
    /// and through the firmlinks the sealed System volume publishes at `/Users`, `/Applications`
    /// and a dozen other names.
    ///
    /// The answer is taken from the home folder's own `statfs` rather than assumed to be
    /// `/System/Volumes/Data`: a Mac whose home folder is on an external disk, or a boot volume
    /// laid out by an older installer, has a different answer and it is the one that matters.
    static func dataVolume(home: URL = StorageManifest.home()) -> URL {
        if let volume = Movable.volume(of: home.path(percentEncoded: false)),
           volume.mountPoint != "/" {
            return URL(filePath: volume.mountPoint)
        }
        // The fallback names the modern layout explicitly, and falls back again to the home folder
        // itself — which is on the right volume even when we could not name that volume.
        let modern = URL(filePath: "/System/Volumes/Data")
        return FileManager.default.fileExists(atPath: modern.path(percentEncoded: false)) ? modern : home
    }

    // MARK: The two numbers

    /// What one reading of a volume produced.
    enum Reading: Sendable, Equatable {
        case read(FreeSpacePicture)
        /// The volume would not answer. **Never a zero** — a zero here reads as a full disk.
        case couldNotBeRead(Unreadable)

        var picture: FreeSpacePicture? {
            if case let .read(picture) = self { return picture }
            return nil
        }
    }

    /// ⭐ **The whole reading: both figures, named, plus the snapshots.**
    ///
    /// The two resource keys are deliberately fetched in one call so they describe the same instant.
    /// A person deleting files while this runs would otherwise get two readings seconds apart and a
    /// "difference" that is really elapsed time.
    static func read(volume: URL? = nil,
                     home: URL = StorageManifest.home(),
                     listSnapshots: Bool = true) -> Reading {
        let target = volume ?? dataVolume(home: home)

        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            // ⭐ THE REAL NUMBER. Bytes that are genuinely not in use. This one leads, and this one
            // is the only one anything subtracts from.
            .volumeAvailableCapacityKey,
            // ⚠️ FINDER'S NUMBER. Room macOS believes it could make under pressure. Printed
            // underneath, explained in one line, and never used in a sum.
            .volumeAvailableCapacityForImportantUsageKey,
        ]

        guard let values = try? target.resourceValues(forKeys: keys),
              let capacity = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacity
        else {
            // A volume that will not report its own size is not a permission problem — there is no
            // switch in System Settings for this — so it is `.notReported`, and the face says so
            // rather than drawing an empty bar.
            return .couldNotBeRead(.notReported)
        }

        let actuallyFree = SizeOnDisk(Int64(available))

        // `volumeAvailableCapacityForImportantUsage` is an Int64 already, and it is optional
        // because not every filesystem publishes it. A volume that does not is simply a volume with
        // nothing to explain, and the line disappears.
        let finder = values.volumeAvailableCapacityForImportantUsage.map { FinderFigure($0) }

        let snapshots = listSnapshots ? localSnapshots(on: target) : .none

        return .read(FreeSpacePicture(capacity: SizeOnDisk(Int64(capacity)),
                                      actuallyFree: actuallyFree,
                                      finderShows: finder,
                                      snapshots: snapshots,
                                      volumeName: name(of: target)))
    }

    /// What to call the volume in a sentence. A person recognises "this Mac's disk", not
    /// `/System/Volumes/Data`.
    static func name(of volume: URL) -> String {
        guard let reading = Movable.volume(of: volume.path(percentEncoded: false)) else {
            return "this Mac's disk"
        }
        return Movable.friendlyVolumeName(reading)
    }

    // MARK: The local snapshots

    /// ⚠️ **Reads the local Time Machine snapshots. No root, no authorization, no dialog.**
    ///
    /// `tmutil listlocalsnapshots` is readable by any user and asks nothing of anybody. There is no
    /// public API for this — the APFS snapshot list is reachable only through a private `fsctl` —
    /// so the supported command-line tool is the honest route, and its output format has been
    /// stable since High Sierra:
    ///
    /// ```
    /// Snapshots for disk /:
    /// com.apple.TimeMachine.2026-08-25-062503.local
    /// ```
    ///
    /// ⚠️ **A failure is `.couldNotBeRead`, not "there are none".** They are opposite answers: no
    /// snapshots means every delete returns the whole file, and an unread list means we may not
    /// promise anything at all. Collapsing the two would make a Mac we could not read look like the
    /// most generous case there is.
    static func localSnapshots(on volume: URL, alsoTryRoot: Bool = true) -> SnapshotStanding {
        var found: [String: LocalSnapshot] = [:]
        var anySucceeded = false

        var mounts = [volume.path(percentEncoded: false)]
        if alsoTryRoot { mounts.append("/") }

        for mount in mounts {
            guard let lines = runTMUtil(listingSnapshotsOn: mount) else { continue }
            anySucceeded = true
            for snapshot in parseSnapshots(lines) { found[snapshot.name] = snapshot }
        }

        guard anySucceeded else { return .couldNotBeRead }
        return SnapshotStanding(snapshots: Array(found.values), wasRead: true)
    }

    /// The snapshot names in tmutil's output. Anything that is not a dated snapshot name — the
    /// header line, a blank line, a future addition — is skipped rather than guessed at.
    static func parseSnapshots(_ output: String) -> [LocalSnapshot] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // tmutil stamps the name in local time, so the formatter stays in the current zone.
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"

        let prefix = "com.apple.TimeMachine."
        var snapshots: [LocalSnapshot] = []

        for raw in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix(prefix) else { continue }
            var stamp = String(line.dropFirst(prefix.count))
            if let dot = stamp.firstIndex(of: ".") { stamp = String(stamp[stamp.startIndex..<dot]) }
            guard let date = formatter.date(from: stamp) else { continue }
            snapshots.append(LocalSnapshot(name: line, takenOn: date))
        }
        return snapshots
    }

    /// `nil` when the tool is missing, failed, or did not answer. See the note on `localSnapshots`.
    ///
    /// ⚠️ No `sudo`, no authorization, and nothing that can raise a dialog. `listlocalsnapshots` is
    /// a read; every tmutil verb that changes anything is somewhere else and is not called here.
    private static func runTMUtil(listingSnapshotsOn mount: String) -> String? {
        let tool = URL(filePath: "/usr/bin/tmutil")
        guard FileManager.default.isExecutableFile(atPath: tool.path(percentEncoded: false)) else {
            return nil
        }

        let process = Process()
        process.executableURL = tool
        process.arguments = ["listlocalsnapshots", mount]

        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return nil }

        // Read before waiting: a pipe that fills while nobody drains it deadlocks the child, and a
        // Mac with many snapshots is exactly where that would first be noticed.
        let data = (try? out.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - ⭐ The arithmetic John approved

extension FreeSpace {

    /// **The sentences about what a press will and will not do.**
    ///
    /// They live together because they are one argument told in four places, and because the one
    /// thing that must never happen is two screens giving a person different arithmetic for the
    /// same button.
    enum Says {

        /// ⭐ **John's sheet, 2026-08-28, for a person's own file.** One at a time, never
        /// pre-ticked, and the arithmetic is stated *before* the press rather than explained after
        /// it.
        ///
        /// > *"this will not make your Mac emptier today; to get the 12 GB back you also have to
        /// > empty the quarantine"*
        ///
        /// The figure in the second half is `recoverableToday`, not the size on disk, because that
        /// is the number the person would actually see afterwards. Where a snapshot is holding the
        /// blocks the two differ by up to 150×, and quoting the larger one would be a promise the
        /// second press cannot keep.
        static func arithmetic(for bytes: Bytes) -> String {
            guard !bytes.recoverableToday.isZero else {
                return "This will not make your Mac emptier today, and emptying the quarantine "
                     + "afterwards will not either — a Time Machine snapshot is still holding "
                     + "these blocks. Setting it aside is still how you stop using it."
            }
            return "This will not make your Mac emptier today. To get the "
                 + "\(bytes.recoverableToday.text) back you also have to empty the quarantine."
        }

        /// The two buttons on that sheet, in John's order: the ordinary one first, and the one for
        /// somebody who needs the room today second. Cancel is the sheet's visible exit and is not
        /// one of these.
        ///
        /// ⚠️ The second button is the answer to the consequence drawn out on 2026-08-28: **if the
        /// disk is full today, setting something aside is the wrong button.** Wanting the space
        /// back now means setting aside and then emptying, deliberately, in one sitting. Offering
        /// it here is what stops somebody setting 40 GB aside and watching nothing happen.
        static let setAsideOnly = "Set aside"
        static let setAsideAndEmpty = "Set aside, then empty the quarantine"

        /// What the row says once machine junk has been swept. **Never a figure that came back**,
        /// because none did.
        static func afterSettingAside(_ onDisk: SizeOnDisk) -> String {
            "\(onDisk.text) set aside. Nothing is deleted and no space comes back until you empty "
            + "the quarantine."
        }

        /// ⚠️ **An estimate, and it says so.** Named `estimate` rather than `willReturn` because a
        /// snapshot can take the whole figure away between this sentence and the press, and because
        /// the real number is measured afterwards by `measuring(_:)`.
        static func estimate(_ bytes: Bytes) -> String {
            bytes.recoverableToday.isZero
                ? "Emptying the quarantine will not make room today — a Time Machine snapshot is "
                + "still holding these blocks."
                : "Emptying the quarantine should make about \(bytes.recoverableToday.text) of room."
        }

        /// The line for a disk that is already full, from `QuarantineWords` so there is one copy.
        static var whenTheDiskIsAlreadyFull: String { QuarantineWords.whenTheDiskIsAlreadyFull }
    }

    // MARK: Measuring what actually happened

    /// What free space did, measured either side of a real delete.
    ///
    /// ⚠️ **This is the only thing in the app allowed to state a figure that came back**, and it
    /// states one that was measured rather than one that was calculated. On a Mac with a stuck
    /// snapshot the two are routinely far apart, and the measured one is the one a person can check
    /// in About This Mac.
    struct Change: Sendable, Equatable {
        let before: SizeOnDisk
        let after: SizeOnDisk

        /// How much room appeared. Zero where the blocks were held by a snapshot — which is a real
        /// answer and is said plainly.
        var difference: SizeOnDisk { after - before }

        /// ⚠️ Negative is normal and is not an error: the Mac keeps working while a delete runs, and
        /// a browser writing a cache in the same second can swallow the whole result.
        var wentDown: Bool { after < before }

        var sentence: String {
            if wentDown {
                return "Free space did not go up. This Mac was writing while that ran, so the "
                     + "figure moved the other way."
            }
            if difference.isZero {
                return "Free space did not change. A Time Machine snapshot is still holding those "
                     + "blocks; until it goes, deleting them makes no room."
            }
            return "\(difference.text) of room came back."
        }
    }

    /// Run `work`, having read free space before and after it, and hand back both.
    ///
    /// The shape is deliberate: there is no way to call this and forget to take the second reading,
    /// and no way to report a figure without having taken the first. A reading that failed at
    /// either end produces `nil` — **not a zero**, which would read as "nothing came back".
    static func measuring<T>(volume: URL? = nil,
                             _ work: () throws -> T) rethrows -> (result: T, change: Change?) {
        let before = read(volume: volume, listSnapshots: false).picture?.actuallyFree
        let result = try work()
        let after = read(volume: volume, listSnapshots: false).picture?.actuallyFree

        guard let before, let after else { return (result, nil) }
        return (result, Change(before: before, after: after))
    }
}

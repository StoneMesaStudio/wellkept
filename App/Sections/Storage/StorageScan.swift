// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import WellkeptCore

//  StorageScan.swift
//  Wellkept — App/Sections/Storage
//
//  ⭐ **The seam. The one place the five Storage readers are called, in the section's own order.**
//
//  Each reader knows nothing about the others and nothing about a view. This runs them, builds the
//  five rows, and hands over one `StorageReport`. It is the same shape as `SecurityModel`'s sweep
//  and `AppsModel`'s, because they are the same screen with different contents.
//
//  ## The five rows, and why in that order
//
//  1. **What is using the space** — the picture. No buttons at all: `whatIsUsingSpace` is a
//     `BigFiles.Place` list, and a `Place` has no field a button could live in.
//  2. **Machine junk** — second, so the one press that needs no judgement finishes before any
//     judgement is asked for. Put a person's documents above it and the first thing anybody meets
//     on this screen is their own files beside a button.
//  3. **Your own large files** — revealed, sized, sorted. Never ticked.
//  4. **Duplicates** — the smallest prize and the most work: 387 MB across 633 judgement calls on
//     this Mac, and 94% of the groups home-wide are inside a project folder where deleting one
//     breaks a build.
//  5. **What is set aside** — last, because it is the only row where space actually comes back,
//     and it comes back at the second press.
//
//  ## ⚠️ What this file may never do
//
//  - **Decide what is junk.** `JunkClassifier` does that, and `Scanner.Entry` has no `origin` field
//    at all so that no walk can decide it in passing.
//  - **Report a figure for something it could not read.** `StorageRow.init` drops the measure when
//    `unreadable` is set, and the refusals are carried rather than swallowed.
//  - **Omit the gap.** `StorageReport.init` computes `MeasuredGap` itself from `measured`, which is
//    a required argument. There is no code path here or anywhere that produces a Storage report
//    without naming the difference between what macOS says is used and what we accounted for.

// MARK: - What one run produced

/// The report, plus the three things a `StorageRow` has nowhere to carry.
///
/// `StorageRow.items` is a flat list — right for a list of files, wrong for the places picture and
/// wrong for duplicate groups, where flattening loses which copy belongs with which. So they travel
/// beside the report rather than being flattened into it.
struct StorageAnswer: Sendable {

    let report: StorageReport

    /// Where the weight sits, one and two levels down. **A picture, not a proposal.**
    let places: [BigFiles.Place]

    /// Every duplicate set, still grouped. `row.items` flattens them for the generic row machinery;
    /// a view that wants to draw the sets reads this.
    let groups: [Duplicates.Group]

    /// What the classifier said about each piece of machine junk, including the ones it decided not
    /// to tick and why.
    let junk: [JunkClassifier.Classified]

    /// What is in quarantine right now. `nil` when the ledger could not be read at all — which is
    /// not the same as an empty quarantine and is never drawn as one.
    let setAside: Quarantine.Summary?

    init(report: StorageReport,
         places: [BigFiles.Place] = [],
         groups: [Duplicates.Group] = [],
         junk: [JunkClassifier.Classified] = [],
         setAside: Quarantine.Summary? = nil) {
        self.report = report
        self.places = places
        self.groups = groups
        self.junk = junk
        self.setAside = setAside
    }

    func row(_ topic: StorageTopic) -> StorageRow? { report.row(topic) }

    /// ⭐ The machine junk that arrives ticked. Empty for every other topic, by construction.
    var preSelected: [Item] { report.row(.machineJunk)?.preSelected ?? [] }
}

// MARK: - The scan

enum StorageScan {

    /// What the app is doing right now, in words somebody can read while they wait.
    ///
    /// ⚠️ **No percentage and no estimate.** A full sweep of the five roots took 56.7 seconds on
    /// this Mac for 983,868 files, and with Full Disk Access granted it will be slower still —
    /// because the 68 folders it was refused are folders it would then walk. Nothing here prints a
    /// time, and `ScanPolicy.Running.whyThereIsNoEstimate` says why in one sentence.
    enum Stage: String, CaseIterable, Sendable, Hashable {
        case freeSpace
        case machineJunk
        case yourOwnFiles
        case duplicates
        case setAside

        static var count: Int { allCases.count }
        var step: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

        var sentence: String {
            switch self {
            case .freeSpace:    "Reading how much room is left, and what Finder is counting."
            case .machineJunk:  "Looking for things this Mac made and will make again."
            case .yourOwnFiles: "Sizing your own files, largest first."
            case .duplicates:   "Comparing files that might be identical."
            case .setAside:     "Reading what is already set aside."
            }
        }
    }

    /// **The whole run.** Blocking, and long — belongs on a detached task and never where a window
    /// is waiting to draw. `nil` if it was cancelled.
    static func run(home: URL = StorageManifest.home(),
                    now: Date = Date(),
                    isCancelled: () -> Bool = { Task.isCancelled },
                    onStage: (Stage) -> Void = { _ in },
                    progress: (String) -> Void = { _ in }) -> StorageAnswer? {

        ScanPolicy.prepareThisThread()

        // ── 1. Free space. Both numbers, and the snapshots every later figure depends on.
        onStage(.freeSpace)
        let reading = FreeSpace.read(home: home)
        guard let picture = reading.picture else {
            // A volume that will not report its own size cannot be scanned honestly: every second
            // number on this screen is arithmetic against a first one we do not have.
            return nil
        }
        let snapshots = picture.snapshots

        // ── 2. Machine junk.
        onStage(.machineJunk)
        guard let junk = JunkSweep.read(home: home, snapshots: snapshots, now: now,
                                        isCancelled: isCancelled, progress: progress)
        else { return nil }

        // ── 3. A person's own files.
        onStage(.yourOwnFiles)
        guard let big = BigFiles.read(home: home, snapshots: snapshots,
                                      isCancelled: isCancelled, progress: progress)
        else { return nil }

        // ── 4. Duplicates.
        onStage(.duplicates)
        guard let dupes = Duplicates.find(home: home, snapshots: snapshots,
                                          isCancelled: isCancelled, progress: progress)
        else { return nil }

        // ── 5. What is already set aside.
        onStage(.setAside)
        let summary = Quarantine.summary(home: home, now: now)

        return assemble(freeSpace: picture,
                        junk: junk,
                        big: big,
                        dupes: dupes,
                        summary: summary,
                        snapshots: snapshots,
                        now: now)
    }

    /// Pure. Every row this section can draw, from readings somebody else took.
    ///
    /// Split out from `run` so demo mode builds its two Macs through **the same** row builders the
    /// real check uses. A demo that hand-wrote its sentences would photograph a screen the app is
    /// no longer capable of producing.
    static func assemble(freeSpace: FreeSpacePicture,
                         junk: JunkSweep.Found,
                         big: BigFiles.Answer,
                         dupes: Duplicates.Answer,
                         summary: Quarantine.Summary?,
                         snapshots: SnapshotStanding,
                         now: Date = Date()) -> StorageAnswer {

        let rows: [StorageRow] = [
            picture(big, freeSpace: freeSpace),
            JunkSweep.row(junk),
            big.row,
            dupes.row,
            setAsideRow(summary, snapshots: snapshots, now: now),
        ]

        // Everywhere anything was refused, gathered once so the face says it once rather than five
        // times. **Never a zero** — a place we could not read is named, not counted as empty.
        let refusedCount = big.refused.count + junk.refused.count + dupes.refused.count
        let notable = Array(Set(big.refused.notable + junk.refused.notable + dupes.refused.notable))
            .sorted()
            .prefix(8)
        let refused: UnreadablePlaces = refusedCount == 0
            ? .sawEverything
            : UnreadablePlaces(count: refusedCount, notable: Array(notable))

        let report = StorageReport(freeSpace: freeSpace,
                                   rows: rows,
                                   // ⭐ Required, and the gap is computed from it. What the walk
                                   // actually accounted for — never inflated to make the sums look
                                   // tidy, and never an "Other" slice.
                                   measured: big.total.onDisk,
                                   refused: refused,
                                   cloudHolding: big.cloudHolding,
                                   ranAt: now)

        return StorageAnswer(report: report,
                             places: big.places,
                             groups: dupes.groups,
                             junk: junk.junk,
                             setAside: summary)
    }

    // MARK: - Row 1 · the picture

    /// **Where the space went, largest first — and nothing to press.**
    ///
    /// `items` is deliberately empty. The places are `DetailPair`s and a typed list beside the row;
    /// an `Item` here would be a thing with a path and a size sitting in a list whose siblings all
    /// carry buttons, and somebody would eventually give it one.
    static func picture(_ big: BigFiles.Answer, freeSpace: FreeSpacePicture) -> StorageRow {
        var details = freeSpace.detailPairs
        details.append(DetailPair("What this scan accounted for", big.total.text))
        details.append(DetailPair("Files counted", big.filesSeen.formatted()))
        for place in big.places { details.append(DetailPair(place.name, place.bytes.text)) }

        let headline: String
        if let biggest = big.places.first {
            headline = "\(biggest.name) is the heaviest place on this Mac, at "
                     + "\(biggest.bytes.onDisk.text) on disk."
        } else {
            headline = "\(freeSpace.used.text) is in use on \(freeSpace.volumeName)."
        }

        return StorageRow(topic: .whatIsUsingSpace,
                          headline: headline,
                          measure: big.total,
                          count: big.places.isEmpty ? nil : big.places.count,
                          reason: Says.thePictureIsNotAProposal,
                          details: details,
                          refused: big.refused)
    }

    // MARK: - Row 5 · what is set aside

    /// **The permanent row: what is waiting, how old the oldest is, and the one button that ends
    /// the sequence.**
    ///
    /// ⚠️ **A ledger that could not be read is not an empty quarantine.** Zero is the one number
    /// here that means somebody's files are unaccounted for, so trouble becomes an `unreadable`
    /// row — which drops the measure and the count on its way through `StorageRow.init` — rather
    /// than a row saying nothing is set aside.
    static func setAsideRow(_ summary: Quarantine.Summary?,
                            snapshots: SnapshotStanding,
                            now: Date = Date()) -> StorageRow {

        guard let summary else {
            return StorageRow.unreadable(.setAside, .notReported,
                                         about: "What is set aside",
                                         reason: Says.theLedgerWasNotRead)
        }
        if let trouble = summary.trouble {
            return StorageRow.unreadable(.setAside, .notReported,
                                         about: "What is set aside",
                                         reason: trouble.sentence)
        }

        let onDisk = SizeOnDisk(summary.bytes)
        // ⚠️ The second number, and it is the whole reason this row is not just a count. On a Mac
        // with a stuck snapshot, emptying a 40 GB quarantine returns nothing at all today, and the
        // sentence under the button says so instead of promising 40 GB.
        let bytes = snapshots.bytes(onDisk: onDisk, modifiedOn: summary.oldest)

        var details: [DetailPair] = []
        if summary.count > 0 {
            details.append(DetailPair("Waiting", "\(summary.count.formatted())"))
            details.append(DetailPair("What emptying it would do", FreeSpace.Says.estimate(bytes)))
        }
        if let ready = summary.readySentence {
            details.append(DetailPair("Past \(Expiry.days) days", ready))
        }
        if let unaccounted = summary.unaccountedSentence {
            details.append(DetailPair("Not where Wellkept put it", unaccounted))
        }

        return StorageRow(topic: .setAside,
                          headline: summary.rowSentence(now: now),
                          measure: summary.count == 0 ? nil : bytes,
                          count: summary.count == 0 ? nil : summary.count,
                          reason: summary.count == 0 ? nil : Says.theSequence,
                          details: details)
    }

    // MARK: - The words

    enum Says {

        /// ⚠️ The sentence that makes row one safe to show. Every commercial cleaner turns this
        /// list into a proposal; here it is a map.
        static let thePictureIsNotAProposal =
            "This is where the room went. Nothing on this list is chosen, nothing here is a "
            + "problem, and there is nothing to press."

        static let theSequence =
            "Set aside, then empty the quarantine. The room appears at the second press, not the "
            + "first."

        static let theLedgerWasNotRead =
            "Wellkept has not read its own record of what is set aside, so it will not tell you a "
            + "number. Nothing has been deleted."
    }
}

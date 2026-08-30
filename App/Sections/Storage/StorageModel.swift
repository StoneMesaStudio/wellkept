// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import Observation
import WellkeptCore

//  StorageModel.swift
//  Wellkept — App/Sections/Storage
//
//  ⭐ **What the Storage screen has read, and the two ceremonies it can run.**
//
//  ## ⚠️ The two ceremonies are the section's whole design, and they live here
//
//  Asked on 2026-08-28: whether setting aside machine junk and setting aside one of your own big
//  files should look and behave differently. **Yes — two ceremonies, same four verbs.**
//
//  - **Machine junk — `setAsideTicked()`.** A batch. Things arrive ticked, one press moves all of
//    them, and afterwards the row says what was set aside. Nobody is asked about any of them
//    individually, because there is nothing to decide: whatever wrote it writes it again.
//  - **A person's own file — `setAside(_:thenEmpty:)`.** One at a time, **never pre-ticked**, and
//    a sheet states the arithmetic before the press. There is no batch entry point for a person's
//    own files anywhere in this file, which is the mechanical half of the promise; the other half
//    is `Origin.maySweep`, which is `false` for `.yours`.
//
//  ## ⭐ The model stores a person's OVERRIDES, and the default comes from the classifier
//
//  The obvious implementation stores the ticked ids and seeds them when a scan lands. Every path
//  that draws the row without a scan behind it — demo mode, a view-shot, a ⌘+ rebuild — then shows
//  an empty batch and a button reading "Set Aside 0 Things". That was the first version, and the
//  picture caught it.
//
//  So nothing is seeded. `isTicked` asks the classifier's own answer (`arrivesTicked`, which is
//  already the intersection of what `JunkClassifier` decided and what `Item` permits) and consults
//  a dictionary of what the **person** has since changed. Two consequences worth having:
//
//  - **The annoyance filter keeps working.** A half-finished download used within the last month
//    arrives unticked with its reason on the row, because the classifier said so and nothing here
//    overrides it. That filter can only ever take a tick away, and this is where that stays true.
//  - **The law is enforced on the way out.** `tickedItems(in:)` reads `StorageRow.preSelected`,
//    which returns `[]` for every topic but machine junk whatever the items claim. A stale id, a
//    re-scan, or a future screen that ticks the wrong list still cannot produce a request to sweep
//    somebody's documents. Proved by
//    `StorageSectionTests.nothingOfYoursCanBeSweptEvenWhenTicked`.
//
//  ## ⚠️ Nothing here composes a sentence about bytes
//
//  Every figure a person reads comes from `Quarantine.Report.sentence`, `DeleteReport.sentence`,
//  `Quarantine.Summary.rowSentence` or `FreeSpace.Says`. Those are the approved sentences, and
//  the one that reports space coming back measures it before and after rather than predicting it.

/// One thing the scan said while it was running. `Sendable` because it crosses from the detached
/// walk back to the screen.
enum ScanNote: Sendable, Equatable {
    case stage(StorageScan.Stage)
    case place(String)
}

@MainActor
@Observable
final class StorageModel {

    // MARK: What the screen draws

    /// The last complete answer. `nil` until the first scan finishes, which is the ordinary state:
    /// Storage never runs by itself.
    private(set) var answer: StorageAnswer?

    /// A scan is running now.
    private(set) var isScanning = false

    /// Which of the five readers is running. `nil` when nothing is.
    private(set) var stage: StorageScan.Stage?

    /// Where it is looking at this moment. A place, never a percentage and never a time — see
    /// `ScanPolicy.Running.whyThereIsNoEstimate`.
    private(set) var place: String?

    /// True while a verb is in flight. The buttons grey rather than queue.
    private(set) var isWorking = false

    /// What the last press did, in the engine's own words. Never re-composed here.
    private(set) var lastWord: String?

    /// Why one row would not budge, kept against that row so the reason is where the button is.
    private(set) var rowWord: [String: String] = [:]

    /// ⭐ **What the person changed, by `Item.id`.** Absent means "whatever the classifier said".
    /// See the note at the top of this file for why nothing is seeded here.
    private(set) var overrides: [String: Bool] = [:]

    /// The quarantine's own list, which now lives on this screen. Held here rather than made by the
    /// view so that a ⌘+ press does not throw away a reading of the ledger — or the sentence
    /// describing something that was just removed for good.
    let quarantine: QuarantineModel

    // MARK: Life

    let home: URL
    private var running: Task<StorageAnswer?, Never>?

    init(home: URL = StorageManifest.home()) {
        self.home = home
        self.quarantine = QuarantineModel(home: home)
    }

    // MARK: - Scanning

    /// Run the whole sweep. Long — about a minute on one real Mac for a million files — so every reader
    /// runs on a detached task and the screen fills in stage by stage while it does.
    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        stage = nil
        place = nil
        lastWord = nil
        rowWord = [:]

        let home = self.home
        let (notes, continuation) = AsyncStream<ScanNote>.makeStream()

        let work = Task.detached(priority: .userInitiated) { () -> StorageAnswer? in
            defer { continuation.finish() }
            return StorageScan.run(home: home,
                                   isCancelled: { Task.isCancelled },
                                   onStage: { continuation.yield(.stage($0)) },
                                   progress: { continuation.yield(.place($0)) })
        }
        running = work

        let watcher = Task { @MainActor [weak self] in
            for await note in notes {
                switch note {
                case let .stage(stage): self?.stage = stage; self?.place = nil
                case let .place(place): self?.place = place
                }
            }
        }

        // ⚠️ A detached task does not inherit cancellation from the task that awaits it. Without
        // this, pressing Cancel would change the button while the disk carried on being walked.
        let result = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
        await watcher.value

        running = nil
        isScanning = false
        stage = nil
        place = nil

        // ⚠️ A cancelled run leaves the previous answer alone. A partial scan is not a shorter
        // answer, it is a wrong one, and the first thing anybody would do with it is act on it.
        guard let result else { return }
        answer = result
        // A fresh sweep is a fresh list, so an override about something that is no longer there
        // stops meaning anything. The batch goes back to whatever the classifier says.
        overrides = [:]
        await quarantine.load()
    }

    /// Stop the scan. What was already read is kept; what was half-read is thrown away.
    func cancelScan() {
        running?.cancel()
    }

    // MARK: - ⭐ Ceremony one · the batch, for machine junk only

    /// Everything ticked in one row, and it can only ever be machine junk.
    ///
    /// ⚠️ **`StorageRow.preSelected` is the source, not `items`.** It returns `[]` for every topic
    /// but machine junk whatever the items claim, and drops anything the engine could not hold. So
    /// the worst a wrong caller can do is hand this the wrong row and get nothing back.
    /// - Parameter arriving: the ids the classifier said arrive ticked, which is
    ///   `JunkClassifier.arrivingTicked` on the run that produced this row. Passed in rather than
    ///   stored, so the answer is the classifier's on every draw — including the draws that have no
    ///   scan behind them at all.
    func tickedItems(in row: StorageRow, arriving: Set<String> = []) -> [Item] {
        row.preSelected.filter { isTicked($0, arrivesTicked: arriving.contains($0.id)) }
    }

    /// Both numbers for the batch. What the one press is about.
    func tickedBytes(in row: StorageRow, arriving: Set<String> = []) -> Bytes {
        Bytes.sum(tickedItems(in: row, arriving: arriving).map(\.bytes))
    }

    /// Whether anything in the batch is somewhere iCloud syncs. Drives the one line.
    func tickedTouchICloud(in row: StorageRow, arriving: Set<String> = []) -> Bool {
        tickedItems(in: row, arriving: arriving).contains { $0.cloudStanding != .onThisMac }
    }

    /// ⭐ The classifier's answer, unless the person has said otherwise — and never for anything
    /// that is not the machine's.
    func isTicked(_ item: Item, arrivesTicked: Bool) -> Bool {
        guard item.mayBePreSelected else { return false }
        return overrides[item.id] ?? arrivesTicked
    }

    /// ⚠️ Refuses anything that is not machine junk, whatever the caller believes. A checkbox is a
    /// view, and a view is the wrong place for the law.
    func setTicked(_ item: Item, _ on: Bool) {
        guard item.mayBePreSelected else { return }
        overrides[item.id] = on
    }

    /// Tick or untick the whole batch. **This is a person pressing a control**, so it overrides the
    /// classifier in both directions — including re-ticking the thing the annoyance filter took a
    /// tick off, which is exactly what "Tick All" means.
    func setAllTicked(_ on: Bool, in row: StorageRow) {
        for item in row.preSelected { overrides[item.id] = on }
    }

    /// **The one press.** Everything ticked, set aside in one batch, and never asked about again.
    func setAsideTicked(in row: StorageRow, arriving: Set<String> = []) async {
        let batch = tickedItems(in: row, arriving: arriving)
        guard !batch.isEmpty else { return }
        await perform(batch, reasonFor: { $0.reason }, thenEmpty: false)
        // What moved is no longer there, so it stops being an offer. The row itself is stale until
        // the next scan, and the button at the top of the screen is how that is put right.
        for item in batch { overrides[item.id] = false }
    }

    // MARK: - ⭐ Ceremony two · one at a time, for a person's own file

    /// **One file, chosen by a person, after a sheet that stated the arithmetic.**
    ///
    /// - Parameter thenEmpty: The second route. Setting something aside returns no room at all;
    ///   somebody who needs the space today wants both halves in one sitting, and offering only the
    ///   first is how a person sets 40 GB aside and watches nothing happen.
    func setAside(_ item: Item, thenEmpty: Bool) async {
        await perform([item], reasonFor: { _ in StorageWords.becauseYouChoseIt }, thenEmpty: thenEmpty)
    }

    /// What emptying the quarantine would take with it, for the sheet to say before the second
    /// route is offered. `nil` when there is nothing already waiting.
    var alreadyWaiting: Quarantine.Summary? {
        guard let summary = quarantine.summary, summary.count > 0 else { return nil }
        return summary
    }

    // MARK: - The engine, called once

    /// Both ceremonies end here. One implementation, so the two cannot drift on what a move is.
    private func perform(_ items: [Item],
                         reasonFor: (Item) -> String,
                         thenEmpty: Bool) async {
        guard !isWorking, !items.isEmpty else { return }
        isWorking = true

        let requests = items.map {
            Quarantine.Request(URL(filePath: $0.path), section: .storage, reason: reasonFor($0))
        }
        let home = self.home
        let report = await Task.detached(priority: .userInitiated) {
            Quarantine.quarantine(requests, home: home)
        }.value

        var word = report.sentence
        for outcome in report.refused where outcome.refusal != nil {
            rowWord[outcome.path] = outcome.refusal
        }

        // ⚠️ The second route, and it is a real delete with no undo. It runs only because somebody
        // pressed a button whose words were "Set aside, then empty the quarantine", and the figure
        // it reports is measured either side rather than predicted.
        if thenEmpty, !report.moved.isEmpty {
            let deleted = await Task.detached(priority: .userInitiated) { () -> String in
                let waiting = Quarantine.records(home: home)
                guard !waiting.isEmpty else { return "" }
                return Quarantine.delete(waiting, expecting: waiting.count, home: home).sentence
            }.value
            if !deleted.isEmpty { word += " \(deleted)" }
        }

        isWorking = false
        lastWord = word

        await quarantine.load()
        await refreshSetAside()
    }

    /// Re-read what is set aside and rebuild that one row, without walking the disk again.
    ///
    /// ⚠️ The other four rows are left exactly as they were, and they are now slightly stale — the
    /// things just set aside are no longer where they were. That is the honest state: re-scanning
    /// silently under somebody would move the list they were reading. The row that changed says so,
    /// and the button to run the whole thing again is at the top of the screen.
    func refreshSetAside() async {
        guard let current = answer else { return }
        let summary = quarantine.summary
        let row = StorageScan.setAsideRow(summary,
                                          snapshots: current.report.freeSpace.snapshots)
        var rows = current.report.rows.filter { $0.topic != .setAside }
        rows.append(row)

        let report = StorageReport(freeSpace: current.report.freeSpace,
                                   rows: rows,
                                   measured: current.report.measured,
                                   refused: current.report.refused,
                                   cloudHolding: current.report.cloudHolding,
                                   ranAt: current.report.ranAt)
        answer = StorageAnswer(report: report,
                               places: current.places,
                               groups: current.groups,
                               junk: current.junk,
                               setAside: summary)
    }

    func clearLastWord() { lastWord = nil }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import WellkeptCore

//  QuarantineModel.swift
//  Wellkept — App/SetAside
//
//  ⭐ **What the quarantine screen has read, and the four verbs it can run.**
//
//  A thin layer over `Quarantine`, and deliberately thin: the engine holds no cached list, because
//  a cached list is a list that can disagree with the disk — and the disk is the one holding the
//  files. So this reads fresh on every appearance and again after every action, and it never
//  answers from memory.
//
//  ## ⚠️ `home` is injected, and that is what makes this testable
//
//  Every entry point in the engine takes `home:`. The app passes nothing and gets the real one; the
//  view-shot harness and the tests pass a sandbox they made thirty milliseconds earlier. Nothing in
//  this app that moves somebody's files is ever exercised against a real home folder by a test.
//
//  ## ⚠️ Why `expecting:` is passed the list that was on screen
//
//  `Quarantine.delete(_:expecting:)` refuses the whole batch when the count does not match. The
//  classic way software deletes the wrong thing is a call site handing over the whole list where it
//  meant the selection — so `empty()` captures the array it is about to delete, and passes that
//  same array's count. One row's Delete passes exactly one.

/// One pass over the disk, read off the main actor and handed back whole.
///
/// ⚠️ **At file scope, not nested inside the model.** A type nested in a `@MainActor` class inherits
/// that isolation, and a detached task cannot return one.
struct QuarantineReading: Sendable {
    let summary: Quarantine.Summary
    let records: [QuarantineRecord]
    let missing: Set<UUID>
}

@MainActor
@Observable
final class QuarantineModel {

    // MARK: What the screen draws

    /// The permanent row's figures. `nil` until the first read finishes.
    private(set) var summary: Quarantine.Summary?

    /// Everything set aside, in the screen's order: **ready first, oldest first within each
    /// group.** `Expiry.sortedForTheScreen` decides that, not this file.
    private(set) var records: [QuarantineRecord] = []

    /// Records whose file is not where the ledger says it is. Marked on the row rather than hidden:
    /// the record is the only surviving statement of where the file came from.
    private(set) var missing: Set<UUID> = []

    /// The ignore list, for Settings.
    private(set) var ignored: [IgnoredItem] = []

    /// ⚠️ Shown **instead of** a count, never beside one.
    private(set) var ignoreTrouble: LedgerTrouble?

    /// True while a read or a verb is in flight. The verbs grey rather than queue.
    private(set) var isWorking = false

    /// Whether the first read has finished. Distinguishes "nothing is set aside" from "we have not
    /// looked yet", which look identical and mean different things.
    private(set) var hasRead = false

    /// What the last action did, in the engine's own words — `RestoreReport.sentence` or
    /// `DeleteReport.sentence`, never re-composed here. `DeleteReport.sentence` is the one place in
    /// the app that reports a figure for space, and it reports what was **measured** afterwards.
    private(set) var lastWord: String?

    /// Why one row would not budge, kept against that row so the reason is where the button is.
    private(set) var rowWord: [UUID: String] = [:]

    // MARK: Life

    let home: URL

    init(home: URL = StorageManifest.home()) {
        self.home = home
    }

    // MARK: Reading

    /// Read the ledger, the sizes and the store. Safe to call again; runs off the main thread.
    func load(now: Date = Date()) async {
        let home = home
        let loaded = await Task.detached(priority: .userInitiated) {
            Self.read(home: home, now: now)
        }.value

        summary = loaded.summary
        records = loaded.records
        missing = loaded.missing
        // A note about a row that is no longer on screen is a note nobody can act on.
        rowWord = rowWord.filter { id, _ in loaded.records.contains { $0.id == id } }
        hasRead = true
    }

    func loadIgnored() async {
        let home = home
        let reading = await Task.detached(priority: .userInitiated) {
            Quarantine.ignored(home: home)
        }.value
        ignored = reading.items.sorted { $0.ignoredOn > $1.ignoredOn }
        ignoreTrouble = reading.trouble
    }

    fileprivate nonisolated static func read(home: URL, now: Date) -> QuarantineReading {
        let summary = Quarantine.summary(home: home, now: now)
        let records = Expiry.sortedForTheScreen(Quarantine.records(home: home), now: now)
        let fileManager = FileManager.default
        let missing = Set(records
            .filter { !fileManager.fileExists(atPath: $0.quarantinedPath) }
            .map(\.id))
        return QuarantineReading(summary: summary, records: records, missing: missing)
    }

    // MARK: The verbs

    /// Put one item back where it came from.
    ///
    /// Nothing is ever written over: a path that is occupied again refuses, and the reason lands on
    /// the row rather than in a dialog.
    func restore(_ record: QuarantineRecord) async {
        guard !isWorking else { return }
        isWorking = true
        let home = home
        let report = await Task.detached(priority: .userInitiated) {
            Quarantine.restore([record], home: home)
        }.value
        isWorking = false

        lastWord = report.sentence
        rowWord[record.id] = report.stuck.first?.refusal?.sentence
        await load()
    }

    /// Remove one item for good. The count is one, because one is what was shown.
    func delete(_ record: QuarantineRecord) async {
        guard !isWorking else { return }
        isWorking = true
        let home = home
        let report = await Task.detached(priority: .userInitiated) {
            Quarantine.delete([record], expecting: 1, home: home)
        }.value
        isWorking = false

        lastWord = report.sentence
        rowWord[record.id] = report.refused.first?.sentence
        await load()
    }

    /// Remove everything that is on screen.
    ///
    /// ⚠️ **The list that was shown is the list that is deleted**, and its own count is what
    /// `expecting:` gets. A mismatch removes nothing, which is the point.
    func empty() async {
        guard !isWorking else { return }
        let shown = records
        guard !shown.isEmpty else { return }
        isWorking = true
        let home = home
        let report = await Task.detached(priority: .userInitiated) {
            Quarantine.delete(shown, expecting: shown.count, home: home)
        }.value
        isWorking = false

        lastWord = report.sentence
        for refusal in report.refused { rowWord[refusal.record.id] = refusal.sentence }
        await load()
    }

    /// Take one entry off the ignore list, so its section can raise it again.
    func stopIgnoring(_ item: IgnoredItem) async {
        guard !isWorking else { return }
        isWorking = true
        let home = home
        let trouble = await Task.detached(priority: .userInitiated) {
            Quarantine.stopIgnoring(item.id, home: home)
        }.value
        isWorking = false

        ignoreTrouble = trouble
        lastWord = trouble?.sentence
            ?? "\(item.name) can be reported again the next time that check runs."
        await loadIgnored()
    }

    func clearLastWord() { lastWord = nil }
}

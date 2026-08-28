// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import WellkeptCore

//  CrashInjectionProofTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **Stop the app halfway through, at every point where stopping could lose a file, and prove the
//  next launch finds all of them.**
//
//  Every destructive verb in this app is three steps: write down what is about to happen, do it,
//  write down that it happened. There are two gaps in that, and a crash in either one leaves the
//  disk and the record disagreeing:
//
//      writeIntent ──① ── the move ──② ── the ledger
//
//  ① The intent says a file is about to move; it never moved. If reconciling got this wrong it
//    would record a file as quarantined that is still sitting in the person's Downloads folder,
//    and the Restore button would then refuse for ever with "there is already something there".
//
//  ② The file has moved and nothing knows. If reconciling got THIS wrong the file is orphaned in
//    a folder with a UUID for a name, the app says quarantine is empty, and the only record of
//    where it came from is gone. **That is the outcome this whole design exists to prevent**, and
//    it is exactly what the Trash does — Finder's Put Back lives in an undocumented `.DS_Store`
//    blob, and trashing several files quickly leaves only the first one able to go back.
//
//  ## What is actually being injected, said plainly
//
//  ⚠️ **The test process is not killed.** A real `SIGKILL` inside the runner would take the runner
//  with it, and `fork()`ing a multithreaded Swift process to kill the child is a way to write a
//  flaky test rather than a rigorous one.
//
//  What is reproduced instead is **the exact on-disk state a kill at that instant would leave**,
//  produced by calling the engine's own functions in the engine's own order and then stopping. The
//  intent file is written by `Ledger.writeIntent`. The move is made by `AtomicMove.perform`. The
//  step that does not run is the one the crash is standing in for. Since a `SIGKILL` runs no
//  cleanup, unwinds nothing and flushes nothing, that on-disk state is the whole of what the next
//  launch can see — which makes it the whole of what there is to prove.

@Suite("A crash halfway through loses nothing")
struct CrashInjectionProofTests {

    // MARK: The engine's own plan, built the engine's own way

    /// Exactly what `Quarantine.quarantine` computes before it writes anything: check the file,
    /// find its store, plan the record. Used so the injected state is the engine's state and not a
    /// hand-built approximation of it.
    private func plan(_ url: URL, in ground: ProvingGround,
                      section: SectionID = .storage,
                      reason: String = "proof") throws -> QuarantineRecord {
        let verdict = Movable.check(url, reach: Reach.standard(home: ground.home))
        let file = try #require(verdict.reading, "the fixture is not readable: \(verdict.refusals)")
        #expect(verdict.isMovable, "the fixture is refused, so no crash can happen here")
        guard case .success(let store) = QuarantineStore.forItem(on: file.volume,
                                                                 home: ground.home) else {
            Issue.record("no store could be made in the sandbox")
            throw SandboxEscape(asked: url.path(percentEncoded: false), why: "no store")
        }
        return QuarantineRecord.planned(from: file, store: store, section: section, reason: reason)
    }

    /// After reconciling, the ledger and the store have to agree in both directions: every record
    /// points at something that is there, and everything that is there has a record.
    ///
    /// The second half is the one that catches an orphan — a folder in the store with a UUID for a
    /// name and nothing anywhere saying where its contents came from.
    private func ledgerAndStoreAgree(in ground: ProvingGround) throws {
        let reading = Quarantine.reading(home: ground.home)
        #expect(reading.trouble == nil, "the ledger could not be read")

        for record in reading.records {
            #expect(ground.exists(record.quarantinedURL) || record.wasContainedInPlace,
                    "the ledger names \(record.originalName), which is not in the store")
        }

        let storePath = ground.store.path(percentEncoded: false)
        let holders = (try? FileManager.default.contentsOfDirectory(atPath: storePath)) ?? []
        let known = Set(reading.records.map(\.id.uuidString))
        for holder in holders where UUID(uuidString: holder) != nil {
            // An EMPTY holder folder is litter, not a lost file: a crash between the move back and
            // the tidy-up leaves one behind, and nothing of anybody's is inside it. A holder with
            // something in it and no record is the orphan this check exists to find.
            let inside = (try? FileManager.default
                .contentsOfDirectory(atPath: storePath + "/" + holder)) ?? []
            guard !inside.isEmpty else { continue }
            #expect(known.contains(holder), """
                there is a folder in the store, \(holder), holding \(inside) — and no record \
                anywhere says where any of it came from
                """)
        }
    }

    // MARK: ① Killed after writing the intent, before the move

    /// The intent says it was about to happen. It did not happen. The file is exactly where the
    /// person left it, and the next launch says nothing, because nothing went wrong.
    @Test func killedBeforeTheMoveLeavesTheFileWhereItWas() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let file = try ground.file("Downloads/Old Installer.dmg", "installer bytes")
        let facts = try #require(FileFacts.take(of: file))
        let record = try plan(file, in: ground)

        try Ledger.writeIntent(.init(verb: .quarantine, startedAt: Date(), records: [record]),
                               home: ground.home)
        // ☠️ killed here.

        #expect(ground.exists(ground.intent), "the fixture did not set up the state it claims to")

        let report = Quarantine.reconcileOnOpening(home: ground.home)
        #expect(report.isQuiet)
        #expect(report.sentence == nil, "an ordinary interrupted launch has nothing to say")
        #expect(report.results.map(\.result) == [.nothingHappened])

        #expect(ground.exists(file))
        #expect(FileFacts.take(of: file)?.differences(from: facts).isEmpty == true)
        #expect(Quarantine.records(home: ground.home).isEmpty,
                "a file that never moved was recorded as quarantined")
        #expect(!ground.exists(ground.intent), "the intent was not cleared")
        try ledgerAndStoreAgree(in: ground)
        #expect(Quarantine.summary(home: ground.home).unaccountedFor == 0)
    }

    // MARK: ② Killed after the move, before the ledger

    /// ⭐ **The dangerous one.** The file is in the store and nothing has written it down. If the
    /// next launch cannot work this out, the file is lost in a folder named after a UUID.
    @Test func killedAfterTheMoveRecordsItRatherThanOrphaningIt() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let file = try ground.file("Downloads/Old Installer.dmg", "installer bytes")
        let facts = try #require(FileFacts.take(of: file))
        let record = try plan(file, in: ground)

        try Ledger.writeIntent(.init(verb: .quarantine, startedAt: Date(), records: [record]),
                               home: ground.home)
        try FileManager.default.createDirectory(at: record.holderURL,
                                                withIntermediateDirectories: true)
        #expect(AtomicMove.perform(from: record.originalPath, to: record.quarantinedPath) == .moved)
        // ☠️ killed here — the ledger has never heard of this file.

        #expect(Ledger.read(home: ground.home).records.isEmpty, "the fixture wrote the ledger anyway")

        let report = Quarantine.reconcileOnOpening(home: ground.home)
        #expect(report.isQuiet, "an interrupted move was reported as trouble")
        #expect(report.sentence == nil)
        #expect(report.finished.count == 1)

        let recovered = Quarantine.records(home: ground.home)
        #expect(recovered.map(\.id) == [record.id], "the move was not written down after all")
        #expect(recovered.first?.originalPath == file.path(percentEncoded: false))
        #expect(!ground.exists(ground.intent))
        try ledgerAndStoreAgree(in: ground)
        #expect(Quarantine.summary(home: ground.home).unaccountedFor == 0)

        // ⭐ And the point of all of it: the file can still be put back, unchanged.
        let back = Quarantine.restore(recovered, home: ground.home)
        #expect(back.stuck.isEmpty, "\(back.sentence)")
        #expect(FileFacts.take(of: file)?.differences(from: facts).isEmpty == true)
    }

    /// The same crash, mid-batch: two moved, one not. Both halves are worked out separately, and
    /// nothing is guessed from the position in the list.
    @Test func aBatchKilledPartWayThroughIsSortedOutItemByItem() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let first = try ground.file("Downloads/one.dmg", "one")
        let second = try ground.file("Downloads/two.dmg", "two")
        let third = try ground.file("Downloads/three.dmg", "three")
        let records = try [first, second, third].map { try plan($0, in: ground) }

        try Ledger.writeIntent(.init(verb: .quarantine, startedAt: Date(), records: records),
                               home: ground.home)
        for record in records.prefix(2) {
            try FileManager.default.createDirectory(at: record.holderURL,
                                                    withIntermediateDirectories: true)
            #expect(AtomicMove.perform(from: record.originalPath,
                                       to: record.quarantinedPath) == .moved)
        }
        // ☠️ killed here, between the second move and the third.

        let report = Quarantine.reconcileOnOpening(home: ground.home)
        #expect(report.isQuiet)
        #expect(report.finished.count == 2)

        let recovered = Quarantine.records(home: ground.home)
        #expect(Set(recovered.map(\.id)) == Set(records.prefix(2).map(\.id)))
        #expect(ground.exists(third), "the one that never moved was lost")
        #expect(ground.contents(of: third) == "three")
        try ledgerAndStoreAgree(in: ground)
        #expect(Quarantine.summary(home: ground.home).unaccountedFor == 0)
    }

    // MARK: ② again, for the other two verbs

    /// A restore that moved the file back and then died. The record has to go, or the person is
    /// looking at a quarantine row for a file that is sitting in their Downloads folder.
    @Test func killedAfterPuttingSomethingBackDropsTheRecord() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let file = try ground.file("Downloads/Old Installer.dmg", "installer bytes")
        let record = try #require(Quarantine.quarantine(
            [.init(file, section: .storage, reason: "proof")], home: ground.home).moved.first)

        try Ledger.writeIntent(.init(verb: .restore, startedAt: Date(), records: [record]),
                               home: ground.home)
        #expect(AtomicMove.perform(from: record.quarantinedPath, to: record.originalPath) == .moved)
        // ☠️ killed here — the ledger still says it is in quarantine.

        #expect(Ledger.read(home: ground.home).count == 1, "the fixture cleared the ledger anyway")

        let report = Quarantine.reconcileOnOpening(home: ground.home)
        #expect(report.isQuiet)
        #expect(report.finished.count == 1)
        #expect(Quarantine.records(home: ground.home).isEmpty,
                "a file that is back where it belongs is still listed as set aside")
        #expect(ground.contents(of: file) == "installer bytes")
        try ledgerAndStoreAgree(in: ground)
    }

    /// A delete that removed the file and then died. Same shape, opposite direction: the record
    /// must go, and there must be no way for it to come back as a row pointing at nothing.
    @Test func killedAfterRemovingSomethingDropsTheRecord() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let file = try ground.file("Downloads/Old Installer.dmg", "installer bytes")
        let record = try #require(Quarantine.quarantine(
            [.init(file, section: .storage, reason: "proof")], home: ground.home).moved.first)

        try Ledger.writeIntent(.init(verb: .delete, startedAt: Date(), records: [record]),
                               home: ground.home)
        try FileManager.default.removeItem(at: record.holderURL)
        // ☠️ killed here.

        let report = Quarantine.reconcileOnOpening(home: ground.home)
        #expect(report.isQuiet)
        #expect(report.finished.count == 1)
        #expect(Quarantine.records(home: ground.home).isEmpty)
        #expect(Quarantine.summary(home: ground.home).isEmpty)
        try ledgerAndStoreAgree(in: ground)

        // And it stays gone. A second launch must not resurrect the row.
        #expect(Quarantine.reconcileOnOpening(home: ground.home).results.isEmpty)
        #expect(Quarantine.records(home: ground.home).isEmpty)
    }

    // MARK: Reconciling is safe to run again, and again

    /// The app calls this at every launch. Running it twice must be the same as running it once,
    /// or the first quiet launch after a crash is followed by a noisy one for no reason.
    @Test func reconcilingTwiceIsTheSameAsReconcilingOnce() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let file = try ground.file("Downloads/Old Installer.dmg", "installer bytes")
        let record = try plan(file, in: ground)
        try Ledger.writeIntent(.init(verb: .quarantine, startedAt: Date(), records: [record]),
                               home: ground.home)
        try FileManager.default.createDirectory(at: record.holderURL,
                                                withIntermediateDirectories: true)
        #expect(AtomicMove.perform(from: record.originalPath, to: record.quarantinedPath) == .moved)

        let first = Quarantine.reconcileOnOpening(home: ground.home)
        let second = Quarantine.reconcileOnOpening(home: ground.home)
        let third = Quarantine.reconcileOnOpening(home: ground.home)

        #expect(first.finished.count == 1)
        #expect(second.results.isEmpty, "there was still an intent file to act on")
        #expect(third.results.isEmpty)
        #expect(Quarantine.records(home: ground.home).count == 1, "the record was added twice")
        try ledgerAndStoreAgree(in: ground)
    }

    // MARK: The one state that is genuinely trouble

    /// ⚠️ **At neither place.** The intent named a file, and it is now neither where it came from
    /// nor where Wellkept was putting it. Nothing in the app can infer what happened, so the honest
    /// thing is to name it and say plainly that nothing was deleted.
    ///
    /// This is the exception to "no file is unaccounted for", and it is deliberate: the file is
    /// unaccounted for, something other than Wellkept moved it, and pretending otherwise would be
    /// the lie. Note that its record is **not** in the ledger, so `Summary` cannot count it — this
    /// launch-time report is the only place it is ever mentioned.
    @Test func somethingMovedByAnotherProgramIsNamedAndNothingIsDeleted() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let file = try ground.file("Downloads/Old Installer.dmg", "installer bytes")
        let record = try plan(file, in: ground)
        try Ledger.writeIntent(.init(verb: .quarantine, startedAt: Date(), records: [record]),
                               home: ground.home)

        // Something that is not Wellkept moves it while Wellkept is not running.
        try ground.folder("Documents")
        let elsewhere = try ground.inside("Documents/somebody moved it.dmg")
        try FileManager.default.moveItem(at: file, to: elsewhere)
        // ☠️ and now the app opens.

        let report = Quarantine.reconcileOnOpening(home: ground.home)
        #expect(!report.isQuiet)
        #expect(report.unaccountedFor.count == 1)
        let sentence = try #require(report.sentence)
        #expect(sentence.contains("Old Installer.dmg"), "the row does not say which file")
        #expect(sentence.contains("Nothing was deleted."))
        #expect(sentence.contains("Something other than Wellkept moved it"))

        #expect(ground.exists(elsewhere), "the file itself is fine and must be left alone")
        #expect(ground.contents(of: elsewhere) == "installer bytes")
        #expect(Quarantine.records(home: ground.home).isEmpty,
                "a file at neither place was recorded as quarantined")
    }
}

// MARK: - ⭐ A damaged ledger is loud, and never a zero

@Suite("A ledger that cannot be read never reads as empty")
struct DamagedLedgerProofTests {

    /// Truncate the file mid-array — the shape a crash during a non-atomic write would leave, and
    /// the exact bug that was found and fixed in `StorageManifest.write` on 2026-08-28.
    ///
    /// ⚠️ **Half a JSON array decodes to nothing.** Left unchecked, every screen would say
    /// quarantine was empty while somebody's files sat in the store with no record of where they
    /// came from. Zero is the one number that must never be reported because we could not look.
    @Test func aLedgerCutInHalfIsReportedAsDamagedRatherThanEmpty() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let first = try ground.file("Downloads/one.dmg", "one")
        let second = try ground.file("Downloads/two.dmg", "two")
        let report = Quarantine.quarantine([
            .init(first, section: .storage, reason: "proof"),
            .init(second, section: .storage, reason: "proof"),
        ], home: ground.home)
        #expect(report.moved.count == 2)

        let whole = try Data(contentsOf: ground.ledger)
        #expect(whole.count > 200, "the fixture ledger is too small to cut meaningfully")
        try whole.prefix(whole.count * 6 / 10).write(to: ground.ledger)

        let reading = Ledger.read(home: ground.home)
        let trouble = try #require(reading.trouble, "half a JSON array was accepted")
        #expect(trouble.kind == .corrupt)
        #expect(trouble.isLoud)
        #expect(reading.records.isEmpty)
        #expect(!reading.isTrustworthy)

        // ⭐ What a screen would show. Never a count, never "nothing is set aside".
        let summary = Quarantine.summary(home: ground.home)
        #expect(summary.trouble != nil)
        #expect(!summary.isEmpty, "a damaged ledger reads as an empty quarantine")
        #expect(summary.trouble?.kind == .corrupt)
        #expect(!summary.rowSentence().contains("Nothing is set aside"))
        #expect(summary.rowSentence().contains("damaged"))
        #expect(summary.rowSentence().contains("Nothing has been deleted"))

        // The files themselves are untouched, which is what the sentence promises.
        #expect(ground.exists(report.moved[0].quarantinedURL))
        #expect(ground.exists(report.moved[1].quarantinedURL))
    }

    /// The damaged file is kept, not thrown away. It is the only remaining evidence of where those
    /// files came from, and somebody may yet get them back out of it by hand.
    @Test func theDamagedRecordIsKeptWhereTheSentenceSaysItIs() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        try Ledger.write([], home: ground.home)
        try Data("[{\"id\":\"not a uuid\"".utf8).write(to: ground.ledger)

        let trouble = try #require(Ledger.read(home: ground.home).trouble)
        let kept = try #require(trouble.keptAt, "the damaged ledger was not kept")
        #expect(FileManager.default.fileExists(atPath: kept))
        #expect(trouble.sentence.contains(kept))
    }

    /// ⚠️ **The trap the API surface warns about.** `records()` hands back an empty array for a
    /// damaged ledger, exactly as it does for a fresh install. A screen that reads only that number
    /// tells somebody their quarantine is empty at the moment it is least true.
    @Test func theEmptyArrayIsIndistinguishableSoTheTroubleMustBeReadToo() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        #expect(Quarantine.records(home: ground.home).isEmpty)
        #expect(Quarantine.reading(home: ground.home).trouble == nil, "a fresh install is fine")

        try Ledger.write([], home: ground.home)
        try Data("[{".utf8).write(to: ground.ledger)

        #expect(Quarantine.records(home: ground.home).isEmpty, "same number…")
        #expect(Quarantine.reading(home: ground.home).trouble != nil, "…entirely different meaning")
    }

    /// Nothing is removed on the strength of a record that could not be read — in either setting,
    /// including the one where the person asked for automatic removal.
    @Test func nothingIsRemovedWhileTheLedgerIsDamaged() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let file = try ground.file("Downloads/one.dmg", "one")
        let record = try #require(Quarantine.quarantine(
            [.init(file, section: .storage, reason: "proof")], home: ground.home).moved.first)

        let whole = try Data(contentsOf: ground.ledger)
        try whole.prefix(whole.count / 2).write(to: ground.ledger)

        let defaults = QuarantineSandbox.defaults("damaged-ledger")
        defer { QuarantineSandbox.forget(defaults, named: "damaged-ledger") }
        Expiry.setMode(.auto, defaults: defaults)

        let sweep = Expiry.sweepOnOpening(home: ground.home,
                                          now: Date().addingTimeInterval(400 * 86_400),
                                          defaults: defaults)
        #expect(sweep.removed.isEmpty)
        #expect(sweep.sentence == nil)
        #expect(ground.exists(record.quarantinedURL), "a file was removed on an unreadable record")
    }

    /// A ledger written whole or not at all. The atomic write is what makes the truncation above a
    /// staged fixture rather than something that happens by itself.
    @Test func theLedgerIsNeverLeftHalfWritten() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let file = try ground.file("Downloads/one.dmg", "one")
        _ = Quarantine.quarantine([.init(file, section: .storage, reason: "proof")],
                                  home: ground.home)

        let text = try String(contentsOf: ground.ledger, encoding: .utf8)
        #expect(text.hasPrefix("["))
        #expect(text.hasSuffix("]"))
        #expect((try? Ledger.decoder().decode([QuarantineRecord].self,
                                              from: Data(text.utf8))) != nil)
    }
}

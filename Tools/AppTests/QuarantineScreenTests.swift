// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import WellkeptCore

//  QuarantineScreenTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **The places a person meets quarantine: the words on the screen, and the model behind them.**
//
//  `QuarantineTests` proves the engine moves files correctly. This proves the screen asks it to move
//  the right ones, and describes what happened without claiming anything that did not happen.
//
//  Every test builds its own pretend home folder and throws it away. Nothing here is ever pointed at
//  a real one — `QuarantineModel` takes `home:` for exactly this reason.

// MARK: - The words

@Suite("What a quarantine row says")
struct QuarantineTextTests {

    /// A record with a date, built by hand so the age is not whatever the clock says.
    private func record(daysAgo: Int, name: String = "Old Installer.dmg") -> QuarantineRecord {
        QuarantineRecord(
            originalPath: "/Users/someone/Downloads/\(name)",
            originalName: name,
            identity: FileIdentity(volumeUUID: nil, volumeDevice: "disk1s1", inode: 4_242),
            quarantinedPath: "/store/\(name)",
            storeRoot: "/store",
            mode: 0o644, ownerID: 501, groupID: 20, flags: 0,
            createdOn: nil, modifiedOn: nil, bytes: 12_000_000,
            isDirectory: false, isSymbolicLink: false, parentMode: 0o755,
            section: .storage, reason: "An installer you already used",
            quarantinedOn: Date().addingTimeInterval(-Double(daysAgo) * 86_400),
            wasInICloud: false)
    }

    /// ⚠️ **The two modes say different things, because they do different things.** In manual the
    /// app removes nothing at thirty days — the item rises to the top and waits. A countdown there
    /// would promise a deletion Wellkept has no intention of performing.
    @Test("Manual promises nothing; auto says what it will do")
    func theCountdownDependsOnTheMode() {
        let young = record(daysAgo: 3)

        let manual = QuarantineText.life(young, mode: .manual)
        #expect(manual.contains("Ready to remove in 27 days."))
        #expect(!manual.contains("Wellkept removes"))

        let auto = QuarantineText.life(young, mode: .auto)
        #expect(auto.contains("Wellkept removes it in 27 days."))
    }

    /// Past thirty days there is no countdown in either mode — "0 days left" is indistinguishable
    /// from a bug.
    @Test("Something already ready is never given a countdown")
    func aReadyItemHasNoCountdown() {
        let old = record(daysAgo: 34)
        for mode in ExpiryMode.allCases {
            let line = QuarantineText.life(old, mode: mode)
            #expect(line.contains("ready to remove"))
            #expect(!line.contains("in 0 days"))
            #expect(!line.contains("days left"))
        }
    }

    /// The row has to say who set it aside as well as why. "Why" with no author is an assertion.
    @Test("A row names the section that set it aside, and its reason")
    func theRowNamesItsAuthor() {
        let line = QuarantineText.origin(record(daysAgo: 1))
        #expect(line.contains(SectionID.storage.title))
        #expect(line.contains("An installer you already used"))
    }

    /// DESIGN §10: name the specific thing, and carry the one consequence sentence.
    @Test("Both confirmations name what they will remove and say there is no undo")
    func theConfirmationsAreSpecific() {
        let words = QuarantineText.deleteConfirmation(record(daysAgo: 2))
        #expect(words.title.contains("Old Installer.dmg"))
        #expect(words.message.contains("cannot be undone"))

        let empty = QuarantineText.emptyConfirmation(count: 12, bytes: 40_000_000_000)
        #expect(empty.message.contains("12 items"))
        #expect(empty.message.contains("40"), "the size a person is agreeing to remove is stated")
        #expect(empty.message.contains("cannot be undone"))

        let one = QuarantineText.emptyConfirmation(count: 1, bytes: 4_096)
        #expect(one.message.contains("1 item"), "and it counts in the singular")
    }

    /// ⚠️ The whole point of the screen's vocabulary. `QuarantineWordsTests` scans the source; this
    /// asks the composed sentences, which is where a later interpolation would show up.
    @Test("Nothing the screen composes claims space came back")
    func nothingClaimsSpaceCameBack() {
        var sentences = [QuarantineText.whatThisIs,
                         QuarantineText.nothingIsSetAsideWhy,
                         QuarantineText.noLongerThere,
                         QuarantineText.ignoreListBlurb,
                         QuarantineWords.beforeSettingAside(40_000_000_000)]
        for mode in ExpiryMode.allCases {
            sentences.append(QuarantineText.life(record(daysAgo: 3), mode: mode))
            sentences.append(mode.explanation)
        }
        for sentence in sentences {
            let lowered = sentence.lowercased()
            for word in ["freed", "reclaim", "recovered space"] {
                #expect(!lowered.contains(word), "“\(sentence)” claims space came back")
            }
        }
    }

    /// The settled line is used verbatim or not at all.
    @Test("The iCloud line is the one approved")
    func theICloudLineIsVerbatim() {
        #expect(QuarantineWords.iCloud == "This also removes it from your iPhone and iPad.")
        #expect(QuarantineWords.iCloudGap.contains("taking up the same room"))
    }
}

// MARK: - The model

@Suite("The quarantine screen's model")
@MainActor
struct QuarantineModelTests {

    /// The same record with a different date, so a test can build a list that is genuinely old
    /// without waiting a month for it.
    private func aged(_ record: QuarantineRecord, daysAgo: Int) -> QuarantineRecord {
        QuarantineRecord(
            id: record.id,
            originalPath: record.originalPath,
            originalName: record.originalName,
            identity: record.identity,
            quarantinedPath: record.quarantinedPath,
            storeRoot: record.storeRoot,
            mode: record.mode, ownerID: record.ownerID, groupID: record.groupID,
            flags: record.flags, createdOn: record.createdOn, modifiedOn: record.modifiedOn,
            bytes: record.bytes, isDirectory: record.isDirectory,
            isSymbolicLink: record.isSymbolicLink, parentMode: record.parentMode,
            sectionRaw: record.sectionRaw, reason: record.reason,
            quarantinedOn: Date().addingTimeInterval(-Double(daysAgo) * 86_400),
            wasInICloud: record.wasInICloud,
            containment: record.containment)
    }

    /// ⚠️ **Ready first, oldest first within each group** — the settled shape. A list sorted by date
    /// alone would bury a ready item under a week of newer ones.
    @Test("The list is ready first, then oldest first")
    func theOrderIsTheScreensOrder() async throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        for name in ["one.dmg", "two.dmg", "three.dmg"] {
            let file = try sandbox.file("Downloads/\(name)")
            _ = Quarantine.quarantine([.init(file, section: .storage, reason: "unused")],
                                      home: sandbox.home)
        }
        var records = Ledger.read(home: sandbox.home).records
        #expect(records.count == 3)
        // one.dmg is the oldest of the two young ones; three.dmg is past thirty days.
        records = [aged(records[0], daysAgo: 5),
                   aged(records[1], daysAgo: 2),
                   aged(records[2], daysAgo: 40)]
        try Ledger.write(records, home: sandbox.home)

        let model = QuarantineModel(home: sandbox.home)
        await model.load()

        #expect(model.records.map(\.originalName) == ["three.dmg", "one.dmg", "two.dmg"])
        #expect(model.summary?.readyCount == 1)
        #expect(model.summary?.readySentence?.contains("ready to remove") == true)
    }

    /// Restore is the ordinary verb, and it puts the file back where it came from.
    @Test("Restore puts one item back and clears its record")
    func restorePutsItBack() async throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Downloads/keep.dmg", contents: "the bytes")
        _ = Quarantine.quarantine([.init(file, section: .storage, reason: "unused")],
                                  home: sandbox.home)

        let model = QuarantineModel(home: sandbox.home)
        await model.load()
        let record = try #require(model.records.first)
        await model.restore(record)

        #expect(sandbox.contents(of: file) == "the bytes")
        #expect(model.records.isEmpty)
        #expect(model.summary?.count == 0)
        #expect(model.lastWord?.contains("back where it came from") == true)
    }

    /// ⚠️ Nothing is ever written over. The refusal lands **on the row**, next to the button that
    /// was pressed, rather than in a dialog the person has to connect back to an item.
    @Test("A blocked restore explains itself on the row")
    func aBlockedRestoreSaysSoOnTheRow() async throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Downloads/clash.dmg", contents: "the original")
        _ = Quarantine.quarantine([.init(file, section: .storage, reason: "unused")],
                                  home: sandbox.home)
        // Somebody has since made a new file with the same name.
        try sandbox.file("Downloads/clash.dmg", contents: "somebody's newer work")

        let model = QuarantineModel(home: sandbox.home)
        await model.load()
        let record = try #require(model.records.first)
        await model.restore(record)

        #expect(sandbox.contents(of: file) == "somebody's newer work", "nothing was written over")
        #expect(model.records.count == 1, "and the item is still in quarantine")
        #expect(model.rowWord[record.id]?.contains("will not write over it") == true)
    }

    /// ⚠️ **`expecting:` is the count that was on screen.** Emptying deletes the list that was
    /// shown, and nothing else.
    @Test("Empty removes everything that was listed, and only that")
    func emptyRemovesWhatWasShown() async throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        var stored: [URL] = []
        for name in ["a.dmg", "b.dmg"] {
            let file = try sandbox.file("Downloads/\(name)")
            let report = Quarantine.quarantine([.init(file, section: .storage, reason: "unused")],
                                               home: sandbox.home)
            stored.append(contentsOf: report.moved.map(\.quarantinedURL))
        }

        let model = QuarantineModel(home: sandbox.home)
        await model.load()
        #expect(model.records.count == 2)
        await model.empty()

        #expect(model.records.isEmpty)
        #expect(stored.allSatisfy { !sandbox.exists($0) })
        #expect(Ledger.read(home: sandbox.home).records.isEmpty)
        // The measured figure, or an honest refusal to give one. Never a promise made beforehand.
        let word = try #require(model.lastWord)
        #expect(word.contains("Removed 2 items"))
        #expect(!word.lowercased().contains("freed"))
    }

    /// One row's Delete removes one row.
    @Test("Deleting one item leaves the others alone")
    func deletingOneLeavesTheRest() async throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        for name in ["gone.dmg", "stays.dmg"] {
            let file = try sandbox.file("Downloads/\(name)")
            _ = Quarantine.quarantine([.init(file, section: .storage, reason: "unused")],
                                      home: sandbox.home)
        }

        let model = QuarantineModel(home: sandbox.home)
        await model.load()
        let doomed = try #require(model.records.first { $0.originalName == "gone.dmg" })
        await model.delete(doomed)

        #expect(model.records.map(\.originalName) == ["stays.dmg"])
    }

    /// ⚠️ **The one number the app may never report on its own.** A ledger it cannot read means
    /// somebody's files are unaccounted for, and "nothing is set aside" would be a lie told
    /// confidently.
    @Test("An unreadable record shows trouble instead of a count")
    func anUnreadableLedgerIsNeverAZero() async throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Downloads/x.dmg")
        _ = Quarantine.quarantine([.init(file, section: .storage, reason: "unused")],
                                  home: sandbox.home)
        try Data("{ this is not the ledger".utf8).write(to: sandbox.ledger)

        let model = QuarantineModel(home: sandbox.home)
        await model.load()

        let summary = try #require(model.summary)
        #expect(summary.trouble != nil)
        #expect(!summary.isEmpty, "a quarantine nobody can read is not an empty quarantine")
        #expect(summary.rowSentence().contains("Nothing has been deleted"))
        #expect(model.records.isEmpty, "and it lists nothing rather than guessing")
    }

    /// The fourth verb's home. Nothing on the ignore list is a file operation, so taking one back
    /// needs no confirmation and loses nobody anything.
    @Test("The ignore list can be read and taken back")
    func theIgnoreListCanBeTakenBack() async throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Downloads/noisy.log")
        #expect(Quarantine.ignore(file, section: .storage,
                                  finding: "A log file that keeps coming back",
                                  home: sandbox.home) == nil)

        let model = QuarantineModel(home: sandbox.home)
        await model.loadIgnored()
        let item = try #require(model.ignored.first)
        #expect(item.finding == "A log file that keeps coming back")
        #expect(QuarantineText.ignoredOn(item).hasPrefix("Ignored "))

        await model.stopIgnoring(item)
        #expect(model.ignored.isEmpty)
        #expect(sandbox.exists(file), "ignoring never touched the file, and neither did undoing it")
    }

    /// The launch pass must not run under the harness — it is the one automatic path in the app
    /// that can delete a file, and `ViewShots` pumps a run loop that fires `.task`.
    @Test("The launch sweep refuses to run under the test harness")
    func theLaunchSweepRefusesUnderTests() async throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Downloads/old.dmg")
        _ = Quarantine.quarantine([.init(file, section: .storage, reason: "unused")],
                                  home: sandbox.home)
        let records = Ledger.read(home: sandbox.home).records
            .map { aged($0, daysAgo: 90) }
        try Ledger.write(records, home: sandbox.home)

        let launch = QuarantineLaunch(home: sandbox.home)
        await launch.runOnOpening(demoMode: false)

        #expect(launch.notices.isEmpty)
        #expect(Ledger.read(home: sandbox.home).records.count == 1,
                "a screenshot run must never empty somebody's quarantine")
    }
}

// MARK: - The uninstaller's question

@Suite("Uninstalling with files in quarantine")
@MainActor
struct UninstallQuarantineTests {

    private func record(_ name: String) -> QuarantineRecord {
        QuarantineRecord(
            originalPath: "/Users/someone/Downloads/\(name)",
            originalName: name,
            identity: FileIdentity(volumeUUID: nil, volumeDevice: "disk1s1", inode: 7),
            quarantinedPath: "/store/\(name)", storeRoot: "/store",
            mode: 0o644, ownerID: 501, groupID: 20, flags: 0,
            createdOn: nil, modifiedOn: nil, bytes: 10, isDirectory: false,
            isSymbolicLink: false, parentMode: 0o755,
            section: .storage, reason: "unused", quarantinedOn: Date(), wasInICloud: false)
    }

    /// ⚠️ Decided 2026-08-26: never decide it for them, never leave them buried. Two real outcomes,
    /// and the question counts correctly in the singular — a dialog that says "1 of your files are"
    /// is a dialog nobody wrote for this moment.
    @Test("The question offers two real outcomes and counts properly")
    func theQuestionIsWrittenForBothCases() {
        let one = Uninstaller.quarantineQuestion([record("a.dmg")])
        #expect(one.title == "One of your files is in Wellkept's quarantine")

        let many = Uninstaller.quarantineQuestion([record("a.dmg"), record("b.dmg")])
        #expect(many.title.hasPrefix("2 of your files"))
        #expect(many.body.contains("Put Them Back"))
        #expect(many.body.contains("Move Them…"))
        #expect(many.body.contains("never deleted them"))
    }

    /// The quarantine folder holds the user's own files, so it is the one thing the uninstaller
    /// asks about instead of deleting. ⚠️ **`.ask`, never `.delete`.**
    @Test("Quarantine is the one thing uninstall must ask about")
    func quarantineIsNeverSweptUp() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let file = try sandbox.file("Downloads/x.dmg")
        _ = Quarantine.quarantine([.init(file, section: .storage, reason: "unused")],
                                  home: sandbox.home)

        let entries = StorageManifest.entries(home: sandbox.home,
                                              defaults: QuarantineSandbox.defaults("uninstall"))
        let quarantine = try #require(entries.first { $0.title == "Quarantine" })
        #expect(quarantine.disposition == .ask)
        #expect(entries.allSatisfy { $0.url != StorageManifest.supportDirectory(home: sandbox.home) },
                "there must be no catch-all entry that would delete the quarantine recursively")
    }
}

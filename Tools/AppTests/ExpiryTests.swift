// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import WellkeptCore

//  ExpiryTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **Thirty CALENDAR days, manual by default, and nothing on a timer.**
//
//  The answer, 2026-08-28. Three of these tests hold the parts somebody could undo in a single
//  well-meaning line: that a missing preference is `manual` and not `auto`, that thirty days is
//  calendar arithmetic and not `30 × 86,400`, and that an unreadable ledger removes nothing even
//  when the user has asked for automatic removal.

private func record(_ home: URL, name: String = "thing.dmg", setAside: Date) -> QuarantineRecord {
    let id = UUID()
    return QuarantineRecord(
        id: id,
        originalPath: home.appending(path: "Downloads/\(name)").path(percentEncoded: false),
        originalName: name,
        identity: FileIdentity(volumeUUID: nil, volumeDevice: "/dev/disk3s5", inode: 1),
        quarantinedPath: StorageManifest.quarantineDirectory(home: home)
            .appending(path: "\(id.uuidString)/\(name)").path(percentEncoded: false),
        storeRoot: StorageManifest.quarantineDirectory(home: home).path(percentEncoded: false),
        mode: 0o644, ownerID: 501, groupID: 20, flags: 0,
        createdOn: setAside, modifiedOn: setAside, bytes: 100,
        isDirectory: false, isSymbolicLink: false, parentMode: 0o755,
        section: .storage, reason: "unused", quarantinedOn: setAside, wasInICloud: false)
}

// MARK: - ⭐ The setting

@Suite struct ExpiryModeTests {

    /// ⚠️ **Absent means manual.** Reading a missing key as `auto` would opt somebody into
    /// automatic removal of their own files by a value nobody set.
    @Test func aFreshInstallIsManual() {
        let defaults = QuarantineSandbox.defaults("mode-fresh")
        defer { QuarantineSandbox.forget(defaults, named: "mode-fresh") }
        #expect(Expiry.mode(defaults: defaults) == .manual)
    }

    /// And so does a stored word this build does not recognise. A future rename must not silently
    /// turn somebody's manual setting into an automatic one.
    @Test func anUnknownStoredValueIsManualToo() {
        let defaults = QuarantineSandbox.defaults("mode-unknown")
        defer { QuarantineSandbox.forget(defaults, named: "mode-unknown") }
        defaults.set("everyFortnight", forKey: Expiry.settingsKey)
        #expect(Expiry.mode(defaults: defaults) == .manual)
    }

    @Test func theChoiceIsStoredAndReadBack() {
        let defaults = QuarantineSandbox.defaults("mode-round-trip")
        defer { QuarantineSandbox.forget(defaults, named: "mode-round-trip") }
        Expiry.setMode(.auto, defaults: defaults)
        #expect(Expiry.mode(defaults: defaults) == .auto)
        Expiry.setMode(.manual, defaults: defaults)
        #expect(Expiry.mode(defaults: defaults) == .manual)
    }

    /// The key is declared in `StorageManifest`, like every other key the app writes, so the
    /// uninstaller cannot go stale.
    @Test func theKeyIsDeclaredWithAllTheOthers() {
        #expect(StorageManifest.Keys.all.contains(Expiry.settingsKey))
        #expect(Expiry.settingsKey == "quarantineExpiry", "raw values are storage and are permanent")
    }

    /// ⚠️ The automatic option **says out loud** that nothing happens while the app is closed. An
    /// app that implied it was watching the clock would be lying about what it is.
    @Test func bothOptionsExplainThemselvesHonestly() {
        // ⚠️ Updated 2026-08-29, when Wellkept took a login item. The old assertion required the
        // sentence to claim there was no background piece at all, which is no longer true — so the
        // test would have kept a false sentence on screen for as long as nobody re-read it. What
        // still has to be said, and is what actually matters to somebody's files, is that the part
        // that keeps running never touches quarantine.
        #expect(ExpiryMode.auto.explanation.contains("Nothing happens to your quarantine while Wellkept is closed"))
        #expect(ExpiryMode.auto.explanation.contains("never touches quarantine"))
        for banned in BackgroundPiece.sentencesThatAreNoLongerTrue {
            #expect(!ExpiryMode.auto.explanation.contains(banned),
                    Comment(rawValue: "the quarantine setting still says “\(banned)”"))
        }
        #expect(ExpiryMode.manual.explanation.contains("never removes anything on its own"))
        for mode in ExpiryMode.allCases { #expect(mode.label.contains("30")) }
    }
}

// MARK: - ⭐ Thirty calendar days

@Suite struct ExpiryArithmeticTests {

    static let losAngeles: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    static func moment(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        losAngeles.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func twentyNineDaysIsNotReadyAndThirtyIs() {
        let setAside = Self.moment(2026, 6, 1)
        let item = record(URL(filePath: "/Users/example"), setAside: setAside)

        #expect(!Expiry.isReady(item, now: Self.moment(2026, 6, 30), calendar: Self.losAngeles))
        #expect(Expiry.isReady(item, now: Self.moment(2026, 7, 1), calendar: Self.losAngeles))
    }

    /// ⚠️ **Calendar days, not `30 × 86,400`.** A period spanning a daylight-saving change is an
    /// hour short or an hour long in seconds, and the naive arithmetic makes the item ready a day
    /// early for somebody who set it aside just after midnight.
    @Test func daylightSavingDoesNotMoveTheThirtiethDay() {
        // 2026-03-08 is the spring-forward date in Los Angeles.
        let setAside = Self.moment(2026, 3, 1, 12)
        let item = record(URL(filePath: "/Users/example"), setAside: setAside)

        let ready = Expiry.readyOn(item, calendar: Self.losAngeles)
        #expect(ready == Self.moment(2026, 3, 31, 12), "the same wall-clock time, thirty days on")
        #expect(ready != setAside.addingTimeInterval(30 * 86_400),
                "which is exactly what a seconds count would have given, an hour out")
    }

    /// The row counts day boundaries, because that is what a person means by "days ago". An item
    /// set aside at 23:50 last night is one day old this morning.
    @Test func theRowCountsDaysTheWayAPersonDoes() {
        let lastNight = Self.moment(2026, 6, 1, 23)
        let thisMorning = Self.moment(2026, 6, 2, 8)
        let item = record(URL(filePath: "/Users/example"), setAside: lastNight)

        #expect(Expiry.daysHeld(item, now: thisMorning, calendar: Self.losAngeles) == 1)
        #expect(Expiry.ageSentence(item, now: thisMorning, calendar: Self.losAngeles)
                == "Set aside yesterday.")
    }

    /// ⚠️ And the two ways of counting are deliberately not the same function. Day-boundary
    /// counting would make an item set aside at 23:59 ready after twenty-nine days and one minute.
    @Test func theDisplayCountAndTheExpiryTestDisagreeOnPurpose() {
        let lateAtNight = Self.moment(2026, 6, 1, 23)
        let item = record(URL(filePath: "/Users/example"), setAside: lateAtNight)
        let twentyNineDaysLater = Self.moment(2026, 6, 30, 8)

        #expect(Expiry.daysHeld(item, now: twentyNineDaysLater, calendar: Self.losAngeles) == 29)
        #expect(!Expiry.isReady(item, now: twentyNineDaysLater, calendar: Self.losAngeles),
                "it is not ready until thirty days have actually passed")
    }

    /// **Never a countdown for something already ready** — "0 days left" reads as a bug.
    @Test func aReadyItemSaysItIsReadyRatherThanCountingDown() {
        let item = record(URL(filePath: "/Users/example"), setAside: Self.moment(2026, 6, 1))
        let later = Self.moment(2026, 7, 15)
        #expect(Expiry.daysLeft(item, now: later, calendar: Self.losAngeles) == 0)
        #expect(Expiry.ageSentence(item, now: later, calendar: Self.losAngeles)
                    .hasSuffix("ready to remove."))
    }

    @Test func todayReadsAsToday() {
        let item = record(URL(filePath: "/Users/example"), setAside: Self.moment(2026, 6, 1, 9))
        #expect(Expiry.ageSentence(item, now: Self.moment(2026, 6, 1, 17),
                                   calendar: Self.losAngeles) == "Set aside today.")
    }

    /// The settled shape: at thirty days the item **rises to the top** and waits there. A list
    /// sorted only by date would bury it under a week of newer ones.
    @Test func readyItemsRiseToTheTop() {
        let home = URL(filePath: "/Users/example")
        let now = Self.moment(2026, 7, 15)
        let old = record(home, name: "old.dmg", setAside: Self.moment(2026, 6, 1))     // ready
        let older = record(home, name: "older.dmg", setAside: Self.moment(2026, 5, 1)) // ready, older
        let fresh = record(home, name: "fresh.dmg", setAside: Self.moment(2026, 7, 14))

        let order = Expiry.sortedForTheScreen([fresh, old, older], now: now,
                                              calendar: Self.losAngeles)
        #expect(order.map(\.originalName) == ["older.dmg", "old.dmg", "fresh.dmg"])
    }
}

// MARK: - ⭐ Opening the app

@Suite struct ExpirySweepTests {

    /// ⚠️ **Manual removes nothing, ever.** An item nobody acknowledges waits for ever, because the
    /// alternative is an app that eventually deletes somebody's file because they were busy.
    @Test func manualRemovesNothingAndSaysWhatIsWaiting() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        let defaults = QuarantineSandbox.defaults("sweep-manual")
        defer { QuarantineSandbox.forget(defaults, named: "sweep-manual") }

        let file = try sandbox.file("Downloads/old.dmg")
        let item = try #require(Quarantine.quarantine(
            [.init(file, section: .storage, reason: "unused")], home: sandbox.home).moved.first)

        let fortyDaysOn = Calendar.current.date(byAdding: .day, value: 40, to: Date())!
        let sweep = Expiry.sweepOnOpening(home: sandbox.home, now: fortyDaysOn, defaults: defaults)

        #expect(sweep.mode == .manual)
        #expect(sweep.wereReady.count == 1)
        #expect(sweep.removed.isEmpty)
        #expect(sandbox.exists(item.quarantinedURL), "manual mode may never remove anything")
        #expect(sweep.sentence?.contains("ready to remove") == true)
    }

    /// Auto acts the next time Wellkept is opened, and **says what it removed** — which is what
    /// makes it the user's own standing instruction rather than the app acting behind their back.
    @Test func autoRemovesTheOverdueOnesAndSaysSo() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        let defaults = QuarantineSandbox.defaults("sweep-auto")
        defer { QuarantineSandbox.forget(defaults, named: "sweep-auto") }
        Expiry.setMode(.auto, defaults: defaults)

        let old = try sandbox.file("Downloads/old.dmg")
        let item = try #require(Quarantine.quarantine(
            [.init(old, section: .storage, reason: "unused")], home: sandbox.home).moved.first)

        let fortyDaysOn = Calendar.current.date(byAdding: .day, value: 40, to: Date())!
        let sweep = Expiry.sweepOnOpening(home: sandbox.home, now: fortyDaysOn, defaults: defaults)

        #expect(sweep.removed.count == 1)
        #expect(!sandbox.exists(item.quarantinedURL))
        #expect(Ledger.read(home: sandbox.home).records.isEmpty)

        let said = try #require(sweep.sentence)
        #expect(said.contains("You asked Wellkept to remove things after 30 days"))
        #expect(!said.lowercased().contains("freed"))
    }

    /// Anything inside its thirty days is untouched in either mode.
    @Test func somethingSetAsideYesterdayIsLeftAlone() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        let defaults = QuarantineSandbox.defaults("sweep-recent")
        defer { QuarantineSandbox.forget(defaults, named: "sweep-recent") }
        Expiry.setMode(.auto, defaults: defaults)

        let file = try sandbox.file("Downloads/new.dmg")
        let item = try #require(Quarantine.quarantine(
            [.init(file, section: .storage, reason: "unused")], home: sandbox.home).moved.first)

        let sweep = Expiry.sweepOnOpening(home: sandbox.home, defaults: defaults)
        #expect(sweep.removed.isEmpty)
        #expect(sweep.sentence == nil, "nothing to say means nothing is said")
        #expect(sandbox.exists(item.quarantinedURL))
    }

    /// ⚠️ **The one that matters most.** Deleting on the strength of a record we could not read is
    /// the shape of every accident on the list.
    @Test func anUnreadableLedgerRemovesNothingEvenInAutomatic() throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        let defaults = QuarantineSandbox.defaults("sweep-damaged")
        defer { QuarantineSandbox.forget(defaults, named: "sweep-damaged") }
        Expiry.setMode(.auto, defaults: defaults)

        let file = try sandbox.file("Downloads/old.dmg")
        let item = try #require(Quarantine.quarantine(
            [.init(file, section: .storage, reason: "unused")], home: sandbox.home).moved.first)

        try Data("[{ half a record".utf8).write(to: sandbox.ledger)

        let fortyDaysOn = Calendar.current.date(byAdding: .day, value: 40, to: Date())!
        let sweep = Expiry.sweepOnOpening(home: sandbox.home, now: fortyDaysOn, defaults: defaults)

        #expect(sweep.removed.isEmpty)
        #expect(sweep.wereReady.isEmpty)
        #expect(sandbox.exists(item.quarantinedURL), "somebody's file was removed on a guess")
    }
}

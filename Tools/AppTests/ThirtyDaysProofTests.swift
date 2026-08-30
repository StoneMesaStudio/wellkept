// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import WellkeptCore

//  ThirtyDaysProofTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **Thirty calendar days, both settings, and the Mac that gets opened once a quarter.**
//
//  The answer, 2026-08-28: **thirty CALENDAR days**, not days the app happened to be open, and
//  **the user chooses** — *remove them at thirty days* or *tell me at thirty days*, with manual as
//  the default.
//
//  Three things have to be true for that to be honest, and each one is a test below:
//
//  1. **Calendar days really are calendar days.** A Mac that is shut in a drawer for three months
//     comes back with everything ready, because nothing is counting launches. A test that only ever
//     checks 29 and 31 days cannot tell the difference between the two ways of counting.
//  2. **Manual removes nothing, ever.** Not after thirty days, not after a year, not after being
//     opened a hundred times. An item nobody acknowledges waits for ever — the alternative is an
//     app that eventually deletes somebody's file because they were busy.
//  3. **Automatic says what it did.** That sentence is not politeness. It is the thing that makes
//     automatic removal the person's own standing instruction being carried out in front of them,
//     rather than the app acting behind their back — which is what "nothing that changes the Mac
//     happens on a schedule" would otherwise forbid.

@Suite("Thirty calendar days, and the Mac opened once a quarter")
struct ThirtyDaysProofTests {

    /// A sandbox with `count` items set aside at `on`, for the sweeps to find.
    private func setAside(_ count: Int, on when: Date, in ground: ProvingGround) throws
        -> [QuarantineRecord] {
        var records: [QuarantineRecord] = []
        for index in 0..<count {
            let file = try ground.file("Downloads/item \(index).dmg", "item \(index)")
            let moved = try #require(Quarantine.quarantine(
                [.init(file, section: .storage, reason: "proof")], home: ground.home).moved.first)
            // The engine stamps `quarantinedOn` with the real clock. Rewriting the stamp is the
            // only way to test thirty days without waiting thirty days, and it changes nothing
            // else about the record.
            records.append(moved.withQuarantinedOn(when))
        }
        try Ledger.write(records, home: ground.home)
        return records
    }

    private func settings(_ mode: ExpiryMode, _ label: String) -> UserDefaults {
        let defaults = QuarantineSandbox.defaults(label)
        Expiry.setMode(mode, defaults: defaults)
        return defaults
    }

    // MARK: 1. Calendar days, not days the app was open

    /// ⭐ **The Mac that gets opened once a quarter.** Set three things aside, close the app, and
    /// open it ninety-one days later. All three are ready, because the calendar kept running while
    /// the app was not.
    @Test func aMacOpenedOnceAQuarterFindsEverythingReady() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let start = Date()
        let records = try setAside(3, on: start, in: ground)
        let aQuarterLater = start.addingTimeInterval(91 * 86_400)

        let ready = Expiry.ready(among: records, now: aQuarterLater)
        #expect(ready.count == 3)
        #expect(Expiry.daysHeld(records[0], now: aQuarterLater) == 91)
        #expect(Expiry.daysLeft(records[0], now: aQuarterLater) == 0)
    }

    /// ⚠️ **Opening the app is not a tick of the clock.** Sweep forty times on the day everything
    /// went in — nothing is ready, and nothing has been counted. Then sweep once, thirty days
    /// later, and everything is ready. If anything anywhere counted launches instead of days, the
    /// forty openings would have moved the answer.
    @Test func openingTheAppFortyTimesInOneDayMovesNothing() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let start = Date()
        _ = try setAside(2, on: start, in: ground)
        let defaults = settings(.auto, "forty-openings")
        defer { QuarantineSandbox.forget(defaults, named: "forty-openings") }

        for _ in 0..<40 {
            let sweep = Expiry.sweepOnOpening(home: ground.home, now: start, defaults: defaults)
            #expect(sweep.removed.isEmpty)
            #expect(sweep.wereReady.isEmpty)
        }
        #expect(Quarantine.records(home: ground.home).count == 2)

        let onDayThirty = Expiry.sweepOnOpening(home: ground.home,
                                                now: start.addingTimeInterval(30 * 86_400),
                                                defaults: defaults)
        #expect(onDayThirty.removed.count == 2)
    }

    /// Twenty-nine days is not thirty. The boundary is asserted from both sides so an off-by-one in
    /// either direction fails.
    @Test func theBoundaryIsExactlyThirty() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let start = Date()
        let records = try setAside(1, on: start, in: ground)
        let record = records[0]

        #expect(!Expiry.isReady(record, now: start.addingTimeInterval(29 * 86_400)))
        #expect(!Expiry.isReady(record, now: start.addingTimeInterval(30 * 86_400 - 1)))
        #expect(Expiry.isReady(record, now: start.addingTimeInterval(30 * 86_400)))
        #expect(Expiry.days == 30, "the settled number")
    }

    /// The calendar and plain arithmetic disagree across a month whose length is not thirty days,
    /// and it is the calendar that decides.
    @Test func aMonthBoundaryIsCountedByTheCalendar() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let lastDayOfJanuary = try #require(
            calendar.date(from: DateComponents(year: 2027, month: 1, day: 31, hour: 9)))

        let records = try setAside(1, on: lastDayOfJanuary, in: ground)
        let readyOn = Expiry.readyOn(records[0], calendar: calendar)
        let parts = calendar.dateComponents([.year, .month, .day], from: readyOn)

        #expect(parts.year == 2027)
        #expect(parts.month == 3, "January the 31st plus thirty days is in March")
        #expect(parts.day == 2)
    }

    // MARK: 2. Manual — the default, and it removes nothing

    @Test func manualIsWhatAFreshInstallGets() {
        let defaults = QuarantineSandbox.defaults("fresh")
        defer { QuarantineSandbox.forget(defaults, named: "fresh") }
        #expect(Expiry.mode(defaults: defaults) == .manual,
                "somebody was opted into automatic removal by a key that was never written")
    }

    /// ⭐ **A year, and a hundred openings, and nothing is removed.** The items rise to the top of
    /// the list and wait there, which is exactly what the developer asked for.
    @Test func manualRemovesNothingEverNoMatterHowLongOrHowOften() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let start = Date()
        let records = try setAside(3, on: start, in: ground)
        let defaults = settings(.manual, "manual-forever")
        defer { QuarantineSandbox.forget(defaults, named: "manual-forever") }

        for day in stride(from: 0, through: 365, by: 5) {
            let sweep = Expiry.sweepOnOpening(home: ground.home,
                                              now: start.addingTimeInterval(Double(day) * 86_400),
                                              defaults: defaults)
            #expect(sweep.removed.isEmpty, "manual removed something on day \(day)")
            #expect(sweep.report == nil)
        }

        #expect(Quarantine.records(home: ground.home).count == 3)
        for record in records {
            #expect(ground.exists(record.quarantinedURL), "\(record.originalName) was removed")
        }
    }

    /// What manual says instead of removing: how many are waiting, and nothing more.
    @Test func manualCountsWhatIsWaitingAndOffersNoNumberItDidNotMeasure() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let start = Date()
        _ = try setAside(2, on: start, in: ground)
        let defaults = settings(.manual, "manual-counts")
        defer { QuarantineSandbox.forget(defaults, named: "manual-counts") }

        let early = Expiry.sweepOnOpening(home: ground.home,
                                          now: start.addingTimeInterval(10 * 86_400),
                                          defaults: defaults)
        #expect(early.sentence == nil, "nothing is ready, so there is nothing to say")

        let late = Expiry.sweepOnOpening(home: ground.home,
                                         now: start.addingTimeInterval(45 * 86_400),
                                         defaults: defaults)
        let sentence = try #require(late.sentence)
        #expect(sentence.contains("2 items"))
        #expect(sentence.contains("ready to remove"))
        #expect(!sentence.lowercased().contains("freed"))
        #expect(!sentence.lowercased().contains("removed"), "manual removed nothing to report")
    }

    /// Ready items rise to the top and wait there, oldest first. A list sorted only by date would
    /// bury a ready item under a week of newer ones.
    @Test func readyItemsRiseToTheTop() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        // A fixed moment rather than `Date()`: the day-boundary arithmetic below is exact, and a
        // test run at ten to midnight the night the clocks change should not be the thing that
        // fails.
        let now = Date(timeIntervalSince1970: 1_800_043_200)
        let old = try setAside(1, on: now.addingTimeInterval(-40 * 86_400), in: ground)[0]
        let older = try setAside(1, on: now.addingTimeInterval(-90 * 86_400), in: ground)[0]
        let recent = try setAside(1, on: now.addingTimeInterval(-2 * 86_400), in: ground)[0]

        let order = Expiry.sortedForTheScreen([recent, old, older], now: now)
        #expect(order.map(\.id) == [older.id, old.id, recent.id])
        #expect(Expiry.ageSentence(older, now: now).contains("ready to remove"))
        #expect(!Expiry.ageSentence(older, now: now).contains("0 days left"),
                "a ready item counting down to zero reads as a bug")
        #expect(Expiry.ageSentence(recent, now: now) == "Set aside 2 days ago.")
    }

    // MARK: 3. Automatic — it acts on opening, and it says what it did

    /// ⭐ **The quarterly Mac, with automatic switched on.** Everything past thirty days goes, the
    /// files are actually gone from the store, and the app says so in the same breath.
    @Test func automaticRemovesTheOverdueOnesOnTheNextOpeningAndSaysWhat() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let start = Date()
        let records = try setAside(3, on: start, in: ground)
        let defaults = settings(.auto, "auto-quarter")
        defer { QuarantineSandbox.forget(defaults, named: "auto-quarter") }

        let sweep = Expiry.sweepOnOpening(home: ground.home,
                                          now: start.addingTimeInterval(91 * 86_400),
                                          defaults: defaults)

        #expect(sweep.mode == .auto)
        #expect(sweep.wereReady.count == 3)
        #expect(sweep.removed.count == 3)
        for record in records {
            #expect(!ground.exists(record.quarantinedURL))
            #expect(!ground.exists(record.holderURL))
        }
        #expect(Quarantine.records(home: ground.home).isEmpty)

        let sentence = try #require(sweep.sentence)
        #expect(sentence.contains("You asked Wellkept to remove things after 30 days."),
                "the sentence does not say whose instruction this was")
        #expect(sentence.contains("Removed 3 items"))
        #expect(!sentence.lowercased().contains("freed"))
        #expect(!sentence.lowercased().contains("reclaim"))
    }

    /// Automatic touches nothing that is not yet due, even in the same sweep that removes others.
    @Test func automaticLeavesAnythingYoungerThanThirtyDaysAlone() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        let now = Date()
        let overdue = try setAside(1, on: now.addingTimeInterval(-45 * 86_400), in: ground)[0]
        let fresh = try setAside(1, on: now.addingTimeInterval(-1 * 86_400), in: ground)[0]
        try Ledger.write([overdue, fresh], home: ground.home)

        let defaults = settings(.auto, "auto-mixed")
        defer { QuarantineSandbox.forget(defaults, named: "auto-mixed") }

        let sweep = Expiry.sweepOnOpening(home: ground.home, now: now, defaults: defaults)
        #expect(sweep.removed.map(\.id) == [overdue.id])
        #expect(!ground.exists(overdue.quarantinedURL))
        #expect(ground.exists(fresh.quarantinedURL), "something set aside yesterday was removed")
        #expect(Quarantine.records(home: ground.home).map(\.id) == [fresh.id])
    }

    /// Nothing at all set aside means nothing at all to say, in either setting. An app that
    /// announces having done nothing is an app people stop reading.
    @Test func anEmptyQuarantineSaysNothingOnOpening() throws {
        let ground = try ProvingGround()
        defer { ground.tearDown() }

        for mode in ExpiryMode.allCases {
            let defaults = settings(mode, "quiet-\(mode.rawValue)")
            defer { QuarantineSandbox.forget(defaults, named: "quiet-\(mode.rawValue)") }
            let sweep = Expiry.sweepOnOpening(home: ground.home, defaults: defaults)
            #expect(sweep.sentence == nil)
            #expect(sweep.removed.isEmpty)
        }
    }

    // MARK: The setting itself

    /// Both explanations state the limitation rather than hiding it. Wellkept has no background
    /// piece, so "automatic" can only ever act the next time it is opened — and a person who thinks
    /// the app is watching the clock while closed has been misled by us.
    @Test func bothSettingsExplainWhatTheyCanAndCannotDo() {
        #expect(ExpiryMode.manual.explanation.contains("never removes anything on its own"))
        #expect(ExpiryMode.auto.explanation.contains("The next time you open Wellkept"))
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
        for mode in ExpiryMode.allCases {
            #expect(mode.label.contains("30"), "the label does not say how long")
        }
    }

    /// A stored value this build does not recognise is manual, like everything else that is not an
    /// explicit yes. Nobody is opted into automatic removal by accident.
    @Test func anythingOtherThanAnExplicitYesIsManual() {
        let defaults = QuarantineSandbox.defaults("nonsense")
        defer { QuarantineSandbox.forget(defaults, named: "nonsense") }
        defaults.set("delete-everything-immediately", forKey: Expiry.settingsKey)
        #expect(Expiry.mode(defaults: defaults) == .manual)
    }
}

// MARK: - Rewriting one field of a record, for the tests that cannot wait thirty days

extension QuarantineRecord {

    /// The same record with a different date on it.
    ///
    /// ⚠️ Test-only, and deliberately verbose rather than made easy: nothing in the app has any
    /// business changing when something was set aside, and a convenient mutator on the shipping
    /// type would be an invitation to do exactly that.
    func withQuarantinedOn(_ date: Date) -> QuarantineRecord {
        QuarantineRecord(id: id, originalPath: originalPath, originalName: originalName,
                         identity: identity, quarantinedPath: quarantinedPath, storeRoot: storeRoot,
                         mode: mode, ownerID: ownerID, groupID: groupID, flags: flags,
                         createdOn: createdOn, modifiedOn: modifiedOn, bytes: bytes,
                         isDirectory: isDirectory, isSymbolicLink: isSymbolicLink,
                         parentMode: parentMode, sectionRaw: sectionRaw, reason: reason,
                         quarantinedOn: date, wasInICloud: wasInICloud, containment: containment)
    }
}

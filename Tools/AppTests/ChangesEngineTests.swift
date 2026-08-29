// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import WellkeptCore

//  ChangesEngineTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **The six measurements the Changes section is built on, each pinned by a test that fails if
//  somebody undoes it.**
//
//  `ChangesTests` in `Tests/` covers the vocabulary, which links `WellkeptCore` alone. These are
//  the three app-layer files — `SnapshotStore`, `Attribution`, `Diff` — and every one of these
//  tests exists because a measurement on 2026-08-28 said the obvious implementation would be
//  wrong:
//
//  1. **The domain-listing command omits the most important domain.** Appearance, accent colour,
//     text size, key repeat and scroll direction all live in the global domain, which does not
//     appear in a listing. Miss it and the section silently never reports the most visible
//     settings on the Mac.
//  2. **The install record's dates are UTC.** macOS 26.6.2 reads as 25 August and happened on the
//     evening of the 24th.
//  3. **A restart is not evidence of an update** — 15 of this Mac's 25 boots carried none.
//  4. **An outage measured from two minute-resolution readings cannot claim 52 seconds.**
//  5. **An idle Mac moved seven domains in three minutes and not one was a setting.**
//  6. **On a standard account the boot record is unreadable**, and the sentence has to get weaker
//     rather than keep its shape and invent the number.

// MARK: - Fixtures

/// A pretend home folder. Reuses the quarantine sandbox rather than adding a second one, so there
/// is exactly one place in the suite that knows how to make a directory that cleans itself up.
private func sandbox() throws -> QuarantineSandbox { try QuarantineSandbox() }

/// A snapshot built by hand, so a comparison can be exercised against a machine history that never
/// happened rather than only against whatever this Mac did this afternoon.
private func snapshot(_ takenAt: TimeInterval,
                      watched: [String: String] = [:],
                      unreadable: [String: String] = [:],
                      settings: [String: String] = [:],
                      machine: String? = "Mac15,3") -> Snapshot {
    Snapshot(takenAt: Date(timeIntervalSince1970: takenAt),
             machine: machine,
             watched: watched,
             unreadable: unreadable,
             settings: settings)
}

private func window(_ after: TimeInterval, _ before: TimeInterval) -> Window {
    Window(after: Date(timeIntervalSince1970: after), before: Date(timeIntervalSince1970: before))
}

// MARK: - ⚠️ The domain the listing command forgets

@Suite("The capture takes the domain no listing mentions")
struct SnapshotCaptureTests {

    /// A `Sources` that answers from a dictionary rather than from this Mac, so the test proves the
    /// capture's logic instead of proving what somebody's preferences happen to say today.
    private static func sources(folder: URL, world: [String: [String: String]]) -> SnapshotStore.Sources {
        SnapshotStore.Sources(
            preferencesFolder: folder,
            keys: { domain in world[domain].map { Array($0.keys) } },
            value: { domain, key in world[domain]?[key] })
    }

    /// ⭐ **`defaults domains` does not list the global domain.** Appearance, accent colour, text
    /// size, key repeat and scroll direction all live there. This is the test that stops a later
    /// build reaching for the listing command and silently losing the most visible settings on the
    /// Mac.
    @Test func theGlobalDomainIsCapturedEvenThoughNoListingNamesIt() throws {
        let ground = try sandbox()
        defer { ground.tearDown() }

        let folder = ground.home.appending(path: "Preferences")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // A folder that names one ordinary domain, and never the global one.
        try Data("x".utf8).write(to: folder.appending(path: "com.example.thing.plist"))

        let world = [
            "com.example.thing": ["Flag": "1"],
            SnapshotStore.globalDomain: ["AppleInterfaceStyle": "Dark"],
        ]
        let taken = SnapshotStore.capture(sources: Self.sources(folder: folder, world: world))

        let key = SnapshotStore.settingKey(domain: SnapshotStore.globalDomain,
                                           key: "AppleInterfaceStyle")
        #expect(taken.settings[key] == "Dark",
                "the global domain was not captured — a listing that omits it was trusted")
        #expect(taken.settings.count == 2)
    }

    /// The global domain's file on disk is called `.GlobalPreferences`, and every API calls it
    /// something else. Captured twice under two names, every diff would report it changing.
    @Test func theGlobalDomainIsNotCapturedTwiceUnderItsTwoNames() throws {
        let ground = try sandbox()
        defer { ground.tearDown() }

        let folder = ground.home.appending(path: "Preferences")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folder.appending(path: ".GlobalPreferences.plist"))

        let world = [SnapshotStore.globalDomain: ["AppleInterfaceStyle": "Dark"],
                     SnapshotStore.globalDomainFilename: ["AppleInterfaceStyle": "Light"]]
        let taken = SnapshotStore.capture(sources: Self.sources(folder: folder, world: world))

        #expect(taken.settings.count == 1)
        #expect(taken.settings.values.first == "Dark")
    }

    /// ⚠️ Two runs must render the same value identically, or every launch reports the whole Mac as
    /// changed. A dictionary hands its keys over in whatever order it likes.
    @Test func aValueRendersTheSameWayEveryTime() {
        let nested: [String: Any] = ["b": 2, "a": [1, 2], "c": "three"]
        #expect(SnapshotStore.stableString(nested) == "{a=[1,2],b=2,c=three}")
        #expect(SnapshotStore.stableString(nested) == SnapshotStore.stableString(nested))
    }

    /// A window position or a recent-documents list is hundreds of bytes of nothing. The
    /// fingerprint still detects that it moved, which is all version one does with it.
    @Test func aLongValueBecomesAFingerprint() {
        let long = String(repeating: "x", count: SnapshotStore.longestStoredValue + 1)
        let stored = SnapshotStore.stored(long)
        #expect(stored.hasPrefix("#"))
        #expect(stored.count < long.count)
        #expect(SnapshotStore.stored("On") == "On")
        #expect(SnapshotStore.stored(long) != SnapshotStore.stored(long + "y"))
    }

    /// The composite key has to come apart again, or the churn exclusion cannot find its domain.
    @Test func aSettingKeySplitsBackIntoItsTwoHalves() {
        let key = SnapshotStore.settingKey(domain: "com.apple.dock", key: "orientation")
        let parts = SnapshotStore.split(key)
        #expect(parts?.domain == "com.apple.dock")
        #expect(parts?.key == "orientation")
        #expect(SnapshotStore.split("nothing separable") == nil)
    }

    /// ⚠️ Excluded means **not counted**, never **not captured**. A domain wrongly named in that
    /// list would otherwise cost somebody a change they never get to see.
    @Test func everyChurnDomainCarriesTheReasonItIsThere() {
        for domain in SnapshotStore.churnDomains {
            #expect(domain.why.count > 20, "\(domain.domain) is excluded with no reason beside it")
            #expect(SnapshotStore.isChurn(domain.domain))
        }
        #expect(SnapshotStore.churnDomains.count >= 7)
        #expect(!SnapshotStore.isChurn("com.apple.dock"))
    }
}

// MARK: - The record on disk

@Suite("The settings record replays, survives damage, and never splices two Macs together")
struct SnapshotStoreFileTests {

    @Test func differencesReplayBackIntoWholeStates() throws {
        let ground = try sandbox()
        defer { ground.tearDown() }

        SnapshotStore.record(snapshot(1_000, settings: ["a": "1", "b": "2"]), home: ground.home)
        SnapshotStore.record(snapshot(2_000, settings: ["a": "9", "b": "2"]), home: ground.home)
        SnapshotStore.record(snapshot(3_000, settings: ["a": "9"]), home: ground.home)

        let all = SnapshotStore.snapshots(home: ground.home)
        #expect(all.count == 3)
        #expect(all[0].settings == ["a": "1", "b": "2"])
        #expect(all[1].settings == ["a": "9", "b": "2"])
        // A key that disappeared has to disappear on replay, or it haunts the record for ever.
        #expect(all[2].settings == ["a": "9"])
    }

    @Test func theLastTwoAreWhatTheDiffAsksFor() throws {
        let ground = try sandbox()
        defer { ground.tearDown() }

        #expect(SnapshotStore.isEmpty(home: ground.home))
        SnapshotStore.record(snapshot(1_000, settings: ["a": "1"]), home: ground.home)
        #expect(SnapshotStore.lastTwo(home: ground.home).earlier == nil)

        SnapshotStore.record(snapshot(2_000, settings: ["a": "2"]), home: ground.home)
        let pair = SnapshotStore.lastTwo(home: ground.home)
        #expect(pair.earlier?.settings == ["a": "1"])
        #expect(pair.latest?.settings == ["a": "2"])
    }

    /// ⚠️ Migration Assistant carries `~/Library/Application Support` to a new Mac. Stored as a
    /// difference against the old machine's settings, the new one would arrive with thousands of
    /// imaginary changes on its first launch.
    @Test func anotherMacStartsItsOwnBaseline() throws {
        let ground = try sandbox()
        defer { ground.tearDown() }

        SnapshotStore.record(snapshot(1_000, settings: ["a": "1", "b": "2"], machine: "Mac15,3"),
                             home: ground.home)
        SnapshotStore.record(snapshot(2_000, settings: ["z": "9"], machine: "MacBookPro18,1"),
                             home: ground.home)

        let all = SnapshotStore.snapshots(home: ground.home)
        #expect(all.last?.settings == ["z": "9"],
                "the new Mac inherited the old one's settings as a difference")
    }

    /// One unparseable line must never cost the rest of the record — it is the one file in the
    /// section that cannot be recreated by running the check again.
    @Test func oneDamagedLineDoesNotTakeTheRecordWithIt() throws {
        let ground = try sandbox()
        defer { ground.tearDown() }

        SnapshotStore.record(snapshot(1_000, settings: ["a": "1"]), home: ground.home)
        let file = SnapshotStore.url(home: ground.home)
        let good = try String(contentsOf: file, encoding: .utf8)
        try Data((good + "{not json at all\n").utf8).write(to: file, options: .atomic)

        #expect(SnapshotStore.snapshots(home: ground.home).count == 1)
    }

    /// **John's answer 3, 2026-08-28** — save-out is a readable summary *and* the raw file, so it
    /// is worth something to somebody who no longer has Wellkept.
    @Test func savingWritesBothHalves() throws {
        let ground = try sandbox()
        defer { ground.tearDown() }

        SnapshotStore.record(
            snapshot(1_000,
                     watched: [WatchedKey(.protections, "fileVault").storageKey: "On"],
                     settings: ["a": "1"]),
            home: ground.home)

        let folder = ground.home.appending(path: "Picked by the person")
        let written = try SnapshotStore.saveOut(to: folder, home: ground.home)

        #expect(written.count == 2)
        let summary = try String(contentsOf: written[0], encoding: .utf8)
        #expect(summary.contains("FileVault: On"))
        #expect(summary.contains("Safari"), "the summary does not say what it could not cover")
        #expect(FileManager.default.fileExists(atPath: written[1].path))
    }

    /// ⛔ `.delete` removes one file and nothing else. The folder it sits in also holds the
    /// quarantine, which holds the user's own files — a recursive remove there would destroy them
    /// while doing exactly what it was told.
    @Test func deletingTheRecordTouchesNothingElse() throws {
        let ground = try sandbox()
        defer { ground.tearDown() }

        SnapshotStore.record(snapshot(1_000, settings: ["a": "1"]), home: ground.home)
        let neighbour = StorageManifest.supportDirectory(home: ground.home)
            .appending(path: "Ledger.json")
        try Data("somebody's undo record".utf8).write(to: neighbour)

        try SnapshotStore.carryOut(.delete, home: ground.home)

        #expect(!FileManager.default.fileExists(atPath: SnapshotStore.url(home: ground.home).path))
        #expect(FileManager.default.fileExists(atPath: neighbour.path),
                "the farewell reached beyond its own file")
    }

    /// "Leave them where they are" has to actually leave them, or a reinstall next month gets
    /// nothing back.
    @Test func leavingItLeavesIt() throws {
        let ground = try sandbox()
        defer { ground.tearDown() }

        SnapshotStore.record(snapshot(1_000, settings: ["a": "1"]), home: ground.home)
        try SnapshotStore.carryOut(.leave, home: ground.home)
        #expect(SnapshotStore.snapshots(home: ground.home).count == 1)
    }

    /// The record is registered with the manifest, or the uninstaller goes stale the day it ships.
    @Test func theUninstallerKnowsAboutIt() throws {
        let ground = try sandbox()
        defer { ground.tearDown() }

        SnapshotStore.record(snapshot(1_000, settings: ["a": "1"]), home: ground.home)
        let entries = StorageManifest.entries(home: ground.home)
        let ours = entries.first { $0.url == SnapshotStore.url(home: ground.home) }
        #expect(ours != nil, "the settings record is not in the manifest the uninstaller reads")
        #expect(ours?.disposition == .ask, "the uninstaller would delete it without asking")
    }

    @Test func theQuestionSaysHowMuchThereIs() throws {
        let ground = try sandbox()
        defer { ground.tearDown() }

        SnapshotStore.record(snapshot(1_000, settings: ["a": "1"]), home: ground.home)
        SnapshotStore.record(snapshot(2_000, settings: ["a": "2"]), home: ground.home)
        let asked = SnapshotStore.farewellQuestion(home: ground.home)
        #expect(asked.body.contains("2 records"))
        #expect(asked.body.contains("yours to decide"))
    }
}

// MARK: - ⚠️ When, and only as much of who as the evidence supports

@Suite("Attribution says when, never who")
struct AttributionTests {

    /// ⭐ **macOS 26.6.2 is stored as `2026-08-25T02:08:52Z` and happened on the evening of the
    /// 24th.** The plist hands back a correct instant; the trap is every later step that turns it
    /// into a day. Pinned in a fixed time zone so it cannot pass by accident on a Mac set to UTC.
    @Test func the2662UpdateLandsOnThe24th() throws {
        let ground = try sandbox()
        defer { ground.tearDown() }

        let recorded = ISO8601DateFormatter().date(from: "2026-08-25T02:08:52Z")!
        let entries: [[String: Any]] = [
            ["displayName": "macOS 26.6.2", "displayVersion": "26.6.2",
             "date": recorded, "processName": "softwareupdated"],
            ["displayName": "XProtectPlistConfigData", "displayVersion": "5301",
             "date": recorded, "processName": "softwareupdated"],
        ]
        let file = ground.home.appending(path: "InstallHistory.plist")
        let data = try PropertyListSerialization.data(fromPropertyList: entries,
                                                      format: .xml, options: 0)
        try data.write(to: file)

        let installs = try #require(Attribution.installs(at: file))
        #expect(installs.count == 2)

        let macOS = installs.filter(\.isMacOS)
        #expect(macOS.count == 1, "XProtect was reported to somebody as a macOS update")
        #expect(macOS[0].version == "26.6.2")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Denver")!
        #expect(calendar.component(.day, from: macOS[0].installedAt) == 24,
                "the install record was read as UTC and the update landed a day out")
    }

    /// ⛔ **15 of this Mac's 25 boots carried no update.** A restart on its own can never produce a
    /// `MacOSUpdate`, and there is deliberately no function that tries.
    @Test func aRestartAloneIsNeverAnUpdate() {
        let asked = window(1_000, 100_000)
        let wentDown = Attribution.BootSession(startedAt: Date(timeIntervalSince1970: 60_000),
                                               stoppedAt: Date(timeIntervalSince1970: 59_000),
                                               exact: true)
        let verdict = Attribution.verdict(for: asked, record: [], boots: [wentDown])

        if case .duringMacOSUpdate = verdict.cause {
            Issue.record("a reboot with no install record was reported as a macOS update")
        }
        #expect(verdict.macWasOffOrAsleep, "the Mac was off and the report did not say so")
        #expect(verdict.confidence == .noEvidence)
    }

    /// The strongest sentence available, and the half of it that matters: *during*, never *because*.
    @Test func anUpdateInTheWindowIsStatedAsACoincidence() {
        let asked = window(1_000, 100_000)
        let install = Attribution.Install(name: "macOS 26.6.2", version: "26.6.2",
                                          installedAt: Date(timeIntervalSince1970: 59_500),
                                          process: "softwareupdated")
        let wentDown = Attribution.BootSession(startedAt: Date(timeIntervalSince1970: 59_792),
                                               stoppedAt: Date(timeIntervalSince1970: 59_500),
                                               exact: true)
        let verdict = Attribution.verdict(for: asked, record: [install], boots: [wentDown])

        guard case let .duringMacOSUpdate(update) = verdict.cause else {
            Issue.record("the update in the window was not found")
            return
        }
        #expect(verdict.confidence == .consistent, "a coincidence was reported as a certainty")
        #expect(update.sentence.contains("while your Mac was off for the macOS 26.6.2 update"))
        #expect(!update.sentence.lowercased().contains("caused"))
        #expect(update.outage != nil)
    }

    /// ⚠️ **On a standard account the boot record is unreadable.** We still know an update happened
    /// and when; we lose the evidence that the Mac was off, which is what made the claim strong. So
    /// the sentence gets weaker rather than keeping its shape and inventing the number.
    @Test func aStandardAccountLosesTheOutageAndSaysSoRatherThanGuessing() {
        let asked = window(1_000, 100_000)
        let install = Attribution.Install(name: "macOS 26.6.2", version: "26.6.2",
                                          installedAt: Date(timeIntervalSince1970: 59_500),
                                          process: "softwareupdated")
        let verdict = Attribution.verdict(for: asked, record: [install], boots: nil)

        #expect(verdict.outageUnreadable == .notGrantable)
        #expect(verdict.outageUnreadable?.stillComplete == true,
                "a refusal nobody can lift was made to look like a permission somebody withheld")
        guard case let .duringMacOSUpdate(update) = verdict.cause else {
            Issue.record("the update was lost along with the boot record")
            return
        }
        #expect(update.outage == nil)
        #expect(update.sentence == "this changed in the same period as the macOS 26.6.2 update")
    }

    /// ⚠️ **`nil` is "could not read" and `[]` is "nothing there".** Collapsing them is how a
    /// section ends up reporting zero because it did not look.
    @Test func nothingReadableAtAllIsUnknownRatherThanAnAnswer() {
        let verdict = Attribution.verdict(for: window(1_000, 100_000), record: nil, boots: nil)
        #expect(verdict.cause == .unknown)
        #expect(verdict.confidence == .noEvidence, "unknown claimed a confidence it has no cause for")
    }

    /// No update, no shutdown, and both records readable: somebody was at the machine. Still not
    /// who — "you" here means this Mac's keyboard.
    @Test func aMacThatNeverWentDownWasBeingUsed() {
        let verdict = Attribution.verdict(for: window(1_000, 100_000), record: [], boots: [])
        #expect(verdict.cause == .whileYouWereUsingTheMac)
        #expect(!verdict.macWasOffOrAsleep)
    }

    /// `last -y` prints "reboot ~ Mon Aug 24 2026 20:07". Without `-y` every boot older than twelve
    /// months lands in the wrong year.
    @Test func aBootLineIsParsedInTheMacsOwnTimeZone() {
        let zone = TimeZone(identifier: "America/Denver")!
        let parsed = Attribution.parseBootLine("reboot    ~                         Mon Aug 24 2026 20:07",
                                               timeZone: zone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        if let read = parsed {
            #expect(read.kind == "reboot")
            #expect(calendar.component(.day, from: read.at) == 24)
            #expect(calendar.component(.hour, from: read.at) == 20)
        } else {
            Issue.record("a `last -y` reboot line was not recognised")
        }
        #expect(Attribution.parseBootLine("jds  console  Mon Aug 24 2026 20:09") == nil)
    }

    /// ⚠️ **Two minute-resolution readings cannot produce "and 52 seconds".** The precision travels
    /// with the measurement, and a session with only one exact end says "about four minutes".
    @Test func secondsAreClaimedOnlyWhenBothEndsWereMeasuredToTheSecond() {
        let zone = TimeZone(identifier: "America/Denver")!
        let lines = ["reboot    ~   Mon Aug 24 2026 20:07",
                     "shutdown  ~   Mon Aug 24 2026 20:04"]

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let boot = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24,
                                                      hour: 20, minute: 7, second: 29))!
        let down = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24,
                                                      hour: 20, minute: 4, second: 17))!

        let sharp = Attribution.sessions(from: lines, currentBoot: boot, lastShutdown: down,
                                         timeZone: zone)
        #expect(sharp.first?.exact == true)

        // The same lines with no second-precision source at either end.
        let blunt = Attribution.sessions(from: lines, currentBoot: nil, lastShutdown: nil,
                                         timeZone: zone)
        #expect(blunt.first?.exact == false)

        let outages = Attribution.outages(in: window(0, 2_000_000_000), sessions: sharp)
        #expect(outages.first?.sentence == "three minutes and twelve seconds")
    }

    /// A reboot with no shutdown recorded before it is a crash or a power cut. Nothing on macOS
    /// distinguishes those after the fact, so it gets no invented instant.
    @Test func aCrashHasNoMeasuredOutage() {
        let zone = TimeZone(identifier: "America/Denver")!
        let sessions = Attribution.sessions(from: ["reboot    ~   Mon Aug 24 2026 20:07"],
                                            timeZone: zone)
        #expect(sessions.first?.stoppedAt == nil)
        #expect(Attribution.outages(in: window(0, 2_000_000_000), sessions: sessions).isEmpty)
    }

    @Test func aVersionIsRecoveredFromTheNameWhenTheRecordCarriesNone() {
        #expect(Attribution.versionFromName("macOS 26.6.2") == "26.6.2")
        #expect(Attribution.versionFromName("Pages") == "Pages")
    }
}

// MARK: - ⭐ Comparing values, never dates

@Suite("The diff compares values and counts what it cannot explain")
struct DiffTests {

    private static let fileVault = WatchedKey(.protections, "fileVault").storageKey
    private static let firewall = WatchedKey(.protections, "firewall").storageKey

    /// ⚠️ **An absent key means "we did not look then", not "it was different".** Most launches take
    /// a snapshot without running the Security readers.
    @Test func aKeyThatWasNeverReadIsNotAChange() {
        let before = snapshot(1_000, watched: [:])
        let after = snapshot(2_000, watched: [Self.fileVault: "On"])
        let found = Diff.changes(from: before, to: after, window: window(1_000, 2_000),
                                 cause: .unknown, confidence: .noEvidence)
        #expect(found.isEmpty, "a first reading was reported as a change")
    }

    @Test func aSwitchThatMovedIsAChangeWithBothItsValues() {
        let before = snapshot(1_000, watched: [Self.firewall: "On"])
        let after = snapshot(2_000, watched: [Self.firewall: "Off"])
        let found = Diff.changes(from: before, to: after, window: window(1_000, 2_000),
                                 cause: .unknown, confidence: .noEvidence)
        #expect(found.count == 1)
        #expect(found.first?.from == "On")
        #expect(found.first?.to == "Off")
        #expect(found.first?.what == "Firewall")
        #expect(found.first?.severity(Watched.of(WatchedKey(.protections, "firewall"))) == .attention)
    }

    /// A privacy grant is the one place where a key appearing genuinely is the news, and the row
    /// names the app — by its **name for the eye and its bundle identifier for the record**.
    @Test func anAppGainingAPermissionIsSaidWithItsName() {
        let grant = Diff.instanceKey(WatchedKey(.whoCanWatch, "screenRecording"),
                                     instance: "us.zoom.xos")
        let before = snapshot(1_000, watched: [Self.firewall: "On"])
        let after = snapshot(2_000, watched: [Self.firewall: "On", grant: "Allowed"])

        let found = Diff.changes(from: before, to: after, window: window(1_000, 2_000),
                                 cause: .unknown, confidence: .noEvidence,
                                 names: ["us.zoom.xos": "Zoom"])
        #expect(found.count == 1)
        #expect(found.first?.what == "Zoom — Screen recording")
        #expect(found.first?.from == "Not allowed")
    }

    @Test func anAppLosingAPermissionIsAlsoTheNews() {
        let grant = Diff.instanceKey(WatchedKey(.whoCanWatch, "camera"), instance: "us.zoom.xos")
        let other = Diff.instanceKey(WatchedKey(.whoCanWatch, "microphone"), instance: "com.apple.FaceTime")
        let before = snapshot(1_000, watched: [grant: "Allowed", other: "Allowed"])
        let after = snapshot(2_000, watched: [other: "Allowed"])

        let found = Diff.changes(from: before, to: after, window: window(1_000, 2_000),
                                 cause: .unknown, confidence: .noEvidence)
        #expect(found.count == 1)
        #expect(found.first?.to == "Not allowed")
    }

    /// A launch that never read the grants must not report every app on the Mac as having lost
    /// everything.
    @Test func aLaunchThatSkippedTheReadersReportsNoLostPermissions() {
        let grant = Diff.instanceKey(WatchedKey(.whoCanWatch, "camera"), instance: "us.zoom.xos")
        let before = snapshot(1_000, watched: [grant: "Allowed"])
        let after = snapshot(2_000, watched: [Self.firewall: "On"])

        let found = Diff.changes(from: before, to: after, window: window(1_000, 2_000),
                                 cause: .unknown, confidence: .noEvidence)
        #expect(found.isEmpty)
    }

    /// A key with no description cannot become a row. It is counted somewhere else or not at all.
    @Test func anUndescribedKeyIsNeverDrawnAsARow() {
        let orphan = WatchedKey(.protections, "somethingNobodyDescribes").storageKey
        let before = snapshot(1_000, watched: [orphan: "On"])
        let after = snapshot(2_000, watched: [orphan: "Off"])
        #expect(Diff.changes(from: before, to: after, window: window(1_000, 2_000),
                             cause: .unknown, confidence: .noEvidence).isEmpty)
    }

    /// ⚠️ **An idle Mac moved seven domains in three minutes and not one was a setting.** They are
    /// excluded from the count by name, and so is Wellkept's own domain — reporting our own
    /// preferences moving because somebody opened our Settings window is the app pointing at itself.
    @Test func daemonBookkeepingAndOurOwnNoiseAreNotCounted() {
        let churn = SnapshotStore.settingKey(domain: "com.apple.spaces", key: "seed")
        let ours = SnapshotStore.settingKey(domain: "studio.stonemesa.wellkept", key: "lastSection")
        let real = SnapshotStore.settingKey(domain: "com.apple.dock", key: "orientation")

        let before = snapshot(1_000, settings: [churn: "1", ours: "hardware", real: "bottom"])
        let after = snapshot(2_000, settings: [churn: "2", ours: "storage", real: "left"])

        #expect(Diff.undescribed(from: before, to: after,
                                 ourBundleID: "studio.stonemesa.wellkept") == 1)
    }

    /// A capture that failed on either side must not report the entire Mac as changed.
    @Test func anEmptyCaptureCountsNothing() {
        let full = snapshot(2_000, settings: ["com.apple.dock\u{1}orientation": "left"])
        #expect(Diff.undescribed(from: snapshot(1_000), to: full) == 0)
        #expect(Diff.undescribed(from: full, to: snapshot(3_000)) == 0)
    }

    /// A key that disappeared from the full capture is a change too.
    @Test func aSettingThatWentAwayIsCounted() {
        let a = SnapshotStore.settingKey(domain: "com.apple.dock", key: "orientation")
        let b = SnapshotStore.settingKey(domain: "com.apple.dock", key: "tilesize")
        let before = snapshot(1_000, settings: [a: "left", b: "48"])
        let after = snapshot(2_000, settings: [a: "left"])
        #expect(Diff.undescribed(from: before, to: after) == 1)
    }
}

// MARK: - What the section reports

@Suite("The report never says all clear when it could not look")
struct DiffReportTests {

    private static let fileVault = WatchedKey(.protections, "fileVault").storageKey

    @Test func theFirstLaunchIsAFirstLookRatherThanAnAllClear() {
        let report = Diff.report(earlier: nil, latest: snapshot(2_000))
        #expect(report.isFirstLook)
        #expect(report.status == .notChecked)
    }

    /// A comparison across a change of machine is not a comparison, so it is honestly a first look
    /// and says so rather than reporting every setting on the new Mac as somebody's doing.
    @Test func aNewMacIsAFirstLookAndNotAThousandChanges() {
        let before = snapshot(1_000, watched: [Self.fileVault: "On"], machine: "Mac15,3")
        let after = snapshot(2_000, watched: [Self.fileVault: "Off"], machine: "MacBookPro18,1")
        let report = Diff.report(earlier: before, latest: after)
        #expect(report.isFirstLook)
        #expect(report.changes.isEmpty)
    }

    /// ⚠️ **Lockdown Mode is recorded and never put on the face.** It is unreadable on every Mac
    /// Apple has shipped, so a caveat about it every launch is a caveat nobody can ever clear —
    /// which is exactly how an app teaches people to stop reading its caveats.
    @Test func aReadingMacOSNeverPublishesIsKeptButNotDrawn() {
        let lockdown = WatchedKey(.protections, "lockdownMode").storageKey
        let camera = WatchedKey(.whoCanWatch, "camera").storageKey
        let taken = snapshot(2_000, unreadable: [lockdown: Unreadable.notReported.rawValue,
                                                 camera: Unreadable.notPermitted.rawValue])
        let unread = Diff.unread(taken)
        #expect(unread.count == 1)
        #expect(unread.first?.key.topic == .whoCanWatch)
        #expect(unread.first?.why == .notPermitted)
    }

    /// One line per topic. **John's answer 4, 2026-08-28**: shown once, never repeated per
    /// permission.
    @Test func theFullDiskAccessLineIsSaidOnceAndNotTwelveTimes() {
        var unreadable: [String: String] = [:]
        for permission in WellkeptCore.Permission.allCases {
            unreadable[WatchedKey(.whoCanWatch, permission.rawValue).storageKey] =
                Unreadable.notPermitted.rawValue
        }
        #expect(Diff.unread(snapshot(2_000, unreadable: unreadable)).count == 1)
    }

    /// **John's answer 4** — we can see *that* the grants changed and not *what*, and that is the
    /// one line with the button on it.
    @Test func privacyGoingDarkIsReportedRatherThanReadingAsZero() {
        let camera = WatchedKey(.whoCanWatch, "camera").storageKey
        let grant = Diff.instanceKey(WatchedKey(.whoCanWatch, "camera"), instance: "us.zoom.xos")

        let couldSee = snapshot(1_000, watched: [grant: "Allowed"])
        let refused = snapshot(2_000, unreadable: [camera: Unreadable.notPermitted.rawValue])

        #expect(Diff.privacyWentDark(couldSee, refused))
        #expect(Diff.privacyWentDark(refused, couldSee), "losing the refusal is a change too")

        let neverLooked = snapshot(1_500)
        #expect(!Diff.privacyWentDark(neverLooked, couldSee),
                "a launch that did not run the readers was reported as a permission change")

        let report = Diff.report(earlier: couldSee, latest: refused,
                                 verdict: Attribution.Verdict(cause: .unknown,
                                                              confidence: .noEvidence,
                                                              macWasOffOrAsleep: false,
                                                              outageUnreadable: nil))
        #expect(!report.complete)
        #expect(report.status == .notChecked, "a run that could not look reported a clean bill")
    }

    /// ⚠️ A Mac asleep or switched off between snapshots has to be said, not glossed. "Since
    /// Tuesday" reads as five days of use.
    @Test func timeTheMacWasOffTravelsIntoTheSentence() {
        let before = snapshot(1_000, watched: [Self.fileVault: "On"])
        let after = snapshot(500_000, watched: [Self.fileVault: "Off"])
        let report = Diff.report(earlier: before, latest: after,
                                 now: Date(timeIntervalSince1970: 500_000),
                                 verdict: Attribution.Verdict(cause: .unknown,
                                                              confidence: .noEvidence,
                                                              macWasOffOrAsleep: true,
                                                              outageUnreadable: nil))
        #expect(report.summary.contains("asleep or switched off"))
        #expect(report.changes.first?.window.macWasOffOrAsleep == true)
    }

    /// ⚠️ A setting an organisation forces is never raised — an accusation aimed at somebody who
    /// cannot act on it.
    @Test func anOrganisationSetSwitchIsStatedAndNeverRaised() {
        let before = snapshot(1_000, watched: [Self.fileVault: "On"])
        let after = snapshot(2_000, watched: [Self.fileVault: "Off"])
        let report = Diff.report(earlier: before, latest: after,
                                 organisationSets: [WatchedKey(.protections, "fileVault")],
                                 verdict: Attribution.Verdict(cause: .unknown,
                                                              confidence: .noEvidence,
                                                              macWasOffOrAsleep: false,
                                                              outageUnreadable: nil))
        #expect(report.changes.first?.cause == .setByAnOrganisation)
        #expect(report.changes.first?.confidence == .certain)
        #expect(report.status == .good, "a Mac configured by an employer was called faulty")
    }

    /// The readings the Security section already produced turn into snapshot values without going
    /// back to the disk — and a sharing service is never recorded as "Off", because no reading on
    /// macOS proves one is.
    @Test func readingsBecomeValuesWithoutRereadingTheWorld() {
        var readings = Diff.Readings()
        readings.protections[.fileVault] = "On"
        readings.protectionsUnreadable[.lockdownMode] = .notReported
        readings.listening[.remoteLogin] = true
        readings.listening[.fileSharing] = false
        readings.startupCounts[.userAgent] = 14
        readings.grants = [Grant(appName: "Zoom", bundleID: "us.zoom.xos", permission: .camera),
                           Grant(appName: "Wellkept", bundleID: "studio.stonemesa.wellkept",
                                 permission: .fullDiskAccess, isWellkept: true)]
        readings.systemVersion = "26.6.2"

        let (watched, unreadable) = Diff.values(from: readings)

        #expect(watched[WatchedKey(.protections, "fileVault").storageKey] == "On")
        #expect(unreadable[WatchedKey(.protections, "lockdownMode").storageKey] == "notReported")
        #expect(watched[WatchedKey(.reachableFrom, "remoteLogin").storageKey] == "Listening")
        #expect(watched[WatchedKey(.reachableFrom, "fileSharing").storageKey] == "Not seen listening")
        #expect(watched[WatchedKey(.startsOnItsOwn, "userAgent").storageKey] == "14")
        #expect(watched[WatchedKey(.macOSItself, "systemVersion").storageKey] == "26.6.2")

        let zoom = Diff.instanceKey(WatchedKey(.whoCanWatch, "camera"), instance: "us.zoom.xos")
        #expect(watched[zoom] == "Allowed")
        #expect(watched.keys.contains { $0.contains("studio.stonemesa.wellkept") } == false,
                "Wellkept's own grant was recorded as a change in somebody's permissions")
    }

    /// A refused Full Disk Access collapses the whole grant list, and it must read as a refusal
    /// rather than as twelve permissions nobody holds.
    @Test func aRefusedGrantListIsRecordedAsARefusal() {
        var readings = Diff.Readings()
        readings.grantsRefused = true
        let (watched, unreadable) = Diff.values(from: readings)
        #expect(watched.isEmpty)
        #expect(unreadable.count == WellkeptCore.Permission.allCases.count)
        #expect(unreadable.values.allSatisfy { $0 == Unreadable.notPermitted.rawValue })
    }
}

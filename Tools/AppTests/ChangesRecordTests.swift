// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import WellkeptCore

//  ChangesRecordTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **The four measured near-misses that a test built out of dictionaries cannot catch, and the
//  question the uninstaller has to ask.**
//
//  `ChangesEngineTests` exercises the three engine files against snapshots typed out by hand, which
//  is the right way to test a comparison. It cannot test the two things below, because both are
//  about the *filesystem*:
//
//  1. ⛔ **A file rewritten with identical contents must produce no change.** Three quarters of the
//     preference files on this Mac were rewritten inside a day by daemons that changed nothing.
//     Proving that with a dictionary proves nothing — a dictionary has no modification date to be
//     tempted by. So these tests write real files, touch them, and read them back.
//  2. ⚠️ **Excluded means not COUNTED, never not captured.** The churn domains are still written
//     into every snapshot, because a record cannot be back-filled and a domain wrongly named in
//     that list would otherwise cost somebody a change they never get to see.
//
//  And two about what the section is allowed to conclude:
//
//  3. ⛔ **15 of this Mac's 25 boots carried no update.** One restart proving that is a coincidence;
//     twenty-five of them, ten of which carried an update, is the shape of the real record.
//  4. ⭐ **Answer 3, 2026-08-28.** On uninstall the settings record is asked about, with
//     three buttons — leave, save, delete. `SnapshotStore` has held the words since it was written;
//     what these tests check is that the uninstaller actually asks them.

// MARK: - Fixtures

/// A preferences folder made of real `.plist` files, read the way `SnapshotStore` reads the real
/// one.
///
/// ⚠️ **The point of this fixture is that it has modification dates.** Everything else in the suite
/// hands `SnapshotStore` a dictionary, which is a world where dates do not exist and a
/// date-comparing implementation would pass every test. Here a file can be rewritten with the same
/// bytes, which is exactly what daemons do all day on a real Mac.
private struct PreferencesFolder {

    let url: URL

    init(_ sandbox: QuarantineSandbox) throws {
        url = try sandbox.folder("Library/Preferences")
    }

    /// Write one domain's plist. Rewriting an existing domain moves its modification date whether or
    /// not any value is different — which is the whole experiment.
    func write(_ domain: String, _ values: [String: String]) throws {
        let name = domain == SnapshotStore.globalDomain
            ? SnapshotStore.globalDomainFilename : domain
        let file = url.appending(path: "\(name).plist")
        let data = try PropertyListSerialization.data(fromPropertyList: values,
                                                      format: .xml, options: 0)
        try data.write(to: file)
    }

    /// A `Sources` that reads those files, in place of `CFPreferences` reading this Mac.
    var sources: SnapshotStore.Sources {
        let folder = url
        @Sendable func read(_ domain: String) -> [String: String]? {
            let name = domain == SnapshotStore.globalDomain
                ? SnapshotStore.globalDomainFilename : domain
            let file = folder.appending(path: "\(name).plist")
            guard let data = try? Data(contentsOf: file),
                  let raw = try? PropertyListSerialization.propertyList(from: data, format: nil)
            else { return nil }
            return raw as? [String: String]
        }
        return SnapshotStore.Sources(
            preferencesFolder: folder,
            keys: { read($0).map { Array($0.keys) } },
            value: { domain, key in read(domain)?[key].map(SnapshotStore.stableString) }
        )
    }

    /// The modification date of one domain's file, so a test can prove it really did move.
    func modified(_ domain: String) -> Date? {
        let name = domain == SnapshotStore.globalDomain
            ? SnapshotStore.globalDomainFilename : domain
        let file = url.appending(path: "\(name).plist")
        return (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate]
            as? Date
    }
}

// MARK: - ⛔ Values, never dates

/// ⭐ **Measured 2026-08-28: three quarters of the preference files in `~/Library/Preferences` had
/// been rewritten inside a day, by daemons, and almost none of them had changed a value.**
///
/// The obvious implementation — look at what moved lately — would therefore report a settled Mac as
/// churning every time somebody opened the app, and would look right doing it, because something
/// genuinely did happen to those files. The only honest comparison is of the values themselves.
@Suite("A file rewritten with the same contents is not a change")
struct ChangesCompareValuesTests {

    private static let domain = "com.example.settled"

    @Test("Rewriting a file with identical contents produces nothing at all")
    func aFileRewrittenWithTheSameContentsIsNoChange() throws {
        let ground = try QuarantineSandbox()
        defer { ground.tearDown() }
        let preferences = try PreferencesFolder(ground)

        let values = ["AppleInterfaceStyle": "Dark", "KeyRepeat": "2"]
        try preferences.write(Self.domain, values)
        let before = SnapshotStore.capture(now: Date(timeIntervalSince1970: 1_000),
                                           sources: preferences.sources)
        let firstWrite = preferences.modified(Self.domain)

        // A daemon rewrites the file. Same bytes, new date — the ordinary event on a real Mac.
        Thread.sleep(forTimeInterval: 0.02)
        try preferences.write(Self.domain, values)
        let secondWrite = preferences.modified(Self.domain)

        let after = SnapshotStore.capture(now: Date(timeIntervalSince1970: 2_000),
                                          sources: preferences.sources)

        // The experiment is only an experiment if the date actually moved.
        #expect(firstWrite != nil && secondWrite != nil)
        #expect(secondWrite! > firstWrite!,
                "the file was not really rewritten, so this test proved nothing")

        #expect(before.settings == after.settings)
        #expect(Diff.undescribed(from: before, to: after, ourBundleID: nil) == 0,
                "a file rewritten with identical contents was reported as a change")

        let report = Diff.report(earlier: before, latest: after,
                                 verdict: Attribution.Verdict(cause: .unknown,
                                                              confidence: .noEvidence,
                                                              macWasOffOrAsleep: false,
                                                              outageUnreadable: nil))
        #expect(report.changes.isEmpty)
        #expect(report.undescribed == 0)
        #expect(report.status == .good)
    }

    /// The positive control. A test that only proves nothing was reported is indistinguishable from
    /// a comparison that reports nothing ever.
    @Test("A value that genuinely moved is counted")
    func aValueThatMovedIsCounted() throws {
        let ground = try QuarantineSandbox()
        defer { ground.tearDown() }
        let preferences = try PreferencesFolder(ground)

        try preferences.write(Self.domain, ["AppleInterfaceStyle": "Dark", "KeyRepeat": "2"])
        let before = SnapshotStore.capture(now: Date(timeIntervalSince1970: 1_000),
                                           sources: preferences.sources)
        try preferences.write(Self.domain, ["AppleInterfaceStyle": "Light", "KeyRepeat": "2"])
        let after = SnapshotStore.capture(now: Date(timeIntervalSince1970: 2_000),
                                          sources: preferences.sources)

        #expect(Diff.undescribed(from: before, to: after, ourBundleID: nil) == 1)
    }

    /// ⚠️ **And a value that came back to where it started is not a change either.** Two writes and
    /// a fresh date, and the setting is what it was; a section that reported that would be reporting
    /// its own scheduling.
    @Test("A value that went away and came back is not a change")
    func aRoundTripIsNotAChange() throws {
        let ground = try QuarantineSandbox()
        defer { ground.tearDown() }
        let preferences = try PreferencesFolder(ground)

        try preferences.write(Self.domain, ["AppleInterfaceStyle": "Dark"])
        let before = SnapshotStore.capture(now: Date(timeIntervalSince1970: 1_000),
                                           sources: preferences.sources)
        try preferences.write(Self.domain, ["AppleInterfaceStyle": "Light"])
        try preferences.write(Self.domain, ["AppleInterfaceStyle": "Dark"])
        let after = SnapshotStore.capture(now: Date(timeIntervalSince1970: 2_000),
                                          sources: preferences.sources)

        #expect(Diff.undescribed(from: before, to: after, ourBundleID: nil) == 0)
    }
}

// MARK: - ⚠️ Excluded means not counted, never not captured

/// ⭐ **The distinction the whole exclusion list rests on.**
///
/// Eight domains are named in `SnapshotStore.churnDomains`, each with the reason it is there. They
/// are subtracted from the number on screen — the "and 41 other values also changed" line — and
/// **from nothing else**. Every one of them is still written into the record, because a record
/// cannot be back-filled and a domain wrongly listed would otherwise cost somebody a change they
/// never get to see. Being wrong about the count is cheap; being wrong about the record is not.
@Suite("The churn domains are excluded from the count and kept in the record")
struct ChangesChurnTests {

    @Test("A domain that keeps score is captured and not counted")
    func daemonBookkeepingIsKeptButNotCounted() throws {
        let ground = try QuarantineSandbox()
        defer { ground.tearDown() }
        let preferences = try PreferencesFolder(ground)

        let churn = try #require(SnapshotStore.churnDomains.first?.domain)
        try preferences.write(churn, ["lastRun": "1"])
        try preferences.write("com.example.real", ["Setting": "On"])
        let before = SnapshotStore.capture(now: Date(timeIntervalSince1970: 1_000),
                                           sources: preferences.sources)

        try preferences.write(churn, ["lastRun": "2"])
        let after = SnapshotStore.capture(now: Date(timeIntervalSince1970: 2_000),
                                          sources: preferences.sources)

        let key = SnapshotStore.settingKey(domain: churn, key: "lastRun")
        #expect(before.settings[key] == "1", "an excluded domain was not captured")
        #expect(after.settings[key] == "2", "an excluded domain stopped being captured")
        #expect(Diff.undescribed(from: before, to: after, ourBundleID: nil) == 0,
                "daemon bookkeeping was counted as a change to somebody's settings")

        // And the record says which domains were held back, by name, so a file read in three years
        // does not need this source to explain a gap.
        #expect(Set(after.excludedDomains) == Set(SnapshotStore.churnDomains.map(\.domain)))
    }

    /// ⭐ **The domain the listing command omits — and the one that carries appearance, accent
    /// colour, text size, key repeat and scroll direction.**
    ///
    /// `SnapshotStore` inserts it by name because nothing else will. This checks the half that
    /// matters after that: it is not on the exclusion list, so a change in the most visible settings
    /// on the Mac is counted rather than quietly dropped along with the daemon noise.
    @Test("The global domain is captured by name and is not excluded")
    func theMostVisibleSettingsAreCounted() throws {
        let ground = try QuarantineSandbox()
        defer { ground.tearDown() }
        let preferences = try PreferencesFolder(ground)

        #expect(!SnapshotStore.isChurn(SnapshotStore.globalDomain),
                "the domain holding appearance and text size was put on the churn list")

        try preferences.write(SnapshotStore.globalDomain, ["AppleInterfaceStyle": "Dark"])
        let before = SnapshotStore.capture(now: Date(timeIntervalSince1970: 1_000),
                                           sources: preferences.sources)
        try preferences.write(SnapshotStore.globalDomain, ["AppleInterfaceStyle": "Light"])
        let after = SnapshotStore.capture(now: Date(timeIntervalSince1970: 2_000),
                                          sources: preferences.sources)

        let key = SnapshotStore.settingKey(domain: SnapshotStore.globalDomain,
                                           key: "AppleInterfaceStyle")
        #expect(before.settings[key] == "Dark")
        #expect(after.settings[key] == "Light")
        #expect(Diff.undescribed(from: before, to: after, ourBundleID: nil) == 1,
                "a change to the Mac's appearance was not counted")
    }

    /// Every excluded domain carries the reason it is there, and at least half were observed moving
    /// rather than guessed at. A list nobody can justify is a list that quietly grows until the
    /// section reports nothing.
    @Test("The exclusion list is short, justified, and mostly measured")
    func theListCannotQuietlyGrow() {
        let domains = SnapshotStore.churnDomains
        #expect(domains.count <= 12, "the exclusion list is growing: \(domains.count) domains")
        for domain in domains {
            #expect(domain.why.count >= 30, "\(domain.domain) has no real reason beside it")
            #expect(domain.why.hasSuffix("."))
        }
        #expect(domains.filter(\.measured).count >= domains.count / 2,
                "most of the exclusion list is now guesswork rather than measurement")

        // ⚠️ Nobody else's application is on it. Naming another developer's software in a
        // hard-coded exclusion list is a judgement about their software on three minutes of
        // evidence, and this section refuses that everywhere else.
        for domain in domains {
            #expect(domain.domain.hasPrefix("com.apple.") || !domain.domain.contains("."),
                    "\(domain.domain) is somebody else's software, named in our exclusion list")
        }
    }
}

// MARK: - ⛔ Twenty-five boots, ten updates

/// ⭐ **15 of this Mac's 25 recorded boots carried no update at all.**
///
/// One restart with no install record is a unit test. Twenty-five of them, ten of which really did
/// carry an update, is the shape of a real machine's history — and it is the only way to catch an
/// implementation that pairs an update with the *nearest* boot rather than with the boot it
/// happened inside. That mistake would attribute ten updates to twenty-five restarts and be right
/// about ten of them, which is exactly the failure mode that looks like it works.
@Suite("A restart is never evidence of an update, over a whole machine's history")
struct ChangesBootHistoryTests {

    /// One session per hour, five minutes of darkness at the start of each.
    private static func machineHistory() -> (sessions: [Attribution.BootSession],
                                             installs: [Attribution.Install],
                                             updated: Set<Int>) {
        let hour: TimeInterval = 3_600
        let base: TimeInterval = 1_780_000_000
        // Ten of twenty-five, scattered rather than the first ten, so an off-by-one cannot pass.
        let updated: Set<Int> = [0, 2, 3, 7, 11, 12, 16, 19, 22, 24]

        var sessions: [Attribution.BootSession] = []
        var installs: [Attribution.Install] = []
        for index in 0..<25 {
            let wentDown = base + Double(index) * hour
            let cameBack = wentDown + 292          // the measured outage: four minutes, 52 seconds
            sessions.append(Attribution.BootSession(startedAt: Date(timeIntervalSince1970: cameBack),
                                                    stoppedAt: Date(timeIntervalSince1970: wentDown),
                                                    exact: true))
            if updated.contains(index) {
                installs.append(Attribution.Install(
                    name: "macOS 26.6.\(index)", version: "26.6.\(index)",
                    installedAt: Date(timeIntervalSince1970: wentDown + 83),
                    process: "softwareupdated"))
            }
            // Every boot carries data updates, which share `softwareupdated` and are not macOS.
            installs.append(Attribution.Install(name: "XProtectPlistConfigData", version: "5301",
                                               installedAt: Date(timeIntervalSince1970: wentDown + 90),
                                               process: "softwareupdated"))
        }
        return (sessions, installs, updated)
    }

    @Test("Only the ten boots with an install record produce an update")
    func fifteenOfTwentyFiveBootsCarryNothing() {
        let history = Self.machineHistory()
        var attributed = 0

        for index in 0..<25 {
            let session = history.sessions[index]
            let window = Window(after: session.stoppedAt!.addingTimeInterval(-60),
                                before: session.startedAt.addingTimeInterval(60))
            let verdict = Attribution.verdict(for: window,
                                              record: history.installs,
                                              boots: [session])

            if case let .duringMacOSUpdate(update) = verdict.cause {
                attributed += 1
                #expect(history.updated.contains(index),
                        "boot \(index) carried no update and was reported as one")
                #expect(update.version == "26.6.\(index)",
                        "an update was paired with the wrong boot")
                #expect(verdict.confidence == .consistent,
                        "a coincidence in time was reported as a certainty")
            } else {
                #expect(!history.updated.contains(index),
                        "boot \(index) carried an update and it was missed")
                #expect(verdict.confidence == .noEvidence)
            }

            // Every one of the twenty-five was a real outage, and every report says so.
            #expect(verdict.macWasOffOrAsleep)
        }

        #expect(attributed == 10, "\(attributed) of 25 boots were called updates rather than 10")
    }

    /// ⚠️ **XProtect shares the installer process with macOS and is not macOS.** Twenty-five data
    /// updates in the same record, and none of them is ever reported to somebody as a system update.
    @Test("A data update is never reported as a macOS update")
    func configurationDataIsNotTheOperatingSystem() {
        let history = Self.machineHistory()
        let whole = Window(after: Date(timeIntervalSince1970: 1_700_000_000),
                           before: Date(timeIntervalSince1970: 1_900_000_000))
        let updates = Attribution.macOSUpdates(in: whole, installs: history.installs)
        #expect(updates.count == 10, "\(updates.count) of the 35 install records were called macOS")
        #expect(updates.allSatisfy { $0.name.hasPrefix("macOS ") })
    }

    /// ⚠️ **A restart with the whole install record readable and empty is not an update, and it is
    /// not "we could not tell" either.** It is a Mac that went off and came back, which is what a
    /// person did on purpose, and the section says exactly that much.
    @Test("A restart with an empty install record says only that the Mac was off")
    func anEmptyRecordIsStillAnAnswer() {
        let history = Self.machineHistory()
        let session = history.sessions[0]
        let window = Window(after: session.stoppedAt!.addingTimeInterval(-60),
                            before: session.startedAt.addingTimeInterval(60))
        let verdict = Attribution.verdict(for: window, record: [], boots: [session])

        #expect(verdict.cause == .unknown)
        #expect(verdict.macWasOffOrAsleep)
        #expect(verdict.outageUnreadable == nil)
    }
}

// MARK: - ⛔ The install record's dates are UTC

/// ⭐ **macOS 26.6.2 is stored as `2026-08-25T02:08:52Z` and it happened on the evening of the
/// 24th.**
///
/// `ChangesEngineTests.the2662UpdateLandsOnThe24th` pins the day. This pins the **hour**, which is
/// the half that says the conversion was actually done rather than accidentally right: an update at
/// two in the morning UTC is an update at eight in the evening in Denver, and a section that
/// reported "2 AM on the 25th" would be wrong about the day *and* about the part of the day, in a
/// sentence a person is meant to recognise as something they remember doing.
///
/// The plist hands back a correct instant. The trap is every later step that turns that instant
/// into a day, and a UTC calendar anywhere in that chain is invisible on a Mac set to UTC — which
/// is why the time zone here is named rather than inherited.
@Suite("The install record is read as an instant and told in the Mac's own time zone")
struct ChangesInstallRecordTimeZoneTests {

    private static let denver = TimeZone(identifier: "America/Denver")!

    private static func calendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    @Test("An update recorded at 02:14 UTC is the evening of the day before, in Mountain time")
    func anEarlyMorningUTCUpdateIsTheEveningBefore() throws {
        let ground = try QuarantineSandbox()
        defer { ground.tearDown() }

        let recorded = try #require(ISO8601DateFormatter().date(from: "2026-08-25T02:14:00Z"))
        let entries: [[String: Any]] = [
            ["displayName": "macOS 26.6.2", "displayVersion": "26.6.2",
             "date": recorded, "processName": "softwareupdated"],
        ]
        let file = ground.home.appending(path: "InstallHistory.plist")
        try PropertyListSerialization.data(fromPropertyList: entries, format: .xml, options: 0)
            .write(to: file)

        let installs = try #require(Attribution.installs(at: file))
        let update = try #require(installs.filter(\.isMacOS).first)

        let mountain = Self.calendar(Self.denver)
        #expect(mountain.component(.day, from: update.installedAt) == 24,
                "the update landed a day out — the record was read as though it were local time")
        #expect(mountain.component(.hour, from: update.installedAt) == 20,
                "the update landed at the wrong time of day")

        // And the same instant really is the 25th in UTC, so the test is measuring a conversion
        // rather than a date that was never ambiguous.
        #expect(Self.calendar(TimeZone(identifier: "UTC")!)
                    .component(.day, from: update.installedAt) == 25)
    }

    /// ⚠️ **The sentence a person reads is built in their own time zone too.** A correct instant
    /// formatted through a UTC calendar is the same bug one step later, and it is the step nobody
    /// looks at because the value in the debugger is right.
    @Test("The window's own sentence lands on the 24th as well")
    func theSentenceAgreesWithTheCalendar() throws {
        let recorded = try #require(ISO8601DateFormatter().date(from: "2026-08-25T02:14:00Z"))
        let window = Window(after: recorded.addingTimeInterval(-3_600),
                            before: recorded.addingTimeInterval(3_600))
        let said = window.sentence(now: recorded.addingTimeInterval(7 * 86_400),
                                   calendar: Self.calendar(Self.denver))
        #expect(said.contains("24"), "the window's sentence reports the update a day late: \(said)")
        #expect(!said.contains("25"))
    }

    /// A whole record, in order, with the operating system picked out of thirty-five entries — the
    /// shape `Attribution.installs` actually meets. Sorted oldest first, whatever order the file is
    /// in, because the newest macOS entry inside a window is the one a change is attributed to.
    @Test("The record comes back oldest first, whatever order it was written in")
    func theRecordIsSortedRegardlessOfTheFile() throws {
        let ground = try QuarantineSandbox()
        defer { ground.tearDown() }

        let base = try #require(ISO8601DateFormatter().date(from: "2026-08-25T02:14:00Z"))
        let entries: [[String: Any]] = [
            ["displayName": "macOS 26.6.2", "displayVersion": "26.6.2",
             "date": base, "processName": "softwareupdated"],
            ["displayName": "macOS 26.6.1", "displayVersion": "26.6.1",
             "date": base.addingTimeInterval(-86_400 * 30), "processName": "softwareupdated"],
            ["displayName": "Pages", "displayVersion": "14.2",
             "date": base.addingTimeInterval(-3_600), "processName": "appstoreagent"],
        ]
        let file = ground.home.appending(path: "InstallHistory.plist")
        try PropertyListSerialization.data(fromPropertyList: entries, format: .xml, options: 0)
            .write(to: file)

        let installs = try #require(Attribution.installs(at: file))
        #expect(installs.map(\.name) == ["macOS 26.6.1", "Pages", "macOS 26.6.2"])

        let window = Window(after: base.addingTimeInterval(-86_400), before: base.addingTimeInterval(60))
        let updates = Attribution.macOSUpdates(in: window, installs: installs)
        #expect(updates.map(\.version) == ["26.6.2"],
                "an app install or an out-of-window update was reported as the macOS in this window")
    }
}

// MARK: - A Mac that was off, end to end

/// The caveat has to survive the whole pipeline, not just the sentence that formats it. It is set by
/// `Attribution`, carried by `Window`, and printed by `ChangesReport` — three files, and a person
/// only ever sees the last one.
@Suite("A Mac that was off between snapshots says so in the report it produces")
struct ChangesMacWasOffEndToEndTests {

    @Test("The verdict's finding reaches the summary and the row")
    func theCaveatSurvivesThePipeline() {
        let earlier = Snapshot(takenAt: Date(timeIntervalSince1970: 1_000), machine: "Mac15,3",
                               watched: [WatchedKey(.protections, "firewall").storageKey: "On"])
        let later = Snapshot(takenAt: Date(timeIntervalSince1970: 500_000), machine: "Mac15,3",
                             watched: [WatchedKey(.protections, "firewall").storageKey: "Off"])

        let verdict = Attribution.Verdict(cause: .unknown, confidence: .noEvidence,
                                          macWasOffOrAsleep: true, outageUnreadable: nil)
        let report = Diff.report(earlier: earlier, latest: later,
                                 now: Date(timeIntervalSince1970: 500_000), verdict: verdict)

        #expect(report.macWasOffOrAsleep)
        #expect(report.summary.contains("asleep or switched off for part of that time"))
        #expect(report.changes.first?.window.macWasOffOrAsleep == true)
        #expect(report.ordered.first?.sentence(now: Date(timeIntervalSince1970: 500_000))
                    .contains("asleep or switched off for part of it") == true)
    }

    /// ⚠️ And a quiet week over a period the Mac spent switched off still says so — which is the
    /// case that matters, because "nothing changed" is the sentence a person acts on.
    @Test("A report with no changes at all still says the Mac was off")
    func aQuietReportStillCarriesIt() {
        let values = [WatchedKey(.protections, "firewall").storageKey: "On"]
        let earlier = Snapshot(takenAt: Date(timeIntervalSince1970: 1_000), machine: "Mac15,3",
                               watched: values)
        let later = Snapshot(takenAt: Date(timeIntervalSince1970: 500_000), machine: "Mac15,3",
                             watched: values)
        let report = Diff.report(earlier: earlier, latest: later,
                                 now: Date(timeIntervalSince1970: 500_000),
                                 verdict: Attribution.Verdict(cause: .unknown,
                                                              confidence: .noEvidence,
                                                              macWasOffOrAsleep: true,
                                                              outageUnreadable: nil))
        #expect(report.changes.isEmpty)
        #expect(report.summary.contains("Nothing Wellkept watches has changed"))
        #expect(report.summary.contains("asleep or switched off"))
    }
}

// MARK: - ⭐ The uninstaller asks rather than assumes

/// ⭐ **Decided 2026-08-28: "On uninstall, ask."** Three buttons — leave them where they are, save
/// them to a folder you pick, delete them.
///
/// `SnapshotStore` has held the words and the three outcomes since it was written, and every one of
/// them was tested. **None of that is worth anything until something calls them**, which is the
/// state this section was in when these tests were written: the question existed and nothing asked
/// it. So this suite checks the wiring as well as the words.
@Suite("The uninstaller asks about the settings record")
@MainActor
struct ChangesFarewellTests {

    /// The uninstaller's own source, for the one thing no unit test can reach: whether `run()`
    /// actually puts the question on screen. Every alternative — a protocol, an injected asker —
    /// would be machinery invented to make a five-line branch testable, and it would still not prove
    /// the branch was reached.
    private static func uninstallerSource() -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tools/AppTests
            .deletingLastPathComponent()   // Tools
            .deletingLastPathComponent()   // the repository
        let file = root.appendingPathComponent("App/Uninstaller.swift")
        return (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    }

    @Test("The record is in the uninstall manifest, and it is a question rather than a deletion")
    func theRecordIsInTheManifestAsAQuestion() throws {
        let ground = try QuarantineSandbox()
        defer { ground.tearDown() }

        SnapshotStore.record(Snapshot(takenAt: Date(), machine: "Mac15,3",
                                      watched: ["protections.fileVault": "On"]),
                             home: ground.home)

        let entries = StorageManifest.entries(home: ground.home,
                                              defaults: QuarantineSandbox.defaults("farewell"))
        let record = try #require(entries.first { $0.url == StorageManifest.snapshotStore(home: ground.home) },
                                  "the settings record is not in the uninstall manifest at all")

        #expect(record.disposition == .ask,
                "the record of somebody's own Mac would be deleted without being asked about")
        #expect(record.bytes > 0)

        // And `delete` refuses it even when handed the whole list, which is the belt to the braces.
        let survived = StorageManifest.delete(entries)
        #expect(!survived.contains(record))
        #expect(FileManager.default.fileExists(atPath: record.url.path),
                "the settings record was deleted by the sweep that is only meant to take our own bookkeeping")
    }

    /// ⭐ **The three buttons, and there is no fourth.** Cancel is not one of them: backing out of
    /// the question backs out of the uninstall, which is not a fate for the record.
    @Test("There are exactly three buttons, in the order that keeps the record by default")
    func thereAreThreeButtons() {
        #expect(Uninstaller.recordButtons == ["Leave Them", "Save Them…", "Delete Them"])
        #expect(!Uninstaller.recordButtons.contains("Cancel"))
    }

    /// ⚠️ **The wiring.** `farewellQuestion` and `carryOut` existed and were tested before anything
    /// called them, which is exactly as much use to somebody uninstalling the app as not writing
    /// them at all.
    @Test("run() actually asks the question")
    func theUninstallerReachesTheQuestion() {
        let source = Self.uninstallerSource()
        #expect(source.contains("askAboutSettingsRecord()"),
                "the uninstaller does not ask about the settings record")
        #expect(source.contains("SnapshotStore.farewellQuestion()"),
                "the question is asked in words that are not the tested ones")
        #expect(source.contains("SnapshotStore.carryOut("),
                "the answer is collected and then not acted on")
        #expect(source.contains("SnapshotStore.isEmpty()"),
                "the question is asked even when there is no record to ask about")
    }

    /// Each of the three does what it says, and none of them touches the quarantine — which sits in
    /// the same folder and holds the user's own files.
    @Test("Leave leaves it, save writes both halves, delete takes the one file")
    func eachOutcomeDoesWhatItSays() throws {
        for outcome in ["leave", "save", "delete"] {
            let ground = try QuarantineSandbox()
            defer { ground.tearDown() }

            SnapshotStore.record(Snapshot(takenAt: Date(timeIntervalSince1970: 1_000),
                                          systemVersion: "26.6.2", machine: "Mac15,3",
                                          watched: ["protections.fileVault": "On"]),
                                 home: ground.home)
            // A file in the quarantine, which shares the folder and is not ours to decide about.
            let quarantined = try ground.file("Library/Application Support/Wellkept/Quarantine/kept.txt")
            let file = SnapshotStore.url(home: ground.home)

            let written: [URL]
            switch outcome {
            case "leave":
                written = try SnapshotStore.carryOut(.leave, home: ground.home)
                #expect(written.isEmpty)
                #expect(ground.exists(file), "\"leave them\" deleted them")
            case "save":
                let folder = try ground.folder("Desktop/Saved")
                written = try SnapshotStore.carryOut(.save(to: folder), home: ground.home)
                #expect(written.count == 2, "saving did not write both a summary and the raw file")
                #expect(written.contains { $0.pathExtension == "txt" })
                #expect(written.contains { $0.pathExtension == "jsonl" })
                let summary = try #require(written.first { $0.pathExtension == "txt" })
                let text = try String(contentsOf: summary, encoding: .utf8)
                #expect(text.contains("FileVault: On"), "the readable half is not readable")
                #expect(text.contains("Safari"), "the summary does not say what it cannot cover")
            default:
                written = try SnapshotStore.carryOut(.delete, home: ground.home)
                #expect(written.isEmpty)
                #expect(!ground.exists(file), "\"delete them\" left them")
            }

            #expect(ground.exists(quarantined),
                    "answering about the settings record touched the quarantine, which holds somebody's own files")
        }
    }

    /// The closing dialog says what happened, including when the answer was "leave them" — silence
    /// there would read as "it went with the app", which is the opposite of the truth.
    @Test("Every outcome gets a sentence, including the quiet one")
    func everyOutcomeIsSaidOutLoud() {
        let folder = URL(filePath: "/Users/example/Desktop/Saved")
        let saved = [folder.appending(path: "Wellkept settings record.txt"),
                     folder.appending(path: "Wellkept snapshots.jsonl")]

        let leave = Uninstaller.recordOutcome(.leave, written: [])
        #expect(leave.contains("still in"))
        #expect(leave.contains("picks up where this left off"))

        let save = Uninstaller.recordOutcome(.save(to: folder), written: saved)
        #expect(save.contains("Wellkept settings record.txt"))
        #expect(save.contains("Wellkept snapshots.jsonl"))

        #expect(Uninstaller.recordOutcome(.delete, written: []) == "Your settings record has been deleted.")

        // A save that wrote nothing says so rather than claiming a folder full of files.
        let failed = Uninstaller.recordOutcome(.save(to: folder), written: [])
        #expect(failed.contains("could not write"))
    }

    /// The question itself: it says how much there is and how far back it goes, because "some
    /// records" is not enough to decide on.
    @Test("The question says how much there is")
    func theQuestionSaysHowMuch() throws {
        let ground = try QuarantineSandbox()
        defer { ground.tearDown() }

        for day in 0..<3 {
            SnapshotStore.record(Snapshot(takenAt: Date(timeIntervalSince1970: 1_780_000_000
                                                        + Double(day) * 86_400),
                                          machine: "Mac15,3"),
                                 home: ground.home)
        }
        let words = SnapshotStore.farewellQuestion(home: ground.home)
        #expect(words.title == "What should happen to your settings record?")
        #expect(words.body.contains("3 records"))
        #expect(words.body.contains("going back to"))
        #expect(words.body.contains("yours to decide about"))
    }
}

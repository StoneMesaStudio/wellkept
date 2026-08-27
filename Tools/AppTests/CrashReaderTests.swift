// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import WellkeptCore

//  CrashReaderTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **The one number this row must never print is 105.**
//
//  Every test below is about the same failure: a crash folder with a hundred files in it, on a Mac
//  where nothing has crashed. The headers are real, typed out from
//  `~/Library/Logs/DiagnosticReports` on 2026-08-27, so the suite gives the same answer on a build
//  machine as it does on the Mac they came from.
//
//  Nothing here reads this Mac.

// MARK: - Real headers, typed out

private enum Header {

    /// Safari, filing a report about itself while staying open. Four of these here.
    static let safariSelfFiled = """
        {"is_simulated":1,"app_name":"Safari","timestamp":"2026-08-20 09:58:08.00 -0600",\
        "app_version":"26.6","platform":1,"bundleID":"com.apple.Safari","bug_type":"309",\
        "os_version":"macOS 26.6.1 (25G76)","incident_id":"90FB1361","name":"Safari"}
        """

    /// The iPhone simulator's own window server. Platform 7, no identifier at all.
    static let backboardd = """
        {"app_name":"backboardd","timestamp":"2026-08-20 16:13:30.00 -0600","platform":7,\
        "bug_type":"309","os_version":"macOS 26.6.1 (25G76)","name":"backboardd"}
        """

    /// The simulator's rendering service. Platform 1 — it really is Mac software — but nobody
    /// opened it.
    static let simRenderServer = """
        {"app_name":"SimRenderServer","timestamp":"2026-08-20 19:03:53.00 -0600","platform":1,\
        "bundleID":"com.apple.CoreSimulator.SimRenderingServices.SimRenderServer",\
        "bug_type":"309","os_version":"macOS 26.6.1 (25G76)","name":"SimRenderServer"}
        """

    /// A compiler process. No identifier, so no app.
    static let swiftFrontend = """
        {"app_name":"swift-frontend","timestamp":"2026-08-27 13:53:52.00 -0600","platform":1,\
        "bug_type":"309","os_version":"macOS 26.6.2 (25G83)","name":"swift-frontend"}
        """

    /// Apple's own security telemetry. Not a crash report at all.
    static let appleTelemetry = """
        {"timestamp":"2026-08-20 12:26:24.89 -0600","bug_type":"226",\
        "os_version":"macOS 26.6.1 (25G76)"}
        """

    /// macOS stopping an app for using too much memory. **Hardware's row, not ours.**
    static let jetsam = """
        {"bug_type":"298","timestamp":"2026-08-26 06:09:19.00 -0600",\
        "os_version":"macOS 26.6.2 (25G83)","incident_id":"FAD89BEA"}
        """

    /// A build product crashing. A real macOS crash of a real app — but not one this section lists.
    static let buildProduct = """
        {"app_name":"Waypoint","timestamp":"2026-08-23 11:46:52.00 -0600","platform":1,\
        "bundleID":"studio.stonemesa.waypoint","bug_type":"309",\
        "os_version":"macOS 26.6.1 (25G76)","name":"Waypoint"}
        """

    /// An app in the list above, actually crashing. This Mac has none; a person's Mac might.
    static let realCrash = """
        {"app_name":"LibreOffice","timestamp":"2026-08-24 08:11:02.00 -0600","platform":1,\
        "bundleID":"org.libreoffice.script","bug_type":"309",\
        "os_version":"macOS 26.6.2 (25G83)","name":"LibreOffice"}
        """
}

private let epoch = Date(timeIntervalSince1970: 1_756_000_000)

private func parse(_ header: String, _ file: String) -> CrashReader.Report {
    let report = CrashReader.report(fromHeader: header, fileName: file, fallbackDate: epoch)
    #expect(report != nil, "the header should parse: \(file)")
    return report ?? CrashReader.Report(fileName: file, at: epoch)
}

// MARK: - Parsing one header

@Suite struct CrashHeaderTests {

    @Test func theFirstLineCarriesEverythingTheFilterNeeds() {
        let report = parse(Header.safariSelfFiled, "ExcUserFault_Safari-2026-08-20-095808.ips")
        #expect(report.bundleID == "com.apple.Safari")
        #expect(report.appName == "Safari")
        #expect(report.bugType == "309")
        #expect(report.platform == 1)
        #expect(report.isSelfFiled)
    }

    /// The header's own timestamp is used, not the file's date — a report copied between Macs keeps
    /// the moment it describes.
    @Test func theTimestampIsRead() {
        let report = parse(Header.realCrash, "LibreOffice-2026-08-24-081102.ips")
        #expect(report.at != epoch)
        #expect(report.at.formatted(date: .numeric, time: .omitted).contains("2026"))
    }

    /// Apple has written `bug_type` as a number as well as a string. Both are the same fact.
    @Test func bugTypeIsAcceptedEitherWay() {
        #expect(CrashReader.bugType("309") == "309")
        #expect(CrashReader.bugType(309) == "309")
        #expect(CrashReader.bugType(nil) == nil)
    }

    /// ⚠️ A file we cannot parse is never assumed to be a crash. Silence is the safe direction here.
    @Test func rubbishIsNotACrash() {
        #expect(CrashReader.report(fromHeader: "not json at all",
                                   fileName: "x.ips",
                                   fallbackDate: epoch) == nil)
    }

    /// A header with no `bug_type` cannot claim to be a crash, because the filter's first rule
    /// requires the number to say so.
    @Test func aHeaderWithNoBugTypeIsSetAside() {
        let report = CrashReader.Report(fileName: "mystery.ips",
                                        bundleID: "com.example.thing",
                                        platform: 1,
                                        at: epoch)
        #expect(CrashReader.setAside(report, appsOnThisMac: ["com.example.thing"]) == .nothingCrashed)
    }
}

// MARK: - ⭐ 105 files, zero crashes

@Suite struct CrashFilterTests {

    static let installed: Set<String> = ["com.apple.Safari", "org.libreoffice.script",
                                        "com.google.Chrome"]

    @Test func safariFilingAboutItselfIsNotACrash() {
        let report = parse(Header.safariSelfFiled, "ExcUserFault_Safari-2026-08-20-095808.ips")
        #expect(CrashReader.setAside(report, appsOnThisMac: Self.installed) == .filedWhileStillRunning)
    }

    /// The filename alone is enough, in case a future macOS drops the `is_simulated` flag.
    @Test func theFilenamePrefixAloneIsEnough() {
        let report = CrashReader.Report(fileName: "ExcUserFault_Safari-2026-01-01.ips",
                                        bundleID: "com.apple.Safari",
                                        bugType: "309",
                                        platform: 1,
                                        isSelfFiled: false,
                                        at: epoch)
        #expect(CrashReader.setAside(report, appsOnThisMac: Self.installed) == .filedWhileStillRunning)
    }

    @Test func iOSProcessesAreNotThisMacsSoftware() {
        let report = parse(Header.backboardd, "backboardd-2026-08-20-161330.ips")
        #expect(CrashReader.setAside(report, appsOnThisMac: Self.installed) == .builtForAnotherDevice)
    }

    @Test func theSimulatorsOwnMachineryIsNamedAsSuch() {
        let report = parse(Header.simRenderServer, "SimRenderServer-2026-08-20-190353.ips")
        #expect(CrashReader.setAside(report, appsOnThisMac: Self.installed) == .theSimulatorItself)
    }

    @Test func aToolWithNoIdentifierIsNotAnApp() {
        let report = parse(Header.swiftFrontend, "swift-frontend-2026-08-27-135352.ips")
        #expect(CrashReader.setAside(report, appsOnThisMac: Self.installed) == .notAnApp)
    }

    @Test func applesTelemetryIsNotACrash() {
        let report = parse(Header.appleTelemetry, "SFA-ckks.json_2026-08-20-122624.diag")
        #expect(CrashReader.setAside(report, appsOnThisMac: Self.installed) == .nothingCrashed)
    }

    /// ⚠️ **The rule the brief names: do not double-report what Hardware's memory row covers.**
    /// It gets its own reason so a later tidy-up cannot fold it into the general bucket.
    @Test func runningOutOfMemoryIsHardwaresRowAndIsNamedSeparately() {
        let report = parse(Header.jetsam, "JetsamEvent-2026-08-26-060919.ips")
        let why = CrashReader.setAside(report, appsOnThisMac: Self.installed)
        #expect(why == .stoppedForMemory)
        #expect(why != .nothingCrashed)
        #expect(CrashReader.SetAside.stoppedForMemory.explanation.contains("Hardware"))
    }

    @Test func aBuildProductIsNotAnAppThisSectionLists() {
        let report = parse(Header.buildProduct, "Waypoint-2026-08-23-114652.ips")
        #expect(CrashReader.setAside(report, appsOnThisMac: Self.installed) == .notAnAppOnThisMac)
    }

    /// The one that must survive every filter.
    @Test func anAppInTheListActuallyCrashingSurvives() {
        let report = parse(Header.realCrash, "LibreOffice-2026-08-24-081102.ips")
        #expect(CrashReader.setAside(report, appsOnThisMac: Self.installed) == nil)
    }

    /// ⭐ The measurement, end to end: eight kinds of file, one real crash between them, and the
    /// only one that survives is the crash.
    @Test func theWholeFolderReducesToWhatActuallyCrashed() {
        let reports = [
            parse(Header.safariSelfFiled, "ExcUserFault_Safari-1.ips"),
            parse(Header.safariSelfFiled, "ExcUserFault_Safari-2.ips"),
            parse(Header.backboardd, "backboardd-1.ips"),
            parse(Header.simRenderServer, "SimRenderServer-1.ips"),
            parse(Header.swiftFrontend, "swift-frontend-1.ips"),
            parse(Header.appleTelemetry, "SFA-1.diag"),
            parse(Header.jetsam, "JetsamEvent-1.ips"),
            parse(Header.buildProduct, "Waypoint-1.ips"),
        ]
        let survivors = reports.filter {
            CrashReader.setAside($0, appsOnThisMac: Self.installed) == nil
        }
        #expect(survivors.isEmpty)
    }
}

// MARK: - The row on a Mac where nothing crashed

@Suite struct CrashRowTests {

    static let installed: Set<String> = ["com.apple.Safari", "org.libreoffice.script"]

    /// Eight days back, which is what this Mac reported.
    static let now = Date(timeIntervalSince1970: 1_756_000_000)
    static let eightDaysAgo = now.addingTimeInterval(-8 * 86_400)

    static func quietMac() -> CrashReader.Survey {
        CrashReader.Survey(reports: [
            parse(Header.safariSelfFiled, "ExcUserFault_Safari-1.ips"),
            parse(Header.backboardd, "backboardd-1.ips"),
            parse(Header.jetsam, "JetsamEvent-1.ips"),
            parse(Header.buildProduct, "Waypoint-1.ips"),
        ], nonCrashFiles: 71, earliestRecord: eightDaysAgo)
    }

    /// ⭐ **The headline on a Mac with 75 crash-folder files and nothing wrong.**
    @Test func aQuietMacIsToldNothingStopped() {
        let answer = CrashReader.answer(from: Self.quietMac(),
                                        appsOnThisMac: Self.installed,
                                        now: Self.now)
        #expect(answer.crashes.isEmpty)
        #expect(answer.row.headline == "No app on this Mac has stopped working in the last 8 days.")
        #expect(answer.windowDays == 8)
    }

    /// ⚠️ **The figure beside the sentence is the window, never the file count.** 75 in large type
    /// beside "nothing stopped working" is the number a person remembers.
    @Test func theMeasureIsTheWindowAndNeverACountOfFiles() {
        let answer = CrashReader.answer(from: Self.quietMac(),
                                        appsOnThisMac: Self.installed,
                                        now: Self.now)
        #expect(answer.row.measure == "8 days")
        #expect(answer.row.measure?.contains("75") != true)
        #expect(answer.row.measure?.contains("report") != true)
    }

    /// The 75 still gets said — in the reason, where it is explained rather than displayed.
    @Test func theFileCountIsExplainedNotDisplayed() {
        let answer = CrashReader.answer(from: Self.quietMac(),
                                        appsOnThisMac: Self.installed,
                                        now: Self.now)
        let reason = answer.row.reason ?? ""
        #expect(reason.contains("75 reports"))
        #expect(reason.contains("None of them is an app on this Mac stopping."))
    }

    /// ⚠️ Every set-aside report is named and counted behind Options. A filter nobody can audit is
    /// a fudge.
    @Test func everyThingSetAsideIsCountedWhereSomebodyCanCheckIt() {
        let answer = CrashReader.answer(from: Self.quietMac(),
                                        appsOnThisMac: Self.installed,
                                        now: Self.now)
        let labels = answer.row.details.map(\.label)
        #expect(labels.contains(CrashReader.SetAside.filedWhileStillRunning.label))
        #expect(labels.contains(CrashReader.SetAside.stoppedForMemory.label))
        #expect(labels.contains(CrashReader.SetAside.notAnAppOnThisMac.label))

        // 71 notices + 1 self-filed + 1 iOS + 1 memory + 1 not-ours = 75, and the row says 75.
        let seen = answer.row.details.first { $0.label == "Reports macOS filed" }
        #expect(seen?.value == "75")
    }

    /// The window is stated in the reason as well, because the row is only true inside it.
    @Test func theWindowIsAlwaysStated() {
        let answer = CrashReader.answer(from: Self.quietMac(),
                                        appsOnThisMac: Self.installed,
                                        now: Self.now)
        #expect(answer.row.reason?.contains("How far back that goes depends on how much this Mac "
                                          + "has had to say") == true)
    }

    /// ⚠️ Apps is `.information` and nothing here may reach past it, whatever crashed.
    @Test func aCrashIsStillOnlyInformation() {
        let survey = CrashReader.Survey(reports: [
            parse(Header.realCrash, "LibreOffice-1.ips"),
            parse(Header.realCrash, "LibreOffice-2.ips"),
        ], nonCrashFiles: 0, earliestRecord: Self.eightDaysAgo)

        let answer = CrashReader.answer(from: survey,
                                        appsOnThisMac: Self.installed,
                                        now: Self.now)
        #expect(answer.crashes.count == 1)
        #expect(answer.crashes[0].crashes == 2)
        #expect(answer.row.headline == "LibreOffice stopped working in the last 8 days.")
        #expect(answer.row.severity == .information)
        #expect(answer.row.status == .good)
    }

    /// Two apps, two names, one sentence.
    @Test func twoAppsAreCountedNotListedInTheHeadline() {
        var second = parse(Header.realCrash, "Other-1.ips")
        second = CrashReader.Report(fileName: second.fileName,
                                    bundleID: "com.apple.Safari",
                                    appName: "Safari",
                                    bugType: "309",
                                    platform: 1,
                                    at: second.at)
        let survey = CrashReader.Survey(reports: [parse(Header.realCrash, "LibreOffice-1.ips"), second],
                                        earliestRecord: Self.eightDaysAgo)
        let answer = CrashReader.answer(from: survey,
                                        appsOnThisMac: Self.installed,
                                        now: Self.now)
        #expect(answer.crashes.count == 2)
        #expect(answer.row.headline == "2 apps stopped working in the last 8 days.")
    }

    /// ⚠️ **Never report zero because we could not look.** An empty folder is a different sentence
    /// from a quiet Mac, and neither of them is "nothing has ever crashed".
    @Test func anEmptyFolderIsNotACleanBillOfHealth() {
        let survey = CrashReader.Survey(reports: [], nonCrashFiles: 0, earliestRecord: nil)
        let answer = CrashReader.answer(from: survey,
                                        appsOnThisMac: Self.installed,
                                        now: Self.now)
        #expect(answer.row.headline == "macOS has not filed any crash report on this Mac.")
        #expect(answer.row.measure == nil)
        #expect(answer.windowDays == nil)
        #expect(answer.row.reason?.contains("nothing is recorded rather than that anything is wrong")
                == true)
    }

    /// ⚠️ A refusal of the shared folder is `.notGrantable`: no button, and the check stays
    /// complete, because no permission this app could ask for would have shown it more.
    @Test func aSharedFolderRefusalCarriesNoButtonAndNoCaveat() {
        let survey = CrashReader.Survey(reports: nil, readSharedFolder: false, readOwnFolder: true)
        let answer = CrashReader.answer(from: survey,
                                        appsOnThisMac: Self.installed,
                                        now: Self.now)
        #expect(answer.row.unreadable == .notGrantable)
        #expect(answer.row.remedy == nil)
        #expect(answer.row.complete)
        #expect(answer.row.measure == nil)
        #expect(answer.row.status == .notChecked)
    }

    /// The other way round: only a privacy setting can keep somebody out of their own Logs folder,
    /// so that one does carry a button. It did not fire on the measured Mac.
    @Test func beingRefusedYourOwnFolderIsSomethingYouCanLift() {
        let survey = CrashReader.Survey(reports: nil, readSharedFolder: true, readOwnFolder: false)
        let answer = CrashReader.answer(from: survey,
                                        appsOnThisMac: Self.installed,
                                        now: Self.now)
        #expect(answer.row.unreadable == .notPermitted)
        #expect(answer.row.remedy?.settingsPane == "fullDiskAccess")
        #expect(!answer.row.complete)
    }

    /// A Mac whose folder was pruned to nothing readable still gets an honest window sentence.
    @Test func anUnmeasurableWindowIsSaidOutLoud() {
        #expect(CrashReader.measuredDays(earliestRecord: nil, now: Self.now) == nil)
        #expect(CrashReader.measure(nil) == nil)
        #expect(CrashReader.windowSentence(nil).contains("does not say how far back"))
    }

    /// Under a day still reads as a day, never as zero.
    @Test func lessThanADayIsADayNotNothing() {
        let recent = Self.now.addingTimeInterval(-3_600)
        #expect(CrashReader.measuredDays(earliestRecord: recent, now: Self.now) == 1)
        #expect(CrashReader.measure(1) == "1 day")
    }

    /// The window sentence is Security's, borrowed, so the two sections cannot disagree about how
    /// far back "nothing" reaches on the same afternoon.
    @Test func theWindowWordingIsTheHouseWording() {
        #expect(CrashReader.windowClause(8) == "in the last 8 days")
        #expect(CrashReader.windowClause(1) == "in the last day")
        #expect(CrashReader.windowClause(nil)
                == SecurityReport(block: .unknown, rows: [], measuredDays: nil).windowClause)
    }
}

// MARK: - Reading this Mac, live

@Suite struct CrashReaderLiveTests {

    /// It runs here, against whatever this Mac happens to hold, and produces a row.
    ///
    /// Deliberately not asserting a count: the folder changes hourly. What is asserted is the shape
    /// — a row of the right topic that never exceeds the section's severity ceiling.
    @Test func itReadsThisMacWithoutFallingOver() {
        let answer = CrashReader.read(appsOnThisMac: ["com.apple.Safari"])
        #expect(answer.row.topic == .stoppedWorking)
        #expect(answer.row.severity == AppsRow.severityCeiling)
        #expect(!answer.row.headline.isEmpty)
    }

    /// ⚠️ The section's claim that Apps needs no Full Disk Access rests on this passing on an
    /// ordinary account.
    @Test func theCrashFolderReadsWithoutFullDiskAccess() {
        let survey = CrashReader.survey()
        #expect(survey.reports != nil, "the person's own crash folder should be readable")
    }
}

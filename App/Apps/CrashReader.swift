// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import WellkeptCore

//  CrashReader.swift
//  Wellkept — App/Apps
//
//  **Apps that stopped working — and the four fifths of the evidence that is not a crash.**
//
//  This row moved here from Hardware on 2026-08-27. It belongs in Apps because the question is
//  about an app, not about the machine: a Mac whose drive and battery are perfect can still have
//  one app that falls over every morning, and that is not a hardware reading.
//
//  ## ⚠️ The measurement this whole file exists for
//
//  **105 crash-report files on this Mac reduce to ZERO real app crashes.** Measured 2026-08-27,
//  read-only, across `~/Library/Logs/DiagnosticReports` and `/Library/Logs/DiagnosticReports`:
//
//  | What is actually in the folder | Files | Is it an app crashing? |
//  |---|---|---|
//  | Performance notices — CPU, wakeups, disk writes, a slow shutdown | 71 | **No.** Nothing crashed. |
//  | Apple's own security telemetry (`SFA-*.json`) | included above | **No.** Apple's bookkeeping. |
//  | iPhone-simulator internals — `backboardd`, `SimRenderServer`, iOS builds | 13 | **No.** Not this Mac's software. |
//  | Command-line tools and daemons with no app behind them | 11 | **No.** Nobody launched an app. |
//  | Reports an app filed **about itself while it kept running** | 4 | **No.** Safari is still open. |
//  | Apps stopped for using too much memory (`JetsamEvent`) | 3 | **No** — and Hardware already says so. |
//  | An app on this Mac actually crashing | **0** | — |
//
//  A row built from the file count would have told somebody with a perfectly healthy Mac that a
//  hundred things had crashed. That number is the product this app exists not to be.
//
//  ## ⚠️ Never double-report the memory row
//
//  `JetsamEvent` reports are macOS stopping an app that asked for more memory than it was allowed.
//  Hardware's memory reading already covers that, in the section where the answer ("this Mac is
//  short of memory") actually lives. Counting them here as well would make one event appear twice,
//  under two different explanations, and the second one would be wrong. They get their own
//  set-aside reason rather than being swept in with everything else, so the intent survives
//  somebody tidying this file up later.
//
//  ## ⚠️ The window is measured, never assumed
//
//  macOS prunes this folder, and **how far back it reaches is decided by how chatty this Mac has
//  been, not by any policy.** On this Mac it reached back about 8 days. On a quiet Mac it goes
//  further; on a busy one, less; and the same Mac gives a different answer next week. There is no
//  setting for it and Apple publishes no number.
//
//  So "no app has ever crashed" and "an app crashed a month ago" look **identical** from here. The
//  only honest sentence says how far back we could see, in the same breath — which is why the
//  window is in the headline, in the measure, and in the reason, and why `windowClause` is borrowed
//  from `SecurityReport` rather than written again here.
//
//  ## What it costs to run
//
//  Two directory listings and a first-line read of the `.ips` files only — about 30 of them here.
//  Everything else is classified on its file extension without being opened. Measured well under a
//  tenth of a second, which is nothing beside the 7–8 seconds the app inventory costs.
//
//  ## Nothing here needs Full Disk Access
//
//  Measured 2026-08-27: both folders read from an ordinary account. `/Library/Logs/DiagnosticReports`
//  is readable by the `admin` group, so a standard account is refused there — that is
//  `Unreadable.notGrantable`, because the kind of account you sign in with is not a privacy setting
//  and no button in this app could ever change it. The row still says plainly that we did not see
//  it; what it does not do is hang a caveat on Overview that nobody can clear.

enum CrashReader {

    // MARK: - What one run produced

    /// The row, the apps that really did crash, and the window we were able to measure.
    ///
    /// The crash list travels beside the row rather than only inside it, because the section face
    /// draws the apps and the row draws the sentence, and neither should have to parse the other.
    struct Answer: Sendable, Hashable {
        let row: AppsRow
        /// The apps that actually crashed, most recent first. **Empty is the ordinary answer.**
        let crashes: [CrashedApp]
        /// How far back the folder reached, in days. **`nil` is a real answer** and is never
        /// replaced with a plausible-looking number.
        let windowDays: Int?
    }

    // MARK: - One report file, from its first line only

    /// The header of one `.ips` file — the single JSON line macOS writes before the body.
    ///
    /// ⚠️ **Only the header is read, and it is enough.** The body of a crash report is a large JSON
    /// object with stack traces, register dumps and a binary image list; the six fields below are
    /// all that decide whether the report is an app on this Mac crashing, and they are all in the
    /// first line. Parsing bodies would multiply the cost of this row by two orders of magnitude to
    /// learn nothing.
    struct Report: Sendable, Hashable, Identifiable {

        /// The file's own name. Kept because it is the only thing a person could go and look at,
        /// and because `ExcUserFault_` in the name is itself a fact — see `isSelfFiled`.
        let fileName: String

        /// The app's identifier, where the report names one. **`nil` is common and it matters**:
        /// a report with no identifier came from a command-line tool or a background daemon, and
        /// nobody launched an app.
        let bundleID: String?

        /// The name in the header, for the row to print. Never used to decide anything.
        let appName: String?

        /// Apple's report-kind number. `"309"` is a crash; `"298"` is an app stopped for memory;
        /// `"226"` is a performance notice. See the constants below.
        let bugType: String?

        /// `1` is macOS. Anything else is a build for another device — an iPhone or iPad app
        /// running under the simulator. `nil` where the header did not say, which is not evidence
        /// of anything.
        let platform: Int?

        /// **The app filed this about itself and carried on running.** macOS marks these
        /// `is_simulated` and names the file `ExcUserFault_…`; Safari filed four of them here while
        /// staying open the whole time. A report about a process that did not stop is not a crash.
        let isSelfFiled: Bool

        /// When it happened.
        let at: Date

        var id: String { fileName }

        init(fileName: String,
             bundleID: String? = nil,
             appName: String? = nil,
             bugType: String? = nil,
             platform: Int? = nil,
             isSelfFiled: Bool = false,
             at: Date) {
            self.fileName = fileName
            self.bundleID = bundleID
            self.appName = appName
            self.bugType = bugType
            self.platform = platform
            self.isSelfFiled = isSelfFiled
            self.at = at
        }
    }

    // MARK: - ⭐ Why a report is not an app crashing

    /// The seven reasons a file in the crash folder is not an app on this Mac crashing.
    ///
    /// ⚠️ **A closed list, and every set-aside report is counted under one of them.** The row prints
    /// the tally. That is the difference between a filter and a fudge: anybody can read what we
    /// threw away and disagree with the reason, and the numbers have to add up to the number of
    /// files in the folder.
    ///
    /// `allCases` is the order they are shown in, which is the order they are applied — see
    /// `setAside(_:appsOnThisMac:)`.
    enum SetAside: String, Sendable, Hashable, CaseIterable, Identifiable, Codable {

        /// A performance notice, a slow shutdown, Apple's own telemetry. **Nothing crashed.**
        /// 71 of the files on this Mac.
        case nothingCrashed

        /// macOS stopped the app for using more memory than it was allowed.
        ///
        /// ⚠️ Named separately from `nothingCrashed` on purpose: **Hardware's memory reading already
        /// reports this**, and folding it in here would report one event twice under two
        /// explanations. See the file header.
        case stoppedForMemory

        /// The app filed a report about itself and kept running. Safari, four times, here.
        case filedWhileStillRunning

        /// The iPhone simulator's own machinery — `SimRenderServer`, `SimLaunchHost`.
        case theSimulatorItself

        /// A build for another device running under the simulator: an iPhone or iPad app, or one of
        /// iOS's own processes. Not this Mac's software.
        case builtForAnotherDevice

        /// A command-line tool or a background process with no app behind it. Nobody launched it,
        /// and there is no app to tell anybody about.
        case notAnApp

        /// It names an app, but not one of the apps this section lists — a build in progress, or an
        /// app that has since been removed.
        ///
        /// ⚠️ This is the last rule, and it is why the count here is zero rather than two. Apps
        /// reports on the apps it lists; naming something the list above does not contain would be
        /// a row about software the reader cannot find.
        case notAnAppOnThisMac

        var id: String { rawValue }

        /// The words in the tally.
        var label: String {
            switch self {
            case .nothingCrashed:         "Nothing crashed"
            case .stoppedForMemory:       "Stopped for memory, not crashed"
            case .filedWhileStillRunning: "Filed by an app that kept running"
            case .theSimulatorItself:     "The iPhone simulator's own machinery"
            case .builtForAnotherDevice:  "Built for another device"
            case .notAnApp:               "Not an app"
            case .notAnAppOnThisMac:      "Not an app on this Mac"
            }
        }

        /// What it means, for behind **Options**. Explanation, not clutter: without it the tally is
        /// a list of numbers nobody can check.
        var explanation: String {
            switch self {
            case .nothingCrashed:
                "A notice about how much processor, power or disk something used, or a slow "
              + "shutdown, or Apple's own bookkeeping. macOS files these in the same folder as "
              + "crashes and they are not crashes."
            case .stoppedForMemory:
                "macOS stopped the app because it asked for more memory than it was allowed. "
              + "Hardware reports that, under memory, where the answer actually is."
            case .filedWhileStillRunning:
                "The app noticed something wrong, wrote it down, and carried on. It did not stop."
            case .theSimulatorItself:
                "Part of the iPhone simulator that Xcode installs, not an app you opened."
            case .builtForAnotherDevice:
                "A report from software built for an iPhone, iPad or Watch, running here under the "
              + "simulator."
            case .notAnApp:
                "A command-line tool or a background process. It has no app to belong to."
            case .notAnAppOnThisMac:
                "It names an app that is not in the list above — usually something being built, or "
              + "an app that has since been removed."
            }
        }
    }

    // MARK: - What one look at the folders produced

    struct Survey: Sendable, Hashable {

        /// Every file we managed to classify. **`nil` where neither folder could be opened at
        /// all** — which is not the same as a Mac with no crashes, and the row keeps those apart.
        let reports: [Report]?

        /// Files we saw but did not open, because their extension already answers the question — a
        /// `.diag` notice, a `.shutdownStall`. Counted, never parsed.
        let nonCrashFiles: Int

        /// The oldest file of any kind, which is how far back the folder reaches.
        ///
        /// ⚠️ Measured from **every** file, not only from the crash reports. A Mac whose last real
        /// crash was a month ago must not be reported as having a one-month window it never had.
        let earliestRecord: Date?

        /// Whether the shared `/Library` folder could be read. A standard account cannot, and the
        /// row says so without offering a button.
        let readSharedFolder: Bool

        /// Whether the person's own folder could be read.
        let readOwnFolder: Bool

        /// True when there were more files than we were willing to open in one press, and the row
        /// says so rather than implying it read everything.
        let trimmed: Bool

        init(reports: [Report]?,
             nonCrashFiles: Int = 0,
             earliestRecord: Date? = nil,
             readSharedFolder: Bool = true,
             readOwnFolder: Bool = true,
             trimmed: Bool = false) {
            self.reports = reports
            self.nonCrashFiles = nonCrashFiles
            self.earliestRecord = earliestRecord
            self.readSharedFolder = readSharedFolder
            self.readOwnFolder = readOwnFolder
            self.trimmed = trimmed
        }

        /// Everything macOS filed in the window, crash-shaped or not. The number a naive tool
        /// prints as crashes.
        var filesSeen: Int { (reports?.count ?? 0) + nonCrashFiles }
    }

    // MARK: - The row

    /// Read this Mac's crash folders and build the row.
    ///
    /// - Parameter appsOnThisMac: the bundle identifiers of the apps this section lists. A crash
    ///   from anything else is set aside as `.notAnAppOnThisMac` and counted, never hidden.
    static func read(appsOnThisMac: Set<String>, now: Date = Date()) -> Answer {
        answer(from: survey(), appsOnThisMac: appsOnThisMac, now: now)
    }

    /// The row, from a survey. **Pure**, so a Mac where an app really did crash — which this one is
    /// not — can be tested without waiting for one to happen.
    static func answer(from survey: Survey,
                       appsOnThisMac: Set<String>,
                       now: Date = Date()) -> Answer {
        let days = measuredDays(earliestRecord: survey.earliestRecord, now: now)

        guard let reports = survey.reports else {
            return Answer(row: refused(survey), crashes: [], windowDays: days)
        }

        var setAsideTally: [SetAside: Int] = [:]
        var real: [Report] = []
        for report in reports {
            if let why = setAside(report, appsOnThisMac: appsOnThisMac) {
                setAsideTally[why, default: 0] += 1
            } else {
                real.append(report)
            }
        }
        setAsideTally[.nothingCrashed, default: 0] += survey.nonCrashFiles

        let crashes = crashedApps(from: real)

        let row = AppsRow(
            topic: .stoppedWorking,
            headline: headline(crashes: crashes, filesSeen: survey.filesSeen, days: days),
            measure: measure(days),
            reason: reason(crashes: crashes,
                           survey: survey,
                           setAside: setAsideTally),
            details: details(survey: survey, crashes: crashes, setAside: setAsideTally, days: days)
        )
        return Answer(row: row, crashes: crashes, windowDays: days)
    }

    /// The row for a Mac whose crash folders could not be opened at all.
    ///
    /// ⚠️ `.notGrantable`, never `.notPermitted`, when the refusal is the shared folder: it is
    /// readable by the `admin` group, so it is **the kind of account you sign in with** that
    /// decides it, not a privacy setting. There is no switch, so there is no button.
    ///
    /// The person's own folder is different. Nothing but a privacy setting can keep somebody out of
    /// their own `~/Library/Logs`, so that refusal is `.notPermitted` and does carry a button — the
    /// one place in Apps that could ever ask for Full Disk Access. **It did not fire on the measured
    /// Mac**, which is what the section's "Apps needs no Full Disk Access" claim rests on.
    private static func refused(_ survey: Survey) -> AppsRow {
        if survey.readOwnFolder {
            return .unreadable(.stoppedWorking, .notGrantable,
                               about: "Apps that stopped working",
                               reason: "macOS keeps crash reports in a folder only an administrator "
                                     + "account can open. That is decided by the kind of account you "
                                     + "sign in with, not by a privacy setting, so there is nothing "
                                     + "to switch on.",
                               details: [howWeLooked])
        }
        return .unreadable(.stoppedWorking, .notPermitted,
                           about: "Apps that stopped working",
                           reason: "We could not open the folder macOS keeps crash reports in. "
                                 + "Giving Wellkept Full Disk Access would let us read it.",
                           details: [howWeLooked],
                           remedy: Remedy(title: "Open Privacy & Security",
                                          settingsPane: "fullDiskAccess"))
    }

    // MARK: - ⭐ The filter

    /// Apple's number for a crash report.
    static let crashBugType = "309"

    /// Apple's number for an app macOS stopped because it used too much memory.
    static let outOfMemoryBugType = "298"

    /// `platform` for software built for this Mac. Anything else came from another device.
    static let macOSPlatform = 1

    /// The identifier prefix the iPhone simulator's own processes carry.
    static let simulatorPrefix = "com.apple.CoreSimulator"

    /// The filename prefix macOS gives a report an app filed about itself.
    static let selfFiledPrefix = "ExcUserFault"

    /// **Why this report is not an app on this Mac crashing — or `nil` where it is one.**
    ///
    /// ⚠️ **The order is the meaning.** Each rule answers a different question, and a report can
    /// satisfy several: `backboardd` has no identifier *and* is an iOS process, and the honest thing
    /// to tell somebody is the second. The order below runs from "this is not a crash at all"
    /// through "it is a crash, but not of anything you opened" to "it is an app, but not one of
    /// yours" — which is the order a person would work it out in.
    static func setAside(_ report: Report, appsOnThisMac: Set<String>) -> SetAside? {
        // 1. Not a crash. The memory case is named first and separately so it can never be
        //    swallowed by the general "nothing crashed" bucket — see the file header.
        if report.bugType == outOfMemoryBugType { return .stoppedForMemory }
        if report.bugType != crashBugType { return .nothingCrashed }

        // 2. It is crash-shaped, but the process did not stop.
        if report.isSelfFiled || report.fileName.hasPrefix(selfFiledPrefix) {
            return .filedWhileStillRunning
        }

        // 3. The simulator's own machinery, which is not software anybody opened.
        if let id = report.bundleID, id.hasPrefix(simulatorPrefix) { return .theSimulatorItself }

        // 4. An iPhone, iPad or Watch build running here. `nil` is not evidence of anything, so a
        //    header that did not say is left alone.
        if let platform = report.platform, platform != macOSPlatform { return .builtForAnotherDevice }

        // 5. No identifier at all — a command-line tool or a daemon.
        guard let bundleID = report.bundleID, !bundleID.isEmpty else { return .notAnApp }

        // 6. An app, but not one of the apps this section lists.
        guard appsOnThisMac.contains(bundleID) else { return .notAnAppOnThisMac }

        return nil
    }

    /// The reports that survived, gathered per app, most recent first.
    static func crashedApps(from reports: [Report]) -> [CrashedApp] {
        var counts: [String: (name: String, crashes: Int, last: Date)] = [:]
        for report in reports {
            guard let id = report.bundleID else { continue }
            let name = report.appName ?? id
            if var existing = counts[id] {
                existing.crashes += 1
                if report.at > existing.last { existing.last = report.at }
                counts[id] = existing
            } else {
                counts[id] = (name, 1, report.at)
            }
        }
        return counts
            .map { CrashedApp(appName: $0.value.name,
                              bundleID: $0.key,
                              crashes: $0.value.crashes,
                              lastCrash: $0.value.last) }
            .sorted { $0.lastCrash > $1.lastCrash }
    }

    // MARK: - The words

    /// The row's own sentence. **The window is in it, always.**
    static func headline(crashes: [CrashedApp], filesSeen: Int, days: Int?) -> String {
        let clause = windowClause(days)

        guard filesSeen > 0 else {
            // ⚠️ Not "no app has crashed". An empty folder on a Mac that has been switched off or
            // freshly set up says nothing was recorded, which is a different fact.
            return "macOS has not filed any crash report on this Mac."
        }
        switch crashes.count {
        case 0:  return "No app on this Mac has stopped working \(clause)."
        case 1:  return "\(crashes[0].appName) stopped working \(clause)."
        default: return "\(crashes.count) apps stopped working \(clause)."
        }
    }

    /// The figure beside the sentence: **the window, and never a count of files.**
    ///
    /// ⚠️ This is the one decision in the row that a redesign would get wrong. The obvious measure
    /// is "105 reports read" — and 105 in large type beside "no app has stopped working" is exactly
    /// the number a cleaner prints, read by a person who will remember the number and not the
    /// sentence. The window cannot be misread as a fault count, and it is the qualifier the
    /// headline depends on. `nil` where it could not be measured — never a stand-in.
    static func measure(_ days: Int?) -> String? {
        guard let days, days > 0 else { return nil }
        return days == 1 ? "1 day" : "\(days) days"
    }

    /// Why the row says what it says. **This is where the 105 goes.**
    static func reason(crashes: [CrashedApp],
                       survey: Survey,
                       setAside: [SetAside: Int]) -> String {
        var parts: [String] = []

        if !crashes.isEmpty {
            parts.append(crashes.map(\.sentence).joined(separator: " "))
        }

        let seen = survey.filesSeen
        if seen > 0 {
            let files = seen == 1 ? "1 report" : "\(seen) reports"
            let none = crashes.isEmpty ? " None of them is an app on this Mac stopping." : ""
            parts.append("macOS filed \(files) in that time.\(none) \(tallySentence(setAside))")
        } else {
            parts.append("A Mac that has been switched off, or one that was set up recently, files "
                       + "none — so this says nothing is recorded rather than that anything is wrong.")
        }

        if !survey.readSharedFolder {
            parts.append("macOS also keeps a shared folder of these that only an administrator "
                       + "account can open, and this account cannot. Nothing we could ask for would "
                       + "change that.")
        }
        if survey.trimmed {
            parts.append("There were more reports than we open in one look, so the oldest were "
                       + "counted but not read.")
        }

        parts.append(windowSentence(survey.earliestRecord))
        return parts.joined(separator: " ")
    }

    /// "71 are performance notices where nothing crashed, 13 came from …" — only the groups that
    /// actually have something in them, in `SetAside.allCases` order.
    static func tallySentence(_ setAside: [SetAside: Int]) -> String {
        let present = SetAside.allCases.compactMap { why -> String? in
            guard let n = setAside[why], n > 0 else { return nil }
            return "\(n) \(clause(for: why, count: n))"
        }
        guard !present.isEmpty else { return "" }
        return "\(sentenceList(present).uppercasedFirst)."
    }

    private static func clause(for why: SetAside, count: Int) -> String {
        let were = count == 1 ? "was" : "were"
        switch why {
        case .nothingCrashed:         return "\(were) notices where nothing crashed"
        case .stoppedForMemory:       return "record an app stopped for using too much memory, which is Hardware's memory reading and not a crash"
        case .filedWhileStillRunning: return "\(were) filed by an app about itself while it kept running"
        case .theSimulatorItself:     return "came from the iPhone simulator's own machinery"
        case .builtForAnotherDevice:  return "came from software built for another device"
        case .notAnApp:               return "came from command-line tools with no app behind them"
        case .notAnAppOnThisMac:      return "name software that is not in the list of apps above"
        }
    }

    /// The limit of the whole row, stated every time it is drawn.
    static func windowSentence(_ earliestRecord: Date?) -> String {
        guard let earliestRecord else {
            return "macOS prunes this folder and does not say how far back what is left goes, so "
                 + "this is a report about what it still keeps rather than about this Mac's whole "
                 + "life."
        }
        return "macOS keeps these back to \(day(earliestRecord)) on this Mac and prunes what is "
             + "older. How far back that goes depends on how much this Mac has had to say, not on "
             + "any setting — so this is a report about that window and not about this Mac's whole "
             + "life."
    }

    // MARK: The detail

    /// Everything more exact, behind **Options**.
    static func details(survey: Survey,
                        crashes: [CrashedApp],
                        setAside: [SetAside: Int],
                        days: Int?) -> [DetailPair] {
        var pairs: [DetailPair] = []

        pairs.append(DetailPair("Window measured",
                                measure(days) ?? "Could not be measured on this run."))
        pairs.append(DetailPair("Reports go back to",
                                survey.earliestRecord.map(day) ?? Unreadable.notReported.sentence))
        pairs.append(DetailPair("Reports macOS filed", "\(survey.filesSeen)"))
        pairs.append(DetailPair("Of those, apps stopping", "\(crashes.count)"))

        for crash in crashes {
            pairs.append(crash.detailPair)
        }

        // ⚠️ Every set-aside report is named and counted. A filter nobody can audit is a fudge.
        for why in SetAside.allCases {
            guard let n = setAside[why], n > 0 else { continue }
            pairs.append(DetailPair(why.label, "\(n) — \(why.explanation)"))
        }

        pairs.append(DetailPair("The shared folder",
                                survey.readSharedFolder
                                    ? "Read."
                                    : "Only an administrator account can open it. No permission "
                                    + "this app could ask for would change that."))
        pairs.append(howWeLooked)
        return pairs
    }

    /// The same sentence wherever the row explains itself, refused or not.
    static let howWeLooked = DetailPair(
        "How we looked",
        "We read the first line of each report macOS had already written. Wellkept made nothing "
      + "crash, changed nothing, and sent nothing anywhere.")

    // MARK: - The window

    /// How far back the folder reached, in whole days. `nil` where it could not be measured, and
    /// `nil` is a real answer.
    static func measuredDays(earliestRecord: Date?, now: Date) -> Int? {
        guard let earliestRecord, earliestRecord < now else { return nil }
        let days = Int(now.timeIntervalSince(earliestRecord) / 86_400)
        return days > 0 ? days : 1
    }

    /// ⚠️ **"in the last 8 days" — and this file never writes its own version of that sentence.**
    ///
    /// The wording belongs to `SecurityReport.windowClause`, and Security's own log row already
    /// borrows it for exactly this reason. Two sections each phrasing "how far back we could see"
    /// is two chances for them to disagree about what "nothing" covers, on the same Mac, on the same
    /// afternoon. Building an empty report to borrow the string is cheap, and it is one wording for
    /// ever.
    static func windowClause(_ days: Int?) -> String {
        SecurityReport(block: .unknown, rows: [], measuredDays: days).windowClause
    }

    // MARK: - Reading the folders

    /// Where macOS files these. The person's own folder first, then the shared one.
    static var folders: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Logs/DiagnosticReports"),
            URL(fileURLWithPath: "/Library/Logs/DiagnosticReports"),
        ]
    }

    /// macOS moves older reports into `Retired` before deleting them. They are still on this Mac and
    /// they widen the window honestly, so they are read too.
    static let retiredFolder = "Retired"

    /// How many reports we are willing to open in one press. A Mac that has been logging for months
    /// can hold thousands; opening all of them would make this row cost more than the app inventory
    /// it sits under. Above this the rest are counted and the row says so.
    static let fileBudget = 2_000

    /// Ask this Mac what macOS has filed. Blocking, and it belongs on a detached task beside the
    /// inventory read.
    static func survey(now: Date = Date()) -> Survey {
        let manager = FileManager.default
        var reports: [Report] = []
        var nonCrash = 0
        var earliest: Date?
        var readOwn = false
        var readShared = false
        var opened = 0
        var trimmed = false

        for (index, folder) in folders.enumerated() {
            var sawFolder = false

            for directory in [folder, folder.appendingPathComponent(retiredFolder)] {
                guard let names = try? manager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }
                sawFolder = true

                for url in names {
                    let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate
                    if let modified, earliest.map({ modified < $0 }) ?? true { earliest = modified }

                    // ⚠️ Classified on the extension alone, without being opened. A `.diag` notice
                    // or a `.shutdownStall` is never a crash, and there are far more of them than
                    // there are crash reports.
                    guard url.pathExtension == "ips" else {
                        if modified != nil { nonCrash += 1 }
                        continue
                    }
                    guard opened < fileBudget else { trimmed = true; nonCrash += 1; continue }
                    opened += 1

                    if let report = report(at: url, fallbackDate: modified ?? now) {
                        reports.append(report)
                    } else {
                        // Unreadable or not the shape we know. Counted so the numbers still add up,
                        // never guessed at.
                        nonCrash += 1
                    }
                }
            }

            if index == 0 { readOwn = sawFolder } else { readShared = sawFolder }
        }

        guard readOwn || readShared else {
            return Survey(reports: nil,
                          readSharedFolder: readShared,
                          readOwnFolder: readOwn)
        }

        return Survey(reports: reports,
                      nonCrashFiles: nonCrash,
                      earliestRecord: earliest,
                      readSharedFolder: readShared,
                      readOwnFolder: readOwn,
                      trimmed: trimmed)
    }

    /// Read one `.ips` file's header line.
    ///
    /// The first line is a small JSON object macOS writes before the body; the body can be
    /// megabytes and is never read. 8 KB is comfortably more than any header measured.
    static func report(at url: URL, fallbackDate: Date) -> Report? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 8_192), !data.isEmpty else { return nil }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)[0]
        return report(fromHeader: String(firstLine),
                      fileName: url.lastPathComponent,
                      fallbackDate: fallbackDate)
    }

    /// Parse one header line. **Pure**, so every shape below can be tested from a string.
    static func report(fromHeader header: String,
                       fileName: String,
                       fallbackDate: Date) -> Report? {
        guard let data = header.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let fields = object as? [String: Any] else { return nil }

        let simulated = (fields["is_simulated"] as? Int) == 1
            || (fields["is_simulated"] as? Bool) == true

        return Report(fileName: fileName,
                      bundleID: fields["bundleID"] as? String,
                      appName: (fields["app_name"] as? String) ?? (fields["name"] as? String),
                      bugType: bugType(fields["bug_type"]),
                      platform: fields["platform"] as? Int,
                      isSelfFiled: simulated,
                      at: date(fields["timestamp"] as? String) ?? fallbackDate)
    }

    /// Apple writes `bug_type` as a string, and has written it as a number. Both are accepted, and
    /// **an absent one is not treated as a crash** — the filter's first rule requires the number to
    /// say so.
    static func bugType(_ raw: Any?) -> String? {
        if let text = raw as? String { return text }
        if let number = raw as? Int { return String(number) }
        return nil
    }

    /// "2026-08-20 09:58:08.00 -0600". `nil` where it is not that shape, and the caller falls back
    /// to the file's own date rather than inventing one.
    static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss.SS Z", "yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    // MARK: - Small language helpers

    private static func day(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private static func sentenceList(_ items: [String]) -> String {
        switch items.count {
        case 0:  return ""
        case 1:  return items[0]
        case 2:  return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + " and \(items[items.count - 1])"
        }
    }
}

private extension String {
    /// The tally is a sentence of its own, so it starts like one.
    var uppercasedFirst: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}

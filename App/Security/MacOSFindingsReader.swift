import Foundation
import OSLog
import WellkeptCore

//  MacOSFindingsReader.swift
//  Wellkept — App/Security
//
//  **What macOS has already found.** XProtect and XProtect Remediator, read out of the Mac's own
//  log.
//
//  This is the row that tells somebody their Mac has already been checked, by Apple, without them
//  asking — about twenty scanners that run in the background and clean up what they find. It is
//  reporting, never scanning: Wellkept runs nothing and removes nothing here. John's answer,
//  2026-08-27, on whether Wellkept should scan for malware itself: **after quarantine exists.** A
//  scan that finds something today has nowhere to put it.
//
//  ## How it is read, and what that cost
//
//  `OSLogStore(scope: .system)` from inside the app. Verified working from a signed, hardened
//  binary on 2026-08-27 — **no entitlement, and no shelling out to the `log` command.** The
//  predicate is `subsystem BEGINSWITH "com.apple.XProtect"`, which catches XProtect, the
//  Remediator plugins and the behavioural service in one pass.
//
//  Measured on this Mac: **about 5.5 seconds.** It is by far the slowest read in the app, and it is
//  why **Security does not run on launch** — it runs on a press, and the screen has to show that it
//  is still looking.
//
//  ## ⚠️ The window is measured, never assumed
//
//  macOS keeps roughly a fortnight of log, and **how far back is decided by how chatty this Mac has
//  been, not by any policy.** On this Mac the store reached back 14 days; on a quiet Mac it reaches
//  further, on a busy one less, and the same Mac gives a different answer next week.
//
//  So "nothing was ever found" and "something was found three weeks ago" look **identical** from
//  here. The only honest way to say anything is to say how far back we could see, in the same
//  breath — which is why `Answer` carries `measuredDays` up to `SecurityReport`, and why every
//  sentence in this file is built with `SecurityReport.windowClause` rather than a number typed out
//  here.
//
//  ## ⚠️ "Some scanners did not finish" is the ORDINARY case
//
//  On a completely clean Mac this morning, one of about twenty plugins — KeySteal — reported
//  `PluginCanceled` part-way through. That is routine: macOS starts these when the Mac is idle and
//  stops them when it is not. The copy below treats it as ordinary, because a health check that
//  raises an eyebrow at the ordinary case raises it on most Macs most days.
//
//  ## ⚠️ Invisible to a standard account, and no permission fixes it
//
//  A non-administrator cannot open the system log at all. That is `Unreadable.notGrantable`: the
//  row says plainly that we did not see it, carries **no button**, and the check stays **complete**
//  — because no permission this app could ever ask for, Full Disk Access included, would have shown
//  it more. Marking it `.notPermitted` would hang a caveat on Overview that a standard account
//  could never clear, which is the exact bug fixed on 2026-08-27.
//
//  ## ⚠️ This row can never be amber, and that is on purpose
//
//  None of the nine conditions in `SecurityConcern` is about an XProtect finding, and
//  `SecurityRow.severity` is computed from concerns — so there is no route by which this row turns
//  amber, including the case where macOS found and removed something. That is defensible: what this
//  row reports is **already dealt with**, by Apple, before Wellkept ever looked. It is stated
//  plainly in the row's own words. A tenth condition is a conversation with John, not a pull
//  request.

enum MacOSFindingsReader {

    // MARK: - What one run produced

    /// The row, and the window it was able to measure.
    ///
    /// ⚠️ **`measuredDays` has to travel.** It is the one number `SecurityReport` cannot work out
    /// for itself, and every honest sentence in this section depends on it. Whoever assembles the
    /// report passes it straight through to `SecurityReport(block:rows:ranAt:measuredDays:)`.
    struct Answer: Sendable, Hashable {
        let row: SecurityRow
        /// How far back the log store actually reached, in days. **`nil` is a real answer** and is
        /// handled honestly by `SecurityReport.windowClause`; it is never replaced with 14.
        let measuredDays: Int?
    }

    // MARK: - What one scanner said

    /// What one scanner reported about one run.
    ///
    /// Built from the `status_message` string rather than the numeric `status_code`. Apple
    /// publishes neither, but the strings are internal enum names — unlocalised, stable, and
    /// legible — while the codes are a table somebody would have to guess at and would be wrong
    /// about silently. The code is still carried through to Options so a curious person sees
    /// exactly what the machine said.
    enum Outcome: Sendable, Hashable {
        /// The scanner ran and found nothing. `NoThreatDetected`, `Success`.
        case clean
        /// The scanner stopped before finishing. **The ordinary case** — see the file header.
        case didNotFinish
        /// macOS found something and dealt with it.
        case dealtWith
        /// A word we do not recognise, carried verbatim so the row can print what macOS actually
        /// said rather than a guess about it.
        case unrecognised(String)

        var isClean: Bool { self == .clean }
    }

    /// One scanner's report of one run.
    struct ScanResult: Sendable, Hashable, Identifiable {
        /// "Adload", "KeySteal" — the plugin's name, with Apple's prefix taken off.
        let scanner: String
        let at: Date
        let outcome: Outcome
        /// Exactly what macOS wrote: "NoThreatDetected", "PluginCanceled".
        let statusMessage: String
        /// The number beside it, where there was one.
        let statusCode: Int?

        var id: String { "\(scanner)|\(at.timeIntervalSince1970)" }
    }

    /// Everything one look at the log produced.
    struct Survey: Sendable, Hashable {
        /// **`nil` where the log could not be opened at all** — which is not the same as a log with
        /// nothing in it, and the row keeps those apart.
        let results: [ScanResult]?
        /// The oldest entry of any kind in the store. This is what the window is measured from, and
        /// it is deliberately not measured from the oldest XProtect entry: a Mac whose scanners
        /// last ran a month ago would otherwise report a one-month window it never had.
        let earliestRecord: Date?
        /// The most recent moment anything XProtect-shaped said anything. It answers "have the
        /// scanners run at all", which is a different question from "what did they find".
        let lastActivity: Date?
        /// Whether this account can read the system log at all. Used only to word the refusal.
        let isAdministrator: Bool

        init(results: [ScanResult]?,
             earliestRecord: Date? = nil,
             lastActivity: Date? = nil,
             isAdministrator: Bool = true) {
            self.results = results
            self.earliestRecord = earliestRecord
            self.lastActivity = lastActivity
            self.isAdministrator = isAdministrator
        }
    }

    // MARK: - The row

    /// Read this Mac's log and build the row. **About 5.5 seconds.** Blocking, and it belongs on a
    /// detached task.
    static func read(now: Date = Date()) -> Answer {
        answer(from: survey(), now: now)
    }

    /// The row, from a survey. **Pure**, so a Mac that found malware three days ago — which this
    /// one has not — can still be tested.
    static func answer(from survey: Survey, now: Date = Date()) -> Answer {
        let days = measuredDays(earliestRecord: survey.earliestRecord, now: now)

        guard let results = survey.results else {
            return Answer(row: refused(survey), measuredDays: days)
        }

        let clause = windowClause(days)
        let dealtWith = results.filter { $0.outcome == .dealtWith }
        let unrecognised = results.filter {
            if case .unrecognised = $0.outcome { return true }
            return false
        }
        let unfinished = results.filter { $0.outcome == .didNotFinish }

        let row = SecurityRow(
            topic: .macOSFindings,
            headline: headline(results: results,
                               dealtWith: dealtWith,
                               unrecognised: unrecognised,
                               lastActivity: survey.lastActivity,
                               clause: clause),
            measure: measure(days),
            reason: reason(results: results,
                           dealtWith: dealtWith,
                           unrecognised: unrecognised,
                           unfinished: unfinished,
                           lastActivity: survey.lastActivity,
                           earliestRecord: survey.earliestRecord,
                           clause: clause),
            details: details(survey: survey, results: results, days: days)
        )
        return Answer(row: row, measuredDays: days)
    }

    /// The row for an account that cannot open the log.
    ///
    /// ⚠️ `.notGrantable`, never `.notPermitted`. There is no button, because there is no door.
    private static func refused(_ survey: Survey) -> SecurityRow {
        let reason = survey.isAdministrator
            ? "macOS did not let this app read its own log on this run. There is no permission "
            + "that would change that — the log is not covered by any privacy setting."
            : "Only an administrator account can read this Mac's log, and macOS's own scanners "
            + "report what they find there. That is decided by the kind of account you sign in "
            + "with, not by a privacy setting, so there is nothing to switch on."

        return .unreadable(.macOSFindings, .notGrantable,
                           about: "What macOS has already found",
                           reason: reason,
                           details: [DetailPair("How we looked",
                                                "We asked macOS for its own log of what its "
                                              + "scanners have done. Nothing was scanned by us.")])
    }

    // MARK: The words

    /// The row's own sentence. **The window is in it, always.**
    static func headline(results: [ScanResult],
                         dealtWith: [ScanResult],
                         unrecognised: [ScanResult],
                         lastActivity: Date?,
                         clause: String) -> String {
        if !dealtWith.isEmpty {
            let what = dealtWith.count == 1 ? "something" : "\(dealtWith.count) things"
            return "macOS found \(what) and dealt with it \(clause)."
        }
        if results.isEmpty {
            // ⚠️ A Mac that has been asleep or switched off runs no scanners. Reporting a clean
            // result nobody earned is the confident wrong answer this section exists to avoid.
            guard lastActivity != nil else {
                return "macOS's own scanners have not run \(clause)."
            }
            return "macOS's own scanners have been busy \(clause), and recorded no result we can "
                 + "read."
        }
        if unrecognised.count == results.count {
            let runs = results.count == 1 ? "once" : "\(results.count) times"
            return "macOS's own scanners ran \(runs) \(clause), and reported something we do not "
                 + "recognise."
        }
        return "macOS's own scanners found nothing \(clause)."
    }

    /// The figure on the row: the window itself.
    ///
    /// It is the one number this row is about, and putting it beside the sentence means a person
    /// who reads only the row still knows what "nothing" covers. `nil` where the window could not
    /// be measured — never a stand-in 14.
    static func measure(_ days: Int?) -> String? {
        guard let days, days > 0 else { return nil }
        return days == 1 ? "1 day" : "\(days) days"
    }

    /// Why the row says what it says.
    static func reason(results: [ScanResult],
                       dealtWith: [ScanResult],
                       unrecognised: [ScanResult],
                       unfinished: [ScanResult],
                       lastActivity: Date?,
                       earliestRecord: Date?,
                       clause: String) -> String {
        var parts: [String] = []

        if !dealtWith.isEmpty {
            let names = list(dealtWith.map(\.scanner))
            parts.append("macOS's own scanner (\(names)) removed it at the time. Nothing is left "
                       + "for you to do about it — this is a record of something already handled.")
        }

        // ⚠️ Ordinary, and worded as ordinary. About twenty of these run in the background; one
        // being stopped mid-flight is what a normal Tuesday looks like.
        if !unfinished.isEmpty {
            let count = unfinished.count
            parts.append("\(count == 1 ? "One scanner" : "\(count) scanners") did not finish the "
                       + "last time round. That is routine: macOS starts about twenty of them when "
                       + "the Mac is idle and stops them again when it is not.")
        }

        if !unrecognised.isEmpty {
            parts.append("\(unrecognised.count == 1 ? "One result uses" : "\(unrecognised.count) results use") "
                       + "a word we do not recognise. It is shown under Options exactly as macOS "
                       + "wrote it.")
        }

        if results.isEmpty, lastActivity == nil {
            parts.append("A Mac that has been asleep or switched off does not run them, so this "
                       + "says nothing is recorded rather than that anything is wrong.")
        }

        // The limit of the whole row, stated every time.
        if let earliestRecord {
            parts.append("macOS keeps its log back to \(day(earliestRecord)) on this Mac, and "
                       + "prunes what is older. How far back that goes depends on how much this "
                       + "Mac has had to say, not on any setting — so this is a report about that "
                       + "window and not about this Mac's whole life.")
        } else {
            parts.append("macOS prunes this log and does not say how far back what is left goes, "
                       + "so this is a report about what it still keeps rather than about this "
                       + "Mac's whole life.")
        }

        return parts.joined(separator: " ")
    }

    /// Everything more exact, behind **Options**.
    static func details(survey: Survey, results: [ScanResult], days: Int?) -> [DetailPair] {
        var pairs: [DetailPair] = []

        pairs.append(DetailPair("Records go back to",
                                survey.earliestRecord.map(day) ?? Unreadable.notReported.sentence))
        pairs.append(DetailPair("Window measured",
                                measure(days) ?? "Could not be measured on this run."))
        pairs.append(DetailPair("Scanner results read", "\(results.count)"))

        if let lastActivity = survey.lastActivity {
            pairs.append(DetailPair("Scanners last active", ShortDate.stamp(lastActivity)))
        }

        // Most recent first, and capped: a busy Mac can record hundreds of these, and a disclosure
        // that unrolls two hundred near-identical lines is a disclosure nobody reads.
        let shown = results.sorted { $0.at > $1.at }.prefix(12)
        var used = Set<String>()
        for result in shown {
            var label = result.scanner
            var suffix = 2
            while !used.insert(label).inserted {
                label = "\(result.scanner) (\(suffix))"
                suffix += 1
            }
            pairs.append(DetailPair(label, "\(sentence(for: result)) — \(ShortDate.stamp(result.at))"))
        }
        if results.count > shown.count {
            pairs.append(DetailPair("Older results", "\(results.count - shown.count) more."))
        }

        pairs.append(DetailPair("How we looked",
                                "We read macOS's own log of what its scanners have done. Wellkept "
                              + "scanned nothing itself and changed nothing."))
        return pairs
    }

    private static func sentence(for result: ScanResult) -> String {
        switch result.outcome {
        case .clean:        "Found nothing"
        case .didNotFinish: "Did not finish this time (macOS said: \(result.statusMessage))"
        case .dealtWith:    "Found something and dealt with it"
        case let .unrecognised(word): "macOS said: \(word)"
        }
    }

    // MARK: The window

    /// How far back the store reached, in whole days. `nil` where it could not be measured, and
    /// `nil` is a real answer.
    static func measuredDays(earliestRecord: Date?, now: Date) -> Int? {
        guard let earliestRecord, earliestRecord < now else { return nil }
        let days = Int(now.timeIntervalSince(earliestRecord) / 86_400)
        return days > 0 ? days : 1
    }

    /// ⚠️ **"in the last 12 days" — and this file never writes its own version of that sentence.**
    ///
    /// The wording belongs to `SecurityReport.windowClause`, which also has to say it, and two
    /// copies of a sentence about time is two chances for the row and the summary above it to
    /// disagree about how far back "nothing" reaches. Building an empty report to borrow the string
    /// is cheap and it is exactly one wording, for ever.
    static func windowClause(_ days: Int?) -> String {
        SecurityReport(block: .unknown, rows: [], measuredDays: days).windowClause
    }

    // MARK: - Reading the log

    /// The subsystem prefix every XProtect component logs under: `com.apple.XProtect`,
    /// `com.apple.XProtectFramework`, `com.apple.XProtectFramework.PluginAPI`. One predicate covers
    /// them all, and one pass over the store is all the time budget allows.
    static let subsystemPrefix = "com.apple.XProtect"

    /// The category the plugins write their machine-readable results to. Everything else under the
    /// prefix is progress chatter — 5,076 path-scanning lines on this Mac against 34 results.
    static let structuredCategory = "XPEvent.structured"

    /// Ask macOS what its scanners have done.
    static func survey() -> Survey {
        let administrator = isAdministrator()

        guard let store = try? OSLogStore(scope: .system) else {
            return Survey(results: nil, isAdministrator: administrator)
        }
        let start = store.position(date: .distantPast)

        // The window, from the first entry of any kind. Lazy, so this stops after one entry — it
        // measured 0.8 s on this Mac against 4.6 s for the filtered pass.
        var earliest: Date?
        if let all = try? store.getEntries(at: start) {
            for entry in all { earliest = entry.date; break }
        }

        let predicate = NSPredicate(format: "subsystem BEGINSWITH %@", subsystemPrefix)
        guard let entries = try? store.getEntries(at: start, matching: predicate) else {
            return Survey(results: nil, earliestRecord: earliest, isAdministrator: administrator)
        }

        var lastActivity: Date?
        var raw: [ScanResult] = []

        for entry in entries {
            guard let log = entry as? OSLogEntryLog else { continue }
            if lastActivity.map({ log.date > $0 }) ?? true { lastActivity = log.date }

            // ⚠️ `category` is a stored string and free; `composedMessage` formats the whole entry
            // and is not. Checking the category first is the difference between reading 34 messages
            // and reading 5,700 of them on every press.
            guard log.category == structuredCategory else { continue }
            if let result = result(fromMessage: log.composedMessage,
                                   process: log.process,
                                   at: log.date) {
                raw.append(result)
            }
        }

        return Survey(results: condense(raw),
                      earliestRecord: earliest,
                      lastActivity: lastActivity,
                      isAdministrator: administrator)
    }

    /// Parse one structured event. **Pure.**
    ///
    /// The message is a small JSON object the plugin wrote itself:
    /// `{"status_message":"NoThreatDetected","status_code":20,"execution_duration":…,"caused_by":[]}`
    static func result(fromMessage message: String, process: String, at date: Date) -> ScanResult? {
        guard let data = message.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let fields = object as? [String: Any],
              let status = fields["status_message"] as? String else { return nil }

        return ScanResult(scanner: scannerName(fromProcess: process),
                          at: date,
                          outcome: outcome(of: status),
                          statusMessage: status,
                          statusCode: fields["status_code"] as? Int)
    }

    /// "XProtectRemediatorKeySteal" → "KeySteal". Anything else keeps its own name.
    static func scannerName(fromProcess process: String) -> String {
        let prefix = "XProtectRemediator"
        guard process.hasPrefix(prefix), process.count > prefix.count else { return process }
        return String(process.dropFirst(prefix.count))
    }

    /// What one status word means.
    ///
    /// ⚠️ **An unrecognised word is reported as unrecognised, never assumed clean and never assumed
    /// bad.** Apple adds to this vocabulary without announcing it, and a reader that quietly filed
    /// an unknown word under "found nothing" would turn a new kind of finding into silence.
    static func outcome(of statusMessage: String) -> Outcome {
        let word = statusMessage.lowercased()

        // Order matters: "NoThreatDetected" contains "threatdetected".
        if word.contains("nothreat") || word == "success" || word.contains("notdetected") {
            return .clean
        }
        if word.contains("cancel") || word.contains("fail") || word.contains("timeout")
            || word.contains("timedout") || word.contains("skip") || word.contains("error") {
            return .didNotFinish
        }
        if word.contains("remediat") || word.contains("detected") || word.contains("removed") {
            return .dealtWith
        }
        return .unrecognised(statusMessage)
    }

    /// Cut a run's worth of events down to what a person would want to see.
    ///
    /// Everything that is not routine is kept: a finding, and anything worded in a way we do not
    /// recognise, stay in the list even where the same scanner ran clean afterwards — "macOS
    /// removed something last Tuesday" does not stop being true because Wednesday was quiet.
    /// Routine results collapse to the most recent one per scanner, which is what keeps a Mac that
    /// has run twenty plugins forty times from producing eight hundred rows.
    static func condense(_ results: [ScanResult]) -> [ScanResult] {
        var kept: [ScanResult] = []
        var latestRoutine: [String: ScanResult] = [:]

        for result in results {
            switch result.outcome {
            case .clean, .didNotFinish:
                if let existing = latestRoutine[result.scanner], existing.at >= result.at { continue }
                latestRoutine[result.scanner] = result
            case .dealtWith, .unrecognised:
                kept.append(result)
            }
        }

        return (kept + latestRoutine.values).sorted { $0.at > $1.at }
    }

    // MARK: - The account

    /// Whether this account is an administrator.
    ///
    /// Used only to word the refusal: an administrator who still cannot open the log has hit
    /// something else, and telling them to become an administrator would be advice they have
    /// already taken.
    static func isAdministrator() -> Bool {
        guard let group = getgrnam("admin") else { return false }
        let adminGroup = group.pointee.gr_gid

        var groups = [gid_t](repeating: 0, count: 64)
        let count = getgroups(Int32(groups.count), &groups)
        guard count > 0 else { return false }
        return groups.prefix(Int(count)).contains(adminGroup)
    }

    // MARK: - Small language helpers

    private static func day(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private static func list(_ items: [String]) -> String {
        let unique = Array(NSOrderedSet(array: items)).compactMap { $0 as? String }
        switch unique.count {
        case 0:  return ""
        case 1:  return unique[0]
        case 2:  return "\(unique[0]) and \(unique[1])"
        default: return unique.dropLast().joined(separator: ", ") + " and \(unique[unique.count - 1])"
        }
    }
}

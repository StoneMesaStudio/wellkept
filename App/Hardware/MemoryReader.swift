import Darwin
import Foundation
import WellkeptCore

//  MemoryReader.swift
//  Wellkept — App/Hardware
//
//  **The Memory row: has macOS had to close anything to keep this Mac running?**
//
//  ## Why this row is not a footnote
//
//  The plan had memory as a line of statistics. It is the loudest true finding on an 8 GB Mac,
//  because it is the one memory measurement a person already recognises: they were using an app,
//  and the app vanished. Nobody watches a swap figure. Everybody remembers that.
//
//  So the row leads with the count of times macOS shut a running program down to get memory back,
//  over a window it states out loud, and it names them. Installed memory, pressure, swap and
//  compression sit behind Options, where numbers belong.
//
//  ## ⚠️ What the measurement actually found, and why the wording is careful
//
//  The research said macOS force-quit three of John's apps in eight days. It did not. Every one of
//  the three `JetsamEvent` reports on this Mac names exactly one process, and all three were
//  killed for **`per-process-limit`** — the process exceeded *its own* memory cap, which macOS
//  sets per program. The three were `ReportCrash` (twice) and `knowledgeconstructiond`: Apple's
//  own crash reporter and an Apple background daemon. Not one of them was a thing John was using,
//  and the Mac was never short of memory.
//
//  That is the difference this file is built around:
//
//  | Kill reason | What it means | Counted in the headline? |
//  |---|---|---|
//  | `vm-pageshortage`, `vm-compressor-thrashing`, `low-swap`, … | **the Mac ran out of memory** | **Yes** |
//  | `per-process-limit`, `highwater` | one program hit its own cap | No — stated in Options |
//  | `idle-exit`, `vnode-limit`, `disk-space-shortage` | routine housekeeping, nothing to do with memory | No |
//
//  Counting all of them together would have produced "macOS closed 3 of your apps to free memory"
//  on a machine where that never happened. A false alarm on the loudest row in the section is the
//  most expensive mistake available here.
//
//  ## Where the record lives, and who is allowed to read it
//
//  `/Library/Logs/DiagnosticReports`, the same folder `RestartReader` walks for kernel panics, for
//  a different kind of file. Both readers list it independently — sixty header peeks each, on a
//  memory-mapped file — rather than sharing a cache, because a shared walk between two files
//  written by two people is a coupling that outlives whichever of them changes first.
//
//  ⚠️ The folder is `drwxrwx--- root:_analyticsusers`, and `_analyticsusers` nests exactly one
//  group: `admin`. **Only an administrator account can read it.** That is decided by the kind of
//  account you sign in with, not by a privacy setting — the same gate as kernel panics, and
//  **Full Disk Access does not open it.** So a standard account gets the house sentence and no
//  button: `Unreadable.notGrantable`, refused with nothing to offer. The check still calls itself
//  complete, because no permission this app could ever ask for would have shown it more, and a
//  caveat on Overview that a standard account can never clear is the warning-nobody-can-clear this
//  product exists to avoid. What it never does is report "nothing was closed" from a folder we
//  were refused.
//
//  ## The window is stated, never implied
//
//  macOS keeps these reports for days, not for ever — about seven here. "Nothing has been closed"
//  is a claim about that window, and a claim about a week that reads like a claim about a lifetime
//  is the kind of thing a person only discovers was wrong at the worst moment. The window is
//  measured from the oldest report of any kind still in the folder, and printed in the row.
//
//  ## What is deliberately not here
//
//  - **No pressure percentage.** `kern.memorystatus_vm_pressure_level` is a state, not a score,
//    and a percentage nobody can act on is not information. It is reported in words.
//  - **No verdict on swap.** Swapping is how modern macOS works; 1.5 GB on this 8 GB Mac with
//    pressure normal is a healthy machine, not a struggling one. Swap is stated, never flagged.
//  - **No unified-log query.** `log show` reaches jetsam events too, takes seconds, and keeps a
//    shorter history than the reports do. Considered and rejected.

enum MemoryReader {

    /// Where macOS files the reports that belong to the whole machine.
    ///
    /// Declared here rather than borrowed from `RestartReader`: the two rows read the same folder
    /// for unrelated files, and one of them being redirected at a fixture folder must not move the
    /// other.
    static let systemReports = URL(filePath: "/Library/Logs/DiagnosticReports",
                                   directoryHint: .isDirectory)

    /// How far back the row is willing to claim, whatever is in the folder.
    ///
    /// A stray old report would otherwise turn "nothing in the last week" into "nothing in the
    /// last two years", which is a much bigger promise made out of one file macOS forgot to tidy.
    static let longestWindow: TimeInterval = 30 * 86_400

    /// The most jetsam reports to open in one run. Each is a snapshot of every process alive at
    /// the moment of the kill — 400 KB and 750 entries is normal — and a Mac that has been
    /// thrashing for a month can hold dozens. Twelve is far more than enough to describe a
    /// pattern, and it bounds the work at roughly five megabytes.
    static let mostReportsRead = 12

    // MARK: - The row

    /// Read the Memory row.
    ///
    /// Injectable so a test can point it at a folder of fixtures. A reader that can only be
    /// exercised on a Mac that is actually running out of memory is a reader nobody exercises.
    static func read(now: Date = Date(),
                     folder: URL = systemReports,
                     fileManager: FileManager = .default) -> Reading {
        let use = MemoryUse.current()

        switch survey(now: now, folder: folder, fileManager: fileManager) {

        case .missing:
            // Nothing has ever been filed here. That is a normal state on a freshly installed Mac,
            // and it is not a refusal — so the check stays complete.
            return Reading(
                topic: .memory,
                headline: "Nothing on this Mac has been closed to free memory.",
                severity: pressureSeverity(use),
                reason: "macOS keeps no memory reports on this Mac at the moment, so there is "
                      + "nothing to look back through. \(pressureSentence(use))",
                details: usePairs(use)
            )

        case .refused:
            // ⚠️ `.notGrantable`, never `.notPermitted`. The obstacle is the account type, and no
            // permission this app could ask for lifts it — so the row says so, offers nothing, and
            // does not leave Overview carrying a caveat a standard account could never clear.
            return .unreadable(
                .memory, .notGrantable,
                about: "Whether macOS has closed anything to free memory",
                reason: "Only an administrator account can read this Mac's memory reports. That is "
                      + "decided by the kind of account you sign in with, not by a privacy "
                      + "setting, so there is nothing to switch on. \(pressureSentence(use))",
                details: usePairs(use) + [DetailPair("Reports live in", folder.path)]
            )

        case let .surveyed(closures, window):
            return row(closures: closures, window: window, use: use, now: now)
        }
    }

    // MARK: - Building the row

    private static func row(closures: [Closure],
                            window: Window,
                            use: MemoryUse,
                            now: Date) -> Reading {
        let outOfMemory = closures.filter { $0.kind == .ranOutOfMemory }
            .sorted { $0.date > $1.date }
        let recentWeek = outOfMemory.filter { $0.date > now.addingTimeInterval(-7 * 86_400) }.count

        // ⚠️ A single closure weeks ago on a Mac that has been fine since is history, not a fault.
        // What earns `.problem` is a pattern inside a week — the state where a person is losing
        // work repeatedly and can act on it by running fewer things at once.
        let severity: Severity
        if recentWeek >= 3 {
            severity = .problem
        } else if !outOfMemory.isEmpty {
            severity = .attention
        } else {
            severity = pressureSeverity(use)
        }

        return Reading(
            topic: .memory,
            headline: headline(outOfMemory, use: use),
            measure: outOfMemory.isEmpty ? nil : "\(outOfMemory.count)",
            number: ReadingNumber(Double(outOfMemory.count), ReadingNumber.count),
            severity: severity,
            reason: reason(outOfMemory, recentWeek: recentWeek, window: window, use: use),
            details: usePairs(use) + closurePairs(closures, window: window)
        )
    }

    private static func headline(_ outOfMemory: [Closure], use: MemoryUse) -> String {
        switch outOfMemory.count {
        case 0:
            return use.pressure == .critical
                ? "This Mac is short of memory right now."
                : "This Mac has enough memory for what you run on it."
        case 1:
            return "macOS closed \(outOfMemory[0].program) to free memory."
        default:
            return "macOS closed \(outOfMemory.count) running programs to free memory."
        }
    }

    /// Why the row says what it says — on the row, never behind a disclosure.
    ///
    /// Every branch names the window. See the header: a clean answer is a claim about a week.
    private static func reason(_ outOfMemory: [Closure],
                               recentWeek: Int,
                               window: Window,
                               use: MemoryUse) -> String? {
        guard !outOfMemory.isEmpty else {
            var text = "Nothing has been closed to free memory \(window.clause). "
                     + pressureSentence(use)
            if use.pressure == .critical {
                text += " Closing a few things you are not using will clear it."
            }
            return text
        }

        // Named once each. The same program closed four times is one thing a person recognises,
        // and "Safari, Photos and Safari" reads like a bug in the sentence.
        var seen = Set<String>()
        let names = list(outOfMemory.map(\.program).filter { seen.insert($0).inserted }.prefix(4)
            .map { $0 })

        var text = "This Mac ran out of memory, so macOS shut something down to get some back: "
                 + "\(names). "
        if recentWeek >= 3 {
            text += "\(recentWeek) of them in the last week. "
        }
        // ⚠️ No advice about adding memory. It cannot be added to an Apple silicon Mac and it can
        // be added to several of the Intel Macs this app still runs on, and there is no reliable
        // way to tell a person which of those they own. Saying nothing is right on both.
        text += "Running fewer things at once is what frees it up."
        return text
    }

    // MARK: - What the details say

    /// The numbers, behind **Options**. None of them is a verdict.
    private static func usePairs(_ use: MemoryUse) -> [DetailPair] {
        var pairs: [DetailPair] = [
            DetailPair("Installed memory", use.installedText),
            DetailPair("Memory pressure", use.pressure.word),
        ]

        if let swapText = use.swapText {
            pairs.append(DetailPair("Swapped to disk", swapText))
        }
        if let compressed = use.compressedText {
            pairs.append(DetailPair("Compressed", compressed))
        }
        return pairs
    }

    /// What was closed, and what merely stopped.
    ///
    /// The second list is the one that keeps this row honest. Apple's own crash reporter hitting
    /// its own memory cap is a true event, it is not a fault, and leaving it out entirely would
    /// mean the Options panel disagreed with anybody who went and read the folder themselves.
    private static func closurePairs(_ closures: [Closure], window: Window) -> [DetailPair] {
        var pairs: [DetailPair] = []

        if let sentence = window.sentence {
            pairs.append(DetailPair("Reports go back to", sentence))
        }

        let outOfMemory = closures.filter { $0.kind == .ranOutOfMemory }
        pairs.append(DetailPair("Closed to free memory",
                                outOfMemory.isEmpty
                                    ? "None \(window.clause)"
                                    : describe(outOfMemory)))

        let ownLimit = closures.filter { $0.kind == .ownLimit }
        if !ownLimit.isEmpty {
            pairs.append(DetailPair("Stopped for their own memory limit",
                                    describe(ownLimit)
                                    + ". macOS caps how much memory each program may take, and "
                                    + "stops one that goes past its own cap. This is not the Mac "
                                    + "running short."))
        }

        let unknown = closures.filter { $0.kind == .unknown }
        if !unknown.isEmpty {
            pairs.append(DetailPair("Stopped for another reason",
                                    unknown.map { "\($0.program) (\($0.reason))" }
                                        .joined(separator: ", ")))
        }
        return pairs
    }

    /// "ReportCrash (twice, most recently 26 Aug 2026), knowledgeconstructiond (25 Aug 2026)".
    ///
    /// Collapsed by name rather than listed one per line: the same program being reaped four times
    /// is one fact about that program, not four facts about the Mac.
    private static func describe(_ closures: [Closure]) -> String {
        var order: [String] = []
        var counts: [String: Int] = [:]
        var latest: [String: Date] = [:]

        for closure in closures.sorted(by: { $0.date > $1.date }) {
            if counts[closure.program] == nil { order.append(closure.program) }
            counts[closure.program, default: 0] += 1
            latest[closure.program] = max(latest[closure.program] ?? closure.date, closure.date)
        }

        return order.map { name in
            let when = latest[name].map(day) ?? ""
            switch counts[name] ?? 1 {
            case 1:  return "\(name) (\(when))"
            case 2:  return "\(name) (twice, most recently \(when))"
            default: return "\(name) (\(counts[name] ?? 0) times, most recently \(when))"
            }
        }.joined(separator: ", ")
    }

    // MARK: - How this Mac is using its memory

    /// The live numbers, all from `sysctl` and Mach, none of them needing a permission.
    struct MemoryUse: Sendable, Hashable {
        let installedBytes: UInt64
        let pressure: Pressure
        let swapUsedBytes: UInt64?
        let swapTotalBytes: UInt64?
        let compressedBytes: UInt64?

        static func current() -> MemoryUse {
            let swap = MemoryReader.swapUsage()
            return MemoryUse(
                installedBytes: ProcessInfo.processInfo.physicalMemory,
                pressure: Pressure(level: VirtualMachine.sysctlInt("kern.memorystatus_vm_pressure_level")),
                swapUsedBytes: swap?.used,
                swapTotalBytes: swap?.total,
                compressedBytes: MemoryReader.compressedBytes()
            )
        }

        var installedText: String {
            installedBytes > 0
                ? MemoryReader.gigabytes(installedBytes)
                : Unreadable.notReported.sentence
        }

        /// "1.6 GB of 2 GB set aside", or "None" — swap files exist and hold nothing on a Mac with
        /// room to spare, and "0 GB" reads like a failed measurement.
        var swapText: String? {
            guard let swapUsedBytes else { return nil }
            guard swapUsedBytes > 0 else { return "None" }
            guard let swapTotalBytes, swapTotalBytes > 0 else {
                return MemoryReader.gigabytes(swapUsedBytes)
            }
            return "\(MemoryReader.gigabytes(swapUsedBytes)) of "
                 + "\(MemoryReader.gigabytes(swapTotalBytes)) set aside"
        }

        var compressedText: String? {
            guard let compressedBytes, compressedBytes > 0 else { return nil }
            return MemoryReader.gigabytes(compressedBytes)
        }
    }

    /// The kernel's own view of memory pressure, in the three states it publishes.
    ///
    /// ⚠️ Not Activity Monitor's graph, which is a different calculation over the same machine.
    /// This is `kern.memorystatus_vm_pressure_level`: the value the kernel itself acts on when it
    /// decides to start closing things, which makes it the right one for a row about closings.
    enum Pressure: Sendable, Hashable {
        case normal, warning, critical, unknown

        init(level: Int?) {
            switch level {
            case 1:  self = .normal
            case 2:  self = .warning
            case 4:  self = .critical
            default: self = .unknown
            }
        }

        /// Words, not a percentage. See the header.
        var word: String {
            switch self {
            case .normal:   "Normal"
            case .warning:  "Under pressure"
            case .critical: "Critical"
            case .unknown:  Unreadable.notReported.sentence
            }
        }
    }

    /// The one sentence about pressure, for whichever branch needs it.
    ///
    /// `.warning` is stated and never flagged: it is a normal, passing state on any busy Mac, and a
    /// status chip that flips between Good and Needs attention depending on what was open when the
    /// app launched is a chip nobody believes twice.
    private static func pressureSentence(_ use: MemoryUse) -> String {
        switch use.pressure {
        case .normal:
            return "Memory is not under pressure right now."
        case .warning:
            return "Memory is under pressure right now — macOS is compressing memory to keep "
                 + "everything running, which is what it is meant to do."
        case .critical:
            return "Memory is critically short right now, which is the state macOS starts closing "
                 + "things in."
        case .unknown:
            return "This Mac does not report how hard its memory is working."
        }
    }

    private static func pressureSeverity(_ use: MemoryUse) -> Severity {
        use.pressure == .critical ? .attention : .information
    }

    /// `vm.swapusage`, the same figures `sysctl` prints.
    private static func swapUsage() -> (used: UInt64, total: UInt64)? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return (used: usage.xsu_used, total: usage.xsu_total)
    }

    /// How much memory the compressor is holding, in bytes.
    ///
    /// This is the part of "8 GB is enough" that is invisible in Activity Monitor's headline: on a
    /// Mac this size, two gigabytes of what is nominally in memory is actually compressed.
    private static func compressedBytes() -> UInt64? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size
                                           / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        // `vm_kernel_page_size` is a mutable global, which Swift 6 will not let a concurrent
        // program read. `hw.pagesize` is the same number — 16,384 on Apple silicon, 4,096 on Intel
        // — read the same way every other machine fact in this section is read.
        let pageSize = UInt64(VirtualMachine.sysctlInt("hw.pagesize") ?? 4_096)
        return UInt64(stats.compressor_page_count) * pageSize
    }

    // MARK: - Reading the folder

    /// One time macOS shut a running program down. Nothing here is a conclusion.
    struct Closure: Sendable, Hashable {
        let date: Date
        /// The program's name **as the kernel recorded it**, which it truncates to 31 characters —
        /// `VoiceMemosSettingsWidgetExtensio` is a real example. Shown as recorded rather than
        /// tidied: an invented ending would be a guess about which program it was.
        let program: String
        /// The kernel's own word for why, kept verbatim so an unfamiliar one can still be shown.
        let reason: String
        let kind: Kind
    }

    /// What a kill reason actually means. See the table in the header.
    enum Kind: Sendable, Hashable {
        /// The Mac was short of memory and something had to go. The only kind the headline counts.
        case ranOutOfMemory
        /// One program went past the cap macOS sets for it. Says nothing about the Mac.
        case ownLimit
        /// Routine tidying — an idle program closed, a file-handle limit. Not shown at all.
        case housekeeping
        /// A reason this build has never seen. Shown, in the kernel's own words, rather than
        /// silently filed under one of the above.
        case unknown

        /// ⚠️ Matched on the kernel's strings, normalised for punctuation only. Adding a guess
        /// here is how "the Mac ran out of memory" gets printed about something else.
        init(reason: String) {
            let key = reason.lowercased()
                .replacingOccurrences(of: "_", with: "-")
                .trimmingCharacters(in: .whitespaces)
            switch key {
            case "vm-pageshortage", "vm-thrashing", "proc-thrashing", "fc-thrashing",
                 "vm-compressor-thrashing", "vm-compressor-space-shortage", "vm-pageout-starvation",
                 "low-swap", "lowswap", "sustained-memory-pressure", "zone-map-exhaustion",
                 "memory-pressure":
                self = .ranOutOfMemory
            case "per-process-limit", "memory-limit", "highwater", "high-watermark":
                self = .ownLimit
            case "idle-exit", "vnode-limit", "disk-space-shortage", "fc-quota",
                 "processor-set-limit":
                self = .housekeeping
            default:
                self = .unknown
            }
        }
    }

    /// How far back the folder can actually see, and how to say it.
    struct Window: Sendable, Hashable {
        /// The oldest report of any kind still in the folder, never earlier than `longestWindow`.
        /// `nil` when the folder holds none at all.
        let oldestReport: Date?
        /// When the check ran. Carried so the sentence is arithmetic on the run, not on the draw —
        /// a window computed at render time would creep by a day while the app sat open overnight.
        let ranAt: Date

        /// "in the last 7 days", or the honest fallback when there is nothing to measure against.
        var clause: String {
            guard let oldestReport else { return "in the reports macOS still keeps" }
            let days = max(1, Int((ranAt.timeIntervalSince(oldestReport) / 86_400).rounded()))
            return days == 1 ? "in the last day" : "in the last \(days) days"
        }

        /// The date itself, for the Options row.
        var sentence: String? { oldestReport.map(day) }
    }

    enum Survey: Sendable {
        /// The folder is not there at all.
        case missing
        /// The folder is there and this account may not open it. See the file header.
        case refused
        case surveyed(closures: [Closure], window: Window)
    }

    /// List the folder, and read the jetsam reports in it.
    ///
    /// ⚠️ The distinction between `.missing` and `.refused` is the whole point of the walk.
    /// `/Library/Logs` is world-readable, so a `stat` on the folder succeeds for every account and
    /// only the listing fails. That is what tells "there is nothing to read" apart from "we are
    /// not allowed to read it", and those two answers must never be shown as the same thing.
    static func survey(now: Date = Date(),
                       folder: URL = systemReports,
                       fileManager: FileManager = .default) -> Survey {
        let exists = (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        guard exists else { return .missing }

        guard let entries = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey,
                                         .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return .refused
        }

        var oldest: Date?
        var candidates: [(url: URL, date: Date)] = []

        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.creationDateKey,
                                                             .contentModificationDateKey,
                                                             .isRegularFileKey])
            // Only files. This folder also holds `Retired` and `DiagnosticLogs` — folders whose
            // own dates are months older than anything in them, and which would stretch the window
            // to a year the reports themselves cannot back up.
            guard values?.isRegularFile == true else { continue }
            guard let stamp = values?.creationDate ?? values?.contentModificationDate else { continue }

            // The oldest report of ANY kind is the honest bound on how far back macOS still lets
            // us see. Using only jetsam reports would make a Mac that has never run short look as
            // though its clean record went back for ever.
            oldest = min(oldest ?? stamp, stamp)

            if entry.pathExtension.lowercased() == "ips" {
                candidates.append((entry, stamp))
            }
        }

        // The furthest back this row will look, and the furthest back it will claim. Nothing else
        // bounds it: a folder holding one forgotten report from two years ago must not turn
        // "nothing has been closed" into a promise about two years.
        let start = now.addingTimeInterval(-longestWindow)
        var closures: [Closure] = []
        var opened = 0

        for candidate in candidates.sorted(by: { $0.date > $1.date }) where candidate.date >= start {
            guard opened < mostReportsRead else { break }
            // Only a report that turned out to be a jetsam one counts against the budget. Most
            // `.ips` files in this folder are something else, and their header peek costs a page
            // fault — spending the budget on them would let sixty crash reports crowd out the
            // three files this row exists to read.
            guard let found = closureRecords(at: candidate.url, fallbackDate: candidate.date) else {
                continue
            }
            opened += 1
            closures += found
        }

        // A closure we actually read is itself proof the record reaches back that far, and on a
        // report that was copied or restored the stamp inside the file is the truthful one. The
        // window is the earlier of the two, so the sentence can never claim a shorter memory than
        // the events it just listed.
        let earliestFound = closures.map(\.date).min()
        let bound = [oldest, earliestFound].compactMap { $0 }.min().map { max($0, start) }
        let window = Window(oldestReport: bound, ranAt: now)
        return .surveyed(closures: closures.filter { $0.kind != .housekeeping }, window: window)
    }

    // MARK: - Reading one report

    /// The closings recorded in one file, or `nil` for one of the sixty other things macOS files
    /// in this folder.
    ///
    /// `nil` and `[]` are different answers on purpose: `nil` means this was not a jetsam report at
    /// all, and `[]` means it was one and named nobody — which does happen, and is not the same as
    /// not looking.
    ///
    /// A jetsam report is a snapshot of **every** process alive at the moment of the kill — 750
    /// entries here — of which the one or two that were actually closed carry a `reason`. So the
    /// header is checked first, on a memory-mapped file, and the 400 KB body is only parsed once
    /// `bug_type` says this is the right kind of report. The type is read from the header rather
    /// than from the file name, so a rename by Apple costs us nothing.
    static func closureRecords(at url: URL, fallbackDate: Date) -> [Closure]? {
        guard url.pathExtension.lowercased() == "ips",
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              let newline = data.firstIndex(of: 0x0A) else { return nil }

        let headerData = data[data.startIndex..<newline]
        guard let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              (header["bug_type"] as? String) == jetsamBugType else { return nil }

        let bodyData = data[data.index(after: newline)...]
        guard let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let processes = body["processes"] as? [[String: Any]] else { return [] }

        let when = date(from: header["timestamp"] as? String)
            ?? date(from: body["date"] as? String)
            ?? fallbackDate

        return processes.compactMap { process in
            guard let reason = process["reason"] as? String, !reason.isEmpty,
                  let name = process["name"] as? String, !name.isEmpty else { return nil }
            return Closure(date: when, program: name, reason: reason, kind: Kind(reason: reason))
        }
    }

    /// `bug_type` 298 is the jetsam report. 210 is the kernel panic, which belongs to
    /// `RestartReader`, and the other fifty-odd numbers in this folder are performance notices
    /// where nothing was closed at all.
    static let jetsamBugType = "298"

    /// "2026-08-26 06:09:19.00 -0600" → a `Date`.
    ///
    /// The file's own date would nearly always do, and it is the fallback. This is preferred
    /// because a report copied or restored from a backup carries the wrong file date and the right
    /// stamp inside it, and "macOS closed Safari today" about something that happened in March is
    /// a worse error than a missing minute.
    static func date(from stamp: String?) -> Date? {
        guard let stamp, !stamp.isEmpty else { return nil }
        // Built per call rather than stored: `DateFormatter` is not `Sendable`, and one shared
        // across threads is a data race that shows up as a wrong year rather than as a crash.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss.SS Z", "yyyy-MM-dd HH:mm:ss Z"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: stamp) { return date }
        }
        return nil
    }

    // MARK: - Words

    /// "12 Aug 2026", in the reader's own region.
    private static func day(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    /// "a, b and c" — a list in a sentence, not a comma-separated dump.
    private static func list(_ items: [String]) -> String {
        switch items.count {
        case 0:  return ""
        case 1:  return items[0]
        case 2:  return "\(items[0]) and \(items[1])"
        default: return "\(items.dropLast().joined(separator: ", ")) and \(items[items.count - 1])"
        }
    }

    /// "1.6 GB", "8 GB" — binary gigabytes, because that is the unit macOS itself reports memory
    /// in, and a memory row that disagreed with Activity Monitor would be checked against it and
    /// found wrong.
    fileprivate static func gigabytes(_ bytes: UInt64) -> String {
        let value = Double(bytes) / 1_073_741_824
        if value >= 10 || abs(value - value.rounded()) < 0.05 {
            return "\(Int(value.rounded())) GB"
        }
        return String(format: "%.1f GB", value)
    }
}

import Foundation
import WellkeptCore

//  RestartReader.swift
//  Wellkept — App/Hardware
//
//  **Has the whole Mac crashed or restarted on its own?**
//
//  ## What this row is, and what it deliberately is not
//
//  It is kernel panics: the machine itself stopping and coming back. It is **not app crashes**.
//  A normal, healthy Mac accumulates something over a hundred diagnostic files in a week — this
//  one had 61, of which not one was a panic and three were memory-pressure notices where nothing
//  crashed at all. Counting those here would put a three-figure number on the Hardware panel of a
//  Mac with nothing wrong with it. Safari quitting says nothing about whether this machine is
//  healthy, so app crashes belong to the Apps section and this row never mentions them.
//
//  ## ⚠️ Never attribute a panic to failing hardware unless the panic itself says so
//
//  This is the one rule that matters in this file. A panic report says what the kernel was doing
//  when it stopped; it almost never says what was wrong. Telling somebody their memory is failing
//  when the real cause was a third-party kernel extension is the worst thing this section could
//  do — it is an accusation against a component, it costs money to act on, and it is usually
//  wrong.
//
//  So this file diagnoses nothing. It reports **how many, when**, and, verbatim, the panic's own
//  first line and whatever kernel extensions the panic itself named in its backtrace. The one
//  exception is a phrase that *is* the machine reporting its own hardware error — an Intel
//  machine-check exception, an uncorrectable ECC error — and even then the wording says the
//  report names it, not that we concluded it. See `hardwareFaultPhrases`, which is short on
//  purpose.
//
//  ## ⚠️ Readable only by administrator accounts, and no permission fixes it
//
//  `/Library/Logs/DiagnosticReports` is `drwxrwx--- root:_analyticsusers`, and `_analyticsusers`
//  nests the `admin` group — verified on this Mac, 2026-08-27. So it is **the kind of account you
//  sign in with** that decides this, not Full Disk Access and not any privacy setting. There is
//  no switch to offer and no button that would help, which is exactly the case `Unreadable`
//  allows to carry no remedy.
//
//  A standard user therefore gets `.notPermitted`, which makes the Hardware check incomplete.
//  That is accepted, and the alternative was never on the table: reporting "no unexpected
//  restarts" because we were not allowed to look is the confident wrong answer this whole product
//  exists to avoid.
//
//  ## What we still cannot see, and say so
//
//  macOS prunes this folder. On this Mac the oldest surviving report of any kind was eight days
//  old, so "nothing here" is a claim about eight days, not about the machine's life. The row
//  states the date it can see back to rather than implying it looked further. And a restart caused
//  by a power cut, a held power button or a dead battery writes no report at all — there is no
//  interface that distinguishes those from a clean shutdown, so the row says a power cut leaves
//  nothing behind rather than counting it as a clean record.
//
//  Nothing here launches a subprocess and nothing here needs Full Disk Access.

enum RestartReader {

    /// Where macOS files the reports that belong to the whole machine.
    ///
    /// The per-user folder — `~/Library/Logs/DiagnosticReports` — is deliberately not consulted.
    /// It holds app crashes, which are the Apps section's business.
    static let systemReports = URL(filePath: "/Library/Logs/DiagnosticReports",
                                   directoryHint: .isDirectory)

    // MARK: - The row

    /// Read the Restarts row.
    ///
    /// Injectable so a test can point it at a folder of fixtures: on a healthy Mac there is
    /// nothing to read, and a reader that can only be exercised on a broken machine is a reader
    /// nobody exercises.
    static func read(now: Date = Date(),
                     folder: URL = systemReports,
                     fileManager: FileManager = .default) -> Reading {
        switch survey(folder: folder, fileManager: fileManager) {

        case .missing:
            return .unreadable(.restarts, .notReported,
                               about: "Unexpected restarts",
                               reason: "macOS has not created the folder these reports live in.")

        case .refused:
            return .unreadable(.restarts, .notPermitted,
                               about: "Unexpected restarts",
                               reason: "Only an administrator account can read this Mac's restart "
                                     + "reports. That is decided by the kind of account you sign "
                                     + "in with, not by a privacy setting, so there is nothing to "
                                     + "switch on.",
                               details: [DetailPair("Reports live in", folder.path)])

        case let .surveyed(panics, oldestReport):
            return row(panics: panics, oldestReport: oldestReport, now: now)
        }
    }

    // MARK: - Building the row

    private static func row(panics: [PanicRecord], oldestReport: Date?, now: Date) -> Reading {
        let found = panics.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        let recentWeek = found.filter { $0.happened(after: now.addingTimeInterval(-7 * 86_400)) }.count
        let recentMonth = found.filter { $0.happened(after: now.addingTimeInterval(-30 * 86_400)) }.count
        let lastHardware = found.first { $0.namesHardwareFault }?.date
        let hardwareRecently = found.contains {
            $0.namesHardwareFault && $0.happened(after: now.addingTimeInterval(-30 * 86_400))
        }

        // ⚠️ How far back we can see is the *older* of the two: the oldest report macOS still
        // keeps, and the oldest panic we found. A surviving panic from 2024 next to a line saying
        // reports only go back a week is a row arguing with itself.
        let window = ([oldestReport] + found.map(\.date)).compactMap { $0 }.min()

        // ⚠️ A restart months ago on a machine that has been fine since is history, not a fault —
        // "worn but working is never a problem". What earns `.problem` is a pattern inside a week,
        // or a report that named a hardware fault **recently**.
        //
        // A hardware fault named two years ago and never repeated deliberately does NOT: it is
        // stated in plain words and left at `.information`. Otherwise a single surviving report
        // would put a red badge on a working Mac for the rest of its life, with no action on earth
        // that could clear it — and a warning nobody can clear is how an app teaches people to
        // ignore its warnings.
        let severity: Severity
        if hardwareRecently || recentWeek >= 3 {
            severity = .problem
        } else if recentMonth >= 2 {
            severity = .attention
        } else {
            severity = .information
        }

        return Reading(
            topic: .restarts,
            headline: headline(found),
            measure: found.isEmpty ? nil : "\(found.count)",
            number: ReadingNumber(Double(found.count), ReadingNumber.count),
            severity: severity,
            reason: reason(found,
                           recentWeek: recentWeek,
                           recentMonth: recentMonth,
                           hardwareRecently: hardwareRecently,
                           lastHardware: lastHardware,
                           window: window),
            details: details(found, window: window)
        )
    }

    private static func headline(_ found: [PanicRecord]) -> String {
        switch found.count {
        case 0:
            return "This Mac has not restarted on its own."
        case 1:
            guard let when = found[0].date else { return "This Mac has restarted on its own once." }
            return "This Mac restarted on its own once, on \(day(when))."
        default:
            return "This Mac has restarted on its own \(found.count) times."
        }
    }

    /// Why the row says what it says — shown on the row, never behind a disclosure.
    ///
    /// Every branch names the limit of what was looked at. "Nothing found" is a claim about a
    /// window macOS chose, and a claim about eight days that reads like a claim about a lifetime
    /// is the kind of thing a person only finds out was wrong at the worst moment.
    private static func reason(_ found: [PanicRecord],
                               recentWeek: Int,
                               recentMonth: Int,
                               hardwareRecently: Bool,
                               lastHardware: Date?,
                               window: Date?) -> String {
        guard !found.isEmpty else {
            guard let window else {
                return "macOS keeps these reports only for a while, and this Mac has none of any "
                     + "kind. A power cut leaves no report at all."
            }
            return "Nothing since \(day(window)), which is as far back as macOS keeps these "
                 + "reports. A power cut leaves no report at all."
        }

        if hardwareRecently {
            return "One of the reports names a hardware fault in its own words. That is worth "
                 + "showing a technician — it is the report's conclusion, not ours."
        }
        if recentWeek >= 3 {
            return "\(recentWeek) of them in the last week. The reports say what the machine was "
                 + "doing when it stopped, not what is wrong; a technician can read them."
        }
        if recentMonth >= 2 {
            return "\(recentMonth) in the last 30 days. Nothing in the reports says the machine "
                 + "itself is faulty."
        }
        if let lastHardware {
            return "A report from \(day(lastHardware)) names a hardware fault in its own words, "
                 + "and it has not happened again since."
        }
        if found.count == 1 {
            return "One restart is not a pattern, and nothing in the report says the machine is "
                 + "faulty."
        }
        return "None in the last 30 days, and nothing in the reports says the machine is faulty."
    }

    /// The most anybody would want behind **Options**: when each one happened, and what its own
    /// report said about it.
    private static func details(_ found: [PanicRecord], window: Date?) -> [DetailPair] {
        var pairs: [DetailPair] = []

        if let window {
            pairs.append(DetailPair("Reports go back to", day(window)))
        }

        // Eight is enough to see a pattern. A Mac in a boot loop can write dozens, and a
        // disclosure that unrolls forty near-identical lines is a disclosure nobody reads.
        let shown = found.prefix(8)
        var used = Set<String>()
        for panic in shown {
            let stamp = panic.date.map(ShortDate.stamp) ?? "Date not recorded"
            // `DetailPair.id` is the label, so two panics inside the same minute — which is
            // exactly what a boot loop produces — would collide in a list.
            var label = stamp
            var suffix = 2
            while !used.insert(label).inserted {
                label = "\(stamp) (\(suffix))"
                suffix += 1
            }

            var value = panic.cause ?? "The report gives no reason."
            if !panic.extensions.isEmpty {
                value += " The report names: \(panic.extensions.joined(separator: ", "))."
            }
            pairs.append(DetailPair(label, value))
        }

        if found.count > shown.count {
            let older = found.count - shown.count
            let boundary = found[shown.count - 1].date.map { ", before \(day($0))" } ?? ""
            pairs.append(DetailPair("Older restarts", "\(older) more\(boundary)."))
        }

        return pairs
    }

    // MARK: - Reading the folder

    enum Survey: Sendable {
        /// The folder is not there at all.
        case missing
        /// The folder is there and this account may not open it. See the file header.
        case refused
        case surveyed(panics: [PanicRecord], oldestReport: Date?)
    }

    /// What one kernel panic report says about itself. Nothing here is a conclusion.
    struct PanicRecord: Sendable, Hashable {
        /// When it happened. `nil` where no source in the report or its name gave a date —
        /// vanishingly rare, and never faked, because a panic dated today that actually happened
        /// in 2024 is worse than a panic with no date.
        let date: Date?
        /// The panic's own first line, condensed. `nil` where the report has no readable one.
        let cause: String?
        /// The kernel extensions the panic named **in its backtrace** — not everything that
        /// happened to be loaded, which on any Mac is a list of two hundred innocent drivers.
        let extensions: [String]
        /// Set only where the report itself names a hardware error. See `hardwareFaultPhrases`.
        let namesHardwareFault: Bool
        let file: URL

        /// An undated panic counts towards the total and towards no window. It is a restart we
        /// know happened and cannot place, and pretending otherwise would put it in whichever
        /// window makes the row look worse or better.
        func happened(after moment: Date) -> Bool {
            guard let date else { return false }
            return date > moment
        }
    }

    /// List the folder and pick out the panics.
    ///
    /// The distinction between `.missing` and `.refused` is the whole point of the walk:
    /// `/Library/Logs` is world-readable, so a `stat` on the folder succeeds for everybody and
    /// only the listing fails. That is what lets us tell "there is nothing to read" apart from
    /// "we are not allowed to read it", and those two answers must never be shown as the same
    /// thing.
    static func survey(folder: URL = systemReports,
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

        var panics: [PanicRecord] = []
        var oldest: Date?

        for entry in entries {
            // ⚠️ Regular files only. This folder contains two long-lived subfolders — `Retired`
            // and `DiagnosticLogs` — created when the Mac was set up. Counting their dates made
            // the row claim a clean record going back nine months on a machine whose actual
            // reports went back seven days, which is the wrong direction to be wrong in.
            guard (try? entry.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }

            // The oldest report of ANY kind is the honest bound on how far back macOS still lets
            // us see. Using only panics would make a Mac that has never panicked look as though
            // its clean record went back for ever.
            if let stamp = fileDate(of: entry) {
                oldest = min(oldest ?? stamp, stamp)
            }
            if let panic = panicRecord(at: entry) {
                panics.append(panic)
            }
        }

        return .surveyed(panics: panics, oldestReport: oldest)
    }

    // MARK: - Reading one report

    /// A panic report, or `nil` for one of the sixty other things macOS files in this folder.
    ///
    /// Two shapes are accepted, because macOS has written both:
    ///
    /// - **Modern** — a one-line JSON header, then a JSON body. `bug_type` `210` is the kernel
    ///   panic. The header is checked rather than the file name so that a rename by Apple costs
    ///   us nothing.
    /// - **Legacy** — plain text beginning `panic(cpu …)`, with no header at all. Accepted on the
    ///   strength of the `.panic` extension, which is what those files have always had.
    ///
    /// The file is memory-mapped rather than read, so peeking at the header of a 400 KB jetsam
    /// report costs a page fault instead of 400 KB.
    static func panicRecord(at url: URL) -> PanicRecord? {
        let ext = url.pathExtension.lowercased()
        guard ext == "panic" || ext == "ips" else { return nil }

        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }

        let split = data.firstIndex(of: 0x0A)
        let headerData = split.map { data[data.startIndex..<$0] } ?? data
        let header = (try? JSONSerialization.jsonObject(with: headerData)) as? [String: Any]

        let bugType = (header?["bug_type"] as? String)
            ?? (header?["bug_type"] as? Int).map(String.init)

        // A `.ips` file is only a panic if it says so. `.panic` is taken at its word, because the
        // legacy files carry no header to ask.
        guard ext == "panic" || bugType == "210" else { return nil }

        let text = panicText(data: data, after: split)

        return PanicRecord(
            date: date(of: url, header: header, text: text),
            cause: text.flatMap(cause(inPanicString:)),
            extensions: text.map(kernelExtensions(inPanicString:)) ?? [],
            namesHardwareFault: text.map(namesHardwareFault(inPanicString:)) ?? false,
            file: url
        )
    }

    /// The panic string, whichever way this report carries it.
    ///
    /// Apple silicon writes `macOSPanicString`, Intel writes `panicString`, and the legacy files
    /// are the panic string with no JSON around it. A modern report is mostly a base64 stackshot
    /// — a megabyte or more — so only the body is parsed and only the one key is kept; the rest
    /// is left mapped and never touched.
    private static func panicText(data: Data, after newline: Data.Index?) -> String? {
        if let newline {
            let body = data[data.index(after: newline)...]
            if let object = try? JSONSerialization.jsonObject(with: body),
               let fields = object as? [String: Any] {
                if let string = fields["macOSPanicString"] as? String { return string }
                if let string = fields["panicString"] as? String { return string }
            }
        }
        // Legacy, or a body we could not parse. The panic string is at the top of those files, so
        // the first 64 KB is all of it and then some.
        let head = String(decoding: data.prefix(64 * 1024), as: UTF8.self)
        return head.contains("panic(") ? head : nil
    }

    /// The panic's own first line, condensed onto one line.
    ///
    /// ⚠️ Verbatim, never interpreted. `panic(cpu 4 caller 0x…): Kernel data abort` is handed
    /// straight through: it is meaningless to most people and precisely what a technician asks
    /// for, and anything we did to make it friendlier would be us guessing at a cause.
    static func cause(inPanicString text: String) -> String? {
        if let opening = text.range(of: "panic("),
           let close = text.range(of: "): ", range: opening.upperBound..<text.endIndex) {
            let tail = text[close.upperBound...]
            let line = tail.prefix { !$0.isNewline }
            let condensed = condensed(String(line), limit: 200)
            if !condensed.isEmpty { return condensed }
        }
        guard let first = text.split(whereSeparator: \.isNewline).first else { return nil }
        let condensed = condensed(String(first), limit: 200)
        return condensed.isEmpty ? nil : condensed
    }

    /// The kernel extensions the panic named in its backtrace, in the order it named them.
    ///
    /// The report also carries `kextsLoaded`, which is every extension on the machine and
    /// implicates none of them. Only the backtrace section is read, because that is the only
    /// place the panic itself points at anything.
    static func kernelExtensions(inPanicString text: String) -> [String] {
        guard let marker = text.range(of: "Kernel Extensions in backtrace",
                                      options: .caseInsensitive) else { return [] }

        // The marker's own line ends with a colon and the list starts on the next one. Scanning
        // from the marker itself made the first "line" the string ":", which matched nothing and
        // ended the scan before it began.
        let tail = text[marker.upperBound...]
        guard let newline = tail.firstIndex(where: \.isNewline) else { return [] }

        var found: [String] = []
        // Empty subsequences are kept, because a blank line is what ends the list.
        let lines = tail[tail.index(after: newline)...]
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)

        for line in lines.prefix(16) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            // Each named extension is followed by its dependencies, indented. They were not in
            // the backtrace and naming them would widen an accusation we are not making.
            if trimmed.hasPrefix("dependency:") { continue }

            // Every entry has the shape `com.foo.bar(1.2.3)[UUID]@0x…`. Requiring the bracket is
            // what stops the scan running on into whatever section follows and reporting the
            // machine's entire loaded-kext list — two hundred innocent drivers — as implicated.
            guard let stop = trimmed.firstIndex(where: {
                      $0 == "(" || $0 == "[" || $0 == "@" || $0.isWhitespace
                  }),
                  trimmed[stop] == "(" || trimmed[stop] == "[" else { break }

            let name = String(trimmed[..<stop])
            guard name.contains("."),
                  name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" })
            else { break }

            if !found.contains(name) { found.append(name) }
            if found.count == 5 { break }
        }
        return found
    }

    /// Phrases that are the machine reporting its own hardware error, rather than us deciding one.
    ///
    /// ⚠️ **Deliberately three entries long, and it should stay that way.** A machine-check
    /// exception and an uncorrectable ECC error are the CPU and the memory controller saying, in
    /// their own words, that a component failed. Everything else a panic contains — a watchdog
    /// timeout, a sleep-wake failure, a kernel trap — is compatible with a driver bug, and adding
    /// it here would turn this row into an accusation against somebody's memory over a piece of
    /// software.
    static let hardwareFaultPhrases = ["machine check", "uncorrectable", "ecc error"]

    static func namesHardwareFault(inPanicString text: String) -> Bool {
        let lowered = text.lowercased()
        return hardwareFaultPhrases.contains { lowered.contains($0) }
    }

    // MARK: - Dates, without a formatter

    /// When the panic happened, best source first.
    ///
    /// The report's own timestamp is authoritative; the file name carries the same moment and
    /// survives a report whose header will not parse; the file's own date is the last resort and
    /// is the moment it was *written*, which for a panic is the boot afterwards.
    static func date(of url: URL, header: [String: Any]?, text: String?) -> Date? {
        if let raw = header?["timestamp"] as? String,
           let stamp = date(fromReportTimestamp: raw) { return stamp }
        if let stamp = date(fromFileName: url.lastPathComponent) { return stamp }
        return fileDate(of: url)
    }

    /// "2026-08-26 06:09:19.00 -0600".
    ///
    /// Parsed by hand rather than with a `DateFormatter`. A formatter is not `Sendable`, so it
    /// cannot be a shared constant under strict concurrency, and one built per file would need a
    /// fixed locale and a fixed calendar set correctly every time or it silently returns `nil` in
    /// somebody's region. The string is fixed-shape ASCII; taking it apart is six lines and has no
    /// locale at all.
    static func date(fromReportTimestamp raw: String) -> Date? {
        let parts = raw.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        let day = parts[0].split(separator: "-").compactMap { Int($0) }
        let time = parts[1].split(separator: ":").compactMap { Int($0.prefix { $0.isNumber }) }
        guard day.count == 3, time.count >= 3 else { return nil }

        var zone = TimeZone.current
        if parts.count >= 3, let seconds = zoneOffset(String(parts[2])),
           let named = TimeZone(secondsFromGMT: seconds) {
            zone = named
        }
        return date(year: day[0], month: day[1], day: day[2],
                    hour: time[0], minute: time[1], second: time[2], zone: zone)
    }

    /// "Kernel_2026-08-26-060919_Johns-MacBook-Air.panic" → the moment in the name.
    ///
    /// The name carries no time zone, because it was written in local time on this machine, which
    /// is the zone we want anyway.
    static func date(fromFileName name: String) -> Date? {
        let characters = Array(name)
        guard characters.count >= 17 else { return nil }

        for start in 0...(characters.count - 17) {
            let slice = Array(characters[start..<(start + 17)])
            let digits = [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 13, 14, 15, 16]
            guard digits.allSatisfy({ slice[$0].isNumber }),
                  slice[4] == "-", slice[7] == "-", slice[10] == "-" else { continue }

            func number(_ range: Range<Int>) -> Int {
                Int(String(slice[range])) ?? 0
            }
            return date(year: number(0..<4), month: number(5..<7), day: number(8..<10),
                        hour: number(11..<13), minute: number(13..<15), second: number(15..<17),
                        zone: .current)
        }
        return nil
    }

    private static func date(year: Int, month: Int, day: Int,
                             hour: Int, minute: Int, second: Int,
                             zone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        parts.second = second
        return calendar.date(from: parts)
    }

    /// "-0600" → -21600.
    private static func zoneOffset(_ raw: String) -> Int? {
        let sign: Int
        var body = Substring(raw)
        switch body.first {
        case "-": sign = -1; body = body.dropFirst()
        case "+": sign = 1;  body = body.dropFirst()
        default:  return nil
        }
        body = Substring(body.replacingOccurrences(of: ":", with: ""))
        guard body.count == 4,
              let hours = Int(body.prefix(2)),
              let minutes = Int(body.suffix(2)) else { return nil }
        return sign * (hours * 3_600 + minutes * 60)
    }

    private static func fileDate(of url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.creationDateKey,
                                                       .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate
    }

    // MARK: - Words

    /// "12 Aug 2026", in the reader's own region.
    private static func day(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    /// One line, no runs of whitespace, no longer than `limit`.
    ///
    /// A panic's first line arrives with tabs and hard wraps in it. Left alone it would take four
    /// lines of a disclosure and still be cut off.
    private static func condensed(_ text: String, limit: Int) -> String {
        let single = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard single.count > limit else { return single }
        return single.prefix(limit).trimmingCharacters(in: .whitespaces) + "…"
    }
}

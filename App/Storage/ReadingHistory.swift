import Foundation
import WellkeptCore

//  ReadingHistory.swift
//  Wellkept — App/Storage
//
//  **Wellkept's own record of every reading it has ever taken on this Mac.**
//
//  ## Why this exists before anything reads it
//
//  Nothing in this version reads it back. It is written anyway, from the first launch, because
//  **it cannot be back-filled.** macOS keeps about eight days of diagnostic history and throws the
//  rest away; Apple's battery percentage is a single current number with no past attached; the
//  drive reports a speed only when you measure it. Every one of the sentences this section
//  eventually wants is subtraction against a number nobody kept:
//
//  - "This drive is slower than it used to be" — the only honest comparison available, since the
//    shipped table of expected speeds ruled out would have been a manufacturer's guess.
//  - "The battery has lost four points since March."
//  - "This Mac runs hot more often than it did." (macOS reports thermal *pressure*, never a
//    temperature we would trust — the die reading moved 62 → 79 → 58 °C in three minutes on an
//    idle machine, so what gets kept is how often macOS itself said things were tight.)
//  - "It has restarted on its own twice this year", on a system that remembers eight days.
//
//  A version that starts keeping this in eighteen months can say none of those for another two
//  years. A version that starts today can say all of them in six months. That asymmetry is the
//  whole argument, and it costs about two hundred bytes a launch.
//
//  ## What it is on disk
//
//  `~/Library/Application Support/Wellkept/Readings.jsonl` — one JSON object per line.
//
//  **Append-only, deliberately.** A line is written with a single `write` at the end of the file
//  and nothing is ever rewritten in place, so an interrupted launch costs at most the line being
//  written rather than the file. A JSON *array* would have to be parsed, re-encoded and rewritten
//  whole on every append: slower every launch, and a crash mid-rewrite would take the only copy
//  of a record that cannot be recreated.
//
//  ## ⚠️ Declared in `StorageManifest`, which is what stops the uninstaller going stale
//
//  This file's URL comes from `StorageManifest.readingHistory(home:)` and it has an `Entry` in
//  `StorageManifest.entries` marked `.delete`. Both were added the day this file was created. An
//  uninstaller that keeps its own list is a list that goes stale silently — the app is in the
//  Trash and its record is still on the disk, in a folder nobody would think to look in.

// MARK: - One recorded reading

/// One reading, as it was at one moment, in a form arithmetic can use.
///
/// ⚠️ **`value` is the point of the whole file.** `measure` is "1,240 cycles" — right for the eye
/// and useless for subtraction, and unparseable a year later in a different locale. `value` and
/// `unit` are the same fact as a number, which is what lets two runs be compared.
struct ReadingSample: Codable, Sendable, Hashable, Identifiable {

    let id: UUID
    let topic: HardwareTopic
    let takenAt: Date

    /// The formatted figure, kept alongside the number so a future screen can show exactly what
    /// the user was shown at the time rather than re-formatting an old value with new rules.
    let measure: String?
    /// The figure as arithmetic. `nil` where the reading has no number — Apple's S.M.A.R.T.
    /// verdict is a word.
    let value: Double?
    /// The unit symbol from `ReadingNumber`. Stored beside the value so a build that changes its
    /// mind about units cannot silently compare megabytes against gigabytes.
    let unit: String?

    let severity: Severity
    let status: SectionStatus
    /// Set where the reading could not be taken. **Kept rather than skipped**, because "this Mac
    /// stopped reporting its battery in April" is itself a finding, and a gap in the file is
    /// indistinguishable from an app that was not launched that week.
    let unreadable: Unreadable?

    /// The model identifier the reading was taken on.
    ///
    /// Migration Assistant carries `~/Library/Application Support` to a new Mac, so without this
    /// a battery history would silently splice two different machines into one line. A comparison
    /// across a change of machine is not a comparison.
    let machine: String?

    /// Wellkept's own version, so a change in how something is measured is visible as a change in
    /// the app rather than as a change in the Mac.
    let appVersion: String?

    init(id: UUID = UUID(),
         topic: HardwareTopic,
         takenAt: Date,
         measure: String?,
         value: Double?,
         unit: String?,
         severity: Severity,
         status: SectionStatus,
         unreadable: Unreadable?,
         machine: String?,
         appVersion: String? = ReadingHistory.appVersion) {
        self.id = id
        self.topic = topic
        self.takenAt = takenAt
        self.measure = measure
        self.value = value
        self.unit = unit
        self.severity = severity
        self.status = status
        self.unreadable = unreadable
        self.machine = machine
        self.appVersion = appVersion
    }

    /// One reading, as it was drawn on screen.
    init(_ reading: Reading, takenAt: Date, machine: String?) {
        self.init(topic: reading.topic,
                  takenAt: takenAt,
                  measure: reading.measure,
                  value: reading.number?.value,
                  unit: reading.number?.unit,
                  severity: reading.severity,
                  status: reading.status,
                  unreadable: reading.unreadable,
                  machine: machine)
    }
}

// MARK: - The file

enum ReadingHistory {

    /// `~/Library/Application Support/Wellkept/Readings.jsonl`.
    static func url(home: URL = StorageManifest.home()) -> URL {
        StorageManifest.readingHistory(home: home)
    }

    /// The app's own version, for `ReadingSample.appVersion`.
    static var appVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// Roughly four megabytes, which is about twenty thousand readings, which is about eleven
    /// years of launching this app every day.
    ///
    /// ⚠️ **The cap is a real loss and it is the one compromise in this file.** Trimming throws
    /// away the oldest records, and they are exactly the ones that cannot be recreated. The cap is
    /// set where it is because an unbounded file in a person's Application Support folder is the
    /// behaviour this whole app exists to catch other software doing, and because nobody has ever
    /// wanted a battery comparison against a Mac they owned eleven years ago.
    static let maximumBytes = 4 * 1024 * 1024

    /// What a trim keeps: the newest three quarters, so trimming happens rarely rather than on
    /// every launch once the file is full.
    private static let keepAfterTrimFraction = 0.75

    /// Appends are serialized. Two checks running at once would otherwise interleave halves of two
    /// lines and make both unreadable — and this file's whole value is that old lines stay
    /// readable.
    private static let lock = NSLock()

    // MARK: Writing

    /// Record every reading from one run.
    ///
    /// `machine` comes from the report, so a history carried to a new Mac by Migration Assistant
    /// stays honest about which machine each line describes.
    @discardableResult
    static func record(_ report: HardwareReport, home: URL = StorageManifest.home()) -> Bool {
        record(report.readings.map {
            ReadingSample($0, takenAt: report.ranAt, machine: report.facts.modelIdentifier)
        }, home: home)
    }

    /// Append samples to the file, creating it if this is the first launch.
    ///
    /// ⚠️ **Returns `false` rather than throwing, and callers ignore it.** A health check that
    /// fails because it could not write its own diary is worse than a gap in the diary — the user
    /// asked about their Mac, not about our bookkeeping. Nothing here is on the path of any
    /// answer the user sees.
    @discardableResult
    static func record(_ samples: [ReadingSample], home: URL = StorageManifest.home()) -> Bool {
        guard !samples.isEmpty else { return true }

        lock.lock()
        defer { lock.unlock() }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Sorted keys so a line is byte-stable for the same input. It makes the file diffable and
        // makes a corrupted line obvious next to its neighbours.
        encoder.outputFormatting = [.sortedKeys]

        var payload = Data()
        for sample in samples {
            guard let line = try? encoder.encode(sample) else { continue }
            payload.append(line)
            payload.append(0x0A)   // newline
        }
        guard !payload.isEmpty else { return false }

        let file = url(home: home)
        let manager = FileManager.default

        do {
            try manager.createDirectory(at: file.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
            if manager.fileExists(atPath: file.path) {
                let handle = try FileHandle(forWritingTo: file)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: payload)
            } else {
                try payload.write(to: file, options: .atomic)
            }
        } catch {
            return false
        }

        trimIfNeeded(home: home)
        return true
    }

    // MARK: Reading it back

    /// Everything on file, oldest first.
    ///
    /// **Nothing in this version calls this.** It exists so the file is testable the day it is
    /// written rather than the day something first needs it, and so that "append-only" is a
    /// property somebody can check rather than a claim in a comment.
    ///
    /// A line that will not decode is skipped rather than fatal. A future build that adds a field
    /// must not be able to make an old file unreadable, and one bad line must never cost the other
    /// twenty thousand.
    static func samples(home: URL = StorageManifest.home()) -> [ReadingSample] {
        lock.lock()
        defer { lock.unlock() }
        return decodeAll(home: home)
    }

    /// One topic's history, oldest first — the shape every future comparison wants.
    static func samples(of topic: HardwareTopic,
                        home: URL = StorageManifest.home()) -> [ReadingSample] {
        samples(home: home).filter { $0.topic == topic }
    }

    /// The most recent recorded reading for a topic, or `nil` on a Mac that has never run a check.
    static func latest(_ topic: HardwareTopic,
                       home: URL = StorageManifest.home()) -> ReadingSample? {
        samples(of: topic, home: home).last
    }

    // MARK: Housekeeping

    /// Rewrite the file keeping the newest lines, once it has grown past `maximumBytes`.
    ///
    /// Checks the file's size rather than counting its lines: one `stat` on every launch instead
    /// of parsing four megabytes to discover there is nothing to do.
    ///
    /// ⚠️ The rewrite is atomic. A trim that failed halfway would take the whole record with it,
    /// and the record is the one thing in this app that cannot be recreated by running the check
    /// again.
    private static func trimIfNeeded(home: URL) {
        let file = url(home: home)
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > maximumBytes else { return }

        let kept = decodeAll(home: home)
        let keep = Int(Double(kept.count) * keepAfterTrimFraction)
        guard keep > 0, keep < kept.count else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        var payload = Data()
        for sample in kept.suffix(keep) {
            guard let line = try? encoder.encode(sample) else { continue }
            payload.append(line)
            payload.append(0x0A)
        }
        try? payload.write(to: file, options: .atomic)
    }

    /// Decode the file, skipping anything that will not parse. Callers hold `lock`.
    private static func decodeAll(home: URL) -> [ReadingSample] {
        guard let data = try? Data(contentsOf: url(home: home)),
              let text = String(data: data, encoding: .utf8) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard let bytes = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(ReadingSample.self, from: bytes)
        }
    }
}

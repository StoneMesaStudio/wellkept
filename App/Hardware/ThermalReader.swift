import Foundation
import WellkeptCore

//  ThermalReader.swift
//  Wellkept — App/Hardware
//
//  **Is this Mac having to slow itself down to stay cool?**
//
//  ## ⚠️ No temperature, in degrees or anything else
//
//  A die temperature is readable on this Mac. It is not reported, and this is the settled reason:
//
//  - It moved **62 → 79 → 58 °C in three minutes** on an idle-ish machine. Whatever a person
//    happened to see would be a coin toss.
//  - The route to it is undocumented and closes whenever Apple reorganises the sensor keys. A
//    number that silently becomes wrong is worse than no number.
//  - **Nobody publishes what is too hot**, Apple included. So there is no honest sentence to put
//    beside the figure, and a number with no meaning attached is something a person can only
//    worry about.
//
//  What macOS *does* publish is `ProcessInfo.thermalState` — public since 10.10.3, free to read,
//  and it is the system's own answer to the only question worth asking: is this Mac having to
//  throttle itself. That is what this file reports, and the word "temperature" does not appear on
//  screen anywhere in the section.
//
//  ## Not a row. A decoration, or silence.
//
//  Thermal pressure is not one of the five Hardware rows, and `HardwareTopic` has no case for it.
//  It has no history of its own that a person would look up, and a sixth row saying "Nominal"
//  every day of the year is the definition of a warning nobody reads.
//
//  Instead it decorates the two rows it can actually explain — a Mac that is throttling is a Mac
//  whose disk benchmark comes back low and whose apps feel slow — and the rest of the time it says
//  nothing at all. `note` and `speedCaveat` are `nil` below `.serious` for exactly that reason.
//  `detail` is always available, because "we looked at this and it was fine" belongs in the audit
//  trail even when it does not belong on the screen.
//
//  ## Why it is recorded from the first launch
//
//  One reading tells you nothing. A hundred readings tell you whether this Mac is running hot more
//  than it used to, which is the one thermal sentence worth saying and the only one this app will
//  ever be able to say honestly. It cannot be back-filled — macOS keeps no such record — so the
//  recording starts on day one, years before anything reads it. See `ThermalHistory`.

// MARK: - What macOS says

/// macOS's own answer about thermal pressure, at one moment.
struct ThermalReading: Sendable, Hashable {

    /// The four states `ProcessInfo` reports, in order.
    ///
    /// Raw values are storage — they are written into `ThermalHistory`, which cannot be rebuilt —
    /// and the labels are English, free to change without a migration.
    enum Pressure: Int, Sendable, Hashable, Codable, CaseIterable, Comparable {
        /// Normal. The overwhelming majority of every reading ever taken.
        case nominal = 0
        /// Slightly warm. Utterly ordinary under load, and **not worth a word on screen**.
        case fair = 1
        /// macOS has started slowing things down to shed heat.
        case serious = 2
        /// macOS is doing everything it can, and may put the Mac to sleep.
        case critical = 3

        var label: String {
            switch self {
            case .nominal:  "Normal"
            case .fair:     "Slightly warm"
            case .serious:  "Running hot"
            case .critical: "Too hot"
            }
        }

        static func < (a: Pressure, b: Pressure) -> Bool { a.rawValue < b.rawValue }

        /// ⚠️ An unknown future state maps to `.fair`, not to `.nominal`.
        ///
        /// `.nominal` is a claim that everything is fine, and claiming that about a state we have
        /// never heard of would be inventing good news. `.fair` is recorded and stays silent,
        /// which is the honest middle: it neither reassures nor alarms on the strength of
        /// something we do not understand.
        init(_ state: ProcessInfo.ThermalState) {
            switch state {
            case .nominal:  self = .nominal
            case .fair:     self = .fair
            case .serious:  self = .serious
            case .critical: self = .critical
            @unknown default: self = .fair
            }
        }
    }

    let pressure: Pressure
    let takenAt: Date
    /// A guest reports `.nominal` for ever, whatever the host is doing. The flag exists so the
    /// section says so rather than reporting a machine that is fine because it is imaginary.
    let isVirtualMachine: Bool

    /// Whether macOS is actually throttling this Mac. Below `.serious` it is not.
    var isUnderPressure: Bool { !isVirtualMachine && pressure >= .serious }

    /// How much this matters to whichever row folds it in.
    ///
    /// A hot Mac is not a broken Mac — it may be in the sun, or compiling something — and this
    /// clears itself, which is exactly what a warning is allowed to do. `.critical` earns
    /// `.problem` because at that point macOS is about to take the machine away from you, and the
    /// person can act on it in the next thirty seconds.
    var severity: Severity {
        switch pressure {
        case .nominal, .fair: .information
        case .serious:        .attention
        case .critical:       .problem
        }
    }

    /// The sentence a row borrows when there is something to say. `nil` is the normal answer.
    var note: String? {
        guard !isVirtualMachine else { return nil }
        switch pressure {
        case .nominal, .fair:
            return nil
        case .serious:
            return "macOS says this Mac is running hot and has started slowing it down to cool off."
        case .critical:
            return "macOS says this Mac is too hot and is doing everything it can to cool it down."
        }
    }

    /// The caveat the Speed row puts under a figure measured while the Mac was throttling.
    ///
    /// Without it the speed test reports a slow drive on a machine whose drive is fine, and the
    /// person goes looking for a fault that is really an air vent.
    var speedCaveat: String? {
        isUnderPressure
            ? "This Mac was running hot while this was measured, so the figure is lower than it "
            + "would otherwise be."
            : nil
    }

    /// The line behind **Options**. Always present — a check that looked and found nothing still
    /// looked, and the audit trail is allowed to say so.
    var detail: DetailPair {
        isVirtualMachine
            ? DetailPair("Thermal pressure", Unreadable.notReported.sentence)
            : DetailPair("Thermal pressure", pressure.label)
    }

    /// What the reading means, for Help and for the Options disclosure.
    static let explanation =
        "macOS reports whether this Mac is having to slow itself down to stay cool. It does not "
        + "report a temperature anyone can act on, so Wellkept does not show one."
}

// MARK: - Reading it

enum ThermalReader {

    /// What macOS says right now. Free, synchronous, needs no permission, works on Intel and on
    /// Apple silicon alike.
    static func read(now: Date = Date()) -> ThermalReading {
        ThermalReading(pressure: ThermalReading.Pressure(ProcessInfo.processInfo.thermalState),
                       takenAt: now,
                       isVirtualMachine: VirtualMachine.current.isVirtual)
    }

    /// Read it and add it to Wellkept's own record.
    ///
    /// ⚠️ **This is the call the section makes once per check.** `read()` has no side effects on
    /// purpose, so nothing is written by drawing a screen; the recording is a separate, named act.
    @discardableResult
    static func readAndRecord(machine: String?,
                              now: Date = Date(),
                              home: URL = StorageManifest.home()) -> ThermalReading {
        let reading = read(now: now)
        ThermalHistory.record(reading, machine: machine, home: home)
        return reading
    }
}

// MARK: - Watching it change

/// **The worst thermal pressure seen over a stretch of time.**
///
/// A single `read()` before a disk benchmark and another after it can both come back `.nominal`
/// while the machine throttled hard in between — which is precisely when the benchmark is worth
/// discarding. macOS posts `thermalStateDidChangeNotification` on every transition, so watching is
/// the only way to know what happened during the measurement rather than at its edges.
///
/// Start it, do the work, read `peak`, `stop()`. The observer is removed on `deinit` as well, so
/// forgetting to stop leaks nothing.
final class ThermalWatch: @unchecked Sendable {

    private let lock = NSLock()
    /// Held so `stop()` and `deinit` unregister from the same centre `init` registered with. A
    /// second default argument on `stop` would have quietly leaked every watch built for a test
    /// centre.
    private let center: NotificationCenter
    private var peakRaw: Int
    private var token: NSObjectProtocol?

    /// Begin watching. The current state is the starting peak — a watch that began during a hot
    /// spell must not report `.nominal` merely because nothing changed while it looked.
    init(center: NotificationCenter = .default) {
        self.center = center
        peakRaw = ThermalReading.Pressure(ProcessInfo.processInfo.thermalState).rawValue

        // The notification carries nothing worth reading, and `ProcessInfo` is the documented way
        // to get the new value. Not touching the `Notification` keeps this closure free of
        // anything that is not `Sendable`.
        token = center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                                   object: nil,
                                   queue: nil) { [weak self] _ in
            self?.note(ProcessInfo.processInfo.thermalState)
        }
    }

    deinit { stop() }

    /// The worst state seen since the watch began, or since the last `reset()`.
    var peak: ThermalReading.Pressure {
        lock.lock()
        defer { lock.unlock() }
        return ThermalReading.Pressure(rawValue: peakRaw) ?? .fair
    }

    /// Whether macOS throttled this Mac at any point while the watch was running.
    var sawPressure: Bool { peak >= .serious }

    /// Forget what has been seen and start again from the current state.
    func reset() {
        let now = ThermalReading.Pressure(ProcessInfo.processInfo.thermalState).rawValue
        lock.lock()
        peakRaw = now
        lock.unlock()
    }

    /// Stop watching. Safe to call more than once, and `peak` keeps its answer afterwards.
    func stop() {
        lock.lock()
        let existing = token
        token = nil
        lock.unlock()
        if let existing { center.removeObserver(existing) }
    }

    private func note(_ state: ProcessInfo.ThermalState) {
        let raw = ThermalReading.Pressure(state).rawValue
        lock.lock()
        peakRaw = max(peakRaw, raw)
        lock.unlock()
    }
}

// MARK: - The record

/// One thermal reading, on disk.
struct ThermalSample: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    let takenAt: Date
    let pressure: ThermalReading.Pressure
    /// The model identifier this was read on. Migration Assistant carries Application Support to a
    /// new Mac, and a comparison that splices two machines into one line is not a comparison.
    let machine: String?
    let appVersion: String?

    init(id: UUID = UUID(),
         takenAt: Date,
         pressure: ThermalReading.Pressure,
         machine: String?,
         appVersion: String? = ReadingHistory.appVersion) {
        self.id = id
        self.takenAt = takenAt
        self.pressure = pressure
        self.machine = machine
        self.appVersion = appVersion
    }
}

/// **Wellkept's own record of how often this Mac has been under thermal pressure.**
///
/// ## ⚠️ Why this is not in `ReadingHistory`
///
/// It should be, and it cannot be. `ReadingSample` is keyed by `HardwareTopic`, and thermal
/// pressure is not one of the five topics — deliberately, since it is not a row. Filing it under a
/// topic it does not belong to would make `ReadingHistory.latest(.speed)` hand a thermal reading
/// to the reader that owns Speed, and a landmine in somebody else's history is a worse cost than a
/// second small file.
///
/// So it is a second small file, in the same folder, written the same way, capped the same way, and
/// declared in `StorageManifest` on the day it was created — which is what stops the uninstaller
/// from leaving it behind.
enum ThermalHistory {

    static func url(home: URL = StorageManifest.home()) -> URL {
        StorageManifest.thermalHistory(home: home)
    }

    /// Half a megabyte, which is roughly six thousand readings. A line here is about eighty bytes
    /// — a fraction of a `ReadingSample`, because there is only one number in it.
    static let maximumBytes = 512 * 1024

    /// What a trim keeps, so trimming happens rarely rather than on every launch once full.
    private static let keepAfterTrimFraction = 0.75

    /// Speaks only once there is enough to speak from.
    ///
    /// Twenty checks is not a statistic; it is the point below which a sentence about "usually"
    /// would be a sentence about three Tuesdays.
    static let minimumChecksForComparison = 20

    private static let lock = NSLock()

    // MARK: Writing

    /// Append one reading.
    ///
    /// ⚠️ Returns `false` rather than throwing, and callers ignore it. A health check that fails
    /// because it could not write its own diary is worse than a gap in the diary.
    @discardableResult
    static func record(_ reading: ThermalReading,
                       machine: String?,
                       home: URL = StorageManifest.home()) -> Bool {
        // A guest's thermal state is `.nominal` for ever, whatever the host is doing. Recording it
        // would fill the record with readings that mean nothing and quietly poison every future
        // comparison with them.
        guard !reading.isVirtualMachine else { return true }

        return record(ThermalSample(takenAt: reading.takenAt,
                                    pressure: reading.pressure,
                                    machine: machine),
                      home: home)
    }

    @discardableResult
    static func record(_ sample: ThermalSample, home: URL = StorageManifest.home()) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        guard var payload = try? encoder.encode(sample) else { return false }
        payload.append(0x0A)

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

    /// Everything on file, oldest first. A line that will not decode is skipped, never fatal.
    static func samples(home: URL = StorageManifest.home()) -> [ThermalSample] {
        lock.lock()
        defer { lock.unlock() }
        return decodeAll(home: home)
    }

    /// How often this Mac has been under thermal pressure, and since when.
    ///
    /// `machine` filters to one model identifier so a history carried across by Migration Assistant
    /// does not blend two machines. Pass `nil` to count everything.
    struct Summary: Sendable, Hashable {
        let checks: Int
        let underPressure: Int
        let since: Date
    }

    static func summary(machine: String?, home: URL = StorageManifest.home()) -> Summary? {
        let kept = samples(home: home).filter { machine == nil || $0.machine == machine }
        // The earliest date, not the first line. The file is appended in time order in practice,
        // but "in practice" is how a record that outlives several versions of this app ends up
        // reporting that it started keeping notes next Tuesday.
        guard let since = kept.map(\.takenAt).min() else { return nil }
        return Summary(checks: kept.count,
                       underPressure: kept.filter { $0.pressure >= .serious }.count,
                       since: since)
    }

    /// **"Hotter than usual for this Mac" — the one sentence this record exists to make possible.**
    ///
    /// It says nothing until there is something to say: no sentence below
    /// `minimumChecksForComparison`, and no sentence at all when the Mac is not currently under
    /// pressure, because "this is unusual" is only interesting about something that is happening.
    ///
    /// It states the count rather than a verdict. "6 of the last 40" lets a person decide whether
    /// that is a lot; "unusually hot" would be us deciding for them from a threshold nobody has
    /// measured.
    static func comparison(with reading: ThermalReading,
                           machine: String?,
                           home: URL = StorageManifest.home()) -> String? {
        guard reading.isUnderPressure,
              let summary = summary(machine: machine, home: home),
              summary.checks >= minimumChecksForComparison else { return nil }

        let when = summary.since.formatted(date: .abbreviated, time: .omitted)
        if summary.underPressure == 0 {
            return "Wellkept has not seen this Mac run hot before, in \(summary.checks) checks "
                 + "since \(when)."
        }
        return "Wellkept has seen this on \(summary.underPressure) of \(summary.checks) checks "
             + "since \(when)."
    }

    // MARK: Housekeeping

    /// Rewrite the file keeping the newest lines, once it has grown past `maximumBytes`.
    /// Atomic, because a trim that failed halfway would take the whole record with it.
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
    private static func decodeAll(home: URL) -> [ThermalSample] {
        guard let data = try? Data(contentsOf: url(home: home)),
              let text = String(data: data, encoding: .utf8) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard let bytes = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(ThermalSample.self, from: bytes)
        }
    }
}

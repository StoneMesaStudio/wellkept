import Foundation
import Observation
import WellkeptCore

//  HardwareModel.swift
//  Wellkept — App/Sections/Hardware
//
//  **The one place the four readers and the speed test are actually called.**
//
//  The readers know nothing about each other and nothing about a view. This is the seam: it runs
//  them, folds the thermal reading into the row it can explain, files the result in Wellkept's own
//  record, and hands the finished `HardwareReport` to the screen.
//
//  ## Off the main thread, on purpose
//
//  Every reader is blocking work — IOKit, `statfs`, a directory of panic reports, and in the
//  battery's case a short-lived `system_profiler`. Together they take a couple of hundred
//  milliseconds, which is four dropped frames if it happens where the window is waiting to draw.
//  `Task.detached` puts the whole sweep somewhere else and hands back a `Sendable` report.
//
//  ## ⚠️ There is no schedule, and this file is where that promise is kept
//
//  Wellkept quits when its window closes. The one part that can outlive the window is the backup
//  background piece, which the person switches on themselves and which does three things, none of
//  them a hardware check — so there is still nothing that runs a check while nobody is looking.
//  Hardware is read **on launch and when the button is pressed**, and that is the whole list.
//  `checkOnLaunch()` runs once per launch and refuses to run a second time; nothing here starts a
//  timer.
//
//  ## ⚠️ It never runs under the test harness
//
//  `ViewShots` renders the real `HardwareView` into an off-screen window, and that render pumps a
//  run loop — which is enough for a `.task` to fire. A screenshot run must not read this Mac's
//  drive, battery and panic log, so `checkOnLaunch` refuses under `xctest`. The button still works
//  everywhere; only the automatic path is gated.

@MainActor
@Observable
final class HardwareModel {

    // MARK: What the screen draws

    /// The last complete answer. `nil` until the first check finishes — which is the "nothing has
    /// been read yet" state, and a real one: setup ends on Overview, so a person can reach this
    /// screen before anything has run.
    private(set) var report: HardwareReport?

    /// The failing-drive screen, when a drive has declared a fault. `nil` on every Mac but one.
    private(set) var alarm: DriveAlarm?

    /// A check is running now. The button greys and says so rather than appearing to do nothing.
    private(set) var isChecking = false

    /// The speed test is running now. Separate from `isChecking` because it is a separate button
    /// with a separate cost, and greying the whole screen for it would be a lie about what is
    /// happening.
    private(set) var isMeasuringSpeed = false

    /// Set once `checkOnLaunch()` has had its turn, whether it ran or refused.
    private var launchCheckDone = false

    // MARK: - Running it

    /// The check Wellkept runs by itself, once, when the window opens.
    ///
    /// Refuses in demo mode, refuses a second time in the same launch, and refuses under the test
    /// harness. Everything else is `check()`.
    func checkOnLaunch(demoMode: Bool) async {
        guard !launchCheckDone else { return }
        launchCheckDone = true
        guard !demoMode, !Self.runningUnderTests else { return }
        await check()
    }

    /// The whole Hardware sweep. Safe to call again; a second call while one is running is
    /// ignored rather than queued.
    func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let outcome = await Task.detached(priority: .userInitiated) { Self.sweep() }.value

        report = outcome.report
        alarm = outcome.alarm

        // Wellkept's own record of every reading it has ever taken. It cannot be back-filled —
        // macOS keeps days and we keep for ever, but only from the first launch — so it is written
        // here, once per check, and nowhere else.
        let report = outcome.report
        Task.detached(priority: .utility) { ReadingHistory.record(report) }
    }

    /// **Measure the drive.** The one button in this app that writes anything to the Mac.
    ///
    /// It writes a single 256 MB file and deletes it in the same breath — `SpeedTest.writeNotice`
    /// is the sentence beside the button, and it is that string, never a second copy of it.
    func measureSpeed() async {
        guard !isMeasuringSpeed, let current = report else { return }
        isMeasuringSpeed = true
        defer { isMeasuringSpeed = false }

        // ⚠️ Watched across the measurement rather than sampled at its edges. A `read()` before and
        // another after can both come back normal while the Mac throttled hard in between, which is
        // exactly the run whose figure should carry a caveat.
        let watch = ThermalWatch()
        let result = await SpeedTest.run()
        let peak = watch.peak
        watch.stop()

        let measured = SpeedTest.reading(result)
        let caveat = ThermalReading(pressure: peak,
                                    takenAt: result.ranAt,
                                    isVirtualMachine: current.facts.isVirtualMachine).speedCaveat

        let row = Self.appending(caveat, to: measured)

        // The report is rebuilt rather than mutated: `HardwareReport.init` re-sorts into row order,
        // drops the duplicate topic (first one wins, which is why the new row goes first) and
        // recomputes the single row Overview gets. Editing a stored copy would leave that row
        // describing a speed reading that has been replaced.
        let rebuilt = HardwareReport(facts: current.facts,
                                     readings: [row] + current.readings,
                                     ranAt: current.ranAt)
        report = rebuilt

        let machine = current.facts.modelIdentifier
        Task.detached(priority: .utility) {
            ReadingHistory.record([ReadingSample(row, takenAt: result.ranAt, machine: machine)])
        }
    }

    // MARK: - The sweep itself

    /// What one run produced. A plain value so the whole thing can cross back from a detached task.
    private struct Outcome: Sendable {
        let report: HardwareReport
        let alarm: DriveAlarm?
    }

    /// ⚠️ **`nonisolated` and free of anything that touches a view.** Everything it calls is a
    /// static on a reader, and none of them needs Full Disk Access — which is the section's whole
    /// promise to somebody who tapped "Finish later" during setup.
    private nonisolated static func sweep() -> Outcome {
        let facts = MachineReader.read()

        // Read once and record once. `read()` deliberately has no side effects, so the recording
        // is a separate, named act rather than something that happens by drawing a screen.
        let thermal = ThermalReader.readAndRecord(machine: facts.modelIdentifier)

        // Drives are read once and used twice: the row, and the failing-drive screen behind it.
        let drives = DriveReader.drives()

        var readings: [Reading] = [
            DriveReader.reading(for: drives),
            memoryRow(thermal: thermal),
            RestartReader.read(),
            SpeedTest.restingReading(),
        ]
        // A Mac with no battery gets no battery row at all, rather than a row explaining that a
        // Mac mini has no battery. `HardwareTopic.allCases` is the order; a missing topic simply
        // does not appear.
        if let battery = BatteryReader.read() { readings.append(battery) }

        return Outcome(report: HardwareReport(facts: facts, readings: readings),
                       alarm: DriveReader.alarm(for: drives))
    }

    /// The Memory row, carrying whatever thermal pressure had to say.
    ///
    /// ⚠️ **Thermal pressure decorates this row and never changes its severity.** There is no
    /// thermal row — a sixth row reading "Normal" every day of the year is the warning nobody
    /// reads — so the sentence goes where it can actually be explained: a Mac that is throttling
    /// is a Mac whose apps feel slow. Letting it escalate the row instead would send "macOS closed
    /// programs to free memory" up to Overview about a Mac that is merely warm, which is a headline
    /// about the wrong thing.
    private nonisolated static func memoryRow(thermal: ThermalReading) -> Reading {
        let base = MemoryReader.read()
        let withNote = appending(thermal.note, to: base)
        return Reading(topic: withNote.topic,
                       headline: withNote.headline,
                       measure: withNote.measure,
                       number: withNote.number,
                       severity: withNote.severity,
                       reason: withNote.reason,
                       details: withNote.details + [thermal.detail],
                       unreadable: withNote.unreadable,
                       remedy: withNote.remedy)
    }

    /// Add one sentence to a row's reason without disturbing anything else about it.
    ///
    /// `Reading` is immutable by design — a row that can be edited after the fact is a row whose
    /// severity and whose words can be made to disagree — so this rebuilds it through the same
    /// initializer, which re-applies every invariant on the way through.
    private nonisolated static func appending(_ sentence: String?, to reading: Reading) -> Reading {
        guard let sentence else { return reading }
        let reason = [reading.reason, sentence].compactMap { $0 }.joined(separator: " ")
        return Reading(topic: reading.topic,
                       headline: reading.headline,
                       measure: reading.measure,
                       number: reading.number,
                       severity: reading.severity,
                       reason: reason,
                       details: reading.details,
                       unreadable: reading.unreadable,
                       remedy: reading.remedy)
    }

    /// Whether this process is a test runner rather than the app.
    ///
    /// Read from the environment rather than from a compile-time flag: `ViewShots` builds the app's
    /// own sources in Debug, so `#if DEBUG` would also silence the launch check for anybody running
    /// the app out of Xcode — which is most of the people who need to see it work.
    private nonisolated static var runningUnderTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
    }
}

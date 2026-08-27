import Foundation
import IOKit
import IOKit.ps
import WellkeptCore

//  BatteryReader.swift
//  Wellkept — App/Hardware
//
//  **The Battery row: Apple's own number, and nothing that argues with it.**
//
//  ## The rule this file exists to enforce
//
//  ⚠️ **Print Apple's percentage. Never recompute it.** Measured by hand on this M3: Apple says
//  95%. Every honest sum from the readable numbers came out lower — 5,412 mAh against a 5,760 mAh
//  design capacity is 94%, and the raw full-charge figure of 5,268 mAh is 91%. Apple's number is
//  smoothed and stored over weeks; ours would be a spot reading of a chemistry that moves with
//  temperature and charge. Both are defensible, and that is exactly the problem: a person with
//  System Settings open on one screen and Wellkept on the other sees two numbers for one battery,
//  and concludes we are broken. So Apple's figure wins wherever Apple publishes one, and our
//  arithmetic appears only on a machine where Apple publishes nothing.
//
//  ## Where the number comes from, and why it is a subprocess
//
//  There is exactly one public route to the figure System Settings shows:
//
//      system_profiler SPPowerDataType -json -detailLevel mini
//        → sppower_battery_health_maximum_capacity = "95%"
//
//  It is **not** in the IORegistry — no key anywhere in `ioreg -l` holds it — and it is not in the
//  power-source dictionary either; `IOPSCopyPowerSourcesInfo` gives the word "Good" and no
//  percentage. `SPPowerReporter` reads it through a key called "Maximum Capacity Percent" that
//  Apple ships no header for. Calling a private symbol to save a process launch would buy us a row
//  that goes blank in a macOS update, silently.
//
//  `MachineReader` refuses to spawn `system_profiler` and is right to: `SPHardwareDataType` takes
//  seconds and answers questions a `sysctl` already answers. This is the opposite case. Measured:
//  the tool itself returns in **60–80 ms**, and the whole row — spawn, JSON, IOKit — costs
//  **130–210 ms**, for the one fact nothing else will tell us. No permission, no prompt, no Full
//  Disk Access. It is guarded by a timeout anyway, because a wedged subprocess must not be able to
//  hang a check.
//
//  ## ⚠️ The trap: one field, two meanings
//
//  `MaxCapacity` — on `AppleSmartBattery` in the IORegistry and as "Max Capacity" in the power
//  source — means **different things on the two architectures**:
//
//  | | Intel | Apple silicon |
//  |---|---|---|
//  | `MaxCapacity` | full-charge capacity in **mAh** (≈ 5,268) | a **percentage**, always 100 |
//  | `CurrentCapacity` | charge in **mAh** | charge as a **percentage** (89) |
//  | full charge, in mAh | `MaxCapacity` | `AppleRawMaxCapacity` / `NominalChargeCapacity` |
//
//  Divide `MaxCapacity` by `DesignCapacity` on an Apple silicon Mac and you get 100/5760 — a
//  battery at 2% health, on a machine that is fine. Every field read below is interpreted through
//  its scale rather than its name, and `chargePercent` works on both by asking whether the maximum
//  is 100 or a four-figure milliamp-hour number.
//
//  ## ⚠️ `system_profiler` translates its values, and this file used to compare them in English
//
//  Fixed 2026-08-27. `condition(source:registry:appleWord:)` lowercased Apple's condition word and
//  looked for "service", "replace" and "poor". A French Mac prints *Réparation recommandée*, which
//  contains none of them, so a battery Apple itself says needs servicing came back normal — and
//  French uses that same string for `Fair`, ordinary wear, so the two are not separable in either
//  direction. The **keys** are stable and the values are not; `AppleWords` reverses the reporter's
//  own `Localizable.loctable` to get back to the key, and where the language genuinely collapses
//  two meanings the row takes the safer one and says so. The language cannot be forced:
//  `system_profiler` rejects `-AppleLanguages` outright.
//
//  ## What is deliberately not here
//
//  - **No temperature.** The battery reports 30.00 °C in `Temperature`. Nobody publishes what is
//    too hot for a battery, so the number can only worry people. House rule, section-wide.
//  - **No recomputed health where Apple gives one.** See above.
//  - **No claim about the Optimised Battery Charging switch.** Its state has no public reading:
//    it is not in `com.apple.PowerManagement`, not in `com.apple.powerd.charging` (which holds
//    only MDM charge policies, empty here), and not in the IORegistry. What *is* observable is
//    what the machine is doing — plugged in, not full, and not charging — and that is what the
//    Options row says, in those words. Inferring the setting from the symptom would be a guess
//    printed as a fact.
//  - **No row at all on a Mac with no battery.** A desktop gets nothing, not an empty row saying
//    so. `read()` returns `nil` and the section never draws it.
//
//  ## ⚠️ Worn but working is never a problem
//
//  A battery past its rated cycle count, or under 80%, still doing its job is a battery in year
//  four. It says so plainly, in the row, and stays `.information` — the section stays Good. The
//  only two states that earn attention are the two where **Apple itself** says something is wrong:
//  a permanent failure, and "Check Battery". Those are Apple's verdict, and the row says so, so a
//  person can tell our opinion from the machine's.

enum BatteryReader {

    // MARK: - The row

    /// Read the Battery row, or `nil` on a Mac that has no battery.
    ///
    /// `nil` is the whole answer for a desktop. An iMac showing "Battery — this Mac does not
    /// report it" would be a row about the absence of a thing it was never going to have, which is
    /// noise dressed as thoroughness.
    static func read() -> Reading? {
        guard let facts = facts() else { return nil }
        return row(facts)
    }

    // MARK: - What was read

    /// Everything the machine said about its battery, before any judgement is made about it.
    ///
    /// Split out from `row` so the wording and the severity rules can be tested against a battery
    /// that has failed, without owning one.
    struct Facts: Sendable, Hashable {

        /// **Apple's own maximum-capacity percentage**, from `system_profiler`. `nil` on a Mac
        /// that does not publish one — mostly Intel, where System Information shows a condition
        /// and no figure.
        let applePercent: Int?

        /// Our own arithmetic: full charge against design capacity, in mAh. Used **only** when
        /// `applePercent` is `nil`. See the header.
        let measuredPercent: Int?

        let condition: Condition
        /// Apple's own failure words, where it named any: "Cell Imbalance", "Fuse Blown".
        let failureModes: [String]

        /// Charge right now, 0–100.
        let charge: Int?
        let cycles: Int?
        /// What this battery was rated for when it was made, usually 1,000.
        let designCycles: Int?

        /// Full-charge capacity in mAh, and the design capacity to compare it against. Both `nil`
        /// where the machine reports them on a scale we cannot identify.
        let fullChargeCapacity: Int?
        let designCapacity: Int?

        let pluggedIn: Bool
        let charging: Bool
        let fullyCharged: Bool

        /// Set inside a virtual machine, where the whole battery may be an invention. See `row`.
        let isVirtualMachine: Bool

        /// **Set when this Mac's language cannot tell ordinary wear from a service
        /// recommendation.**
        ///
        /// `system_profiler` translates the condition word, and several languages — French among
        /// them — print the same string for Apple's `Fair` (normal wear) and its `Poor` (service
        /// recommended). `condition` then carries the safer of the two and this flag carries the
        /// doubt, so the row can say it out loud instead of printing a verdict we did not earn.
        ///
        /// `var` with a default so the demo Macs, which state their condition outright, do not have
        /// to mention it. See `AppleWords`.
        var uncertain: Bool = false

        /// The percentage to print: Apple's if there is one, ours if there is not, `nil` if
        /// neither.
        var percent: Int? { applePercent ?? measuredPercent }

        /// Whether the figure on the row is Apple's own. Decides one clause of the reason, because
        /// "Apple says" and "we measured" are not the same claim and must not read as though they
        /// were.
        var percentIsApples: Bool { applePercent != nil }

        /// Worn, in the two ways a battery visibly wears. Never a problem — see the header.
        var isWorn: Bool {
            if let percent, percent < 80 { return true }
            if let cycles, let designCycles, designCycles > 0, cycles > designCycles { return true }
            return false
        }
    }

    /// What the machine says about the battery's condition, in the three states that change what
    /// the row does.
    ///
    /// Deliberately **not** a copy of Apple's vocabulary, which is three vocabularies: the power
    /// source says "Good"/"Fair"/"Poor", the health condition says ""/"Check Battery"/"Permanent
    /// Battery Failure", and System Settings shows "Normal"/"Service Recommended". Mapping all of
    /// them into these three, once, is what stops the row from showing a word System Settings has
    /// never used.
    enum Condition: Sendable, Hashable {
        /// Working. Includes a worn battery — wear is not a condition, it is a number.
        case normal
        /// Apple recommends service. "Check Battery", or a health of "Poor".
        case serviceRecommended
        /// Apple says this battery has failed permanently.
        case failed
        /// Nothing readable said either way.
        case unknown

        /// The word for the Options row. System Settings' vocabulary, not the IOKit key's.
        var word: String {
            switch self {
            case .normal:             "Normal"
            case .serviceRecommended: "Service recommended"
            case .failed:             "Failed"
            case .unknown:            Unreadable.notReported.sentence
            }
        }
    }

    // MARK: - Reading the machine

    /// Everything, from three sources, or `nil` when there is no battery.
    static func facts() -> Facts? {
        let source = internalBattery()
        let registry = registryProperties()

        // The presence test, and the only thing that decides whether this row exists at all. A
        // desktop has neither source; a laptop whose battery has been disconnected has a registry
        // entry that says so.
        let present = (source?[kIOPSIsPresentKey] as? Bool) == true
            || (registry?["BatteryInstalled"] as? Bool) == true
        guard present else { return nil }

        let apple = appleHealth()
        let design = positive(registry?["DesignCapacity"]) ?? positive(source?[kIOPSDesignCapacityKey])
        let fullCharge = fullChargeCapacity(registry: registry, designCapacity: design)
        let verdict = condition(source: source, registry: registry, appleWord: apple?.condition)

        return Facts(
            applePercent: apple?.percent,
            measuredPercent: percentage(of: fullCharge, against: design),
            condition: verdict.condition,
            failureModes: (source?[kIOPSBatteryFailureModesKey] as? [String]) ?? [],
            charge: chargePercent(source: source, registry: registry),
            cycles: apple?.cycles
                ?? positive(registry?["CycleCount"])
                ?? positive(source?["CycleCount"]),
            designCycles: positive(registry?["DesignCycleCount9C"])
                // Not a named constant: `IOPSKeys.h` declares no key for it, and the string is
                // what the dictionary actually carries.
                ?? positive(source?["DesignCycleCount"]),
            fullChargeCapacity: fullCharge,
            designCapacity: design,
            pluggedIn: (source?[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
                || (registry?["ExternalConnected"] as? Bool) == true,
            charging: (source?[kIOPSIsChargingKey] as? Bool)
                ?? (registry?["IsCharging"] as? Bool) ?? false,
            fullyCharged: (registry?["FullyCharged"] as? Bool) ?? false,
            isVirtualMachine: VirtualMachine.current.isVirtual,
            uncertain: verdict.uncertain
        )
    }

    // MARK: - Building the row

    /// The row itself. Pure: hand it a `Facts` and it produces the same `Reading` every time.
    static func row(_ facts: Facts) -> Reading {
        // A battery that is present and told us nothing usable — no percentage, no condition — is
        // a row we could not read, and it has to say so in the house sentence rather than wear a
        // "Good" chip above a sentence admitting we do not know. `.notReported` rather than
        // `.notPermitted`: nothing refused us, the machine simply did not answer, so the check
        // stays complete.
        if facts.condition == .unknown && facts.percent == nil {
            return .unreadable(.battery, .notReported,
                               about: "How much charge this battery holds",
                               details: details(facts))
        }

        // Inside a virtual machine the battery may not exist at all — Parallels and VMware invent
        // one, at a percentage that never moves. `HardwareReport` already puts the "this is a
        // virtual machine" row above everything, so the honest thing here is to keep the numbers
        // and refuse to pass a verdict on them: a fictional battery must never produce a real
        // "needs servicing".
        let severity: Severity
        switch facts.condition {
        case .failed:             severity = facts.isVirtualMachine ? .information : .problem
        case .serviceRecommended: severity = facts.isVirtualMachine ? .information : .attention
        case .normal, .unknown:   severity = .information
        }

        return Reading(
            topic: .battery,
            headline: headline(facts),
            measure: facts.percent.map { "\($0)%" },
            number: facts.percent.map { ReadingNumber(Double($0), ReadingNumber.percent) },
            severity: severity,
            reason: reason(facts),
            details: details(facts)
        )
    }

    private static func headline(_ facts: Facts) -> String {
        switch facts.condition {
        case .failed:
            return "Apple's own check says this battery has failed."
        case .serviceRecommended:
            return "Apple's own check says this battery needs servicing."
        case .normal, .unknown:
            // The both-unreadable case never reaches here — see `row`.
            guard let percent = facts.percent else { return "This battery is working normally." }
            return "This battery holds \(percent)% of the charge it held when it was new."
        }
    }

    /// Why the row says what it says — shown on the row, never behind a disclosure.
    ///
    /// Two jobs, in this order: separate Apple's verdict from ours, and say out loud that a worn
    /// battery is not a broken one. The second is the sentence that stops a 78% battery from
    /// reading as a fault on a machine that works perfectly well.
    private static func reason(_ facts: Facts) -> String? {
        guard let plain = plainReason(facts) else { return uncertaintyClause(facts) }
        guard let doubt = uncertaintyClause(facts) else { return plain }
        return "\(plain) \(doubt)"
    }

    /// ⚠️ **The sentence that stops a translation from becoming a verdict.**
    ///
    /// macOS prints the battery's condition in the Mac's own language, and several languages —
    /// French among them — use one string for Apple's `Fair`, which is ordinary wear, and its
    /// `Poor`, which is Apple recommending service. When that happens the row shows the safer of
    /// the two, and this says so. A person who reads it can open System Settings and see the same
    /// word Apple printed, which is the only place the two can be told apart.
    private static func uncertaintyClause(_ facts: Facts) -> String? {
        guard facts.uncertain else { return nil }
        return "One caveat: macOS reports this Mac's battery condition in a word that covers both "
             + "ordinary wear and a service recommendation, and nothing in what it gives us "
             + "separates the two. This row shows the more cautious of them."
    }

    private static func plainReason(_ facts: Facts) -> String? {
        switch facts.condition {
        case .failed:
            var text = "That is Apple's verdict, not ours. A battery in this state needs replacing "
                     + "by a technician; the Mac still runs on the power adapter."
            if !facts.failureModes.isEmpty {
                text += " The battery reports: \(facts.failureModes.joined(separator: ", "))."
            }
            return text

        case .serviceRecommended:
            return "That is Apple's verdict, not ours. The battery still works — Apple is saying "
                 + "it no longer holds enough charge to be worth keeping."

        case .normal, .unknown:
            if facts.isWorn {
                return "\(wearClause(facts)) That is wear, not a fault: it holds less than it did, "
                     + "and it is still doing its job."
            }
            if let cycles = facts.cycles, let design = facts.designCycles, design > 0 {
                return "\(cycles.formatted()) charge cycles of the roughly \(design.formatted()) "
                     + "this battery is rated for."
            }
            if facts.percent != nil && !facts.percentIsApples {
                return "Measured from the battery's own capacity figures. This Mac does not "
                     + "publish a percentage of its own to compare it against."
            }
            return nil
        }
    }

    /// The half-sentence naming what the wear actually is, so "that is wear, not a fault" has
    /// something to point at.
    private static func wearClause(_ facts: Facts) -> String {
        if let cycles = facts.cycles, let design = facts.designCycles,
           design > 0, cycles > design {
            return "It is past the \(design.formatted()) charge cycles it was rated for, at "
                 + "\(cycles.formatted())."
        }
        return "Below 80% is where Apple starts calling a battery worn."
    }

    /// Everything more exact than the headline, behind **Options**. John's rule, 2026-08-27:
    /// Apple's figure on the row, the arithmetic underneath it.
    private static func details(_ facts: Facts) -> [DetailPair] {
        var pairs: [DetailPair] = []

        if let charge = facts.charge {
            pairs.append(DetailPair("Charge now", "\(charge)%"))
        }

        pairs.append(DetailPair("Condition", conditionWords(facts)))

        if let cycles = facts.cycles {
            let value = facts.designCycles.map {
                "\(cycles.formatted()) of about \($0.formatted())"
            } ?? cycles.formatted()
            pairs.append(DetailPair("Charge cycles", value))
        }

        if let full = facts.fullChargeCapacity, let design = facts.designCapacity {
            pairs.append(DetailPair("Capacity",
                                    "\(full.formatted()) mAh, against \(design.formatted()) mAh "
                                    + "when it was new"))
        }

        pairs.append(DetailPair("Power", facts.pluggedIn ? "Plugged in" : "On battery"))
        pairs.append(DetailPair("Charging", chargingWords(facts)))

        return pairs
    }

    /// The Options row's condition, with the doubt attached where there is one. See
    /// `uncertaintyClause`.
    private static func conditionWords(_ facts: Facts) -> String {
        guard facts.uncertain else { return facts.condition.word }
        return "\(facts.condition.word), or ordinary wear — macOS uses one word for both in this "
             + "Mac's language"
    }

    /// What the battery is doing right now — and the closest honest answer to "is Optimised
    /// Battery Charging on?", which has no public reading. See the header.
    private static func chargingWords(_ facts: Facts) -> String {
        guard facts.pluggedIn else { return "Not charging — this Mac is running on the battery" }
        if facts.charging { return "Charging" }
        if facts.fullyCharged { return "Fully charged" }
        return "Paused — plugged in and holding below full. macOS does this to slow wear, and "
             + "also when the battery is warm."
    }

    // MARK: - Apple's own figure

    /// What `system_profiler` reports about battery health.
    struct AppleHealth: Sendable, Hashable {
        /// "95%" → 95. `nil` where the field is absent.
        let percent: Int?
        /// Apple's own word for the condition — **and it is translated.** "Good" on this Mac,
        /// *Réparation recommandée* on a French one. Never compared in English; it goes through
        /// `AppleWords` and `appleConditionKeys`.
        let condition: String?
        let cycles: Int?
    }

    /// Ask `system_profiler` for the one figure nothing else publishes.
    ///
    /// `-detailLevel mini` is deliberate: it keeps the health block and drops the model block,
    /// which is the only part that carries the battery's serial number. We do not need a second
    /// identifying number to answer "how is the battery", and not asking for it is cheaper than
    /// asking and discarding.
    ///
    /// Returns `nil` on any failure at all — a missing binary, a non-zero exit, unreadable JSON,
    /// or the timeout. Every caller treats `nil` as "Apple publishes no figure on this Mac", which
    /// is also the true answer on hardware that publishes none.
    static func appleHealth(timeout: TimeInterval = 5) -> AppleHealth? {
        guard let data = systemProfilerPowerData(timeout: timeout),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["SPPowerDataType"] as? [[String: Any]] else { return nil }

        for item in items {
            guard let health = item["sppower_battery_health_info"] as? [String: Any] else { continue }
            return AppleHealth(
                percent: percentValue(health["sppower_battery_health_maximum_capacity"]),
                condition: health["sppower_battery_health"] as? String,
                cycles: positive(health["sppower_battery_cycle_count"])
            )
        }
        return nil
    }

    /// "95%" → 95, and 95 → 95. The field is a string today; a future macOS printing a number
    /// instead should not blank the row.
    private static func percentValue(_ raw: Any?) -> Int? {
        if let number = raw as? Int { return clampPercent(number) }
        guard let text = raw as? String else { return nil }
        let digits = text.filter(\.isNumber)
        return Int(digits).flatMap(clampPercent)
    }

    /// Run it, with a watchdog.
    ///
    /// The watchdog exists because this is the one place in Hardware that hands control to another
    /// process. `system_profiler` measured 60–80 ms here across three runs; a version of it that
    /// blocks on something would otherwise hold the whole check open for as long as it liked.
    ///
    /// The output is drained *before* `waitUntilExit`, which is the order that matters: a child
    /// filling the pipe buffer while the parent waits for it to exit is a deadlock, and it is a
    /// deadlock that only shows up on the machine with the unusual amount to say.
    private static func systemProfilerPowerData(timeout: TimeInterval) -> Data? {
        let tool = URL(filePath: "/usr/sbin/system_profiler")
        guard FileManager.default.isExecutableFile(atPath: tool.path) else { return nil }

        let process = Process()
        process.executableURL = tool
        process.arguments = ["SPPowerDataType", "-json", "-detailLevel", "mini"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }

        // `Process` is not `Sendable`, and the watchdog runs on another queue. The box is the
        // narrowest possible admission of that: one reference, read by two threads, and the only
        // thing either of them does with it is ask whether the process is still running.
        let box = Watchdog(process)
        let killer = DispatchWorkItem { box.terminate() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: killer)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()

        guard process.terminationStatus == 0, !data.isEmpty else { return nil }
        return data
    }

    private final class Watchdog: @unchecked Sendable {
        private let process: Process
        init(_ process: Process) { self.process = process }
        func terminate() { if process.isRunning { process.terminate() } }
    }

    // MARK: - Reading IOKit

    /// The internal battery's power-source dictionary, or `nil`.
    ///
    /// Filtered by transport type rather than by position in the list: a Mac with a UPS or a
    /// Bluetooth mouse attached reports those as power sources too, and the first entry is not
    /// promised to be the battery.
    static func internalBattery() -> [String: Any]? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            if description[kIOPSTransportTypeKey] as? String == kIOPSInternalType {
                return description
            }
        }
        return nil
    }

    /// Every property of `AppleSmartBattery`, or `nil` on a machine that has no such service.
    ///
    /// This is where the milliamp-hour figures live. The class name is the same on Intel and
    /// Apple silicon; what the keys inside it *mean* is not — see the table in the header.
    static func registryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties,
                                                kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else { return nil }
        return dictionary
    }

    // MARK: - Interpreting the numbers

    /// Charge now, 0–100, on both architectures.
    ///
    /// ⚠️ This is the trap from the header, handled. "Current Capacity" is a percentage on Apple
    /// silicon and milliamp-hours on Intel, and the way to tell which you have is to look at the
    /// maximum beside it: 100 means the pair is already a percentage, a four-figure number means
    /// they are capacities and the percentage has to be divided out.
    static func chargePercent(source: [String: Any]?, registry: [String: Any]?) -> Int? {
        if let current = positive(source?[kIOPSCurrentCapacityKey]),
           let maximum = positive(source?[kIOPSMaxCapacityKey]), maximum > 0 {
            return maximum == 100 ? clampPercent(current)
                                  : clampPercent(Int((Double(current) / Double(maximum)) * 100))
        }
        if let current = positive(registry?["CurrentCapacity"]),
           let maximum = positive(registry?["MaxCapacity"]), maximum > 0 {
            return maximum == 100 ? clampPercent(current)
                                  : clampPercent(Int((Double(current) / Double(maximum)) * 100))
        }
        return nil
    }

    /// Full-charge capacity in **milliamp-hours**, on either architecture, or `nil` when the
    /// machine gives nothing on that scale.
    ///
    /// Apple silicon publishes it as `NominalChargeCapacity` (Apple's own smoothed figure) or
    /// `AppleRawMaxCapacity` (the gauge's raw one). Intel publishes it as `MaxCapacity`, which on
    /// Apple silicon is the number 100 — so that key is only trusted when it is on the same scale
    /// as the design capacity beside it.
    static func fullChargeCapacity(registry: [String: Any]?, designCapacity: Int?) -> Int? {
        if let nominal = positive(registry?["NominalChargeCapacity"]) { return nominal }
        if let raw = positive(registry?["AppleRawMaxCapacity"]) { return raw }
        if let maximum = positive(registry?["MaxCapacity"]),
           let design = designCapacity, design > 200, maximum > 200 {
            return maximum
        }
        return nil
    }

    /// Full charge against design capacity, as a whole percentage. **Only ever used where Apple
    /// publishes no figure of its own** — see the header.
    ///
    /// Clamped to 100: a new battery routinely gauges above its design capacity, and "this battery
    /// holds 103% of what it held when it was new" is a true sentence that reads like a bug.
    static func percentage(of fullCharge: Int?, against design: Int?) -> Int? {
        guard let fullCharge, let design, design > 0, fullCharge > 0 else { return nil }
        return clampPercent(Int(((Double(fullCharge) / Double(design)) * 100).rounded()))
    }

    /// The English keys `SPPowerReporter` uses for the battery's condition, and what each one means
    /// to us.
    ///
    /// ⚠️ **These are keys, not words on a screen.** Apple's own English table already collapses
    /// three of them onto the single string "Service Recommended", and every other language
    /// collapses them differently — French puts `Fair` and `Poor` together under *Réparation
    /// recommandée*. Comparing the printed words is the bug this replaces; see `AppleWords`.
    ///
    /// `Fair` is `.normal` on purpose. It is Apple's word for ordinary wear, and wear is reported
    /// as a number on this row, never as a condition — "worn but working is never a problem".
    static let appleConditionKeys: [String: Condition] = [
        "Good":          .normal,
        "Fair":          .normal,
        "Poor":          .serviceRecommended,
        "Check Battery": .serviceRecommended,
    ]

    /// What we decided about the condition, and whether this Mac's language let us decide it.
    struct ConditionReading: Sendable, Hashable {
        let condition: Condition
        /// **Set when the word Apple printed covers both ordinary wear and a service
        /// recommendation**, and there is no way to tell which this Mac has. See `Facts.uncertain`.
        let uncertain: Bool

        static let unknown = ConditionReading(condition: .unknown, uncertain: false)
    }

    /// Apple's three vocabularies, mapped into our three states. See `Condition`.
    ///
    /// The permanent-failure flag is checked first and on its own: it is the battery's own gauge
    /// reporting a hardware fault, and it is the one signal here that does not depend on Apple's
    /// judgement of wear. The two IOKit strings after it are constants from `IOPSKeys.h` and are
    /// **not** localized — those comparisons are safe as they stand.
    ///
    /// Only the last source, `system_profiler`'s own word, is translated, and that is the one that
    /// goes through `AppleWords`.
    static func condition(source: [String: Any]?,
                          registry: [String: Any]?,
                          appleWord: String?) -> ConditionReading {
        func settled(_ condition: Condition) -> ConditionReading {
            ConditionReading(condition: condition, uncertain: false)
        }

        if let failure = registry?["PermanentFailureStatus"] as? Int, failure != 0 {
            return settled(.failed)
        }

        let health = source?[kIOPSBatteryHealthKey] as? String
        let state = source?[kIOPSBatteryHealthConditionKey] as? String

        if state == kIOPSPermanentFailureValue { return settled(.failed) }
        if state == kIOPSCheckBatteryValue { return settled(.serviceRecommended) }
        if health == kIOPSPoorValue { return settled(.serviceRecommended) }

        // `system_profiler`'s word, for the macOS releases where System Settings says "Service
        // Recommended" and the power source still says "Good".
        //
        // ⚠️ This was `word.contains("service") || word.contains("replace") || word == "poor"`
        // until 2026-08-27 — an English comparison against a value macOS translates. On a French
        // Mac it matched nothing, so a battery Apple says needs servicing came back normal.
        if let appleWord {
            switch AppleWords.meaning(of: appleWord, from: .power, keys: appleConditionKeys) {
            case let .certain(condition):
                return settled(condition)

            case let .ambiguous(possible):
                // ⚠️ **Take the safer reading, and say so on the row.** French prints the same
                // string for `Fair` (ordinary wear) and for `Poor` (Apple recommending service),
                // and nothing in the output separates them. Reporting normal would hide Apple's own
                // recommendation; reporting service recommended agrees with what this person's
                // System Settings is already showing them, because Apple's English table collapses
                // the two the same way. The uncertainty is stated in `reason`, never swallowed.
                if possible.contains(.failed) {
                    return ConditionReading(condition: .failed, uncertain: true)
                }
                if possible.contains(.serviceRecommended) {
                    return ConditionReading(condition: .serviceRecommended, uncertain: true)
                }
                return ConditionReading(condition: possible.first ?? .unknown, uncertain: true)

            case .unrecognised:
                break
            }
        }

        // "Good" and "Fair" are both working batteries.
        if health == kIOPSGoodValue || health == kIOPSFairValue { return settled(.normal) }
        if state?.isEmpty == true && health != nil { return settled(.normal) }

        // A word we could not place at all. The machine did answer, so this is not "no battery
        // information" — but we will not translate an unknown string into a verdict.
        if appleWord != nil { return settled(.normal) }

        return .unknown
    }

    // MARK: - Small conversions

    /// A positive whole number out of an IOKit or JSON value, or `nil`.
    ///
    /// Zero is treated as absent throughout this file, deliberately: every field it is applied to
    /// — a capacity, a cycle count — is zero only on a machine that did not answer. A design
    /// capacity of 0 would otherwise divide into an infinite battery.
    private static func positive(_ raw: Any?) -> Int? {
        let value: Int?
        switch raw {
        case let number as Int:    value = number
        case let number as Int32:  value = Int(number)
        case let number as Int64:  value = Int(number)
        case let number as UInt32: value = Int(number)
        case let number as Double: value = Int(number)
        case let number as NSNumber: value = number.intValue
        default: value = nil
        }
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func clampPercent(_ value: Int) -> Int? {
        guard value > 0 else { return nil }
        return min(value, 100)
    }
}

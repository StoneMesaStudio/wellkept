import Foundation

//  Hardware.swift
//  WellkeptCore
//
//  The words the Hardware section agrees on, and the shape a reader hands back.
//
//  ## What this file is for
//
//  Four readers (drive, battery, memory, restarts) and one speed test compile against this file
//  without seeing each other. Nothing here imports SwiftUI or IOKit: the vocabulary has to be
//  testable without a window and without a machine, and a reader has to be replaceable without
//  touching a view.
//
//  ## ⚠️ The measured truth this file is built around
//
//  These were checked by hand on an M3 running macOS 26. They are not assumptions, and a cleverer
//  API does not exist for any of them:
//
//  - **Drive wear is not readable on Apple Silicon.** `IONVMeSMARTUserClient` returns
//    `kIOReturnUnsupported` against `AppleANS3CGv2Controller`, and no wear key exists anywhere in
//    the IORegistry. All an Apple Silicon Mac reports about its own drive is Apple's verdict —
//    the "S.M.A.R.T. status" that reads `Verified` — plus model, capacity, serial and connection.
//    On **Intel** Macs the real NVMe SMART counters *are* readable. So `Reading` has to carry a
//    number when there is one and degrade honestly when there is not, on the same row, in the
//    same build.
//  - **No temperature in degrees.** The undocumented route to a die temperature moved
//    62 → 79 → 58 °C in three minutes on an idle machine, can close in any macOS update, and
//    nobody — Apple included — publishes what is too hot. A number nobody can act on is not
//    information.
//  - **Kernel panics are readable only by administrator accounts**, by account type rather than
//    by Full Disk Access. No permission grant fixes it, which is why `Unreadable.notGrantable`
//    exists: refused, no button, and the check still honestly complete, because no run of this app
//    on this account was ever going to see more.
//  - **Nothing in Hardware needs Full Disk Access.** The whole section works for someone who
//    tapped "Finish later".
//
//  ## The rule that shapes every type below
//
//  **Never report zero because we could not look.** A drive with no readable wear counter is not
//  a drive at 0% wear, and a Mac whose panic log we cannot open has not had zero panics. A reader
//  that cannot read something returns an `Unreadable`, and the row says so in the same house
//  sentence everywhere in the app.

// MARK: - The five rows

/// The five things Hardware reports, in the order they are drawn.
///
/// ⚠️ **`allCases` IS the row order, and this list never sorts.** Worst-first is right for a list
/// of findings and wrong for a fixed panel: a person who learns that Battery is the second row
/// should still find it there next week, on a Mac where the drive happens to have gone quiet. A
/// panel that reshuffles between runs is a panel you have to re-read every time you open it.
///
/// Raw values are storage — they are written into the reading history, which is the one record
/// in this app that cannot be rebuilt — and the labels are English. They are allowed to drift
/// apart forever.
public enum HardwareTopic: String, CaseIterable, Sendable, Identifiable, Codable, Hashable {
    /// What the Mac's own drive check says, plus what the drive is.
    case drive
    /// Apple's own battery percentage, on a Mac that has a battery.
    case battery
    /// Whether this Mac has enough memory for what is actually run on it.
    case memory
    /// Kernel panics and restarts of the whole machine. **Not app crashes** — those belong to
    /// Apps, because Safari quitting says nothing about whether this machine is healthy, and the
    /// hundred-odd diagnostic files a normal Mac accumulates would make a fine Mac look alarming.
    case restarts
    /// How fast this drive reads and writes. The one row with a button that does work.
    case speed

    public var id: String { rawValue }

    /// The row's name. One word each, because the row beneath it is where the sentence goes.
    public var label: String {
        switch self {
        case .drive:    "Drive"
        case .battery:  "Battery"
        case .memory:   "Memory"
        case .restarts: "Restarts"
        case .speed:    "Speed"
        }
    }

    /// What the reading means, in one plain sentence.
    ///
    /// This is explanation, not clutter (DESIGN §12.4): it says what the number on the row is
    /// actually telling you, which is the one thing a person cannot work out by looking at it.
    /// It sits with the row it belongs to, once, and never as a paragraph under a heading.
    public var explanation: String {
        switch self {
        case .drive:
            "The drive holds everything on this Mac. This is the drive's own verdict on itself."
        case .battery:
            "How much charge the battery still holds, compared with when it was new."
        case .memory:
            "Whether this Mac has enough memory for what you actually run on it."
        case .restarts:
            "Whether the whole machine has crashed or restarted on its own."
        case .speed:
            "How fast this drive reads and writes, measured against its own past."
        }
    }

    /// Sort position, so a caller that has collected readings out of order can put them back into
    /// the fixed order without knowing how the order is expressed.
    public var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

// MARK: - Something we could not read

/// **The one house sentence for anything Wellkept could not read**, in exactly three flavours.
///
/// A reader returns this instead of a number. It exists so that "we do not know" is a first-class
/// answer with one wording, rather than five sections each inventing a way to say nothing — and
/// so that the far worse alternative, reporting a zero we never measured, has no place to hide.
///
/// The three flavours are not interchangeable, and the difference decides two separate things:
///
/// | | What it means | Does the row get a button? | Does it make the check incomplete? |
/// |---|---|---|---|
/// | `.notReported` | The machine does not have this to give | No | **No** |
/// | `.notPermitted` | Refused, **and the person can grant it** | Yes | **Yes** |
/// | `.notGrantable` | Refused, and **nothing can grant it** | No | **No** |
///
/// ## ⚠️ Why "refused" had to split in two — the bug this shape fixes
///
/// Until 2026-08-27 there were two cases, and every refusal was `.notPermitted`, which marked the
/// whole check incomplete. That was survivable while Hardware was the only section: its one
/// refusal is the panic log, which a standard account cannot read.
///
/// **Security breaks it outright.** Every root-only Security fact is a refusal that no user on
/// earth can lift from inside an app — the FileVault recovery key, which accounts can unlock the
/// Mac, Gatekeeper's exception list, the Intel firmware password, Apple's own login-items store.
/// Under two cases, Overview would have said "I could not see everything" on **100% of Macs,
/// including a flawlessly configured one**, for ever, with no button anywhere that could clear
/// it. That is precisely the warning-nobody-can-clear this whole app is built to avoid.
///
/// So the question a reader now has to answer is not "were we refused" but **"is there something
/// the person could actually do about it"**:
///
/// - Full Disk Access is refused → `.notPermitted`. There is a switch, we can point at it, and
///   until it is flipped we genuinely did not see everything. Both halves are true and both are
///   said.
/// - macOS reserves it for an administrator, or for nobody → `.notGrantable`. There is no switch,
///   no button we could honestly draw, and no version of this run that would have seen more. The
///   check looked at everything it was ever able to look at, so it is **complete** — and the row
///   still says plainly that we did not see it, which is the part that must never be dropped.
///
/// ⚠️ **`.notGrantable` is not a quiet way to hide a refusal.** It still reports `.notChecked` on
/// the row, still prints the house sentence, and still appears in `unreadableTopics`. The only
/// thing it does not do is put a permanent caveat on Overview that nobody can clear.
public enum Unreadable: String, Sendable, Hashable, Codable, CaseIterable {

    /// The machine does not report it. Nothing is wrong and nothing can be done.
    case notReported

    /// It exists, we were refused, **and the person could grant it** — in this app that means Full
    /// Disk Access, the one permission Wellkept ever asks for.
    ///
    /// This is the only state that marks a check incomplete, and it is the only one that should
    /// ever carry a button, because it is the only one where a button leads somewhere that changes
    /// the answer. Both facts are the same fact: something is being withheld that the user can
    /// hand over.
    ///
    /// ⚠️ A reader should reach for this **only where a grant would genuinely change the reading**,
    /// and should still answer as much of the question as it can from what it *is* allowed to read.
    case notPermitted

    /// It exists, we were refused, **and nothing can grant it** — macOS reserves it for an
    /// administrator account, or for nobody at all.
    ///
    /// Kernel panics are the case that proves the point: `/Library/Logs/DiagnosticReports` is
    /// readable by the `admin` group, so it is **the kind of account you sign in with** that
    /// decides it, not a privacy setting. No switch exists. Offering a button would be offering a
    /// door with no room behind it.
    ///
    /// Added 2026-08-27. It sits after `.notPermitted` rather than replacing it: raw values are
    /// written into the reading history, which cannot be rebuilt, so cases are **added, never
    /// renumbered or re-meant**.
    case notGrantable

    /// The clause, lower case, for building a sentence around a thing.
    public var clause: String {
        switch self {
        case .notReported:  "this Mac does not report it"
        case .notPermitted: "we were not allowed to look"
        case .notGrantable: "there is no permission that would let us see it"
        }
    }

    /// The bare house sentence, standing alone.
    public var sentence: String {
        switch self {
        case .notReported:  "This Mac does not report it."
        case .notPermitted: "We were not allowed to look."
        case .notGrantable: "There is no permission that would let us see it."
        }
    }

    /// The house sentence, about a named thing: "Drive wear — this Mac does not report it."
    public func sentence(about thing: String) -> String { "\(thing) — \(clause)." }

    /// Whether something exists that we were kept away from, either way round.
    ///
    /// Useful to a reader that wants to say "we could not see it" without caring which kind of
    /// refusal it was. Nothing in the app should branch on this to decide a button or a caveat —
    /// those are `mayOfferRemedy` and `stillComplete`, and they deliberately disagree here.
    public var wasRefused: Bool { self != .notReported }

    /// Whether a row in this state is ever allowed to carry a button.
    ///
    /// `true` is permission, not obligation: a `.notPermitted` row may carry a remedy and may
    /// still, in a particular case, have none worth offering.
    public var mayOfferRemedy: Bool { self == .notPermitted }

    /// Whether a check containing this can still call itself complete. See the table above.
    ///
    /// ⚠️ **Read this as "could a person have made this run see more".** Only `.notPermitted`
    /// answers yes, and only that answer earns a caveat on Overview — because only that caveat can
    /// ever be cleared.
    public var stillComplete: Bool { self != .notPermitted }
}

/// The button on a `.notPermitted` row — the one refusal a person can lift — and where it goes.
///
/// The pane is a *name*, not a URL. Every `x-apple.systempreferences:` link in the app lives in
/// one file in the app layer (`SystemSettingsPane`), because those anchors are internal names
/// Apple renames without notice — a Core module that baked one in would rot the day macOS 27
/// reorganised the sidebar, and rot invisibly, since a wrong anchor still opens *a* pane.
public struct Remedy: Sendable, Hashable, Codable {
    /// The button's words. A verb that says exactly what pressing it does.
    public let title: String
    /// The raw value of a `SystemSettingsPane` case in the app layer, or `nil` for a button that
    /// does something else entirely.
    public let settingsPane: String?

    public init(title: String, settingsPane: String? = nil) {
        self.title = title
        self.settingsPane = settingsPane
    }
}

// MARK: - A number worth keeping

/// A reading as a number, so that two runs can be compared.
///
/// ⚠️ **This is the reason the reading history is worth writing at all.** `Reading.measure` is
/// "1,240 cycles" — correct for the eye and useless to arithmetic. Four of the sentences this
/// section eventually wants ("slower than usual for this Mac", "the battery has lost 4 points
/// since March") are subtraction on this field, and none of them can be back-filled: macOS keeps
/// days of history and Wellkept keeps for ever, but only starting from the first launch.
///
/// `nil` on a `Reading` is a normal answer — Apple's S.M.A.R.T. verdict is a word, not a number.
public struct ReadingNumber: Sendable, Hashable, Codable {
    public let value: Double
    /// The unit, as a short symbol. Use the constants below so two readers cannot spell the same
    /// unit two ways and make the history uncomparable.
    public let unit: String

    public init(_ value: Double, _ unit: String) {
        self.value = value
        self.unit = unit
    }

    public static let percent = "%"
    public static let megabytesPerSecond = "MB/s"
    public static let cycles = "cycles"
    public static let gigabytes = "GB"
    public static let count = "count"
    public static let days = "days"
}

// MARK: - A detail behind Options

/// One label-and-value pair, shown behind the section's **Options** disclosure.
///
/// ⚠️ **Built label-above-value, never as a two-column table.** A table with a fixed left column
/// breaks at 200% text: the labels wrap to four lines and the numbers drift away from what they
/// describe. This type carries no layout — it exists so that every detail in the app is the same
/// two strings, and the one view that draws them decides how, once.
public struct DetailPair: Sendable, Hashable, Codable, Identifiable {
    /// What it is: "Capacity", "Cycle count", "Connection".
    public let label: String
    /// Already formatted for a person. A reader that has nothing to put here uses the
    /// `Unreadable` initializer rather than writing "0" or "—".
    public let value: String
    /// A serial number, or anything else a person might not want on a screenshot.
    ///
    /// It changes nothing about how the pair is drawn. It exists so the "copy this for a repair
    /// shop" button can show, before anything reaches the clipboard, exactly which lines are the
    /// identifying ones.
    public let sensitive: Bool

    public var id: String { label }

    public init(_ label: String, _ value: String, sensitive: Bool = false) {
        self.label = label
        self.value = value
        self.sensitive = sensitive
    }

    /// A detail we could not read, in the house sentence rather than a dash.
    public init(_ label: String, unreadable: Unreadable) {
        self.init(label, unreadable.sentence, sensitive: false)
    }
}

// MARK: - One row's result

/// What one reader found: a headline in plain words, a measure where there is one, and whatever
/// detail is worth keeping behind Options.
///
/// ## The two states that are not "a number"
///
/// - `unreadable != nil` — we could not read it. `measure` and `number` are `nil`, and the
///   headline is the house sentence.
/// - `severity == .information` with no measure — a fact worth stating that has no figure, such
///   as a Mac with no battery.
///
/// ## ⚠️ Worn but working is never a problem
///
/// A battery past its rated cycle count still holding 83% is a battery doing its job in year
/// four. It says so plainly and stays `.information`. Marking it a problem produces a warning the
/// user cannot clear by any action, on a machine that is working — and every one of those teaches
/// a person that this app's warnings can be ignored, which costs us the one warning that matters.
public struct Reading: Sendable, Hashable, Identifiable, Codable {

    public let topic: HardwareTopic

    /// The row's own sentence, in plain words: "Apple's drive check says the drive is fine."
    /// Never a raw value, never a unit on its own.
    public let headline: String

    /// The figure, formatted for a person — "95%", "1,240 cycles", "2,900 MB/s". `nil` where
    /// there is nothing to measure.
    public let measure: String?

    /// The same figure as arithmetic, for the reading history. See `ReadingNumber`.
    public let number: ReadingNumber?

    /// How much this matters. `.problem` **only where something is actually wrong.**
    public let severity: Severity

    /// Why it says what it says, where that is not obvious from the headline. Shown on the row,
    /// never behind a disclosure — a flagged row with no reason is an accusation, and the reason
    /// is what lets a person disagree with us.
    public let reason: String?

    /// Everything else worth knowing, shown behind **Options**.
    public let details: [DetailPair]

    /// Set when the reader could not read this at all.
    public let unreadable: Unreadable?

    /// The button on an unreadable row. See the invariant on `init`.
    public let remedy: Remedy?

    public var id: HardwareTopic { topic }

    /// The row's status chip, in the app's three words.
    ///
    /// **Computed, not stored, and deliberately.** A stored status is a second opinion that can
    /// disagree with the severity beside it, and the first time that happens the row shows "Good"
    /// above a sentence describing a failure. Derived, it cannot drift:
    ///
    /// - could not read it → `.notChecked` (we did not check it; saying "Good" would be a lie)
    /// - something is wrong → `.needsAttention`
    /// - otherwise → `.good`
    public var status: SectionStatus {
        if unreadable != nil { return .notChecked }
        return severity >= .attention ? .needsAttention : .good
    }

    /// Whether this row leaves the check able to call itself complete.
    public var complete: Bool { unreadable?.stillComplete ?? true }

    /// ⚠️ **`remedy` is dropped unless `unreadable == .notPermitted`** — the one refusal a person
    /// can actually lift.
    ///
    /// Enforced here rather than trusted to five call sites. "Only a refusal somebody can lift gets
    /// a button" is a rule about what the user is offered, and a rule enforced by everyone
    /// remembering it is a rule that lasts until the fourth reader is written by somebody who read
    /// a different file.
    public init(topic: HardwareTopic,
                headline: String,
                measure: String? = nil,
                number: ReadingNumber? = nil,
                severity: Severity = .information,
                reason: String? = nil,
                details: [DetailPair] = [],
                unreadable: Unreadable? = nil,
                remedy: Remedy? = nil) {
        self.topic = topic
        self.headline = headline
        self.measure = unreadable == nil ? measure : nil
        self.number = unreadable == nil ? number : nil
        self.severity = severity
        self.reason = reason
        self.details = details
        self.unreadable = unreadable
        self.remedy = (unreadable?.mayOfferRemedy ?? false) ? remedy : nil
    }

    /// A row we could not read, in the house sentence.
    ///
    /// `headline` defaults to `why.sentence(about: topic.label)` — "Battery — this Mac does not
    /// report it." Pass one only where a more specific noun reads better: "Drive wear", "Kernel
    /// panics".
    public static func unreadable(_ topic: HardwareTopic,
                                  _ why: Unreadable,
                                  about thing: String? = nil,
                                  reason: String? = nil,
                                  details: [DetailPair] = [],
                                  remedy: Remedy? = nil) -> Reading {
        Reading(topic: topic,
                headline: why.sentence(about: thing ?? topic.label),
                severity: .information,
                reason: reason,
                details: details,
                unreadable: why,
                remedy: remedy)
    }
}

// MARK: - What this Mac is

/// The "what this Mac is" block at the top of the section.
///
/// ⚠️ **Inventory, never a verdict. This type can never say Needs attention**, and it carries no
/// status for that reason — there is no arrangement of these fields that constitutes a fault.
/// A 2019 iMac is not broken for being a 2019 iMac.
///
/// The one thing here that a person genuinely needs told is `standing`: whether Apple still ships
/// security updates for what this Mac can run. John's instruction, 2026-08-27: say it plainly,
/// and frame it as security rather than as a reason to buy a machine. That sentence appears in
/// this block as a statement of fact; only the case where the updates have actually stopped is
/// ever promoted to a problem.
public struct MachineFacts: Sendable, Hashable, Codable {

    /// What the Mac calls itself — "John's MacBook Air".
    public let name: String
    /// The marketing name: "MacBook Air (15-inch, M3, 2024)". Where the model is not in the
    /// shipped table, readers put the identifier here rather than inventing a name.
    public let modelName: String
    /// "Mac15,13". Kept alongside the marketing name because it is the thing a repair shop and a
    /// support page both ask for.
    public let modelIdentifier: String
    /// "Apple M3", "3.6 GHz 8-Core Intel Core i9".
    public let chip: String
    /// Already formatted: "8 GB".
    public let memory: String
    /// Already formatted: "460 GB".
    public let driveSize: String
    /// "macOS 26.6.2".
    public let systemVersion: String
    /// 26. Kept separately because `standing` is arithmetic on it and parsing a display string
    /// back into a number is how a locale eventually breaks a verdict.
    public let systemMajorVersion: Int
    /// When this Mac was first set up, as best it can be told. `nil` where it cannot.
    public let inUseSince: Date?
    /// `nil` where it could not be read. Never a placeholder string.
    public let serialNumber: String?
    /// Set by `VirtualMachine` in the app layer. Every hardware reading inside a VM is fiction —
    /// a confident verdict on a battery that does not exist is the kind of thing that costs an
    /// app its credibility in one screenshot.
    public let isVirtualMachine: Bool

    public init(name: String,
                modelName: String,
                modelIdentifier: String,
                chip: String,
                memory: String,
                driveSize: String,
                systemVersion: String,
                systemMajorVersion: Int,
                inUseSince: Date? = nil,
                serialNumber: String? = nil,
                isVirtualMachine: Bool = false) {
        self.name = name
        self.modelName = modelName
        self.modelIdentifier = modelIdentifier
        self.chip = chip
        self.memory = memory
        self.driveSize = driveSize
        self.systemVersion = systemVersion
        self.systemMajorVersion = systemMajorVersion
        self.inUseSince = inUseSince
        self.serialNumber = serialNumber
        self.isVirtualMachine = isVirtualMachine
    }

    /// This model in the shipped table, or `nil` if it is newer than this build of Wellkept.
    public var model: MacModel? { MacModels.model(for: modelIdentifier) }

    /// Where this Mac sits in Apple's support window. `.unknown` for a model the shipped table
    /// has never heard of, which is the honest answer for a Mac released after this build.
    public func standing(asOf date: Date = Date()) -> SupportStanding {
        MacModels.standing(for: modelIdentifier, runningMacOS: systemMajorVersion, asOf: date)
    }

    /// The block, as rows, in a fixed order.
    ///
    /// The serial number is last and marked `sensitive`, so a screenshot taken from the top of
    /// the block does not carry it and the repair-shop copy can say what it is about to include.
    public var detailPairs: [DetailPair] {
        var rows: [DetailPair] = [
            DetailPair("Name", name),
            DetailPair("Model", modelName),
            DetailPair("Model identifier", modelIdentifier),
            DetailPair("Chip", chip),
            DetailPair("Memory", memory),
            DetailPair("Drive", driveSize),
            DetailPair("macOS", systemVersion),
        ]
        if let inUseSince {
            rows.append(DetailPair("In use since",
                                   inUseSince.formatted(date: .abbreviated, time: .omitted)))
        }
        if isVirtualMachine {
            rows.append(DetailPair("Machine", "A virtual machine, not real hardware"))
        }
        if let serialNumber {
            rows.append(DetailPair("Serial number", serialNumber, sensitive: true))
        }
        return rows
    }

    /// The placeholder a view draws before anything has been read. Every field says so; nothing
    /// here is a guess dressed as a fact.
    public static let unknown = MachineFacts(
        name: "This Mac",
        modelName: "Not checked yet",
        modelIdentifier: "—",
        chip: "Not checked yet",
        memory: "—",
        driveSize: "—",
        systemVersion: "—",
        systemMajorVersion: 0
    )
}

// MARK: - The whole section's answer

/// Everything one run of the Hardware check produced.
public struct HardwareReport: Sendable, Hashable {

    public let facts: MachineFacts
    /// Always in `HardwareTopic` order, whatever order the readers finished in. Duplicates are
    /// dropped, first one wins.
    public let readings: [Reading]
    public let ranAt: Date

    /// The single row Hardware sends up to Overview, or `nil` when nothing here needs a person.
    ///
    /// ⚠️ **One row, not one per reading.** Overview lists what needs you; a section that posts
    /// five rows there has turned the summary into a second copy of itself, and the section a
    /// person should actually open gets lost among its own details.
    ///
    /// Stored rather than computed so its `id` is stable: a `Finding` recomputed on every draw is
    /// a new identity every draw, which is how a list animates itself to pieces.
    public let overviewFinding: Finding?

    public init(facts: MachineFacts, readings: [Reading], ranAt: Date = Date()) {
        self.facts = facts

        var seen = Set<HardwareTopic>()
        self.readings = readings
            .filter { seen.insert($0.topic).inserted }
            .sorted { $0.topic.order < $1.topic.order }

        self.ranAt = ranAt
        self.overviewFinding = Self.summarise(readings: self.readings,
                                              facts: facts,
                                              asOf: ranAt)
    }

    /// The section's status chip.
    ///
    /// A reading we could not take does not make the section "Not checked" — we checked, and
    /// found that this Mac does not report that one thing. `.notChecked` here is reserved for a
    /// section with no readings at all.
    public var status: SectionStatus {
        if readings.isEmpty { return .notChecked }
        return readings.contains { $0.status == .needsAttention } ? .needsAttention : .good
    }

    /// Whether this run saw everything it set out to see.
    ///
    /// ⚠️ **Only `.notPermitted` makes a check incomplete** — a refusal the person can lift. See
    /// the table on `Unreadable`: a Mac that does not report drive wear was fully checked, and a
    /// standard account that cannot read the panic log saw everything that account was ever going
    /// to see. Marking either one permanently incomplete would put a caveat on Overview that no
    /// user could ever clear.
    public var complete: Bool { readings.allSatisfy(\.complete) }

    /// The line this run contributes to the app's audit trail.
    public var record: CheckRecord {
        CheckRecord(section: .hardware, ranAt: ranAt, status: status, complete: complete)
    }

    public func reading(_ topic: HardwareTopic) -> Reading? {
        readings.first { $0.topic == topic }
    }

    /// Everything on this Mac that could not be read, with the reason, for the section to state
    /// once rather than five times.
    public var unreadableTopics: [(topic: HardwareTopic, why: Unreadable)] {
        readings.compactMap { r in r.unreadable.map { (r.topic, $0) } }
    }

    // MARK: The one row for Overview

    private static func summarise(readings: [Reading],
                                  facts: MachineFacts,
                                  asOf date: Date) -> Finding? {
        // A verdict taken inside a virtual machine is a verdict about a file on somebody's disk.
        // Saying so is the only honest row available, and it outranks every reading below it.
        if facts.isVirtualMachine {
            return Finding(section: .hardware,
                           title: "This is a virtual machine",
                           reason: "The hardware readings below describe a simulated Mac, not real hardware, so nothing here says anything about a physical machine.",
                           severity: .attention)
        }

        var candidates: [(severity: Severity, title: String, reason: String, measure: String?)] =
            readings
                .filter { $0.severity >= .attention }
                .sorted { $0.severity > $1.severity }
                .map { ($0.severity, $0.headline, $0.reason ?? $0.topic.explanation, $0.measure) }

        // Out of security updates is not a hardware fault, and it is the one thing in the "what
        // this Mac is" block a person genuinely needs told. John, 2026-08-27: say it plainly, as
        // security rather than as obsolescence.
        let standing = facts.standing(asOf: date)
        if standing.severity >= .attention {
            candidates.append((standing.severity,
                               "This Mac no longer gets security updates",
                               standing.sentence,
                               nil))
        }

        guard let worst = candidates.max(by: { $0.severity < $1.severity }) else { return nil }
        let others = candidates.count - 1
        let reason = others > 0
            ? "\(worst.reason) And \(others) more in Hardware."
            : worst.reason

        return Finding(section: .hardware,
                       title: worst.title,
                       reason: reason,
                       severity: worst.severity,
                       measure: worst.measure)
    }

    // MARK: Copy for a repair shop

    /// Plain text a person can paste into an email to a repair shop or a support thread.
    ///
    /// ⚠️ **The caller must show this to the user before it reaches the clipboard**, serial
    /// number included. Something that quietly copies an identifying number is doing the thing
    /// this app exists to catch other software doing.
    public func clipboardText(includeSerial: Bool = true) -> String {
        var lines: [String] = ["Wellkept — \(facts.name)",
                               ShortDate.stamp(ranAt)]
        if facts.isVirtualMachine {
            lines.append("⚠️ Virtual machine — these readings are not real hardware.")
        }
        lines.append("")

        for pair in facts.detailPairs where includeSerial || !pair.sensitive {
            lines.append("\(pair.label): \(pair.value)")
        }

        for reading in readings {
            lines.append("")
            lines.append("\(reading.topic.label): \(reading.headline)")
            if let measure = reading.measure { lines.append("  \(measure)") }
            if let reason = reading.reason { lines.append("  \(reason)") }
            for pair in reading.details where includeSerial || !pair.sensitive {
                lines.append("  \(pair.label): \(pair.value)")
            }
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Dates, once

/// The one date format Core writes into text a person will read outside a view.
///
/// Views use `ShellFormat.when`. This exists because `clipboardText` and the reading history are
/// not views and must not each grow their own format string.
public enum ShortDate {
    /// "27 Aug 2026 at 2:32 PM", in the reader's own region.
    public static func stamp(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Storage conformances

// The reading history is written as JSON and cannot be rebuilt, so the two vocabulary enums it
// stores have to survive a round trip. Both are `String`-backed, which is what makes their raw
// values permanent and their labels free to change — see the header of `Vocabulary.swift`.
extension SectionStatus: Codable {}
extension Severity: Codable {}

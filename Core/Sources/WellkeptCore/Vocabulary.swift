import Foundation

//  Vocabulary.swift
//  WellkeptCore
//
//  The words the whole app agrees on. Nothing here imports SwiftUI, so the vocabulary can be
//  tested without building a view, and so a section's engine (later) can produce results without
//  knowing anything about how they are drawn.
//
//  ⚠️ **A raw value is storage. A label is English. They are separate on purpose, in every enum
//  below.** The raw values are written into UserDefaults and into the saved audit trail, so
//  renaming one is a migration — a released build that reads `needsAttention` back as an unknown
//  string forgets that a Mac had a problem. The labels are what a person reads, and John edits
//  those; making a word better must be a one-line change to `label`, never a schema change.
//  This is why `SectionStatus.needsAttention.rawValue` is "needsAttention" and its label is
//  "Needs attention", and why the two are allowed to drift apart forever.

// MARK: - The seven sections

/// The seven things Wellkept looks at, in the order the sidebar shows them.
///
/// `allCases` **is** the sidebar order — fixed, never sorted, never reordered by findings. A list
/// that rearranges itself is a list you have to re-read every time you open the app.
public enum SectionID: String, CaseIterable, Sendable, Identifiable {
    case overview, hardware, storage, apps, security, backup, changes

    public var id: String { rawValue }

    /// Sidebar row and page heading. The same word in both places, so the heading confirms the
    /// click rather than renaming the destination.
    public var title: String {
        switch self {
        case .overview: "Overview"
        case .hardware: "Hardware"
        case .storage:  "Storage"
        case .apps:     "Apps"
        case .security: "Security"
        case .backup:   "Backup"
        case .changes:  "Changes"
        }
    }

    /// The question this section answers, in the user's words rather than the app's. Used where
    /// the app has to explain itself — Help, the welcome page, an empty state.
    public var question: String {
        switch self {
        case .overview: "Is my Mac OK?"
        case .hardware: "Is this machine healthy?"
        case .storage:  "What's eating my space?"
        case .apps:     "What's installed, and is it current?"
        case .security: "Am I safe?"
        case .backup:   "Is my stuff safe?"
        case .changes:  "What changed, and who changed it?"
        }
    }

    /// The one plain sentence on the section's face, directly above its button.
    ///
    /// It says what pressing the button will actually do. That is the one thing a person cannot
    /// work out from the screen, and the reason this is information rather than clutter: an app
    /// that reads your disk owes you a sentence about what it is reading.
    public var sentence: String {
        switch self {
        case .overview: "Check everything, and say what needs you."
        // ⚠️ **The word "temperature" was removed on 2026-08-27, and must not come back.** The
        // section reports no temperature in degrees: the reading moved 62 → 79 → 58 °C in three
        // minutes on an idle Mac, the route to it is undocumented, and nobody — Apple included —
        // publishes what is too hot. A sentence promising a temperature above a screen that does
        // not show one is a promise the section cannot keep.
        case .hardware: "Read the drive, the battery, the memory and this Mac's restart history, and report what they say."
        case .storage:  "Look at what is using the space on this Mac, largest first."
        case .apps:     "List every app, where it came from, and whether a newer version exists."
        case .security: "Check this Mac's protections, what can watch you, and what macOS has already found."
        case .backup:   "Check whether your files are backed up, and what is not covered."
        case .changes:  "Compare your settings against the last time we looked."
        }
    }

    /// The section's one button. Every verb says exactly what it does, and the set is fixed
    /// app-wide — no screen invents a synonym.
    public var verb: String {
        switch self {
        case .overview: "Check my Mac"
        case .hardware: "Check hardware"
        case .storage:  "Scan storage"
        case .apps:     "Check apps"
        case .security: "Check security"
        case .backup:   "Check backup"
        case .changes:  "Check for changes"
        }
    }

    /// The six sections Overview summarises — everything except Overview itself.
    ///
    /// Named rather than written as `allCases.dropFirst()` at each call site: "drop the first one"
    /// is correct only for as long as `overview` stays first, and a seventh section added in the
    /// wrong place would silently remove Hardware from every audit trail in the app.
    public static var checkable: [SectionID] { allCases.filter { $0 != .overview } }
}

// MARK: - Status

/// What a section has to say about itself, in the three words the whole app uses.
///
/// There is no fourth state and there is never a score. A number invites the user to chase it,
/// and a Mac with nothing wrong would then be graded on how little it happened to have installed.
public enum SectionStatus: String, Sendable, CaseIterable {
    /// Checked, and nothing is wrong.
    case good
    /// Checked, and at least one thing is a problem.
    case needsAttention
    /// Not run yet, or run against a permission we did not have.
    case notChecked

    public var label: String {
        switch self {
        case .good:           "Good"
        case .needsAttention: "Needs attention"
        case .notChecked:     "Not checked"
        }
    }
}

// MARK: - Severity

/// How much a finding matters.
///
/// ⚠️ **`.problem` ONLY where something is actually wrong.** A 40 GB folder is not a problem, it
/// is large — Wellkept revealed it, and calling it a problem would be the app telling the user
/// their own files are a fault. Anything Wellkept merely *reveals* is `.information`. This is the
/// distinction the product is built on; getting it wrong turns a health check into a scareware
/// cleaner, which is the entire category this app exists to not be.
public enum Severity: String, Sendable, Comparable, CaseIterable {
    /// Something is wrong: a failing drive, a disabled firewall, a backup that has not run.
    case problem
    /// Not wrong yet, but heading there: a disk at 92%, a battery at 78% health.
    case attention
    /// A fact, revealed. Never a fault.
    case information

    public var label: String {
        switch self {
        case .problem:     "Problem"
        case .attention:   "Needs attention"
        case .information: "Information"
        }
    }

    /// Sort order, most severe last — so `max()` finds the worst and a descending sort puts
    /// problems at the top of Overview.
    private var rank: Int {
        switch self {
        case .information: 0
        case .attention:   1
        case .problem:     2
        }
    }

    public static func < (a: Severity, b: Severity) -> Bool { a.rank < b.rank }
}

// MARK: - A finding

/// A thing Wellkept found.
public struct Finding: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let section: SectionID
    /// What it is, in a few words. Goes on the row.
    public let title: String
    /// **Why it was flagged.** Always present, always shown on the row, never behind a disclosure.
    /// A flagged item with no reason is an accusation; the reason is what lets the user disagree.
    public let reason: String
    public let severity: Severity
    /// The measurement, already formatted for a human — "4.2 GB", "83%", "14 days ago". `nil`
    /// where there is nothing to measure. Formatted at the boundary, never a raw byte count.
    public let measure: String?
    /// The verb that sits on this row, if this row has one — "Reveal in Finder", "Open Settings".
    /// `nil` means the row is words only.
    public let verb: String?

    public init(id: UUID = UUID(),
                section: SectionID,
                title: String,
                reason: String,
                severity: Severity,
                measure: String? = nil,
                verb: String? = nil) {
        self.id = id
        self.section = section
        self.title = title
        self.reason = reason
        self.severity = severity
        self.measure = measure
        self.verb = verb
    }
}

// MARK: - The audit trail

/// One line of the audit trail: what was checked, and when.
///
/// `complete` is the field that keeps Overview honest. A check that ran without Full Disk Access
/// saw part of the machine, and Overview may never say a Mac looks fine on the strength of a
/// partial look — so the flag travels with the record rather than being inferred later from
/// whichever permissions happen to be granted at the moment the summary is drawn.
public struct CheckRecord: Sendable, Hashable {
    public let section: SectionID
    public let ranAt: Date
    public let status: SectionStatus
    /// `false` when a permission stopped us seeing everything.
    public let complete: Bool

    public init(section: SectionID, ranAt: Date, status: SectionStatus, complete: Bool) {
        self.section = section
        self.ranAt = ranAt
        self.status = status
        self.complete = complete
    }
}

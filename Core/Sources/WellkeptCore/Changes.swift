// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation

//  Changes.swift
//  WellkeptCore
//
//  **The words the Changes section agrees on, and the shape a snapshot, a difference and a cause
//  are allowed to take.**
//
//  Three files in the app layer compile against this one without seeing each other:
//  `SnapshotStore` (what was true at each launch), `Attribution` (when, and how much of why the
//  evidence supports) and `Diff` (what is different). Nothing here imports SwiftUI or Darwin: the
//  vocabulary has to be testable without a window and without a machine.
//
//  ## ⚠️ The measured truth this file is built around
//
//  Measured by hand on an M3 running macOS 26, 2026-08-28, all read-only. `CHANGES-QUESTIONS.md`
//  has the whole survey; these are the four findings that shaped the types.
//
//  1. **We can say WHEN. We can never say WHO.** Nothing an unprivileged app can read records
//     which process wrote a setting. So `Cause` has **no case for "an app did it"**, and there is
//     a test that fails the build if anybody adds one. Naming somebody's software as the culprit
//     would be an accusation on no evidence, and it would be wrong often.
//  2. **The strongest honest sentence is a coincidence stated as a coincidence**: *"this changed
//     while your Mac was off for the macOS 26.6.2 update — it was off for four minutes and 52
//     seconds."* **Changed during, never the update changed it.** See `Cause.duringMacOSUpdate`
//     and `MacOSUpdate.sentence`.
//  3. **A restart is not evidence of an update** — 15 of this Mac's 25 boots carried none. A boot
//     alone can never build a `MacOSUpdate`; the install record has to name one in the window.
//  4. **Unknown is the ordinary answer, not an error.** Most changes on most Macs will land with
//     `Cause.unknown`, and the face has to read as calm when they do. `Confidence.noEvidence` is
//     the default value of the field for exactly that reason.
//
//  ## ⚠️ The scope, settled by John on 2026-08-28, and it is smaller than it looks
//
//  Changes **describes** only what Wellkept already reads elsewhere — the Security section's
//  protections, sharing services, startup items, configuration profiles and privacy grants, plus
//  macOS's own version. That is what `Watched.all` is: about thirty things, each with a
//  description we wrote and can defend.
//
//  It **records** everything readable, from the first launch, because a record cannot be
//  back-filled. `Snapshot.settings` is the full capture — 63 KB, 0.77 seconds — and nothing in
//  this version reads it back. Version two arrives with a year of history instead of an empty
//  file. The two halves are deliberately separate fields so that "we describe less than we keep"
//  is a property of the type rather than a promise in a comment.
//
//  A difference in `settings` that no `Watched` describes is **counted and never listed** — see
//  `ChangesReport.undescribed`. A row we cannot explain is a row that worries somebody for no
//  reason, and 383 of the 787 descriptions in the prior art everybody points at are flagged
//  AI-generated. We would rather say "and 41 other things we do not yet explain" than print 41
//  rows of raw preference keys.

// MARK: - The five rows

/// The five things Changes reports on, in the order they are drawn.
///
/// ⚠️ **`allCases` IS the row order, and this list never sorts.** Same rule as `SecurityTopic`:
/// a person who learns that macOS itself is the last row should find it there next week.
///
/// **Why this order, and why it is not `SecurityTopic`'s order.** Security is a panel somebody
/// browses, so it is ordered the way you would read a dashboard. Changes is a list of things that
/// happened without being announced, so it is ordered by **how much a silent change costs you**:
///
/// 1. `protections` — a switch that protected you and no longer does. Nothing else on this list
///    can cost you the whole machine.
/// 2. `reachableFrom` — a door to this Mac that opened. Worse than anything below it because the
///    change is visible from outside the house.
/// 3. `startsOnItsOwn` — something new that runs whether or not you asked. This is where a
///    configuration profile appearing on a Thursday shows up.
/// 4. `whoCanWatch` — an app that gained the camera, the microphone or the screen. Below the
///    three above only because it is bounded: one app, one permission, and macOS asked somebody.
/// 5. `macOSItself` — the version. Last on purpose: it is the one row that is **never a fault**,
///    and it is usually the explanation for the rows above it rather than a finding of its own.
///
/// Raw values are storage and are written into every snapshot on disk. They are permanent.
public enum ChangesTopic: String, CaseIterable, Sendable, Identifiable, Codable, Hashable {

    /// FileVault, the firewall, Gatekeeper, system protection, secure boot, automatic security
    /// updates, automatic login.
    case protections

    /// Screen Sharing, Remote Login, File Sharing, Remote Management, AirPlay Receiver.
    case reachableFrom

    /// Login items, launch agents and daemons, scheduled jobs, configuration profiles.
    case startsOnItsOwn

    /// Which apps hold the camera, the microphone, the screen, and the other privacy grants.
    case whoCanWatch

    /// The version of macOS on this Mac.
    case macOSItself

    public var id: String { rawValue }

    /// The row's name, as it is drawn. Deliberately the same English as the Security section
    /// wherever the two describe the same thing — a person who learned it once has learned it.
    public var label: String {
        switch self {
        case .protections:    "Protections"
        case .reachableFrom:  "What can reach this Mac"
        case .startsOnItsOwn: "What starts on its own"
        case .whoCanWatch:    "Who can watch you"
        case .macOSItself:    "macOS itself"
        }
    }

    /// What a change in this row means, in one plain sentence.
    public var explanation: String {
        switch self {
        case .protections:
            "A protection built into macOS that is not set the way it was the last time we looked."
        case .reachableFrom:
            "A service that lets another machine reach this one, which was not doing that before."
        case .startsOnItsOwn:
            "Something that now starts by itself, or has stopped doing so, since we last looked."
        case .whoCanWatch:
            "An app that has gained or lost the camera, the microphone, the screen, or another permission."
        case .macOSItself:
            "The version of macOS this Mac is running."
        }
    }

    /// Sort position, so a caller that collected rows out of order can put them back.
    public var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

// MARK: - ⭐ One thing we understand well enough to describe

/// The stable identity of one watched thing.
///
/// ⚠️ **`storageKey` is written into every snapshot on disk and is permanent.** Renaming one
/// silently breaks the comparison against every snapshot already taken, which is the one thing in
/// this section that cannot be recreated by running the check again. `title` is English and may be
/// edited freely; the two are allowed to drift apart forever.
public struct WatchedKey: Sendable, Hashable, Codable, Identifiable, Comparable {

    public let topic: ChangesTopic
    /// A short, permanent name, unique within the topic. Lower camel case, matching the case name
    /// of whatever reader enum it mirrors — `fileVault`, `screenSharing`, `screenRecording`.
    public let name: String

    public init(_ topic: ChangesTopic, _ name: String) {
        self.topic = topic
        self.name = name
    }

    /// What goes in the snapshot file. Never shown to anybody.
    public var storageKey: String { "\(topic.rawValue).\(name)" }

    public var id: String { storageKey }

    /// Parse a key back out of a snapshot. `nil` for a key written by a build that watched
    /// something this one does not — which is a normal thing to meet in a file that outlives a
    /// release, not an error.
    public init?(storageKey: String) {
        guard let dot = storageKey.firstIndex(of: "."), dot != storageKey.startIndex else { return nil }
        guard let topic = ChangesTopic(rawValue: String(storageKey[storageKey.startIndex..<dot])) else {
            return nil
        }
        let name = String(storageKey[storageKey.index(after: dot)...])
        guard !name.isEmpty else { return nil }
        self.init(topic, name)
    }

    public static func < (a: WatchedKey, b: WatchedKey) -> Bool {
        a.topic.order == b.topic.order ? a.name < b.name : a.topic.order < b.topic.order
    }
}

/// One thing Wellkept watches, carrying **our own three-part description**.
///
/// ## ⚠️ Why the description is a type with three required parts
///
/// The prior art everybody points at — SetShot's knowledge base — is 787 one-line descriptions,
/// 383 of them flagged AI-generated, and none of them attempt the two things a person actually
/// needs. John's instruction on 2026-08-28 was *"let's show him up and do it better"*, and better
/// was defined concretely: every description says **what the setting does**, **what turning it off
/// actually costs you**, and **why it might have changed**.
///
/// Three separate stored properties with no defaults is the enforcement. A one-line description
/// cannot be written by accident, because there is no initialiser that accepts one — and
/// `Description.isComplete`, exercised over the whole catalogue by
/// `ChangesDescriptionTests.everyWatchedThingSaysAllThreeThings`, fails the build on a description
/// that fills the third field by repeating the first.
public struct Watched: Sendable, Hashable, Codable, Identifiable {

    /// The three sentences, and there must be three different ones.
    public struct Description: Sendable, Hashable, Codable {

        /// What the setting does. Present tense, plain words, no jargon.
        public let does: String
        /// **What turning it off actually costs you.** Not "reduces security" — what stops
        /// working, or what somebody else can now do.
        public let costOfTurningItOff: String
        /// **Why it might have changed.** The ordinary, innocent reasons first, because they are
        /// the usual answer, and the alarming one only where it is real.
        public let whyItMightHaveChanged: String

        public init(does: String, costOfTurningItOff: String, whyItMightHaveChanged: String) {
            self.does = does
            self.costOfTurningItOff = costOfTurningItOff
            self.whyItMightHaveChanged = whyItMightHaveChanged
        }

        /// Whether this is three real sentences rather than one sentence typed three times.
        ///
        /// The length floor is deliberately low — it catches "N/A", "See above" and an empty
        /// field, which is what actually goes wrong — and the distinctness check is what catches
        /// the copy-paste. Neither is a judgement about quality; that is a human's job, and John's.
        public var isComplete: Bool {
            let parts = [does, costOfTurningItOff, whyItMightHaveChanged]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.allSatisfy({ $0.count >= 20 && $0.hasSuffix(".") }) else { return false }
            return Set(parts).count == 3
        }

        /// The three, in order, for a view that draws them one under the other.
        public var sentences: [String] { [does, costOfTurningItOff, whyItMightHaveChanged] }
    }

    public let key: WatchedKey
    /// What it is called on the row. English, editable, never storage.
    public let title: String
    public let description: Description

    /// The value that protects you, where one of the two values is safer than the other, spelled
    /// exactly as the reader spells it.
    ///
    /// `nil` where neither value is better — the macOS version, the number of login items. This is
    /// the **only** thing that lets a change be `.attention` rather than `.information`, which
    /// keeps the "a large folder is not a problem" rule from being re-argued per row. See
    /// `Change.severity`.
    public let safeValue: String?

    /// The raw value of a `SystemSettingsPane` case in the app layer, or `nil` where macOS offers
    /// no pane for this.
    ///
    /// ⚠️ A *name*, never a URL — every `x-apple.systempreferences:` anchor in this app lives in
    /// one file in the app layer, because Apple renames them without notice and a wrong anchor
    /// still opens *a* pane, so the rot would be invisible.
    ///
    /// **This is a destination, not a verb.** John, 2026-08-28: Wellkept writes no setting, ever.
    /// There is no fifth verb; Changes shows what changed and opens the right pane.
    public let settingsPane: String?

    public var id: WatchedKey { key }

    public init(key: WatchedKey,
                title: String,
                description: Description,
                safeValue: String? = nil,
                settingsPane: String? = nil) {
        self.key = key
        self.title = title
        self.description = description
        self.safeValue = safeValue
        self.settingsPane = settingsPane
    }
}

// MARK: - How long the Mac was off

/// How exactly an outage was measured, because the two ends do not come from the same place.
///
/// ⚠️ **The boot instant is exact and the shutdown instant is not.** `kern.boottime` is a
/// microsecond value that any account can read; the record of when the Mac went *down* has
/// minute resolution. A sentence that says "four minutes and 52 seconds" on the strength of two
/// minute-resolution readings is inventing 52 seconds, so the precision travels with the
/// measurement and `Outage.sentence` says "about four minutes" when that is all we have.
public enum OutagePrecision: String, Sendable, Hashable, Codable {
    case toTheSecond
    case toTheMinute
}

/// The Mac was off, from one instant to another.
public struct Outage: Sendable, Hashable, Codable {

    /// When the Mac went down.
    public let wentDown: Date
    /// When it came back.
    public let cameBack: Date
    public let precision: OutagePrecision

    public init(wentDown: Date, cameBack: Date, precision: OutagePrecision) {
        self.wentDown = wentDown
        self.cameBack = cameBack
        self.precision = precision
    }

    public var seconds: Int { max(0, Int(cameBack.timeIntervalSince(wentDown).rounded())) }

    /// "four minutes and 52 seconds", or "about four minutes" where the seconds were not measured.
    ///
    /// Spelled out in words rather than "4m52s" because this appears mid-sentence in a line a
    /// person reads once.
    public var sentence: String {
        let total = seconds
        let minutes = total / 60
        let remainder = total % 60

        switch precision {
        case .toTheSecond:
            if minutes == 0 { return count(remainder, "second") }
            if remainder == 0 { return count(minutes, "minute") }
            return "\(count(minutes, "minute")) and \(count(remainder, "second"))"
        case .toTheMinute:
            // Rounded to the nearest minute, and never to zero: "about no time at all" is not a
            // measurement, and a sub-minute outage rounds up to the smallest thing we can say.
            let nearest = max(1, Int((Double(total) / 60).rounded()))
            return "about \(count(nearest, "minute"))"
        }
    }

    private func count(_ n: Int, _ noun: String) -> String {
        "\(Self.words[n] ?? String(n)) \(noun)\(n == 1 ? "" : "s")"
    }

    /// Small numbers as words, which is how they read in a sentence. Anything larger falls back to
    /// digits rather than inventing English for 143.
    private static let words: [Int: String] = [
        0: "no", 1: "one", 2: "two", 3: "three", 4: "four", 5: "five", 6: "six", 7: "seven",
        8: "eight", 9: "nine", 10: "ten", 11: "eleven", 12: "twelve",
    ]
}

/// A macOS update this Mac actually installed, taken from the install record.
///
/// ⚠️ **A restart is not evidence of an update.** 15 of this Mac's 25 recorded boots carried none.
/// This type can only be built from a named entry in the install record; a boot on its own cannot
/// produce one, and `Attribution` has no code path that tries.
public struct MacOSUpdate: Sendable, Hashable, Codable {

    /// "26.6.2". Apple's own version string, not one we composed.
    public let version: String

    /// When the install record says it went on.
    ///
    /// ⚠️ **The install record's dates are UTC.** macOS 26.6.2 reads as 25 August and happened on
    /// the evening of the 24th. This field is a real `Date`, so it is an instant rather than a
    /// day, and every place that turns it into a day must do so in the Mac's own time zone. Read
    /// it wrong and every update in the section lands a day out.
    public let installedAt: Date

    /// How long the Mac was off around it, where that could be measured. `nil` on a standard
    /// account, which cannot read the boot record — see `ChangesReport.outageUnreadable`.
    public let outage: Outage?

    public init(version: String, installedAt: Date, outage: Outage? = nil) {
        self.version = version
        self.installedAt = installedAt
        self.outage = outage
    }

    /// ⭐ **The strongest honest sentence this section has, and its wording is the whole point.**
    ///
    /// *"this changed while your Mac was off for the macOS 26.6.2 update — it was off for four
    /// minutes and 52 seconds."*
    ///
    /// **"while your Mac was off for", never "the update changed it".** The evidence is that two
    /// things happened in the same window. It is not evidence that one caused the other, and the
    /// difference between those two sentences is the difference between a fact and a guess.
    ///
    /// On a standard account the boot record is unreadable, so the outage half is missing and the
    /// sentence is honestly weaker: we still know the update happened and when, and we no longer
    /// know that the Mac was off — which was the evidence that made the claim strong.
    public var sentence: String {
        guard let outage else {
            return "this changed in the same period as the macOS \(version) update"
        }
        return "this changed while your Mac was off for the macOS \(version) update "
             + "— it was off for \(outage.sentence)"
    }
}

// MARK: - ⭐ Cause, and the case that will never exist

/// What the evidence supports about why something changed.
///
/// ⛔ **There is no case for "an app did it", and there must never be one.**
/// `ChangesCauseGuardTests` fails the build on any case whose name mentions an app, a process or a
/// culprit. Nothing an unprivileged app can read on macOS records which process wrote a setting,
/// and the one log that might forgets within a day. A case named `.changedByAnApp` would put a
/// piece of somebody's software on screen next to a security warning on the strength of a
/// coincidence — that is defamation with a nice typeface, and it would be wrong often.
///
/// ⚠️ **`.unknown` is the honest default and it must read as ordinary.** On most Macs most changes
/// will land here. A face that draws it as a failure teaches people that Wellkept is broken; a
/// face that draws it as a plain sentence teaches them what we actually know.
public enum Cause: Sendable, Hashable, Codable {

    /// It changed inside a window in which macOS installed an update.
    ///
    /// **A coincidence in time, stated as one.** See `MacOSUpdate.sentence`.
    case duringMacOSUpdate(MacOSUpdate)

    /// It changed between two launches, with no update and no restart in between — so the Mac was
    /// awake and somebody was at it. Still not *who*: "you" here means this Mac's keyboard, which
    /// is the strongest thing the evidence carries.
    case whileYouWereUsingTheMac

    /// An organisation's management profile forces this setting.
    ///
    /// The one cause we can state outright, because the profile is a readable file that names the
    /// setting it forces. It is also **never a fault** — `ChangesReport` drops the severity for
    /// these, for the same reason `SecurityReport` does: a Mac configured by an employer is not a
    /// Mac with something wrong with it, and the person reading the screen cannot act on it.
    case setByAnOrganisation

    /// Nothing we can read says anything about why. **The ordinary answer.**
    case unknown

    /// The clause, lower case, for building the row's sentence around.
    public var clause: String {
        switch self {
        case let .duringMacOSUpdate(update): update.sentence
        case .whileYouWereUsingTheMac:       "this changed while the Mac was in use"
        case .setByAnOrganisation:           "an organisation's profile sets this"
        case .unknown:                       "we cannot tell what changed it"
        }
    }

    /// Whether a change with this cause is allowed to raise the section.
    ///
    /// Only `.setByAnOrganisation` says no, and it says no for the whole section rather than per
    /// row. See `Change.severity`.
    public var mayRaiseSeverity: Bool { self != .setByAnOrganisation }
}

/// How much the evidence supports the cause. **Named cases, never a percentage** — a number here
/// would be invented, and an invented number is the most persuasive kind of wrong answer.
public enum Confidence: String, Sendable, Hashable, Codable, CaseIterable, Comparable {

    /// The evidence names the cause outright. In this version there is exactly one: a management
    /// profile that forces the setting by name.
    case certain

    /// The evidence is consistent with the cause, and we are saying so rather than concluding it.
    /// A change that landed inside a macOS update's window is this and never more.
    case consistent

    /// We have no evidence about the cause at all. **Ordinary, not an error.**
    case noEvidence

    public var label: String {
        switch self {
        case .certain:    "Certain"
        case .consistent: "Consistent with"
        case .noEvidence: "No evidence"
        }
    }

    private var rank: Int {
        switch self {
        case .noEvidence:  0
        case .consistent:  1
        case .certain:     2
        }
    }

    public static func < (a: Confidence, b: Confidence) -> Bool { a.rank < b.rank }
}

// MARK: - The window a change happened in

/// The two moments a change is trapped between: the snapshot that still had the old value, and the
/// one that had the new one.
///
/// ⚠️ **This is the whole of what we know about when.** We do not know the instant; we know it was
/// somewhere in here. Every sentence about timing has to be built from this rather than from a
/// file's modification date — three quarters of the preference files on this Mac were rewritten in
/// a single day by daemons that changed nothing, so a timestamp is not evidence of anything.
public struct Window: Sendable, Hashable, Codable {

    /// The snapshot that still showed the old value.
    public let after: Date
    /// The snapshot that showed the new one.
    public let before: Date

    /// The Mac was asleep or switched off for part of this window.
    ///
    /// ⚠️ **It has to be said, not glossed.** "Since Tuesday" reads as five days of use; if the
    /// Mac was shut for four of them, the sentence has quietly overstated how much happened while
    /// somebody was watching.
    public let macWasOffOrAsleep: Bool

    public init(after: Date, before: Date, macWasOffOrAsleep: Bool = false) {
        self.after = after
        self.before = before
        self.macWasOffOrAsleep = macWasOffOrAsleep
    }

    public var span: TimeInterval { before.timeIntervalSince(after) }

    /// "between 24 August and today", with the sleep caveat attached where it applies.
    public func sentence(now: Date = Date(), calendar: Calendar = .current) -> String {
        let start = calendar.isDateInToday(after)
            ? "earlier today"
            : after.formatted(date: .abbreviated, time: .omitted)
        let end = calendar.isDate(before, inSameDayAs: now)
            ? "now"
            : before.formatted(date: .abbreviated, time: .omitted)
        let core = "between \(start) and \(end)"
        return macWasOffOrAsleep ? "\(core), and this Mac was asleep or switched off for part of it"
                                 : core
    }
}

// MARK: - One difference

/// One thing that is not what it was.
public struct Change: Sendable, Hashable, Identifiable, Codable {

    public let key: WatchedKey

    /// What it is, on the row. Usually the `Watched.title`; for a privacy grant it names the
    /// instance too — "Zoom — Screen recording" — because the permission alone is not the news.
    public let what: String

    /// The previous value, **already in the words a person reads**: "On", "Off", "Not allowed".
    /// Never a raw plist value, and never a date.
    public let from: String
    public let to: String

    public let window: Window
    public let cause: Cause
    public let confidence: Confidence

    /// Stable across runs so a list does not reshuffle while somebody is reading it.
    public var id: String {
        "\(key.storageKey)|\(what)|\(Int(window.before.timeIntervalSince1970))"
    }

    /// ⚠️ **The initialiser is where cause and confidence are kept in step**, rather than trusting
    /// three call sites to remember. The same trick as `Protection.init` dropping a settings pane
    /// for an organisation-set switch: an invariant that lives in one place cannot be half-applied.
    ///
    /// - An `.unknown` cause is always `.noEvidence`. Claiming any confidence about a cause we do
    ///   not have is a contradiction, and it is the exact contradiction that would let a future
    ///   build slide "probably an app" back in through the confidence field.
    /// - A known cause is never `.noEvidence`. If there is no evidence, the cause is `.unknown`.
    public init(key: WatchedKey,
                what: String,
                from: String,
                to: String,
                window: Window,
                cause: Cause = .unknown,
                confidence: Confidence = .noEvidence) {
        self.key = key
        self.what = what
        self.from = from
        self.to = to
        self.window = window
        self.cause = cause
        switch cause {
        case .unknown:            self.confidence = .noEvidence
        case .setByAnOrganisation: self.confidence = .certain
        default:                  self.confidence = confidence == .noEvidence ? .consistent : confidence
        }
    }

    /// How much this matters.
    ///
    /// ⚠️ **`.attention` is the ceiling, and there is deliberately no route to `.problem`.** A
    /// change is a change; whether the *resulting state* is a problem is the Security section's
    /// question and it is answered there, once, through `SecurityConcern`. Two sections both
    /// deciding that FileVault being off is a problem is two places to fix it and two chances to
    /// disagree on screen.
    ///
    /// A setting an organisation forces is never raised at all — see `Cause.mayRaiseSeverity`.
    public func severity(_ watched: Watched?) -> Severity {
        guard cause.mayRaiseSeverity else { return .information }
        guard let safe = watched?.safeValue else { return .information }
        return to == safe ? .information : .attention
    }

    /// The row's own line: what it was, what it is, and what we can honestly say about why.
    public func sentence(now: Date = Date()) -> String {
        "\(what) went from \(from) to \(to) \(window.sentence(now: now)) — \(cause.clause)."
    }
}

// MARK: - What was true at one moment

/// Everything Wellkept could read at one launch.
///
/// ## ⚠️ Two maps, and the difference between them is the scope decision
///
/// - `watched` is the ~30 things we understand well enough to describe. It is what `Diff` compares
///   and what the face lists.
/// - `settings` is **everything readable**, captured from the first launch and read back by
///   nothing in this version. 0.77 seconds, 63 KB, 23 MB a year. A record cannot be back-filled:
///   a build that starts keeping this in eighteen months can answer nothing for two years, and one
///   that starts today can answer in six months. That asymmetry is the entire argument, and it is
///   the same one that put `ReadingHistory` in before anything read it.
public struct Snapshot: Sendable, Hashable, Codable, Identifiable {

    public let id: UUID
    public let takenAt: Date

    /// `kern.boottime`, exact to the microsecond and readable by any account with no permission at
    /// all. Two snapshots with different boot instants bracket a restart — which, on its own, is
    /// **not** evidence of an update.
    public let bootedAt: Date?

    /// "26.6.2". Compared rather than parsed: a version is a name, not a number.
    public let systemVersion: String?

    /// The model identifier the snapshot was taken on.
    ///
    /// Migration Assistant carries `~/Library/Application Support` to a new Mac, so without this a
    /// comparison could silently splice two machines together and report the second Mac's settings
    /// as the first one's changes. See `Snapshot.comparable(with:)`.
    public let machine: String?

    /// Wellkept's own version, so a change in *how* we read something is visible as a change in the
    /// app rather than as a change in the Mac.
    public let appVersion: String?

    /// The described subset, keyed by `WatchedKey.storageKey`, values already in a person's words.
    public let watched: [String: String]

    /// Where a watched thing could not be read at all, keyed the same way, valued by
    /// `Unreadable.rawValue`.
    ///
    /// ⚠️ **Kept rather than skipped.** A gap is indistinguishable from an app that was not
    /// launched that week, and "we stopped being allowed to see your privacy grants in April" is
    /// itself the finding.
    public let unreadable: [String: String]

    /// The full capture: every readable preference, keyed `"domain\u{1}key"`.
    ///
    /// Values are the property list rendered as a stable string rather than typed — a snapshot has
    /// to survive a build that has never heard of a type somebody's app invented.
    public let settings: [String: String]

    /// The domains that were deliberately not captured, by name, so a file can be read years later
    /// without guessing why something is missing. See `SnapshotStore.churnDomains`.
    public let excludedDomains: [String]

    public init(id: UUID = UUID(),
                takenAt: Date,
                bootedAt: Date? = nil,
                systemVersion: String? = nil,
                machine: String? = nil,
                appVersion: String? = nil,
                watched: [String: String] = [:],
                unreadable: [String: String] = [:],
                settings: [String: String] = [:],
                excludedDomains: [String] = []) {
        self.id = id
        self.takenAt = takenAt
        self.bootedAt = bootedAt
        self.systemVersion = systemVersion
        self.machine = machine
        self.appVersion = appVersion
        self.watched = watched
        self.unreadable = unreadable
        self.settings = settings
        self.excludedDomains = excludedDomains
    }

    public func value(_ key: WatchedKey) -> String? { watched[key.storageKey] }

    public func unreadable(_ key: WatchedKey) -> Unreadable? {
        unreadable[key.storageKey].flatMap(Unreadable.init(rawValue:))
    }

    /// Whether two snapshots describe the same machine.
    ///
    /// ⚠️ A comparison across a change of machine is not a comparison. Where either snapshot does
    /// not know its machine — an old file, or a Mac that would not say — we compare anyway rather
    /// than throwing the history away; the alternative is silently reporting nothing for ever.
    public func comparable(with other: Snapshot) -> Bool {
        guard let mine = machine, let theirs = other.machine else { return true }
        return mine == theirs
    }

    /// Whether the Mac restarted between two snapshots.
    ///
    /// ⛔ **This answers "did it restart", and nothing else.** It is never, on its own, evidence
    /// that macOS was updated — 15 of this Mac's 25 boots carried no update at all.
    public func restarted(since earlier: Snapshot) -> Bool {
        guard let mine = bootedAt, let theirs = earlier.bootedAt else { return false }
        return abs(mine.timeIntervalSince(theirs)) > 1
    }
}

// MARK: - The section's answer

/// What the Changes section found, and what it is allowed to say about it.
public struct ChangesReport: Sendable, Hashable {

    public let ranAt: Date

    /// When the snapshot we compared against was taken. `nil` on the very first launch, which is
    /// the one run where "nothing changed" would be a lie — there was nothing to compare with.
    public let previous: Date?

    /// The differences we can describe, worst first, then newest.
    public let changes: [Change]

    /// ⚠️ **Differences in the full capture that no `Watched` describes: counted, never listed.**
    ///
    /// The face says "and 41 other values changed that Wellkept does not yet explain". It does not
    /// print 41 rows of raw preference keys, because a row nobody can explain is a row that
    /// worries somebody for no reason — which is the whole trade the version-one scope was drawn
    /// around.
    public let undescribed: Int

    /// One watched thing we could not read this time, and why.
    ///
    /// A named struct rather than a tuple because `ChangesReport` is `Hashable`, and a tuple is
    /// not — the kind of detail that turns into a compile error the day somebody adds a field.
    public struct Unread: Sendable, Hashable, Identifiable {
        public let key: WatchedKey
        public let why: Unreadable
        public var id: WatchedKey { key }
        public init(key: WatchedKey, why: Unreadable) {
            self.key = key
            self.why = why
        }
    }

    /// The watched things we could not read this time.
    public let unreadable: [Unread]

    /// **John's answer 4, 2026-08-28.** Without Full Disk Access we can see *that* the privacy
    /// grants changed and not *what*. This is the one line that says so, with the button that
    /// grants access — shown once, never repeated per permission.
    ///
    /// Saying nothing instead would be reporting zero because we could not look, which the app has
    /// banned everywhere else.
    public let privacyChangedButUnreadable: Bool

    /// The Mac was asleep or switched off for part of the period being reported on.
    ///
    /// ⚠️ Said plainly, not glossed. A person who reads "since Tuesday" assumes five days of use.
    public let macWasOffOrAsleep: Bool

    /// Set where the boot record could not be read — a standard account. The section still knows
    /// an update happened and when; it has lost the evidence that the Mac was off, which is
    /// exactly the evidence that made the claim strong.
    public let outageUnreadable: Unreadable?

    public init(ranAt: Date,
                previous: Date?,
                changes: [Change],
                undescribed: Int = 0,
                unreadable: [Unread] = [],
                privacyChangedButUnreadable: Bool = false,
                macWasOffOrAsleep: Bool = false,
                outageUnreadable: Unreadable? = nil) {
        self.ranAt = ranAt
        self.previous = previous
        self.changes = changes
        self.undescribed = max(0, undescribed)
        self.unreadable = unreadable
        self.privacyChangedButUnreadable = privacyChangedButUnreadable
        self.macWasOffOrAsleep = macWasOffOrAsleep
        self.outageUnreadable = outageUnreadable
    }

    /// The very first launch: a snapshot was taken and there is nothing yet to compare it with.
    ///
    /// ⚠️ **This is not "Good".** Saying nothing changed on the day we started looking is the
    /// confident wrong answer the product exists to avoid, so it reports `.notChecked` and the
    /// face says plainly that the record starts today.
    public var isFirstLook: Bool { previous == nil }

    public var status: SectionStatus {
        if isFirstLook { return .notChecked }
        if !complete { return .notChecked }
        return worst == .attention ? .needsAttention : .good
    }

    /// A run that could not see everything.
    ///
    /// Only a refusal a person could lift counts — `Unreadable.stillComplete`. A reading macOS
    /// reserves for an administrator leaves the check complete and still says plainly that we did
    /// not see it, because a caveat nobody can clear is how an app teaches people to ignore it.
    public var complete: Bool {
        unreadable.allSatisfy { $0.why.stillComplete }
            && (outageUnreadable?.stillComplete ?? true)
            && !privacyChangedButUnreadable
    }

    public var worst: Severity {
        changes.map { $0.severity(Watched.of($0.key)) }.max() ?? .information
    }

    public var record: CheckRecord {
        CheckRecord(section: .changes, ranAt: ranAt, status: status, complete: complete)
    }

    /// Worst first, then newest first inside that. A fixed panel would be wrong here: this *is* a
    /// list of findings, and the order a person wants is "what should I look at".
    public var ordered: [Change] {
        changes.sorted {
            let a = $0.severity(Watched.of($0.key)), b = $1.severity(Watched.of($1.key))
            if a != b { return a > b }
            if $0.window.before != $1.window.before { return $0.window.before > $1.window.before }
            return $0.key < $1.key
        }
    }

    public func changes(in topic: ChangesTopic) -> [Change] {
        ordered.filter { $0.key.topic == topic }
    }

    /// The one line at the top of the face.
    public var summary: String {
        if isFirstLook {
            return "This is the first look. Wellkept has recorded what your settings are now, and "
                 + "from the next time you open it, it can tell you what has changed."
        }

        let since = previous.map { "since \($0.formatted(date: .abbreviated, time: .omitted))" }
            ?? "since we last looked"

        var sentence: String
        switch changes.count {
        case 0:  sentence = "Nothing Wellkept watches has changed \(since)."
        case 1:  sentence = "One thing Wellkept watches has changed \(since)."
        default: sentence = "\(changes.count) things Wellkept watches have changed \(since)."
        }

        if undescribed > 0 {
            sentence += undescribed == 1
                ? " One other value also changed, which Wellkept does not yet explain."
                : " \(undescribed) other values also changed, which Wellkept does not yet explain."
        }
        if macWasOffOrAsleep {
            sentence += " This Mac was asleep or switched off for part of that time."
        }
        return sentence
    }
}

// MARK: - ⭐ The catalogue — everything Wellkept understands well enough to describe

//  **About thirty things, each with three sentences we wrote and can defend.**
//
//  ⚠️ **Nothing goes in this list that Wellkept does not already read somewhere else.** John's
//  answer 2, 2026-08-28: our descriptions, only for settings the app already reads across Security,
//  Apps and Storage. A few dozen sentences we can stand behind, not 787 we cannot maintain — and
//  no line of anybody else's material, because the prior art's descriptions sit in a repository
//  with no licence at all and folding them into a GPL-3.0 app would pass on a right we never had.
//
//  Every entry mirrors a case of an enum a reader already owns — `ProtectionKind`,
//  `ReachableReader.Service`, `StartupReader.Origin`, `Permission` — and `WatchedKey.name` is
//  spelled the same as that case. That is not decoration: `Diff` builds keys from those enums, so
//  a name typed differently here is a watched thing that silently never matches.

extension Watched {

    /// Every watched thing, in row order then alphabetically inside a row.
    ///
    /// Built once and held, because `ChangesReport.ordered` looks a key up per change per sort
    /// comparison and rebuilding thirty structs inside a sort is the kind of quiet waste nobody
    /// ever profiles.
    public static let all: [Watched] = protections + reachable + startup + grants + [system]

    private static let index: [WatchedKey: Watched] =
        Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

    /// The description for a key, or `nil` where this build does not describe it.
    ///
    /// ⚠️ `nil` is ordinary and is how the "counted, never listed" rule is enforced: a change whose
    /// key has no entry here cannot be drawn as a row, because there is nothing to say about it.
    public static func of(_ key: WatchedKey) -> Watched? { index[key] }

    public static func inTopic(_ topic: ChangesTopic) -> [Watched] {
        all.filter { $0.key.topic == topic }
    }

    // MARK: The switches

    private static let protections: [Watched] = [
        Watched(key: WatchedKey(.protections, "fileVault"),
                title: "FileVault",
                description: .init(
                    does: "Encrypts everything on the disk, so the files can only be read by somebody who can sign in.",
                    costOfTurningItOff: "Anyone who takes the Mac, or takes the drive out of it, can read every file on it without knowing a password.",
                    whyItMightHaveChanged: "Somebody switched it off in Privacy & Security, or an organisation's profile decided it. macOS does not turn it off by itself."),
                safeValue: "On",
                settingsPane: "fileVault"),

        Watched(key: WatchedKey(.protections, "systemProtection"),
                title: "System Integrity Protection",
                description: .init(
                    does: "Stops any program, even one running as an administrator, from altering the parts of macOS that macOS itself depends on.",
                    costOfTurningItOff: "Software that gets in can change the system, and the usual repair — reinstalling macOS — stops being enough to clear it out.",
                    whyItMightHaveChanged: "It can only be switched off from Recovery, deliberately, by somebody holding a key at startup. Some developer tools and older drivers ask people to do exactly that."),
                safeValue: "On"),

        Watched(key: WatchedKey(.protections, "gatekeeper"),
                title: "Gatekeeper",
                description: .init(
                    does: "Checks an app the first time it runs, and refuses one that has been tampered with since its developer signed it.",
                    costOfTurningItOff: "An app that has been altered since it was built will open without a word being said about it.",
                    whyItMightHaveChanged: "Somebody allowed one app macOS had blocked, or ran a terminal command that switched the check off for everything at once."),
                safeValue: "On",
                settingsPane: "privacyAndSecurity"),

        Watched(key: WatchedKey(.protections, "secureBoot"),
                title: "Secure boot",
                description: .init(
                    does: "Checks at startup that the system about to run is the one Apple signed, before any of it has run.",
                    costOfTurningItOff: "This Mac will start a system that has been altered, which is the one change no software running afterwards can detect.",
                    whyItMightHaveChanged: "It is lowered from Recovery, usually so the Mac can load a driver Apple has not signed, and it stays lowered until somebody puts it back."),
                safeValue: "On"),

        Watched(key: WatchedKey(.protections, "firewall"),
                title: "Firewall",
                description: .init(
                    does: "Decides which programs on this Mac are allowed to accept a connection from another machine.",
                    costOfTurningItOff: "Any program here can accept connections from anything else on the network you have joined, including a café's.",
                    whyItMightHaveChanged: "Somebody switched it off in Network settings — often to make a game, a printer or a file transfer work — and did not switch it back."),
                safeValue: "On",
                settingsPane: "firewall"),

        Watched(key: WatchedKey(.protections, "automaticSecurityUpdates"),
                title: "Automatic security updates",
                description: .init(
                    does: "Installs Apple's security fixes on their own, without waiting to be asked.",
                    costOfTurningItOff: "This Mac keeps a hole Apple has already fixed for as long as nobody gets round to installing the update.",
                    whyItMightHaveChanged: "Somebody turned it off in Software Update to stop updates arriving mid-week, or an organisation decides when updates land on this Mac."),
                safeValue: "On",
                settingsPane: "softwareUpdate"),

        // ⚠️ The one switch where ON is the concern. The cost sentence is written the other way up
        // on purpose — the honest answer to "what does turning this off cost you" here really is
        // "typing your password", and pretending otherwise would be the app arguing rather than
        // explaining.
        Watched(key: WatchedKey(.protections, "automaticLogin"),
                title: "Automatic login",
                description: .init(
                    does: "Signs one account in at startup without anybody typing a password.",
                    costOfTurningItOff: "Only the convenience of not typing a password when the Mac starts. In exchange, it stops unlocking itself for whoever happens to have it.",
                    whyItMightHaveChanged: "Somebody switched it on in Users & Groups so the Mac would come straight back after a power cut, or a shared machine was set up that way."),
                safeValue: "Off",
                settingsPane: "usersAndGroups"),

        // ⚠️ **The one entry that can never produce a change, and it is here on purpose.**
        //
        // Apple publishes no readable state for Lockdown Mode anywhere, so this key only ever
        // lands in a snapshot's `unreadable` map. `Diff.values` walks `ProtectionKind.allCases`,
        // so leaving it out would put a key into the record that nothing in the catalogue could
        // describe — the silent kind of gap, where a row simply never appears and nobody can tell
        // whether it was watched or forgotten.
        //
        // `safeValue` is deliberately `nil`. A person who switched Lockdown Mode on because they
        // are targeted personally is exactly the person who must never be told by a health check
        // that it is off, and we cannot read it either way.
        Watched(key: WatchedKey(.protections, "lockdownMode"),
                title: "Lockdown Mode",
                description: .init(
                    does: "Strips this Mac back for somebody who has reason to think they are being targeted personally: most message attachments, some web technologies and calls from strangers stop working.",
                    costOfTurningItOff: "For almost everybody, nothing at all — it is off by default and meant for a small number of people. For somebody who switched it on deliberately, every door it closed opens again.",
                    whyItMightHaveChanged: "Only a person can switch it, in Privacy & Security, and macOS makes them restart to do it. Wellkept cannot read its state at all, so this row records that we looked rather than what we found."),
                safeValue: nil,
                settingsPane: "privacyAndSecurity"),
    ]

    // MARK: The ways in

    //  ⚠️ **`safeValue` is "Not seen listening", which is not the same as "off".** macOS gives no
    //  reading that proves a sharing service is switched off, so that is the exact phrase the
    //  Security reader prints and the exact phrase stored in a snapshot. A change *to* listening is
    //  news; a change away from it is a fact, not a triumph.

    private static let reachable: [Watched] = [
        Watched(key: WatchedKey(.reachableFrom, "screenSharing"),
                title: "Screen Sharing",
                description: .init(
                    does: "Lets another machine see this screen and control it, as though somebody were sitting here.",
                    costOfTurningItOff: "Nothing, unless you actually connect to this Mac from elsewhere — that stops working until it goes back on.",
                    whyItMightHaveChanged: "Somebody switched it on in Sharing to help you remotely, or a remote-support app switched it on when it was installed."),
                safeValue: "Not seen listening",
                settingsPane: "sharing"),

        Watched(key: WatchedKey(.reachableFrom, "remoteLogin"),
                title: "Remote Login",
                description: .init(
                    does: "Lets another machine open a command line on this Mac over SSH and run things as you.",
                    costOfTurningItOff: "Remote command-line access stops — including file transfers with scp or rsync, and anything you drive from another machine.",
                    whyItMightHaveChanged: "Somebody switched it on in Sharing, or a developer tool asked for it during setup. It does not switch itself on."),
                safeValue: "Not seen listening",
                settingsPane: "sharing"),

        Watched(key: WatchedKey(.reachableFrom, "fileSharing"),
                title: "File Sharing",
                description: .init(
                    does: "Lets another machine open the folders you have shared, over the network.",
                    costOfTurningItOff: "Other machines can no longer reach those folders, so files move some other way.",
                    whyItMightHaveChanged: "Somebody switched it on in Sharing to move files to another computer, or a printer or backup device asked for it."),
                safeValue: "Not seen listening",
                settingsPane: "sharing"),

        Watched(key: WatchedKey(.reachableFrom, "remoteManagement"),
                title: "Remote Management",
                description: .init(
                    does: "Lets an administrator's machine watch this screen, control it, and install software on it.",
                    costOfTurningItOff: "An IT department loses the ability to fix this Mac without walking over to it, which on a work machine is rather the point of it.",
                    whyItMightHaveChanged: "It is almost always an employer or a school, switched on when the Mac was enrolled. On a Mac nobody manages, it is worth asking about."),
                safeValue: "Not seen listening",
                settingsPane: "sharing"),

        Watched(key: WatchedKey(.reachableFrom, "airPlayReceiver"),
                title: "AirPlay Receiver",
                description: .init(
                    does: "Lets another Apple device send its screen or its sound to this Mac.",
                    costOfTurningItOff: "You can no longer play or mirror to this Mac from an iPhone, an iPad or another Mac.",
                    whyItMightHaveChanged: "It arrives switched on for some Macs, and macOS has switched it back on during an update before now."),
                safeValue: "Not seen listening",
                settingsPane: "sharing"),
    ]

    // MARK: What starts on its own

    //  These are counts, not switches, so three of the four carry no `safeValue`. Three more login
    //  items is a fact about a Mac somebody installed software on; calling it amber would put a
    //  warning on every working machine in the world.
    //
    //  ⚠️ **Configuration profiles are the exception, and they earn it.** The first draft treated
    //  them like the other three counts and said the interesting part in words instead — which
    //  produced a screen (2026-08-28, shot 504) whose row read *Good* one inch above its own
    //  sentence calling a new profile "the single thing on this list most worth asking about".
    //  A reader believes the chip, not the paragraph. So this one count has a `safeValue` of "0".
    //  It does not warn a managed Mac: `Cause.mayRaiseSeverity` is already false when an
    //  organisation's profile is what set it, which is exactly the case where a profile is
    //  ordinary. What is left is a profile arriving on a Mac nobody manages, and that is the case
    //  the description was written about.

    private static let startup: [Watched] = [
        Watched(key: WatchedKey(.startsOnItsOwn, "userAgent"),
                title: "Things that start when you log in",
                description: .init(
                    does: "Programs macOS starts for you every time you log in, counted from the startup files on this Mac.",
                    costOfTurningItOff: "Something that was quietly doing a job stops doing it — syncing a folder, checking for updates, holding a menu-bar icon.",
                    whyItMightHaveChanged: "Almost always an app you installed adding itself, which most apps do without asking. Apps you removed often leave theirs behind."),
                settingsPane: "loginItems"),

        Watched(key: WatchedKey(.startsOnItsOwn, "globalDaemon"),
                title: "Things that start with the Mac",
                description: .init(
                    does: "Programs macOS starts before anybody logs in, running as the system rather than as you.",
                    costOfTurningItOff: "Whatever the program did for every account on this Mac stops — a driver, a licence check, a backup agent.",
                    whyItMightHaveChanged: "Installers add these, and they are the usual home of printer software, virtual machines and security tools."),
                settingsPane: "loginItems"),

        Watched(key: WatchedKey(.startsOnItsOwn, "cron"),
                title: "Scheduled jobs",
                description: .init(
                    does: "Jobs this account has scheduled to run at fixed times, from the old cron table macOS still honours.",
                    costOfTurningItOff: "Whatever was scheduled stops happening, silently, because cron tells nobody when a job disappears.",
                    whyItMightHaveChanged: "Somebody added one by hand, or a tool wrote one while installing itself. Very little modern software uses cron, which is why a new one is worth a look."),
                settingsPane: nil),

        Watched(key: WatchedKey(.startsOnItsOwn, "configurationProfile"),
                title: "Configuration profiles",
                description: .init(
                    does: "Files that let an organisation set this Mac's settings and keep them set, whatever anybody here does.",
                    costOfTurningItOff: "Whatever the profile configured stops being applied — a wifi network, a mail account, a security rule, a restriction.",
                    whyItMightHaveChanged: "An employer, a school or a VPN app installed one. A profile appearing on a Mac nobody manages is the single thing on this list most worth asking about."),
                safeValue: "0",
                settingsPane: "profiles"),
    ]

    // MARK: Who can watch you

    //  One entry per permission, built from `Permission` so all twelve exist and none can be
    //  forgotten. A `Change` in this topic names the app as well — "Zoom — Screen recording" —
    //  because the permission on its own is not the news.
    //
    //  ⚠️ **Four of the twelve carry a `safeValue`, and the other eight deliberately do not.**
    //  Camera, microphone, contacts and the rest are granted by a macOS dialog that names the app
    //  and waits for a person; a Mac where somebody said yes to a video-call app is not a Mac with
    //  something wrong with it. The four that do — control this Mac, keystrokes, the screen, and
    //  every file on the disk — are the ones where the software can act as you or see everything,
    //  and where gaining one is worth a person's attention even when they granted it themselves.

    private static let grants: [Watched] = Permission.allCases.map { permission in
        Watched(key: WatchedKey(.whoCanWatch, permission.rawValue),
                title: permission.label,
                description: .init(does: grantDoes(permission),
                                   costOfTurningItOff: grantCost(permission),
                                   whyItMightHaveChanged: grantWhy(permission)),
                safeValue: grantIsWorthAttention(permission) ? "Not allowed" : nil,
                settingsPane: grantPane(permission))
    }

    private static func grantIsWorthAttention(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility, .inputMonitoring, .screenRecording, .fullDiskAccess: true
        default: false
        }
    }

    private static func grantDoes(_ permission: Permission) -> String {
        switch permission {
        case .camera:
            "Lets an app turn on the camera whenever it likes, without asking you again."
        case .microphone:
            "Lets an app listen through the microphone whenever it likes, without asking you again."
        case .screenRecording:
            "Lets an app see everything on your screen, in every other app, at any time."
        case .accessibility:
            "Lets an app control this Mac: move the pointer, press keys, and read any window."
        case .inputMonitoring:
            "Lets an app see every key you press, in every app, passwords included."
        case .fullDiskAccess:
            "Lets an app read every file on this Mac, including mail, messages and other apps' data."
        case .location:
            "Lets an app see where this Mac is."
        case .contacts:
            "Lets an app read the people in your Contacts."
        case .calendars:
            "Lets an app read your calendars and add events to them."
        case .reminders:
            "Lets an app read your reminders and add to them."
        case .photos:
            "Lets an app read your photo library."
        case .appleEvents:
            "Lets an app drive your other apps as though it were you — open them, read from them, act in them."
        }
    }

    private static func grantCost(_ permission: Permission) -> String {
        switch permission {
        case .camera:
            "That app's video calls, photographs and document scanning stop working until it is allowed again."
        case .microphone:
            "That app can no longer record, take dictation, or carry your voice on a call."
        case .screenRecording:
            "Screen sharing, screenshots and recordings made by that app stop working."
        case .accessibility:
            "Window managers, text expanders, clipboard tools and anything that automates this Mac stop being able to act."
        case .inputMonitoring:
            "Keyboard remapping, shortcut tools and controllers that watch the keyboard stop responding."
        case .fullDiskAccess:
            "Backup tools, search tools and anything that indexes your files see only part of the disk — sometimes quietly."
        case .location:
            "Weather, maps, the time zone and Find My stop being accurate for that app."
        case .contacts:
            "That app can no longer fill in a name, an address or an email address for you."
        case .calendars:
            "Meetings stop appearing in that app, and it can no longer put anything in your calendar."
        case .reminders:
            "That app can no longer show you a reminder or create one."
        case .photos:
            "That app can no longer see your photographs; most will offer to let you pick files by hand instead."
        case .appleEvents:
            "Automations, scripts and workflows that reach into other apps stop working, usually without saying why."
        }
    }

    private static func grantWhy(_ permission: Permission) -> String {
        switch permission {
        case .camera:
            "You said yes to a dialog the first time the app wanted the camera. macOS never grants this silently."
        case .microphone:
            "You said yes to a dialog the first time the app wanted to listen. Removing the app does not always remove its entry."
        case .screenRecording:
            "You allowed it for a meeting app, a recorder or a remote-support tool. It is also the permission the least trustworthy software wants most."
        case .accessibility:
            "You allowed it for a utility that automates something. It is the strongest permission on this list and the one granted most casually."
        case .inputMonitoring:
            "You allowed it for a keyboard tool. Nothing on this Mac can add itself, and it is precisely what a keylogger needs."
        case .fullDiskAccess:
            "Somebody dragged the app into the list in Privacy & Security. macOS cannot put an app there on its own."
        case .location:
            "You allowed it when the app first asked. Some apps ask again after they update."
        case .contacts:
            "You said yes to a dialog. Mail, messaging and calendar apps ask for this as a matter of course."
        case .calendars:
            "You said yes when the app first wanted to show your schedule."
        case .reminders:
            "You said yes to a dialog, usually from a task list or a note-taking app."
        case .photos:
            "You said yes when the app first asked. macOS also offers a limited version of this, and that counts as allowed."
        case .appleEvents:
            "You said yes to a dialog naming both apps. It is granted one pair at a time, so a new one appears whenever an app reaches for a new target."
        }
    }

    private static func grantPane(_ permission: Permission) -> String {
        switch permission {
        case .camera:          "camera"
        case .microphone:      "microphone"
        case .screenRecording: "screenRecording"
        case .accessibility:   "accessibility"
        case .inputMonitoring: "inputMonitoring"
        case .fullDiskAccess:  "fullDiskAccess"
        case .location:        "locationServices"
        case .contacts:        "contacts"
        case .calendars:       "calendars"
        case .reminders:       "reminders"
        case .photos:          "photos"
        case .appleEvents:     "automation"
        }
    }

    // MARK: macOS itself

    //  ⚠️ The cost sentence answers the question sideways, and says so. Nothing turns macOS off, so
    //  the honest reading of "what does turning it off cost you" for a version number is what
    //  *not* moving forward costs — and pretending the question fits would be worse than admitting
    //  it does not.

    private static let system = Watched(
        key: WatchedKey(.macOSItself, "systemVersion"),
        title: "macOS version",
        description: .init(
            does: "The version of macOS this Mac is running, which decides what everything else on this list is even capable of.",
            costOfTurningItOff: "Nothing turns macOS off. Staying on an older version costs you every security fix Apple has published since, and those are public — so what is left unpatched is known to everybody but you.",
            whyItMightHaveChanged: "Software Update installed it, on its own or because somebody asked. This is the row most likely to explain the rows above it."),
        safeValue: nil,
        settingsPane: "softwareUpdate")
}

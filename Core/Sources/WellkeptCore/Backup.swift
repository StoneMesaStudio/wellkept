// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation

//  Backup.swift
//  WellkeptCore
//
//  **The words the Backup section agrees on, and the two distinctions it is not allowed to blur.**
//
//  Same shape as `Hardware.swift`, `Security.swift`, `Apps.swift` and `Storage.swift` — a fixed row
//  set that never re-sorts, a facts block that cannot carry a verdict, one row up to Overview.
//  Nothing here imports SwiftUI, AppKit or Darwin: the vocabulary has to be testable without a
//  window, without a drive and without ever touching Time Machine.
//
//  ⛔ **Nothing in this file, and nothing that compiles against it, may write to a drive without a
//  `RehearsalGate.Pass`.** See `RehearsalGate.swift`. The gate is not a note; it is a token type
//  whose initialiser lives in one file, so a copier that has not asked cannot be called at all.
//
//  ## ⭐ The two distinctions this file exists to keep
//
//  **1. Switched off is not failing.** On 2026-08-28 I told the owner "Time Machine cannot reach
//  JDS Backup." It was wrong, and it was the exact wrong shape of wrong. Measured on his Mac the
//  next day: `AutoBackup = 0` — automatic backups are simply **switched off**; the destination is
//  configured and correct; the drive is just not plugged in; the last successful backup was
//  25 August. Nothing is broken. Somebody turned it off, or it turned itself off, and nobody said
//  so. **"Your backup is off and nobody told you" is both truer and more useful than "your backup
//  is broken"** — and it is exactly the finding this section exists to produce. So
//  `TimeMachineStanding` has a case for it, that case outranks every failure in
//  `TimeMachineState.standing`, and a test holds the precedence.
//
//  **2. A file that also lives in iCloud is not a backup gap.** `Coverage.lives` splits three ways
//  and **only `.onlyOnThisMac` can ever be a gap**. A photo that is on this Mac and in iCloud
//  survives the disk dying. A file that is *only* in iCloud is not on the disk to copy and never
//  was. Counting either as missing from a backup is how a health tool manufactures alarm out of a
//  working arrangement — 72.2 GB of this Mac's files would have been reported missing on day one.
//
//  ## ⚠️ The measurements this file is built around
//
//  Taken by hand on an M3 running macOS 26.6.2 on 2026-08-29, all read-only. Nothing was written to
//  any drive, no volume was created or modified, and Time Machine was not touched. `BACKUP-QUESTIONS.md`
//  has the whole survey; these are the findings that shaped the types below.
//
//  - **Time Machine's full state reads with ZERO permissions** — on or off, destination, connected,
//    last success, days since, the failure and its cause. So the first two rows of this section are
//    honest on every Mac, including one that has never granted Wellkept anything.
//  - ⚠️ **About 95% of the error volume in Apple's own backup log is XPC teardown noise.** Print it
//    and every Mac on earth looks broken. `LogNoise` filters it — and filters it in the one safe
//    direction: **noise can never become a failure on its own**, and a message we do not recognise
//    is kept rather than hidden. See `TimeMachineFailure.init?`.
//  - **Without Full Disk Access a backup contains no mail, no messages, no photos, no contacts, no
//    Safari data and no Trash** — not partial, *nothing* — and macOS refuses **silently, with no
//    error**. That is the list of things people actually restore. See `ProtectedPlace` and
//    `BackupCompleteness`, which is the type that refuses to call such a run complete.
//  - **The whole-Mac backup is impossible unprivileged**: 320,465 of the 361,714 files outside the
//    home folder are root-owned and `lchown` returns `EPERM`. **Inside the home folder, 586,642 of
//    586,643 files are the user's own.** The engine backs up the home folder, and this file never
//    contains the words "rebuild your Mac".
//  - **Migration Assistant accepting a data-only volume is UNVERIFIED**, with Apple's own string
//    arguing against it: *"Volume does not contain an installation of macOS or OS X."* The promise
//    is **"all your files"**, and `RehearsalGate` is what stops that promise being offered to
//    anybody before somebody has actually walked a restore.
//  - **72.2 GB of this Mac's files are in the cloud and not on the disk.** Named and skipped, never
//    downloaded by default. See `NotCopied.inTheCloudOnly`.
//  - ⚠️ **A zero-byte cloud file "succeeds".** Completeness is judged by the file flag, never by the
//    return code. See `Backup.whyTheReturnCodeIsNotEvidence`.
//  - **macOS 26 moved the FileVault recovery key out of Apple escrow into the Passwords app.**
//    "I can get it back with my Apple ID" is no longer true. See `RecoveryPlan`.
//  - ⛔ **The recorded snapshot fallback is dead twice over** — mounting a snapshot needs root, and
//    `tmutil localsnapshot` only works on a volume already in a Time Machine set. It is struck, and
//    there is no type here that expresses it.
//  - ⛔ **"Time Machine copies serially" is out of date.** macOS 26's `backupd` is parallel. That
//    claim is not in this app and must not be added to it.

// MARK: - The four rows

/// The four things Backup reports, in the order they are drawn.
///
/// ⚠️ **`allCases` IS the row order, and this list never sorts.** Raw values are storage — they go
/// into the check history, the one record in this app that cannot be rebuilt — and the labels are
/// English. The two are allowed to drift apart for ever.
///
/// ## Why this order
///
/// It is **what is already true, then what that leaves out, then what we could do about it, then
/// what you do when all of it has failed.** Each row is the qualification of the one above it, and
/// the order also happens to be strictly decreasing in how much we can prove:
///
/// 1. **Time Machine** — first because on most Macs it is the whole answer, and because it is the
///    only row that is *entirely measured*: every fact on it reads with no permission at all. A
///    section about backups that led with our own offer, ahead of the backup the person already
///    has, would be an advertisement wearing a health check's clothes.
/// 2. **What is not covered** — second because it qualifies whatever row 1 just said, and it is
///    true whichever answer row 1 gave. Time Machine has the cloud-only hole too and never mentions
///    it. This is the row that keeps the section honest, so it sits directly under the claim it
///    qualifies rather than at the bottom where a caveat goes to be ignored.
/// 3. **Wellkept's own backup** — third, because an offer comes after the facts, never before them.
///    ⛔ It is also the only row `RehearsalGate` can close, and while the gate is shut this row
///    shows what the engine would do and does not offer to do it.
/// 4. **The Recovery Plan** — last because it is what you reach for when everything above has
///    already failed. It is also the only row that needs no drive, no root, no background piece and
///    no network, which makes it the one row that still works on the worst day.
public enum BackupTopic: String, CaseIterable, Sendable, Identifiable, Codable, Hashable {

    /// What Apple's own backup is doing, or not doing. Measured, unprivileged, on every Mac.
    case appleBackup

    /// The things no backup on this Mac is holding, and why — the row that qualifies the one above.
    case notCovered

    /// Wellkept's own copy of the home folder. ⛔ Gated by `RehearsalGate`.
    case wellkeptBackup

    /// The printed page for the day the Mac will not start.
    case recoveryPlan

    public var id: String { rawValue }

    /// The words on the row.
    ///
    /// ⚠️ The first row is called **Time Machine**, not "Apple's own backup". That is the name on
    /// the person's own Mac, and renaming it here would make them hunt for a thing we invented.
    public var label: String {
        switch self {
        case .appleBackup:     "Time Machine"
        case .notCovered:      "What is not covered"
        case .wellkeptBackup:  "Wellkept's own backup"
        case .recoveryPlan:    "The Recovery Plan"
        }
    }

    /// The one sentence under the row's name, saying what it is. Shown always, not behind Options.
    public var explanation: String {
        switch self {
        case .appleBackup:
            "Whether macOS is backing this Mac up, where to, when it last worked, and what stopped it."
        case .notCovered:
            "The things that would not come back — what lives only on this Mac and is in no backup."
        case .wellkeptBackup:
            "A plain copy of your home folder onto a drive you choose, that you can read in the Finder."
        case .recoveryPlan:
            "One page to print and keep away from this Mac, for the day it will not start."
        }
    }

    /// Sort position, so a caller that collected rows out of order can put them back without
    /// knowing how the order is expressed.
    public var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// ⛔ Whether this row is behind the rehearsal gate. Exactly one is.
    ///
    /// The gate does not hide the row — it replaces the button with a sentence. A person is told
    /// what the engine does and told plainly that it is not being offered yet, which is the whole
    /// difference between a feature that is not finished and a feature that is being hidden.
    public var needsRehearsal: Bool { self == .wellkeptBackup }
}

// MARK: - How fresh a backup is

/// How long ago a backup last actually worked.
///
/// ⚠️ **Nine days is the owner's number**, not a round one somebody liked the look of: it is the
/// staleness the background piece was asked to notice, so the same line is used here rather than
/// this section and that one disagreeing about when a backup has gone quiet.
public enum BackupFreshness: String, Sendable, Codable, CaseIterable, Hashable {

    /// Nothing has ever succeeded, as far as we can read.
    case never

    /// Within the last day.
    case today

    /// Within the last nine days.
    case recent

    /// Nine days or more. Long enough that something has stopped and nobody noticed.
    case stale

    /// ⭐ The line between `.recent` and `.stale`, in days. Named once so the app and its background
    /// piece cannot drift apart about what "a while ago" means.
    public static let staleAfterDays = 9

    /// Work out the freshness from a date. `nil` means nothing has ever succeeded.
    public static func of(_ lastSuccess: Date?, now: Date = Date()) -> BackupFreshness {
        guard let lastSuccess else { return .never }
        let days = Self.days(from: lastSuccess, to: now)
        if days >= staleAfterDays { return .stale }
        return days < 1 ? .today : .recent
    }

    /// Whole days between two moments, floored at zero. A clock that has gone backwards — a
    /// timezone change, a corrected system clock — reads as zero rather than as a negative age.
    public static func days(from: Date, to: Date) -> Int {
        max(0, Int(to.timeIntervalSince(from) / 86_400))
    }

    /// The phrase for a row: "today", "4 days ago", "never".
    public static func phrase(for lastSuccess: Date?, now: Date = Date()) -> String {
        guard let lastSuccess else { return "never" }
        let days = Self.days(from: lastSuccess, to: now)
        switch days {
        case 0:  return "today"
        case 1:  return "yesterday"
        default: return "\(days.formatted()) days ago"
        }
    }

    public var label: String {
        switch self {
        case .never:  "Never"
        case .today:  "Today"
        case .recent: "Recent"
        case .stale:  "Stale"
        }
    }

    /// Whether this freshness on its own is worth raising. `.stale` and `.never` are.
    public var worthRaising: Bool { self == .stale || self == .never }
}

// MARK: - Where a backup goes

/// What kind of place a backup is being written to.
public enum DestinationKind: String, Sendable, Codable, CaseIterable, Hashable, Identifiable {

    /// A drive plugged into this Mac.
    case localDrive

    /// A share on the network, or a Time Capsule.
    case networkShare

    /// Configured, but macOS did not say which kind.
    case unknown

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .localDrive:   "A drive connected to this Mac"
        case .networkShare: "A place on your network"
        case .unknown:      "A backup destination"
        }
    }

    /// Whether "plug it in" is sensible advice for this kind. It is not, for a network share.
    public var isPluggedIn: Bool { self == .localDrive }
}

/// A place a backup is configured to go.
///
/// ⛔ **Reading this touches nothing.** Nothing in this app mounts, unmounts, formats, erases or
/// otherwise modifies a volume, and no type here has a property that would express having done so.
public struct BackupDestination: Sendable, Hashable, Codable, Identifiable {

    /// The name a person would recognise — "JDS Backup".
    public let name: String

    public let kind: DestinationKind

    /// Whether it is reachable right now. On this Mac, on 2026-08-29, this was `false`: the drive
    /// was simply in a drawer. **That is not a fault**, and nothing in this file treats it as one.
    public let isConnected: Bool

    /// Where it is mounted, when it is. `nil` when it is not connected, which is the ordinary case.
    public let volumePath: String?

    /// How big the destination is, if macOS said. `nil` is a normal answer.
    public let capacity: SizeOnDisk?

    /// How much room is left on it, if macOS said.
    public let free: SizeOnDisk?

    public var id: String { name }

    public init(name: String,
                kind: DestinationKind = .unknown,
                isConnected: Bool,
                volumePath: String? = nil,
                capacity: SizeOnDisk? = nil,
                free: SizeOnDisk? = nil) {
        self.name = name
        self.kind = kind
        self.isConnected = isConnected
        self.volumePath = volumePath
        self.capacity = capacity
        self.free = free
    }

    /// The sentence about where the backup goes and whether it is there.
    public var sentence: String {
        if isConnected { return "\(name) is connected." }
        return kind.isPluggedIn
            ? "\(name) is not plugged in."
            : "\(name) cannot be reached right now."
    }

    public var detailPairs: [DetailPair] {
        var pairs = [DetailPair("Backs up to", name),
                     DetailPair("Kind", kind.label),
                     DetailPair("Connected", isConnected ? "Yes" : "No")]
        if let capacity { pairs.append(DetailPair("Capacity", capacity.text)) }
        if let free { pairs.append(DetailPair("Free on it", free.text)) }
        return pairs
    }
}

// MARK: - ⚠️ The noise filter

/// **The teardown noise in Apple's backup log, and the one safe direction to filter it in.**
///
/// ⚠️ Measured 2026-08-29: roughly **95% of the error volume** in `backupd`'s log is XPC connections
/// being torn down at the end of an operation — normal shutdown, written at error level. Print it
/// raw and every Mac on earth reads as broken, including one whose backups all succeeded.
///
/// ## The direction of safety, and why it is this way round
///
/// A filter can fail two ways: hide a real failure, or show a fake one. They are not symmetrical
/// here, so the rules are asymmetrical too:
///
/// - **A message we do not recognise is KEPT.** Never dropped. The list below only ever subtracts
///   patterns somebody measured; a new kind of failure Apple invents next year still reaches the
///   screen. A denylist that grows quietly is how a health tool learns to say nothing.
/// - **Noise alone can never become a failure.** `TimeMachineFailure.init?` refuses to build one
///   from log text that is entirely noise — a failure needs an independent signal, which is a
///   result code from `tmutil` or a cause somebody has already worked out.
///
/// Between those two rules, the worst this filter can do is show a person a message that turned out
/// to be nothing. The worst the opposite arrangement could do is hide the day their backups stopped.
public enum LogNoise {

    /// The measured teardown patterns, matched case-insensitively as substrings.
    ///
    /// ⚠️ These are **whole-message noise**, not keywords. "connection invalid" appearing inside a
    /// longer sentence about a missing disk is still about the missing disk, which is why
    /// `isTeardownNoise` requires the message to be nothing but one of these.
    public static let teardownPatterns: [String] = [
        "connection invalid",
        "connection was invalidated",
        "connection interrupted",
        "couldn't communicate with a helper application",
        "the connection to service",
        "nsxpcconnection",
        "xpc error",
        "error domain=nscocoaerrordomain code=4097",
        "error domain=nscocoaerrordomain code=4099",
        "invalidated because the service",
        "terminated with signal",
        "process failed to exit",
    ]

    /// Whether a line is nothing but teardown noise.
    ///
    /// It matches only when the message carries **no other content**: the pattern has to account for
    /// the bulk of the line. A long message that merely mentions XPC on its way to naming a real
    /// problem is not noise and is not dropped.
    public static func isTeardownNoise(_ message: String) -> Bool {
        let text = message.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        guard let hit = teardownPatterns.first(where: { text.contains($0) }) else { return false }
        // ⚠️ The pattern has to BE most of the line. A 400-character message that happens to
        // contain "xpc error" is a message about something else.
        return Double(hit.count) / Double(text.count) >= 0.25
    }

    /// Everything that is not teardown noise, in the order it arrived, duplicates collapsed.
    public static func realErrors(in messages: [String]) -> [String] {
        var seen = Set<String>()
        return messages
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isTeardownNoise($0) }
            .filter { seen.insert($0.lowercased()).inserted }
    }

    /// The reason, in one sentence, for whoever finds this filter and wonders why we throw log
    /// lines away.
    public static let why =
        "About 95% of the errors in Apple's backup log are XPC connections being torn down normally "
        + "at the end of an operation. Printed raw, every Mac looks broken."
}

// MARK: - What stopped a backup

/// Why a backup is not working, as far as anything readable can say.
///
/// ⚠️ **`.driveNotConnected` is deliberately here and deliberately never used by
/// `TimeMachineState.standing`.** An unplugged drive is a *reason a backup has not run*, not a
/// *failure*, and the standing says so before it ever reaches this type. The case exists because
/// Apple's own log sometimes records it as an error and we would otherwise have to file it under
/// `.unknown`.
public enum FailureCause: String, Sendable, Codable, CaseIterable, Hashable, Identifiable {

    /// The destination is not there. Apple records this as an error; we do not.
    case driveNotConnected

    /// The backup drive has no room left.
    case driveFull

    /// macOS could not write to the destination — ownership, permissions, or a read-only mount.
    case cannotWriteThere

    /// The destination is damaged: the backup disk needs repair, or the sparsebundle is broken.
    case destinationDamaged

    /// A network destination could not be reached or would not authenticate.
    case cannotReachTheNetworkPlace

    /// The backup that was there is gone — a drive erased, reformatted, or used by another Mac.
    case backupNoLongerThere

    /// It started and stopped part way. One of these on its own is ordinary; a run of them is not.
    case interrupted

    /// Something failed and macOS did not say what in words we can honestly translate.
    case unknown

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .driveNotConnected:         "The drive is not connected"
        case .driveFull:                 "The backup drive is full"
        case .cannotWriteThere:          "macOS could not write to the drive"
        case .destinationDamaged:        "The backup on the drive is damaged"
        case .cannotReachTheNetworkPlace:"The network place could not be reached"
        case .backupNoLongerThere:       "The backup is no longer on the drive"
        case .interrupted:               "The backup stopped part way"
        case .unknown:                   "Something stopped it"
        }
    }

    /// What a person can actually do, in one sentence. `nil` where there is nothing honest to say.
    public var whatToDo: String? {
        switch self {
        case .driveNotConnected:
            "Plug the drive in. macOS will pick up where it left off."
        case .driveFull:
            "Time Machine deletes its own oldest backups to make room, so a full drive usually means the drive is smaller than what is being backed up."
        case .cannotWriteThere:
            "Open Time Machine settings and select the drive again. macOS will ask for permission if it needs it."
        case .destinationDamaged:
            "Disk Utility's First Aid can check the drive. If the backup itself is damaged, starting a fresh one is usually faster than repairing it."
        case .cannotReachTheNetworkPlace:
            "Check that the machine or Time Capsule is switched on and on the same network."
        case .backupNoLongerThere:
            "Open Time Machine settings and select the drive again, or choose a new one."
        case .interrupted:
            "One interrupted backup is ordinary — a sleep, or the drive being unplugged. Several in a row is not."
        case .unknown:
            nil
        }
    }
}

/// **A backup that is actually failing**, with what macOS said and what we made of it.
///
/// ⚠️ **This cannot be built out of log noise.** The failing initialiser refuses when the only
/// evidence is text that `LogNoise` recognises as an XPC teardown, because that text appears on a
/// Mac whose backups are all succeeding. A failure needs a result code or a cause somebody has
/// already established from something other than the log.
public struct TimeMachineFailure: Sendable, Hashable, Codable {

    /// Apple's own result code, where there is one. Kept because it is the one part of this that
    /// never gets reworded between macOS versions.
    public let code: Int?

    /// What macOS actually wrote. Shown behind **Options**, never as the headline — Apple's phrasing
    /// is written for Apple's engineers.
    public let message: String?

    public let cause: FailureCause

    /// When it was noticed, if the source carried a date.
    public let noticedOn: Date?

    /// ⭐ **The only way to build one.** Returns `nil` when there is no independent evidence.
    ///
    /// - Parameters:
    ///   - code: a `tmutil` or `backupd` result code. Non-nil and non-zero is evidence on its own.
    ///   - message: whatever the log said. On its own this is **not** evidence — see `LogNoise`.
    ///   - cause: a cause established from something other than the log text.
    public init?(code: Int? = nil,
                 message: String? = nil,
                 cause: FailureCause = .unknown,
                 noticedOn: Date? = nil) {
        let hasCode = (code ?? 0) != 0
        let hasCause = cause != .unknown
        let hasRealMessage = (message.map { !LogNoise.isTeardownNoise($0) } ?? false)

        // ⚠️ The whole point of this initialiser. Teardown noise with no code and no established
        // cause is a Mac that is working, and it must not produce a failure.
        guard hasCode || hasCause || hasRealMessage else { return nil }

        self.code = code
        self.message = message
        self.cause = cause
        self.noticedOn = noticedOn
    }

    /// The sentence on the row.
    public var sentence: String { cause.label + "." }

    public var detailPairs: [DetailPair] {
        var pairs = [DetailPair("What stopped it", cause.label)]
        if let code { pairs.append(DetailPair("Result code", String(code))) }
        if let message, !message.isEmpty { pairs.append(DetailPair("What macOS said", message)) }
        if let noticedOn {
            pairs.append(DetailPair("Noticed", noticedOn.formatted(date: .abbreviated, time: .shortened)))
        }
        return pairs
    }
}

// MARK: - ⭐ What Time Machine is actually doing

/// **The arrangement Time Machine is in.** Six answers, and the first job of this type is to keep
/// two of them apart.
///
/// ⚠️ **`.switchedOff` outranks `.failing`, always.** See the file header: this is the mistake that
/// was made in front of the owner. A Mac with automatic backups off will accumulate errors in the
/// log as a matter of course — of course it will, nothing is running — and reading those errors
/// back as "your backup is broken" sends somebody to Disk Utility to fix a switch.
public enum TimeMachineStanding: String, Sendable, Codable, CaseIterable, Hashable, Identifiable {

    /// We could not read the state at all.
    case notReadable

    /// No destination has ever been configured. ⚠️ **Not the same as broken**, and not necessarily
    /// the same as unbacked-up — Wellkept can only see Time Machine.
    case neverSetUp

    /// ⭐ **A destination is configured and automatic backups are off.** Somebody turned it off, or
    /// it turned itself off, and nobody said so. **This is the finding the section exists for.**
    case switchedOff

    /// On, configured, and the drive is not here. Ordinary for a drive that lives in a drawer —
    /// how ordinary depends entirely on when it was last plugged in, which is why severity is
    /// computed from the whole state and not from this case.
    case waitingForTheDrive

    /// On, reachable, and something is stopping it.
    case failing

    /// On, reachable, nothing reported wrong, and still nothing has succeeded in a long time.
    case overdue

    /// On, and it worked recently.
    case working

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .notReadable:       "Not checked"
        case .neverSetUp:        "Never set up"
        case .switchedOff:       "Switched off"
        case .waitingForTheDrive:"Waiting for the drive"
        case .failing:           "Failing"
        case .overdue:           "Overdue"
        case .working:           "Working"
        }
    }

    /// ⚠️ Whether this standing means something is **wrong**, as opposed to merely off or absent.
    /// `.switchedOff` is not a malfunction, and nothing in the app may describe it as one.
    public var isAMalfunction: Bool { self == .failing }
}

/// **Everything about Time Machine that reads with no permission at all.**
///
/// Measured 2026-08-29: configured, on or off, the destination, whether it is connected, the last
/// success, the days since, the failure and its cause — every one of them readable by an ordinary
/// program with nothing granted. That is why the first two rows of this section are honest on a Mac
/// that has given Wellkept nothing.
///
/// ⛔ **Reading is all this describes.** Nothing anywhere in Wellkept enables, disables or triggers
/// Time Machine, and there is no property here that could express having done so.
public struct TimeMachineState: Sendable, Hashable, Codable {

    /// Whether a destination has ever been configured.
    public let isConfigured: Bool

    /// ⭐ `AutoBackup`. On this Mac, on 2026-08-29, this was `false`.
    public let automaticBackupsOn: Bool

    /// Where it is set to go. `nil` when nothing is configured.
    public let destination: BackupDestination?

    /// When a backup last actually finished. `nil` means none ever has, as far as we can read.
    public let lastSuccess: Date?

    /// What is stopping it, if anything is. ⚠️ Built only through `TimeMachineFailure.init?`, which
    /// refuses to make one out of log noise.
    public let failure: TimeMachineFailure?

    /// Set when we could not read the state at all. Everything else is then meaningless and the
    /// initialiser clears it.
    public let unreadable: Unreadable?

    public init(isConfigured: Bool,
                automaticBackupsOn: Bool,
                destination: BackupDestination? = nil,
                lastSuccess: Date? = nil,
                failure: TimeMachineFailure? = nil,
                unreadable: Unreadable? = nil) {
        self.unreadable = unreadable
        if unreadable != nil {
            // ⚠️ Never report a state we did not read. A `false` here is the one value a person
            // would act on and the one we have no right to.
            self.isConfigured = false
            self.automaticBackupsOn = false
            self.destination = nil
            self.lastSuccess = nil
            self.failure = nil
        } else {
            self.isConfigured = isConfigured
            self.automaticBackupsOn = automaticBackupsOn
            self.destination = destination
            self.lastSuccess = lastSuccess
            self.failure = failure
        }
    }

    /// A state we could not read, in the house sentence.
    public static func couldNotRead(_ why: Unreadable) -> TimeMachineState {
        TimeMachineState(isConfigured: false, automaticBackupsOn: false, unreadable: why)
    }

    // MARK: ── ⭐ The precedence ──────────────────────────────────────────────────────────────────

    /// **Which of the six answers this Mac is in.**
    ///
    /// ⚠️ **The order of these tests is the whole point of the type**, and a test holds it:
    ///
    /// 1. Could not read → say so, claim nothing else.
    /// 2. Never configured → an absence, not a fault.
    /// 3. ⭐ **Switched off → `.switchedOff`, whatever the log says.** Off explains the errors; the
    ///    errors do not explain off. Putting this test below `failure` is the bug that was shipped
    ///    in conversation on 2026-08-28.
    /// 4. Drive not connected → waiting, not failing. A drive in a drawer is somebody's system.
    /// 5. A real failure → failing.
    /// 6. Nothing wrong, nothing recent → overdue.
    /// 7. Otherwise → working.
    public func standing(now: Date = Date()) -> TimeMachineStanding {
        if unreadable != nil { return .notReadable }
        if !isConfigured { return .neverSetUp }
        if !automaticBackupsOn { return .switchedOff }
        if let destination, !destination.isConnected { return .waitingForTheDrive }
        if failure != nil { return .failing }
        return BackupFreshness.of(lastSuccess, now: now).worthRaising ? .overdue : .working
    }

    /// How long ago it last worked.
    public func freshness(now: Date = Date()) -> BackupFreshness {
        BackupFreshness.of(lastSuccess, now: now)
    }

    /// Whole days since the last success. `nil` when none has ever happened.
    public func daysSinceLastSuccess(now: Date = Date()) -> Int? {
        lastSuccess.map { BackupFreshness.days(from: $0, to: now) }
    }

    // MARK: ── What it means ─────────────────────────────────────────────────────────────────────

    /// **How much this matters** — computed from the whole state, never from the standing alone.
    ///
    /// A drive waiting to be plugged in is ordinary at four days and a problem at four months, and
    /// the standing cannot tell those apart on its own.
    ///
    /// ⚠️ `.neverSetUp` is `.attention`, not `.problem`, and the reason is written into
    /// `headline`: **Wellkept can only see Time Machine.** Somebody using Backblaze or Carbon Copy
    /// Cloner has a backup we cannot see, and calling their Mac unprotected would be the app
    /// asserting something it did not measure. `.switchedOff` gets `.problem` instead, because the
    /// configured destination is the person's own evidence that they meant to be backing up.
    public func severity(now: Date = Date()) -> Severity {
        switch standing(now: now) {
        case .notReadable:  return .information
        case .neverSetUp:   return .attention
        case .switchedOff:  return .problem
        case .failing:      return .problem
        case .overdue:      return .problem
        case .waitingForTheDrive:
            return freshness(now: now).worthRaising ? .problem : .attention
        case .working:      return .information
        }
    }

    /// The section's status chip for this row.
    public func status(now: Date = Date()) -> SectionStatus {
        switch standing(now: now) {
        case .notReadable: return .notChecked
        case .working:     return .good
        default:           return severity(now: now) == .information ? .good : .needsAttention
        }
    }

    /// **The one sentence on the row**, in plain words, saying what is true rather than what to feel.
    public func headline(now: Date = Date()) -> String {
        let when = BackupFreshness.phrase(for: lastSuccess, now: now)
        switch standing(now: now) {
        case .notReadable:
            return unreadable?.sentence(about: "Time Machine") ?? "Time Machine — we could not read it."
        case .neverSetUp:
            return "Time Machine has never been set up on this Mac. If you back up another way, Wellkept cannot see it."
        case .switchedOff:
            return "Time Machine is switched off. It is still set up, and it last backed up \(when)."
        case .waitingForTheDrive:
            let name = destination?.name ?? "the backup drive"
            return "Time Machine is on and waiting for \(name). It last backed up \(when)."
        case .failing:
            return "Time Machine is on and is not finishing. It last backed up \(when)."
        case .overdue:
            return "Time Machine is on and nothing has succeeded since \(when)."
        case .working:
            return "Time Machine backed up \(when)."
        }
    }

    /// **Why it says that** — always present on the row, never behind a disclosure. A flagged Mac
    /// with no reason is an accusation; the reason is what lets somebody disagree with us.
    public func reason(now: Date = Date()) -> String? {
        switch standing(now: now) {
        case .notReadable:
            return nil
        case .neverSetUp:
            return "No backup destination has ever been chosen in Time Machine settings."
        case .switchedOff:
            return "Automatic backups are turned off in Time Machine settings, so nothing is running on its own. Nothing is broken."
        case .waitingForTheDrive:
            guard let destination else { return "The destination is not reachable right now." }
            return destination.sentence + (freshness(now: now).worthRaising
                ? " A drive that is never plugged in is not a backup."
                : "")
        case .failing:
            return failure.map { $0.sentence + ($0.cause.whatToDo.map { " " + $0 } ?? "") }
        case .overdue:
            return "macOS did not report anything wrong, and still nothing has finished in \(BackupFreshness.staleAfterDays) days or more."
        case .working:
            return nil
        }
    }

    /// Everything exact, behind **Options**.
    public func detailPairs(now: Date = Date()) -> [DetailPair] {
        if let unreadable { return [DetailPair("Time Machine", unreadable: unreadable)] }
        var pairs: [DetailPair] = [
            DetailPair("Set up", isConfigured ? "Yes" : "No"),
            DetailPair("Automatic backups", automaticBackupsOn ? "On" : "Off"),
        ]
        pairs += destination?.detailPairs ?? []
        if let lastSuccess {
            pairs.append(DetailPair("Last successful backup",
                                    lastSuccess.formatted(date: .abbreviated, time: .shortened)))
            if let days = daysSinceLastSuccess(now: now) {
                pairs.append(DetailPair("Days since", days.formatted()))
            }
        } else {
            pairs.append(DetailPair("Last successful backup", "None recorded"))
        }
        pairs += failure?.detailPairs ?? []
        return pairs
    }

    /// The button, where one leads somewhere that changes the answer.
    ///
    /// ⚠️ The button **opens the Time Machine pane**. It does not switch anything on. Nothing in
    /// Wellkept ever enables, disables or triggers a backup — that is the person's decision and
    /// their drive, and this app's whole rule is that nothing which changes the Mac happens without
    /// somebody pressing something in the place that owns it.
    public func remedy(now: Date = Date()) -> Remedy? {
        switch standing(now: now) {
        case .switchedOff, .neverSetUp, .failing, .overdue:
            return Remedy(title: "Open Time Machine settings", settingsPane: "timeMachine")
        case .waitingForTheDrive, .working, .notReadable:
            return nil
        }
    }
}

// MARK: - ⭐ Coverage: what is and is not in a backup, and why

/// **Where a thing actually lives.** Three answers, and only one of them can be a backup gap.
///
/// ⚠️ This is the second of the two distinctions in the file header, and it is the one that decides
/// whether this section is useful or hysterical. On this Mac, 72.2 GB of files are in the cloud and
/// not on the disk. A tool that counted those as "missing from your backup" would open with a
/// 72 GB alarm about an arrangement that is working exactly as designed.
public enum WhereItLives: String, Sendable, Codable, CaseIterable, Hashable, Identifiable {

    /// ⭐ **On this Mac and nowhere else. The only one that can be a gap.** If the disk dies, this
    /// is gone unless something copied it.
    case onlyOnThisMac

    /// In iCloud, with a copy here. The disk dying does not lose it. Worth *saying*, never worth
    /// raising: the person already has two copies, which is more than a backup gives them.
    case inTheCloudAndHere

    /// In iCloud and **not on this disk at all** — the 72.2 GB. There is nothing here to copy, and
    /// copying it would mean downloading it first, onto a Mac with 95 GB free.
    case onlyInTheCloud

    /// On another drive that this backup does not cover. A fact about scope, not a fault.
    case onAnotherDrive

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .onlyOnThisMac:     "Only on this Mac"
        case .inTheCloudAndHere: "In iCloud, with a copy here"
        case .onlyInTheCloud:    "In iCloud, not on this Mac"
        case .onAnotherDrive:    "On another drive"
        }
    }

    /// ⭐ **Whether being left out of a backup is a gap.** Exactly one answer is yes.
    ///
    /// A test walks every case and asserts this stays a set of one. Widening it is the change that
    /// turns this section into a scare.
    public var canBeAGap: Bool { self == .onlyOnThisMac }

    /// The line that explains a non-gap, so a row can say why it is not raising something.
    public var whyItIsNotAGap: String? {
        switch self {
        case .onlyOnThisMac:
            return nil
        case .inTheCloudAndHere:
            return "There is a copy in iCloud as well as here, so this survives the disk failing."
        case .onlyInTheCloud:
            return "This is not on the disk to copy. Backing it up would mean downloading it first."
        case .onAnotherDrive:
            return "This is on a different drive, which this backup does not cover."
        }
    }
}

/// Whether one thing made it into a backup.
public enum Included: Sendable, Hashable, Codable {

    /// It is in the backup.
    case yes

    /// It is not.
    case no

    /// ⚠️ **We were not allowed to look, or macOS refused silently.** Not the same as "no", and it
    /// is the answer that makes a whole run incomplete when the refusal is one a person could lift.
    case notKnown(Unreadable)

    public var label: String {
        switch self {
        case .yes:              "In the backup"
        case .no:               "Not in the backup"
        case .notKnown(let why): why.sentence
        }
    }

    public var isKnown: Bool { if case .notKnown = self { return false }; return true }

    /// The refusal behind a `.notKnown`, if that is what this is.
    public var unreadable: Unreadable? {
        if case .notKnown(let why) = self { return why }
        return nil
    }
}

/// **One thing that is or is not in a backup, and why.**
///
/// ⭐ `isGap` is computed, and it is computed from `lives` as well as from `included`. There is no
/// initialiser argument that could make a cloud file into a gap.
public struct Coverage: Sendable, Hashable, Codable, Identifiable {

    /// What it is, in the person's words: "Your Mail", "Photos library", "Documents".
    public let name: String

    /// ⭐ Where it actually lives. The field that decides whether missing means anything.
    public let lives: WhereItLives

    public let included: Included

    /// **Why**, always present, always on the row. Never behind Options.
    public let why: String

    /// How big, where that is known and means something. `nil` is ordinary.
    public let bytes: SizeOnDisk?

    /// ⚠️ Whether reading this at all needs Full Disk Access. Without the grant macOS refuses
    /// **silently**, so a run that lacks it does not fail — it quietly holds nothing.
    public let needsFullDiskAccess: Bool

    public var id: String { name }

    public init(name: String,
                lives: WhereItLives,
                included: Included,
                why: String,
                bytes: SizeOnDisk? = nil,
                needsFullDiskAccess: Bool = false) {
        self.name = name
        self.lives = lives
        self.included = included
        self.why = why
        self.bytes = bytes
        self.needsFullDiskAccess = needsFullDiskAccess
    }

    /// ⭐ **The one rule of this type: only something that lives on this Mac alone, and is not in the
    /// backup, is a gap.**
    ///
    /// A thing we could not check is **not** a gap either — it is unknown, and unknown is reported
    /// as unknown. Guessing in either direction here is how a backup tool ends up either lying or
    /// crying wolf.
    public var isGap: Bool {
        guard lives.canBeAGap else { return false }
        if case .no = included { return true }
        return false
    }

    /// Something we could not check. Distinct from a gap, and it makes the run incomplete when the
    /// refusal is one a person could lift.
    public var isUnknown: Bool { !included.isKnown }

    /// The sentence on the row.
    public var sentence: String {
        let size = bytes.map { " (\($0.text))" } ?? ""
        switch included {
        case .yes:              return "\(name)\(size) — in the backup."
        case .no where isGap:   return "\(name)\(size) — not in any backup, and it is only on this Mac."
        case .no:               return "\(name)\(size) — not in the backup. \(lives.whyItIsNotAGap ?? "")"
        case .notKnown(let w):  return "\(name) — \(w.clause)."
        }
    }

    public var detailPair: DetailPair {
        DetailPair(name, "\(included.label) · \(lives.label)")
    }
}

// MARK: - ⚠️ The protected places, and the silent refusal

/// **The six places a backup made without Full Disk Access contains nothing of.**
///
/// ⚠️ Measured 2026-08-29: without the grant a backup holds **no mail, no messages, no photos, no
/// contacts, no Safari data and no Trash** — not partial, *nothing* — and macOS refuses **silently,
/// with no error at all**. That is the list of things people actually restore, which makes this the
/// most dangerous failure available to this section: a backup that finished, reported success, and
/// is missing everything that mattered.
///
/// **Half a backup is worse than none.** It converts a risk somebody knows about into a belief they
/// never check. `BackupCompleteness` is the type that refuses to call such a run complete.
public enum ProtectedPlace: String, Sendable, Codable, CaseIterable, Hashable, Identifiable {
    case mail
    case messages
    case photos
    case contacts
    case safari
    case trash

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .mail:     "Your Mail"
        case .messages: "Your Messages"
        case .photos:   "Your Photos library"
        case .contacts: "Your Contacts"
        case .safari:   "Safari's history and bookmarks"
        case .trash:    "Your Trash"
        }
    }

    /// What is lost, said as a loss rather than as a path.
    public var whatIsLost: String {
        switch self {
        case .mail:     "Every message in Mail, and every account it is set up with."
        case .messages: "Every conversation in Messages, including its attachments."
        case .photos:   "The whole photo library — every picture and video it holds."
        case .contacts: "Everybody in your address book."
        case .safari:   "Bookmarks, reading list and history."
        case .trash:    "Anything you put in the Trash and have not emptied."
        }
    }

    /// The list, as one sentence, for a face that has room for a line.
    public static var listSentence: String {
        let names = allCases.map { $0.label.replacingOccurrences(of: "Your ", with: "") }
        return UnreadablePlaces.list(names)
    }
}

/// **Whether a backup may be called complete.**
///
/// ⭐ There is no way to construct one of these that says yes without having held the grant. That is
/// the whole type: a run that lacked Full Disk Access finished, reported success, and contains none
/// of the six things in `ProtectedPlace` — and macOS said nothing about it.
///
/// ⚠️ **Judged by the file flag, never by the return code.** See `Backup.whyTheReturnCodeIsNotEvidence`.
public struct BackupCompleteness: Sendable, Hashable, Codable {

    /// Whether the run held Full Disk Access. ⭐ The single fact that decides everything else.
    public let fullDiskAccessHeld: Bool

    /// How many files were skipped because they are in the cloud and not on the disk. **Not a
    /// failure** — named and skipped is the design — but it is stated, every time, because Time
    /// Machine has the same hole and never mentions it.
    public let cloudOnlySkipped: Int

    /// What those files claim to weigh. ⚠️ The apparent size, never a size we stand behind.
    public let cloudOnlyApparent: SizeOnDisk?

    /// Files that genuinely failed to copy, for a reason that is not the cloud.
    public let failed: Int

    /// Places the run was refused.
    public let refused: UnreadablePlaces

    public init(fullDiskAccessHeld: Bool,
                cloudOnlySkipped: Int = 0,
                cloudOnlyApparent: SizeOnDisk? = nil,
                failed: Int = 0,
                refused: UnreadablePlaces = .sawEverything) {
        self.fullDiskAccessHeld = fullDiskAccessHeld
        self.cloudOnlySkipped = max(0, cloudOnlySkipped)
        self.cloudOnlyApparent = cloudOnlyApparent
        self.failed = max(0, failed)
        self.refused = refused
    }

    /// ⭐ **Whether this run may be described as a complete backup.** No, unless the grant was held
    /// and nothing failed.
    public var mayBeCalledComplete: Bool {
        fullDiskAccessHeld && failed == 0 && refused.stillComplete
    }

    /// **What is missing, said plainly.** Empty when nothing is.
    public var missingSentences: [String] {
        var lines: [String] = []
        if !fullDiskAccessHeld {
            lines.append("""
                This backup contains no \(ProtectedPlace.listSentence). Without Full Disk Access \
                macOS hands over none of them, and it does so without any error — so a backup made \
                this way looks finished and is not.
                """)
        }
        if cloudOnlySkipped > 0 {
            let size = cloudOnlyApparent.map { " (about \($0.text) as they are listed)" } ?? ""
            lines.append("""
                \(cloudOnlySkipped.formatted()) files were skipped because they are in iCloud and \
                not on this disk\(size). Copying them would mean downloading them first.
                """)
        }
        if failed > 0 {
            lines.append("\(failed.formatted()) files could not be copied.")
        }
        if let refusedLine = refused.sentence { lines.append(refusedLine) }
        return lines
    }

    /// The headline, in the one word that matters.
    public var headline: String {
        mayBeCalledComplete
            ? "Everything on this Mac that could be copied was copied."
            : "This is not a complete backup."
    }

    /// The button, on the one refusal a person can lift.
    public var remedy: Remedy? {
        fullDiskAccessHeld ? nil : Remedy(title: "Open Full Disk Access", settingsPane: "fullDiskAccess")
    }
}

// MARK: - Why a file was not copied

/// Why one file did not make it into a backup.
///
/// ⚠️ **`.inTheCloudOnly` is not a failure and never counts as one.** It is the designed behaviour
/// of the one line that protects a person from the worst outcome available here: with the dataless
/// materialise policy off, reading a cloud-only file **fails outright** rather than writing an empty
/// file into a backup somebody will one day rely on.
public enum NotCopied: String, Sendable, Codable, CaseIterable, Hashable, Identifiable {

    /// In iCloud and not on the disk. Named, skipped, never downloaded.
    case inTheCloudOnly

    /// ⚠️ macOS handed over nothing, silently, because Full Disk Access is not granted.
    case refusedSilently

    /// The person excluded it.
    case excludedByYou

    /// Not a thing a copy means anything for — a socket, a device node, a named pipe.
    case notACopyableThing

    /// It genuinely failed.
    case failed

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .inTheCloudOnly:    "In iCloud, not on this Mac"
        case .refusedSilently:   "macOS did not hand it over"
        case .excludedByYou:     "You left it out"
        case .notACopyableThing: "Not a file a copy means anything for"
        case .failed:            "It failed"
        }
    }

    /// ⭐ Whether this counts against the run being complete.
    public var countsAgainstCompleteness: Bool {
        switch self {
        case .inTheCloudOnly, .excludedByYou, .notACopyableThing: false
        case .refusedSilently, .failed:                           true
        }
    }
}

// MARK: - A row, and the whole section's answer

/// What one topic found. The same three facts, the same **Options** details and the same house
/// sentence for a refusal as every other section in the app.
///
/// ⚠️ **Severity is clamped in the initialiser, per topic.** Unlike Storage — where nothing may ever
/// exceed `.information`, because revealing somebody's own files is not a fault — this section
/// genuinely can find something wrong. But two of its rows still cannot:
///
/// | Topic | Ceiling | Why |
/// |---|---|---|
/// | Time Machine | `.problem` | A backup that is off or failing is actually wrong. |
/// | What is not covered | `.problem` **only if a real gap exists** | Otherwise it is describing where files live, which is never a fault. |
/// | Wellkept's own backup | `.problem` | A run that did not finish is actually wrong. |
/// | The Recovery Plan | `.attention` | Not having printed a page is not a malfunction. |
public struct BackupRow: Sendable, Hashable, Identifiable, Codable {

    public let topic: BackupTopic

    /// The row's own sentence, in plain words. **Fact one of three.**
    public let headline: String

    /// The measurement, already formatted for a person — "4 days ago", "489 GB". **Fact two.**
    public let measure: String?

    /// Why it says what it says. Shown on the row, never behind a disclosure. **Fact three.**
    public let reason: String?

    /// What is and is not covered, in the order the row draws them.
    public let coverage: [Coverage]

    /// Everything more exact, behind **Options**.
    public let details: [DetailPair]

    /// Set when this could not be read at all.
    public let unreadable: Unreadable?

    /// The button, where one leads somewhere that changes the answer.
    public let remedy: Remedy?

    /// ⛔ Set when the row exists but is not being offered, because the rehearsal has not happened.
    /// The row still draws, still explains itself, and has no button.
    public let withheld: String?

    private let statedSeverity: Severity

    public var id: BackupTopic { topic }

    public init(topic: BackupTopic,
                headline: String,
                measure: String? = nil,
                reason: String? = nil,
                severity: Severity = .information,
                coverage: [Coverage] = [],
                details: [DetailPair] = [],
                unreadable: Unreadable? = nil,
                remedy: Remedy? = nil,
                withheld: String? = nil) {
        self.topic = topic
        self.headline = headline
        self.measure = unreadable == nil ? measure : nil
        self.reason = reason
        self.coverage = unreadable == nil ? coverage : []
        self.details = details
        self.unreadable = unreadable
        // ⚠️ A refusal nobody can lift never carries a button. Offering one would be offering a
        // door with no room behind it — see the table on `Unreadable`.
        self.remedy = (unreadable?.mayOfferRemedy == false) ? nil : remedy
        self.withheld = withheld

        // ⚠️ The clamp. See the table in the type note.
        if unreadable != nil {
            // Not knowing is never a fault. It is reported as not knowing.
            self.statedSeverity = .information
        } else {
            switch topic {
            case .recoveryPlan:
                self.statedSeverity = min(severity, .attention)
            case .notCovered:
                let hasGap = coverage.contains(where: \.isGap)
                self.statedSeverity = hasGap ? severity : min(severity, .information)
            case .appleBackup, .wellkeptBackup:
                self.statedSeverity = severity
            }
        }
    }

    /// A row we could not read at all, in the house sentence.
    public static func unreadable(_ topic: BackupTopic,
                                  _ why: Unreadable,
                                  about thing: String? = nil,
                                  reason: String? = nil,
                                  details: [DetailPair] = [],
                                  remedy: Remedy? = nil) -> BackupRow {
        BackupRow(topic: topic,
                  headline: why.sentence(about: thing ?? topic.label),
                  reason: reason,
                  details: details,
                  unreadable: why,
                  remedy: why.mayOfferRemedy ? remedy : nil)
    }

    public var severity: Severity { statedSeverity }

    /// The row's status chip.
    public var status: SectionStatus {
        if unreadable != nil { return .notChecked }
        return severity == .information ? .good : .needsAttention
    }

    /// Whether this row leaves the run able to call itself complete.
    public var complete: Bool {
        guard unreadable?.stillComplete ?? true else { return false }
        return !coverage.contains { $0.included.unreadable?.stillComplete == false }
    }

    /// ⭐ The things on this row that are actually missing. Never the cloud ones.
    public var gaps: [Coverage] { coverage.filter(\.isGap) }

    /// The three facts, in order, for a view that wants them as a list.
    public var facts: [String] { [headline, measure, reason].compactMap { $0 } }
}

/// Everything one run of the Backup check produced.
public struct BackupReport: Sendable, Hashable {

    /// What Apple's own backup is doing. Leads the face, and reads on every Mac with no permission.
    public let timeMachine: TimeMachineState

    /// Always in `BackupTopic` order, whatever order the readers finished in. Duplicates dropped,
    /// first one wins.
    public let rows: [BackupRow]

    /// Whether a Wellkept backup, if one has been made, may be called complete. `nil` when no
    /// Wellkept backup exists — which is every Mac until the rehearsal has happened.
    public let completeness: BackupCompleteness?

    /// Whether a Recovery Plan has been printed, and whether it is still current.
    public let recoveryPlan: RecoveryPlan?

    /// The macOS this Mac is on right now, so a Recovery Plan written for an older one can say so.
    /// `nil` when nobody told us, in which case the page is not called stale on a guess.
    public let currentMacOS: String?

    public let ranAt: Date

    /// The single row Backup sends up to Overview, or `nil` when there is nothing to say.
    ///
    /// ⚠️ **One row, not one per finding.** And it is about whether the person's files are backed
    /// up — never about how big the backup is or where their files happen to live.
    public let overviewFinding: Finding?

    public init(timeMachine: TimeMachineState,
                rows: [BackupRow],
                completeness: BackupCompleteness? = nil,
                recoveryPlan: RecoveryPlan? = nil,
                currentMacOS: String? = nil,
                ranAt: Date = Date()) {
        self.timeMachine = timeMachine

        var seen = Set<BackupTopic>()
        self.rows = rows
            .filter { seen.insert($0.topic).inserted }
            .sorted { $0.topic.order < $1.topic.order }

        self.completeness = completeness
        self.recoveryPlan = recoveryPlan
        self.currentMacOS = currentMacOS
        self.ranAt = ranAt
        self.overviewFinding = Self.summarise(timeMachine: timeMachine, rows: self.rows, now: ranAt)
    }

    public var status: SectionStatus {
        guard !rows.isEmpty else { return .notChecked }
        return rows.contains { $0.status == .needsAttention } ? .needsAttention : .good
    }

    public var complete: Bool { rows.allSatisfy(\.complete) }

    public var record: CheckRecord {
        CheckRecord(section: .backup, ranAt: ranAt, status: status, complete: complete)
    }

    public func row(_ topic: BackupTopic) -> BackupRow? { rows.first { $0.topic == topic } }

    /// Everything this run could not read at all, with the reason.
    public var unreadableTopics: [(topic: BackupTopic, why: Unreadable)] {
        rows.compactMap { row in row.unreadable.map { (row.topic, $0) } }
    }

    /// ⭐ Every real gap, across every row, in row order. Never a cloud file.
    public var gaps: [Coverage] { rows.flatMap(\.gaps) }

    /// The section's own sentence at the top of its face.
    public var summary: String {
        guard !rows.isEmpty else { return "Nothing has been checked yet." }
        return timeMachine.headline(now: ranAt)
    }

    /// What the section says under its headline, in order, with nothing optional missing.
    public var linesUnderTheHeadline: [String] {
        var lines: [String] = []
        if let reason = timeMachine.reason(now: ranAt) { lines.append(reason) }
        lines += completeness?.missingSentences ?? []
        if let plan = recoveryPlan, let now = currentMacOS,
           let line = plan.reprintLine(currentMacOS: now) { lines.append(line) }
        if !RehearsalGate.hasBeenRehearsed { lines.append(RehearsalGate.faceLine) }
        return lines
    }

    // MARK: The one row for Overview

    /// ⚠️ **Overview hears about a backup that is not happening. It never hears about where files
    /// live.** A person with 72 GB in iCloud has an arrangement, not a fault.
    private static func summarise(timeMachine: TimeMachineState,
                                  rows: [BackupRow],
                                  now: Date) -> Finding? {
        let severity = timeMachine.severity(now: now)
        if severity != .information {
            return Finding(section: .backup,
                           title: timeMachine.standing(now: now) == .switchedOff
                                ? "Time Machine is switched off"
                                : timeMachine.headline(now: now),
                           reason: timeMachine.reason(now: now)
                                ?? "Wellkept could not tell when this Mac last backed up.",
                           severity: severity,
                           measure: "Last backup \(BackupFreshness.phrase(for: timeMachine.lastSuccess, now: now))",
                           verb: SectionID.backup.verb)
        }

        // A real gap, when Time Machine itself is fine, still deserves the one row.
        let gaps = rows.flatMap(\.gaps)
        guard !gaps.isEmpty else { return nil }
        return Finding(section: .backup,
                       title: gaps.count == 1
                            ? "\(gaps[0].name) is in no backup"
                            : "\(gaps.count.formatted()) things are in no backup",
                       reason: "They are only on this Mac. If the disk fails they are gone.",
                       severity: .attention,
                       measure: nil,
                       verb: SectionID.backup.verb)
    }
}

// MARK: - The section's own sentences

/// The words this section owns that are not attached to a type.
public enum Backup {

    /// ⚠️ **What Wellkept's own backup promises, and what it does not.**
    ///
    /// Migration Assistant accepting a data-only volume is **unverified**, with Apple's own string
    /// arguing against it: *"Volume does not contain an installation of macOS or OS X."* And a
    /// whole-Mac copy is impossible unprivileged — 320,465 of the 361,714 files outside the home
    /// folder are root-owned and an ordinary program cannot set an owner.
    ///
    /// **So the promise is "all your files", and it is never "rebuild your Mac".** Nothing in this
    /// app may say the second thing.
    public static let whatItPromises = """
        A Wellkept backup is a plain copy of your home folder — your documents, pictures, music, \
        mail, messages and settings — on a drive you can open in the Finder and read without us. \
        It is not a copy of macOS, and it does not reinstall your Mac.
        """

    /// ⛔ The sentence that must never appear anywhere in this app, recorded here so a test can
    /// look for it.
    public static let promiseWeDoNotMake = "rebuild your Mac"

    /// ⚠️ **Why a successful return from a copy proves nothing.**
    ///
    /// With the dataless-materialise policy off, copying a cloud-only file fails outright rather
    /// than writing an empty one — which is the safety net. But a genuinely zero-byte cloud file
    /// **succeeds**, and the result is a file in the backup that is the right name, the right date,
    /// and empty. So completeness is judged by the dataless flag on the source, never by whether
    /// the copy returned zero.
    public static let whyTheReturnCodeIsNotEvidence = """
        A copy that returns success can still have written nothing, because a cloud-only file that \
        happens to be empty copies cleanly. Whether a file is really here is read from the file \
        itself, not from the result of copying it.
        """

    /// ⭐ **The replacement for "the app quits when its window closes."**
    ///
    /// ⚠️ That sentence was true until 2026-08-29, when John agreed to a Login Item — an
    /// `SMAppService.agent`, no password, no root, listed in System Settings ▸ Login Items. It is
    /// still true for anybody who leaves the background piece off, which is why the replacement
    /// says both halves rather than simply deleting the old claim.
    ///
    /// Anywhere in the app that describes what happens when the window closes uses this. As of
    /// 2026-08-29 the old sentence still stands in `App/Help/HelpContent.swift`,
    /// `App/Shell/RootView.swift`, `App/Sections/HardwareView.swift`,
    /// `App/Sections/Hardware/HardwareModel.swift` and `docs/CONTRACTS.md`.
    public static let whatHappensWhenTheWindowCloses = """
        Wellkept quits when you close its window. The one exception is the background piece, which \
        you switch on yourself: a small part of Wellkept that keeps running to back up while your \
        drive is connected. It is listed in System Settings ▸ Login Items, it needs no password and \
        no administrator, and switching it off leaves you a complete app.
        """

    /// ⚠️ **Untested and load-bearing**, recorded in code rather than in a document.
    ///
    /// If the background piece does not inherit the app's Full Disk Access, every scheduled backup
    /// silently contains no mail, no messages and no photos — and reports success. `RehearsalGate`
    /// holds a second proof for exactly this, and the agent cannot obtain a pass without it.
    public static let whatTheBackgroundPieceMustProveFirst = """
        The background piece must be shown to hold the same Full Disk Access as the app before it \
        copies anything. Without it, a scheduled backup would quietly contain none of your mail, \
        messages or photos, and macOS would report no error.
        """

    /// ⛔ Struck 2026-08-29, and recorded so nobody proposes it again: mounting an APFS snapshot
    /// needs root, and `tmutil localsnapshot` only works on a volume that is already in a Time
    /// Machine set — so on a Mac with no destination it produces nothing at all.
    public static let whySnapshotsAreNotAFallback = """
        Taking our own filesystem snapshot is not available to an app like this one: reading a \
        snapshot back needs administrator rights, and macOS will only make one on a drive that is \
        already part of a Time Machine backup.
        """
}

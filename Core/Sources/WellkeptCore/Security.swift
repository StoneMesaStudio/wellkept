import Foundation

//  Security.swift
//  WellkeptCore
//
//  **The words the Security section agrees on, and the shape a reader hands back.**
//
//  Six readers compile against this file without seeing each other. Nothing here imports SwiftUI,
//  IOKit or OSLog: the vocabulary has to be testable without a window and without a machine, and a
//  reader has to be replaceable without touching a view.
//
//  It is deliberately the same shape as `Hardware.swift` — a facts block that can never carry a
//  verdict, a fixed row set that never re-sorts, one row up to Overview — because the two sections
//  are the same screen with different contents, and a person who has learned one has learned both.
//
//  ## ⚠️ The measured truth this file is built around
//
//  Checked by hand on an M3 running macOS 26, 2026-08-27, all read-only. See
//  `SECURITY-QUESTIONS.md` for the whole survey.
//
//  - **Without Full Disk Access the watch screen is empty, not partial.** Eleven of the twelve
//    permissions read exactly zero; only Location reads without it. So a refused grant collapses
//    that row to one sentence rather than printing a near-empty list — "we checked and found
//    almost nothing" is the one thing this section promised never to say.
//  - **We can prove a sharing service is ON. We can never prove one is off.** There is no reading
//    that distinguishes "off" from "we could not tell", so `.off` is never printed for Screen
//    Sharing, Remote Login or Remote Management.
//  - **Lockdown Mode has no readable state anywhere.** That row says this Mac does not report it,
//    never "off".
//  - **Apple's own login-items list needs root and a tool that raises a password box.** We build
//    our own from the startup files and say plainly that it can differ from Apple's.
//  - **FileVault: we can say the door is locked. We cannot say whether there is a key**, or who can
//    unlock the Mac. Both need an administrator password.
//  - **What macOS already found comes from `OSLogStore`, and the window is about 14 days set by how
//    chatty the Mac has been.** It is never assumed — see `SecurityReport.measuredDays`.
//  - **The whole boot-security block is Apple silicon only**, and nobody has run it on Intel, which
//    this app ships to.
//
//  ## The three rules that shape every type below
//
//  1. **Never report zero because we could not look.** A reader that was refused returns an
//     `Unreadable`, in the same house sentence the whole app uses.
//  2. **Amber is a closed list.** Nine conditions, named once, in `SecurityConcern`. A row cannot
//     become amber by any other route — see `SecurityRow.severity`, which is computed from the
//     concerns rather than declared beside them.
//  3. **A management fact is never a problem.** A Mac whose settings were chosen by an employer is
//     not a Mac with faults, and a health check that says otherwise is an accusation aimed at
//     somebody who cannot act on it. `SecurityReport` drops the concern rather than asking six
//     readers to remember.

// MARK: - The six rows

/// The six things Security reports, in the order they are drawn.
///
/// ⚠️ **`allCases` IS the row order, and this list never sorts.** Worst-first is right for a list
/// of findings and wrong for a fixed panel: a person who learns that browser extensions are the
/// fourth row should still find them there next week.
///
/// Raw values are storage and the labels are English, and they are allowed to drift apart for ever.
/// `whoCanWatch` is the case in point: the raw value says what the row is *for*, and the label says
/// what it *lists*. John's call, 2026-08-27 — "Who can watch you" tells someone they are being
/// watched before they have read a line, and for almost everyone nothing is wrong.
public enum SecurityTopic: String, CaseIterable, Sendable, Identifiable, Codable, Hashable {

    /// FileVault, system protection, Gatekeeper, secure boot, the firewall — the switches.
    case protections

    /// Which apps hold camera, microphone, screen recording and control of this Mac.
    case whoCanWatch

    /// Launch agents, launch daemons, login items, cron, configuration profiles.
    case startsOnItsOwn

    /// Extensions installed in the browsers on this Mac, and what each one can see.
    case browserExtensions

    /// Sharing services that are listening, and what they are reachable from.
    case reachableFrom

    /// What macOS itself has already found and dealt with — XProtect Remediator and friends.
    case macOSFindings

    public var id: String { rawValue }

    /// The row's name, as it is drawn.
    public var label: String {
        switch self {
        case .protections:       "Protections"
        case .whoCanWatch:       "Camera, microphone, screen and control"
        case .startsOnItsOwn:    "What starts on its own"
        case .browserExtensions: "Browser extensions"
        case .reachableFrom:     "What can reach this Mac"
        case .macOSFindings:     "What macOS has already found"
        }
    }

    /// What the row means, in one plain sentence. Explanation, not clutter: it says what the row is
    /// actually telling you, which is the one thing a person cannot work out by looking at it.
    public var explanation: String {
        switch self {
        case .protections:
            "The protections built into macOS, and whether each one is switched on."
        case .whoCanWatch:
            "Which apps you have allowed to use the camera, the microphone, the screen, or to control this Mac."
        case .startsOnItsOwn:
            "Programs that start by themselves when this Mac starts or when you log in."
        case .browserExtensions:
            "Extensions added to your browsers, and how much of your browsing each one can see."
        case .reachableFrom:
            "Services that let another machine reach this one, and where they can be reached from."
        case .macOSFindings:
            "What macOS's own scanners have found and already dealt with, and how far back that goes."
        }
    }

    /// Sort position, so a caller that collected rows out of order can put them back without
    /// knowing how the order is expressed.
    public var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

// MARK: - ⭐ The nine amber conditions, in one place

/// **Every condition in Security that is allowed to raise the section, and there are exactly
/// nine.**
///
/// John kept all nine on 2026-08-27 and struck none. *"Everything else is a plain fact with no
/// colour."*
///
/// ⚠️ **This enum is the enforcement, not a reference list.** `SecurityRow.severity` is computed
/// from the concerns a row carries, so a reader cannot make a row amber by declaring a severity
/// beside it — it has to name which of the nine this is. That is the whole point: six readers
/// written in parallel would otherwise arrive with ten, twelve, twenty conditions between them,
/// each defensible on its own and collectively a screen of amber on a healthy Mac, which is the
/// scareware pattern this app exists to not be.
///
/// **Nothing in Security is ever `.problem`.** Every one of these is a setting a person may have
/// chosen deliberately, or a machine their employer configured. Amber says "this is worth a look".
/// Red would say "you have done something wrong", and this section is not in a position to know
/// that. A tenth condition, or a red one, is a conversation with John, not a pull request.
public enum SecurityConcern: String, CaseIterable, Sendable, Codable, Hashable, Identifiable {

    /// The disk is not encrypted, so anyone holding the machine can read it.
    case fileVaultOff

    /// The firewall is switched off.
    case firewallOff

    /// Gatekeeper has been weakened — apps can run without being checked.
    case gatekeeperWeakened

    /// System Integrity Protection is off.
    case systemProtectionOff

    /// Secure boot has been reduced below Full Security.
    case bootSecurityReduced

    /// macOS is not installing security fixes on its own.
    case automaticSecurityUpdatesOff

    /// This Mac logs somebody in without asking for a password.
    case automaticLoginOn

    /// An app holding the camera, the microphone or the screen **is not the app that was
    /// approved** — its signature has changed since the permission was granted.
    case signatureChangedSinceApproved

    /// A permission is still held by an app that is no longer on this Mac.
    case permissionHeldByMissingApp

    public var id: String { rawValue }

    /// The row's words: what is true, stated flatly.
    ///
    /// ⚠️ No imperatives. Never "you should", never "turn this on". The section states the fact and
    /// offers the pane; on a managed Mac even the offer is dropped. The one place advice is allowed
    /// is the FileVault recovery-key sentence, and only because it is the single piece of advice in
    /// this app that can cost somebody every file they own.
    public var title: String {
        switch self {
        case .fileVaultOff:
            "This Mac's disk is not encrypted"
        case .firewallOff:
            "The firewall is off"
        case .gatekeeperWeakened:
            "Apps can run without being checked"
        case .systemProtectionOff:
            "System Integrity Protection is off"
        case .bootSecurityReduced:
            "Secure boot is set below full security"
        case .automaticSecurityUpdatesOff:
            "Security fixes are not installing on their own"
        case .automaticLoginOn:
            "This Mac logs in without a password"
        case .signatureChangedSinceApproved:
            "An app has changed since you allowed it"
        case .permissionHeldByMissingApp:
            "A permission is held by an app that is gone"
        }
    }

    /// Why it is worth a look, in plain words. Always shown with the row — a flagged item with no
    /// reason is an accusation, and the reason is what lets a person disagree with us.
    public var explanation: String {
        switch self {
        case .fileVaultOff:
            "Without FileVault, anyone who has the machine itself can read what is on the disk. It cannot be switched on afterwards for files that have already been taken."
        case .firewallOff:
            "The firewall decides which programs on this Mac can accept a connection from another machine. With it off, that decision is not being made."
        case .gatekeeperWeakened:
            "Gatekeeper checks an app before it runs for the first time. It has been set to let apps through unchecked."
        case .systemProtectionOff:
            "System Integrity Protection stops anything — including software running as an administrator — from altering the parts of macOS that macOS depends on."
        case .bootSecurityReduced:
            "This Mac has been set to start up without verifying that the system it is starting is the one Apple signed. That is usually done on purpose, to run something Apple does not allow."
        case .automaticSecurityUpdatesOff:
            "Apple ships fixes for security holes between big releases. This Mac is not taking them on its own, so they arrive whenever somebody remembers."
        case .automaticLoginOn:
            "Anybody who opens the lid or presses the power button is signed in as this person, with no password asked."
        case .signatureChangedSinceApproved:
            "The permission was given to a particular app. The app on disk now signs as something different, so it is not certainly the same software you allowed."
        case .permissionHeldByMissingApp:
            "The app is not on this Mac any more, but the permission it was given is still on the list. If anything is ever installed under that identity, it starts with the permission already granted."
        }
    }

    /// Amber. Every one of them, always.
    ///
    /// Stated as a property rather than assumed, so the one place this could ever change is here
    /// and the tests can hold it. See the type's own note on why nothing here is `.problem`.
    public var severity: Severity { .attention }

    /// The switch this concern is about, where it is about a switch.
    ///
    /// ⚠️ **This is what makes "a management fact is never a problem" enforceable in one place.**
    /// `SecurityReport` drops a concern whose protection was set by an organisation, rather than
    /// asking six readers to each remember to check. The last two concerns are about apps rather
    /// than settings and have no protection behind them.
    public var protection: ProtectionKind? {
        switch self {
        case .fileVaultOff:                 .fileVault
        case .firewallOff:                  .firewall
        case .gatekeeperWeakened:           .gatekeeper
        case .systemProtectionOff:          .systemProtection
        case .bootSecurityReduced:          .secureBoot
        case .automaticSecurityUpdatesOff:  .automaticSecurityUpdates
        case .automaticLoginOn:             .automaticLogin
        case .signatureChangedSinceApproved: nil
        case .permissionHeldByMissingApp:    nil
        }
    }

    /// The topic whose row raises it. Used to check that a reader has not filed a concern under
    /// somebody else's row, which is how a fact ends up reported twice.
    public var topic: SecurityTopic {
        switch self {
        case .signatureChangedSinceApproved, .permissionHeldByMissingApp: .whoCanWatch
        default: .protections
        }
    }
}

// MARK: - One switch

/// The protections this section can look at, one case per switch.
///
/// XProtect is deliberately **not** here: it is a data version and a date, not something that is on
/// or off, and it lives on `ProtectionsBlock` instead.
public enum ProtectionKind: String, CaseIterable, Sendable, Codable, Hashable, Identifiable {
    case fileVault
    case systemProtection
    case gatekeeper
    case secureBoot
    case firewall
    case automaticSecurityUpdates
    case automaticLogin
    /// Apple publishes no readable state for this anywhere. It exists as a case so the row can say
    /// "this Mac does not report it" rather than being quietly missing — and it must **never** say
    /// off. See the header.
    case lockdownMode

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .fileVault:                "FileVault"
        case .systemProtection:         "System Integrity Protection"
        case .gatekeeper:               "Gatekeeper"
        case .secureBoot:               "Secure boot"
        case .firewall:                 "Firewall"
        case .automaticSecurityUpdates: "Automatic security updates"
        case .automaticLogin:           "Automatic login"
        case .lockdownMode:             "Lockdown Mode"
        }
    }

    /// What this switch actually does, in one sentence a person can act on.
    public var explanation: String {
        switch self {
        case .fileVault:
            "Encrypts the disk, so the files cannot be read by anyone who only has the machine."
        case .systemProtection:
            "Stops anything from altering the parts of macOS that macOS itself depends on."
        case .gatekeeper:
            "Checks an app the first time it runs, and refuses one that has been tampered with."
        case .secureBoot:
            "Verifies, at startup, that the system being started is the one Apple signed."
        case .firewall:
            "Decides which programs on this Mac may accept a connection from another machine."
        case .automaticSecurityUpdates:
            "Installs Apple's security fixes without waiting to be asked."
        case .automaticLogin:
            "Signs somebody in at startup without asking for a password."
        case .lockdownMode:
            "Apple's extreme setting for people who may be targeted personally. Most people should not need it."
        }
    }

    /// ⚠️ **`automaticLogin` is the one where being on is the concern.** Everything else in this
    /// list protects you when it is on. A view that draws a green tick beside "on" would otherwise
    /// congratulate somebody on a Mac that signs itself in.
    public var onIsTheSafeState: Bool { self != .automaticLogin }

    /// Which of the nine this switch raises when it is not in the state that protects you, or `nil`
    /// where the switch has no amber condition of its own — Lockdown Mode, which nobody can read.
    public var concern: SecurityConcern? {
        SecurityConcern.allCases.first { $0.protection == self }
    }
}

/// What a switch is set to.
///
/// ⚠️ **There is no fifth case, and `.off` is a claim.** Where a reading can prove something is on
/// but can never prove it is off — every sharing service on this Mac — the honest answer is
/// `.unreadable`, not `.off`. Printing "off" for something we merely failed to see is the
/// confident wrong answer this product exists to avoid.
public enum ProtectionState: Sendable, Hashable, Codable {
    /// Switched on, and we read it.
    case on
    /// Switched off, and we read that it is off.
    case off
    /// On, but not at its full strength: Gatekeeper with exceptions, secure boot below Full
    /// Security. Neither is "off", and calling it off would be wrong in a way that matters to
    /// somebody who reduced it deliberately.
    case reduced
    /// We could not read it. Carries which kind of not-reading, in the app's house vocabulary.
    case unreadable(Unreadable)

    /// Whether this state is the one that protects the person, given what the switch is.
    ///
    /// `nil` where we could not tell — which is not the same as `false`, and the difference is the
    /// whole file.
    public func isProtecting(_ kind: ProtectionKind) -> Bool? {
        switch self {
        case .on:         kind.onIsTheSafeState
        case .off:        !kind.onIsTheSafeState
        case .reduced:    false
        case .unreadable: nil
        }
    }

    /// The word on the row. Never a bare "Off" for something we did not read.
    public var label: String {
        switch self {
        case .on:                  "On"
        case .off:                 "Off"
        case .reduced:             "Reduced"
        case let .unreadable(why): why.sentence
        }
    }

    public var wasRead: Bool {
        if case .unreadable = self { return false }
        return true
    }

    public var unreadable: Unreadable? {
        if case let .unreadable(why) = self { return why }
        return nil
    }
}

/// One protection, as this Mac reports it.
public struct Protection: Sendable, Hashable, Codable, Identifiable {

    public let kind: ProtectionKind
    public let state: ProtectionState

    /// Anything more exact than the state, already formatted: "Full Security", "Two apps are
    /// allowed to accept connections", "Encrypted, unlock unknown". `nil` where the state says it
    /// all.
    public let detail: String?

    /// **Set by an organisation** — an employer, a school, an MDM profile.
    ///
    /// ⚠️ It changes what the section is allowed to say, not just how it looks. The row is labelled
    /// as organisation-set, the button is dropped because pressing it would not work, and
    /// `SecurityReport` drops the concern entirely. Otherwise a health check becomes an accusation
    /// about somebody's employer, aimed at a person who cannot act on it.
    public let setByOrganisation: Bool

    /// The raw value of a `SystemSettingsPane` case in the app layer, or `nil` for a switch with no
    /// pane to open.
    ///
    /// A *name*, never a URL. Every `x-apple.systempreferences:` anchor in this app lives in one
    /// file in the app layer, because those are internal names Apple renames without notice — and
    /// a wrong anchor still opens *a* pane, so the rot would be invisible.
    public let settingsPane: String?

    public var id: ProtectionKind { kind }

    public init(kind: ProtectionKind,
                state: ProtectionState,
                detail: String? = nil,
                setByOrganisation: Bool = false,
                settingsPane: String? = nil) {
        self.kind = kind
        self.state = state
        self.detail = detail
        self.setByOrganisation = setByOrganisation
        // A pane a person cannot change is a button that does nothing. Enforced here rather than
        // trusted to every reader.
        self.settingsPane = setByOrganisation ? nil : settingsPane
    }

    /// Whether this switch is in the state that protects the person. `nil` where we could not tell.
    public var isProtecting: Bool? { state.isProtecting(kind) }

    /// The concern this raises, or `nil`.
    ///
    /// Three ways to get `nil`, and they are all different: the switch is in the protecting state;
    /// we could not read it, so we have nothing to claim; or an organisation set it, and that is
    /// never a fault. The last one is repeated in `SecurityReport` because a reader is free to
    /// build a concern list by hand.
    public var concern: SecurityConcern? {
        guard !setByOrganisation, isProtecting == false else { return nil }
        return kind.concern
    }

    /// The Options pair for this switch.
    public var detailPair: DetailPair {
        var value = state.label
        if let detail { value += " — \(detail)" }
        if setByOrganisation { value += " (set by an organisation)" }
        return DetailPair(kind.label, value)
    }
}

// MARK: - What is protecting this Mac

/// **The "what is protecting this Mac" block at the top of the section.**
///
/// ⚠️ **Inventory, never a verdict. This type can never say Needs attention**, and it carries no
/// status for that reason. It lists what the protections are set to; deciding whether any of that
/// is worth a look is `SecurityRow`'s job and it happens exactly once, through `SecurityConcern`.
public struct ProtectionsBlock: Sendable, Hashable, Codable {

    /// In `ProtectionKind.allCases` order, duplicates dropped, first one wins.
    public let protections: [Protection]

    /// XProtect's signature version — "5310" — or `nil` where it could not be read.
    public let xprotectVersion: String?

    /// When XProtect's data last changed. `nil` where it could not be read; **never `Date()` as a
    /// stand-in**, which would print today's date for a Mac whose scanner has not updated in a
    /// year.
    public let xprotectUpdated: Date?

    /// This Mac is enrolled with an organisation. Enrolment reads free and unprivileged.
    public let isManaged: Bool

    public init(protections: [Protection],
                xprotectVersion: String? = nil,
                xprotectUpdated: Date? = nil,
                isManaged: Bool = false) {
        var seen = Set<ProtectionKind>()
        self.protections = protections
            .filter { seen.insert($0.kind).inserted }
            .sorted { $0.kind.order < $1.kind.order }
        self.xprotectVersion = xprotectVersion
        self.xprotectUpdated = xprotectUpdated
        self.isManaged = isManaged
    }

    public func protection(_ kind: ProtectionKind) -> Protection? {
        protections.first { $0.kind == kind }
    }

    /// The block, as rows, in a fixed order — the switches, then XProtect.
    public var detailPairs: [DetailPair] {
        var rows = protections.map(\.detailPair)

        rows.append(DetailPair("XProtect data",
                               xprotectVersion ?? Unreadable.notReported.sentence))
        rows.append(DetailPair("XProtect last updated",
                               xprotectUpdated.map { $0.formatted(date: .abbreviated, time: .omitted) }
                                   ?? Unreadable.notReported.sentence))
        if isManaged {
            rows.append(DetailPair("Managed by", "An organisation configures this Mac"))
        }
        return rows
    }

    /// The placeholder before anything has been read. Every switch says so; nothing here is a guess
    /// dressed as a fact.
    public static let unknown = ProtectionsBlock(
        protections: ProtectionKind.allCases.map {
            Protection(kind: $0, state: .unreadable(.notReported))
        }
    )
}

private extension ProtectionKind {
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

// MARK: - One app holding one permission

/// The permissions this section lists.
///
/// Twelve, and eleven of them read **exactly zero** without Full Disk Access — measured, not
/// assumed. `location` is the only one that reads without it, which is why it is hidden along with
/// the rest when the grant is refused: one populated row surrounded by refusals reads as "we
/// checked and found almost nothing".
public enum Permission: String, CaseIterable, Sendable, Codable, Hashable, Identifiable {
    case camera
    case microphone
    case screenRecording
    /// Control this Mac — move the pointer, press keys, read any window.
    case accessibility
    /// See every key pressed, in any app.
    case inputMonitoring
    case fullDiskAccess
    case location
    case contacts
    case calendars
    case reminders
    case photos
    /// Drive other apps through Apple Events.
    case appleEvents

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .camera:          "Camera"
        case .microphone:      "Microphone"
        case .screenRecording: "Screen recording"
        case .accessibility:   "Control this Mac"
        case .inputMonitoring: "Keystrokes"
        case .fullDiskAccess:  "Full Disk Access"
        case .location:        "Location"
        case .contacts:        "Contacts"
        case .calendars:       "Calendars"
        case .reminders:       "Reminders"
        case .photos:          "Photos"
        case .appleEvents:     "Controlling other apps"
        }
    }

    /// What an app holding it can actually do, said plainly.
    public var explanation: String {
        switch self {
        case .camera:          "Can turn on the camera without asking again."
        case .microphone:      "Can listen through the microphone without asking again."
        case .screenRecording: "Can see everything on your screen, in any app."
        case .accessibility:   "Can control this Mac: move the pointer, press keys, read any window."
        case .inputMonitoring: "Can see every key you press, in any app, including passwords."
        case .fullDiskAccess:  "Can read every file on this Mac, including mail and messages."
        case .location:        "Can see where this Mac is."
        case .contacts:        "Can read your contacts."
        case .calendars:       "Can read your calendars."
        case .reminders:       "Can read your reminders."
        case .photos:          "Can read your photo library."
        case .appleEvents:     "Can drive your other apps as though it were you."
        }
    }

    /// ⚠️ **The three that make concern 8 a concern.** An app whose signature has changed since it
    /// was approved is amber only for these — the camera, the microphone and the screen — because
    /// those are the ones where the wrong software silently watching is the harm.
    public var watchesYou: Bool {
        self == .camera || self == .microphone || self == .screenRecording
    }

    /// Whether reading who holds this needs Full Disk Access. True for eleven of the twelve.
    public var needsFullDiskAccessToRead: Bool { self != .location }
}

/// Whether the app holding a permission is still the app that was approved.
public enum SignatureStanding: String, Sendable, Codable, Hashable, CaseIterable {
    /// The app on disk signs as what the permission was granted to.
    case matches
    /// **It signs as something else.** The permission was given to a particular app; this is not
    /// certainly that app any more.
    case changed
    /// We could not check — the app is gone, or the signature could not be read. Never treated as
    /// `.matches`, and never as `.changed`: an unchecked app is not an accused one.
    case unknown

    public var label: String {
        switch self {
        case .matches: "Unchanged since you allowed it"
        case .changed: "Changed since you allowed it"
        case .unknown: Unreadable.notReported.sentence
        }
    }
}

/// One app holding one permission.
///
/// One row per pair, not per app: "Zoom has the camera" and "Zoom has the microphone" are two
/// different things a person may feel differently about, and merging them hides the one they would
/// have removed.
public struct Grant: Sendable, Hashable, Codable, Identifiable {

    /// What the app calls itself — "Zoom". Where the name cannot be read, readers put the bundle
    /// id here rather than inventing one.
    public let appName: String

    /// "us.zoom.xos". The identity the permission was actually granted to, and the thing that
    /// survives the app being deleted.
    public let bundleID: String

    public let permission: Permission

    /// **`false` where the app is no longer on this Mac** — concern 9. The permission outlives the
    /// app, so anything later installed under this identity starts with it already granted.
    public let stillInstalled: Bool

    public let signature: SignatureStanding

    /// When this was granted, where the machine records it. `nil` is ordinary.
    public let grantedAt: Date?

    /// **This is Wellkept itself.**
    ///
    /// Wellkept holds Full Disk Access, so Wellkept appears in its own list. John's call,
    /// 2026-08-27: say so, rather than filter ourselves out. An app that quietly removes itself
    /// from the list of apps that can read your disk is doing the thing this app exists to catch
    /// other software doing.
    public let isWellkept: Bool

    public var id: String { "\(bundleID)|\(permission.rawValue)" }

    public init(appName: String,
                bundleID: String,
                permission: Permission,
                stillInstalled: Bool = true,
                signature: SignatureStanding = .unknown,
                grantedAt: Date? = nil,
                isWellkept: Bool = false) {
        self.appName = appName
        self.bundleID = bundleID
        self.permission = permission
        self.stillInstalled = stillInstalled
        self.signature = signature
        self.grantedAt = grantedAt
        self.isWellkept = isWellkept
    }

    /// The concern this grant raises, or `nil` — which is the ordinary answer for almost every
    /// permission on almost every Mac.
    ///
    /// Missing-app is checked first: an app that is gone cannot have its signature compared, so
    /// reporting both would be reporting the same absence twice.
    public var concern: SecurityConcern? {
        if !stillInstalled { return .permissionHeldByMissingApp }
        if signature == .changed && permission.watchesYou { return .signatureChangedSinceApproved }
        return nil
    }
}

// MARK: - One row's result

/// What one Security reader found.
///
/// The same shape and the same invariants as `Reading` in `Hardware.swift`, with one addition that
/// matters: **`severity` is computed from `concerns`, not declared.** A reader cannot make a row
/// amber without naming which of the nine it is.
public struct SecurityRow: Sendable, Hashable, Identifiable, Codable {

    public let topic: SecurityTopic

    /// The row's own sentence, in plain words. Never a raw value, never a bare number.
    public let headline: String

    /// A count or figure, already formatted for a person — "3 extensions", "12 days". `nil` where
    /// there is nothing to measure.
    public let measure: String?

    /// **Which of the nine this row raises.** Empty on almost every row on almost every Mac.
    /// De-duplicated and put in a fixed order, so two runs give the same list in the same order.
    public let concerns: [SecurityConcern]

    /// Why it says what it says. Shown on the row, never behind a disclosure.
    public let reason: String?

    /// Everything more exact, shown behind **Options**.
    public let details: [DetailPair]

    /// Set when the reader could not read this at all.
    public let unreadable: Unreadable?

    /// The button on a `.notPermitted` row — the one refusal a person can lift. Dropped otherwise;
    /// see `init`.
    public let remedy: Remedy?

    public var id: SecurityTopic { topic }

    /// ⚠️ **Computed from the concerns, and there is no way to set it directly.**
    ///
    /// Nothing in Security is `.problem` — see `SecurityConcern`. A row we could not read is
    /// `.information` and reports `.notChecked`, because "we did not look" is not a finding about
    /// the Mac.
    public var severity: Severity {
        if unreadable != nil { return .information }
        return concerns.isEmpty ? .information : .attention
    }

    /// The row's status chip, derived so it cannot disagree with the row beneath it.
    public var status: SectionStatus {
        if unreadable != nil { return .notChecked }
        return concerns.isEmpty ? .good : .needsAttention
    }

    /// Whether this row leaves the check able to call itself complete. Only a refusal somebody can
    /// lift counts — see the table on `Unreadable`.
    public var complete: Bool { unreadable?.stillComplete ?? true }

    public init(topic: SecurityTopic,
                headline: String,
                measure: String? = nil,
                concerns: [SecurityConcern] = [],
                reason: String? = nil,
                details: [DetailPair] = [],
                unreadable: Unreadable? = nil,
                remedy: Remedy? = nil) {
        self.topic = topic
        self.headline = headline
        // ⚠️ Never report zero because we could not look. A row we did not read cannot carry a
        // figure, whatever a reader hands in.
        self.measure = unreadable == nil ? measure : nil
        // A row we could not read raises nothing: it has not found that everything is fine, and it
        // has not found that anything is wrong.
        self.concerns = unreadable == nil ? Self.tidy(concerns) : []
        self.reason = reason
        self.details = details
        self.unreadable = unreadable
        self.remedy = (unreadable?.mayOfferRemedy ?? false) ? remedy : nil
    }

    /// A row we could not read, in the house sentence.
    public static func unreadable(_ topic: SecurityTopic,
                                  _ why: Unreadable,
                                  about thing: String? = nil,
                                  reason: String? = nil,
                                  details: [DetailPair] = [],
                                  remedy: Remedy? = nil) -> SecurityRow {
        SecurityRow(topic: topic,
                    headline: why.sentence(about: thing ?? topic.label),
                    reason: reason,
                    details: details,
                    unreadable: why,
                    remedy: remedy)
    }

    /// De-duplicated, and in `SecurityConcern.allCases` order — which is what makes two runs on the
    /// same Mac produce the same list in the same order, whatever order the reader happened to find
    /// things in. Filtering `allCases` rather than the input does both jobs at once.
    private static func tidy(_ concerns: [SecurityConcern]) -> [SecurityConcern] {
        let raised = Set(concerns)
        return SecurityConcern.allCases.filter(raised.contains)
    }
}

// MARK: - The whole section's answer

/// Everything one run of the Security check produced.
public struct SecurityReport: Sendable, Hashable {

    /// The "what is protecting this Mac" block. Inventory, never a verdict.
    public let block: ProtectionsBlock

    /// Always in `SecurityTopic` order, whatever order the readers finished in. Duplicates dropped,
    /// first one wins.
    public let rows: [SecurityRow]

    public let ranAt: Date

    /// **How far back this run could actually see, in days.**
    ///
    /// ⚠️ **Measured, never assumed, and `nil` is a real answer.** The window comes from
    /// `OSLogStore`, is roughly a fortnight, and is set by how chatty this Mac has been rather than
    /// by any policy — so it differs between two Macs and between two weeks on the same Mac.
    /// Printing an assumed 14 would be a number nobody measured, on the one sentence in the section
    /// that is a claim about time.
    public let measuredDays: Int?

    /// The single row Security sends up to Overview, or `nil` when nothing here needs a person.
    ///
    /// ⚠️ **One row, not one per finding.** A section that posts nine rows to Overview has turned
    /// the summary into a second copy of itself.
    ///
    /// Stored rather than computed so its `id` is stable across draws.
    public let overviewFinding: Finding?

    public init(block: ProtectionsBlock,
                rows: [SecurityRow],
                ranAt: Date = Date(),
                measuredDays: Int? = nil) {
        self.block = block

        var seen = Set<SecurityTopic>()
        let ordered = rows
            .filter { seen.insert($0.topic).inserted }
            .sorted { $0.topic.order < $1.topic.order }

        // ⚠️ **A management fact is never a problem — enforced here, once.**
        //
        // A concern about a switch an organisation set is dropped from the row before anything else
        // sees it, so it cannot reach the status chip, Overview, or the audit trail. Doing it in
        // one place is the point: six readers each remembering is six chances to forget, and the
        // failure mode is an app telling somebody their employer has misconfigured their Mac.
        let organisationSet = Set(block.protections.filter(\.setByOrganisation).map(\.kind))
        self.rows = organisationSet.isEmpty ? ordered : ordered.map { row in
            let kept = row.concerns.filter { concern in
                concern.protection.map { !organisationSet.contains($0) } ?? true
            }
            guard kept.count != row.concerns.count else { return row }
            return SecurityRow(topic: row.topic,
                               headline: row.headline,
                               measure: row.measure,
                               concerns: kept,
                               reason: row.reason,
                               details: row.details,
                               unreadable: row.unreadable,
                               remedy: row.remedy)
        }

        self.ranAt = ranAt
        self.measuredDays = measuredDays
        self.overviewFinding = Self.summarise(rows: self.rows,
                                              block: block,
                                              measuredDays: measuredDays)
    }

    /// Every concern this run raised, de-duplicated, in the fixed order.
    public var concerns: [SecurityConcern] {
        let raised = Set(rows.flatMap(\.concerns))
        return SecurityConcern.allCases.filter(raised.contains)
    }

    /// The section's status chip.
    ///
    /// A row we could not read does not make the section "Not checked" — we checked, and found that
    /// we were not able to see that one thing. `.notChecked` is reserved for a section with no rows
    /// at all.
    public var status: SectionStatus {
        if rows.isEmpty { return .notChecked }
        return concerns.isEmpty ? .good : .needsAttention
    }

    /// Whether this run saw everything it set out to see. Only a refusal a person could lift counts
    /// — see `Unreadable`.
    public var complete: Bool { rows.allSatisfy(\.complete) }

    /// The line this run contributes to the app's audit trail.
    public var record: CheckRecord {
        CheckRecord(section: .security, ranAt: ranAt, status: status, complete: complete)
    }

    public func row(_ topic: SecurityTopic) -> SecurityRow? {
        rows.first { $0.topic == topic }
    }

    /// Everything this run could not read, with the reason, for the section to state once rather
    /// than six times.
    public var unreadableTopics: [(topic: SecurityTopic, why: Unreadable)] {
        rows.compactMap { row in row.unreadable.map { (row.topic, $0) } }
    }

    // MARK: The window, said out loud

    /// "in the last 12 days", or the honest shrug where the window could not be measured.
    ///
    /// ⚠️ Callers must use this rather than writing their own. The whole reason the section can say
    /// "macOS found nothing" is that it also says how far back that "nothing" reaches.
    public var windowClause: String {
        guard let days = measuredDays, days > 0 else {
            return "in the records it still keeps, which do not say how far back they go"
        }
        return days == 1 ? "in the last day" : "in the last \(days) days"
    }

    /// **The clean sentence — and it never stands alone.**
    ///
    /// John's rule, 2026-08-27: Good always carries its scope and its window. **The word "safe"
    /// never appears as a verdict** anywhere in this section: Wellkept is not watching in real time
    /// and must not imply that it is.
    public var summary: String {
        if !concerns.isEmpty {
            let count = concerns.count
            return count == 1
                ? "One thing here is worth a look."
                : "\(count) things here are worth a look."
        }
        let scope = complete
            ? "The protections we can see are on"
            : "The protections we were allowed to see are on"
        return "\(scope), and macOS found nothing \(windowClause)."
    }

    // MARK: The one row for Overview

    private static func summarise(rows: [SecurityRow],
                                  block: ProtectionsBlock,
                                  measuredDays: Int?) -> Finding? {
        let raised = Set(rows.flatMap(\.concerns))
        let ordered = SecurityConcern.allCases.filter(raised.contains)
        guard let first = ordered.first else { return nil }

        let others = ordered.count - 1
        var reason = first.explanation
        if others > 0 {
            reason += others == 1
                ? " And one more in Security."
                : " And \(others) more in Security."
        }
        // On a managed Mac the imperative goes, everywhere. The concern is still stated; what is
        // dropped is any suggestion that this person is the one who should change it.
        if block.isManaged {
            reason += " Some of this Mac's settings are chosen by an organisation."
        }

        return Finding(section: .security,
                       title: first.title,
                       reason: reason,
                       severity: first.severity,
                       measure: ordered.count > 1 ? "\(ordered.count)" : nil)
    }
}

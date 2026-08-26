// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import AppKit
import Foundation
import Observation
import WellkeptCore

//  Permissions.swift
//  Wellkept
//
//  Ported from Scout's `App/Permissions.swift` — the only shipped, unsandboxed, notarized,
//  direct-download Mac app in the house, and the one that already got the honest Full Disk Access
//  probe right.
//
//  ## What is different here, and why
//
//  Scout's `Permission.Action` had an `.ask` case for Contacts and Reminders, which macOS will
//  prompt for from inside an app. Wellkept asks for nothing that has a request API: Full Disk
//  Access can only be granted by the user in System Settings. The `.ask` case is dropped rather
//  than carried as a shape nothing fills. When a future section needs a promptable permission it
//  comes back, one case, in this file.
//
//  Scout also stamped the date each permission was first seen granted. Dropped: it is a fourth
//  stored key for a line nobody asked for, and the two keys this app stores about setup are
//  exactly the two in `docs/CONTRACTS.md`.

// MARK: - The deep links

/// **Every `x-apple.systempreferences:` URL in the app lives here, and nowhere else.**
///
/// These anchors are Apple implementation detail, not API. They have been renamed before, and
/// macOS 27 — which ships within weeks — is exactly the kind of release that renames them again.
/// One file means one edit when that happens, instead of a hunt through seven section faces.
enum SystemSettingsLink: String {

    /// Privacy & Security ▸ Full Disk Access.
    case fullDiskAccess = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"

    /// Privacy & Security, top of the pane. The fallback when an anchor above stops resolving.
    case privacyAndSecurity = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"

    /// Opens the pane, falling back to the top of Privacy & Security if the deep anchor is gone.
    ///
    /// `NSWorkspace.open` reports whether the URL could be handed to a handler at all — it cannot
    /// tell us that System Settings landed on the wrong pane. So this is a floor, not a guarantee:
    /// the worst case after a rename is the user arriving one level up, rather than nothing
    /// happening when they press the button.
    @MainActor
    @discardableResult
    func open() -> Bool {
        guard let url = URL(string: rawValue) else { return Self.openPrivacyRoot() }
        if NSWorkspace.shared.open(url) { return true }
        return self == .privacyAndSecurity ? false : Self.openPrivacyRoot()
    }

    @MainActor
    private static func openPrivacyRoot() -> Bool {
        guard let url = URL(string: Self.privacyAndSecurity.rawValue) else { return false }
        return NSWorkspace.shared.open(url)
    }
}

// MARK: - The honest probe

/// Whether Full Disk Access has actually been granted.
///
/// ⚠️ **The obvious checks are all wrong.** There is no API that answers this. `FileManager`'s
/// `isReadableFile` reports POSIX permissions, which say yes for the user's own Library whether or
/// not the switch is on — macOS enforces this separately, at the moment the file is opened. And
/// asking the user "did you turn it on?" is worse than useless: they answer for what they intended
/// to do, and the app then reports a clean Mac it was never allowed to look at.
///
/// So the only honest test is to try to read something that is unreadable without the grant, and
/// believe the result.
enum FullDiskAccess {

    /// Files that exist on every Mac and cannot be opened without Full Disk Access.
    ///
    /// More than one, because a probe file that is missing tells us nothing — a Mac with Mail never
    /// configured has no `~/Library/Mail`, and Scout's probe would have read that absence as a
    /// refusal. The TCC databases are the reliable pair: macOS creates them on every install, and
    /// they are precisely what the switch protects.
    private static var probes: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appending(path: "Library/Application Support/com.apple.TCC/TCC.db"),
            URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db"),
            home.appending(path: "Library/Safari/Bookmarks.plist"),
        ]
    }

    /// True only when a real read of a real protected file succeeded.
    ///
    /// A probe whose file does not exist is skipped rather than counted as a refusal. If none of
    /// them exists — which would mean a Mac unlike any we have seen — the answer is "not granted",
    /// because the whole point is never to claim sight we cannot demonstrate.
    static var isGranted: Bool {
        probes.contains { canRead($0) }
    }

    /// Opening can succeed where reading does not, so take a byte before believing it.
    private static func canRead(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 1)) != nil
    }

    /// The sections whose answers are incomplete while this is off.
    ///
    /// **Derived from `shortfall(for:)` rather than listed separately**, so the two can never
    /// disagree — a hand-kept second list is how a section ends up flagged as blind on Overview
    /// while its own face says nothing.
    ///
    /// Hardware is absent on purpose: it reads the drive, battery and sensors through IOKit, which
    /// this switch does not cover. Saying otherwise on the Hardware face would be a warning about
    /// something that is not true.
    static var affectedSections: [SectionID] {
        SectionID.allCases.filter { shortfall(for: $0) != nil }
    }

    /// What each section loses, in that section's own terms. Shown on the section's own face, so it
    /// says what is missing *here* rather than repeating the general notice.
    static func shortfall(for section: SectionID) -> String? {
        switch section {
        case .storage:
            String(localized: "Full Disk Access is off, so this cannot see everything using your space.")
        case .apps:
            String(localized: "Full Disk Access is off, so some apps will be missing from the list.")
        case .security:
            String(localized: "Full Disk Access is off, so this cannot read what macOS has already blocked.")
        case .backup:
            String(localized: "Full Disk Access is off, so this cannot see every backup on this Mac.")
        case .changes:
            String(localized: "Full Disk Access is off, so some settings are hidden from this comparison.")
        case .overview, .hardware:
            nil
        }
    }

    /// What the grant is for, said once, in the fewest plain words that carry it. Used by the setup
    /// step, the standing notice and Settings ▸ Permissions, so the app never contradicts itself.
    static let purpose = String(localized: """
        macOS keeps parts of this Mac private, even from you. Full Disk Access lets Wellkept read \
        them — the records macOS keeps of what it has blocked, other apps' support files, and \
        folders like Mail and Messages.
        """)

    static let consequence = String(localized: """
        Without it Wellkept still works. It just cannot see all of your storage, cannot tell you \
        what macOS has already blocked, and will say so on the screen rather than call this Mac \
        clean after a partial look.
        """)

    static let reassurance = String(localized: """
        Wellkept only reads. It never deletes anything, nothing it reads leaves this Mac, and you \
        can switch this off again in System Settings whenever you like.
        """)
}

// MARK: - The model

/// One thing macOS makes the user allow before Wellkept can do part of its job.
struct Permission: Identifiable, Sendable {

    enum State: Equatable, Sendable {
        case granted
        case notGranted

        var isGranted: Bool { self == .granted }

        /// The word on screen. Never the raw case.
        var label: String {
            self == .granted
                ? String(localized: "On", comment: "A permission that has been granted")
                : String(localized: "Off", comment: "A permission that has not been granted")
        }
    }

    let id: String
    let title: String
    /// What stops working without it, in the user's terms.
    let purpose: String
    let symbol: String
    var state: State
    /// No API exists to request any of these; all an app can do is open the pane that can.
    let link: SystemSettingsLink
}

/// Reads the real state of every permission Wellkept uses, and notices when one changes.
///
/// macOS has no single place to ask "what am I allowed to do", and nothing Wellkept needs can be
/// requested from inside the app at all. So this checks the only way that is honest — by trying —
/// and keeps the answer in one place that the setup flow, Overview, the section faces and Settings
/// all read, so they cannot disagree with each other on screen.
///
/// ⚠️ **This never asks for anything on its own.** Setup asks once. After that the app's only
/// reminder is the quiet notice in `PermissionNotice.swift`. A utility that re-raises a refused
/// permission is the reason people stop opening utilities.
@MainActor
@Observable
final class PermissionCenter {

    /// One instance, because four separate screens read the same answer and a second copy would
    /// eventually show a different one.
    static let shared = PermissionCenter()

    private(set) var permissions: [Permission] = []

    /// True when the user has left for System Settings during this launch. It is what turns the
    /// dead end — "you say it is on, we still cannot read" — into an offer to start again.
    /// Deliberately not stored: it describes this run of the app, not the user.
    private(set) var visitedSettings = false

    /// `nonisolated(unsafe)` for one reason, and it is a narrow one: this is written only on the
    /// main actor, in `watchForReturn()`, and read only in `deinit` — which by definition runs when
    /// nothing else holds a reference and no other thread can be touching it. Without the
    /// annotation the observer token cannot be handed back to `NotificationCenter` at all, and a
    /// centre created for a test would leave a live block behind.
    @ObservationIgnored private nonisolated(unsafe) var activationObserver: (any NSObjectProtocol)?

    init() {
        refresh()
        watchForReturn()
    }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }


    // MARK: Reading the truth

    var fullDiskAccessGranted: Bool {
        permissions.first { $0.id == Self.fullDiskID }?.state.isGranted ?? false
    }

    /// Whether every check the app can run would see the whole picture.
    ///
    /// ⚠️ Overview reads this. It may **never** say the Mac looks fine while this is false — a
    /// clean result from a partial look is the one lie this app must not tell.
    var everythingVisible: Bool { fullDiskAccessGranted }

    /// True when the user has been to System Settings and we still cannot read.
    ///
    /// macOS does not extend an already-running process's access the moment the switch is flipped;
    /// the app has to start again. This is the state that offers that, rather than asking the user
    /// whether they really did it.
    var needsReopenToSee: Bool { visitedSettings && !fullDiskAccessGranted }

    func refresh() {
        permissions = [fullDiskAccess]
    }

    private static let fullDiskID = "fullDisk"

    private var fullDiskAccess: Permission {
        Permission(
            id: Self.fullDiskID,
            title: String(localized: "Full Disk Access", comment: "Name of the macOS permission"),
            purpose: FullDiskAccess.purpose,
            symbol: "externaldrive",
            state: FullDiskAccess.isGranted ? .granted : .notGranted,
            link: .fullDiskAccess
        )
    }

    // MARK: Acting

    /// Open the pane that can grant it, and remember that the user went.
    func openSettings(for permission: Permission) {
        visitedSettings = true
        permission.link.open()
    }

    /// The same, for the one permission this version has, from a screen that has no `Permission`
    /// value in hand.
    func openFullDiskAccessSettings() {
        visitedSettings = true
        SystemSettingsLink.fullDiskAccess.open()
    }

    /// Start Wellkept again so macOS hands the new process the access it just granted.
    ///
    /// ⚠️ **Only ever from a button the user pressed.** Quitting an app the user is looking at,
    /// unannounced, is how a utility loses trust in one move — and there is no undo for a window
    /// that vanished. The new instance is launched first and this one goes away only once it is on
    /// its way, so a failure to launch leaves the user with the app they had.
    func reopenWellkept() {
        Task { @MainActor in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            do {
                _ = try await NSWorkspace.shared.openApplication(
                    at: Bundle.main.bundleURL, configuration: configuration
                )
                NSApp.terminate(nil)
            } catch {
                // Leave the running app alone. The notice stays on screen and the user can try
                // again, which is a better outcome than no Wellkept at all.
            }
        }
    }

    // MARK: Noticing

    /// Re-read the truth whenever Wellkept comes back to the front.
    ///
    /// This is the whole detection story for a permission that lives in another app: the user
    /// leaves, flips a switch, comes back — and the screen has already caught up before they look
    /// at it. Nothing polls, and nobody is asked whether they did it.
    private func watchForReturn() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
}

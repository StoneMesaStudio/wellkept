import AppKit

//  SystemSettingsPane.swift
//  Wellkept — App/Settings
//
//  **Every `x-apple.systempreferences:` link in the app lives here.** One file, by contract.
//
//  These URLs are not API. They are internal anchor names that Apple renames without notice, and
//  **macOS 27 ships within weeks and is exactly the kind of release that renames them** — it has
//  already reorganised the System Settings sidebar once. Scattered across a dozen call sites they
//  would rot invisibly: a button that opens the wrong pane still opens *a* pane, so nothing looks
//  broken and nobody reports it.
//
//  So: one list, one fallback, and one place to fix them all in September.
//
//  ## ⚠️ Not every pane is a corner of Privacy & Security
//
//  Added 2026-08-27, for the Security section. The first four cases are anchors *within* Privacy &
//  Security; the four the Security section needs are separate panes with their own extension names —
//  the firewall moved into Network in Ventura, and automatic login has always lived in Users &
//  Groups. So each case names its own root, and the fallback walks outwards: the exact anchor, then
//  that case's own pane, then Privacy & Security. A person who asked for the firewall and got the
//  Network pane has been helped; one who got a dead button has not.

enum SystemSettingsPane: String, CaseIterable, Sendable {

    /// The Privacy & Security pane itself. Also the last-resort fallback for everything below.
    case privacyAndSecurity
    /// Full Disk Access — the one that has to be granted by dragging the app into a list.
    case fullDiskAccess
    /// Files and Folders: Desktop, Documents, Downloads, each granted separately.
    case filesAndFolders
    /// Removable volumes — external drives, which is where a backup goes.
    case removableVolumes

    // ── Added 2026-08-29 for the Backup section ─────────────────────────────────────────────────
    //
    //  ⚠️ **A destination, never a switch.** `TimeMachineState.remedy` names this pane and nothing
    //  else: Wellkept never enables, disables or starts a backup. The row's button puts the person
    //  in front of the control that owns it, and they decide.
    //
    //  Time Machine is its own pane in macOS 26 — bundle id read from
    //  `/System/Library/ExtensionKit/Extensions/TimeMachineSettings.appex` on 2026-08-29 — so it
    //  gets its own root rather than falling into Privacy & Security.

    /// Time Machine, which owns whether this Mac backs itself up and where to.
    case timeMachine

    /// FileVault. Lives in Privacy & Security, below Gatekeeper's "Allow applications from".
    case fileVault
    /// The firewall — **in Network settings since Ventura**, not in Security where it used to be.
    case firewall
    /// Software Update, which owns whether security fixes install by themselves.
    case softwareUpdate
    /// Users & Groups, which owns automatic login.
    case usersAndGroups

    // ── Added 2026-08-28 for the Changes section ────────────────────────────────────────────────
    //
    //  ⚠️ **These are destinations, not verbs.** John, 2026-08-28: Wellkept writes no setting,
    //  ever. Changes shows what changed and opens the pane where a person can change it back
    //  themselves. There is no fifth verb; "Open Settings" is where the row goes, not something the
    //  app does to the Mac.
    //
    //  The eleven privacy anchors are one line each and worth it: pointing somebody at Privacy &
    //  Security when what moved was Screen Recording leaves them scrolling a list of twelve
    //  headings. A renamed anchor falls back to the pane and then to Privacy & Security, which is
    //  no worse than where they would have started.

    /// Sharing — Screen Sharing, Remote Login, File Sharing, Remote Management, AirPlay Receiver.
    case sharing
    /// General ▸ Login Items & Extensions.
    case loginItems
    /// General ▸ Device Management, where configuration profiles are listed.
    case profiles

    case camera
    case microphone
    case screenRecording
    case accessibility
    case inputMonitoring
    case locationServices
    case contacts
    case calendars
    case reminders
    case photos
    /// "Automation" in Apple's words — one app driving another.
    case automation

    private static let privacyRoot = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"

    /// Which pane this case lives in.
    private var root: String {
        switch self {
        case .privacyAndSecurity, .fullDiskAccess, .filesAndFolders, .removableVolumes, .fileVault,
             .camera, .microphone, .screenRecording, .accessibility, .inputMonitoring,
             .locationServices, .contacts, .calendars, .reminders, .photos, .automation:
            Self.privacyRoot
        case .sharing:
            "x-apple.systempreferences:com.apple.Sharing-Settings.extension"
        case .loginItems, .profiles:
            "x-apple.systempreferences:com.apple.SystemProfiler.AboutExtension"
        case .firewall:
            "x-apple.systempreferences:com.apple.Network-Settings.extension"
        case .softwareUpdate:
            "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"
        case .usersAndGroups:
            "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension"
        case .timeMachine:
            "x-apple.systempreferences:com.apple.Time-Machine-Settings.extension"
        }
    }

    /// The anchor within that pane, where there is one.
    private var anchor: String? {
        switch self {
        case .privacyAndSecurity, .softwareUpdate, .usersAndGroups, .sharing, .timeMachine: nil
        case .fullDiskAccess:   "Privacy_AllFiles"
        case .filesAndFolders:  "Privacy_FilesAndFolders"
        case .removableVolumes: "Privacy_RemovableVolume"
        case .fileVault:        "FileVault"
        case .firewall:         "Firewall"
        case .loginItems:       "LoginItems-Extensions"
        case .profiles:         "Profiles"
        case .camera:           "Privacy_Camera"
        case .microphone:       "Privacy_Microphone"
        case .screenRecording:  "Privacy_ScreenCapture"
        case .accessibility:    "Privacy_Accessibility"
        case .inputMonitoring:  "Privacy_ListenEvent"
        case .locationServices: "Privacy_LocationServices"
        case .contacts:         "Privacy_Contacts"
        case .calendars:        "Privacy_Calendars"
        case .reminders:        "Privacy_Reminders"
        case .photos:           "Privacy_Photos"
        case .automation:       "Privacy_Automation"
        }
    }

    var url: URL? {
        guard let anchor else { return URL(string: root) }
        return URL(string: "\(root)?\(anchor)")
    }

    /// Open it, falling back outwards when the anchor no longer resolves.
    ///
    /// The fallback is the whole point of routing every link through one function. A renamed anchor
    /// leaves the user one scroll away from what they wanted instead of staring at a button that
    /// did nothing — and "did nothing" is what an unrecognised anchor actually produces.
    @discardableResult
    @MainActor
    func open() -> Bool {
        if let url, NSWorkspace.shared.open(url) { return true }
        if let pane = URL(string: root), NSWorkspace.shared.open(pane) { return true }
        guard let privacy = URL(string: Self.privacyRoot) else { return false }
        return NSWorkspace.shared.open(privacy)
    }
}

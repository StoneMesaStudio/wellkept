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

    /// FileVault. Lives in Privacy & Security, below Gatekeeper's "Allow applications from".
    case fileVault
    /// The firewall — **in Network settings since Ventura**, not in Security where it used to be.
    case firewall
    /// Software Update, which owns whether security fixes install by themselves.
    case softwareUpdate
    /// Users & Groups, which owns automatic login.
    case usersAndGroups

    private static let privacyRoot = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"

    /// Which pane this case lives in.
    private var root: String {
        switch self {
        case .privacyAndSecurity, .fullDiskAccess, .filesAndFolders, .removableVolumes, .fileVault:
            Self.privacyRoot
        case .firewall:
            "x-apple.systempreferences:com.apple.Network-Settings.extension"
        case .softwareUpdate:
            "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"
        case .usersAndGroups:
            "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension"
        }
    }

    /// The anchor within that pane, where there is one.
    private var anchor: String? {
        switch self {
        case .privacyAndSecurity, .softwareUpdate, .usersAndGroups: nil
        case .fullDiskAccess:   "Privacy_AllFiles"
        case .filesAndFolders:  "Privacy_FilesAndFolders"
        case .removableVolumes: "Privacy_RemovableVolume"
        case .fileVault:        "FileVault"
        case .firewall:         "Firewall"
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

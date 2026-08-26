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

enum SystemSettingsPane: String, CaseIterable, Sendable {

    /// The Privacy & Security pane itself. Also the fallback for everything below.
    case privacyAndSecurity
    /// Full Disk Access — the one that has to be granted by dragging the app into a list.
    case fullDiskAccess
    /// Files and Folders: Desktop, Documents, Downloads, each granted separately.
    case filesAndFolders
    /// Removable volumes — external drives, which is where a backup goes.
    case removableVolumes

    private static let privacyRoot = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"

    /// The anchor within Privacy & Security, where there is one.
    private var anchor: String? {
        switch self {
        case .privacyAndSecurity: nil
        case .fullDiskAccess:     "Privacy_AllFiles"
        case .filesAndFolders:    "Privacy_FilesAndFolders"
        case .removableVolumes:   "Privacy_RemovableVolume"
        }
    }

    var url: URL? {
        guard let anchor else { return URL(string: Self.privacyRoot) }
        return URL(string: "\(Self.privacyRoot)?\(anchor)")
    }

    /// Open it, falling back to the Privacy & Security pane when the anchor no longer resolves.
    ///
    /// The fallback is the whole point of routing every link through one function. A renamed
    /// anchor leaves the user one scroll away from what they wanted instead of staring at a button
    /// that did nothing — and "did nothing" is what an unrecognised anchor actually produces.
    @discardableResult
    @MainActor
    func open() -> Bool {
        if let url, NSWorkspace.shared.open(url) { return true }
        guard let root = URL(string: Self.privacyRoot) else { return false }
        return NSWorkspace.shared.open(root)
    }
}

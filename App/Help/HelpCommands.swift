import SwiftUI

//  HelpCommands.swift
//  Wellkept — App/Help
//
//  The Help menu, which is also where the uninstaller lives — DESIGN §10 asks for that by name.
//
//  Five items, in this order:
//
//      Wellkept Help                ⌘?
//      Quarantine…
//      Report an Issue…
//      Support this project    ▸
//      ──────────────────
//      Uninstall Wellkept…
//
//  **Quarantine sits second because it is the only item here that is about the user's own files.**
//  It has no section of its own yet — Storage will own it — and until then this menu and the
//  Settings page are the only two doors to a list of files Wellkept has moved out of somebody's
//  home folder. A holding pen nobody can open is not a holding pen.
//
//  The separator is doing real work: it puts the one item that removes the app on its own, away
//  from the three that open a web page. An interface should not make it easy to perform a
//  destructive action by muscle memory.
//
//  ⚠️ **"Support this project" is the entire monetisation of Wellkept, and it is one quiet menu
//  item.** It is never shown during setup, never on Overview, never in a banner, and never counted
//  or reacted to. A free GPL app that nags is a free GPL app somebody forks.

/// Every address the app opens, in one place.
///
/// ⚠️ **Unverified as of 2026-08-26.** The repository is public from the first commit and the
/// sponsor pages follow the house pattern, but none of these four have been opened and confirmed.
/// A Help menu item that lands on a 404 is worse than one that is missing, so somebody confirms
/// these before the first release goes out.
enum WellkeptLinks {
    static let source = URL(string: "https://github.com/StoneMesaStudio/wellkept")!
    static let reportIssue = URL(string: "https://github.com/StoneMesaStudio/wellkept/issues/new")!
    static let gitHubSponsors = URL(string: "https://github.com/sponsors/StoneMesaStudio")!
    static let koFi = URL(string: "https://ko-fi.com/stonemesastudio")!
}

struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Wellkept Help") { openWindow(id: HelpWindowID.value) }
                .keyboardShortcut("?", modifiers: .command)

            Button("Quarantine…") { openWindow(id: QuarantineWindowID.value) }

            Button("Report an Issue…") { openURL(WellkeptLinks.reportIssue) }

            // A menu rather than a single link, because there are two places to give and picking
            // one for the user would be picking a fee structure for them. A `Menu` shows its own
            // arrow, so it announces that it hides something — DESIGN §7.2.
            Menu("Support this project") {
                Button("GitHub Sponsors…") { openURL(WellkeptLinks.gitHubSponsors) }
                Button("Ko-fi…") { openURL(WellkeptLinks.koFi) }
                Divider()
                Button("Source Code…") { openURL(WellkeptLinks.source) }
            }

            Divider()

            // ⚠️ **Insertion point for "Run Setup Again…", which the contract requires and this
            // file cannot yet provide.** Setup is a separate owner's flow and there is no symbol to
            // call; it belongs directly under "Wellkept Help", above "Report an Issue…", so that
            // the three web items stay together. Nothing that runs once may be unreachable
            // afterwards (DESIGN §14.6).

            Button("Uninstall Wellkept…") { Uninstaller.run() }
        }
    }
}

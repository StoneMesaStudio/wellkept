import SwiftUI
import AppKit
import WellkeptCore

//  WellkeptApp.swift
//  Wellkept
//
//  One window, a normal title bar, the menu bar — and, since 2026-08-29, two ways to start.
//
//  ## ⭐ The same executable is also the background piece
//
//  `WellkeptEntry` is `@main`, not `WellkeptApp`. It looks at the command line first: launchd starts
//  this same binary with `--background-piece`, and that path never touches SwiftUI or
//  `NSApplication` at all — no window, no menu bar, no Dock tile. Everything it does is in
//  `App/Backup/Agent/`.
//
//  ⚠️ **The same binary is the point, not a shortcut.** macOS decides Full Disk Access from the code
//  signature of the process asking; a separate helper would be a different program with a different
//  identity, and a scheduled backup made without the grant contains no mail, no messages and no
//  photos — silently, with no error. See `BackgroundPiece.swift`.
//
//  ## Closing the window quits the app, unless the person switched the background piece on
//
//  There is no menu-bar icon yet, so an app still running with nothing on screen is a process the
//  user cannot find and cannot stop without the Dock or Activity Monitor. That is still true of the
//  app. It is **not** true of the background piece, which is a separate process the person switches
//  on themselves and can see and stop in System Settings ▸ General ▸ Login Items — which is exactly
//  what makes it allowed to exist. `Backup.whatHappensWhenTheWindowCloses` is the sentence, written
//  once. When the menu-bar icon ships, this flips: closing will hide, and the rule a person learns
//  is *if the icon is there, the app is still there.* One rule, and it is always visibly true.
//
//  ## Why the other three scenes are mounted here
//
//  A `Scene` can only be declared in an `App` body, so Settings and Help are named in this file
//  even though both are written elsewhere. Each owner ships its own `Scene` — `WellkeptSettingsScene`
//  and `HelpScene` — so what this file names is a scene, never the views inside it.

// MARK: - The delegate

/// Exists for one line. SwiftUI has no scene-level equivalent of "quit when the last window
/// closes", and the AppKit default on macOS is to keep running with no window and no way back.
@MainActor
final class WellkeptAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - ⭐ Which of the two things this process is

/// **The entry point, and the only thing in the app that reads the command line.**
///
/// It exists so `runUntilKilled()` can be reached before SwiftUI is: `App` supplies its own
/// `main()`, and there is no hook inside it that runs early enough to decide not to be an
/// application at all.
///
/// ⚠️ `MainActor.assumeIsolated` is correct rather than convenient — `main()` runs on the main
/// thread by definition, and the background piece's timer and workspace observer both need the main
/// run loop they are about to be added to.
@main
enum WellkeptEntry {
    static func main() {
        if BackgroundPiece.isTheBackgroundPiece() {
            MainActor.assumeIsolated { BackgroundPieceProcess.runUntilKilled() }
            return
        }
        WellkeptApp.main()
    }
}

// MARK: - The app

struct WellkeptApp: App {
    @NSApplicationDelegateAdaptor(WellkeptAppDelegate.self) private var delegate

    /// ⚠️ **Held here, above `AppearanceHost`, and that placement is load-bearing.**
    /// `AppearanceHost` re-identifies everything inside it whenever the font or text size changes,
    /// which destroys every `@State` beneath it. The selected section, the open disclosures and any
    /// sheet in flight all live in this object precisely so a ⌘+ press cannot throw them away.
    @State private var app = AppState()

    /// Whether setup is on screen. Above `AppearanceHost` for the same reason, and because Help's
    /// "Run Setup Again…" has to reach it from the menu bar, which is outside every view.
    @State private var setup = SetupState()

    var body: some Scene {
        // `Window`, not `WindowGroup`: this app is one window. A `WindowGroup` hands the user ⌘N
        // and a second copy of a health check for the same Mac, which is two screens that can
        // disagree about what was found.
        Window("Wellkept", id: "main") {
            AppearanceHost {
                RootView()
                    .environment(app)
                    .environment(setup)
            }
            // The floor. Below this the rail and a 700-pt readable column stop fitting side by
            // side, which is the point where dragging smaller destroys the layout rather than
            // compressing it. Stated on the content so `.contentMinSize` can enforce it while the
            // window stays free to grow — and to go full screen.
            .frame(minWidth: Layout.windowMinimum.width,
                   minHeight: Layout.windowMinimum.height)
        }
        .defaultSize(width: Layout.windowDefault.width, height: Layout.windowDefault.height)
        .windowResizability(.contentMinSize)
        .commands { commands }

        // ⌘, and the sidebar's foot row both land here.
        WellkeptSettingsScene()

        // ⌘? and Help ▸ Wellkept Help. A window rather than a website, so the answer to "how does
        // this work" is inside the app.
        HelpScene()

        // Help ▸ Quarantine…, Settings ▸ Quarantine, and the launch bar's *Show Quarantine*.
        //
        // ⚠️ **A window rather than a sheet on the main window, and that is deliberate.** It lists
        // the user's own files, and somebody deciding whether to put one back wants to keep looking
        // at the section that set it aside while they decide. It moves into the Storage face when
        // that face is built; nothing in it assumes a window.
        QuarantineScene()
    }

    // MARK: Menus

    @CommandsBuilder private var commands: some Commands {
        // Nothing in this app is a document, so there is no New.
        CommandGroup(replacing: .newItem) { }

        CommandGroup(replacing: .printItem) {
            // ⚠️ **Present and greyed, not absent.** Both belong to Overview and both need Overview
            // to have found something first. A command that appears once the app grows a feature is
            // a command nobody knows to look for; a greyed one is a promise you can read today.
            // `.help` carries the reason, since a menu has nowhere to say it.
            //
            // ⚠️ **Neither one prints or writes anything.** Both open `HealthReportSheet`, which
            // shows the whole page before any of it leaves the app — the page carries the Mac's
            // name and, unless the person switches it off, its serial number. ⌘P straight to a
            // printer with a serial number on the paper and no chance to look first is exactly the
            // thing this app exists to catch other software doing. See `HealthReportSheet`.
            Button(HealthReportSheet.Intent.save.title) { app.presentHealthReport(.save) }
                .disabled(!app.canMakeHealthReport)
                .help(app.canMakeHealthReport
                      ? "Show the report, then save it as a PDF."
                      : "There is nothing to save until a check has run.")
            Button(HealthReportSheet.Intent.print.title) { app.presentHealthReport(.print) }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(!app.canMakeHealthReport)
                .help(app.canMakeHealthReport
                      ? "Show the report, then print it."
                      : "There is nothing to print until a check has run.")
        }

        // View ▸ Text Size. Written by whoever owns the slider it shares a key with, so the menu
        // and the slider cannot drift apart on what 150% means.
        TextSizeCommands()

        // The rail's seven, in the rail's order, numbered the way they are listed. Every place the
        // app can go has a menu-bar route — Apple's hardest structural requirement, and the
        // cheapest way to make the whole app reachable from the keyboard.
        CommandMenu("Go") {
            ForEach(Array(SectionID.allCases.enumerated()), id: \.element) { index, section in
                Button(section.title) { app.selection = section }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }

        // Wellkept Help · Report an Issue · Support this project · Uninstall Wellkept.
        HelpCommands()

        // ⚠️ **Setup's only door after the first launch, and it has to exist.** Nothing that runs
        // once may be unreachable afterwards. It sits in its own group because the Help menu's four
        // items are `replacing: .help` in another file; a second group after them is the only way
        // to add to that menu from here without taking it over. Fold it into `HelpCommands` the day
        // that file can reach `SetupState`, and delete this.
        CommandGroup(after: .help) {
            Button("Run Setup Again…") { setup.present() }
        }
    }
}

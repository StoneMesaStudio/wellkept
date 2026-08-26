import SwiftUI
import AppKit
import WellkeptCore

//  WellkeptApp.swift
//  Wellkept
//
//  One window, a normal title bar, and the menu bar.
//
//  ## Closing the window quits the app
//
//  There is no menu-bar icon yet, so an app still running with nothing on screen is a process the
//  user cannot find and cannot stop without the Dock or Activity Monitor. When the icon ships, this
//  flips: closing will hide, and the rule a person learns is *if the icon is there, the app is
//  still there.* One rule, and it is always visibly true.
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

// MARK: - The app

@main
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
            Button("Save as PDF…") { }
                .disabled(true)
                .help("There is nothing to save until a check has run.")
            Button("Print…") { }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(true)
                .help("There is nothing to print until a check has run.")
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

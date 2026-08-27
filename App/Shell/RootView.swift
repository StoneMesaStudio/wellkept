import SwiftUI
import UniformTypeIdentifiers
import WellkeptCore

//  RootView.swift
//  Wellkept — App/Shell
//
//  The window: a fixed rail of words on the left, one section on the right.
//
//  ## Why this is an HStack and not a NavigationSplitView
//
//  Both of the house's design-law apps hand-roll the rail, and the reason is the bug this project
//  keeps rediscovering: a detail view whose root does not claim its full height gets **vertically
//  centred** by the split view — a heading stranded mid-window with empty gutters above and below
//  it, and the page ground covering only the band. An `HStack` with a hard-width sibling has no
//  such container to centre anything, and every face here also calls `.fillsPane()`, so the bug is
//  guarded twice.
//
//  The trade is that nothing about the rail comes free — no collapse, no system animation. This
//  app does not want either: the rail is always visible, by decision.

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(SetupState.self) private var setup

    var body: some View {
        @Bindable var app = app

        ZStack {
            shell

            // ⚠️ **Setup COVERS the window; it does not replace this view.**
            //
            // Two reasons, both learned elsewhere. Presented from outside `AppearanceHost` it would
            // sit outside the palette — a welcome page in light-mode colours on a dark-mode Mac,
            // which is the first screen anyone ever sees. And swapping the shell out for it would
            // take the app's single sheet, alert and file-picker slots off screen with it, so every
            // button in setup that raises one would silently do nothing.
            //
            // A full-window cover rather than a panel over the shell: during setup the sidebar is
            // not usable, and showing it greyed behind a scrim would be an invitation to click it.
            if setup.isPresented {
                SetupFlow(onFinish: setup.finish)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .pageGround()
                    // The macOS reflex, and the same answer as "Finish later": both are answers,
                    // and there is no such thing as deferring here.
                    .onExitCommand { setup.finish() }
                    .transition(.faceFade)
            }
        }
        .appAnimation(Motion.selection, value: setup.isPresented)

        // ⚠️ **The whole of Wellkept's automatic behaviour, in one line.**
        //
        // Hardware is read once when the window opens, and after that only when a button is
        // pressed. There is no schedule and no background piece — the app quits when this window
        // closes — so this is the only place anything starts by itself, which is what makes that
        // promise checkable rather than a claim in the Help page.
        //
        // Keyed on setup: nothing reads the Mac while the welcome cover is up. A person who has
        // not finished being told what this app does has not agreed to it doing anything.
        // `HardwareModel.checkOnLaunch` runs at most once per launch, refuses in demo mode, and
        // refuses under the test harness — see its own note.
        .task(id: setup.isPresented) {
            guard !setup.isPresented else { return }
            await app.hardware.checkOnLaunch(demoMode: app.demoMode)
            if let report = app.hardware.report {
                app.publish(report.record, finding: report.overviewFinding)
            }
        }

        // ── The three modal slots ─────────────────────────────────────────────────────────
        //
        // ⚠️ **One of each, on this view, and nowhere else.** Two `.sheet` modifiers on one view
        // make SwiftUI silently drop one; the same is true of `.fileImporter`. There is no error
        // and no crash — a button simply does nothing, on some launches. Every caller in the app
        // routes through `AppState`, which can hold exactly one of each by construction.
        .sheet(item: $app.sheet) { route in
            route.content()
        }
        .alert(app.alert?.title ?? "",
               isPresented: Binding(get: { app.alert != nil },
                                    set: { if !$0 { app.alert = nil } }),
               presenting: app.alert) { route in
            if let confirmTitle = route.confirmTitle {
                Button(confirmTitle, role: route.confirmRole) { route.confirm?() }
                Button("Cancel", role: .cancel) { }
            } else {
                Button("OK", role: .cancel) { }
            }
        } message: { route in
            // A title and the verbs. Body text only where an action cannot be undone and the
            // consequence has to be stated.
            if let message = route.message { Text(message) }
        }
        .fileImporter(isPresented: Binding(get: { app.fileRequest != nil },
                                           set: { if !$0 { app.fileRequest = nil } }),
                      allowedContentTypes: app.fileRequest?.contentTypes ?? [],
                      allowsMultipleSelection: app.fileRequest?.allowsMultiple ?? false) { result in
            // Taken before it is cleared: dismissing the panel clears the request, and a completion
            // read afterwards would be reading `nil`.
            let request = app.fileRequest
            app.fileRequest = nil
            request?.completion(result)
        }
    }

    // MARK: The window itself

    private var shell: some View {
        // ⚠️ **The GeometryReader is a clamp, not a measurement.**
        //
        // A content-sized tree reports its own width and height to the window, and a window that
        // sizes to its content can be pushed past the screen — Lode ended up with saved window
        // frames taller than the display, its title bar under the menu bar, and the pinned foot of
        // its sidebar below the bottom edge. `GeometryReader` adopts the size it is *offered*, so
        // pinning the HStack to `geo.size` caps the whole tree at the window for every screen,
        // including the ones not written yet.
        GeometryReader { geo in
            HStack(spacing: 0) {
                Sidebar()

                VStack(spacing: 0) {
                    if app.demoMode { DemoBar() }

                    // ⚠️ **The animation lives on the view, not on the writers.** The sidebar,
                    // ⌘1–⌘7 and an Overview row all assign `selection`; wrapping each in a
                    // `withAnimation` would give the keyboard different behaviour from the mouse.
                    detail.faceTransition(app.selection)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // The page ground, painted once here for every face. A ground that each screen
                // opts into is not a ground — it is a decoration that some pages forgot.
                .pageGround()
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }

    @ViewBuilder private var detail: some View {
        switch app.selection {
        case .overview: OverviewView()
        case .hardware: HardwareView()
        case .storage:  StorageView()
        case .apps:     AppsView()
        case .security: SecurityView()
        case .backup:   BackupView()
        case .changes:  ChangesView()
        }
    }
}

// MARK: - The demo bar

/// Says, permanently and on every screen, that what is below it is invented.
///
/// Not a hint and not a nag: it is the app reporting its own state, and it disappears the moment
/// the switch is off. Without it a screenshot of a demo Storage screen is indistinguishable from a
/// real one, and the first person to act on an invented row would find the app had described a Mac
/// it had never looked at.
private struct DemoBar: View {
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: Space.gutter) {
            Text("Sample results. Wellkept has not looked at this Mac.")
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: Space.row)
            Button("Turn Off") { app.demoMode = false }
                .buttonStyle(.app)
                .controlSize(.small)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.row)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Achromatic on purpose. The three semantic colours mean good, not-yet-wrong and wrong;
        // dressing a mode switch as one of those is how a user learns to ignore the real ones.
        .background(Theme.stripe)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairlineInk).frame(height: Hairline.thin)
        }
    }
}

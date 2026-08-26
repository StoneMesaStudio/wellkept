import AppKit
import SwiftUI

//  SettingsView.swift
//  Wellkept — App/Settings
//
//  **Four controls and a permissions page. Nothing else.**
//
//  Settings only ever grows, and this is the one moment it is short enough to design rather than
//  organise. Everything here is either something the app must know without asking (how it should
//  look) or something macOS makes the user leave the app to change (a permission). Nothing that
//  belongs on the thing it concerns is allowed to move in here — DESIGN §1.2: a preference earns a
//  field only when the app must act without being asked.
//
//  ⚠️ **Every setting read app-wide must have a control on this screen.** Waypoint shipped the
//  opposite (`App/Shared/WaypointSettings.swift:31`): `fontFamily` and `textScale` were consulted
//  by every screen and settable nowhere, so they were constants with a `UserDefaults` lookup in
//  front of them. The five appearance keys are `AppearancePrefs`'; four of them have a control
//  below and the fifth (`identityColor`) has exactly one legal value, so there is nothing to
//  choose yet — when petrol and slate ship, they get a row here in the same pass.

struct SettingsView: View {

    enum Page: String, Hashable, CaseIterable, Identifiable, Sendable {
        case appearance, permissions
        var id: String { rawValue }
        var label: String {
            switch self {
            case .appearance:  "Appearance"
            case .permissions: "Permissions"
            }
        }
        var symbol: String {
            switch self {
            case .appearance:  "paintpalette"
            case .permissions: "lock"
            }
        }
    }

    /// Where to land. Something that opens Settings to make a point — a section that could not see
    /// the disk — says which page it means.
    var initialPage: Page = .appearance

    /// ⚠️ **Declared here, ABOVE `AppearanceHost`, on purpose.** The host hangs
    /// `.id(AppFont.typeKey)` on everything inside it, so any `@State` down there is discarded the
    /// moment the typeface or the text size changes — and both of those controls are on this
    /// screen. State kept inside would send the user back to the first tab every time they nudged
    /// the slider.
    @State private var page: Page = .appearance

    /// Read only so this view rebuilds when the type changes, which is what lets the window grow
    /// with it. `AppFont.scale` is a plain `UserDefaults` read: SwiftUI cannot see it, so a frame
    /// computed from it never updates unless something observable changes alongside.
    @AppStorage(AppearancePrefs.textScaleKey) private var textScale = 1.0

    var body: some View {
        AppearanceHost {
            TabView(selection: $page) {
                AppearanceSettings()
                    .tabItem { Label(Page.appearance.label, systemImage: Page.appearance.symbol) }
                    .tag(Page.appearance)
                PermissionSettings()
                    .tabItem { Label(Page.permissions.label, systemImage: Page.permissions.symbol) }
                    .tag(Page.permissions)
            }
        }
        // A floor, not a fixed size: the window may be dragged bigger, and it grows on its own as
        // the text does. A hard `.frame(width:height:)` here clips the permissions page at 200%.
        .frame(minWidth: SheetMetrics.width(560), minHeight: SheetMetrics.height(430))
        .onAppear { page = initialPage }
    }
}

// MARK: - The Settings scene

/// The Settings scene. `WellkeptApp` mounts this; ⌘, routes to it for free.
struct WellkeptSettingsScene: Scene {
    var body: some Scene {
        Settings { SettingsView() }
    }
}

/// Opens Settings from inside the window — the row at the foot of the sidebar, or a link in a
/// section that needs a permission.
///
/// ⚠️ **`SettingsLink`, not `openSettings()`.** The environment action goes through the responder
/// chain, which is fine from the main window and silently does nothing from anywhere else; Scout
/// lost its whole Settings command to exactly that. `SettingsLink` is a real button wired to the
/// scene and works from anywhere.
///
/// The label is the caller's, so the sidebar's foot row looks like the sidebar's other rows rather
/// than like something bolted underneath them.
struct OpenSettingsButton<Label: View>: View {
    @ViewBuilder var label: Label

    init(@ViewBuilder label: () -> Label) { self.label = label() }

    var body: some View {
        SettingsLink { label }
            .buttonStyle(.plain)
    }
}

// MARK: - View ▸ Text Size

/// ⌘+ / ⌘− / ⌘0, in the View menu.
///
/// macOS has no Dynamic Type and Apple's own guidance still asks for 200% enlargement, so this
/// command is the only enlargement the platform offers (DESIGN §4). It writes the same key the
/// slider in Settings writes, and clamps to the same bounds — Lode's ⌘+ counted to 250% while
/// `AppFont.scale` stopped at 200%, so the readout lied and ⌘− had to walk back down through the
/// phantom range before anything on screen moved.
struct TextSizeCommands: Commands {
    @AppStorage(AppearancePrefs.textScaleKey) private var textScale = 1.0

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Bigger Text") { step(+0.1) }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(textScale >= Double(AppFont.maxScale))
            Button("Smaller Text") { step(-0.1) }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(textScale <= Double(AppFont.minScale))
            Button("Actual Size") { textScale = 1 }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(textScale == 1)
            Divider()
        }
    }

    private func step(_ delta: Double) {
        // Rounded to a tenth at every step. Repeated addition of 0.1 drifts, and the drift shows
        // up as a percentage readout that says 149% at the point the user pressed ⌘+ five times.
        let next = ((textScale + delta) * 10).rounded() / 10
        textScale = min(Double(AppFont.maxScale), max(Double(AppFont.minScale), next))
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {

    @AppStorage(AppearancePrefs.modeKey) private var modeRaw = AppearancePrefs.defaultMode.rawValue
    @AppStorage(AppearancePrefs.colorLevelKey) private var levelRaw = AppearancePrefs.defaultLevel.rawValue
    @AppStorage(AppearancePrefs.fontFamilyKey) private var fontFamily = AppFont.defaultFamily
    @AppStorage(AppearancePrefs.textScaleKey) private var textScale = 1.0

    private var mode: Binding<AppearanceMode> {
        Binding(get: { AppearanceMode(rawValue: modeRaw) ?? AppearancePrefs.defaultMode },
                set: { modeRaw = $0.rawValue })
    }

    private var level: Binding<ColorLevel> {
        Binding(get: { ColorLevel(rawValue: levelRaw) ?? AppearancePrefs.defaultLevel },
                set: { levelRaw = $0.rawValue })
    }

    var body: some View {
        StableScrollView {
            Grid(alignment: .topLeading,
                 horizontalSpacing: Space.gutter,
                 verticalSpacing: Space.section) {

                GridRow {
                    rowLabel("Appearance")
                    SegmentedControl(
                        items: AppearanceMode.allCases.map { (value: $0, label: $0.label) },
                        selection: mode)
                }

                GridRow {
                    rowLabel("Colour")
                    VStack(alignment: .leading, spacing: Space.row) {
                        SegmentedControl(
                            items: ColorLevel.allCases.map { (value: $0, label: $0.label) },
                            selection: level)
                        // Says what the chosen setting actually does. It changes with the
                        // selection, so it is feedback rather than a hint that never retires —
                        // and "Minimal" is otherwise a word with no meaning attached to it.
                        Text(level.wrappedValue.blurb)
                            .font(.appCaption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                GridRow {
                    rowLabel("Text size")
                    VStack(alignment: .leading, spacing: Space.row) {
                        HStack(spacing: Space.gutter) {
                            Slider(value: $textScale,
                                   in: Double(AppFont.minScale)...Double(AppFont.maxScale),
                                   step: 0.1)
                                .frame(maxWidth: AppFont.pt(230))
                                .accessibilityLabel("Text size")
                                .accessibilityValue(percentage)
                            // Fixed width, so 100% and 200% do not move the control beside them.
                            Figure(percentage, size: 14, weight: .semibold)
                                .frame(width: AppFont.pt(52), alignment: .leading)
                                .accessibilityHidden(true)
                        }
                        // DESIGN §7.4: where a modifier-key shortcut exists, say so where the
                        // person would need it.
                        Text("⌘+ and ⌘− change this from anywhere; ⌘0 puts it back.")
                            .font(.appCaption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                GridRow {
                    rowLabel("Typeface")
                    SegmentedControl(
                        items: AppFont.families.map { (value: $0, label: $0) },
                        selection: $fontFamily)
                }
            }
            .padding(Space.page)
            .readableColumn(Layout.readableColumn)
        }
        .pageGround()
    }

    /// Percent in the reader's own number format. A comma-decimal region turned a weight into a
    /// 10× error in a shipped build; the habit is cheap here and expensive to acquire later.
    private var percentage: String {
        textScale.formatted(.percent.precision(.fractionLength(0)))
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.appHeadline)
            .foregroundStyle(Theme.textSecondary)
            .gridColumnAlignment(.trailing)
            // Sits the word against the top of the control box beside it rather than the top of
            // the cell, which at 200% text is a visible drift.
            .padding(.top, AppFont.pt(6))
    }
}

// MARK: - Permissions

/// One thing macOS makes the user allow before Wellkept can do part of its job.
///
/// Named `WellkeptPermission` rather than `Permission` so that the onboarding flow's own permission
/// model — which probes the live state, which this page does not — can keep the shorter name.
struct WellkeptPermission: Identifiable, Sendable {
    let id: String
    let title: String
    /// What it buys, in the user's terms.
    let purpose: String
    /// What Wellkept does without it. Never a threat — a refused permission is a supported way to
    /// run this app, and every section reports what it could not see rather than sulking.
    let without: String
    let pane: SystemSettingsPane
    /// macOS offers no prompt for this one; the app has to be dragged into a list by hand.
    let mustBeDraggedIn: Bool

    static let all: [WellkeptPermission] = [
        WellkeptPermission(
            id: "fullDisk",
            title: "Full Disk Access",
            purpose: "Lets Wellkept read the whole disk — what is using your space, what macOS "
                   + "has already flagged, and what changed on this Mac without you.",
            without: "Wellkept still runs, and each section says plainly what it could not see.",
            pane: .fullDiskAccess,
            mustBeDraggedIn: true),
        WellkeptPermission(
            id: "filesAndFolders",
            title: "Files and Folders",
            purpose: "Your Desktop, Documents and Downloads. macOS asks for these one at a time, "
                   + "the first time Wellkept reads one.",
            without: "Those three folders are left out of what Storage reports.",
            pane: .filesAndFolders,
            mustBeDraggedIn: false),
        WellkeptPermission(
            id: "removableVolumes",
            title: "Removable volumes",
            purpose: "External drives. Backup writes to the drive you choose, and checks what is "
                   + "already on it.",
            without: "Backup can use a folder on this Mac, but not an external drive.",
            pane: .removableVolumes,
            mustBeDraggedIn: false),
    ]
}

private struct PermissionSettings: View {
    var body: some View {
        StableScrollView {
            VStack(alignment: .leading, spacing: Space.card) {
                // The one thing a person reading this page wants settled before they read anything
                // else, and the one thing they cannot work out from the screen.
                Text("Wellkept asks for as little as it can, and nothing it reads leaves this Mac.")
                    .font(.appBody)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(WellkeptPermission.all) { permission in
                    PermissionCard(permission: permission)
                }
            }
            .padding(Space.page)
            .readableColumn(Layout.readableColumn)
        }
        .pageGround()
    }
}

private struct PermissionCard: View {
    let permission: WellkeptPermission

    var body: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            HStack(alignment: .firstTextBaseline, spacing: Space.gutter) {
                Text(permission.title)
                    .font(.appTitle3)
                Spacer(minLength: Space.gutter)
                Button("Open System Settings") { permission.pane.open() }
                    .buttonStyle(.app)
            }

            Text(permission.purpose)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(permission.without)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // ⚠️ Full Disk Access is the one macOS will not let an app prompt for: the user has to
            // find the app and drag it into a list, in a window that does not explain itself. This
            // is where utilities lose people (DESIGN §14.6), so it gets the steps rather than a
            // button and a shrug.
            if permission.mustBeDraggedIn {
                VStack(alignment: .leading, spacing: Space.hairline) {
                    Text("1.  The button above opens straight to Full Disk Access.")
                    Text("2.  Find Wellkept in the list and switch it on.")
                    Text("3.  If Wellkept is not listed, click + and pick it:")
                    Button("Reveal Wellkept in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    }
                    .buttonStyle(.app)
                    .controlSize(.small)
                    .padding(.leading, Space.gutter)
                    .padding(.top, Space.hairline)
                }
                .font(.appCaption)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, Space.hairline)
            }
        }
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }
}

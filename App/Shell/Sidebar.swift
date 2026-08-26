import SwiftUI
import WellkeptCore

//  Sidebar.swift
//  Wellkept — App/Shell
//
//  Seven words, in a fixed order, with Settings pinned at the foot.
//
//  ## Why there are no icons
//
//  "We as a people don't share a common graphical language" — and there is no glyph that means
//  *Changes* as opposed to *Apps*. A rail of seven icons would need a tooltip on every row to be
//  read at all, which is the definition of the wrong control. The words are the control.
//
//  ## Why there are no counts
//
//  A red 3 beside Storage would make the sidebar a scoreboard, and a scoreboard invites you to
//  chase it to zero. Storage will always have something in it; that is not a debt. Overview is the
//  one place the app says what needs a person, and it says it in a sentence.

struct Sidebar: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.hairline) {
                    ForEach(SectionID.allCases) { section in
                        SidebarRow(title: section.title,
                                   selected: app.selection == section) {
                            app.selection = section
                        }
                    }
                }
                .padding(.horizontal, Space.row)
                .padding(.vertical, Space.row)
            }
            // Left visible. Seven rows fit any window this app can be dragged to, but the rows
            // scale with the text setting and at 200% on a short window the last one goes under
            // the fold — where a hidden indicator would make it simply not exist.
            .scrollIndicators(.automatic)

            Spacer(minLength: 0)

            // The hairline that sets Settings apart from the seven. It is not one of them: the
            // seven answer a question about the Mac, and Settings is about the app.
            Divider().opacity(0.6)

            // Settings' own button, wearing this column's row face — so the foot looks like the
            // list rather than like something bolted underneath it. It wraps `SettingsLink`, which
            // is wired to the scene and therefore works from anywhere; the environment's
            // `openSettings()` goes through the responder chain and silently does nothing off the
            // main window, which is how Scout lost its Settings command.
            OpenSettingsButton {
                SidebarRowLabel(title: "Settings", selected: false)
            }
            .padding(.horizontal, Space.row)
            .padding(.vertical, Space.row)
        }
        // ⚠️ **The hard width is the window-explosion guard and it stays.** A sidebar that reports
        // its content's width hands that width to the window, and the window then hands it back —
        // the pair chase each other and the layout never settles. `Layout.sidebarWidth` scales with
        // the text setting, because the rows are words and a fixed rail truncates them at 200%.
        .frame(width: Layout.sidebarWidth, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        // A system material, not a painted colour: this is the surface macOS 27 restyles for free,
        // and only for the apps that did not draw their own.
        .background(.bar)
        .overlay(alignment: .trailing) { Divider() }
        .appAnimation(Motion.selection, value: app.selection)
    }
}

// MARK: - One row

private struct SidebarRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SidebarRowLabel(title: title, selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// The row's face, shared by the seven and by Settings so the foot cannot drift from the list.
private struct SidebarRowLabel: View {
    let title: String
    let selected: Bool

    @State private var hovering = false
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                // **Bolder words, as well as the plate.** With no icons a plate alone is a
                // colour carrying the whole meaning of "you are here", and Differentiate Without
                // Color switches exactly that off. The weight change survives it; so does the
                // spine below.
                .font(.appBody.weight(selected ? .semibold : .regular))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.row + 2)
        .padding(.vertical, AppFont.pt(7))
        .background {
            let shape = Radius.shape(Radius.control)
            if selected {
                // One of the three places bronze appears. `identitySoft` is an opaque mix toward
                // the ground rather than an alpha, because the rail sits on a system material and
                // an alpha would change colour as the window passed over a dark desktop.
                shape.fill(palette.identitySoft)
            } else if hovering {
                shape.fill(Theme.rowHover)
            }
        }
        .overlay(alignment: .leading) {
            // The cue that survives Differentiate Without Color, at the weight reserved for
            // selection and used nowhere else in the app.
            if selected && differentiate {
                Capsule().fill(Color.primary)
                    .frame(width: Hairline.selection)
                    .padding(.vertical, Space.hairline)
            }
        }
        .contentShape(Radius.shape(Radius.control))
        .onHover { hovering = $0 }
        .appAnimation(Motion.chrome, value: hovering)
    }
}

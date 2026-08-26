import SwiftUI

//  HelpWindow.swift
//  Wellkept — App/Help
//
//  The help browser: a rail of pages, a search field, and selectable text.
//
//  ⚠️ **It never opens itself.** No first-launch reveal, no "see what's new" on update. It is one
//  menu item and ⌘?. First launch already has a welcome page and a permission to ask about; a
//  third window stacked on those is a wall, not a welcome.
//
//  A separate window rather than an eighth section in the sidebar, because the sidebar is the seven
//  questions Wellkept answers about your Mac and help is not one of them — and because somebody
//  reading how to remove the app wants to keep the app on screen while they read.

enum HelpWindowID {
    /// The scene id. `openWindow(id:)` takes this string, so it lives in one place.
    static let value = "wellkept-help"
}

/// The Help window scene. `WellkeptApp` mounts this alongside the main window.
///
/// ⚠️ **This is a second window, and it changes what "closing the window quits" means.** If the app
/// terminates after the *last* window closes, then closing the main window while Help is open no
/// longer quits — which is right. What must not happen is quitting on the main window's close while
/// this one is still on screen, tearing away a page somebody is reading.
struct HelpScene: Scene {
    var body: some Scene {
        Window("Wellkept Help", id: HelpWindowID.value) {
            HelpBrowser()
        }
        .defaultSize(width: 860, height: 620)
        .defaultPosition(.center)
    }
}

struct HelpBrowser: View {

    // ⚠️ Above `AppearanceHost`, which re-identifies everything inside it whenever the typeface or
    // the text size changes. Selection and the search query kept below it would be thrown away by
    // a ⌘+ pressed while reading.
    @State private var selection = HelpLibrary.all.first?.id ?? ""
    @State private var query = ""

    private var results: [HelpArticle] { HelpLibrary.matching(query) }

    private var article: HelpArticle? {
        results.first { $0.id == selection } ?? results.first
    }

    var body: some View {
        AppearanceHost {
            HStack(spacing: 0) {
                rail
                Divider()
                detail
            }
            .fillsPane()
        }
        .frame(minWidth: SheetMetrics.width(720), minHeight: SheetMetrics.height(460))
    }

    // MARK: The rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: Space.block) {
            // Outside the scroll region on purpose. A search field that has to be scrolled to is a
            // search field nobody finds — and scroll indicators are not an affordance.
            TextField("Search help", text: $query)
                .textFieldStyle(.roundedBorder)
                .font(.appCallout)
                .accessibilityLabel("Search help")

            if results.isEmpty {
                InlineEmptyNote(symbol: "magnifyingglass", text: "No page mentions that.")
            } else {
                StableScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                            Button { selection = item.id } label: {
                                Text(item.title)
                                    .font(.appCallout.weight(item.id == article?.id ? .semibold : .regular))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .appRow(index, selected: item.id == article?.id, hPad: Space.row)
                            .accessibilityAddTraits(item.id == article?.id ? [.isSelected, .isButton] : .isButton)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.gutter)
        .frame(width: AppFont.pt(230))
        .frame(maxHeight: .infinity, alignment: .top)
        // System material, so macOS 27's restyled sidebars arrive on rebuild without a code change.
        .background(.bar)
    }

    // MARK: The page

    @ViewBuilder private var detail: some View {
        Group {
            if let article {
                StableScrollView {
                    HelpArticleView(article: article)
                        .padding(Space.page)
                        .readableColumn()
                }
            } else {
                EmptyStateView(symbol: "questionmark.circle",
                               title: "Nothing to show",
                               message: "No help page matches what you typed.")
            }
        }
        .faceTransition(article?.id ?? "")
        .fillsPane()
        .pageGround()
    }
}

/// One rendered help page. Text is selectable throughout — somebody explaining a problem to
/// somebody else needs to be able to copy the sentence rather than retype it.
struct HelpArticleView: View {
    let article: HelpArticle

    var body: some View {
        VStack(alignment: .leading, spacing: Space.block) {
            Text(article.title)
                .sectionHeading()

            ForEach(Array(article.blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func view(for block: HelpBlock) -> some View {
        switch block {
        case .heading(let text):
            Text(LocalizedStringKey(text))
                .font(.appTitle3)
                .padding(.top, Space.row)

        case .paragraph(let text):
            Text(LocalizedStringKey(text))
                .font(.appBody)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: Space.row) {
                Text(verbatim: "•")
                    .font(.appBody)
                    .foregroundStyle(Theme.textSecondary)
                    // The dot is punctuation. Spoken aloud it is noise, and the sentence beside it
                    // reads perfectly well without it.
                    .accessibilityHidden(true)
                Text(LocalizedStringKey(text))
                    .font(.appBody)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .padding(.leading, Space.hairline)

        case .note(let text):
            HStack(alignment: .firstTextBaseline, spacing: Space.row) {
                Image(systemName: "info.circle")
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
                Text(LocalizedStringKey(text))
                    .font(.appCallout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
            .softCard(cornerRadius: Radius.control)
        }
    }
}

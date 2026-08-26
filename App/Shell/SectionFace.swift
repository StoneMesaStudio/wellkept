import SwiftUI
import WellkeptCore

//  SectionFace.swift
//  Wellkept — App/Shell
//
//  The face every section wears. Three parts, in this order, on all seven screens:
//
//    1. **A plain sentence** saying what the button will do. It is the one thing a person cannot
//       work out from the screen, and an app that reads your disk owes you that sentence.
//    2. **One button**, carrying the section's own verb.
//    3. **Results**, worst first, each row saying why it was flagged and carrying its own verb.
//
//  A labelled **Options** disclosure sits between 2 and 3 — and is **absent** on a section that has
//  no options. Not disabled, not an empty panel: absent. An options control that opens onto nothing
//  teaches the user that the app's disclosures are not worth pressing.
//
//  One face rather than seven means a change to how a section reads is one edit, and no screen can
//  quietly invent a second way of saying "needs attention".

struct SectionFace<Options: View>: View {
    let section: SectionID
    /// Greys the verb and puts one line under it. Every section in the shell is `true`.
    var comingSoon = true
    /// The label on the disclosure — "Options". **`nil` means no disclosure is drawn at all.**
    var optionsLabel: String?
    @ViewBuilder var options: Options

    @Environment(AppState.self) private var app

    private var record: CheckRecord? { app.records[section] }
    private var found: [Finding] { app.findings(in: section) }

    var body: some View {
        StableScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                SectionHeader(section: section, record: record)

                // One line, and only on a section whose answer this permission actually shortens.
                // It draws nothing when the permission is on, and nothing on a section the switch
                // does not affect — so there is nothing to dismiss and nothing to nag with.
                PermissionNoticeLine(section: section)

                VStack(alignment: .leading, spacing: Space.block) {
                    Text(section.sentence)
                        .font(.appBody)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: Space.gutter) {
                        Button(section.verb) { }
                            .buttonStyle(.appProminent)
                            .controlSize(.large)
                            .disabled(comingSoon)
                        Spacer(minLength: 0)
                    }

                    if comingSoon { ComingSoonNote() }
                }

                // At most one disclosure per view, and it says what is behind it.
                if let optionsLabel {
                    LabelledDisclosure(optionsLabel, isExpanded: app.optionsOpen(section)) {
                        options
                    }
                }

                results
            }
            .padding(Space.page)
            .readableColumn()
        }
        .fillsPane()
    }

    @ViewBuilder private var results: some View {
        if found.isEmpty {
            // Say why it is empty. "Nothing here" with no reason is indistinguishable from a
            // screen that failed to load.
            InlineEmptyNote(symbol: record == nil ? "questionmark.circle" : "checkmark.circle",
                            text: record == nil
                                ? "Not checked yet, so there is nothing to show."
                                : "Nothing to show — the last check found nothing worth telling you about.")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(found.enumerated()), id: \.element.id) { index, finding in
                    FindingRow(finding: finding, index: index, showSection: false)
                }
            }
        }
    }
}

/// The no-options case, which is every section in the shell.
extension SectionFace where Options == EmptyView {
    init(_ section: SectionID, comingSoon: Bool = true) {
        self.init(section: section, comingSoon: comingSoon, optionsLabel: nil) { EmptyView() }
    }
}

// MARK: - The heading

/// The section's name, its status, and when it last ran.
struct SectionHeader: View {
    let section: SectionID
    let record: CheckRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.hairline) {
            HStack(alignment: .firstTextBaseline, spacing: Space.gutter) {
                // One of the three places bronze appears.
                Text(section.title).sectionHeading()
                StatusChip(status: record?.status ?? .notChecked)
            }
            if let record {
                Text(record.complete
                     ? "Checked \(ShellFormat.when(record.ranAt))."
                     : "Checked \(ShellFormat.when(record.ranAt)) — but it could not see everything.")
                    .font(.appCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

// MARK: - The line under a greyed verb

/// One line, under the button, on a section whose engine is not written yet.
///
/// It exists because the alternative was a screen saying "not built yet" instead of showing its
/// face — and a face you can look at is what settles an argument about a screen months before the
/// screen can do anything.
struct ComingSoonNote: View {
    var body: some View {
        Text("Not built yet — this button will work in a later version.")
            .font(.appCallout)
            .foregroundStyle(Theme.textSecondary)
    }
}

// MARK: - One result

/// A row in a results list. Used by every section face and by Overview.
///
/// `showSection` puts the section's name on the row — Overview needs it, because a row there could
/// have come from any of six places; a section's own face does not, because the heading above
/// already said it.
struct FindingRow: View {
    let finding: Finding
    let index: Int
    var showSection = false
    /// What the row does when clicked. Overview passes "go to that section"; a section face
    /// passes nothing, because the row is already where it belongs.
    var onOpen: (() -> Void)?

    var body: some View {
        let content = HStack(alignment: .top, spacing: Space.gutter) {
            VStack(alignment: .leading, spacing: Space.hairline) {
                HStack(spacing: Space.row) {
                    SeverityTag(severity: finding.severity)
                    Text(finding.title)
                        .font(.appHeadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Text(showSection ? "\(finding.section.title) · \(finding.reason)" : finding.reason)
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: Space.row)

            VStack(alignment: .trailing, spacing: Space.row) {
                if let measure = finding.measure {
                    Figure(measure, size: 15, weight: .semibold)
                }
                if let verb = finding.verb {
                    Button(verb) { }
                        .buttonStyle(.app)
                        .controlSize(.small)
                        // Greyed for the same reason the section's own verb is: nothing acts on
                        // this Mac yet. The verb is shown rather than removed because a control
                        // that comes and goes with the build is a control nobody can rely on.
                        .disabled(true)
                }
            }
        }
        .appRow(index)

        if let onOpen {
            Button(action: onOpen) { content }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens \(finding.section.title).")
        } else {
            content
        }
    }
}

/// The severity, in a word.
///
/// ⚠️ **`.information` gets no tag at all.** A revealed fact is not a fault, and a row reading
/// "Information · Downloads — 1,340 files" says nothing the row does not already say. Tagging
/// everything is how a tag stops meaning anything.
struct SeverityTag: View {
    let severity: Severity

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    var body: some View {
        if severity != .information {
            let c = palette.color(for: severity)
            Text(severity.label.uppercased())
                .font(.appCaption2.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(c)
                .lineLimit(1)
                .padding(.horizontal, AppFont.pt(6))
                .padding(.vertical, AppFont.pt(2))
                .background(c.opacity(0.10), in: Radius.shape(AppFont.pt(Radius.small)))
                .overlay(differentiate
                         ? Radius.shape(AppFont.pt(Radius.small))
                            .strokeBorder(c.opacity(0.7), lineWidth: Hairline.thin)
                         : nil)
                // ⚠️ **Not hidden.** This is a word rather than a coloured dot, and severity is
                // the one thing on the row a screen reader must not lose. The label is respelled
                // in sentence case because some voices spell an all-caps word out letter by letter.
                .accessibilityLabel(severity.label)
        }
    }
}

// MARK: - Dates

/// How the app writes a date. One place, so no two screens format the same instant differently.
enum ShellFormat {
    /// "26 Aug 2026 at 2:32 PM", in the reader's own region — the separators, the order and the
    /// clock all come from `Locale.current` rather than from a format string written here.
    static func when(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

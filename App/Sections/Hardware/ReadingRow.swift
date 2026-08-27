import AppKit
import SwiftUI
import WellkeptCore

//  ReadingRow.swift
//  Wellkept — App/Sections/Hardware
//
//  **One row of the five, and the label-above-value pairs behind Options.**
//
//  ## Three facts on the row, and the fourth only when it is needed
//
//  A row carries the topic and its status, the sentence, and the figure. That is the whole panel
//  on a Mac with nothing wrong, and it is deliberately short: five rows that each need a paragraph
//  read as five problems.
//
//  The **reason** is the fourth line and appears only where the reader supplied one — which is
//  every flagged row, always. A flagged row with no reason is an accusation, and the reason is what
//  lets a person disagree with us. It is never behind a disclosure.
//
//  **What the reading means** — `HardwareTopic.explanation` — lives behind Options rather than on
//  the row. It is explanation, not clutter, and it is wanted; it is simply wanted once, in the
//  place a person goes when the sentence on the row was not enough. Printing it on every row would
//  put five sentences of theory above the five sentences of answer.
//
//  ## ⚠️ Never a two-column table
//
//  The label sits **above** the value, everywhere, on the row and in the details alike. A table
//  with a fixed left column looks tidy at 100% text and comes apart at 200%: the labels wrap to
//  four lines and the numbers drift away from the thing they describe. This is cheap to build in
//  and near-impossible to retrofit, so it is built in.

// MARK: - One of the five rows

struct ReadingRow: View {
    let reading: Reading
    let index: Int

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.hairline) {
            HStack(alignment: .firstTextBaseline, spacing: Space.row) {
                Text(reading.topic.label)
                    .font(.appHeadline)
                Spacer(minLength: Space.row)
                StatusChip(status: reading.status)
            }

            // The answer. A row we could not read carries the one house sentence — "Drive wear —
            // this Mac does not report it." — in supporting ink rather than in a colour, because
            // "we did not look" is the absence of an answer and a hue would make it read as one.
            Text(reading.headline)
                .font(.appBody)
                .foregroundStyle(headlineInk)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)

            // The figure, under its own label rather than beside it. `Reading.init` guarantees
            // there is none on a row we could not read, which is the rule against reporting a zero
            // we never measured, enforced somewhere other than here.
            if let measure = reading.measure {
                Figure(measure, size: 20, weight: .semibold)
                    .foregroundStyle(headlineInk)
                    .padding(.top, 2)
            }

            if let reason = reading.reason {
                Text(reason)
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 2)
            }

            // ⚠️ Only a row that was **refused** ever gets a button, and only when something can
            // actually fix it. `Reading.init` drops a remedy on any other kind of row, so there is
            // no arrangement of this view that can offer a person a button that does nothing.
            // Kernel panics are the case that proves it: readable only by an administrator account,
            // by account type rather than by any privacy setting, so that row says so and offers
            // nothing, because there is nothing honest to offer.
            if let remedy = reading.remedy {
                Button(remedy.title) { open(remedy) }
                    .buttonStyle(.app)
                    .controlSize(.small)
                    .padding(.top, Space.hairline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appRow(index)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(reading.topic.label), \(reading.status.label)")
    }

    /// The answer's own colour, where there is something wrong to say.
    ///
    /// `.information` resolves to `.primary` and not to a hue — a revealed fact is not a fault. The
    /// three semantic colours are exempt from the colour dial at every level, so "this drive is
    /// failing" survives a person turning the app's colour down, which is precisely the sentence
    /// that has to.
    private var headlineInk: Color {
        if reading.unreadable != nil { return Theme.textSecondary }
        return reading.severity >= .attention ? palette.color(for: reading.severity) : Color.primary
    }

    @MainActor private func open(_ remedy: Remedy) {
        guard let raw = remedy.settingsPane, let pane = SystemSettingsPane(rawValue: raw) else { return }
        pane.open()
    }
}

// MARK: - The details behind Options

/// One topic's worth of "everything more exact", under its own heading.
struct ReadingDetails: View {
    let reading: Reading

    var body: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            Text(reading.topic.label)
                .font(.appHeadline)

            // What the reading means. One sentence, once, where somebody has gone looking for it.
            Text(reading.topic.explanation)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if reading.details.isEmpty {
                InlineEmptyNote(symbol: "tray",
                                text: "Nothing more exact than the line above — this Mac reports "
                                    + "no further detail here.")
            } else {
                DetailPairGrid(pairs: reading.details)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Label-above-value pairs, reflowing into as many columns as the width allows.
///
/// ⚠️ **Adaptive columns, not a fixed grid.** At 100% text this lands as two or three columns and
/// reads like a specification sheet; at 200% it collapses to one and stays readable. A fixed
/// `Grid` with two columns would keep both at every size, which is where a 200% layout puts three
/// words per line in each of them.
struct DetailPairGrid: View {
    let pairs: [DetailPair]

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: AppFont.pt(210)), spacing: Space.gutter, alignment: .topLeading)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Space.block) {
            ForEach(pairs) { pair in
                DetailPairCell(pair: pair)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One pair. The label is small and quiet; the value is the thing being read.
struct DetailPairCell: View {
    let pair: DetailPair
    /// A cell the user can click to put the value on the clipboard — the serial number, which is
    /// the one value in this app somebody is going to want to type into a form or read down a
    /// telephone.
    var copyable = false

    @State private var copied = false

    var body: some View {
        if copyable {
            Button(action: copy) { cell }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Copies the \(pair.label.lowercased()) to the clipboard.")
                .help("Click to copy")
        } else {
            cell
        }
    }

    private var cell: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(pair.label)
                .font(.appCaption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: Space.row) {
                Text(pair.value)
                    .font(.appCallout)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    // Selectable, so a sentence can be pasted into an email without retyping it.
                    .textSelection(.enabled)
                if copyable {
                    Text(copied ? "Copied" : "Copy")
                        .font(.appCaption2.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @MainActor private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pair.value, forType: .string)
        copied = true
        // The word goes back after a moment. A cell that says "Copied" for the rest of the session
        // stops being feedback and becomes a label — and the next click then looks like it failed.
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

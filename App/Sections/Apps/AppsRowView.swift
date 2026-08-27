import SwiftUI
import WellkeptCore

//  AppsRowView.swift
//  Wellkept — App/Sections/Apps
//
//  **One of the five rows, and the label-above-value pairs behind Options.**
//
//  The same shape as `ReadingRow` in Hardware and `SecurityRowView` in Security, and deliberately
//  so: a person who has learned one panel has learned all three. Topic and status, the sentence,
//  the figure, the reason.
//
//  ## ⚠️ What this row cannot do, and it is the section's whole ruling
//
//  **There is no colour here.** `AppsRow.severity` is a computed constant — `.information`, always,
//  with no argument that could raise it — so this file has nothing to paint amber with and no
//  branch that would want one. Without vulnerability data an old app is not dangerous, and a
//  version behind is not something wrong.
//
//  That is why the headline is drawn in `.primary` unconditionally, where the Security row picks a
//  hue from its severity. The only ink that is ever different is the supporting grey on a row we
//  could not read at all: "we did not look" is the absence of an answer, and a hue would make it
//  read as one.
//
//  ## The footnote
//
//  A row can carry one sentence underneath it that is not part of `AppsRow` — the Updates row's
//  account of exactly which app names left this Mac. It goes here rather than into the row's own
//  `reason` because it is a privacy disclosure about a thing that happened, not an explanation of
//  the answer, and it must never end up behind Options.

// MARK: - One of the five rows

struct AppsRowView<Content: View>: View {
    let row: AppsRow
    let index: Int

    /// A sentence drawn under the row, quieter than the reason. `nil` on four of the five.
    var footnote: String?

    /// Anything the row is a heading for — the crashes, the leftovers. Drawn under the row and
    /// **never behind a disclosure**: a flagged item whose content is hidden is an accusation the
    /// person cannot examine. `EmptyView` on the rows that head nothing.
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.hairline) {
            HStack(alignment: .firstTextBaseline, spacing: Space.row) {
                Text(row.topic.label)
                    .font(.appHeadline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.row)
                StatusChip(status: row.status)
            }

            Text(row.headline)
                .font(.appBody)
                // See the file header: never a hue. Grey only where there is no answer at all.
                .foregroundStyle(row.unreadable == nil ? Color.primary : Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)

            // ⚠️ `AppsRow.init` guarantees a row we could not read carries no figure — the rule
            // against reporting a zero nobody measured, enforced somewhere other than here.
            //
            // Never coloured. Every measure in this section is an inventory count: "31 apps",
            // "2 of 6", "21 days". A warning colour on the number of apps installed would say the
            // count is the thing that is wrong.
            if let measure = row.measure {
                Figure(measure, size: 20, weight: .semibold)
                    .padding(.top, 2)
            }

            if let reason = row.reason {
                Text(reason)
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 2)
            }

            if let footnote {
                Text(footnote)
                    .font(.appCaption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .padding(.top, Space.hairline)
            }

            // The list this row heads, where it heads one. Each of those views draws nothing at all
            // when it is empty, so a row with no crashes gets no gap and no "nothing here" note —
            // its own sentence already said so.
            content

            // ⚠️ Only a row that was refused, and could be un-refused, gets this button.
            // `AppsRow.init` drops a remedy on any other kind, so there is no arrangement of this
            // view that offers a door with no room behind it. On the measured Mac only the
            // leftovers row can ever carry one.
            if let remedy = row.remedy {
                Button(remedy.title) { open(remedy.settingsPane) }
                    .buttonStyle(.app)
                    .controlSize(.small)
                    .padding(.top, Space.hairline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appRow(index)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(row.topic.label), \(row.status.label)")
    }

    @MainActor private func open(_ raw: String?) {
        guard let raw, let pane = SystemSettingsPane(rawValue: raw) else { return }
        pane.open()
    }
}

/// The three rows that head nothing — macOS, Updates, and the installed row, whose list is a band
/// of its own further down the page.
extension AppsRowView where Content == EmptyView {
    init(row: AppsRow, index: Int, footnote: String? = nil) {
        self.init(row: row, index: index, footnote: footnote) { EmptyView() }
    }
}

// MARK: - A row that has not arrived yet

/// The placeholder for a row whose reader is still working.
///
/// ⚠️ **A real state that lasts about thirteen seconds**, eight of them the inventory. Without it
/// the panel would be one row and four holes, which reads as a screen that failed rather than one
/// still going. It says which row is coming and nothing about what it will contain — a placeholder
/// that guessed at a status would be a verdict from a check that had not run.
struct AppsRowPlaceholder: View {
    let topic: AppsTopic
    let index: Int
    /// True for the row being read at this moment. The others are simply queued.
    var active: Bool
    /// How far through, where the reader reports it. Only the inventory does.
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.hairline) {
            HStack(alignment: .firstTextBaseline, spacing: Space.row) {
                Text(topic.label)
                    .font(.appHeadline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.row)
                if active {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
            }

            Text(active ? (detail ?? "Reading this now…") : "Waiting its turn.")
                .font(.appBody)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appRow(index)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(topic.label), \(active ? "reading now" : "waiting")")
    }
}

// MARK: - The details behind Options

/// One topic's worth of "everything more exact", under its own heading.
struct AppsRowDetails: View {
    let row: AppsRow

    var body: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            Text(row.topic.label)
                .font(.appHeadline)
                .fixedSize(horizontal: false, vertical: true)

            // What the row means. One sentence, once, where somebody has gone looking for it.
            Text(row.topic.explanation)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if row.details.isEmpty {
                InlineEmptyNote(symbol: "tray",
                                text: "Nothing more exact than the line above — this Mac reports "
                                    + "no further detail here.")
            } else {
                DetailPairGrid(pairs: row.details)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The apps that stopped working

/// The crashes themselves, named, under the row that counts them.
///
/// ⚠️ **Empty is the ordinary answer and draws nothing.** 108 crash files on the measured Mac reduce
/// to zero real app crashes; the row's own sentence says so, and a "Nothing here" note underneath it
/// would say the same thing twice.
struct CrashList: View {
    let crashes: [CrashedApp]

    var body: some View {
        if !crashes.isEmpty {
            VStack(alignment: .leading, spacing: Space.row) {
                ForEach(crashes) { crash in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(crash.appName)
                            .font(.appCallout.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(crash.sentence)
                            .font(.appCallout)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Space.row)
        }
    }
}

// MARK: - What removed apps left behind

/// One block per removed app: what it was called, why we believe it is gone, where the files are,
/// and what they weigh.
///
/// ⚠️ **Never totalled.** There is no section-wide figure here and `Leftover` has no field for one.
/// Name-matching everything on the measured Mac produces 7.6 GB against about 350 MB genuinely
/// orphaned, because 95% of it belongs to software running right now. A single headline number
/// would be wrong by a factor of twenty, and it is exactly the number a cleaner puts in a big font.
///
/// ⚠️ **The reason is on the row, never behind a disclosure.** A flagged item with no reason is an
/// accusation, and this is the row where the accusation is most likely to be wrong.
struct LeftoverList: View {
    let leftovers: [Leftover]

    var body: some View {
        if !leftovers.isEmpty {
            VStack(alignment: .leading, spacing: Space.block) {
                ForEach(leftovers) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: Space.row) {
                            Text(item.appName)
                                .font(.appCallout.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: Space.row)
                            // Per item, and only where it was actually weighed. Never "0 bytes"
                            // for something a walk was refused part-way through.
                            if let size = item.sizeText {
                                Text(size)
                                    .font(.appCaption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }

                        Text(item.reason)
                            .font(.appCallout)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(item.paths, id: \.self) { path in
                            Text(path)
                                .font(.appCaption)
                                .foregroundStyle(Theme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // ⚠️ Said once, here, because the obvious next question is "so remove them" and
                // the honest answer is that this version cannot. Nothing in Wellkept deletes
                // anything, and the quarantine engine that would hold them for thirty days does not
                // exist yet. Promising a button that is not there is worse than not having one.
                Text("Wellkept is showing you these, not offering to remove them. Nothing in this "
                   + "app deletes anything.")
                    .font(.appCaption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Space.row)
        }
    }
}

import SwiftUI
import WellkeptCore

//  OverviewView.swift
//  Wellkept — App/Shell
//
//  The answer to "is my Mac OK?", as a sentence and a ranked list.
//
//  ## Three things this screen will not do
//
//  **It never gives a score.** A number out of 100 invites you to chase it, and a Mac with nothing
//  wrong would then be graded on how little it happened to have installed. The headline is a
//  sentence, and the sentence is the whole verdict.
//
//  **It never lists everything.** Six sections' worth of facts is a report, not an answer. This
//  screen carries only what needs a person; the facts live in the section that found them.
//
//  **It never says the Mac looks fine when it could not see everything.** A permission that
//  stopped a check from reading part of the disk changes the headline and puts a row at the top
//  naming what was missed. An app that reassures you on the strength of a partial look is worse
//  than an app that says nothing.

struct OverviewView: View {
    @Environment(AppState.self) private var app

    private var needsYou: [Finding] { app.needsYou }
    private var blind: [SectionID] { app.incompleteSections }
    private var everChecked: Bool { !app.records.isEmpty }
    private var isClean: Bool { everChecked && needsYou.isEmpty && blind.isEmpty }

    var body: some View {
        StableScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                headline

                VStack(alignment: .leading, spacing: Space.block) {
                    Text(SectionID.overview.sentence)
                        .font(.appBody)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: Space.gutter) {
                        Button(SectionID.overview.verb) { }
                            .buttonStyle(.appProminent)
                            .controlSize(.large)
                            .disabled(true)
                        Spacer(minLength: 0)
                    }

                    ComingSoonNote()
                }

                // The standing notice for a permission that is off: what is hidden, what it costs,
                // and the way to change it. It draws nothing at all when the permission is on,
                // which is what makes it a statement of fact rather than a nag.
                PermissionNoticeRow()

                list

                // Overview's one disclosure. On a clean Mac it starts open: "everything looks
                // fine" is only worth as much as the evidence behind it, and the evidence is this
                // list. Once the reader touches it, their choice sticks for the session.
                LabelledDisclosure("What was checked",
                                   isExpanded: app.whatWasChecked(default: isClean)) {
                    auditTrail
                }
            }
            .padding(Space.page)
            .readableColumn()
        }
        .fillsPane()
    }

    // MARK: The headline

    @ViewBuilder private var headline: some View {
        VStack(alignment: .leading, spacing: Space.hairline) {
            Text(headlineText).sectionHeading()
            if let last = app.lastCheckedAt {
                Text("Checked \(ShellFormat.when(last)).")
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
            }
            // A different fact from the permission notice below, and it belongs up here with the
            // verdict: this is about the RESULT being short, not about a switch being off. It shows
            // whenever a check saw part of the Mac, including the case where plenty else needs you
            // — the headline has only one sentence to spend, and it spends it on the worst news.
            if !blind.isEmpty, !needsYou.isEmpty {
                Text("\(Count.list(blind.map(\.title))) could not see everything, so this is not the whole picture.")
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The verdict, in one sentence.
    ///
    /// The order of these branches is the product: **blind beats clean**. A Mac with nothing wrong
    /// on the part we could see is not a Mac with nothing wrong, and the sentence has to say so
    /// before it says anything reassuring.
    private var headlineText: String {
        guard everChecked else { return "Nothing has been checked yet." }
        if needsYou.isEmpty && !blind.isEmpty {
            return "Everything we could see looks fine — but \(Count.list(blind.map(\.title))) couldn’t see everything."
        }
        if needsYou.isEmpty { return "Everything looks fine." }
        return needsYou.count == 1
            ? "One thing needs you."
            : "\(Count.spelled(needsYou.count).capitalizedFirst) things need you."
    }

    // MARK: The ranked list

    @ViewBuilder private var list: some View {
        if !everChecked {
            InlineEmptyNote(symbol: "questionmark.circle",
                            text: "Nothing has run yet, so there is nothing to rank.")
        } else if needsYou.isEmpty {
            InlineEmptyNote(symbol: "checkmark.circle",
                            text: "Nothing on this Mac needs you right now.")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(needsYou.enumerated()), id: \.element.id) { index, finding in
                    FindingRow(finding: finding, index: index, showSection: true) {
                        app.selection = finding.section
                    }
                }
            }
        }
    }

    // MARK: The audit trail

    /// All seven, and when each ran. The clean state's evidence, and the answer to "did it
    /// actually look at that?"
    private var auditTrail: some View {
        VStack(spacing: 0) {
            ForEach(Array(SectionID.allCases.enumerated()), id: \.element) { index, section in
                let record = app.records[section]
                HStack(alignment: .firstTextBaseline, spacing: Space.gutter) {
                    Text(section.title)
                        .font(.appCallout)
                        .lineLimit(1)
                    Spacer(minLength: Space.row)
                    if let record, !record.complete {
                        Text("saw part of this Mac")
                            .font(.appCaption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    StatusChip(status: record?.status ?? .notChecked)
                    Text(record.map { ShellFormat.when($0.ranAt) } ?? "—")
                        .font(.appCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                .appRow(index)
            }
        }
    }
}

// MARK: - Counting in words

/// Small numbers written out, and short lists joined.
///
/// A headline is a sentence, and a sentence says "Two things need you". Digits are for
/// measurements — "84.3 GB", "91%" — where the exact figure is the point. Past twelve the digits
/// win back, because "twenty-seven" in a headline is harder to read than 27.
enum Count {
    private static let words = ["zero", "one", "two", "three", "four", "five", "six",
                               "seven", "eight", "nine", "ten", "eleven", "twelve"]

    static func spelled(_ n: Int) -> String {
        n >= 0 && n < words.count ? words[n] : "\(n)"
    }

    /// "Storage" · "Storage and Apps" · "Storage, Apps and Security".
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        case 2: "\(items[0]) and \(items[1])"
        default: "\(items.dropLast().joined(separator: ", ")) and \(items[items.count - 1])"
        }
    }
}

extension String {
    /// Sentence case without touching the rest of the string — `capitalized` would turn
    /// "two things" into "Two Things".
    var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}

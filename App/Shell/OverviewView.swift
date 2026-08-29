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
//  than an app that says nothing. **A section that was never checked at all counts the same way** —
//  see `OverviewWords.headline`.
//
//  ## The button
//
//  `Check my Mac` runs all six sections in turn. The loop, the running order and the reason for
//  the order are in `RunEverything.swift`; the words are in `SweepWords`. While it runs, this
//  screen names the section being read and opens the audit trail so the rows land where a person
//  can watch them arrive. **No percentage and no time remaining** — the same law `Storage` keeps.

struct OverviewView: View {
    @Environment(AppState.self) private var app

    private var needsYou: [Finding] { app.needsYou }
    private var blind: [SectionID] { app.incompleteSections }
    private var unchecked: [SectionID] { app.uncheckedSections }
    private var everChecked: Bool { !app.records.isEmpty }
    private var isClean: Bool { everChecked && needsYou.isEmpty && blind.isEmpty && unchecked.isEmpty }

    private var sweep: Sweep { app.sweep }
    /// Demo mode is a picture of a Mac, not this Mac, so nothing on it may start a real check.
    private var live: Bool { !app.demoMode }
    /// True while a real sweep is in flight. Never in demo mode, where nothing runs at all.
    private var running: Bool { live && sweep.isRunning }

    var body: some View {
        StableScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                headline

                checkControl

                // The standing notice for a permission that is off: what is hidden, what it costs,
                // and the way to change it. It draws nothing at all when the permission is on,
                // which is what makes it a statement of fact rather than a nag.
                PermissionNoticeRow()

                list

                // Overview's one disclosure. On a clean Mac it starts open: "everything looks
                // fine" is only worth as much as the evidence behind it, and the evidence is this
                // list. It also starts open **while a sweep is running**, because that is the one
                // moment the list is live and watching it arrive is the whole answer to "is this
                // thing doing anything". Once the reader touches it, their choice sticks for the
                // session.
                LabelledDisclosure("What was checked",
                                   isExpanded: app.whatWasChecked(default: isClean || running)) {
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
            // The two shortfalls the headline had no room for. A headline has one sentence and it
            // spends it on the worst news; these are the facts that would otherwise be lost —
            // and they are two different facts. "Could not see everything" means we looked and a
            // permission stopped us. "Has not been checked" means we never looked.
            ForEach(shortfallLines, id: \.self) { line in
                Text(line)
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var headlineText: String {
        OverviewWords.headline(needsYou: needsYou.count,
                               blind: blind.map(\.title),
                               unchecked: unchecked.map(\.title),
                               everChecked: everChecked)
    }

    /// Whatever the headline did not manage to say.
    ///
    /// ⚠️ **The unchecked line is silent while a sweep is running**, and only that line. Mid-sweep
    /// it would read "Security hasn't been checked" directly above "Reading Security", which is a
    /// sentence that was true when the run started and is being falsified as it is read. The live
    /// audit trail underneath is the better answer to the same question, and it is open by default
    /// exactly then. The permission line has no such problem: being blocked does not resolve itself
    /// while you watch.
    private var shortfallLines: [String] {
        guard everChecked else { return [] }
        var lines: [String] = []
        if !blind.isEmpty, !needsYou.isEmpty {
            lines.append(OverviewWords.blindNote(blind.map(\.title)))
        }
        if !running, !unchecked.isEmpty, !needsYou.isEmpty || !blind.isEmpty {
            lines.append(OverviewWords.uncheckedNote(unchecked.map(\.title)))
        }
        return lines
    }

    // MARK: The sentence, the button, and what it is doing

    /// The section template, on Overview: a sentence saying what the button will do, the button,
    /// and — while it runs — the section being read.
    private var checkControl: some View {
        VStack(alignment: .leading, spacing: Space.block) {
            Text(SectionID.overview.sentence)
                .font(.appBody)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.gutter) {
                Button(running ? SweepWords.running : SectionID.overview.verb) {
                    app.startEverything()
                }
                .buttonStyle(.appProminent)
                .controlSize(.large)
                .disabled(!live || sweep.isRunning)

                if running {
                    Button(SweepWords.stop) { app.stopEverything() }
                        .buttonStyle(.app)
                        .controlSize(.regular)
                        .disabled(sweep.stopRequested)
                }
                Spacer(minLength: 0)
            }

            if running {
                inFlight
            } else if sweep.wasStopped {
                Text(SweepWords.stopped)
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !running { shortfalls }

            // ⚠️ Said once, on the screen it is true of. Overview is the only screen that can
            // honestly describe what six checks cost, and it is the screen where somebody presses
            // a button and then waits half a minute wondering whether they should have.
            Text(SweepWords.whatThePressDoes)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(SweepWords.onlyOnAPress)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// **Which section is being read, and nothing that was not measured.**
    ///
    /// ⛔ No percentage and no time remaining — see `ScanPolicy.Running.whyThereIsNoEstimate` and
    /// the header of `RunEverything.swift`. "Section 3 of 6" is a count of sections, which is a
    /// fact; it is the same device every section face already uses for its own stages.
    private var inFlight: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.gutter) {
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                if let current = sweep.current {
                    Text(SweepWords.reading(current))
                        .font(.appCallout)
                        .foregroundStyle(Theme.textSecondary)
                    if let position = sweep.position {
                        Text(SweepWords.position(position))
                            .font(.appCaption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    // The running section's own stage sentence, borrowed rather than rewritten.
                    // Security says "reading what macOS has already found"; there is no better
                    // sentence to invent here, and inventing one would give the app two.
                    if let stage = stageSentence(for: current) {
                        Text(stage)
                            .font(.appCaption)
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if sweep.stopRequested {
                    Text(SweepWords.stopping)
                        .font(.appCaption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .appAnimation(Motion.chrome, value: sweep.current)
    }

    /// What the running section says about itself. `nil` for Hardware, which has no stages — it is
    /// a single sweep and it is over before a stage could be read.
    private func stageSentence(for section: SectionID) -> String? {
        switch section {
        case .security: app.security.stage?.sentence
        case .apps:     app.apps.stage?.sentence
        case .storage:  app.storage.stage?.sentence
        case .changes:  app.changes.stage?.sentence
        case .backup:   app.backup.stage?.sentence
        default:        nil
        }
    }

    /// **What the last sweep did not check, and why.** One row each, and each opens the section
    /// that can do something about it — a person told that Apps was skipped for want of an answer
    /// needs the place where the answer is given.
    @ViewBuilder private var shortfalls: some View {
        let items = sweep.shortfalls
        if !items.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.section) { index, item in
                    Button { app.selection = item.section } label: {
                        VStack(alignment: .leading, spacing: Space.hairline) {
                            Text(OverviewWords.notCheckedTitle(item.section.title))
                                .font(.appHeadline)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                            Text(item.reason)
                                .font(.appCallout)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appRow(index)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Opens \(item.section.title).")
                }
            }
        }
    }

    // MARK: The ranked list

    @ViewBuilder private var list: some View {
        if !everChecked {
            InlineEmptyNote(symbol: "questionmark.circle",
                            text: "Nothing has run yet, so there is nothing to rank.")
        } else if needsYou.isEmpty {
            InlineEmptyNote(symbol: "checkmark.circle",
                            text: OverviewWords.nothingNeedsYou(anythingUnchecked: !unchecked.isEmpty))
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

    /// All seven, and when each ran. The clean state's evidence, the answer to "did it actually
    /// look at that?", and — while a sweep is running — the live picture of what has come back.
    private var auditTrail: some View {
        VStack(spacing: 0) {
            ForEach(Array(SectionID.allCases.enumerated()), id: \.element) { index, section in
                let record = app.records[section]
                let step = live ? sweep.step(section) : nil
                HStack(alignment: .firstTextBaseline, spacing: Space.gutter) {
                    Text(section.title)
                        .font(.appCallout)
                        .lineLimit(1)
                    Spacer(minLength: Space.row)
                    // The sweep's word for this row, where it has one, and the permission's word
                    // otherwise. The sweep wins because it is about this run: "waiting" while a
                    // check is queued is more use than last week's partial read.
                    if let note = step?.short ?? (record.map { !$0.complete } == true
                                                  ? "saw part of this Mac" : nil) {
                        Text(note)
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

// MARK: - Overview's words

/// **The verdict, in one sentence, and the sentences that qualify it.**
///
/// Out of the view so they can be tested. Every one of these has a rule behind it that a reader of
/// the view would have to reconstruct from the branch order, and a rule that lives only in a branch
/// order is a rule that gets reordered.
enum OverviewWords {

    /// The headline.
    ///
    /// ⚠️ **The branch order is the product.** Bad news beats missing news beats good news:
    ///
    ///  1. Nothing has run — say so, and reassure nobody.
    ///  2. Something needs you — that is the whole sentence; the shortfalls go underneath.
    ///  3. We looked and were blocked — "everything we could see", never "everything".
    ///  4. We never looked — same rule, different reason, and it must not be silently folded into
    ///     the clean sentence. A Mac whose Storage has never been scanned is not a Mac with nothing
    ///     wrong with its storage.
    ///  5. Only then, "Everything looks fine."
    static func headline(needsYou: Int,
                         blind: [String],
                         unchecked: [String],
                         everChecked: Bool) -> String {
        guard everChecked else { return "Nothing has been checked yet." }
        if needsYou > 0 {
            return needsYou == 1
                ? "One thing needs you."
                : "\(Count.spelled(needsYou).capitalizedFirst) things need you."
        }
        if !blind.isEmpty {
            return "Everything we could see looks fine — but \(Count.list(blind)) couldn’t see everything."
        }
        if !unchecked.isEmpty {
            return "Everything checked looks fine — but \(Count.list(unchecked)) \(Count.hasNot(unchecked.count)) been checked."
        }
        return "Everything looks fine."
    }

    /// Said under the headline when the headline was spent on something worse.
    static func blindNote(_ sections: [String]) -> String {
        "\(Count.list(sections)) could not see everything, so this is not the whole picture."
    }

    /// The other shortfall. Deliberately a different sentence from `blindNote` — being refused and
    /// never being asked are not the same thing, and one wording for both would tell somebody a
    /// permission is missing when nothing of the sort is true.
    static func uncheckedNote(_ sections: [String]) -> String {
        "\(Count.list(sections)) \(Count.hasNot(sections.count)) been checked."
    }

    /// The heading on a row saying a sweep left a section alone.
    static func notCheckedTitle(_ section: String) -> String { "\(section) was not checked" }

    /// The empty state under a clean headline. It has to stay true when part of the Mac was never
    /// looked at — "nothing needs you" would be a claim about sections nobody read.
    static func nothingNeedsYou(anythingUnchecked: Bool) -> String {
        anythingUnchecked
            ? "Nothing that has been checked needs you right now."
            : "Nothing on this Mac needs you right now."
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

    /// Subject–verb agreement for a list this app builds at runtime. One section hasn't; two
    /// haven't. Getting this wrong is the sort of thing that makes an app read as machine-written.
    static func hasNot(_ count: Int) -> String { count == 1 ? "hasn’t" : "haven’t" }
}

extension String {
    /// Sentence case without touching the rest of the string — `capitalized` would turn
    /// "two things" into "Two Things".
    var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}

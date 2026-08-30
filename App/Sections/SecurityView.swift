import SwiftUI
import WellkeptCore

//  SecurityView.swift
//  Wellkept — App/Sections
//
//  **"Am I safe?"** — this Mac's protections, what can watch you, what starts on its own, what is
//  in your browsers, what can reach this machine, and what macOS has already found.
//
//  Reporting, not fixing. Where something is off, the row's button opens the System Settings pane
//  that owns it; the app never reaches in and flips a switch. A utility that silently changes
//  security settings is the category this one exists not to be.
//
//  ## The shape, top to bottom
//
//  1. The heading, its status, and when it last ran.
//  2. The sentence and the one button — plus the live state while it is reading.
//  3. **The section's own summary sentence**, which carries its scope and its window.
//  4. **What is protecting this Mac** — inventory, on its own card, visibly separate, never a
//     verdict.
//  5. **The six rows, in fixed order and never sorted**: Protections · Camera, microphone, screen
//     and control · What starts on its own · Browser extensions · What can reach this Mac · What
//     macOS has already found. Every row every time, even when everything is fine.
//  6. **Options** — everything more exact, and the full list of who holds which permission.
//
//  ## ⚠️ Three sentences this screen may never say
//
//  - **"Safe."** Not as a verdict, not anywhere. Wellkept looks when you press the button and does
//    not watch. A word that implies live protection is a promise the app cannot keep, and somebody
//    would reasonably rely on it.
//  - **"Good", on its own.** Every clean answer carries what was looked at and how far back:
//    *"The protections we can see are on, and macOS found nothing in the last 12 days."* That
//    sentence is `SecurityReport.summary`, and it is never rewritten here.
//  - **A number nobody measured.** The window comes from what `OSLogStore` actually reached back
//    to on this run. Where it could not be measured, the sentence says so instead of printing 14.
//
//  ## ⚠️ This section does not run on launch, and nothing here may start it
//
//  The log read alone is about six seconds — the slowest read in the app. So Security runs on a
//  press, and while it runs the panel fills in row by row rather than sitting frozen behind a
//  spinner. There is no scan button of any kind: a malware scan that found something would have
//  nowhere to put it until quarantine exists, which is the decision of 2026-08-27 and not a
//  gap waiting to be filled in.

struct SecurityView: View {
    @Environment(AppState.self) private var app

    private var model: SecurityModel { app.security }

    /// What is drawn. In demo mode this is an invented Mac and **nothing has been read from this
    /// one** — which is the promise the bar across the top of the window makes on every screen.
    private var answer: SecurityAnswer? {
        app.demoMode ? DemoData.security(app.demoMachine) : model.answer
    }

    /// The section's own line, taken from the report it describes so the chip and the rows cannot
    /// disagree.
    private var record: CheckRecord? { answer?.report.record ?? app.records[.security] }

    /// Demo mode is a picture of a Mac, not this Mac, so nothing on it may start a real check.
    private var live: Bool { !app.demoMode }

    /// True while a real run is in flight. Never in demo mode, where nothing runs at all.
    private var reading: Bool { live && model.isChecking }

    var body: some View {
        StableScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                SectionHeader(section: .security, record: record)

                // ⚠️ Security is the section Full Disk Access actually costs something in: without
                // it, the camera / microphone / screen row is empty rather than short. The line
                // draws nothing once the grant is on.
                PermissionNoticeLine(section: .security)

                checkControl

                if reading {
                    inFlight
                } else if let answer {
                    summary(answer)
                    ProtectionsBlockView(block: answer.report.block)
                    rows(answer)
                    options(answer)
                } else {
                    notReadYet
                }
            }
            .padding(Space.page)
            .readableColumn()
        }
        .fillsPane()
    }

    // MARK: The sentence and the button

    private var checkControl: some View {
        VStack(alignment: .leading, spacing: Space.block) {
            Text(SectionID.security.sentence)
                .font(.appBody)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.gutter) {
                Button(SectionID.security.verb) {
                    Task { await app.runSecurityCheck() }
                }
                .buttonStyle(.appProminent)
                .controlSize(.large)
                .disabled(!live || model.isChecking)

                if reading, let stage = model.stage {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(stage.sentence)
                            .font(.appCallout)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Step \(stage.step) of \(SecurityModel.Stage.count)")
                            .font(.appCaption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .appAnimation(Motion.chrome, value: model.stage)

            // ⚠️ Said once, on the screen it is true of, and it is a different sentence from
            // Hardware's. Hardware reads on launch; this one never does, and a person who notices
            // that Security is blank when they open the app deserves to know it is deliberate.
            Text("Wellkept reads this only when you press the button — never when the app opens and "
                 + "never on its own. It takes a few seconds, it looks at settings and at macOS's "
                 + "own records, and it changes nothing.")
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: The summary sentence

    /// **The section's answer, in one line, and it never stands alone.**
    ///
    /// It comes from `SecurityReport.summary`, which is where the scope and the measured window are
    /// welded to the word "Good". Rewriting it here is how the two would come apart.
    private func summary(_ answer: SecurityAnswer) -> some View {
        Text(answer.report.summary)
            .font(.appTitle3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isSummaryElement)
    }

    // MARK: While it is reading

    /// The live state. **A real one, and it lasts about seven seconds.**
    ///
    /// The block appears as soon as the first reader hands it over, and each row replaces its own
    /// placeholder as it lands. The alternative — a spinner over a blank panel for seven seconds —
    /// is indistinguishable from an app that has stopped.
    private var inFlight: some View {
        VStack(alignment: .leading, spacing: Space.section) {
            if let block = model.arrivedBlock {
                ProtectionsBlockView(block: block, stillReading: true)
            }

            VStack(spacing: 0) {
                ForEach(Array(SecurityTopic.allCases.enumerated()), id: \.element) { index, topic in
                    if let row = model.arrived.first(where: { $0.topic == topic }) {
                        SecurityRowView(row: row, index: index, block: model.arrivedBlock)
                    } else {
                        SecurityRowPlaceholder(topic: topic,
                                               index: index,
                                               active: model.stage?.topic == topic)
                    }
                }
            }
        }
    }

    // MARK: The six rows

    private func rows(_ answer: SecurityAnswer) -> some View {
        // ⚠️ `report.rows` is already in `SecurityTopic` order, put there by `SecurityReport.init`.
        // It is never sorted here, and it is never filtered.
        VStack(spacing: 0) {
            ForEach(Array(answer.report.rows.enumerated()), id: \.element.id) { index, row in
                SecurityRowView(row: row, index: index, block: answer.report.block)
            }
        }
    }

    // MARK: Options

    /// **One disclosure on this screen, and it says what is behind it.**
    ///
    /// Its open state lives in `AppState` rather than in a `@State` here, so a ⌘+ press does not
    /// collapse a panel somebody had just opened.
    ///
    /// It sits **after** the rows: everything in it is a more exact version of something in the
    /// panel above, and a disclosure that opens above the thing it details makes the reader scroll
    /// back up to use it.
    private func options(_ answer: SecurityAnswer) -> some View {
        LabelledDisclosure("Options", isExpanded: app.optionsOpen(.security)) {
            VStack(alignment: .leading, spacing: Space.section) {
                ForEach(answer.report.rows) { row in
                    VStack(alignment: .leading, spacing: Space.block) {
                        SecurityRowDetails(row: row)
                        // The list of who holds what. It lives here rather than on the row because
                        // the row's job is three facts and a sentence; this is the exact version.
                        // Absent entirely when the row was refused — `SecurityAnswer.grants` is
                        // empty by construction in that case, and a short list beside a refusal is
                        // the "we checked and found almost nothing" sentence this section promised
                        // never to say.
                        if row.topic == .whoCanWatch, row.unreadable == nil {
                            GrantList(answer: answer)
                        }
                    }
                }
                whatWasRead(answer)
            }
            .padding(.top, Space.row)
        }
    }

    /// The section's own audit trail: when it ran, how far back it could see, whether it saw
    /// everything, and what it did not.
    ///
    /// The developer asked for this on a clean Overview — a check that says "nothing is wrong" is worth
    /// exactly as much as the list of what it actually looked at. The same argument holds one level
    /// down, and here it costs nothing.
    private func whatWasRead(_ answer: SecurityAnswer) -> some View {
        VStack(alignment: .leading, spacing: Space.row) {
            Text("This check")
                .font(.appHeadline)

            DetailPairGrid(pairs: auditPairs(answer))

            ForEach(answer.report.unreadableTopics, id: \.topic) { item in
                Text(item.why.sentence(about: item.topic.label))
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func auditPairs(_ answer: SecurityAnswer) -> [DetailPair] {
        let report = answer.report
        return [
            DetailPair("Ran at", ShortDate.stamp(report.ranAt)),
            DetailPair("Rows read", "\(report.rows.count) of \(SecurityTopic.allCases.count)"),
            // ⚠️ Measured, never assumed. `windowClause` handles a window that could not be
            // measured honestly; there is no fallback 14 anywhere in this section.
            DetailPair("How far back macOS's records reach",
                       report.measuredDays.map { $0 == 1 ? "1 day" : "\($0) days" }
                           ?? "Could not be measured on this run."),
            DetailPair("Saw everything it looked for",
                       report.complete
                           ? "Yes"
                           : "No — something on this Mac refused to be read, and the rows above say which."),
            DetailPair("What it changed", "Nothing. Every reading here is a look, not a touch."),
        ]
    }

    // MARK: Nothing read yet

    /// ⚠️ **The ordinary state, not an edge case.** Security never runs by itself, so this is what
    /// the screen looks like on every launch until somebody presses the button.
    private var notReadYet: some View {
        VStack(alignment: .leading, spacing: Space.block) {
            EmptyStateView(
                symbol: "lock.shield",
                title: "Nothing has been checked yet",
                message: "Press \(SectionID.security.verb) and Wellkept will read this Mac's "
                       + "protections, which apps can use the camera, the microphone and the "
                       + "screen, what starts on its own, what is in your browsers, what can reach "
                       + "this machine, and what macOS's own scanners have already found. It takes "
                       + "a few seconds and it changes nothing.",
                greedy: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

import SwiftUI
import WellkeptCore

//  AppsView.swift
//  Wellkept — App/Sections
//
//  **"What's installed, and is it current?"** — every app, where it came from, who signed it, and
//  whether a newer version exists.
//
//  ## The shape, top to bottom
//
//   1. The heading, its status, and when it last ran.
//   2. The sentence and the one button — plus the live state while it is reading.
//   3. **The consent question**, on the first press and nowhere else.
//   4. The section's own summary sentence, which carries its coverage.
//   5. **What is installed** — inventory, on its own card, visibly separate, never a verdict.
//   6. **The five rows, in fixed order and never sorted**: Everything installed · macOS · Updates ·
//      Apps that stopped working · Removed apps that left things behind. Every row every time.
//   7. **Every app on this Mac** — the searchable list, which is the section's actual content.
//   8. **Options** — everything more exact, per row.
//
//  ## ⚠️ Three things this screen may never do
//
//  - **Go amber.** `AppsRow.severity` is a computed constant and `AppsReport` builds its Overview
//    row with a literal `.information`. Without vulnerability data an old app is not dangerous, and
//    a version behind is not something wrong. The section is `Good` or `Not checked`, and nothing
//    else is reachable.
//  - **Print a count without its denominator.** Every sentence about updates comes from
//    `UpdateTally`, whose only initialiser takes the coverage. "4 apps are out of date" hides the
//    eleven nobody could check, and hides them in the flattering direction.
//  - **Say 422.** The number a person recognises is the one in their Applications folders. The rest
//    is one sentence on the block that says where it went.
//
//  ## ⚠️ It does not run on launch, and nothing here may start it
//
//  The inventory call alone is 7–8 seconds and the whole sweep about thirteen. So Apps runs on a
//  press, and while it runs the panel fills in row by row rather than sitting frozen behind a
//  spinner. `AppsModel` has no launch check; this file must not add one.

struct AppsView: View {
    @Environment(AppState.self) private var app

    private var model: AppsModel { app.apps }

    /// What is drawn. In demo mode this is an invented Mac and **nothing has been read from this
    /// one** — the promise the bar across the top of the window makes on every screen.
    private var answer: AppsAnswer? {
        app.demoMode ? DemoData.apps(app.demoMachine) : model.answer
    }

    /// The section's own line, taken from the report it describes so the chip and the rows cannot
    /// disagree.
    private var record: CheckRecord? { answer?.report.record ?? app.records[.apps] }

    /// Demo mode is a picture of a Mac, not this Mac, so nothing on it may start a real check.
    private var live: Bool { !app.demoMode }

    /// True while a real run is in flight. Never in demo mode, where nothing runs at all.
    private var reading: Bool { live && model.isChecking }

    var body: some View {
        StableScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                SectionHeader(section: .apps, record: record)

                // ⚠️ One line, and only the leftovers row is short without the grant. Everything
                // else in Apps — the inventory, the versions, the update check, the crashes — needs
                // no permission at all, measured 2026-08-27.
                PermissionNoticeLine(section: .apps)

                checkControl

                if app.askingUpdateConsent {
                    consentQuestion
                } else if reading {
                    inFlight
                } else if let answer {
                    summary(answer)
                    WhatIsInstalledBlock(inventory: answer.report.inventory,
                                         bundledWithMacOS: answer.bundledWithMacOS)
                    rows(answer)
                    appList(answer)
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
            Text(SectionID.apps.sentence)
                .font(.appBody)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.gutter) {
                Button(SectionID.apps.verb) {
                    Task { await app.runAppsCheck() }
                }
                .buttonStyle(.appProminent)
                .controlSize(.large)
                .disabled(!live || model.isChecking || app.askingUpdateConsent)

                if reading, let stage = model.stage {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.inventoryProgress?.sentence ?? stage.sentence)
                            .font(.appCallout)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Step \(stage.step) of \(AppsModel.Stage.count)")
                            .font(.appCaption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .appAnimation(Motion.chrome, value: model.stage)

            // ⚠️ Said once, on the screen it is true of. Thirteen seconds is long enough that a
            // person who pressed the button and watched nothing happen for eight of them deserves
            // to have been told first.
            Text("Wellkept reads this only when you press the button — never when the app opens and "
                 + "never on its own. Asking macOS for the list of apps takes several seconds, and "
                 + "nothing here changes anything.")
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: The consent question

    /// **The ask, on the screen rather than over it.** See `UpdateConsentPanel`.
    ///
    /// It appears once, on the first press. `UpdateConsent.Answer` remembers the reply, and the
    /// switch afterwards lives in Settings ▸ Permissions.
    private var consentQuestion: some View {
        UpdateConsentPanel(
            // The real number, where a run has already produced one. `nil` before the first, in
            // which case the line is left out rather than padded with a guess.
            storeAppCount: model.answer?.appsThatWouldBeNamed,
            onAllow: { Task { await app.answerUpdateConsent(true) } },
            onDecline: { Task { await app.answerUpdateConsent(false) } })
    }

    // MARK: The summary sentence

    /// **The section's answer, in one line, and it never stands alone.**
    ///
    /// It comes from `AppsReport.summary`, which is where the count is welded to its coverage.
    /// Rewriting it here is how the two would come apart.
    private func summary(_ answer: AppsAnswer) -> some View {
        Text(answer.report.summary)
            .font(.appTitle3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isSummaryElement)
    }

    // MARK: While it is reading

    /// The live state. **A real one, and it lasts about thirteen seconds.**
    ///
    /// Each row replaces its own placeholder as it lands. The alternative — a spinner over a blank
    /// panel for thirteen seconds — is indistinguishable from an app that has stopped.
    private var inFlight: some View {
        VStack(spacing: 0) {
            ForEach(Array(AppsTopic.allCases.enumerated()), id: \.element) { index, topic in
                if let row = model.arrived.first(where: { $0.topic == topic }) {
                    AppsRowView(row: row, index: index)
                } else {
                    AppsRowPlaceholder(topic: topic,
                                       index: index,
                                       active: model.stage?.topic == topic,
                                       detail: topic == .installed
                                           ? model.inventoryProgress?.sentence
                                           : nil)
                }
            }
        }
    }

    // MARK: The five rows

    private func rows(_ answer: AppsAnswer) -> some View {
        // ⚠️ `report.rows` is already in `AppsTopic` order, put there by `AppsReport.init`. It is
        // never sorted here and never filtered — every row every time, even on a Mac where nothing
        // has crashed and nothing was left behind.
        VStack(spacing: 0) {
            ForEach(Array(answer.report.rows.enumerated()), id: \.element.id) { index, row in
                switch row.topic {
                case .updates:
                    // The one row that carries a footnote: exactly which app names left this Mac.
                    // On the row, never behind Options — it is a disclosure about something that
                    // happened, not an explanation of the answer.
                    AppsRowView(row: row, index: index, footnote: answer.update.disclosureSentence)
                case .stoppedWorking:
                    AppsRowView(row: row, index: index) { CrashList(crashes: answer.crashes) }
                case .removedLeftovers:
                    AppsRowView(row: row, index: index) { LeftoverList(leftovers: answer.leftovers) }
                case .installed, .macOS:
                    AppsRowView(row: row, index: index)
                }
            }
        }
    }

    // MARK: The app list

    /// The section's actual content. Not behind Options — see `InstalledAppsList`.
    ///
    /// The search term lives on `AppsModel` in **both** modes. It is the one control in demo mode
    /// that is worth being live: typing into it reads nothing from this Mac, and a search field that
    /// does nothing is a worse demonstration of the section than no search field at all.
    private func appList(_ answer: AppsAnswer) -> some View {
        @Bindable var model = model
        return InstalledAppsList(apps: answer.apps, searchText: $model.searchText)
    }

    // MARK: Options

    /// **One disclosure on this screen, and it says what is behind it.**
    ///
    /// Its open state lives in `AppState` rather than in a `@State` here, so a ⌘+ press does not
    /// collapse a panel somebody had just opened. It sits **after** the rows and the list:
    /// everything in it is a more exact version of something above, and a disclosure that opens
    /// above the thing it details makes the reader scroll back up to use it.
    private func options(_ answer: AppsAnswer) -> some View {
        LabelledDisclosure("Options", isExpanded: app.optionsOpen(.apps)) {
            VStack(alignment: .leading, spacing: Space.section) {
                ForEach(answer.report.rows) { row in
                    AppsRowDetails(row: row)
                }
                selfUpdatingList
                whatWasRead(answer)
            }
            .padding(.top, Space.row)
        }
    }

    /// **The list of apps Wellkept knows update themselves, shown rather than asserted.**
    ///
    /// It is the one piece of judgement in this section that is not read off the machine — fifteen
    /// entries typed into `SelfUpdatingApps` by hand — so it is printed, with the updater each entry
    /// is justified by. A person who thinks an app is on it wrongly can see that it is, and say so.
    private var selfUpdatingList: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            Text("Apps Wellkept knows update themselves")
                .font(.appHeadline)

            Text("These are never compared against a published version, because comparing them is "
               + "how a perfectly current app gets reported as behind — Chrome ships to a "
               + "percentage of people at a time, so the newest version on its public list is "
               + "often serving nobody.")
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            DetailPairGrid(pairs: SelfUpdatingApps.entries.map {
                DetailPair($0.name, $0.updater)
            })
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The section's own audit trail: when it ran, what it looked at, and what it changed.
    ///
    /// John asked for this on a clean Overview — a check that says "nothing is wrong" is worth
    /// exactly as much as the list of what it actually looked at. The same argument holds one level
    /// down, and here it costs nothing.
    private func whatWasRead(_ answer: AppsAnswer) -> some View {
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

    private func auditPairs(_ answer: AppsAnswer) -> [DetailPair] {
        let report = answer.report
        return [
            DetailPair("Ran at", ShortDate.stamp(report.ranAt)),
            DetailPair("Rows read", "\(report.rows.count) of \(AppsTopic.allCases.count)"),
            // ⚠️ Both numbers, never a percentage. A percentage is a rounding, and the rounding is
            // where the dishonesty gets in.
            DetailPair("How much of the update question we could answer", report.coverage.sentence),
            // Measured, never assumed. `nil` is a real answer and is not replaced with a
            // plausible-looking number.
            DetailPair("How far back macOS's crash records reach",
                       answer.crashWindowDays.map { $0 == 1 ? "1 day" : "\($0) days" }
                           ?? "Could not be measured on this run."),
            DetailPair("Saw everything it looked for",
                       report.complete
                           ? "Yes"
                           : "No — something on this Mac refused to be read, and the rows above say which."),
            DetailPair("What left this Mac", answer.update.disclosureSentence),
            DetailPair("What it changed", "Nothing. Every reading here is a look, not a touch."),
        ]
    }

    // MARK: Nothing read yet

    /// ⚠️ **The ordinary state, not an edge case.** Apps never runs by itself, so this is what the
    /// screen looks like on every launch until somebody presses the button.
    private var notReadYet: some View {
        EmptyStateView(
            symbol: "square.grid.2x2",
            title: "Nothing has been checked yet",
            message: "Press \(SectionID.apps.verb) and Wellkept will list every app on this Mac, "
                   + "what version each one is, where it came from and who signed it — then which "
                   + "ones have a newer version, which have stopped working, and what apps you have "
                   + "removed left behind. It takes about a quarter of a minute and it changes "
                   + "nothing.",
            greedy: false)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

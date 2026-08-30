// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import SwiftUI
import WellkeptCore

//  StorageView.swift
//  Wellkept — App/Sections
//
//  **"What's eating my space?"** — the real free-space number, where the room went, what this Mac
//  made and will make again, your own biggest files, byte-identical copies, and what is already set
//  aside.
//
//  ⭐ **This is the first section that offers to touch anything, and the whole screen is built
//  around one distinction: machine junk regenerates and may be pre-selected; a person's own files
//  are revealed, sized and sorted, and are never pre-selected and never swept.** Nothing is deleted
//  either way — anything moved goes to quarantine with a thirty-day undo, and the room appears at
//  the second press.
//
//  ## The shape, top to bottom
//
//  1. The heading, its status, and when it last ran.
//  2. The sentence and the one button — plus where the scan is looking while it runs.
//  3. ⭐ **The free-space picture.** The real number leads, Finder's is printed underneath, and one
//     line says what the difference is. Then the snapshot line, the refusals, the iCloud files and
//     the named gap — all of them from `StorageReport.linesUnderTheHeadline`, in that order.
//  4. **The five rows, in fixed order and never sorted**: What is using the space · Machine junk ·
//     Your own large files · Duplicates · What is set aside.
//  5. **Options** — everything more exact, plus what this run actually looked at.
//
//  ## ⭐ The two ceremonies, and why it is obvious which one you are in
//
//  | | Machine junk | Your own file |
//  |---|---|---|
//  | Selection | ticks, and some arrive ticked | no ticks anywhere |
//  | The press | one, for the whole batch | one file, after a sheet |
//  | Before it | `SetAsideNotice` — the before-sentence | `SetAsideSheet` — the approved arithmetic |
//  | Routes | one | two: set aside, or set aside and empty |
//
//  The four verbs are identical. What differs is the ceremony, and it is carried by three visible
//  things at once — the checkbox column, the one-press button, and a line on each card saying which
//  list this is.
//
//  ## ⚠️ Three things this screen may never do
//
//  - **Say space was freed.** Setting 391 MB aside across 100,000 files moved free space by −8 KiB.
//    `QuarantineWordsTests` fails the build on the word.
//  - **Pre-select anything of yours.** `StorageRow.preSelected` returns `[]` for four of the five
//    topics whatever the items claim, and `Item.mayBePreSelected` refuses again underneath it.
//  - **Draw an "Other" slice.** The scan accounted for 244 GB of a disk macOS says has 357 GB in
//    use. The difference is named and explained, never bundled into a wedge.
//
//  ## ⚠️ This section does not run on launch, and nothing here may start it
//
//  A full sweep took 56.7 seconds on this Mac for 983,868 files, and with Full Disk Access granted
//  it gets slower rather than faster — the folders it was refused are folders it would then walk.
//  So Storage runs on a press, it says where it is looking as it goes, and it never promises a time.

struct StorageView: View {

    @Environment(AppState.self) private var app

    private var model: StorageModel { app.storage }

    /// What is drawn. In demo mode this is an invented Mac and **nothing has been read from this
    /// one** — the promise the bar across the top of the window makes on every screen.
    private var answer: StorageAnswer? {
        app.demoMode ? DemoData.storage(app.demoMachine) : model.answer
    }

    private var record: CheckRecord? { answer?.report.record ?? app.records[.storage] }

    /// Demo mode is a picture of a Mac, not this Mac, so nothing on it may start a real check or
    /// move a real file.
    private var live: Bool { !app.demoMode }

    private var scanning: Bool { live && model.isScanning }

    /// ⚠️ The consequence, threaded through to every place a press is offered: **if the disk is
    /// full today, quarantine is the wrong button.**
    private var diskIsAlreadyFull: Bool {
        answer.map { $0.report.freeSpace.pressure != .comfortable } ?? false
    }

    var body: some View {
        StableScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                SectionHeader(section: .storage, record: record)

                // ⚠️ Storage is the section Full Disk Access costs the most in: without it, 54
                // folders in the home directory cannot be read here — including the Trash and the
                // Photos library, usually the two biggest wins. The line draws nothing once the
                // grant is on.
                PermissionNoticeLine(section: .storage)

                scanControl

                if let answer {
                    FreeSpaceBlock(report: answer.report)
                    if let word = model.lastWord, live { outcome(word) }
                    rows(answer)
                    options(answer)
                } else if !scanning {
                    notScannedYet
                }
            }
            .padding(Space.page)
            .readableColumn()
        }
        .fillsPane()
    }

    // MARK: The sentence and the button

    private var scanControl: some View {
        VStack(alignment: .leading, spacing: Space.block) {
            Text(SectionID.storage.sentence)
                .font(.appBody)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.gutter) {
                Button(scanning ? StorageWords.scanning : SectionID.storage.verb) {
                    Task { await app.runStorageCheck() }
                }
                .buttonStyle(.appProminent)
                .controlSize(.large)
                .disabled(!live || model.isScanning)

                if scanning {
                    Button(StorageWords.cancel) { model.cancelScan() }
                        .buttonStyle(.app)
                        .controlSize(.regular)
                }
                Spacer(minLength: 0)
            }

            if scanning { inFlight }

            // Said once, on the screen it is true of. Storage never runs by itself, and a person
            // who notices the screen is blank when they open the app deserves to know that is
            // deliberate rather than broken.
            Text(StorageWords.whatTheScanDoes)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Where it is looking, and which reader is running. **No percentage and no estimate** — see
    /// `ScanPolicy.Running.whyThereIsNoEstimate`.
    private var inFlight: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.gutter) {
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                if let stage = model.stage {
                    Text(stage.sentence)
                        .font(.appCallout)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Step \(stage.step) of \(StorageScan.Stage.count)")
                        .font(.appCaption)
                        .foregroundStyle(Theme.textTertiary)
                }
                if let place = model.place {
                    Text(place)
                        .font(.appCaption)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
        .appAnimation(Motion.chrome, value: model.stage)
    }

    /// What the last press did, in the engine's own words, where the person is already looking.
    ///
    /// It stays until it is dismissed or replaced. A note that vanished on a timer would be the one
    /// sentence in the app somebody is most likely to want to re-read: it is the only report of an
    /// action that cannot be undone.
    private func outcome(_ word: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.gutter) {
            Text(word)
                .font(.appCallout)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: Space.row)
            Button("Dismiss") { model.clearLastWord() }
                .buttonStyle(.app)
                .controlSize(.small)
        }
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(cornerRadius: Radius.control)
        .accessibilityElement(children: .combine)
    }

    // MARK: The five rows

    /// ⚠️ `report.rows` is already in `StorageTopic` order, put there by `StorageReport.init`. It is
    /// never sorted here and never filtered.
    private func rows(_ answer: StorageAnswer) -> some View {
        VStack(alignment: .leading, spacing: Space.gutter) {
            ForEach(answer.report.rows) { row in
                StorageTopicCard(row: row, ceremonyNote: ceremonyNote(row)) {
                    content(row, answer: answer)
                }
            }
        }
    }

    /// The one line that says which ceremony this card is. Absent where there is nothing to press.
    private func ceremonyNote(_ row: StorageRow) -> String? {
        guard row.unreadable == nil, !row.items.isEmpty else { return nil }
        switch row.topic {
        case .machineJunk:                 return StorageWords.thisOneIsABatch
        case .yourOwnFiles, .duplicates:   return StorageWords.thisOneIsOneAtATime
        case .whatIsUsingSpace, .setAside: return nil
        }
    }

    @ViewBuilder
    private func content(_ row: StorageRow, answer: StorageAnswer) -> some View {
        if let why = row.unreadable {
            refusal(row, why: why)
        } else {
            switch row.topic {
            case .whatIsUsingSpace:
                PlacesList(places: answer.places)

            case .machineJunk:
                JunkBatch(row: row,
                          judgements: answer.junk,
                          model: model,
                          diskIsAlreadyFull: diskIsAlreadyFull)
                    // Demo mode is a picture of a Mac, not this Mac. Nothing on it may move a file.
                    .disabled(!live)

            case .yourOwnFiles:
                VStack(spacing: 0) {
                    ForEach(Array(row.items.enumerated()), id: \.element.id) { index, item in
                        OwnItemRow(item: item,
                                   index: index,
                                   home: model.home,
                                   busy: model.isWorking || !live,
                                   trouble: model.rowWord[item.path],
                                   onSetAside: { ask(item) })
                    }
                }

            case .duplicates:
                VStack(spacing: 0) {
                    ForEach(Array(answer.groups.enumerated()), id: \.element.id) { index, group in
                        DuplicateGroupView(group: group,
                                           index: index,
                                           home: model.home,
                                           busy: model.isWorking || !live,
                                           trouble: { model.rowWord[$0.path] },
                                           onSetAside: { ask($0) })
                    }
                }

            case .setAside:
                SetAsideList(model: model.quarantine)
                    .disabled(!live)
            }
        }
    }

    /// The house sentence for something we could not read, and the one button that can change the
    /// answer — offered only where a grant would genuinely change it.
    private func refusal(_ row: StorageRow, why: Unreadable) -> some View {
        VStack(alignment: .leading, spacing: Space.row) {
            Text(why.sentence(about: row.topic.label))
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let remedy = row.remedy {
                Button(remedy.title) { open(remedy) }
                    .buttonStyle(.app)
                    .controlSize(.small)
                    .disabled(!live)
            }
        }
    }

    @MainActor private func open(_ remedy: Remedy) {
        guard let raw = remedy.settingsPane, let pane = SystemSettingsPane(rawValue: raw) else { return }
        pane.open()
    }

    // MARK: ⭐ Ceremony two — the sheet

    /// One file, one sheet, and the arithmetic before the press.
    ///
    /// ⚠️ It goes through the window's **one** sheet slot. Two `.sheet` modifiers on one view make
    /// SwiftUI silently drop one, with no warning and no crash — just a button that does nothing on
    /// the days the other sheet happens to be first.
    private func ask(_ item: Item) {
        guard live else { return }
        app.sheet = SheetRoute(id: "set-aside-\(item.id)") {
            SetAsideSheet(item: item,
                          alreadyWaiting: model.alreadyWaiting,
                          diskIsAlreadyFull: diskIsAlreadyFull) { thenEmpty in
                Task { await model.setAside(item, thenEmpty: thenEmpty) }
            }
        }
    }

    // MARK: Options

    /// **One disclosure on this screen, and it says what is behind it.** It sits after the rows:
    /// everything in it is a more exact version of something above, and a disclosure that opens
    /// above the thing it details makes the reader scroll back up to use it.
    private func options(_ answer: StorageAnswer) -> some View {
        LabelledDisclosure("Options", isExpanded: app.optionsOpen(.storage)) {
            VStack(alignment: .leading, spacing: Space.section) {
                ForEach(answer.report.rows) { row in
                    if !row.details.isEmpty {
                        VStack(alignment: .leading, spacing: Space.row) {
                            Text(row.topic.label)
                                .font(.appHeadline)
                            DetailPairGrid(pairs: row.details)
                        }
                    }
                }
                whatWasRead(answer)
            }
            .padding(.top, Space.row)
        }
    }

    /// The section's own audit trail: when it ran, what it accounted for, what it could not see,
    /// and what it changed.
    private func whatWasRead(_ answer: StorageAnswer) -> some View {
        VStack(alignment: .leading, spacing: Space.row) {
            Text("This scan")
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

    private func auditPairs(_ answer: StorageAnswer) -> [DetailPair] {
        let report = answer.report
        var pairs = [
            DetailPair("Ran at", ShortDate.stamp(report.ranAt)),
            DetailPair("Rows read", "\(report.rows.count) of \(StorageTopic.allCases.count)"),
            DetailPair("What it accounted for", report.measured.text),
            DetailPair("Where it started", ScanPolicy.whyNotTheRoot),
            DetailPair("Why there is no time estimate", ScanPolicy.Running.whyThereIsNoEstimate),
            DetailPair("Last accessed dates", ScanPolicy.whyLastAccessedIsNotHere),
            DetailPair("Saw everything it looked for",
                       report.complete
                           ? "Yes"
                           : "No — something on this Mac refused to be read, and the rows above say which."),
            // ⚠️ Reading is a look. The only thing on this screen that changes anything is a button
            // a person pressed, and even that moves a file rather than deleting one.
            DetailPair("What the scan changed", "Nothing. It reads sizes and names; it opens nothing."),
        ]
        pairs.append(contentsOf: report.gap.detailPairs)
        return pairs
    }

    // MARK: Nothing scanned yet

    /// ⚠️ **The ordinary state, not an edge case.** Storage never runs by itself, so this is what
    /// the screen looks like on every launch until somebody presses the button.
    private var notScannedYet: some View {
        EmptyStateView(symbol: "internaldrive",
                       title: StorageWords.notScannedYet,
                       message: "\(StorageWords.whatTheScanDoes) \(StorageWords.howLongItTakes)",
                       greedy: false)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

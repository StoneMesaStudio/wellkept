// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import AppKit
import SwiftUI
import Testing
import WellkeptCore

//  StorageShot.swift
//  ViewShots
//
//  ⭐ **Pictures of the real Storage screen — never scanned, both demo Macs, Options open, the
//  batch, and the sheet that states the arithmetic.**
//
//  These are `StorageView`, `SetAsideSheet` and `FreeSpaceBlock`, the same types the app puts on
//  screen, driven by a real `AppState` in demo mode. A harness that photographs an imitation
//  certifies a screen nobody ships.
//
//  ## ⚠️ Nothing here reads or touches this Mac, and on this section that is the whole point
//
//  Storage is the first section that offers to move somebody's files. Every picture below comes
//  from `DemoData`, whose two Macs are invented; `StorageModel` is never asked to scan, and no shot
//  in this file presses anything. `StorageView` disables the batch and the quarantine list outright
//  in demo mode, so even a render that pumped a run loop into a button would find it inert.
//
//  ## What to look at
//
//  - **The real free-space number leads**, Finder's is underneath, and one line says what the
//    difference is. On the unwell Mac the snapshot line, the 54 refused folders, the 15,593 iCloud
//    files and the named gap all follow it, in that order and with no "Other" slice anywhere.
//  - **Exactly one list has ticks on it.** The junk card has a checkbox column and one button; the
//    two lists of a person's own things have neither, and each card says which it is.
//  - **Every offer shows two numbers.** On the unwell Mac the second one is nothing, over and over,
//    because a snapshot from 4 August is holding the blocks. That column of zeroes is the point.
//  - **The runtimes have no button at all**, under a heading that says so.
//  - **At 200% text** the checkbox column, the two figures and the row's sentences stay in their
//    columns rather than the numbers being pushed out of the readable column.
//
//      bin/make-shots.sh

@Suite("View shots — Storage", .serialized)
@MainActor
struct StorageShot {

    // MARK: - Fixtures

    /// A shell state positioned on Storage.
    ///
    /// ⚠️ `demoMode` and `demoMachine` write to `UserDefaults.standard`, which under `xctest` is the
    /// test process's own domain rather than the app's. Nothing this touches survives the run.
    private func state(demo: DemoMachine? = nil, optionsOpen: Bool = false) -> AppState {
        let app = AppState()
        app.demoMode = demo != nil
        if let demo { app.demoMachine = demo }
        app.selection = .storage
        if optionsOpen { app.openOptions.insert(.storage) }
        return app
    }

    /// The window: the hand-rolled rail beside the pane, which is the shape `RootView` builds.
    private func window(_ app: AppState) -> some View {
        HStack(spacing: 0) {
            Sidebar()
            StorageView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .pageGround()
        .environment(app)
    }

    /// How tall a frame the page needs when nothing may scroll out of the picture.
    ///
    /// ⚠️ A shot at the window's real height photographs the free-space block and the first card.
    /// **The five rows are the section**, so the frame is tall enough to hold all of them. Width is
    /// what governs reflow, so a taller frame changes nothing about the layout.
    private enum PageHeight {
        static let face: CGFloat = 3_600
        static let whole: CGFloat = 6_400
        static let wholeAtLargestText: CGFloat = 11_000
    }

    private func bothAppearances(_ view: some View, width: CGFloat, height: CGFloat,
                                 _ number: Int, _ name: String) {
        ShotWriter.write(view, width: width, height: height,
                         name: "\(number)-\(name)-light", scheme: .light)
        ShotWriter.write(view, width: width, height: height,
                         name: "\(number + 1)-\(name)-dark", scheme: .dark)
    }

    /// Run a block with the app's text size turned up. Restored whatever happens.
    private func atLargestText(_ body: () -> Void) {
        let key = AppearancePrefs.textScaleKey
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(Double(AppFont.maxScale), forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        body()
    }

    // MARK: - The faces

    /// **Nothing has been scanned — and this is every launch, not an edge case.**
    ///
    /// Storage never runs by itself: a full sweep took 56.7 seconds on this Mac for 983,868 files.
    /// So this is what a person sees each time they open the section, and it has to read as a
    /// section waiting rather than one that failed to load.
    @Test("Storage, never scanned")
    func neverScanned() {
        let size = Layout.windowDefault
        bothAppearances(window(state()), width: size.width, height: size.height,
                        300, "storage-never-scanned")
    }

    /// **A healthy Mac.** Modest junk, a couple of big files, and a comfortable disk — so Storage
    /// contributes nothing at all to "what needs you". The thing to look at is that the screen is
    /// still worth opening: it says where the room went, and there is nothing to do about it.
    @Test("Storage, the healthy demo Mac")
    func healthyMac() {
        let size = Layout.windowDefault
        bothAppearances(window(state(demo: .healthy)), width: size.width, height: PageHeight.face,
                        302, "storage-healthy")
    }

    /// **A Mac with problems.** A nearly full disk, a stuck snapshot taking the second number away
    /// on almost every row, 1,204 duplicate sets inside project folders we decline to offer, and
    /// 11.6 GB of simulator runtimes reported with no button.
    @Test("Storage, the unwell demo Mac")
    func unwellMac() {
        let size = Layout.windowDefault
        bothAppearances(window(state(demo: .problems)), width: size.width, height: PageHeight.face,
                        304, "storage-problems")
    }

    /// Options open on the unwell Mac: every row's exact figures, plus what this scan actually
    /// looked at and what it changed.
    @Test("Storage, Options open")
    func optionsOpen() {
        let size = Layout.windowDefault
        bothAppearances(window(state(demo: .problems, optionsOpen: true)),
                        width: size.width, height: PageHeight.whole, 306, "storage-options")
    }

    // MARK: - The free-space block on its own

    /// ⭐ **The one thing no other tool on this Mac does.** The real number, Finder's underneath, and
    /// a line saying what the difference is — measured 68.1 GB apart on the machine this was
    /// written on.
    @Test("The free-space picture, both Macs")
    func freeSpace() {
        bothAppearances(FreeSpaceBlock(report: DemoData.storage(.healthy).report)
                            .padding(Space.page)
                            .frame(width: Layout.readableColumn)
                            .pageGround(),
                        width: Layout.readableColumn + Space.page * 2, height: 420,
                        310, "storage-free-space-healthy")
        bothAppearances(FreeSpaceBlock(report: DemoData.storage(.problems).report)
                            .padding(Space.page)
                            .frame(width: Layout.readableColumn)
                            .pageGround(),
                        width: Layout.readableColumn + Space.page * 2, height: 620,
                        312, "storage-free-space-problems")
    }

    // MARK: - ⭐ Ceremony two, the sheet

    /// **The sheet, on a file a snapshot is holding.** The arithmetic says the second press will not
    /// help either, and it says it before the button rather than after.
    @Test("The set-aside sheet, held by a snapshot")
    func sheetHeldBySnapshot() {
        let answer = DemoData.storage(.problems)
        guard let item = answer.report.row(.yourOwnFiles)?.items.first(where: {
            $0.handling.mayOfferAButton && $0.bytes.recoverableToday.isZero
        }) else {
            Issue.record("the unwell demo Mac no longer has a file a snapshot is holding")
            return
        }
        bothAppearances(SetAsideSheet(item: item,
                                      alreadyWaiting: answer.setAside,
                                      diskIsAlreadyFull: true,
                                      onConfirm: { _ in }),
                        width: 640, height: 620, 314, "storage-sheet-held")
    }

    /// **The same sheet on a file that really would come back**, so the two sentences can be read
    /// side by side. This is the ordinary case, and it is the one that makes the other legible.
    @Test("The set-aside sheet, room that really comes back")
    func sheetRoomComesBack() {
        let answer = DemoData.storage(.healthy)
        guard let item = answer.report.row(.yourOwnFiles)?.items.first(where: {
            !$0.bytes.recoverableToday.isZero
        }) else {
            Issue.record("the healthy demo Mac no longer has a file that would come back")
            return
        }
        bothAppearances(SetAsideSheet(item: item, alreadyWaiting: nil,
                                      diskIsAlreadyFull: false, onConfirm: { _ in }),
                        width: 640, height: 560, 316, "storage-sheet-free")
    }

    // MARK: - The two ceremonies, side by side

    /// ⭐ **The batch card on its own.** This is the only list in the app with ticks on it, and the
    /// picture is here so the checkbox column, the two figures and the one press can be judged
    /// against each other rather than against the whole page.
    ///
    /// Look for: the runtimes underneath, under a heading that says there is nothing to press.
    @Test("The machine-junk batch")
    func junkBatch() {
        bothAppearances(card(.machineJunk, on: .problems),
                        width: Layout.readableColumn + Space.page * 2, height: 1_500,
                        330, "storage-junk-batch")
    }

    /// **A person's own files, on the same screen, with no ticks anywhere.** The contrast with the
    /// picture above is the section's whole design: same four verbs, different ceremony, and the
    /// difference is visible without reading a word.
    @Test("Your own large files")
    func yourOwnFiles() {
        bothAppearances(card(.yourOwnFiles, on: .problems),
                        width: Layout.readableColumn + Space.page * 2, height: 1_200,
                        332, "storage-your-own-files")
    }

    /// **The duplicates card**, where we list every copy and nominate none of them.
    @Test("Duplicates, with no original nominated")
    func duplicates() {
        bothAppearances(card(.duplicates, on: .problems),
                        width: Layout.readableColumn + Space.page * 2, height: 900,
                        334, "storage-duplicates")
    }

    /// **The quarantine, where it now lives.** Oldest first, anything past thirty days risen to the
    /// top and marked ready, Restore and Delete on the row, and one button that says what it
    /// removes.
    @Test("What is set aside")
    func setAside() {
        bothAppearances(card(.setAside, on: .problems),
                        width: Layout.readableColumn + Space.page * 2, height: 900,
                        336, "storage-set-aside")
    }

    /// One card, alone, in the page's own column.
    private func card(_ topic: StorageTopic, on machine: DemoMachine) -> some View {
        let app = state(demo: machine)
        let answer = DemoData.storage(machine)
        return Group {
            if let row = answer.report.row(topic) {
                StorageTopicCard(row: row, ceremonyNote: nil) {
                    cardContent(topic, row: row, answer: answer, app: app)
                }
            }
        }
        .padding(Space.page)
        .frame(width: Layout.readableColumn + Space.page * 2, alignment: .topLeading)
        .pageGround()
        .environment(app)
    }

    @ViewBuilder
    private func cardContent(_ topic: StorageTopic,
                             row: StorageRow,
                             answer: StorageAnswer,
                             app: AppState) -> some View {
        switch topic {
        case .machineJunk:
            JunkBatch(row: row, judgements: answer.junk, model: app.storage,
                      diskIsAlreadyFull: true)
        case .yourOwnFiles:
            VStack(spacing: 0) {
                ForEach(Array(row.items.enumerated()), id: \.element.id) { index, item in
                    OwnItemRow(item: item, index: index, onSetAside: { })
                }
            }
        case .duplicates:
            VStack(spacing: 0) {
                ForEach(Array(answer.groups.enumerated()), id: \.element.id) { index, group in
                    DuplicateGroupView(group: group, index: index,
                                       trouble: { _ in nil }, onSetAside: { _ in })
                }
            }
        case .setAside:
            SetAsideList(model: app.storage.quarantine)
        case .whatIsUsingSpace:
            PlacesList(places: answer.places)
        }
    }

    // MARK: - The largest text

    /// ⚠️ **Where this section is judged.** Storage is the only screen with a checkbox column, two
    /// stacked figures and a wrapping path on the same row. At 200% text those three want the same
    /// width, and this is the picture that shows whether they got it.
    @Test("Storage at 200% text")
    func atTwoHundredPercent() {
        atLargestText {
            bothAppearances(window(state(demo: .problems)),
                            width: Layout.windowDefault.width, height: PageHeight.wholeAtLargestText,
                            320, "storage-problems-200")
        }
    }

    /// The batch at 200%, where the checkbox, the name, the path and two stacked figures all want
    /// the same width.
    @Test("The batch at 200% text")
    func batchAtTwoHundredPercent() {
        atLargestText {
            bothAppearances(card(.machineJunk, on: .problems),
                            width: Layout.readableColumn + Space.page * 2, height: 2_600,
                            322, "storage-junk-batch-200")
        }
    }

    /// And at the window's floor, where the sidebar and a 700-point column only just fit.
    @Test("Storage at the window's floor")
    func atTheFloor() {
        let size = Layout.windowMinimum
        bothAppearances(window(state(demo: .problems)), width: size.width, height: PageHeight.face,
                        324, "storage-problems-narrow")
    }
}

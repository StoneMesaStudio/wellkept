// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import AppKit
import SwiftUI
import Testing
import WellkeptCore

//  QuarantineShot.swift
//  ViewShots
//
//  ⭐ **Pictures of the real quarantine screen, driven by real records in a pretend home folder.**
//
//  These are `QuarantinePage` and `QuarantineSettings`, the same types the app puts on screen, with
//  a `QuarantineModel` pointed at a sandbox this file builds and throws away. A harness that
//  photographs an imitation certifies a screen nobody ships.
//
//  ## ⚠️ Nothing here touches a real home folder, and this is the screen where that matters most
//
//  Every entry point in the engine takes `home:`. The sandbox is made in the temporary directory,
//  filled with files this test wrote itself, and removed in a `defer`. The one automatic path that
//  could delete something — `QuarantineLaunch` — refuses under `xctest` outright, which is proved in
//  `QuarantineScreenTests` rather than assumed here.
//
//  ## What to look at
//
//  - **The ready item is at the top**, tagged, above two younger ones. That order is
//    `Expiry.sortedForTheScreen`, and it is the one list in this app that is not worst-first.
//  - **The summary row never says a figure came back.** "40 GB set aside — the oldest is 12 days
//    old", and Empty sits on it.
//  - **The iCloud row carries one line** — John's line, on the row it is true of, not in a dialog.
//  - **At 200% text** the row's two verbs and its size stay in the right-hand column while the path
//    wraps, rather than the buttons being pushed off the readable column.
//
//      bin/make-shots.sh
//

@Suite("View shots — the quarantine screen", .serialized)
@MainActor
struct QuarantineShot {

    // MARK: - Fixtures

    /// The same record with a different date. Building a month-old quarantine any other way means
    /// waiting a month.
    private func aged(_ record: QuarantineRecord, daysAgo: Int) -> QuarantineRecord {
        QuarantineRecord(
            id: record.id, originalPath: record.originalPath, originalName: record.originalName,
            identity: record.identity, quarantinedPath: record.quarantinedPath,
            storeRoot: record.storeRoot, mode: record.mode, ownerID: record.ownerID,
            groupID: record.groupID, flags: record.flags, createdOn: record.createdOn,
            modifiedOn: record.modifiedOn, bytes: record.bytes, isDirectory: record.isDirectory,
            isSymbolicLink: record.isSymbolicLink, parentMode: record.parentMode,
            sectionRaw: record.sectionRaw, reason: record.reason,
            quarantinedOn: Date().addingTimeInterval(-Double(daysAgo) * 86_400),
            wasInICloud: record.wasInICloud, containment: record.containment)
    }

    /// Three things set aside: one past thirty days, one in iCloud, one from last week.
    ///
    /// The iCloud one is genuinely in an iCloud path — `Library/Mobile Documents/…` inside the
    /// sandbox — so `wasInICloud` is read from the file rather than asserted, and the picture shows
    /// the line the app would really draw.
    private func filled(_ sandbox: QuarantineSandbox) throws {
        let plan: [(String, SectionID, String, Int)] = [
            ("Library/Caches/com.example.oldapp/Cache.db", .apps,
             "Left behind by an app you removed", 41),
            ("Library/Mobile Documents/com~apple~CloudDocs/Wedding Video.mov", .storage,
             "A large file you chose to set aside", 12),
            ("Downloads/Sierra Installer.dmg", .storage,
             "An installer you have already used", 3),
        ]

        var records: [QuarantineRecord] = []
        for (path, section, reason, daysAgo) in plan {
            let file = try sandbox.file(path, contents: String(repeating: "x", count: 4_096))
            let report = Quarantine.quarantine([.init(file, section: section, reason: reason)],
                                               home: sandbox.home)
            guard let record = report.moved.first else {
                Issue.record("the fixture could not be set aside: \(report.sentence)")
                continue
            }
            records.append(aged(record, daysAgo: daysAgo))
        }
        try Ledger.write(records, home: sandbox.home)
    }

    private func model(_ sandbox: QuarantineSandbox) async -> QuarantineModel {
        let model = QuarantineModel(home: sandbox.home)
        // Loaded before the render rather than left to the page's own `.task`: the harness pumps the
        // run loop for a moment, and a picture taken before the first read lands is a picture of an
        // empty list.
        await model.load()
        return model
    }

    /// The expiry mode, set explicitly for the duration of one picture.
    ///
    /// ⚠️ Under `xctest`, `UserDefaults.standard` is the test process's own domain, so this touches
    /// nothing of the app's — but it is put back anyway, because the next suite in this bundle reads
    /// the same key.
    private func withMode(_ mode: ExpiryMode, _ body: () -> Void) {
        let key = StorageManifest.Keys.quarantineExpiry
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(mode.rawValue, forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        body()
    }

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

    private func bothAppearances(_ view: some View, width: CGFloat, height: CGFloat,
                                 _ number: Int, _ name: String) {
        ShotWriter.write(view, width: width, height: height,
                         name: "\(number)-\(name)-light", scheme: .light)
        ShotWriter.write(view, width: width, height: height,
                         name: "\(number + 1)-\(name)-dark", scheme: .dark)
    }

    // MARK: - The page

    /// **The whole screen with three things set aside**, in the default mode — manual, where nothing
    /// is ever removed without a press.
    @Test("The quarantine page, with items")
    func pageWithItems() async throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try filled(sandbox)
        let model = await model(sandbox)

        #expect(model.records.count == 3, "the fixture is empty, so this picture is of nothing")
        #expect(model.records.first?.section == .apps, "the ready item should have risen to the top")

        withMode(.manual) {
            bothAppearances(QuarantinePage(model: model), width: 860, height: 1_320,
                            190, "quarantine-page")
        }
    }

    /// The same list with the automatic setting on. **The rows say something different**, and they
    /// have to: in this mode Wellkept really will remove these, and in the other one it never will.
    @Test("The quarantine page in automatic mode")
    func pageInAutomaticMode() async throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try filled(sandbox)
        let model = await model(sandbox)

        withMode(.auto) {
            bothAppearances(QuarantinePage(model: model), width: 860, height: 1_320,
                            192, "quarantine-page-auto")
        }
    }

    /// ⚠️ **The ordinary state.** Nothing has been set aside on almost every Mac, almost always, and
    /// an empty screen that does not say why is indistinguishable from one that failed to load.
    @Test("The quarantine page with nothing in it")
    func pageWhenEmpty() async throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        let model = await model(sandbox)

        #expect(model.records.isEmpty)
        bothAppearances(QuarantinePage(model: model), width: 860, height: 720,
                        194, "quarantine-page-empty")
    }

    /// **200% text.** The size and the two verbs stay in their column while the path wraps; nothing
    /// is pushed out of the readable column and no button truncates.
    @Test("The quarantine page at 200% text")
    func pageAtLargestText() async throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try filled(sandbox)
        let model = await model(sandbox)

        atLargestText {
            withMode(.manual) {
                bothAppearances(QuarantinePage(model: model),
                                width: Layout.windowMinimum.width, height: 2_600,
                                196, "quarantine-200-page")
            }
        }
    }

    // MARK: - Settings

    /// **The Settings page**: the summary row, the thirty-day choice, and the ignore list.
    @Test("The Quarantine page in Settings")
    func settingsPage() async throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try filled(sandbox)

        let noisy = try sandbox.file("Library/Logs/chatty.log")
        _ = Quarantine.ignore(noisy, section: .apps,
                              finding: "A log file that keeps coming back",
                              home: sandbox.home)
        let dev = try sandbox.folder("Developer/build")
        _ = Quarantine.ignore(dev, section: .storage,
                              finding: "A 14 GB folder you use every day",
                              home: sandbox.home)

        let model = QuarantineModel(home: sandbox.home)
        await model.load()
        await model.loadIgnored()
        #expect(model.ignored.count == 2)

        withMode(.manual) {
            bothAppearances(QuarantineSettings(model: model)
                                .frame(width: SheetMetrics.width(560)),
                            width: SheetMetrics.width(560), height: 2_000,
                            198, "quarantine-settings")
        }

        // And the ignore list on its own, which is the half of that page a screenshot of the
        // whole thing always cuts off.
        bothAppearances(IgnoredItemsPanel(model: model)
                            .padding(Space.page)
                            .frame(width: Layout.readableColumn, alignment: .leading),
                        width: Layout.readableColumn, height: 900,
                        204, "quarantine-ignore-list")
    }

    // MARK: - The pieces a section will reuse

    /// **The two sentences that stop the app looking broken**, on their own, at the readable column
    /// — the picture to read the words off.
    ///
    /// The top one is what Storage will show *before* the button; the bottom is the permanent row
    /// afterwards. Neither says "freed", because nothing was.
    @Test("The before-and-after sentences")
    func theTwoSentences() async throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }
        try filled(sandbox)
        let model = await model(sandbox)
        let summary = try #require(model.summary)

        let pieces = VStack(alignment: .leading, spacing: Space.card) {
            SetAsideNotice(bytes: 40_000_000_000, anyInICloud: true, diskIsAlreadyFull: true)
            QuarantineSummaryRow(summary: summary, onOpen: {}, onEmpty: {})
        }
        .padding(Space.page)
        .frame(width: Layout.readableColumn, alignment: .leading)

        bothAppearances(pieces, width: Layout.readableColumn, height: 820,
                        200, "quarantine-sentences")
    }

    /// **The bar the window wears when the thirty-day sweep has just removed something**, and when
    /// a crash left an item at neither address.
    ///
    /// It is the whole reason automatic removal is allowed to exist: the person is told, in front of
    /// them, the first moment they are there to see it.
    @Test("The launch bar")
    func launchBar() {
        let bar = QuarantineLaunchBar(
            notices: ["You asked Wellkept to remove things after 30 days. Removed 2 items, "
                      + "1.2 GB. 1.2 GB has come back.",
                      "Wellkept was interrupted while setting Cache.db aside, and it is now at "
                      + "neither the place it came from nor the place Wellkept was putting it. "
                      + "Something other than Wellkept moved it. Nothing was deleted."],
            onOpen: {}, onDismiss: {})
            .frame(width: 900, alignment: .leading)

        bothAppearances(bar, width: 900, height: 420, 202, "quarantine-launch-bar")
    }
}

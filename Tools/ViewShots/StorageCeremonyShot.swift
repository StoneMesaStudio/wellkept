// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import AppKit
import SwiftUI
import Testing
import WellkeptCore

//  StorageCeremonyShot.swift
//  ViewShots
//
//  ⭐ **The four Storage states the demo Macs cannot produce, photographed from real state.**
//
//  `StorageShot` photographs the section's faces, and it drives them from `DemoData` — which is the
//  right way to photograph a face. But demo mode is deliberately inert: `StorageView` disables the
//  batch and the quarantine list on an invented Mac, and `StorageModel.ticked` is only ever filled
//  by a scan of a real disk. So four states never appear in that file at all, and they happen to be
//  the four this section is judged on:
//
//  1. ⭐ **The junk batch mid-selection.** Two boxes ticked on arrival, one cleared by hand, and one
//     thing reported with **no box at all** because nothing can move it. The demo batch is drawn
//     with an empty tick set, so it shows a card that says "these arrive ticked" above four cleared
//     boxes.
//  2. ⭐ **The sheet on a Mac that is already full**, with something in iCloud and something already
//     waiting — the version carrying John's second route, his iCloud line, and the sentence saying
//     quarantine is the wrong button today. All three lines are conditional and all three are off on
//     a healthy demo Mac.
//  3. ⭐ **The quarantine list with something genuinely past thirty days**, built by the real engine
//     in a sandbox and then dated backwards. The demo list is pointed at this Mac's own quarantine,
//     which under `xctest` is empty.
//  4. ⭐ **Full Disk Access refused**, drawn from `StorageRow.unreadable` — the house sentence, no
//     figure, no count, and a button only on the refusal a person can actually lift.
//
//  ## ⚠️ Nothing here touches a real home folder
//
//  The items in 1, 2 and 4 are built at paths that exist on no Mac. The records in 3 are written
//  into a `QuarantineSandbox` — a whole pretend home folder, removed in a `defer` — by the real
//  quarantine engine, which is the only honest way to photograph a month-old quarantine without
//  waiting a month. Every closure below does nothing: a picture of a screen is not a rehearsal of it.
//
//      bin/make-shots.sh

@Suite("View shots — Storage, the states a demo cannot reach", .serialized)
@MainActor
struct StorageCeremonyShot {

    // MARK: - Fixtures

    /// The width a card is photographed at: the readable column plus the page inset on both sides,
    /// so the card gets the 700 points it really has in the window rather than 700 minus padding.
    private static var cardWidth: CGFloat { Layout.readableColumn + Space.page * 2 }

    private func bothAppearances(_ view: some View, width: CGFloat, height: CGFloat,
                                 _ number: Int, _ name: String) {
        ShotWriter.write(view, width: width, height: height,
                         name: "\(number)-\(name)-light", scheme: .light)
        ShotWriter.write(view, width: width, height: height,
                         name: "\(number + 1)-\(name)-dark", scheme: .dark)
    }

    /// Run a block with the app's text size turned up. The setting is the real one — `AppFont.scale`
    /// reads this key on every call, so type, page insets and the sidebar width all move together,
    /// exactly as they do when somebody presses ⌘+ four times. Restored whatever happens.
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

    // MARK: - Items at paths that exist on no Mac

    private func item(_ path: String,
                      onDisk: Int64,
                      back: Int64,
                      origin: Origin = .yours,
                      kind: ItemKind = .file,
                      cloud: CloudStanding = .onThisMac,
                      handling: Handling = .canBeSetAside,
                      reason: String,
                      daysOld: Int = 40,
                      inode: UInt64) -> Item {
        Item(identity: ItemIdentity(volumeUUID: "PRETEND", volumeDevice: "/dev/disk9s1",
                                    inode: inode),
             path: path,
             bytes: Bytes(onDisk: SizeOnDisk(onDisk), recoverableToday: .all(of: SizeOnDisk(back))),
             kind: kind,
             origin: origin,
             cloudStanding: cloud,
             handling: handling,
             modifiedOn: Date().addingTimeInterval(-Double(daysOld) * 86_400),
             reason: reason)
    }

    /// ⭐ Three things that may arrive ticked, and one reported with no box at all.
    private var junkItems: [Item] {
        [item("/Users/somebody/Library/Developer/Xcode/DerivedData/Waypoint-fbkxq",
              onDisk: 13_100_000_000, back: 12_800_000_000, origin: .machineJunk, kind: .folder,
              reason: "Xcode's build output for Waypoint. Xcode writes it again on the next build.",
              daysOld: 2, inode: 101),
         item("/Users/somebody/Library/Caches/Firefox/Profiles/n2k.default/cache2",
              onDisk: 760_000_000, back: 744_000_000, origin: .machineJunk, kind: .folder,
              reason: "A store where every name is a checksum of its contents. Firefox fetches "
                    + "anything it still wants again.",
              daysOld: 0, inode: 102),
         item("/Users/somebody/Downloads/ventura.iso.download",
              onDisk: 2_400_000_000, back: 2_100_000_000, origin: .machineJunk,
              reason: "A download that stopped part way. Nothing can open it.",
              daysOld: 96, inode: 103),
         item("/Library/Developer/CoreSimulator/Images/8E1C.dmg",
              onDisk: 7_900_000_000, back: 0, origin: .machineJunk, kind: .diskImage,
              handling: .cannot("These are read-only disk images owned by the system, so there is "
                              + "no way to set one aside and no way to undo it."),
              reason: "An iOS simulator runtime. Xcode downloads it again if you remove it in "
                    + "Xcode's own settings.",
              daysOld: 120, inode: 104)]
    }

    private var junkRow: StorageRow {
        StorageRow(topic: .machineJunk,
                   headline: "Four things this Mac made and will make again.",
                   measure: .sum(junkItems.map(\.bytes)),
                   count: junkItems.count,
                   // ⚠️ Not the topic's own explanation — `StorageTopicCard` draws that already, and
                   // passing it again printed the same sentence twice in the first run of this file.
                   reason: "Three of these can be set aside. The fourth is reported because nothing "
                         + "can move it.",
                   items: junkItems)
    }

    /// The ticked set for the picture: everything that arrives ticked, **minus one a person has
    /// cleared by hand**. That is the state the picture is actually about — somebody has read the
    /// list and disagreed with one line of it.
    private var midSelection: Set<String> {
        var ticked = Set(junkRow.preSelected.map(\.id))
        if let cleared = junkItems.first(where: { $0.path.hasSuffix(".download") }) {
            ticked.remove(cleared.id)
        }
        return ticked
    }

    @ViewBuilder private func batchRows(_ ticked: Set<String>) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(junkRow.items.enumerated()), id: \.element.id) { index, item in
                JunkTickRow(item: item,
                            index: index,
                            notTickedBecause: item.mayBePreSelected ? nil : item.handling.why,
                            isTicked: ticked.contains(item.id),
                            onToggle: { _ in })
            }
        }
    }

    // MARK: - ⭐ 1. The batch, mid-selection

    /// ⭐ **Ceremony one, caught in the middle.** Two ticked, one cleared, one with no box.
    ///
    /// The fourth row is the one to look at: 7.9 GB, "nothing comes back today", greyed, and no
    /// checkbox — because a tick that cannot be acted on is a promise the press would break.
    @Test("The junk batch, mid-selection")
    func theJunkBatchMidSelection() {
        let ticked = midSelection
        #expect(ticked.count == 2, "the batch is not mid-selection — this picture proves nothing")
        #expect(junkRow.items.contains { !$0.mayBePreSelected },
                "nothing in the fixture is unmovable, so the no-box row is missing")

        let card = StorageTopicCard(row: junkRow, ceremonyNote: StorageWords.thisOneIsABatch) {
            VStack(alignment: .leading, spacing: Space.block) {
                Text(StorageWords.batchHeading).font(.appHeadline)
                batchRows(ticked)
                SetAsideNotice(bytes: 13_860_000_000, anyInICloud: false, diskIsAlreadyFull: false)
                Button(StorageWords.batchButton(ticked.count)) { }
                    .buttonStyle(.appProminent)
                    .controlSize(.large)
            }
        }
        .padding(Space.page)
        .frame(width: Self.cardWidth, alignment: .leading)

        bothAppearances(card, width: Self.cardWidth, height: 1_800, 340, "storage-batch-mid-selection")
    }

    /// The same batch at 200% text. **The checkbox column and the two figures have to stay in their
    /// columns** while the path and the reason wrap — this is the row that breaks first.
    @Test("The batch mid-selection at 200% text")
    func theBatchAtLargestText() {
        atLargestText {
            let rows = batchRows(midSelection)
                .padding(Space.page)
                .frame(width: Self.cardWidth, alignment: .leading)
            bothAppearances(rows, width: Self.cardWidth, height: 3_200,
                            342, "storage-batch-mid-selection-200")
        }
    }

    // MARK: - ⭐ 2. The sheet, in the state that carries every line

    /// ⭐ **John's sheet with all three conditional lines showing at once**: a file iCloud also
    /// holds, a Mac that is short of room today, and something already waiting in the quarantine.
    ///
    /// This is the picture to read the words off. The figure in the arithmetic is **what comes back
    /// today**, never the size on disk — quoting the larger one would be a promise the second press
    /// cannot keep.
    @Test("The one-file sheet, with every line it can carry")
    func theSheetWithEveryLine() {
        let synced = item("/Users/somebody/Movies/Wedding — full edit.mov",
                          onDisk: 12_000_000_000, back: 3_400_000_000,
                          cloud: .bothPlaces,
                          reason: "It is the largest single file in your Movies folder.",
                          daysOld: 1, inode: 201)
        #expect(synced.warning == CloudStanding.alsoRemovesItFromYourDevices)
        #expect(synced.bytes.agree == false, "the sheet's whole point is two numbers that disagree")

        let sheet = SetAsideSheet(item: synced,
                                  alreadyWaiting: Self.waiting,
                                  diskIsAlreadyFull: true,
                                  onConfirm: { _ in })
            .frame(width: SheetMetrics.width(560))

        bothAppearances(sheet, width: SheetMetrics.width(560), height: 1_300,
                        344, "storage-sheet-every-line")
    }

    /// ⚠️ **The same sheet where a snapshot is holding everything.** Nothing comes back today
    /// whatever the file's size, and the sheet must say so rather than name a figure — this is the
    /// picture that shows it saying so.
    @Test("The sheet when a snapshot holds all of it")
    func theSheetWhenASnapshotHoldsEverything() {
        let held = item("/Users/somebody/Documents/Media/Archive 2019.fcpbundle",
                        onDisk: 14_800_000_000, back: 0, kind: .bundle,
                        reason: "It is the largest single thing in your Documents folder.",
                        daysOld: 400, inode: 202)
        #expect(held.bytes.recoverableToday.isZero)

        let sheet = SetAsideSheet(item: held, alreadyWaiting: nil,
                                  diskIsAlreadyFull: false, onConfirm: { _ in })
            .frame(width: SheetMetrics.width(560))

        bothAppearances(sheet, width: SheetMetrics.width(560), height: 1_100,
                        346, "storage-sheet-held-by-snapshot")
    }

    /// ⭐ **The sheet at 200% text.** It is the one screen in this section a person reads word by
    /// word, and both routes are long labels: if a button truncates anywhere, it is here.
    @Test("The sheet at 200% text")
    func theSheetAtLargestText() {
        atLargestText {
            let mine = item("/Users/somebody/Documents/Media/Sardinia 2019.fcpbundle",
                            onDisk: 14_800_000_000, back: 500_000_000, kind: .bundle,
                            reason: "It is the largest single thing in your Documents folder.",
                            daysOld: 400, inode: 203)
            let sheet = SetAsideSheet(item: mine,
                                      alreadyWaiting: Self.waiting,
                                      diskIsAlreadyFull: true,
                                      onConfirm: { _ in })
                .frame(width: SheetMetrics.width(560))
            bothAppearances(sheet, width: SheetMetrics.width(560), height: 2_400,
                            348, "storage-sheet-200")
        }
    }

    /// Something already in quarantine, so the second route has an amount to name.
    private static let waiting = Quarantine.Summary(count: 4,
                                                    bytes: 6_100_000_000,
                                                    oldest: Date().addingTimeInterval(-34 * 86_400),
                                                    readyCount: 1,
                                                    unaccountedFor: 0,
                                                    trouble: nil)

    // MARK: - ⭐ 3. The quarantine, with something past thirty days

    /// ⭐ **The set-aside list with one item genuinely past thirty days**, risen to the top and
    /// marked ready.
    ///
    /// The records are written by the real engine into a sandbox and then dated backwards — there is
    /// no other way to photograph a month-old quarantine without waiting a month. The ready item is
    /// first because `Expiry.sortedForTheScreen` puts it there; it is the one list in this app that
    /// is not worst-first.
    @Test("The set-aside list, with something expired")
    func theSetAsideListWithAnExpiredItem() async throws {
        let sandbox = try QuarantineSandbox()
        defer { sandbox.tearDown() }

        let plan: [(String, String, Int)] = [
            ("Documents/Media/Sardinia 2019.fcpbundle",
             "You chose to set this aside from Storage.", 41),
            ("Library/Developer/Xcode/DerivedData/Waypoint-fbkxq/Build/out.o",
             "Xcode's build output. Xcode writes it again on the next build.", 12),
            ("Downloads/ventura.iso.download",
             "A download that stopped part way. Nothing can open it.", 3),
        ]

        var records: [QuarantineRecord] = []
        for (path, reason, daysAgo) in plan {
            let file = try sandbox.file(path, contents: String(repeating: "x", count: 4_096))
            let report = Quarantine.quarantine([.init(file, section: .storage, reason: reason)],
                                               home: sandbox.home)
            guard let record = report.moved.first else {
                Issue.record(Comment(rawValue: "the fixture could not be set aside: \(report.sentence)"))
                continue
            }
            records.append(Self.aged(record, daysAgo: daysAgo))
        }
        try Ledger.write(records, home: sandbox.home)

        let model = QuarantineModel(home: sandbox.home)
        await model.load()
        #expect(model.records.count == 3, "the fixture is empty, so this is a picture of nothing")
        #expect(model.summary?.readyCount == 1, "nothing is past thirty days — the picture is wrong")

        let list = SetAsideList(model: model)
            .padding(Space.page)
            .frame(width: Self.cardWidth, alignment: .leading)

        bothAppearances(list, width: Self.cardWidth, height: 1_500, 350, "storage-set-aside-expired")
    }

    /// The same record with a different date. Building a month-old quarantine any other way means
    /// waiting a month.
    private static func aged(_ record: QuarantineRecord, daysAgo: Int) -> QuarantineRecord {
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

    // MARK: - ⭐ 4. Not allowed to look

    /// ⭐ **Full Disk Access refused.** Without it, 54 folders in a home directory cannot be read —
    /// the Trash and the photo library among them, usually the two biggest wins on any Mac.
    ///
    /// ⚠️ **Never a zero.** Each card says what happened in the house sentence and carries no figure
    /// and no count at all, and only the refusal a person can actually lift gets a button.
    @Test("Full Disk Access refused")
    func fullDiskAccessRefused() {
        let refused = UnreadablePlaces(count: 54,
                                       notable: ["your Trash", "your photo library", "your mail"],
                                       why: .notPermitted)
        #expect(refused.remedy != nil, "the one refusal a person can lift has no button")

        // ⚠️ `about:` names the **place**, not the row. Left to default it is the topic's own label,
        // and the card then prints its own title twice — which the first run of this file did.
        let rows = [StorageRow.unreadable(.yourOwnFiles, .notPermitted,
                                          about: "Your Trash and your photo library",
                                          reason: "They are usually the two biggest things on a "
                                                + "Mac, and both are behind this permission."),
                    StorageRow.unreadable(.duplicates, .notPermitted,
                                          about: "Most of the folders that could hold copies")]
        for row in rows {
            #expect(row.measure == nil, "a refused row carried a figure")
            #expect(row.count == nil)
            #expect(row.items.isEmpty)
        }

        bothAppearances(refusedBlock(refused, rows), width: Self.cardWidth, height: 1_300,
                        352, "storage-refused")
    }

    /// The refusal at 200% text, which is the state a first-run Mac is actually in.
    @Test("Full Disk Access refused, at 200% text")
    func theRefusalAtLargestText() {
        atLargestText {
            let refused = UnreadablePlaces(count: 54,
                                           notable: ["your Trash", "your photo library"],
                                           why: .notPermitted)
            let rows = [StorageRow.unreadable(.yourOwnFiles, .notPermitted,
                                              about: "Your Trash and your photo library",
                                              reason: "They are usually the two biggest things on a "
                                                    + "Mac, and both are behind this permission.")]
            bothAppearances(refusedBlock(refused, rows), width: Self.cardWidth, height: 1_600,
                            354, "storage-refused-200")
        }
    }

    private func refusedBlock(_ refused: UnreadablePlaces, _ rows: [StorageRow]) -> some View {
        VStack(alignment: .leading, spacing: Space.section) {
            if let sentence = refused.sentence {
                Text(sentence)
                    .font(.appBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(rows) { row in
                StorageTopicCard(row: row) { EmptyView() }
            }
        }
        .padding(Space.page)
        .frame(width: Self.cardWidth, alignment: .leading)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import WellkeptCore

//  StorageWords.swift
//  Wellkept — App/Sections/Storage
//
//  ⭐ **Every sentence this screen says that is not already written somewhere with better authority.**
//
//  Four files already own words this section shows, and none of them is re-worded here:
//
//  | Where | What it owns |
//  |---|---|
//  | `QuarantineWords` | John's four sentences about setting aside, including the disk-is-full one |
//  | `FreeSpace.Says` | the arithmetic on the sheet, and the two routes off it |
//  | `QuarantineText` | the quarantine row, its two confirmations, and the ignore list |
//  | `StorageTopic.explanation` | one plain sentence per row, in `WellkeptCore` |
//
//  What is left is the handful of headings and captions the screen itself needs. It is a short
//  file on purpose: a section that writes its own vocabulary is a section that will eventually
//  describe the same quarantine in two different ways, and one of them will be wrong.

enum StorageWords {

    // MARK: - The verbs
    //
    // Fixed app-wide: Quarantine · Restore · Delete · Ignore. The two buttons on the sheet are
    // `FreeSpace.Says.setAsideOnly` and `.setAsideAndEmpty` — they are not a fifth and sixth verb,
    // they are the two routes John asked for, and their words are his.

    static let quarantine = "Quarantine"
    static let showInFinder = "Reveal in Finder"

    // MARK: - The batch

    static let batchHeading = "Ready to set aside"

    /// Above the tick list, said once.
    static let batchExplanation =
        "Tick what you want moved and press once. Everything here was written by this Mac and gets "
        + "written again when it is needed."

    static func batchButton(_ count: Int) -> String {
        count == 1 ? "Set Aside 1 Thing" : "Set Aside \(count) Things"
    }

    static let nothingTicked = "Nothing is ticked, so there is nothing to move."

    /// The one line that separates the two ceremonies for a reader, on the row where the batch is.
    static let thisOneIsABatch =
        "This is the only list on this screen with ticks on it."

    /// And its opposite, on every list of a person's own things.
    static let thisOneIsOneAtATime =
        "Nothing here is ticked and nothing here is chosen for you. Each one is its own decision."

    // MARK: - The sheet

    static func sheetTitle(_ item: Item) -> String { "Set aside “\(item.name)”?" }

    static let sheetSizes = "What it is, and what it would give you back"

    /// What the second route also removes, when the quarantine is not already empty. Said before
    /// the button rather than discovered afterwards.
    static func emptyingAlsoRemoves(_ summary: Quarantine.Summary) -> String {
        let items = summary.count == 1 ? "1 other item" : "\(summary.count) other items"
        return "The quarantine already holds \(items), \(StorageManifest.readable(summary.bytes)). "
             + "Emptying it removes those as well, for good."
    }

    // MARK: - Why something is on the ledger

    /// The reason written into the quarantine record when a person picks one of their own files.
    ///
    /// ⚠️ It has to still make sense in a month, on a row in a list, to somebody who has forgotten
    /// this screen. "Large" is not a reason a person would accept about their own file — they chose
    /// it, and that is the whole of it.
    static let becauseYouChoseIt = "You chose to set this aside from Storage."

    // MARK: - The face

    static let notScannedYet = "Nothing has been scanned yet"

    static let whatTheScanDoes =
        "Press \(SectionID.storage.verb) and Wellkept will read how much room is left, size what is "
        + "using it, and look for things this Mac made and will make again. It reads; it moves "
        + "nothing until you press a button that says it will."

    /// ⚠️ Honest, not theatrical, and it names no number of seconds. Measured at 56.7 seconds for
    /// 983,868 files on this Mac — and with Full Disk Access granted it gets slower, because the
    /// folders it was refused are folders it would then walk.
    static let howLongItTakes =
        "It takes about a minute on a full disk, and it says where it is looking as it goes."

    static let scanning = ScanPolicy.Running.verb

    static let cancel = "Stop"
}

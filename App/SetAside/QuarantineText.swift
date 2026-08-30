// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import WellkeptCore

//  QuarantineText.swift
//  Wellkept — App/SetAside
//
//  ⭐ **Every sentence a person reads about quarantine that is not already in the engine.**
//
//  `QuarantineWords` (App/Quarantine/Quarantine.swift) holds the four settled sentences
//  himself, and `Report.sentence`, `RestoreReport.sentence`, `DeleteReport.sentence` and
//  `Summary.rowSentence` are already written and ready to display. **Those are used verbatim and
//  never re-composed here.** This file is only what a screen needs on top of them: a row's age
//  line, a confirmation's title and consequence, the verbs.
//
//  It exists so that the Storage section — which will own this screen when it is built — inherits
//  the words instead of writing its own set. That is not tidiness: two screens describing the same
//  quarantine in different words is how one of them ends up describing it wrongly.
//
//  ## ⚠️ The word that may never appear
//
//  **"Freed."** Setting 391 MB aside across 100,000 files moved free space by −8 KiB, measured
//  2026-08-28: a same-volume rename re-points an inode and no bytes move. `QuarantineWordsTests`
//  fails the build on it, on "reclaim", and on "recovered space". After a real delete the figure is
//  measured before and after and reported as what came back — which is `DeleteReport.sentence`'s
//  job, not this file's.
//
//  ## ⚠️ Why "days left" is two different sentences
//
//  In **manual** — the default — nothing is removed at thirty days. The item rises to the top of
//  the list and waits, for ever if nobody acts. Saying "27 days left" there would promise a
//  deletion the app has no intention of performing. In **auto** the person asked for exactly that
//  deletion, so the countdown is the truth. One sentence for both would have to be wrong in one of
//  them.

enum QuarantineText {

    // MARK: - The verbs
    //
    // Fixed app-wide: Quarantine · Restore · Delete · Ignore. "Empty" is not a fifth verb — it is
    // Delete applied to everything at once, and it is worded as its own button only because the
    // thing it acts on is the quarantine rather than one item in it.

    static let restore = "Restore"
    static let delete = "Delete"
    static let empty = "Empty Quarantine"
    static let stopIgnoring = "Stop Ignoring"

    // MARK: - The page

    /// What the screen is, said once at the top.
    ///
    /// The sequence is the thing worth carrying: set aside → nothing on the Mac changes size →
    /// empty the quarantine → the space comes back. A person who does not know that reads a Mac
    /// that did not change as an app that did not work.
    /// ⚠️ **Not "Wellkept never deletes anything."** That was the first draft, and it sat directly
    /// above a column of Delete buttons. The promise is that nothing is deleted *by the app, on its
    /// own* — the person deletes, deliberately, having looked. A sentence a reader can disprove by
    /// glancing six inches down the same screen costs more than it buys.
    static let whatThisIs =
        "Nothing here has been deleted. Whatever Wellkept sets aside is moved to a folder on the "
        + "same disk and waits — for \(Expiry.days) days, or until you put it back or remove it "
        + "yourself. Nothing on this Mac gets smaller until you empty the quarantine."

    /// The empty state, which is the ordinary one.
    static let nothingIsSetAside = "Nothing is set aside."

    static let nothingIsSetAsideWhy =
        "Nothing has been set aside, so there is nothing to put back and nothing to remove. This is "
        + "where anything Wellkept sets aside for you will appear."

    // MARK: - One row

    /// The age line: how long it has been here, and what happens next, in the mode that is actually
    /// set. See the header for why this is not one sentence.
    static func life(_ record: QuarantineRecord,
                     mode: ExpiryMode,
                     now: Date = Date(),
                     calendar: Calendar = .current) -> String {
        // `ageSentence` already says "ready to remove" for anything past thirty days, in both
        // modes, and a countdown beside it would be a second answer to the same question.
        if Expiry.isReady(record, now: now, calendar: calendar) {
            return Expiry.ageSentence(record, now: now, calendar: calendar)
        }
        let age = Expiry.ageSentence(record, now: now, calendar: calendar)
        let left = Expiry.daysLeft(record, now: now, calendar: calendar)
        let days = left == 1 ? "1 day" : "\(left) days"
        switch mode {
        case .manual:
            return "\(age) Ready to remove in \(days)."
        case .auto:
            return "\(age) Wellkept removes it in \(days)."
        }
    }

    /// The path with the home folder written as `~`, which is how a person thinks of it.
    ///
    /// ⚠️ **Shortened, never hidden.** A row without a path is a row that cannot tell two files
    /// called `Cache.db` apart, and somebody deciding whether to put something back needs to see
    /// where it would go. The full string is still on the row as its tooltip and is still
    /// selectable.
    static func shortPath(_ path: String, home: URL = StorageManifest.home()) -> String {
        let root = home.path(percentEncoded: false)
        guard path.hasPrefix(root + "/") else { return path }
        return "~" + path.dropFirst(root.count)
    }

    /// Who set it aside and why — the two things a person needs to recognise a file they have not
    /// thought about for a month.
    ///
    /// The section is named because a row could have come from any of six places, and "why" without
    /// "who said so" is an assertion with no author.
    static func origin(_ record: QuarantineRecord) -> String {
        guard let section = record.section else { return record.reason }
        return "\(section.title) · \(record.reason)"
    }

    /// A record whose file is not where the ledger says it is.
    ///
    /// ⚠️ Never hidden and never quietly dropped from the list. It is the evidence that something
    /// outside Wellkept moved the file, and the record is the only surviving statement of where it
    /// came from.
    static let noLongerThere =
        "This is not where Wellkept put it. Something other than Wellkept moved or removed it — "
        + "Wellkept cannot put it back, and Delete now only clears the record."

    // MARK: - The two confirmations

    /// ⚠️ **Names the specific thing**, per DESIGN §10, and carries exactly one consequence
    /// sentence because there is no undo. No other body text.
    static func deleteConfirmation(_ record: QuarantineRecord) -> (title: String, message: String) {
        ("Delete “\(record.originalName)”?",
         "It is removed from this Mac for good, and Wellkept can no longer put it back. This "
         + "cannot be undone.")
    }

    /// What Empty will actually remove, counted and sized, before the button is pressed.
    static func emptyConfirmation(count: Int, bytes: Int64) -> (title: String, message: String) {
        let items = count == 1 ? "1 item" : "\(count) items"
        return ("Empty the quarantine?",
                "This removes \(items), \(StorageManifest.readable(bytes)), from this Mac for good. "
                + "Wellkept can no longer put any of them back. This cannot be undone.")
    }

    // MARK: - The ignore list

    static let ignoreListTitle = "Ignored"

    static let ignoreListBlurb =
        "Things you told Wellkept to stop raising. Nothing here was moved, changed or deleted — an "
        + "ignored item is a statement about what Wellkept will mention, not about the file. Stop "
        + "ignoring one and it can be reported again."

    static let ignoreListEmpty = "You have not told Wellkept to ignore anything."

    static func ignoredOn(_ item: IgnoredItem) -> String {
        "Ignored \(ShortDate.stamp(item.ignoredOn))"
    }
}

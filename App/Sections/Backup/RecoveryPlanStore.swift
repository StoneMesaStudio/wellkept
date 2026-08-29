// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import WellkeptCore

//  RecoveryPlanStore.swift
//  Wellkept — App/Sections/Backup
//
//  **Remembering that a page was printed, and what it said.**
//
//  ## Why this file exists at all
//
//  The Recovery Plan is the one thing in this section that is not software: it is a page somebody
//  prints and puts in a drawer. Wellkept cannot see the drawer. What it *can* do is remember that
//  the page was made, and which macOS it was made for — and that second fact is the whole reason
//  the record is worth keeping. **Migration Assistant refuses a backup made on a newer macOS than
//  the machine being restored to**, so a page written for 26.6.2 is describing a different world
//  once this Mac is on 26.7. `RecoveryPlan.reprintLine(currentMacOS:)` says so, and it can only be
//  asked when there is a stored page to ask about.
//
//  ⛔ **There is no secret in this file and there is nowhere in it to put one.** `RecoveryBlank`
//  carries a label and a place to look, and no value — the FileVault recovery key, the Apple
//  Account password and the backup drive's password are hand-written on paper and never touch this
//  app. A test asserts the field list, and it is asserted again here in the only other place a
//  value could have leaked into: what gets written to disk.
//
//  ## What is recorded, and what is not
//
//  The page as it stood at the moment it was printed. Not "the newest page" and not "the page as it
//  would be today" — the point of the record is to describe the piece of paper that actually
//  exists, so that a Mac which has since been updated can say the paper is out of date. Rebuilding
//  the plan from today's facts and calling that the record would make the staleness check answer
//  "still current" every single time.

enum RecoveryPlanStore {

    /// The page on record, or `nil` if nobody has printed one.
    ///
    /// ⚠️ A missing or unreadable file is `nil`, never an error. Somebody who has never printed the
    /// page and somebody whose record was lost are in the same position — no paper — and the screen
    /// says the same true thing to both.
    static func read(at url: URL = StorageManifest.recoveryPlanRecord()) -> RecoveryPlan? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.wellkept.decode(RecoveryPlan.self, from: data)
    }

    /// Write down that this page was printed.
    ///
    /// Atomic, so a crash mid-write leaves the previous record rather than a half-written file that
    /// decodes to nothing. Returns whether it stuck — the caller says so on the screen rather than
    /// claiming a page was remembered when it was not.
    @discardableResult
    static func record(_ plan: RecoveryPlan,
                       at url: URL = StorageManifest.recoveryPlanRecord()) -> Bool {
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder.wellkeptPretty.encode(plan) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

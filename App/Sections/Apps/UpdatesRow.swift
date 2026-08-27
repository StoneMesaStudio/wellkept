import Foundation
import WellkeptCore

//  UpdatesRow.swift
//  Wellkept — App/Sections/Apps
//
//  **The `.updates` row — the one place in the app that says how many apps have a newer version.**
//
//  ## ⚠️ The count never appears without its denominator, and this file is where that is kept
//
//  `UpdateTally` has exactly one initialiser and it takes the coverage, so a bare count cannot be
//  constructed. This file is the other half of the same guard: the row's **headline** is
//  `tally.sentenceWithCoverage`, which welds the count, the number of apps actually checked, the
//  apps that could not be checked and the apps that look after themselves into one sentence.
//
//  So the coverage is **not** behind Options, is **not** a footnote, and is not something a later
//  edit can drop by deleting a line — deleting it deletes the row's answer. On the measured Mac it
//  reads: *"2 of the 6 apps we could check have a newer version. 3 more apps could not be checked.
//  4 apps keep themselves up to date."*
//
//  ## ⚠️ "Keeps itself up to date" and "cannot be checked" are opposite messages
//
//  Four apps on the measured Mac are on `SelfUpdatingApps`' list. Folding them into the "could not
//  be checked" caveat turns a well-kept Applications folder into a neglected-looking one, and each
//  of those apps' own lines two inches below says the opposite. `UpdateCoverage` counts them
//  separately; this file never re-adds them.
//
//  ## ⚠️ Nothing here is a fault
//
//  `AppsRow.severity` is a computed constant, so there is no argument this file could pass that
//  would colour the row. Without vulnerability data, a version behind is not something wrong — it
//  is a fact, and it is stated as one. See rule 4 in `Apps.swift`.

enum UpdatesRow {

    /// The row.
    ///
    /// - Parameters:
    ///   - inventory: the inventory **after** the standings have been applied. Coverage and the
    ///     tally are derived from it, so they cannot disagree with the app lines below them.
    ///   - update: what the reader did, including the answer that was in force.
    static func row(inventory: AppsInventory, update: UpdateReader.Answer) -> AppsRow {
        guard update.consent == .allowed else {
            return notChecked(inventory: inventory, update: update)
        }

        let tally = inventory.tally

        return AppsRow(topic: .updates,
                       headline: tally.sentenceWithCoverage,
                       measure: measure(tally),
                       reason: reason(inventory: inventory, update: update),
                       details: details(inventory: inventory, update: update))
    }

    // MARK: - Nobody was asked, or the answer was no

    /// ⚠️ **Not an `Unreadable`, and that distinction is the whole point of the switch.**
    ///
    /// Nothing refused us and nothing failed. Somebody was asked a question and answered it, and
    /// dressing their answer up as a machine's refusal would put a "we could not look" chip on a
    /// section that is working exactly as they asked. The row says what is off and where the switch
    /// is, in the words the privacy register already owns.
    private static func notChecked(inventory: AppsInventory,
                                   update: UpdateReader.Answer) -> AppsRow {
        let headline = update.consent == .declined
            ? "Update checking is off, so nothing here was checked."
            : "Nothing has been checked for a newer version yet."

        // ⚠️ **The account of what was sent is NOT repeated here.** It is drawn under the row by
        // the screen, from `UpdateReader.Answer.disclosureSentence` — the one sentence that says
        // exactly which app names left this Mac, and on a Mac where checking is off it says none
        // did. Putting it in the reason as well printed it twice, one line apart. DESIGN §8.
        let reason = UpdateConsent.departure.cost + " " + (update.consent == .declined
            ? "You can switch it back on in Settings, under Permissions."
            : "Wellkept will ask before it checks anything.")

        return AppsRow(topic: .updates,
                       headline: headline,
                       measure: nil,
                       reason: reason,
                       details: [
                        DetailPair("Apps installed", "\(inventory.apps.count)"),
                        DetailPair("Checked for a newer version", "None"),
                        DetailPair(UpdateConsent.departure.title, UpdateConsent.departure.whatLeaves),
                       ])
    }

    // MARK: - The figure

    /// **"2 of 6" — a count and its denominator, in one figure, or nothing at all.**
    ///
    /// ⚠️ Never a bare `newerAvailable`. A large "2" beside a sentence about coverage is the number
    /// a person carries away, and on its own it claims a completeness the section does not have.
    /// Where nothing could be checked there is no honest figure, so there is none.
    static func measure(_ tally: UpdateTally) -> String? {
        guard tally.coverage.checked > 0 else { return nil }
        return "\(tally.newerAvailable) of \(tally.coverage.checked)"
    }

    // MARK: - Why it says that

    /// The reasons the unchecked apps are unchecked, named rather than shrugged at, plus what was
    /// sent.
    ///
    /// ⚠️ **`UpdateUnknown` is a closed list precisely so this sentence can exist.** "We could not
    /// tell about 11 apps" is a shrug; "nothing publishes a current version for 9 of them, and 2
    /// have version numbers that cannot be compared reliably" is a fact somebody can disagree with.
    static func reason(inventory: AppsInventory, update: UpdateReader.Answer) -> String {
        var parts: [String] = []

        let counts = unknownCounts(inventory.apps)
        if !counts.isEmpty {
            let clauses = counts.map { clause(for: $0.reason, count: $0.count) }
            parts.append("Where we could not tell: \(clauses.formatted(.list(type: .and))).")
        }

        // The honest cost of the decision of 2026-08-27 not to ship a hand-kept list of makers'
        // version pages, said in the section it costs something in rather than buried in a document.
        if counts.contains(where: { $0.reason == .noSourceToAsk }) {
            parts.append("Wellkept asks Apple's App Store and reads Homebrew's own records. It does "
                       + "not keep a list of makers' download pages, because a list like that goes "
                       + "stale and a stale answer is worse than none.")
        }

        // ⚠️ **What was actually sent is not said here**, and that is not an omission. It is drawn
        // under the row by the screen, from `UpdateReader.Answer.disclosureSentence`, which names
        // every app whose name left this Mac. It was in both places once, and the two paragraphs
        // sat one line apart saying the same thing.
        return parts.joined(separator: " ")
    }

    /// One reason, counted, as a clause that can be joined into a list.
    ///
    /// ⚠️ Written here rather than taken from `UpdateUnknown.label`, which is a sentence about **one
    /// app** — "Nothing publishes a current version for this app". Pluralised naively that becomes
    /// "9 because nothing publishes a current version for this app", which is English nobody wrote
    /// on purpose. The three in-scope reasons are a closed set, so three clauses is the whole cost.
    static func clause(for reason: UpdateUnknown, count: Int) -> String {
        let one = count == 1
        switch reason {
        case .noSourceToAsk:
            return one ? "one has nowhere that publishes a current version"
                       : "\(count) have nowhere that publishes a current version"
        case .versionsNotComparable:
            return one ? "one has version numbers that cannot be compared reliably"
                       : "\(count) have version numbers that cannot be compared reliably"
        case .askFailed:
            return one ? "one was asked about and gave no usable answer"
                       : "\(count) were asked about and gave no usable answer"
        case .testFlightBuild, .shipsWithMacOS:
            // Filtered out before this is reached — they are questions that do not apply rather
            // than gaps. Kept exhaustive so a sixth reason cannot be added without a clause.
            return one ? "one does not apply" : "\(count) do not apply"
        }
    }

    /// How many apps carry each reason, in `UpdateUnknown.allCases` order, zeroes dropped.
    ///
    /// ⚠️ Only the reasons that are **in scope**. A TestFlight build and an app that ships with
    /// macOS are not gaps in our coverage — they are questions that do not apply — and listing them
    /// here would read as four more failures. Their own lines say what they are.
    static func unknownCounts(_ apps: [InstalledApp]) -> [(reason: UpdateUnknown, count: Int)] {
        UpdateUnknown.allCases.filter(\.isInScope).compactMap { reason in
            let n = apps.filter { $0.update == .couldNotTell(reason) }.count
            return n > 0 ? (reason, n) : nil
        }
    }

    // MARK: - Everything exact, behind Options

    static func details(inventory: AppsInventory, update: UpdateReader.Answer) -> [DetailPair] {
        let apps = inventory.apps
        let coverage = inventory.coverage
        var rows: [DetailPair] = [
            DetailPair("Apps a check makes sense for", "\(coverage.checkable) of \(apps.count)"),
            DetailPair("Apps we could actually check", "\(coverage.checked)"),
        ]

        let newer = apps.filter { $0.update.hasNewerVersion }
        if !newer.isEmpty {
            rows.append(DetailPair("A newer version is available for",
                                   newer.map(\.name).sorted().formatted(.list(type: .and))))
        }

        // Named, and named as the opposite of a gap. See the file header.
        let selfUpdating = apps.filter { $0.update == .keepsItselfUpToDate }
        if !selfUpdating.isEmpty {
            rows.append(DetailPair("Keep themselves up to date",
                                   selfUpdating.map(\.name).sorted().formatted(.list(type: .and))))
        }

        for entry in unknownCounts(apps) {
            let names = apps.filter { $0.update == .couldNotTell(entry.reason) }
                .map(\.name).sorted().formatted(.list(type: .and))
            rows.append(DetailPair(entry.reason.label, names))
        }

        // Out of scope rather than unchecked, and said with the reason so the two are never read as
        // the same thing.
        for reason in UpdateUnknown.allCases where !reason.isInScope {
            let names = apps.filter { $0.update == .couldNotTell(reason) }.map(\.name).sorted()
            if !names.isEmpty {
                rows.append(DetailPair(reason.label, names.formatted(.list(type: .and))))
            }
        }

        rows.append(DetailPair("Homebrew casks read", "\(update.casksRead)"))
        // "What left this Mac" is deliberately absent: it is on the row itself, above, and again in
        // the section's own audit block at the bottom of Options. A third copy in between is the
        // same sentence three times on one page.
        rows.append(DetailPair("What Wellkept never does",
                               "It never asks anybody to verify an app, never sends anything about "
                             + "you or this Mac, and never checks unless you have said it may."))
        return rows
    }
}

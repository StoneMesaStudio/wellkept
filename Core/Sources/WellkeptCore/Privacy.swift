import Foundation

//  Privacy.swift
//  WellkeptCore
//
//  ⭐ **The privacy sentences, in one place, for the whole app.**
//
//  ## Why this file exists
//
//  Until 2026-08-27 the welcome page said **"Nothing leaves your Mac."** That was Claude's wording,
//  not John's, and John struck it:
//
//  > *"it is about not scraping user data, violating their privacy or collecting contact
//  > information for marketing. No data is collected and sold. Information leaving the computer to
//  > benefit their experience and app functionality is disclosed and optional, but just like not
//  > granting whole disc access, you lose functionality. **Inform and consent**."*
//
//  The old sentence had already grown an "except" clause on the welcome page, a different "except"
//  clause in Help, and no clause at all in Settings — three places, three promises, drifting apart.
//  Then the Apps section arrived and needed to ask Apple and a handful of makers whether an app has
//  a newer version, which the absolute promise forbids outright.
//
//  **An absolute promise we break in the Apps section is worse than an honest conditional one.** So
//  the shape is fixed: say what is never done, then name every single thing that does leave, then
//  say that each one has a switch and what switching it off costs. Nothing is buried, nothing is
//  implied, and no reader has to take a general assurance on faith.
//
//  ## The rule for every future section
//
//  ⚠️ **Nowhere else in this app writes its own version of these sentences.** Not Help, not
//  Settings, not the welcome page, not a section that later wants to send something. `Departure` is
//  the register: **something that leaves this Mac and is not in it does not ship.** Adding a case
//  is the moment somebody has to write down what is sent, who receives it, what it buys the user
//  and what switching it off costs — which is exactly the conversation that would otherwise be
//  skipped.
//
//  A grep for "nothing leaves" across the repo should find only this note, the tests that guard
//  against the phrase, and the comments in the four files that used to carry it. If it ever turns up
//  in a string a person can read, the promise has come back.

// MARK: - What is never done

/// The privacy vocabulary. Nothing here is a view; the words are the point.
public enum Privacy {

    // MARK: The promise that is absolute, because it is true

    /// **The things Wellkept never does, under any setting.**
    ///
    /// ⚠️ Every line here is unconditional, and each one is unconditional because it is *actually*
    /// true — that is the whole difference between this list and the sentence it replaced. Nothing
    /// in this app collects anything, nothing is sold, there is no account, no identifier, no
    /// analytics and no marketing. Those promises need no "except", and if one of them ever does,
    /// it does not belong on this list.
    public static let neverDone: [String] = [
        "Nothing about you is collected. Not what is on this Mac, not what Wellkept found, not how you use it.",
        "Nothing is ever sold, shared or handed to anybody. There is no business here that works that way.",
        "There is no account and no sign-in. Wellkept never asks who you are.",
        "You are given no identifier of any kind, and nothing counts you.",
        "There is no analytics, no telemetry and no crash reporting.",
        "Your email address is never asked for, and nothing here feeds a mailing list.",
    ]

    /// The same promise in one sentence, for a place with room for one line.
    ///
    /// ⚠️ Use this rather than writing a shorter version. "Wellkept collects nothing" on its own
    /// reads as the absolute claim this file exists to retire — the second half is what makes the
    /// first half honest.
    public static let headline = String(localized: """
        Wellkept collects nothing about you and sells nothing to anybody. Two things do leave this \
        Mac, both listed below, and each one can be switched off.
        """)

    /// What the departures list means, said once above it.
    public static let departuresIntro = String(localized: """
        Here is everything that leaves this Mac, and there is nothing else. Each one buys you \
        something, each one has a switch, and switching one off costs you that and nothing else.
        """)

    // MARK: - Everything that leaves this Mac

    /// **Every single thing Wellkept sends anywhere. Today there are two.**
    ///
    /// ⚠️ **This enum is the register, and it is enforcement rather than documentation.** A section
    /// that wants to send something adds a case here first. That forces four answers onto the record
    /// — what is sent, who receives it, what the user gets for it, and what turning it off costs —
    /// and it makes the welcome page grow a line automatically, so nothing can be added quietly.
    ///
    /// Raw values are storage and are permanent; the labels are English and John edits them freely.
    public enum Departure: String, CaseIterable, Sendable, Identifiable, Codable, Hashable {

        /// Asking Apple's storefront, and a small number of makers, whether an app has a newer
        /// version.
        case appUpdateCheck

        /// Asking Stone Mesa Studio whether a newer Wellkept exists.
        case wellkeptUpdateCheck

        public var id: String { rawValue }

        /// The switch's name, as it appears in Settings and on the welcome page.
        public var title: String {
            switch self {
            case .appUpdateCheck:      String(localized: "Checking whether your apps are current")
            case .wellkeptUpdateCheck: String(localized: "Checking whether Wellkept has an update")
            }
        }

        /// **What actually goes out, and to whom.** Specific, not reassuring.
        ///
        /// ⚠️ The app-update line says the unavoidable part out loud: to ask whether a newer version
        /// of an app exists, we have to ask the people who make it, and that necessarily tells them
        /// a copy is installed somewhere. It is not a leak, it is arithmetic — but a person deciding
        /// whether to leave this on deserves to be told rather than to work it out.
        public var whatLeaves: String {
            switch self {
            case .appUpdateCheck:
                String(localized: """
                    Wellkept asks Apple's App Store, and a small number of makers, what the current \
                    version of an app is. Asking necessarily tells them a copy is installed \
                    somewhere. Nothing about you or about this Mac goes with the question.
                    """)
            case .wellkeptUpdateCheck:
                String(localized: """
                    Wellkept asks Stone Mesa Studio whether a newer Wellkept exists, and sends the \
                    version it is now. Nothing about you or about this Mac goes with the question.
                    """)
            }
        }

        /// **What switching it off costs — that feature, and nothing else.**
        ///
        /// This is the half of "inform and consent" that usually goes missing. A switch with no
        /// stated cost is a switch people flip out of caution and then wonder why the app got worse,
        /// which is precisely what happens with Full Disk Access.
        public var cost: String {
            switch self {
            case .appUpdateCheck:
                String(localized: """
                    Off, the Apps section still lists everything installed and what each app is. It \
                    just says it does not know whether any of them is current, rather than telling \
                    you.
                    """)
            case .wellkeptUpdateCheck:
                String(localized: """
                    Off, Wellkept will not tell you when a new version comes out. Everything else \
                    works exactly the same.
                    """)
            }
        }

        /// The `UserDefaults` key holding the answer. Named here so Settings, the welcome page and
        /// the section that does the sending cannot each invent one.
        ///
        /// ⚠️ **Stored as an optional Bool, and "not set" is a real third state** — it means nobody
        /// has been asked yet. That is what makes this inform-and-consent rather than a default
        /// nobody was told about: `appUpdateCheck` is unset until the first time Apps runs, when the
        /// section says what checking involves and offers to do it or not. A missing key must never
        /// be read as `true`.
        public var settingsKey: String {
            switch self {
            case .appUpdateCheck:      "checkAppUpdates"
            case .wellkeptUpdateCheck: "checkWellkeptUpdates"
            }
        }

        /// The three sentences, as detail pairs, for Help and Settings — so those two pages cannot
        /// present the same fact two different ways.
        public var detailPairs: [DetailPair] {
            [DetailPair(String(localized: "What leaves"), whatLeaves),
             DetailPair(String(localized: "If you switch it off"), cost)]
        }
    }

    // MARK: - The sentence for a place with one line

    /// **The one-line version, for a screen that has room for a sentence and not a page.**
    ///
    /// Used by Settings ▸ Permissions and by the Full Disk Access notice. It says what those screens
    /// are actually about — reading — and points at the register rather than making a claim that
    /// competes with it.
    public static let readingOnly = String(localized: """
        Wellkept only reads. Nothing it reads about this Mac is collected, kept anywhere but this \
        Mac, or sent to anybody.
        """)

    /// The line for the README and for anywhere describing the app from outside.
    public static let summaryLine = String(localized: """
        Nothing is collected and nothing is sold. Two things leave this Mac — a check for newer \
        versions of your apps, and a check for a newer Wellkept — both disclosed, both optional.
        """)
}

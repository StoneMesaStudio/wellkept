// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import AppKit
import Foundation
import WellkeptCore

//  LeftoverReader.swift
//  Wellkept — App/Apps
//
//  **What an app that is gone left behind — and the twenty-fold lie every cleaner tells about it.**
//
//  ## ⚠️ Read this before changing anything below
//
//  This is the single most dangerous screen in the product. It is the one where being wrong costs
//  somebody their work, and it is the one every other Mac cleaner gets wrong in the same direction,
//  because the wrong answer is a bigger number and a bigger number sells.
//
//  Measured on one real Mac, 2026-08-27, read-only:
//
//  | How you decide what is a leftover | What it finds here | What is actually orphaned |
//  |---|---|---|
//  | Match folder names against app names — what cleaners do | **7.6 GB** | ~350 MB |
//  | Match bundle identifiers, with the seven guards below | **28.6 MB** | 28.6 MB |
//
//  **95% of the name-matched figure belongs to software that is running right now.** Three of the
//  traps on this one Mac:
//
//  - **`~/Library/Application Support/Herd` has no app, no Spotlight entry, and looks like textbook
//    dead weight. It is a working PHP and Composer install** — the thing somebody's working day
//    runs on. It is safe here for one reason: **"Herd" is not a bundle identifier**, so this file
//    never looks at it. That is not luck, it is the rule.
//  - **Six "orphaned browser profiles" belong to an extension that is installed and working.** They
//    are filed under `com.khanov.BlockerX.…`, and the app is 1Blocker, whose identifier is
//    `com.khanov.BlockerX`. Guard 4 catches them.
//  - **Chrome's own updater lives at `com.google.Keystone.Agent`** with no app of its own, while
//    Chrome is `com.google.Chrome`. Guard 5 — same publisher — is the only thing between that
//    folder and a person whose Chrome quietly stops updating.
//
//  And the one that decides the shape of the type: **Chrome's provable files come to 5.8 MB. The
//  real figure is about 5.9 GB, in a folder called "Google" that matches neither the app's name nor
//  its identifier.** There is therefore **no section-wide total anywhere in this file**, and
//  `Leftover` in `WellkeptCore` deliberately offers none. A single number covering "this app and
//  everything it owns" would be a guess dressed as a fact, and it is exactly the number that goes
//  in a big font on somebody else's screen.
//
//  ## The two-sided test
//
//  A candidate has to pass **both** halves, and each half kills a different wrong answer:
//
//  1. **Was it ever an app?** Only four places on this Mac are made by macOS for an app —
//     see `Place.provesAnAppWasHere`. A preferences file proves nothing: anybody's shell script can
//     write one. On this Mac that single rule removes CUPS's printing preferences, Swift Package
//     Manager's cache and twelve throwaway test containers, none of which was ever an app and none
//     of which will ever have one.
//  2. **Is it gone?** LaunchServices — macOS's own register of what is installed — has no app for
//     the identifier, no installed app owns it as a component, no app from the same publisher is
//     here, and nothing is running under it.
//
//  ## ⚠️ We would rather miss one than be wrong about one
//
//  Guard 5 (same publisher) is blunt. A genuinely removed Microsoft app will be missed on a Mac
//  with Word installed. That is the intended error: the cost of missing one is a line nobody sees,
//  and the cost of being wrong is Chrome's updater. The row says plainly that it only lists what it
//  can prove, so the number is never presented as the whole truth.
//
//  ## ⚠️ Nothing is offered for removal this round
//
//  Removal needs the quarantine engine — 30-day undo, nothing ever deleted — and that does not
//  exist. The row says so in its own words rather than leaving a disabled button to be explained.
//  What the removal half will need is declared in `Removal` below, so this screen is not torn up
//  when it arrives.
//
//  ## What it costs to run
//
//  Eight directory listings and a size walk per surviving candidate. Measured at well under a tenth
//  of a second on this Mac.

enum LeftoverReader {

    // MARK: - What one run produced

    struct Answer: Sendable, Hashable {
        let row: AppsRow
        /// The removed apps, largest first where we could weigh them. **Empty is a fine answer.**
        let leftovers: [Leftover]
    }

    // MARK: - ⭐ Where we look, and what a place proves

    /// The eight places in `~/Library` where files are filed under an app's bundle identifier.
    ///
    /// ⚠️ **`provesAnAppWasHere` is the important column.** Four of these are folders macOS itself
    /// creates on an app's behalf; the other four are places any process at all can write,
    /// including a shell script and a command-line tool. A name appearing only in the second group
    /// is not evidence that an app was ever installed, and treating it as evidence is how a health
    /// check starts offering to delete Swift Package Manager.
    enum Place: String, Sendable, Hashable, CaseIterable, Identifiable, Codable {

        /// `~/Library/Containers/<id>` — the sandbox macOS builds for an app or its extensions.
        case containers

        /// `~/Library/Saved Application State/<id>.savedState` — macOS reopening an app's windows.
        case savedApplicationState

        /// `~/Library/Application Support/<id>` — where an app keeps what it made.
        case applicationSupport

        /// `~/Library/WebKit/<id>` — made for an app that showed web content.
        case webKit

        /// `~/Library/Preferences/<id>.plist` — **anybody can write one of these.**
        case preferences

        /// `~/Library/Caches/<id>` — anybody can write one of these too.
        case caches

        /// `~/Library/HTTPStorages/<id>` — cookies and cached responses, from any process.
        case httpStorages

        /// `~/Library/Logs/<id>` — a log folder, from any process.
        case logs

        var id: String { rawValue }

        /// The path under `~/Library`.
        var directory: String {
            switch self {
            case .containers:           "Containers"
            case .savedApplicationState: "Saved Application State"
            case .applicationSupport:   "Application Support"
            case .webKit:               "WebKit"
            case .preferences:          "Preferences"
            case .caches:               "Caches"
            case .httpStorages:         "HTTPStorages"
            case .logs:                 "Logs"
            }
        }

        /// What is added to the identifier to make the entry's name, where anything is.
        var suffix: String? {
            switch self {
            case .savedApplicationState: ".savedState"
            case .preferences:           ".plist"
            default:                     nil
            }
        }

        /// The words on the row: what this place is, not where it is.
        var label: String {
            switch self {
            case .containers:            "Its sandbox folder"
            case .savedApplicationState: "Its saved windows"
            case .applicationSupport:    "Its own files"
            case .webKit:                "Its web data"
            case .preferences:           "Its settings"
            case .caches:                "Its cache"
            case .httpStorages:          "Its cookies"
            case .logs:                  "Its logs"
            }
        }

        /// Draw order, so a group's paths read the same way twice.
        var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

        /// ⚠️ **Whether merely LISTING this folder raises the macOS privacy dialog.**
        ///
        /// `~/Library/Containers` and `~/Library/Group Containers` hold other apps' sandboxed data,
        /// and macOS gates them behind *"would like to access data from other apps"* — which it
        /// shows on the **attempt**, not on the failure. So a speculative read to find out whether
        /// we are allowed IS the harm: it puts an unexplained dialog on somebody's screen, named
        /// after whatever process asked.
        ///
        /// This is not theoretical. It happened twice on 2026-08-27 while this file was being
        /// written, both times naming *Xcode*, because the code ran under the test harness. The
        /// person at the keyboard had to be told to press Don't Allow. **Wellkept must never be the
        /// cause of one.** So: these places are visited only when Full Disk Access is ALREADY
        /// granted, and otherwise skipped without being touched. Everything else here is the user's
        /// own Library and needs no permission at all.
        var needsFullDiskAccess: Bool {
            switch self {
            case .containers: true
            default:          false
            }
        }

        /// ⚠️ **Whether macOS only makes this for a real app.** See the type note. `false` here
        /// does not mean the files are ignored — once an app is proven, everything filed under its
        /// identifier is listed. It means this place **on its own** is not proof.
        var provesAnAppWasHere: Bool {
            switch self {
            case .containers, .savedApplicationState, .applicationSupport, .webKit: true
            case .preferences, .caches, .httpStorages, .logs:                       false
            }
        }
    }

    // MARK: - One thing found in one place

    /// A single entry whose name is a bundle identifier.
    struct Candidate: Sendable, Hashable, Identifiable {
        /// The identifier exactly as the entry is named, with any suffix taken off.
        let identifier: String
        let place: Place
        let path: String
        /// What it weighs, where we were able to weigh it. **`nil`, never zero, when a walk was
        /// refused part-way.**
        let bytes: Int64?

        var id: String { path }

        init(identifier: String, place: Place, path: String, bytes: Int64? = nil) {
            self.identifier = identifier
            self.place = place
            self.path = path
            self.bytes = bytes
        }
    }

    // MARK: - ⭐ The seven guards

    /// **Why a candidate is not evidence that an app was removed.**
    ///
    /// Every one of these was written because of a real folder on a real Mac that a name-matching
    /// cleaner would have offered to delete. `nil` from `guarded(_:…)` is the only route to a
    /// `Leftover`.
    enum Guard: String, Sendable, Hashable, CaseIterable, Identifiable, Codable {

        /// The name is not a bundle identifier — "Herd", "Google", "Adobe".
        ///
        /// ⚠️ **This one guard is what keeps a working PHP installation safe.** A folder named
        /// after a company or a product tells us nothing about which app, if any, put it there.
        case notAnIdentifier

        /// It belongs to macOS: `com.apple.…`. macOS puts these back, and removing one changes the
        /// Mac rather than tidying it.
        case macOSOwnsIt

        /// A group container — `group.…`, `systemgroup.…`, or a team identifier prefix.
        ///
        /// ⚠️ **Shared between apps by design.** One of these can hold data for four apps of which
        /// three are installed. Wellkept does not look in that folder at all.
        case sharedBetweenApps

        /// macOS has an app with this identifier. It is installed; there is nothing left over.
        case theAppIsStillHere

        /// It is a component of an app that is installed — an extension, a helper, an XPC service.
        ///
        /// ⚠️ The six "orphaned browser profiles" on this Mac land here. They are 1Blocker's, and
        /// 1Blocker is running.
        case partOfAnAppThatIsStillHere

        /// An app from the same publisher is installed, so this may well be its updater, its
        /// helper, or a second copy of its data under a different name.
        ///
        /// ⚠️ Chrome's updater is `com.google.Keystone.Agent` and Chrome is `com.google.Chrome`.
        /// Nothing else catches that. Deliberately blunt — see the file header.
        case sameMakerAsAnInstalledApp

        /// Something is running under this identifier right now.
        case somethingIsRunningIt

        /// Nothing about it says an app was ever here — it exists only in places any process can
        /// write to. See `Place.provesAnAppWasHere`.
        case neverAnAppInTheFirstPlace

        var id: String { rawValue }

        /// Why we left it alone, for behind **Options**.
        var explanation: String {
            switch self {
            case .notAnIdentifier:
                "Its name is not an app identifier, so nothing tells us which app — if any — put it "
              + "there. A folder named after a company is not evidence of anything."
            case .macOSOwnsIt:
                "It belongs to macOS."
            case .sharedBetweenApps:
                "It is a shared folder. Apps that are still installed keep things in it."
            case .theAppIsStillHere:
                "The app is installed."
            case .partOfAnAppThatIsStillHere:
                "It is part of an app that is installed — an extension, a helper or a background "
              + "part of it."
            case .sameMakerAsAnInstalledApp:
                "An app from the same maker is installed, so this may be its updater or a second "
              + "place it keeps things."
            case .somethingIsRunningIt:
                "Something is running under this name right now."
            case .neverAnAppInTheFirstPlace:
                "Nothing about it says an app was ever here. It is only in places any program can "
              + "write to."
            }
        }
    }

    // MARK: - What one look produced

    struct Survey: Sendable, Hashable {
        /// Every bundle-identifier-shaped entry found. **`nil` where the Library could not be read
        /// at all**, which is not the same as a Mac with nothing left over.
        let candidates: [Candidate]?
        /// Entries we saw and did not treat as candidates because their names are not identifiers.
        /// Counted so the row can say how much it deliberately left alone.
        let notIdentifiers: Int
        /// Places we did not look in because they need Full Disk Access and it is not granted.
        /// **Not an error and not a zero** — the row says which places it could not see, which is
        /// the difference between "nothing was left behind" and "we did not look everywhere".
        let skipped: [Place]

        init(candidates: [Candidate]?, notIdentifiers: Int = 0, skipped: [Place] = []) {
            self.candidates = candidates
            self.notIdentifiers = notIdentifiers
            self.skipped = skipped
        }
    }

    // MARK: - The row

    /// Look at this Mac and build the row.
    ///
    /// - Parameter appsOnThisMac: the bundle identifiers of the apps this section lists,
    ///   lower-cased by this function. They are the first half of "is it gone"; LaunchServices is
    ///   the second, and it catches apps that live outside the four folders the inventory walks.
    /// ⚠️ `FullDiskAccess.isGranted` is read ONCE, here, and passed down. It probes a file we are
    /// allowed to attempt — it does not touch another app's container, which is the read that
    /// raises the privacy dialog. Never reverse that order.
    static func read(appsOnThisMac: Set<String>) -> Answer {
        answer(from: survey(fullDiskAccess: FullDiskAccess.isGranted),
               appsOnThisMac: appsOnThisMac,
               runningBundleIDs: runningBundleIDs(),
               isRegistered: isRegisteredWithLaunchServices,
               weigh: { weigh(URL(fileURLWithPath: $0.path)) })
    }

    /// The row, from a survey. **Pure** — every guard below can be tested from strings, on a build
    /// machine, with no Library to look at.
    ///
    /// ⚠️ **`weigh` runs after the guards, and that is not a tidiness point — it is why this row is
    /// fast.** The first version weighed every bundle-identifier-shaped folder in `~/Library` and
    /// then threw almost all of them away, which meant adding up Apple's own caches and every
    /// installed app's container: **it exceeded a two-minute test timeout on this Mac.** Only the
    /// handful of folders that survive all seven guards is ever walked, and that is under a tenth
    /// of a second. The default closure hands back whatever a test already put on the candidate, so
    /// the pure path stays pure.
    static func answer(from survey: Survey,
                       appsOnThisMac: Set<String>,
                       runningBundleIDs: Set<String>,
                       isRegistered: (String) -> Bool,
                       weigh: (Candidate) -> Int64? = { $0.bytes }) -> Answer {

        guard let candidates = survey.candidates else {
            return Answer(row: .unreadable(.removedLeftovers, .notPermitted,
                                           about: "What removed apps left behind",
                                           reason: "We could not read your Library folder, so we "
                                                 + "cannot say what is in it.",
                                           details: [howWeLooked],
                                           remedy: Remedy(title: "Open Privacy & Security",
                                                          settingsPane: "fullDiskAccess")),
                          leftovers: [])
        }

        var setAside: [Guard: Int] = [:]
        if survey.notIdentifiers > 0 { setAside[.notAnIdentifier] = survey.notIdentifiers }

        var kept: [Candidate] = []
        for candidate in candidates {
            if let why = guarded(candidate.identifier,
                                 appsOnThisMac: appsOnThisMac,
                                 runningBundleIDs: runningBundleIDs,
                                 isRegistered: isRegistered) {
                setAside[why, default: 0] += 1
            } else {
                kept.append(candidate)
            }
        }

        // Only now, on the few that survived, is anything weighed.
        var someSizesUnknown = false
        let weighed = kept.map { candidate -> Candidate in
            let bytes = weigh(candidate)
            if bytes == nil { someSizesUnknown = true }
            return Candidate(identifier: candidate.identifier,
                             place: candidate.place,
                             path: candidate.path,
                             bytes: bytes)
        }

        let (leftovers, unproven) = gather(weighed)
        if unproven > 0 { setAside[.neverAnAppInTheFirstPlace, default: 0] += unproven }

        let row = AppsRow(
            topic: .removedLeftovers,
            headline: headline(leftovers),
            measure: measure(leftovers),
            reason: reason(leftovers: leftovers, setAside: setAside),
            details: details(leftovers: leftovers,
                             someSizesUnknown: someSizesUnknown,
                             setAside: setAside)
        )
        return Answer(row: row, leftovers: leftovers)
    }

    // MARK: - ⭐ The guards, applied

    /// Identifiers macOS or a shared container uses. None of them is ever a removed app.
    static let reservedPrefixes = ["com.apple.", "group.", "systemgroup."]

    /// **Why we are leaving this identifier alone — or `nil` where it is a removed app's.**
    ///
    /// Order runs from cheapest and most certain to most judgemental, so the reason a person reads
    /// is the strongest one that applies.
    static func guarded(_ identifier: String,
                        appsOnThisMac: Set<String>,
                        runningBundleIDs: Set<String>,
                        isRegistered: (String) -> Bool) -> Guard? {
        let id = identifier.lowercased()

        // 1. Not an identifier at all. Two dots minimum: "Herd" and "Google" are not identifiers,
        //    and neither is "Adobe Photoshop 2024".
        guard isBundleIdentifier(identifier) else { return .notAnIdentifier }

        // 2. macOS's own.
        if reservedPrefixes.contains(where: { id.hasPrefix($0) }) {
            return id.hasPrefix("com.apple.") ? .macOSOwnsIt : .sharedBetweenApps
        }

        // 3. A team-identifier prefix — "UBF8T346G9.com.microsoft.teams". Shared, and not ours to
        //    reason about.
        if hasTeamPrefix(identifier) { return .sharedBetweenApps }

        let installed = Set(appsOnThisMac.map { $0.lowercased() })

        // 4. The app is installed, by our own list or by macOS's register.
        if installed.contains(id) { return .theAppIsStillHere }

        // 5. A component of an installed app.
        if installed.contains(where: { id.hasPrefix($0 + ".") }) { return .partOfAnAppThatIsStillHere }

        // 6. Something is running under it.
        if runningBundleIDs.contains(where: { $0.lowercased() == id }) { return .somethingIsRunningIt }

        // 7. Same publisher as something installed. Blunt on purpose — see the file header.
        let maker = publisher(of: id)
        if !maker.isEmpty, installed.contains(where: { publisher(of: $0) == maker }) {
            return .sameMakerAsAnInstalledApp
        }

        // 8. macOS's own register, which knows about apps outside the folders we walk. Last because
        //    it is the only rule that costs anything.
        if isRegistered(identifier) { return .theAppIsStillHere }

        return nil
    }

    /// Reverse-DNS with at least three parts: `de.beyondco.herd`, not `Herd` and not `beyondco.herd`.
    ///
    /// ⚠️ Three parts rather than two. Two-part names ("org.swift", "wb.tests") are as often a
    /// namespace as an app, and the shape an app identifier actually takes is three.
    static func isBundleIdentifier(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
    }

    /// "UBF8T346G9.com.microsoft.teams" — an Apple team identifier is ten upper-case letters and
    /// digits, and what follows it is a shared container rather than an app's own folder.
    static func hasTeamPrefix(_ identifier: String) -> Bool {
        guard let first = identifier.split(separator: ".").first else { return false }
        guard first.count == 10 else { return false }
        return first.allSatisfy { $0.isNumber || ($0.isLetter && $0.isUppercase) }
    }

    /// The maker, as the first two parts: `com.google.Chrome` → `com.google`.
    static func publisher(of identifier: String) -> String {
        let parts = identifier.lowercased().split(separator: ".")
        guard parts.count >= 2 else { return "" }
        return parts[0...1].joined(separator: ".")
    }

    /// The app identifier a component belongs to, as the first three parts:
    /// `com.samuellaska.AdBuster.Blocker` → `com.samuellaska.AdBuster`.
    ///
    /// This is what collects eight sandbox folders for eight Safari extensions into **one removed
    /// app**, which is what a person recognises. Eight rows for one app they deleted once is a
    /// screen that looks like an infestation.
    static func appIdentifier(of identifier: String) -> String {
        let parts = identifier.split(separator: ".")
        guard parts.count > 3 else { return identifier }
        return parts[0...2].joined(separator: ".")
    }

    // MARK: - Gathering

    /// Group surviving candidates into one `Leftover` per removed app.
    ///
    /// Returns the leftovers and **how many candidates were dropped for having no proof an app was
    /// ever there** — see `Place.provesAnAppWasHere`. They are returned rather than silently
    /// discarded so the row's tally still adds up.
    static func gather(_ candidates: [Candidate]) -> (leftovers: [Leftover], unproven: Int) {
        var grouped: [String: [Candidate]] = [:]
        for candidate in candidates {
            grouped[appIdentifier(of: candidate.identifier), default: []].append(candidate)
        }

        var leftovers: [Leftover] = []
        var unproven = 0

        for (appID, group) in grouped {
            guard group.contains(where: { $0.place.provesAnAppWasHere }) else {
                unproven += group.count
                continue
            }
            let ordered = group.sorted { a, b in
                a.place == b.place ? a.path < b.path : a.place.order < b.place.order
            }
            leftovers.append(Leftover(appName: displayName(for: appID),
                                      bundleID: appID,
                                      paths: ordered.map(\.path),
                                      bytes: total(of: ordered),
                                      reason: reason(for: appID, places: ordered.map(\.place))))
        }

        // Largest first where we know, then by name, so the list is stable between runs.
        leftovers.sort { a, b in
            switch (a.bytes, b.bytes) {
            case let (x?, y?) where x != y: return x > y
            case (nil, _?):                 return false
            case (_?, nil):                 return true
            default:                        return a.appName.localizedCaseInsensitiveCompare(b.appName) == .orderedAscending
            }
        }
        return (leftovers, unproven)
    }

    /// The sum, **or `nil` where any part of it could not be weighed.**
    ///
    /// ⚠️ A partial sum is worse than no sum: it reads as a measurement and it is not one. This is
    /// the same rule as everywhere else in the app — never report a figure we could not take.
    static func total(of candidates: [Candidate]) -> Int64? {
        var sum: Int64 = 0
        for candidate in candidates {
            guard let bytes = candidate.bytes else { return nil }
            sum += bytes
        }
        return sum
    }

    /// A readable name from the identifier's last part: `co.magiclasso.MagicLassoMacApp` →
    /// "Magic Lasso Mac App".
    ///
    /// ⚠️ **This is a display name, not a match.** The app's own name went with the app, and the
    /// only thing left is what it was filed under. The row prints the identifier beside it and says
    /// where the name came from, so nobody mistakes it for what the app called itself.
    static func displayName(for identifier: String) -> String {
        guard let last = identifier.split(separator: ".").last, !last.isEmpty else { return identifier }
        var words = ""
        var previous: Character?
        for character in last {
            if let previous, previous.isLowercase || previous.isNumber, character.isUppercase {
                words.append(" ")
            }
            words.append(character)
            previous = character
        }
        return words
    }

    /// Why we believe this app is gone. **Shown on the row, never behind a disclosure** — a flagged
    /// item with no reason is an accusation, and this is the screen where the accusation is most
    /// likely to be wrong.
    static func reason(for identifier: String, places: [Place]) -> String {
        let proof = places.first(where: \.provesAnAppWasHere) ?? .containers
        let evidence: String
        switch proof {
        case .containers:
            evidence = "These are in the sandbox folder macOS makes for an app"
        case .savedApplicationState:
            evidence = "macOS saved this app's windows to reopen them"
        case .applicationSupport:
            evidence = "These are the files an app keeps for itself"
        case .webKit:
            evidence = "macOS made this for an app that showed web pages"
        case .preferences, .caches, .httpStorages, .logs:
            evidence = "These are filed under an app's own identifier"
        }
        return "\(evidence), and macOS has no app with the identifier \(identifier) — none "
             + "installed, none from the same maker, and nothing running under it. The name above "
             + "comes from that identifier: the app's own name went with the app."
    }

    // MARK: - The words

    static func headline(_ leftovers: [Leftover]) -> String {
        switch leftovers.count {
        case 0:  return "Nothing here belonged to an app that has been removed."
        case 1:  return "One app is gone and left something behind."
        default: return "\(leftovers.count) apps are gone and left something behind."
        }
    }

    /// The figure beside the sentence: **how many apps, and never how many bytes.**
    ///
    /// ⚠️ This is the ruling the whole file is built on. A size in the measure position is the
    /// cleaner's headline — "reclaim 7.6 GB" — and on this Mac that number is wrong by a factor of
    /// twenty. Each app's own size sits on its own line, where it is a fact about one thing rather
    /// than a promise about the disk. `nil` where there is nothing to count.
    static func measure(_ leftovers: [Leftover]) -> String? {
        guard !leftovers.isEmpty else { return nil }
        return leftovers.count == 1 ? "1 app" : "\(leftovers.count) apps"
    }

    static func reason(leftovers: [Leftover], setAside: [Guard: Int]) -> String {
        var parts: [String] = []

        parts.append("We only count files filed under an app's own identifier, and only where macOS "
                   + "has no app with that identifier, no app from the same maker is installed, and "
                   + "nothing is running under it. That misses things, and it is the right way "
                   + "round: a folder named after a company is not evidence that anything is dead.")

        let ignored = setAside.values.reduce(0, +)
        if ignored > 0 {
            parts.append("\(ignored) other \(ignored == 1 ? "thing" : "things") in your Library "
                       + "\(ignored == 1 ? "looks" : "look") like leftovers and \(ignored == 1 ? "is" : "are") "
                       + "not. Options says what each of them is.")
        }

        // ⚠️ Said on the row, not left to a disabled button to imply.
        parts.append(Removal.notYet)
        return parts.joined(separator: " ")
    }

    static func details(leftovers: [Leftover],
                        someSizesUnknown: Bool,
                        setAside: [Guard: Int]) -> [DetailPair] {
        var pairs: [DetailPair] = []

        pairs.append(DetailPair("Removed apps that left something", "\(leftovers.count)"))
        for leftover in leftovers {
            pairs.append(contentsOf: leftover.detailPairs)
        }

        if someSizesUnknown {
            pairs.append(DetailPair("Some sizes",
                                    "We were not allowed to read part of what one of these holds, "
                                  + "so its size is left out rather than reported short."))
        }

        // Every guard that fired, counted. A filter nobody can audit is a fudge — and on this
        // screen the guards are the product.
        for why in Guard.allCases {
            guard let n = setAside[why], n > 0 else { continue }
            pairs.append(DetailPair("Left alone — \(n)", why.explanation))
        }

        pairs.append(DetailPair("Where we did not look",
                                "Group containers. Apps share them, so one folder can hold things "
                              + "belonging to four apps of which three are still installed."))
        pairs.append(DetailPair("No total",
                                "Each app's size is its own. We do not add them up: an app's real "
                              + "footprint often sits in a folder named after the company rather "
                              + "than the app, and a single total would be a guess."))
        pairs.append(DetailPair("Removing them", Removal.notYet))
        pairs.append(howWeLooked)
        return pairs
    }

    static let howWeLooked = DetailPair(
        "How we looked",
        "We listed the folders in your Library whose names are app identifiers and asked macOS "
      + "which of those apps are installed. Nothing was opened, changed, moved or removed.")

    // MARK: - ⭐ The hooks the removal half will need

    /// **What quarantine will plug into, declared now so this screen is not rebuilt later.**
    ///
    /// ⚠️ **Nothing here removes anything, and nothing here is wired to a button.** Removal needs
    /// the quarantine engine — move aside, keep for 30 days, restore in one press, delete only on
    /// the person's word — and that engine does not exist. What exists is the shape:
    ///
    /// - `Leftover.id` is the bundle identifier, so a selection is a `Set<Leftover.ID>` that
    ///   survives a re-scan. Nothing else in the section is stable enough to select against.
    /// - `Plan` is what one quarantine job would take: the exact paths, already grouped by app,
    ///   with the size where it is known.
    /// - `promise` is the sentence the engine has to be able to keep. It is here rather than in the
    ///   engine because it is a product decision, and because writing it now means the engine is
    ///   built to it rather than described afterwards.
    enum Removal {

        /// ⚠️ **False, and it is the type's whole job to say so.** A screen that quietly grew a
        /// working Remove button would be shipping deletion without the undo behind it.
        static let available = false

        /// One app's files, as a quarantine job would receive them.
        struct Plan: Sendable, Hashable, Identifiable {
            /// The same identity the row is keyed by, so a selection survives a re-scan.
            let leftoverID: String
            let appName: String
            /// Exactly the paths listed on the row. **Never a folder we inferred**: quarantine
            /// moves what was shown, and nothing else.
            let paths: [String]
            let bytes: Int64?

            var id: String { leftoverID }
        }

        /// What one row would hand the engine. Pure, and safe to call today — it builds a
        /// description, not an action.
        static func plan(for leftover: Leftover) -> Plan {
            Plan(leftoverID: leftover.id,
                 appName: leftover.appName,
                 paths: leftover.paths,
                 bytes: leftover.bytes)
        }

        /// The promise the engine has to keep before any of this is offered.
        static let promise =
            "Nothing is deleted. Anything set aside is moved, kept for 30 days, and put back in one "
          + "press."

        /// The sentence the row shows today. Plain, and not an apology.
        static let notYet =
            "Wellkept does not remove these yet. Nothing in this app is ever deleted, and the part "
          + "that can set files aside and put them back is not built."
    }

    // MARK: - Looking at this Mac

    /// Every bundle-identifier-shaped entry in the eight places.
    ///
    /// ⚠️ **Nothing is weighed here.** Sizes are taken in `answer(…)`, after the guards, on the
    /// handful that survive. See the note there for what weighing everything cost.
    /// - Parameter fullDiskAccess: whether the grant is ALREADY held. Pass it; never let this
    ///   function find out by trying, because trying is what raises the dialog.
    static func survey(fullDiskAccess: Bool) -> Survey {
        let manager = FileManager.default
        let library = manager.homeDirectoryForCurrentUser.appendingPathComponent("Library")

        var candidates: [Candidate] = []
        var notIdentifiers = 0
        var readSomething = false
        var skipped: [Place] = []

        for place in Place.allCases {
            if place.needsFullDiskAccess && !fullDiskAccess {
                skipped.append(place)
                continue
            }
            let directory = library.appendingPathComponent(place.directory)
            guard let entries = try? manager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            readSomething = true

            for url in entries {
                var name = url.lastPathComponent
                if let suffix = place.suffix {
                    guard name.hasSuffix(suffix) else { continue }
                    name = String(name.dropLast(suffix.count))
                }
                guard isBundleIdentifier(name) else {
                    notIdentifiers += 1
                    continue
                }
                candidates.append(Candidate(identifier: name, place: place, path: url.path))
            }
        }

        guard readSomething else { return Survey(candidates: nil) }
        return Survey(candidates: candidates, notIdentifiers: notIdentifiers, skipped: skipped)
    }

    /// How many files we will walk to weigh one thing. A browser profile can hold hundreds of
    /// thousands, and a press that stalls for a minute to produce one number in small type is a bad
    /// trade. Above this the size is `nil`, which the row already knows how to say.
    static let fileBudget = 50_000

    /// How many bytes one entry holds. **`nil` the moment anything is refused** — a walk that was
    /// turned away part-way returns a number smaller than the truth, and a number smaller than the
    /// truth is the one thing worse than no number on a screen about disk space.
    static func weigh(_ url: URL) -> Int64? {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }

        if !isDirectory.boolValue {
            guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else {
                return nil
            }
            return Int64(size)
        }

        var refused = false
        guard let walker = manager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey],
            options: [],
            errorHandler: { _, _ in refused = true; return true }
        ) else { return nil }

        var total: Int64 = 0
        var seen = 0
        for case let file as URL in walker {
            seen += 1
            if seen > fileBudget { return nil }
            guard let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey,
                                                                 .fileSizeKey,
                                                                 .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return refused ? nil : total
    }

    /// What is running right now, by identifier.
    ///
    /// ⚠️ Not surveillance and not a list anybody sees: it is asked once, used to answer "is this
    /// dead", and thrown away. A folder belonging to something running is the most certain "leave
    /// it alone" there is.
    static func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    /// Whether macOS's own register knows an app by this identifier.
    ///
    /// `NSWorkspace` rather than a walk of `/Applications`: it finds apps wherever they are,
    /// including the ones inside other folders. On this Mac it is what proves Chrome's updater — an
    /// app living inside `Application Support` — is installed. Safe off the main actor; it touches
    /// no window server. Measured at well under a millisecond per lookup.
    static func isRegisteredWithLaunchServices(_ bundleID: String) -> Bool {
        guard !bundleID.isEmpty else { return false }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }
}

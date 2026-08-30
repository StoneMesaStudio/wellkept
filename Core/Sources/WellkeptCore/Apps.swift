import Foundation

//  Apps.swift
//  WellkeptCore
//
//  **The words the Apps section agrees on, and the shape a reader hands back.**
//
//  Five readers compile against this file without seeing each other. Nothing here imports SwiftUI,
//  AppKit or LaunchServices: the vocabulary has to be testable without a window and without a
//  machine, and a reader has to be replaceable without touching a view.
//
//  It is deliberately the same shape as `Hardware.swift` and `Security.swift` — a facts block that
//  can never carry a verdict, a fixed row set that never re-sorts, one row up to Overview — because
//  the three sections are the same screen with different contents, and a person who has learned one
//  has learned all three.
//
//  ## ⚠️ The measured truth this file is built around
//
//  Measured by hand on an M3 running macOS 26.6.2, 2026-08-27, all read-only, 31 apps. The whole
//  survey is in `APPS-QUESTIONS.md`; these are the six findings that shaped the types below.
//
//  - **422 bundles, and 31 is the number a person recognises.** 294 of them are macOS itself, 81
//    are Xcode build products and Automator droplets sitting in the home folder, 12 are under
//    `/Library`, 7 are nested inside other apps. Take LaunchServices' line on what is an app;
//    re-deriving it from file paths is wrong here by a factor of three. See `AppsInventory`.
//  - **Safari is absent from Apple's own inventory** — it is a symlink into the Preboot Cryptex
//    carrying restricted and hidden flags — and it is the 4th most-launched app on this Mac. It is
//    added by hand, and the app's line says so. See `InstalledApp.addedByHand`.
//  - **Version comparison is never a plain `!=`.** Apple's own storefront says Pages 15.3 while the
//    installed copy says 15.3.1; a naive test calls 3 of 9 App Store apps outdated and advises
//    *downgrading* Pages, Numbers and Keynote. 13 of 18 apps carry a hazard of the same kind —
//    "02.06.00.51", dates used as versions, a marketing string that lags the build that shipped.
//    Where the comparison is not confident the answer is `.couldNotTell`, never a guess.
//  - **Chrome looks two versions behind and is current.** Google serves a staged rollout, and the
//    version at the top of their public list was serving to nobody. Chrome is on the self-updating
//    list precisely so it is never compared. See `UpdateStanding.keepsItselfUpToDate`.
//  - **A real current version is obtainable for 13 of the 24 apps in scope — 54%**, and 8 of 19
//    once Apple's own apps and Xcode are set aside. "Covers most of a normal Applications folder"
//    is not true and is not said anywhere. See `UpdateCoverage`.
//  - **We read who SIGNED an app. We never claim to verify it.** `spctl` takes 3 minutes 9 seconds
//    for 29 apps, and it is slow *because* it reports each unstapled app to Apple. Reading the
//    signature takes 1.3 seconds. Of 31 apps, 11 "fail" full verification — 8 purely because Finder
//    tags were added, one because LibreOffice writes cache files inside itself on first run. Not
//    one had been tampered with. See `SignedBy`, which has no case that means "verified".
//
//  ## The four rules that shape every type below
//
//  1. **Never report zero because we could not look.** A reader that was refused returns an
//     `Unreadable`, in the same house sentence the whole app uses, and the row drops its figure.
//  2. **There is no "outdated" without a version we trust.** `UpdateStanding` has no such case, so
//     no reader can reach for one under deadline.
//  3. **A count never travels without its denominator.** `UpdateTally` is the only thing in the app
//     that may say how many apps have a newer version, and it cannot be built without the number of
//     apps that were actually checked. See its initialiser — there is exactly one.
//  4. **Apps can never turn Overview amber this round.** Without vulnerability data an old app is
//     not dangerous, and a version behind is not something wrong. `AppsRow.severity` is a computed
//     constant and `AppsReport` builds its finding with a literal, so there is no argument anywhere
//     that could carry a worse one.

// MARK: - The five rows

/// The five things Apps reports, in the order they are drawn.
///
/// ⚠️ **`allCases` IS the row order, and this list never sorts.** Worst-first is right for a list of
/// findings and wrong for a fixed panel: a person who learns that updates are the third row should
/// still find them there next week, on a Mac where nothing happens to have an update.
///
/// Raw values are storage — they are written into the check history, which is the one record in
/// this app that cannot be rebuilt — and the labels are English. The two are allowed to drift apart
/// for ever.
public enum AppsTopic: String, CaseIterable, Sendable, Identifiable, Codable, Hashable {

    /// Every app on this Mac that a person would call an app, with what each one is.
    case installed

    /// macOS itself: which version is running, and whether a newer one is offered.
    ///
    /// It is a row in Apps rather than in Hardware because it is the same question as every other
    /// row here — is this current — and because the apps that ship with macOS are updated by this
    /// row and by nothing else.
    case macOS

    /// Which apps have a newer version, which keep themselves up to date, and which we could not
    /// tell about. **The last group is the point of the row**, not a footnote to it.
    case updates

    /// Apps that have crashed on this Mac, after the noise is removed.
    ///
    /// ⚠️ 108 crash files on this Mac reduce to **zero real app crashes** once Apple's own
    /// telemetry, iOS Simulator internals, performance notices where nothing actually crashed, and
    /// reports an app files about itself while still running are taken out. A row that printed 108
    /// would be describing a healthy Mac as a broken one.
    case stoppedWorking

    /// Apps that are no longer here, and what they left behind.
    ///
    /// ⚠️ **Removed apps only, and never totalled as one number.** Name-matched "leftovers" on this
    /// Mac come to 7.6 GB; genuinely orphaned is about 350 MB, because 95% of it belongs to software
    /// that is running right now. `~/Library/Application Support/Herd` has no app and no Spotlight
    /// entry and looks like textbook dead weight — it is a working PHP and Composer install.
    case removedLeftovers

    public var id: String { rawValue }

    /// The row's name, as it is drawn.
    public var label: String {
        switch self {
        case .installed:        "Everything installed"
        case .macOS:            "macOS"
        case .updates:          "Updates"
        case .stoppedWorking:   "Apps that stopped working"
        case .removedLeftovers: "Removed apps that left things behind"
        }
    }

    /// What the row means, in one plain sentence. Explanation, not clutter: it says what the row is
    /// actually telling you, which is the one thing a person cannot work out by looking at it.
    public var explanation: String {
        switch self {
        case .installed:
            "Every app on this Mac, what version each one is, and where each one came from."
        case .macOS:
            "Which version of macOS this Mac is running, and whether Apple is offering a newer one."
        case .updates:
            "Which apps have a newer version available, and which ones we could not find that out about."
        case .stoppedWorking:
            "Apps that have actually crashed on this Mac, once the reports that are not crashes are set aside."
        case .removedLeftovers:
            "Files still on this Mac that belonged to an app that is no longer here."
        }
    }

    /// Sort position, so a caller that collected rows out of order can put them back without knowing
    /// how the order is expressed.
    public var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

// MARK: - What an app is built for

/// What an app can run on.
///
/// ⚠️ **A plain labelled fact on the app's line. No countdown, no "will stop working", never a
/// problem colour.** This cuts the other way from the Hardware ruling on security updates, and
/// deliberately: nothing about a Rosetta app is a security matter, macOS 26.4 already warns at
/// launch, and only the developer can act on it. Telling somebody their app is doomed, on a screen
/// where nothing they can press changes it, is a warning that teaches them to ignore warnings.
public enum AppArchitecture: String, Sendable, Codable, Hashable, CaseIterable {

    /// Built for Intel only. It runs here through Rosetta.
    case intelOnly

    /// One app containing both, which is most of what ships now.
    case universal

    /// Built for Apple silicon only. It will not run on an Intel Mac.
    case appleSilicon

    /// We could not read what it was built for. Present because the alternative is picking one, and
    /// picking one is how a universal app gets labelled Intel on somebody's screen.
    case unknown

    public var label: String {
        switch self {
        case .intelOnly:    "Intel only"
        case .universal:    "Universal"
        case .appleSilicon: "Apple silicon"
        case .unknown:      Unreadable.notReported.sentence
        }
    }

    /// What it means for the person, where it means anything. `nil` for the two ordinary answers,
    /// because a universal app needs no sentence.
    public var explanation: String? {
        switch self {
        case .intelOnly:
            "Built for Intel Macs. It runs on Apple silicon through Rosetta, which macOS provides."
        case .appleSilicon:
            "Built for Apple silicon. It will not run on an Intel Mac."
        case .universal, .unknown:
            nil
        }
    }
}

// MARK: - Where an app came from

/// Where an app came from, as far as this Mac can tell.
///
/// This is not a judgement. An unsigned app is very often something the person built themselves,
/// and Homebrew installs software that is perfectly ordinary. The row states where it came from and
/// stops there — the whole section is `.information`, and there is no route from any case here to a
/// colour.
public enum AppOrigin: String, Sendable, Codable, Hashable, CaseIterable, Identifiable {

    /// Bought or downloaded from the Mac App Store — it carries a receipt.
    case appStore

    /// Installed by Homebrew, as a cask or a formula.
    case homebrew

    /// Downloaded from its maker and signed with an Apple Developer ID.
    case developerID

    /// It carries no signature at all. Usually something built on this Mac.
    case unsigned

    /// It ships as part of macOS, and macOS updates it.
    case bundledWithMacOS

    /// We could not tell. **Never a stand-in for the others** — see the header rule.
    case unknown

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .appStore:         "Mac App Store"
        case .homebrew:         "Homebrew"
        case .developerID:      "From its maker"
        case .unsigned:         "Not signed"
        case .bundledWithMacOS: "Comes with macOS"
        case .unknown:          "Where it came from is not recorded"
        }
    }

    public var explanation: String {
        switch self {
        case .appStore:
            "Installed from the Mac App Store, which updates it for you."
        case .homebrew:
            "Installed by Homebrew. Homebrew updates it when you ask it to."
        case .developerID:
            "Downloaded from the people who make it, and signed with an Apple Developer ID."
        case .unsigned:
            "It carries no signature. That is ordinary for software you built yourself."
        case .bundledWithMacOS:
            "It comes with macOS, and a macOS update is what updates it."
        case .unknown:
            "This Mac does not record where it came from."
        }
    }
}

// MARK: - ⭐ Who signed it — and nothing about verifying it

/// **Who signed an app, as the app's own signature says it.**
///
/// ⚠️ **There is no case here that means "verified", and there must never be one.** Wellkept reads
/// a signature; it does not assess one.
///
/// The reason is measured. Apple's own assessment tool, `spctl`, took **3 minutes 9 seconds for 29
/// apps** — and it is slow *because* it asks Apple about every app that has no stapled ticket, so
/// running it would report the contents of somebody's Applications folder to Apple in order to tell
/// them their apps are fine. Worse, it is wrong in the direction that frightens people: **11 of 31
/// apps here "fail"** — 8 of them purely because Finder tags were added to the bundle, one because
/// LibreOffice writes cache files inside itself the first time it runs. Not one had been tampered
/// with. An app that told this user 11 of their apps had failed verification would be wrong eleven
/// times and alarming once.
///
/// Reading the signature costs 1.3 seconds, answers the question a person is actually asking — who
/// made this — and cannot produce a false accusation.
public enum SignedBy: Sendable, Hashable, Codable {

    /// Apple's own signature, on Apple's own software.
    case apple

    /// Signed by a named developer. The string is the authority as the signature spells it —
    /// "Google LLC", "The Document Foundation" — never a name we tidied up.
    case developer(String)

    /// It carries no signature. Ordinary for something built on this Mac.
    case notSigned

    /// We could not read the signature, in the house vocabulary.
    case unreadable(Unreadable)

    /// The words on the row. Note that none of them is "verified", "valid", "trusted" or "safe".
    public var label: String {
        switch self {
        case .apple:               "Apple"
        case let .developer(name): name
        case .notSigned:           "Not signed"
        case let .unreadable(why): why.sentence
        }
    }

    /// The named signer, where there is one. `nil` covers both "nobody signed it" and "we could not
    /// read it", which are different facts the callers that want a name do not need to separate.
    public var name: String? {
        switch self {
        case .apple:               "Apple"
        case let .developer(name): name
        case .notSigned,
             .unreadable:          nil
        }
    }

    public var wasRead: Bool {
        if case .unreadable = self { return false }
        return true
    }
}

// MARK: - ⭐ Whether an app is current — and there is no "outdated"

/// Why we could not tell whether an app is current.
///
/// ⚠️ **A closed list, so "we could not tell" is always accompanied by which kind.** A row that says
/// only "could not tell" is a shrug; a row that says "nothing publishes a current version for this
/// app" is a fact the person can do something with, or at least disagree with.
public enum UpdateUnknown: String, Sendable, Codable, Hashable, CaseIterable, Identifiable {

    /// Nobody publishes a current version for this app in a form we can read.
    ///
    /// This is the honest cost of the decision on 2026-08-27 to **not** ship a hand-maintained
    /// list of makers' version pages: *"I don't know that I want that responsibility. They
    /// frequently release updates."* A stale endpoint gives a wrong answer, and a wrong answer is
    /// worse than none. Coverage on this Mac drops from 13 apps to about 9, and the section says so
    /// rather than implying it looked everywhere.
    case noSourceToAsk

    /// We have both version numbers and **cannot compare them honestly**.
    ///
    /// 13 of 18 apps here carry a hazard of this kind: "02.06.00.51", dates used as version numbers,
    /// a marketing string that lags the build that actually shipped. Apple's storefront says Pages
    /// 15.3 while the installed copy says 15.3.1, and a plain "is it different" test advises
    /// downgrading three apps that are perfectly current.
    case versionsNotComparable

    /// We asked and got no usable answer back — no network, a refusal, a page that changed shape.
    case askFailed

    /// A pre-release build. Six apps on this Mac are TestFlight builds; the storefront answers about
    /// the shipping version, which is a different piece of software.
    case testFlightBuild

    /// It ships with macOS, so the **macOS** row is the answer and this one would repeat it.
    case shipsWithMacOS

    public var id: String { rawValue }

    /// The words on the app's line — always a reason, never a bare shrug.
    public var label: String {
        switch self {
        case .noSourceToAsk:        "Nothing publishes a current version for this app"
        case .versionsNotComparable: "Its version numbers cannot be compared reliably"
        case .askFailed:            "We asked and got no usable answer"
        case .testFlightBuild:      "A test build, so there is nothing to compare it with"
        case .shipsWithMacOS:       "It comes with macOS — see the macOS row"
        }
    }

    /// Whether a check of this app was ever going to mean anything.
    ///
    /// The last two are `false`: a TestFlight build and a macOS-bundled app are not gaps in our
    /// coverage, they are questions that do not apply. Counting them as failures would make the
    /// coverage figure worse than the truth, which is its own kind of dishonesty.
    public var isInScope: Bool {
        switch self {
        case .noSourceToAsk, .versionsNotComparable, .askFailed: true
        case .testFlightBuild, .shipsWithMacOS:                  false
        }
    }
}

/// **Whether an app is current — the honest set, and there is no `outdated`.**
///
/// ⚠️ **`.newerAvailable` requires the version.** That is the whole guard: a reader that cannot name
/// the newer version cannot claim one exists, and the only remaining honest answers are
/// `.couldNotTell` or `.current`. Under deadline, an `outdated` case with no version attached is
/// exactly what somebody reaches for, and it is how Pages 15.3.1 gets reported as behind Pages 15.3.
public enum UpdateStanding: Sendable, Hashable, Codable {

    /// We compared, and the installed copy is the current one.
    case current

    /// A newer version exists, **and here it is**. The string is the newer version as its publisher
    /// spells it, so the row can show both and the person can see the comparison we made.
    case newerAvailable(String)

    /// The app updates itself, so there is nothing here to do and nothing worth comparing.
    ///
    /// See `SelfUpdatingApps` in the app layer for the list and for why a list of *self-updating
    /// apps* survives when a list of *vendor version endpoints* did not.
    case keepsItselfUpToDate

    /// We could not tell, and this is why. See `UpdateUnknown`.
    case couldNotTell(UpdateUnknown)

    /// Nobody asked. Update checking is off, or this run did not reach this app.
    ///
    /// ⚠️ Distinct from `.couldNotTell` and never merged with it: "we did not look" and "we looked
    /// and could not tell" are different sentences, and only the first one has a switch behind it.
    case notChecked

    /// The words on the app's line.
    public var label: String {
        switch self {
        case .current:                  "Current"
        case let .newerAvailable(v):    "Version \(v) is available"
        case .keepsItselfUpToDate:      "Keeps itself up to date"
        case let .couldNotTell(why):    why.label
        case .notChecked:               "Not checked"
        }
    }

    /// The newer version, where we have one.
    public var newerVersion: String? {
        if case let .newerAvailable(v) = self { return v }
        return nil
    }

    /// **Whether this is an answer to "is it current".**
    ///
    /// ⚠️ Only two standings count: `.current` and `.newerAvailable`. `.keepsItselfUpToDate` is
    /// deliberately **not** counted — we did not compare anything, and folding it in would inflate
    /// the denominator of the Overview sentence with apps nobody checked. It is not a gap either;
    /// it is answered by a different route, and the section says so on its own line.
    public var wasChecked: Bool {
        switch self {
        case .current, .newerAvailable: true
        case .keepsItselfUpToDate, .couldNotTell, .notChecked: false
        }
    }

    /// Whether checking this app was in scope at all — the denominator of the coverage pair.
    ///
    /// `.notChecked` is out of scope because nothing was attempted; the two "does not apply" reasons
    /// are out of scope because there was never a question.
    public var isInScope: Bool {
        switch self {
        case .current, .newerAvailable, .keepsItselfUpToDate: true
        case let .couldNotTell(why):                          why.isInScope
        case .notChecked:                                     false
        }
    }

    /// Whether a newer version is available. Never a severity, and never a colour — see rule 4.
    public var hasNewerVersion: Bool {
        if case .newerAvailable = self { return true }
        return false
    }
}

// MARK: - ⭐ The coverage pair — never optional, never rounded

/// **How many apps we could actually check, out of how many it made sense to check.**
///
/// ⚠️ **Both numbers, always, and never a percentage.** A percentage is a rounding, and the rounding
/// is where the dishonesty gets in: "54% covered" sounds like a specification, while "13 of the 24
/// apps that can be checked" is a fact somebody can hold us to. On this Mac it is 13 of 24, and 8 of
/// 19 once Apple's own apps and Xcode are set aside — a figure this particular Mac flatters. The
/// claim "covers most of a normal Applications folder" is not true and is not made anywhere in this
/// app or on its site.
///
/// It is a required field on `AppsReport` rather than an optional one, because an optional coverage
/// figure is a coverage figure somebody eventually leaves out.
public struct UpdateCoverage: Sendable, Hashable, Codable {

    /// Apps we got a trustworthy answer for — `.current` or `.newerAvailable`.
    public let checked: Int

    /// Apps a check was meaningful for at all. Always `>= checked`.
    public let checkable: Int

    /// ⭐ **Apps in scope that look after themselves — Chrome, Firefox, VS Code and the like.**
    ///
    /// ⚠️ **They are the third number because they are neither of the other two, and folding them
    /// into either one says something untrue.** They were not compared, so they are not `checked`.
    /// But "we could not check Chrome" and "Chrome keeps itself up to date" are opposite messages,
    /// and on the measured Mac four apps sit here — enough that lumping them into the caveat turns
    /// a well-kept Applications folder into a neglected-looking one.
    ///
    /// Their own rows already say `keepsItselfUpToDate`. This is the same fact, arriving at the
    /// summary sentence, where it would otherwise be lost.
    public let selfUpdating: Int

    /// Clamped rather than trusted: `checked` above `checkable` is arithmetic nobody can read, and
    /// it would put a number larger than its own denominator on somebody's screen. `selfUpdating`
    /// is clamped to what is left after `checked`, for the same reason.
    public init(checked: Int, checkable: Int, selfUpdating: Int = 0) {
        let floor = max(0, checkable)
        self.checkable = floor
        let counted = min(max(0, checked), floor)
        self.checked = counted
        self.selfUpdating = min(max(0, selfUpdating), floor - counted)
    }

    // ⚠️ Decoded by hand so that a coverage figure written before this third number existed still
    // reads back, as nothing rather than as a decoding failure.
    private enum CodingKeys: String, CodingKey { case checked, checkable, selfUpdating }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        self.init(checked: try box.decode(Int.self, forKey: .checked),
                  checkable: try box.decode(Int.self, forKey: .checkable),
                  selfUpdating: try box.decodeIfPresent(Int.self, forKey: .selfUpdating) ?? 0)
    }

    /// The apps in scope that we could not get an answer for — and that nothing else answers for
    /// either. **An app that updates itself is not one of these.**
    public var unchecked: Int { max(0, checkable - checked - selfUpdating) }

    /// Nothing was in scope — an empty Applications folder, or update checking switched off.
    public var isEmpty: Bool { checkable == 0 }

    /// The sentence the section states once, so no row has to imply it.
    ///
    /// ⚠️ Callers use this rather than writing their own. It is the one place the app admits how
    /// much of the question it can answer, and five sections each phrasing it differently is five
    /// chances for one of them to phrase it flatteringly.
    public var sentence: String {
        if checkable == 0 {
            return "Nothing here could be checked for a newer version."
        }
        // ⚠️ Nothing is outstanding. That is a different sentence from "we could not look", and the
        // branch order is what keeps them apart on a Mac whose apps all update themselves.
        if unchecked == 0 {
            if checked == 0 {
                return selfUpdating == 1
                    ? "The one app here that can be checked keeps itself up to date."
                    : "All \(selfUpdating) apps here that can be checked keep themselves up to date."
            }
            if selfUpdating == 0 {
                return checked == 1
                    ? "We could check the one app that can be checked."
                    : "We could check all \(checked) apps that can be checked."
            }
            return "We could check \(checked) of the \(checkable) apps that can be checked."
        }
        if checked == 0 {
            return unchecked == 1
                ? "We could not find out whether the one app that can be checked is current."
                : "We could not find out whether any of the \(unchecked) apps that can be checked are current."
        }
        return "We could check \(checked) of the \(checkable) apps that can be checked."
    }

    /// Coverage worked out from a list of apps, which is how `AppsReport` builds it — so the three
    /// numbers can never disagree with the list they are about.
    public static func measuring(_ apps: [InstalledApp]) -> UpdateCoverage {
        UpdateCoverage(checked: apps.filter { $0.update.wasChecked }.count,
                       checkable: apps.filter { $0.update.isInScope }.count,
                       selfUpdating: apps.filter { $0.update == .keepsItselfUpToDate }.count)
    }
}

/// **How many apps have a newer version — and it is impossible to say so without saying out of how
/// many.**
///
/// ⚠️ **There is exactly one initialiser and it takes the coverage.** That is the enforcement asked
/// for on 2026-08-27: a bare "4 apps are out of date" hides the eleven we could not check, and it
/// hides them in the direction that makes the app look more capable than it is. There is no
/// `init(count:)`, no `init(_ n: Int)`, and no free function anywhere that formats a bare count.
///
/// `sentence` is the only thing in the app permitted to put an update count into English. A caller
/// that formats `newerAvailable` itself has stepped around the guard, and the tests say so.
public struct UpdateTally: Sendable, Hashable, Codable {

    /// How many of the checked apps have a newer version. Never more than `coverage.checked`.
    public let newerAvailable: Int

    /// The pair this count is against. Not optional, and not defaulted.
    public let coverage: UpdateCoverage

    /// The only way to make one.
    public init(newerAvailable: Int, coverage: UpdateCoverage) {
        self.coverage = coverage
        self.newerAvailable = min(max(0, newerAvailable), coverage.checked)
    }

    /// A tally worked out from a list of apps.
    public static func measuring(_ apps: [InstalledApp]) -> UpdateTally {
        UpdateTally(newerAvailable: apps.filter { $0.update.hasNewerVersion }.count,
                    coverage: .measuring(apps))
    }

    /// Whether there is anything here to say at all.
    public var isEmpty: Bool { newerAvailable == 0 }

    /// **The sentence, with its denominator welded on.**
    ///
    /// "4 of the 13 apps we could check have a newer version." Never "4 apps are out of date", and
    /// never "4 updates available" — both of those are true statements that leave out the part that
    /// matters, which is how much of the Applications folder the number is about.
    public var sentence: String {
        guard coverage.checked > 0 else { return coverage.sentence }

        // One checked app is its own sentence. "One of the one app we could check" is English
        // nobody wrote on purpose, and it is the form a naïve template produces.
        if coverage.checked == 1 {
            return newerAvailable == 1
                ? "The one app we could check has a newer version."
                : "The one app we could check is current."
        }

        let denominator = "the \(coverage.checked) apps we could check"
        switch newerAvailable {
        case 0:  return "None of \(denominator) has a newer version."
        case 1:  return "One of \(denominator) has a newer version."
        default: return "\(newerAvailable) of \(denominator) have a newer version."
        }
    }

    /// The sentence, followed by what it does not cover — the form Overview and the section face
    /// both use. Where coverage is complete, the caveat is dropped rather than padded out.
    ///
    /// ⚠️ **The apps that update themselves get their own clause, never the caveat's.** Folding
    /// them in reads "4 more apps could not be checked" about Chrome, Firefox, VS Code and Claude,
    /// each of whose own rows says the opposite two lines further down. Same page, two contradictory
    /// answers, and the one in larger type is the wrong one.
    public var sentenceWithCoverage: String {
        var parts = [sentence]
        if coverage.unchecked > 0 {
            parts.append(coverage.unchecked == 1
                ? "One more app could not be checked."
                : "\(coverage.unchecked) more apps could not be checked.")
        }
        // Only where it is news. A Mac with no self-updating apps gets no clause about them, and a
        // Mac where they are the whole story has already said so in `sentence`.
        if coverage.selfUpdating > 0, coverage.checked > 0 || coverage.unchecked > 0 {
            parts.append(coverage.selfUpdating == 1
                ? "One app keeps itself up to date."
                : "\(coverage.selfUpdating) apps keep themselves up to date.")
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - One app

/// One app on this Mac.
///
/// ⚠️ **What counts as an app is LaunchServices' answer, never ours.** Walking the file system finds
/// **422 bundles** here: 294 belong to macOS, 81 are Xcode build products and Automator droplets in
/// the home folder, 12 are under `/Library`, and 7 are nested inside other apps. The number a person
/// recognises is **31**. A section that opened with "422 apps installed" would be wrong by a factor
/// of three on its very first line, and wrong in the direction that sells cleaners.
public struct InstalledApp: Sendable, Hashable, Codable, Identifiable {

    /// What the app calls itself — "Pages". Where the name cannot be read, readers put the bundle
    /// identifier here rather than inventing one.
    public let name: String

    /// "com.apple.iWork.Pages". The identity that survives the app being renamed or moved, and the
    /// key everything else in this section joins on.
    public let bundleID: String

    /// The version a person sees — `CFBundleShortVersionString`. `nil` where it could not be read;
    /// **never "0" and never "unknown"** as a string, which is how a placeholder ends up compared.
    public let version: String?

    /// The build — `CFBundleVersion`. Often the more truthful of the two, and often uglier:
    /// "02.06.00.51" is a real value from this Mac. Kept because the marketing string sometimes lags
    /// the shipped build, which is one of the reasons a comparison is not always possible.
    public let build: String?

    /// The app bundle's own size in bytes. `nil` where it was not measured.
    ///
    /// ⚠️ **The bundle only — never "this app and everything it owns".** Chrome's provable files
    /// come to 5.8 MB; the real figure is about 5.9 GB, in a folder called "Google" that matches
    /// neither the app's name nor its identifier. One number covering both would be a guess dressed
    /// as a fact.
    public let bytes: Int64?

    /// When it arrived on this Mac, as best the file system can tell. `nil` is ordinary.
    public let installedAt: Date?

    /// When it was last opened, where macOS records it. `nil` is ordinary and harmless — macOS
    /// reports nothing at all for 6 of the 31 apps here, **including Keynote and Teams, both
    /// demonstrably run**. That is why "apps you have not opened" is not a finding.
    public let lastOpenedAt: Date?

    public let architecture: AppArchitecture

    /// Who signed it. Read, never verified — see `SignedBy`.
    public let signedBy: SignedBy

    public let origin: AppOrigin

    /// Whether this app is current. `.notChecked` until the update reader has run.
    public let update: UpdateStanding

    /// **This app is not in macOS's own inventory and we added it by hand.**
    ///
    /// Safari is the case that forced this field: it is a symlink into the Preboot Cryptex carrying
    /// restricted and hidden flags, it is absent from `system_profiler`'s list entirely, and it is
    /// the 4th most-launched app on this Mac. Adding it silently would be inventing a row; adding it
    /// and saying so is a fact the person can check.
    public let addedByHand: Bool

    public var id: String { bundleID }

    public init(name: String,
                bundleID: String,
                version: String? = nil,
                build: String? = nil,
                bytes: Int64? = nil,
                installedAt: Date? = nil,
                lastOpenedAt: Date? = nil,
                architecture: AppArchitecture = .unknown,
                signedBy: SignedBy = .unreadable(.notReported),
                origin: AppOrigin = .unknown,
                update: UpdateStanding = .notChecked,
                addedByHand: Bool = false) {
        self.name = name
        self.bundleID = bundleID
        self.version = version
        self.build = build
        self.bytes = bytes
        self.installedAt = installedAt
        self.lastOpenedAt = lastOpenedAt
        self.architecture = architecture
        self.signedBy = signedBy
        self.origin = origin
        self.update = update
        self.addedByHand = addedByHand
    }

    /// The same app with an update standing attached — what the update reader hands back, so it does
    /// not have to rebuild an inventory that took 7–8 seconds to gather.
    public func withUpdate(_ standing: UpdateStanding) -> InstalledApp {
        InstalledApp(name: name,
                     bundleID: bundleID,
                     version: version,
                     build: build,
                     bytes: bytes,
                     installedAt: installedAt,
                     lastOpenedAt: lastOpenedAt,
                     architecture: architecture,
                     signedBy: signedBy,
                     origin: origin,
                     update: standing,
                     addedByHand: addedByHand)
    }

    /// The version, formatted for a person, or the house sentence.
    public var versionText: String {
        version ?? Unreadable.notReported.sentence
    }

    /// The bundle's size, formatted, or `nil` where it was not measured. **Never "0 bytes" for
    /// something we did not weigh.**
    public var sizeText: String? {
        bytes.map { $0.formatted(.byteCount(style: .file)) }
    }

    /// **The three facts on this app's line, in order.** Everything more exact is behind Options.
    ///
    /// Version, where it came from, and whether it is current: the three a person is actually asking
    /// about. Size, build, architecture, signer and dates are all real and all belong one layer down
    /// — a line carrying eight facts is a line nobody reads.
    public var lineFacts: [String] {
        [versionText, origin.label, update.label]
    }

    /// Everything exact, for behind the **Options** disclosure.
    ///
    /// Label-above-value, never two columns — see `DetailPair`. The order is fixed so two apps'
    /// panels read the same way.
    public var detailPairs: [DetailPair] {
        var rows: [DetailPair] = [
            DetailPair("Version", versionText),
        ]
        if let build, build != version {
            rows.append(DetailPair("Build", build))
        }
        rows.append(DetailPair("Identifier", bundleID))
        rows.append(DetailPair("Where it came from", origin.label))
        rows.append(DetailPair("Signed by", signedBy.label))
        rows.append(DetailPair("Built for", architecture.label))
        rows.append(DetailPair("Size", sizeText ?? Unreadable.notReported.sentence))
        rows.append(DetailPair("Installed",
                               installedAt.map { $0.formatted(date: .abbreviated, time: .omitted) }
                                   ?? Unreadable.notReported.sentence))
        rows.append(DetailPair("Last opened",
                               lastOpenedAt.map { $0.formatted(date: .abbreviated, time: .omitted) }
                                   ?? Unreadable.notReported.sentence))
        rows.append(DetailPair("Updates", update.label))
        if addedByHand {
            rows.append(DetailPair("Listing", "macOS does not list this app. Wellkept added it."))
        }
        return rows
    }
}

// MARK: - What is installed

/// **The "what is installed" block at the top of the section.**
///
/// ⚠️ **Inventory, never a verdict. This type can never say Needs attention**, and it carries no
/// status for that reason. It lists what is here; nothing about a list of apps constitutes a fault,
/// and nothing in this round of Apps constitutes one either.
///
/// **Only real apps are listed** — `/Applications`, `~/Applications`, `/Applications/Utilities` and
/// `/System/Applications`, as LaunchServices reports them. The other 391 bundles on this Mac get one
/// line behind Options, in `otherBundles`, because the honest thing is to say they exist and the
/// dishonest thing is to count them as apps.
public struct AppsInventory: Sendable, Hashable, Codable {

    /// The apps, in the order given. Duplicates by identifier are dropped, first one wins.
    public let apps: [InstalledApp]

    /// Bundles on this Mac that are **not** apps a person would recognise — macOS's own components,
    /// Xcode build products, Automator droplets, helpers nested inside other apps.
    ///
    /// `nil` where nothing counted them, which is not the same as zero — see the header rule. On
    /// this Mac the figure is 391.
    public let otherBundles: Int?

    /// When the inventory itself was gathered. Kept because it is the slow half: the inventory call
    /// alone takes 7–8 seconds, which is why **Apps does not run on launch**.
    public let gatheredAt: Date?

    public init(apps: [InstalledApp], otherBundles: Int? = nil, gatheredAt: Date? = nil) {
        var seen = Set<String>()
        self.apps = apps.filter { seen.insert($0.bundleID).inserted }
        self.otherBundles = otherBundles
        self.gatheredAt = gatheredAt
    }

    public func app(_ bundleID: String) -> InstalledApp? {
        apps.first { $0.bundleID == bundleID }
    }

    /// How many apps came from each origin, in `AppOrigin.allCases` order, zeroes dropped.
    public var byOrigin: [(origin: AppOrigin, count: Int)] {
        AppOrigin.allCases.compactMap { origin in
            let n = apps.filter { $0.origin == origin }.count
            return n > 0 ? (origin, n) : nil
        }
    }

    /// Apps built for Intel only. A labelled fact, never a countdown — see `AppArchitecture`.
    public var intelOnly: [InstalledApp] { apps.filter { $0.architecture == .intelOnly } }

    /// The apps we added by hand because macOS does not list them. Safari, here.
    public var addedByHand: [InstalledApp] { apps.filter(\.addedByHand) }

    /// Coverage across this inventory. Derived, so it can never disagree with the list.
    public var coverage: UpdateCoverage { .measuring(apps) }

    /// The tally across this inventory. Derived, for the same reason.
    public var tally: UpdateTally { .measuring(apps) }

    /// The same inventory with update standings attached, keyed by bundle identifier. An app the
    /// dictionary does not mention keeps the standing it already had.
    public func applying(_ standings: [String: UpdateStanding]) -> AppsInventory {
        AppsInventory(apps: apps.map { app in
            standings[app.bundleID].map(app.withUpdate) ?? app
        }, otherBundles: otherBundles, gatheredAt: gatheredAt)
    }

    /// The block, as rows, in a fixed order.
    public var detailPairs: [DetailPair] {
        var rows: [DetailPair] = [
            DetailPair("Apps", "\(apps.count)"),
        ]
        for entry in byOrigin {
            rows.append(DetailPair(entry.origin.label, "\(entry.count)"))
        }
        let intel = intelOnly.count
        if intel > 0 {
            rows.append(DetailPair("Built for Intel only", "\(intel)"))
        }
        rows.append(DetailPair("Other bundles on this Mac",
                               otherBundles.map { "\($0) — components, helpers and build products, not apps" }
                                   ?? Unreadable.notReported.sentence))
        return rows
    }

    /// The placeholder before anything has been read. Empty, and honest that it is empty.
    public static let notCheckedYet = AppsInventory(apps: [], otherBundles: nil)
}

// MARK: - Apps that stopped working

/// One app that has actually crashed on this Mac.
///
/// ⚠️ **The filtering happens before this type exists, and it is most of the work.** 108 crash files
/// on this Mac reduce to **zero real app crashes** once four groups are removed: Apple's own
/// telemetry, iOS Simulator internals, performance notices where nothing crashed at all, and reports
/// an app files about itself while it is still running. A row built straight from the file count
/// would tell somebody with a perfectly healthy Mac that a hundred things had crashed.
public struct CrashedApp: Sendable, Hashable, Codable, Identifiable {

    public let appName: String
    public let bundleID: String

    /// How many real crashes, after the filtering. Never a file count.
    public let crashes: Int

    /// The most recent one.
    public let lastCrash: Date

    public var id: String { bundleID }

    public init(appName: String, bundleID: String, crashes: Int, lastCrash: Date) {
        self.appName = appName
        self.bundleID = bundleID
        self.crashes = max(0, crashes)
        self.lastCrash = lastCrash
    }

    /// "Crashed 3 times, last on 12 Aug 2026."
    public var sentence: String {
        let when = lastCrash.formatted(date: .abbreviated, time: .omitted)
        return crashes == 1
            ? "Crashed once, on \(when)."
            : "Crashed \(crashes) times, last on \(when)."
    }

    public var detailPair: DetailPair { DetailPair(appName, sentence) }
}

// MARK: - What a removed app left behind

/// Files still on this Mac that belonged to an app that is no longer here.
///
/// ⚠️ **Shown for removed apps only, and never totalled as one number. There is deliberately no
/// section-wide total anywhere in this file.** Name-matching every folder against every app on this
/// Mac produces 7.6 GB; genuinely orphaned is about 350 MB, because 95% of that belongs to software
/// running right now. Six "orphaned browser profiles" here belong to an extension that is installed
/// and working, and `~/Library/Application Support/Herd` — no app, no Spotlight entry, textbook dead
/// weight — is a working PHP and Composer install.
///
/// A single headline number would be wrong by a factor of twenty, and it is exactly the number a
/// cleaner puts in a big font. So the section lists the items and lets a person read them.
///
/// ⚠️ **Nothing here can be removed in this round.** Removal needs the quarantine engine, which does
/// not exist. The type is named now so this screen is not torn up when it does.
public struct Leftover: Sendable, Hashable, Codable, Identifiable {

    /// The app that is gone, as best it can be named.
    public let appName: String

    /// The identifier the files are filed under, where there is one.
    public let bundleID: String?

    /// Where it is. One entry per place — an app often leaves several, and merging them hides which
    /// one a person would actually recognise.
    public let paths: [String]

    /// What these files come to, in bytes. `nil` where they were not weighed. **Per item only.**
    public let bytes: Int64?

    /// Why we believe the app is gone — shown on the row, never behind a disclosure. A flagged item
    /// with no reason is an accusation, and this is the section where the accusation is most likely
    /// to be wrong.
    public let reason: String

    public var id: String { bundleID ?? paths.first ?? appName }

    public init(appName: String,
                bundleID: String? = nil,
                paths: [String],
                bytes: Int64? = nil,
                reason: String) {
        self.appName = appName
        self.bundleID = bundleID
        self.paths = paths
        self.bytes = bytes
        self.reason = reason
    }

    /// The size, formatted, or `nil` where it was not measured.
    public var sizeText: String? { bytes.map { $0.formatted(.byteCount(style: .file)) } }

    public var detailPairs: [DetailPair] {
        var rows = [DetailPair(appName, reason)]
        for path in paths { rows.append(DetailPair("Location", path)) }
        if let sizeText { rows.append(DetailPair("Size", sizeText)) }
        return rows
    }
}

// MARK: - One row's result

/// What one Apps reader found.
///
/// The same shape and the same invariants as `Reading` in `Hardware.swift` and `SecurityRow` in
/// `Security.swift`, with one difference that is the whole ruling of 2026-08-27:
///
/// ⚠️ **`severity` is a computed constant. There is no argument, anywhere, that can raise it.**
/// Without vulnerability data an old app is not dangerous, and a version behind is not something
/// wrong. Apps reports facts this round; it does not raise concerns. A reader that wants a colour
/// has to change this line, in this file, with the developer — not pass a different value.
public struct AppsRow: Sendable, Hashable, Identifiable, Codable {

    public let topic: AppsTopic

    /// The row's own sentence, in plain words. **Fact one of three.**
    public let headline: String

    /// A count or figure, already formatted for a person — "31 apps", "4 of 13". `nil` where there
    /// is nothing to measure. **Fact two of three.**
    public let measure: String?

    /// Why it says what it says, in plain words. Shown on the row, never behind a disclosure.
    /// **Fact three of three.**
    public let reason: String?

    /// Everything more exact, shown behind **Options**.
    public let details: [DetailPair]

    /// Set when the reader could not read this at all.
    public let unreadable: Unreadable?

    /// The button on a `.notPermitted` row — the one refusal a person can lift. Dropped otherwise.
    ///
    /// ⚠️ **Nothing in Apps needs Full Disk Access**, measured 2026-08-27, so this section works
    /// completely for somebody who tapped "Finish later" and in practice never carries one. The
    /// field exists because the uninstaller, later, will.
    public let remedy: Remedy?

    public var id: AppsTopic { topic }

    /// ⚠️ **Always `.information`, and there is no way to make it anything else.** See the type note.
    public var severity: Severity { Self.severityCeiling }

    /// The one severity Apps may produce this round. Named so a test can hold it and so the reason
    /// lives beside the rule.
    public static let severityCeiling: Severity = .information

    /// The row's status chip. **Never `.needsAttention`** — the only two answers this section has
    /// are "we looked" and "we could not look".
    public var status: SectionStatus {
        unreadable == nil ? .good : .notChecked
    }

    /// Whether this row leaves the check able to call itself complete. Only a refusal somebody can
    /// lift counts — see the table on `Unreadable`.
    public var complete: Bool { unreadable?.stillComplete ?? true }

    /// The three facts, in order, for a view that wants them as a list rather than as fields.
    public var facts: [String] { [headline, measure, reason].compactMap { $0 } }

    public init(topic: AppsTopic,
                headline: String,
                measure: String? = nil,
                reason: String? = nil,
                details: [DetailPair] = [],
                unreadable: Unreadable? = nil,
                remedy: Remedy? = nil) {
        self.topic = topic
        self.headline = headline
        // ⚠️ Never report zero because we could not look. A row we did not read cannot carry a
        // figure, whatever a reader hands in.
        self.measure = unreadable == nil ? measure : nil
        self.reason = reason
        self.details = details
        self.unreadable = unreadable
        self.remedy = (unreadable?.mayOfferRemedy ?? false) ? remedy : nil
    }

    /// A row we could not read, in the house sentence.
    public static func unreadable(_ topic: AppsTopic,
                                  _ why: Unreadable,
                                  about thing: String? = nil,
                                  reason: String? = nil,
                                  details: [DetailPair] = [],
                                  remedy: Remedy? = nil) -> AppsRow {
        AppsRow(topic: topic,
                headline: why.sentence(about: thing ?? topic.label),
                reason: reason,
                details: details,
                unreadable: why,
                remedy: remedy)
    }
}

// MARK: - The whole section's answer

/// Everything one run of the Apps check produced.
public struct AppsReport: Sendable, Hashable {

    /// The "what is installed" block. Inventory, never a verdict.
    public let inventory: AppsInventory

    /// Always in `AppsTopic` order, whatever order the readers finished in. Duplicates dropped,
    /// first one wins.
    public let rows: [AppsRow]

    public let ranAt: Date

    /// **How much of the update question this run could answer. Never optional, never rounded.**
    ///
    /// Derived from the inventory rather than passed in, so it cannot disagree with the list of apps
    /// it is about. See `UpdateCoverage`.
    public let coverage: UpdateCoverage

    /// How many apps have a newer version, welded to the number that were checked.
    public let tally: UpdateTally

    /// The single row Apps sends up to Overview, or `nil` when there is nothing to say.
    ///
    /// ⚠️ **One row, not one per app.** A section that posts four rows to Overview has turned the
    /// summary into a second copy of itself.
    ///
    /// ⚠️ **Always `.information`.** `AppState.needsYou` lists findings at `.attention` and above, so
    /// this row does not appear in "what needs you" — which is the correct outcome and the point of
    /// the ruling: nothing in Apps needs you this round. It is here for the audit trail and for the
    /// section's own face, and it carries its denominator wherever it is drawn.
    ///
    /// Stored rather than computed so its `id` is stable across draws.
    public let overviewFinding: Finding?

    public init(inventory: AppsInventory, rows: [AppsRow], ranAt: Date = Date()) {
        self.inventory = inventory

        var seen = Set<AppsTopic>()
        self.rows = rows
            .filter { seen.insert($0.topic).inserted }
            .sorted { $0.topic.order < $1.topic.order }

        self.ranAt = ranAt

        let coverage = inventory.coverage
        let tally = UpdateTally(newerAvailable: inventory.apps.filter { $0.update.hasNewerVersion }.count,
                                coverage: coverage)
        self.coverage = coverage
        self.tally = tally
        self.overviewFinding = Self.summarise(tally: tally)
    }

    /// The section's status chip.
    ///
    /// ⚠️ **`.needsAttention` is unreachable**, by the same ruling that fixes `AppsRow.severity`.
    /// `.notChecked` is reserved for a section with no rows at all.
    public var status: SectionStatus {
        rows.isEmpty ? .notChecked : .good
    }

    /// Whether this run saw everything it set out to see. Only a refusal a person could lift counts.
    public var complete: Bool { rows.allSatisfy(\.complete) }

    /// The line this run contributes to the app's audit trail.
    public var record: CheckRecord {
        CheckRecord(section: .apps, ranAt: ranAt, status: status, complete: complete)
    }

    public func row(_ topic: AppsTopic) -> AppsRow? {
        rows.first { $0.topic == topic }
    }

    /// Everything this run could not read, with the reason, for the section to state once rather
    /// than five times.
    public var unreadableTopics: [(topic: AppsTopic, why: Unreadable)] {
        rows.compactMap { row in row.unreadable.map { (row.topic, $0) } }
    }

    /// The section's own sentence, at the top of its face.
    ///
    /// ⚠️ It always carries the coverage, because the count on its own is the flattering half.
    public var summary: String {
        guard !inventory.apps.isEmpty else {
            return "Nothing has been checked yet."
        }
        let count = inventory.apps.count
        let installed = count == 1 ? "One app is installed." : "\(count) apps are installed."
        return "\(installed) \(tally.sentenceWithCoverage)"
    }

    // MARK: The one row for Overview

    /// ⚠️ **The severity is a literal, here, once.** There is no parameter and no branch: whatever
    /// the tally says, Apps hands Overview an `.information` row. Removing this comment does not
    /// change the behaviour, which is the whole idea.
    private static func summarise(tally: UpdateTally) -> Finding? {
        guard tally.newerAvailable > 0 else { return nil }

        return Finding(section: .apps,
                       title: tally.newerAvailable == 1
                           ? "One app has a newer version"
                           : "\(tally.newerAvailable) apps have a newer version",
                       // The reason IS the denominator. A caller drawing this row cannot leave it
                       // out, because there is nothing else here to draw.
                       reason: tally.sentenceWithCoverage,
                       severity: .information,
                       measure: nil)
    }
}

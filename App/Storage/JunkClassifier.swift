// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Darwin
import Foundation
import WellkeptCore

//  JunkClassifier.swift
//  Wellkept — App/Storage
//
//  ⭐ **The one file that decides whether something is the machine's or yours.**
//
//  Machine junk may arrive with its box already ticked. So a wrong answer here is not a bad row on
//  a screen — it is somebody's file in a holding pen they never asked for. Nothing else in Storage
//  is allowed to decide `Origin`, and `Item.init` defaults it to `.yours`, which means every path
//  through this file that fails to convict produces a thing nobody may sweep.
//
//  ## ⚠️ The case this file exists because of
//
//  **There is a 1.3 GB audiobook in `~/Library/Caches` right now.** It is at
//  `~/Library/Caches/com.apple.bookassetd/1442759222/Track 1.m4b` — Apple Books put it there, filed
//  under its store number, inside a folder named with a perfectly genuine Apple bundle identifier.
//
//  Measured on one real Mac, 2026-08-28: **the whole of `~/Library/Caches` is 4.6 GB, and 1.5 GB of it
//  is those audiobooks.** A cleaner that offers "Caches — 4.6 GB" is offering a third of somebody's
//  audiobook library as part of the prize, and it will be right about the number and wrong about
//  the thing.
//
//  Two rules fall out of that one file, and everything below is one or the other:
//
//  1. **Location may narrow where we look. It may never be what convicts.** `~/Library/Caches` is
//     where this file starts looking for a cache. It is not evidence that anything in there is one.
//  2. **A category must name the program that will write the thing again.** If we cannot say what
//     puts it back, it is not junk — it is a file, and files are the person's.
//
//  ## ⚠️ The Herd trap, and why "nothing claims it" is not a finding
//
//  `~/Library/Application Support/Herd` is 90 MB, has no app, no receipt, no Spotlight entry, and
//  has not been touched in four and a half months. Every orphan heuristic ever written fires on it
//  at once. **It is a working PHP interpreter — the thing somebody's working day runs on.**
//
//  It is safe from this file for a reason that is not luck: **nothing here ever concludes anything
//  from an absence.** There is no rule below of the form "no app claims it", "nobody has opened it",
//  or "it is not in any receipt". Every category is a positive claim about the thing itself.
//
//  ## What qualifies, measured on one real Mac
//
//  | Category | Found here | Ticked | What puts it back |
//  |---|---|---|---|
//  | Xcode's build folders | **13 GB** | yes | Xcode, on the next build |
//  | A content-addressed cache | **1.3 GB** (Firefox 760 MB, Chrome 434 MB, Homebrew 155 MB) | yes | whatever wrote it, by fetching it again |
//  | A half-finished download | 0 bytes | yes | your browser, if you start the download again |
//  | The iOS simulator runtimes | **11.6 GB** | ⛔ never — no button at all | Xcode ▸ Settings ▸ Components |
//
//  ## What does NOT qualify, and what leaving it alone costs
//
//  Each of these fails one of the four questions, and the size is what the honesty costs.
//
//  | Not a category | Size here | Which question it fails |
//  |---|---|---|
//  | `~/Library/Caches` as a folder | 4.6 GB | *What qualifies* — the folder is not evidence. 1.5 GB of it is audiobooks. |
//  | pip's cache (469 MB), Composer's (139 MB) | 608 MB | *What qualifies* — nothing about those files says pip wrote them. Only the folder does, and the folder is where the audiobook was. |
//  | Xcode's Archives | 601 MB | *What breaks* — they are the debug symbols for builds already shipped. Lose them and a customer's crash report can never be read again. |
//  | Xcode's iOS DeviceSupport | 5.7 GB | *How it comes back* — Xcode copies it from the device, so it comes back only if you still own that iPhone on that version of iOS. |
//  | A project's `node_modules` or `.build` | not measured | *How it comes back* — over the network, from a machine that may be offline, into a folder where a build may be half-finished. A project folder is a workshop. |
//  | Crash reports | small | *What breaks* — the Apps section reads them as evidence, and they were never a space finding. |
//  | Installers in Downloads | not measured | *How it comes back* — old software cannot always be downloaded again. |
//  | What a removed app left behind | 28.6 MB | Not ours: `LeftoverReader` does it by bundle identifier, with seven guards. |
//
//  ## ⚠️ "Older than 30 days" is an annoyance filter, and it applies to exactly one category
//
//  It is never the reason anything is ticked. Three measurements decide where it may even adjust:
//
//  - Pointed at `~/Library/Caches`, **it picks the audiobook first** — the biggest, oldest thing in
//    there.
//  - **96% of Xcode's 13 GB is under 30 days old.** Applying it there would untick nearly all of
//    the only large safe win on this Mac, in the name of safety it does not provide.
//  - **A browser cache was written to seconds ago, always** — that is what a cache is. Applying it
//    there unticks 100% of the category forever.
//
//  So it survives on **half-finished downloads only**, where it does the one thing it is good at:
//  do not make me start over on something I was downloading this week. See
//  `Category.theAnnoyanceFilterApplies`.
//
//  ## How a row is wired to it
//
//  `Scanner` deliberately decides nothing — its `Entry` has no `origin` field at all — so the two
//  meet in one place, and it is two lines:
//
//  ```swift
//  let judged = JunkClassifier.judge(JunkClassifier.Subject.onDisk(url) ?? …, home: home)
//  let item = entry.item(origin: judged.origin, reason: judged.reason, handling: judged.handling)
//  ```
//
//  ⚠️ **Ask `judged.stopHere` before descending.** A folder that is junk is junk whole; walking into
//  it and judging the children again counts the same bytes at four depths and offers a person the
//  same thing four times.
//
//  ## What this file may touch: nothing
//
//  It reads directory **listings** and `lstat`. It never opens a file. That is not modesty — a
//  read rewrites the access date (our own research rewrote 2,012 of them) and, on a thread that
//  forgot `ScanPolicy.prepareThisThread()`, pulls the file down from iCloud. `ScanPolicy` permits a
//  contents read for one purpose, comparing two duplicates, and this is not it.

enum JunkClassifier {

    // MARK: - ⭐ The categories

    /// One kind of machine junk. **Every case answers all four questions**, and a case that cannot
    /// is not a case — see the rejection table in the file note. `JunkCategoryTests` fails the build
    /// if any answer is blank.
    enum Category: String, Sendable, Codable, CaseIterable, Identifiable, Hashable {

        /// Xcode's build folders. 13 GB on this Mac, the largest honest win in the section.
        case xcodeBuildOutput

        /// A store where every file is named after its own checksum. Firefox, Chrome and Homebrew
        /// on this Mac.
        case contentAddressedCache

        /// A download that never finished. The extension is the claim.
        case halfFinishedDownload

        /// ⛔ **Reported with no button.** The simulator disk images macOS downloaded.
        case simulatorRuntime

        var id: String { rawValue }

        /// What it is called on the row.
        var label: String {
            switch self {
            case .xcodeBuildOutput:      "Xcode build folders"
            case .contentAddressedCache: "Cache files"
            case .halfFinishedDownload:  "Half-finished downloads"
            case .simulatorRuntime:      "iPhone simulator software"
            }
        }

        /// ⭐ **Question 1 — what it is**, in the words a person would use.
        var whatItIs: String {
            switch self {
            case .xcodeBuildOutput:
                "What Xcode produced the last time it built a project."
            case .contentAddressedCache:
                "A store where every file is named after a checksum of what is inside it, which is "
                + "how a program keeps a copy of something it can get again."
            case .halfFinishedDownload:
                "A download that stopped part way. It is not a usable file yet."
            case .simulatorRuntime:
                "The iPhone, iPad and Watch software Xcode downloaded so it can run a simulator."
            }
        }

        /// ⭐ **Question 2 — how it comes back.** If this cannot name the program that writes it
        /// again, the case does not belong in this enum.
        var howItComesBack: String {
            switch self {
            case .xcodeBuildOutput:
                "Xcode writes it again the next time you build."
            case .contentAddressedCache:
                "The program that made it fetches or works it out again the next time it needs it."
            case .halfFinishedDownload:
                "Your browser writes it again if you start the download over."
            case .simulatorRuntime:
                "Xcode downloads it again from Apple if you need that simulator."
            }
        }

        /// ⭐ **Question 3 — what breaks if we are wrong**, stated as the cost and not as a promise
        /// that we are not.
        var ifWeAreWrong: String {
            switch self {
            case .xcodeBuildOutput:
                "One build takes longer. Your project's own files are somewhere else entirely."
            case .contentAddressedCache:
                "A page loads slowly once, or a download runs again."
            case .halfFinishedDownload:
                "You start the download again from the beginning."
            case .simulatorRuntime:
                "Nothing — Wellkept cannot touch these at all."
            }
        }

        /// ⭐ **Question 4 — whether it may arrive ticked.**
        ///
        /// ⛔ `false` for `.simulatorRuntime`, and it is not a near miss: those files are on the
        /// side of the disk macOS keeps to itself, so there is no button either.
        var mayBeTicked: Bool { self != .simulatorRuntime }

        /// ⚠️ Whether the 30-day filter may untick this. See the file note: it earns its place on
        /// one category and would gut the other two.
        var theAnnoyanceFilterApplies: Bool { self == .halfFinishedDownload }

        /// The sentence that goes on the row as `Item.reason` — what it is, and what puts it back.
        var reason: String { "\(whatItIs) \(howItComesBack)" }

        /// Every category is the machine's. That is what the enum means.
        var origin: Origin { .machineJunk }
    }

    // MARK: - ⭐ The verdict, and the three answers there are

    /// ⚠️ **There are exactly three, and the shape is the safety.**
    ///
    /// There is no "junk, probably" and no "junk but leave it unticked because it makes me nervous".
    /// A category we would not tick is not a category; it goes in the rejection table with its size
    /// and its reason. The only junk that arrives without a tick is junk **nothing can move**, and
    /// that state carries the reason with it.
    enum Verdict: Sendable, Equatable, Hashable {

        /// The machine's, and the engine can hold it.
        case junk(Category)

        /// The machine's, and nothing we can do reaches it. Reported with its size and no button.
        case nothingCanMoveIt(Category, why: String)

        /// ⭐ **The default, and the answer to every question this file cannot answer.**
        case yours(String)

        var category: Category? {
            switch self {
            case let .junk(category):              category
            case let .nothingCanMoveIt(category, _): category
            case .yours:                            nil
            }
        }
    }

    /// What the classifier concluded, in the three fields `Item.init` wants plus the tick.
    struct Judgement: Sendable, Equatable, Hashable {

        let verdict: Verdict

        /// ⭐ Whether this arrives with its box ticked. **Never true for anything but `.junk`.**
        let arrivesTicked: Bool

        /// When it is junk we could tick and did not, the reason, in a sentence. `nil` otherwise.
        let notTickedBecause: String?

        var category: Category? { verdict.category }

        /// ⭐ For `Item.origin`.
        var origin: Origin {
            switch verdict {
            case .junk, .nothingCanMoveIt: .machineJunk
            case .yours:                   .yours
            }
        }

        /// For `Item.handling`. ⚠️ `.notCheckedYet` is the honest answer for everything else: a full
        /// `Movable.check` is a syscall per item and a scan finds thousands, so the engine refuses
        /// in place at press time rather than in bulk at scan time.
        var handling: Handling {
            switch verdict {
            case let .nothingCanMoveIt(_, why): .cannot(why)
            case .junk, .yours:                 .notCheckedYet
            }
        }

        /// For `Item.reason` — always present, always on the row.
        var reason: String {
            switch verdict {
            case let .junk(category):               category.reason
            case let .nothingCanMoveIt(category, why): "\(category.whatItIs) \(why)"
            case let .yours(reason):                reason
            }
        }

        /// ⭐ **Whether the walk should stop here.**
        ///
        /// A folder that is junk is junk whole. Descending into it and judging its children again
        /// counts the same bytes twice and offers a person the same thing at four depths.
        var stopHere: Bool { verdict.category != nil }

        /// The house default. Anything unclassified is the person's, is never ticked, and is never
        /// swept.
        static func yours(_ reason: String) -> Judgement {
            Judgement(verdict: .yours(reason), arrivesTicked: false, notTickedBecause: nil)
        }
    }

    // MARK: - What the classifier is shown

    /// ⚠️ **Names, never contents.** One directory listing and one `lstat`, which is the whole
    /// evidence base this file is allowed.
    struct Subject: Sendable, Equatable, Hashable {

        /// The path as the filesystem spells it.
        let path: String

        let isDirectory: Bool

        /// The immediate children's **names**. Empty for a file.
        let entries: [String]

        /// ⚠️ `true` when the folder had more children than `entriesCap` and the listing was cut
        /// short. **A truncated listing convicts nobody** — see `theWholeListingOrNothing`.
        let listingWasCutShort: Bool

        let modifiedOn: Date?

        init(path: String,
             isDirectory: Bool,
             entries: [String] = [],
             listingWasCutShort: Bool = false,
             modifiedOn: Date? = nil) {
            self.path = path
            self.isDirectory = isDirectory
            self.entries = entries
            self.listingWasCutShort = listingWasCutShort
            self.modifiedOn = modifiedOn
        }

        var name: String { (path as NSString).lastPathComponent }

        /// The name of the folder this sits in.
        var parentName: String {
            ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
        }

        /// Read one thing off the disk: an `lstat` and, for a folder, a listing.
        ///
        /// ⚠️ Nothing here opens a file. `contentsOfDirectory` reads the directory, which is the
        /// same act the walk that found this already performed.
        static func onDisk(_ url: URL) -> Subject? {
            let path = url.path(percentEncoded: false)
            var status = stat()
            guard lstat(path, &status) == 0 else { return nil }

            let isDirectory = (status.st_mode & S_IFMT) == S_IFDIR
            let modified = Date(timeIntervalSince1970: TimeInterval(status.st_mtimespec.tv_sec))

            guard isDirectory else {
                return Subject(path: path, isDirectory: false, modifiedOn: modified)
            }

            let all = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            let tooMany = all.count > entriesCap
            return Subject(path: path,
                           isDirectory: true,
                           entries: tooMany ? Array(all.prefix(entriesCap)) : all,
                           listingWasCutShort: tooMany,
                           modifiedOn: modified)
        }
    }

    /// How many names we will look at before giving up on a folder.
    ///
    /// Reading names is cheap — a browser cache with forty thousand of them lists in a few
    /// milliseconds — so the cap is high enough that no real cache reaches it.
    static let entriesCap = 50_000

    /// ⚠️ **A folder we could not list in full is not junk.**
    ///
    /// The cache rule works by finding nothing a person would recognise. Sampling turns that into
    /// "we found nothing recognisable in the part we looked at", and one audiobook at position
    /// thirty thousand is exactly the file the whole rule exists to catch.
    static let theWholeListingOrNothing =
        "A folder too large to list in full is left alone, because the rule that protects your files "
        + "works by looking at every name in it."

    // MARK: - ⭐ The judgement

    /// ⭐ **The one question the scanner asks about every single thing it finds.**
    ///
    /// - Parameters:
    ///   - subject: names and dates only.
    ///   - foundBecause: the scanner's own sentence, used when nothing here convicts. It becomes
    ///     `Item.reason` for the person's own files, which is most of what a scan finds.
    ///   - home: the home folder.
    ///   - now: for the annoyance filter and the in-flight check.
    static func judge(_ subject: Subject,
                      foundBecause: String = "It is one of the largest things here.",
                      home: URL = StorageManifest.home(),
                      now: Date = Date()) -> Judgement {

        // ⛔ The refusal list first, and it is absolute. A Photos library, a project's history, the
        // inside of an app: if `ScanPolicy` will not let a button be drawn on it, this file will not
        // call it junk we could tick either.
        if let refusal = ScanPolicy.refusal(for: subject.path, home: home) {
            if let category = category(of: subject, home: home, now: now) {
                return Judgement(verdict: .nothingCanMoveIt(category, why: refusal.why),
                                 arrivesTicked: false,
                                 notTickedBecause: refusal.why)
            }
            return .yours(refusal.why)
        }

        // ⚠️ Something is writing to it right now. Not offered, and it says why.
        if isADownloadInProgress(subject, now: now) { return .yours(stillArriving) }

        guard let category = category(of: subject, home: home, now: now) else {
            return .yours(foundBecause)
        }

        guard category.mayBeTicked else {
            return Judgement(verdict: .nothingCanMoveIt(category, why: whyARuntimeHasNoButton),
                             arrivesTicked: false,
                             notTickedBecause: whyARuntimeHasNoButton)
        }

        // ⚠️ The annoyance filter, on the one category where it is not a lie. It can only ever take
        // a tick away.
        if category.theAnnoyanceFilterApplies,
           ScanPolicy.isRecentlyUsed(subject.modifiedOn, now: now) {
            return Judgement(verdict: .junk(category),
                             arrivesTicked: false,
                             notTickedBecause: usedThisMonth)
        }

        return Judgement(verdict: .junk(category), arrivesTicked: true, notTickedBecause: nil)
    }

    /// Why something the machine made is still not ticked.
    static let usedThisMonth =
        "You were using this within the last month, so it is left for you to decide."

    /// ⭐ **Which category, if any.** The order matters only for speed; no two of these can match
    /// the same thing.
    static func category(of subject: Subject,
                         home: URL = StorageManifest.home(),
                         now: Date = Date()) -> Category? {
        if isASimulatorRuntimeImage(subject.path) { return .simulatorRuntime }
        if isXcodeBuildOutput(subject) { return .xcodeBuildOutput }
        if isAHalfFinishedDownload(subject, now: now) { return .halfFinishedDownload }
        if isAContentAddressedCache(subject, home: home) { return .contentAddressedCache }
        return nil
    }

    // MARK: - ⭐ Xcode's build folders — 13 GB here

    /// The three names Xcode writes into every derived-data folder it makes.
    ///
    /// ⚠️ **This is identity and not location**, and the difference is measurable: this Mac has a
    /// folder called `Lode-desktop-launcher` sitting beside seventeen others named
    /// `Waypoint-djcjvzisnpplxdfssrrwkaetabzs`. A rule that matched Xcode's usual
    /// `<project>-<28 letters>` shape would have missed it and left 13 GB partly unaccounted for. A
    /// rule that reads what is inside catches both, and catches a project whose derived data was
    /// pointed somewhere else entirely.
    ///
    /// Three markers, not one: `info.plist` is Xcode's own note saying which workspace this was
    /// built from, `Build` is where the products go, and `.noindex` is Apple's suffix telling
    /// Spotlight to stay out — which nobody types by hand.
    static func isXcodeBuildOutput(_ subject: Subject) -> Bool {
        guard subject.isDirectory, !subject.listingWasCutShort else { return false }

        let names = Set(subject.entries)
        if names.contains("info.plist"),
           names.contains("Build"),
           subject.entries.contains(where: { $0.hasSuffix(noIndexSuffix) }) {
            return true
        }

        // Xcode's shared caches — `ModuleCache.noindex` alone is 4.4 GB here. They carry no marker
        // of their own, so this is the one rule in the file where the parent's name does work. The
        // mitigation is that both halves still point at a tool rather than at a person: the suffix
        // is Apple's do-not-index marker, and `DerivedData` is a folder Xcode creates and owns.
        return subject.name.hasSuffix(noIndexSuffix) && subject.parentName == "DerivedData"
    }

    /// Apple's suffix meaning "Spotlight, stay out of here".
    static let noIndexSuffix = ".noindex"

    // MARK: - ⭐ A content-addressed cache — 1.3 GB here

    /// ⭐ **A store where every file is named after its own checksum.**
    ///
    /// The name *is* the regeneration story: a program that files something under a hash of its
    /// contents is a program that can recognise the same thing again if it fetches it a second
    /// time. Nothing a person made is filed that way, because a person has to be able to find it.
    ///
    /// Three stores on this Mac pass, with one rule between them:
    ///
    /// | Store | An entry looks like | Size |
    /// |---|---|---|
    /// | Firefox | `001A35731806701800B01AD330846DA5B7176DA3` | 760 MB |
    /// | Chrome | `001a2f37ae4468af_0` | 434 MB |
    /// | Homebrew | `0132997974d2…6674f1ad--gettext-1.0.bottle_manifest.json` | 155 MB |
    ///
    /// ⚠️ **And the audiobook fails it twice**: `com.apple.bookassetd` holds a folder called
    /// `1442759222`, which is ten characters where sixteen are needed, and that folder holds
    /// `Track 1.m4b`, which has a name a person can read and an extension a person recognises.
    /// Neither test knows anything about audiobooks. That is the point.
    static func isAContentAddressedCache(_ subject: Subject,
                                         home: URL = StorageManifest.home()) -> Bool {
        guard subject.isDirectory, !subject.listingWasCutShort else { return false }
        // ⚠️ Location narrowing, and it is the only thing location does in this file. A store filed
        // under checksums is also what a backup looks like from the outside, so we look for one
        // only in the two places the system itself designates as scratch.
        guard isSomewhereTheSystemCallsACache(subject.path, home: home) else { return false }

        var hashed = 0
        for entry in subject.entries {
            if storeBookkeepingNames.contains(entry) { continue }
            // ⭐ **One name a person could read and the whole folder is theirs.** Not a ratio, not a
            // majority — one. `Track 1.m4b` is why.
            guard looksLikeAChecksum(entry) else { return false }
            hashed += 1
        }
        return hashed >= smallestCacheWorthTheRisk
    }

    /// How many checksum-named files it takes before a folder is a store rather than a coincidence.
    static let smallestCacheWorthTheRisk = 8

    /// The handful of names a content-addressed store keeps beside its contents.
    ///
    /// ⚠️ Deliberately three, and it does not grow without a measurement. Every name added here is
    /// a name that no longer has to look like a checksum, and the rule's whole strength is that
    /// nothing in the folder looks like anything.
    static let storeBookkeepingNames: Set<String> = [".DS_Store", "index", "index-dir"]

    /// ⚠️ Whether a path is inside one of the two places macOS and unix set aside for caches.
    ///
    /// **This narrows the search and convicts nobody.** The audiobook is inside `~/Library/Caches`
    /// and survives; a project's own `cache` folder is outside both and is never looked at, because
    /// a project folder is somebody's workshop and we do not know what is half-finished in there.
    static func isSomewhereTheSystemCallsACache(_ path: String,
                                                home: URL = StorageManifest.home()) -> Bool {
        let roots = [home.appending(path: "Library/Caches").path(percentEncoded: false),
                     home.appending(path: ".cache").path(percentEncoded: false)]
        // ⚠️ Strictly inside. `isInside` counts a root as being inside itself, and the one thing
        // this section must never offer to set aside in a single press is the whole cache folder.
        guard !roots.contains(where: { Movable.isInside($0, any: [path]) }) else { return false }
        return Movable.isInside(path, any: roots)
    }

    /// ⭐ **A name that is a checksum**: at least sixteen leading hexadecimal characters, and then
    /// either nothing at all or a separator.
    ///
    /// Sixteen because that is Chrome's key length and it is already 2^64 — and because the store
    /// number on the audiobook's folder is ten digits, which are hexadecimal characters too. Six
    /// more is the difference between a rule and an accident.
    static func looksLikeAChecksum(_ name: String) -> Bool {
        guard !carriesAnExtensionAPersonWouldRecognise(name) else { return false }

        var hex = 0
        var rest = Substring(name)
        while let character = rest.first, character.isHexDigit {
            hex += 1
            rest = rest.dropFirst()
        }
        guard hex >= checksumPrefixLength else { return false }
        guard let next = rest.first else { return true }
        return checksumSeparators.contains(next)
    }

    static let checksumPrefixLength = 16
    static let checksumSeparators: Set<Character> = ["-", "_", ".", "@", "~"]

    /// ⚠️ **The extensions of things people make and keep.**
    ///
    /// A file with one of these is never part of a cache, wherever it is sitting and whatever is
    /// around it. This is the second, independent reason the audiobook survives: `.m4b`.
    ///
    /// It deliberately does not list `.json`, `.tar.gz`, `.plist` or the rest of the machine's own
    /// formats — Homebrew's downloads end in `.json` and `.tar.gz`, and a rule that refused those
    /// would refuse the only thing it was built to find.
    static let extensionsAPersonWouldRecognise: Set<String> = [
        // Sound
        "m4b", "m4a", "m4p", "mp3", "aac", "aiff", "aif", "wav", "flac", "alac", "aax", "ogg",
        // Moving pictures
        "mov", "mp4", "m4v", "avi", "mkv", "mpg", "mpeg", "wmv", "webm",
        // Still pictures
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "tif", "bmp", "raw", "dng", "cr2",
        "cr3", "nef", "arw", "orf", "raf", "psd", "ai", "sketch",
        // Documents
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "rtf",
        "rtfd", "txt", "md", "csv", "odt", "ods",
        // Books
        "epub", "mobi", "ibooks", "azw", "azw3",
    ]

    static func carriesAnExtensionAPersonWouldRecognise(_ name: String) -> Bool {
        let ending = (name as NSString).pathExtension.lowercased()
        guard !ending.isEmpty else { return false }
        return extensionsAPersonWouldRecognise.contains(ending)
    }

    // MARK: - A half-finished download

    /// What the browsers call a file that is not a file yet.
    static let unfinishedDownloadEndings: Set<String> = [
        "crdownload",   // Chrome, Edge, Brave
        "part",         // Firefox
        "partial",      // older Edge
        "download",     // Safari — this one is a package, not a file
        "opdownload",   // Opera
    ]

    /// ⚠️ **A download in progress is not offered at all**, not merely left unticked.
    ///
    /// A file something is writing to right now is the one case where a move succeeds and the
    /// program keeps writing into a copy nobody will ever look at again — the failure the
    /// quarantine engine measured and the reason it counts open files before it moves anything.
    static let inFlightMinutes = 60.0

    static func isAHalfFinishedDownload(_ subject: Subject, now: Date = Date()) -> Bool {
        let ending = (subject.path as NSString).pathExtension.lowercased()
        guard unfinishedDownloadEndings.contains(ending) else { return false }
        guard let modified = subject.modifiedOn else { return true }
        return now.timeIntervalSince(modified) > inFlightMinutes * 60
    }

    /// Whether this carries a browser's unfinished-download ending **and** was written within the
    /// hour, which is the one case that is not offered at all.
    static func isADownloadInProgress(_ subject: Subject, now: Date = Date()) -> Bool {
        let ending = (subject.path as NSString).pathExtension.lowercased()
        guard unfinishedDownloadEndings.contains(ending), let modified = subject.modifiedOn
        else { return false }
        return now.timeIntervalSince(modified) <= inFlightMinutes * 60
    }

    /// The sentence for one that is still being written.
    static let stillArriving =
        "Something is writing to this right now — it looks like a download in progress."

    // MARK: - ⛔ The simulator runtimes: reported, and no button

    /// ⚠️ **The measurement that changed what this reports, taken 2026-08-28 on macOS 26.6.2.**
    ///
    /// The worksheet says the simulator runtimes are "30 GB of root-owned read-only disk images" at
    /// `/Library/Developer/CoreSimulator/Profiles/Runtimes`. On this Mac, today:
    ///
    /// - **That folder does not exist.** Apple moved the runtimes into the MobileAsset system, and
    ///   `ScanPolicy`'s refusal entry names a path no current Mac has. The refusal costs nothing —
    ///   it can only ever subtract — but it also protects nothing, so this is where the honest
    ///   report has to come from.
    /// - They are **mounted as separate sealed read-only APFS volumes** under
    ///   `/Library/Developer/CoreSimulator/Volumes/`. `ScanPolicy.descend` therefore refuses them as
    ///   another volume, correctly, which means **no walk in this section will ever see them**.
    /// - **The mounted size and the disk cost are not the same number, and they are 12 GB apart.**
    ///   The two volumes report 16 GiB and 8.2 GiB used — 24 GB. The disk images behind them are
    ///   7.9 GB and 3.7 GB — **11.6 GB**. The images are compressed. Reporting the mounted figure
    ///   would overstate this by more than double, which is exactly the kind of number this section
    ///   exists not to print.
    ///
    /// So this reads the images, not the mounts, and it reads them by `lstat`, not by walking.
    static let whyARuntimeHasNoButton =
        "It is a disk image macOS downloaded and mounted, on the part of the disk it keeps to "
        + "itself. Wellkept cannot set it aside, so there would be no thirty-day undo. Xcode removes "
        + "these from Settings ▸ Components."

    /// Where Apple keeps downloaded system assets. On the Data volume, reached through a firmlink.
    static let assetStore = "/System/Library/AssetsV2"

    /// The asset folders that hold simulator runtimes.
    static let runtimeAssetPrefix = "com_apple_MobileAsset_"
    static let runtimeAssetSuffix = "SimulatorRuntime"

    /// Whether a path is one of the runtime disk images.
    ///
    /// ⚠️ No walk in this section will ever hand this a path — the runtimes mount as their own
    /// volumes and `ScanPolicy.descend` refuses another volume. It is here so that a walk which one
    /// day *does* reach one recognises it rather than offering it, and because `simulatorRuntimes()`
    /// and this rule have to agree about what a runtime is.
    static func isASimulatorRuntimeImage(_ path: String) -> Bool {
        guard (path as NSString).pathExtension.lowercased() == "dmg" else { return false }
        guard Movable.isInside(path, any: [assetStore]) else { return false }
        return path.contains(runtimeAssetPrefix) && path.contains(runtimeAssetSuffix)
    }

    /// One simulator runtime, as the image on the disk rather than as the volume it mounts to.
    struct Runtime: Sendable, Equatable, Hashable, Identifiable {
        /// `iOS`, `watchOS`, `xrOS` — taken from the asset folder's name.
        let platform: String
        /// The disk image.
        let path: String
        /// ⭐ The image's own size on disk, which is the space it actually costs.
        let bytes: SizeOnDisk
        let inode: UInt64

        var id: String { path }
        var name: String { "\(platform) simulator" }
    }

    /// Every simulator runtime image on this Mac, largest first.
    ///
    /// Three directory listings and one `lstat` per image. No subprocess, no privilege, no dialog.
    static func simulatorRuntimes(assetStore: String = assetStore) -> [Runtime] {
        let manager = FileManager.default
        guard let kinds = try? manager.contentsOfDirectory(atPath: assetStore) else { return [] }

        var found: [Runtime] = []
        for kind in kinds where kind.hasPrefix(runtimeAssetPrefix) && kind.hasSuffix(runtimeAssetSuffix) {
            let platform = String(kind.dropFirst(runtimeAssetPrefix.count).dropLast(runtimeAssetSuffix.count))
            let kindPath = "\(assetStore)/\(kind)"
            guard let assets = try? manager.contentsOfDirectory(atPath: kindPath) else { continue }

            for asset in assets {
                let restore = "\(kindPath)/\(asset)/AssetData/Restore"
                guard let images = try? manager.contentsOfDirectory(atPath: restore) else { continue }
                for image in images where (image as NSString).pathExtension.lowercased() == "dmg" {
                    let path = "\(restore)/\(image)"
                    var status = stat()
                    guard lstat(path, &status) == 0 else { continue }
                    found.append(Runtime(platform: platform.isEmpty ? "Simulator" : platform,
                                         path: path,
                                         // ⭐ Blocks, not `st_size`. Size on disk is the only size
                                         // this section prints.
                                         bytes: SizeOnDisk(Int64(status.st_blocks) * 512),
                                         inode: UInt64(status.st_ino)))
                }
            }
        }
        return found.sorted { $0.bytes > $1.bytes }
    }

    /// How many simulator runtimes are mounted right now.
    ///
    /// Only for the row's sentence — the sizes come from the images. `getfsstat` is a syscall that
    /// reads the mount table; it touches nothing.
    static func mountedSimulatorVolumes(under prefix: String = "/Library/Developer/CoreSimulator/Volumes/") -> [String] {
        let capacity = getfsstat(nil, 0, MNT_NOWAIT)
        guard capacity > 0 else { return [] }

        // ⚠️ A raw buffer rather than a Swift array: `statfs` is both a struct and a function here,
        // and `[statfs](repeating: statfs(), …)` resolves to the function.
        let table = UnsafeMutablePointer<statfs>.allocate(capacity: Int(capacity))
        defer { table.deallocate() }

        let read = getfsstat(table, Int32(MemoryLayout<statfs>.size) * capacity, MNT_NOWAIT)
        guard read > 0 else { return [] }

        var mounted: [String] = []
        for index in 0..<Int(read) {
            let point = withUnsafePointer(to: table[index].f_mntonname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            if point.hasPrefix(prefix) { mounted.append(point) }
        }
        return mounted.sorted()
    }

    /// ⛔ **The runtimes as rows: a size, an explanation, and no offer.**
    ///
    /// `Handling.cannot` is what removes the button, and `recoverableToday` is `nothing` because
    /// nothing we could do returns those bytes. The sentence says where they do come off.
    static func simulatorRuntimeItems(assetStore: String = assetStore) -> [Item] {
        let runtimes = simulatorRuntimes(assetStore: assetStore)
        guard !runtimes.isEmpty else { return [] }

        let volume = Movable.volume(of: assetStore)
        return runtimes.map { runtime in
            Item(identity: ItemIdentity(volumeUUID: volume?.uuid,
                                        volumeDevice: volume?.device ?? assetStore,
                                        inode: runtime.inode),
                 path: runtime.path,
                 name: runtime.name,
                 bytes: Bytes(onDisk: runtime.bytes, recoverableToday: .nothing),
                 kind: .diskImage,
                 origin: .machineJunk,
                 handling: .cannot(whyARuntimeHasNoButton),
                 reason: "\(Category.simulatorRuntime.whatItIs) \(whyARuntimeHasNoButton)")
        }
    }

    // MARK: - Building the row's items

    /// One classified thing: the `Item` the row draws, and whether its box arrives ticked.
    struct Classified: Sendable, Equatable, Hashable, Identifiable {
        let item: Item
        let judgement: Judgement

        var id: String { item.id }
        var arrivesTicked: Bool { judgement.arrivesTicked }
        var stopHere: Bool { judgement.stopHere }
    }

    /// ⭐ **Build the `Item` from the judgement, so no scanner has to remember which three fields
    /// the classification fills in.**
    ///
    /// A scanner that builds its own `Item` and forgets `origin` gets `.yours`, which is safe. A
    /// scanner that builds its own and passes `.machineJunk` by hand has just written a second
    /// classifier. This is the way that is neither.
    static func classify(_ subject: Subject,
                         identity: ItemIdentity,
                         bytes: Bytes,
                         kind: ItemKind,
                         cloudStanding: CloudStanding = .onThisMac,
                         lastOpenedOn: Date? = nil,
                         foundBecause: String = "It is one of the largest things here.",
                         home: URL = StorageManifest.home(),
                         now: Date = Date()) -> Classified {
        let judgement = judge(subject, foundBecause: foundBecause, home: home, now: now)
        let item = Item(identity: identity,
                        path: subject.path,
                        bytes: bytes,
                        kind: kind,
                        origin: judgement.origin,
                        cloudStanding: cloudStanding,
                        handling: judgement.handling,
                        modifiedOn: subject.modifiedOn,
                        lastOpenedOn: lastOpenedOn,
                        reason: judgement.reason)

        // ⭐ The tick is the intersection of what this file decided and what `Item` itself permits.
        // `Item.mayBePreSelected` also refuses anything that is not on this Mac, which is how a file
        // that lives only in iCloud can never arrive ticked no matter what category it fell into.
        return Classified(item: item,
                          judgement: Judgement(verdict: judgement.verdict,
                                               arrivesTicked: judgement.arrivesTicked && item.mayBePreSelected,
                                               notTickedBecause: judgement.notTickedBecause))
    }

    /// The things that arrive ticked, out of a set that has been classified.
    ///
    /// ⚠️ `StorageRow.preSelected` is the **ceiling** — everything the row would permit to be
    /// ticked. This is the **choice made inside it**, and it is always a subset. Nothing here can
    /// tick something the row would not.
    static func arrivingTicked(_ classified: [Classified]) -> [Item] {
        classified.filter(\.arrivesTicked).map(\.item)
    }
}

import CoreServices
import Foundation
import WellkeptCore

//  InventoryReader.swift
//  Wellkept — App/Apps
//
//  **The list of apps a person would recognise, and one fact about each of them.**
//
//  It produces the `.installed` row and the `AppsInventory` block above it. Nothing here decides
//  whether an app is current — that is the update reader's job, and it applies its answers to this
//  inventory rather than gathering one of its own, because gathering one costs seven seconds.
//
//  ## ⚠️ 422 bundles, and 31 is the number a person recognises
//
//  Measured on an M3 running macOS 26.6.2, 2026-08-27. `system_profiler` reports **422** app
//  bundles on this Mac. Broken up by where they live:
//
//      30   /Applications and ~/Applications          the apps a person would name
//       0   /Applications/Utilities                   empty here, and not on every Mac
//      65   /System/Applications (+ its Utilities)     the apps that come with macOS
//      327  everywhere else                           components, helpers, build products
//
//  117 of that last group are in `/System/Library/CoreServices`, 18 are input methods, 11 are
//  Automator droplets in a Documents folder, 6 live inside `Xcode.app`, 5 inside
//  `Finder.app`. Not one of them is a thing anybody installed or would think to remove. **A section
//  that opened with "422 apps installed" would be wrong by a factor of three on its first line, and
//  wrong in the direction that sells cleaners.**
//
//  So the three numbers are kept apart and all three are said: **31 apps**, **65 that come with
//  macOS**, **327 other bundles**. They add to 422 plus Safari, which is the next problem.
//
//  ## ⚠️ Take LaunchServices' line on what is an app — never re-derive it from paths
//
//  Everything below starts from macOS's own inventory (`system_profiler SPApplicationsDataType`,
//  which is LaunchServices' answer in a readable form). The folders are used only to decide **which
//  of macOS's apps belong on which list** — never to decide what an app is. Walking `/Applications`
//  for `*.app` looks like the same thing and is not: it finds bundles LaunchServices does not
//  consider apps, misses the version, architecture and signer that come free in the same call, and
//  has to be taught by hand about every folder Apple invents next.
//
//  ## ⚠️ Safari is added by hand, and the row says so
//
//  `/Applications/Safari.app` is a symlink into `/System/Cryptexes/App`, carrying restricted and
//  hidden flags. It is **absent from macOS's own inventory entirely** — 422 entries, no Safari — and
//  it is the 4th most-launched app on this Mac. Its `Info.plist` reads fine by path
//  (`com.apple.Safari`, 26.6.2, build 21624.5.1.11.3) and its signature and architecture read fine
//  too, so the only thing missing was the row. Adding it silently would be inventing a line; adding
//  it and marking `addedByHand` is a fact the person can check.
//
//  ## ⚠️ We read who signed an app. We never claim to verify one
//
//  `spctl` is banned in this project: 3 minutes 9 seconds for 29 apps, and it is slow *because* it
//  asks Apple about every app with no stapled ticket — checking your apps would report your apps to
//  Apple. It is also wrong in the direction that frightens people. **11 of the 31 apps here "fail"**
//  full verification: 8 purely because Finder tags were added to the bundle, one because LibreOffice
//  writes cache files inside itself the first time it runs. Not one had been tampered with.
//
//  The signer comes out of the same `system_profiler` call at no extra cost, and the Security
//  framework reads it directly for the handful of entries that carry none. Neither path calls
//  `SecStaticCodeCheckValidity`, which is the verification call, and neither ever should.
//
//  ## ⚠️ Intel-only is a plain labelled fact, and that is deliberate
//
//  An Intel-only app gets `AppArchitecture.intelOnly` and nothing else: no countdown, no "will stop
//  working", never a problem colour, and it cannot reach Overview because `AppsRow.severity` is a
//  computed constant. This cuts the other way from the Hardware section's ruling on missing security
//  updates, on purpose, for three reasons that all have to hold before a warning is worth making:
//
//  1. **Nothing about a Rosetta app is a security matter.** An old app with a known vulnerability
//     would be — and we cannot honestly detect that, which is why CVE matching was dropped.
//  2. **macOS already warns at launch**, in Apple's own words, at the moment it is relevant.
//  3. **Only the developer can act.** There is no button we could draw. A warning on a screen where
//     nothing the person presses changes the answer is a warning that teaches them to ignore
//     warnings — and the next one might matter.
//
//  Do not "fix" this by promoting it. The ruling is dated 2026-08-27, and it is in
//  `APPS-QUESTIONS.md`.
//
//  ## ⚠️ "Last opened" is a fact, never a finding
//
//  macOS records it in Spotlight (`kMDItemLastUsedDate`) and reports **nothing at all for 6 of the
//  31 apps here — including Keynote and Teams, both demonstrably run**. A blank is harmless. "You
//  have not opened this in two years" built on the same blank is an accusation, and it would be
//  wrong six times out of thirty-one on a Mac where nothing is wrong. That is why "apps you have not
//  opened" is not a finding anywhere in this section.
//
//  ## Timing, and why this is cancellable
//
//  `system_profiler` alone is 7–8 seconds cold. Weighing all 31 bundles is another 5 (2.7 of it
//  `Xcode.app`, 4.3 GB across roughly 200,000 files). That is why **Apps does not run on launch**,
//  why every phase reports progress in words, and why cancellation is checked between every app.

enum InventoryReader {

    // MARK: - Where a person's apps live

    /// The folders whose contents a person would call "my apps", and the folder macOS keeps its own
    /// in.
    ///
    /// ⚠️ **These decide which list an app belongs on. They never decide what an app is** — see the
    /// header. An entry macOS did not report is not here to be filed, whatever is in the folder.
    struct Folders: Sendable, Hashable {

        /// `/Applications`, `/Applications/Utilities` and `~/Applications`.
        let mine: [URL]

        /// `/System/Applications` and its `Utilities` folder. **Grouped separately**: these are 65
        /// apps here, they are updated by a macOS update and by nothing else, and folding them into
        /// the person's list would double the count on the section's first line.
        let macOS: [URL]

        init(mine: [URL], macOS: [URL]) {
            self.mine = mine
            self.macOS = macOS
        }

        static var standard: Folders {
            Folders(mine: [URL(fileURLWithPath: "/Applications"),
                           URL(fileURLWithPath: "/Applications/Utilities"),
                           FileManager.default.homeDirectoryForCurrentUser
                               .appendingPathComponent("Applications")],
                    macOS: [URL(fileURLWithPath: "/System/Applications"),
                            URL(fileURLWithPath: "/System/Applications/Utilities")])
        }

        /// Where Homebrew keeps what it has installed, on Apple silicon and on Intel.
        static let caskrooms = [URL(fileURLWithPath: "/opt/homebrew/Caskroom"),
                                URL(fileURLWithPath: "/usr/local/Caskroom")]

        /// Which list an app at this path belongs on, or `nil` for the 327 that belong on neither.
        func group(for path: String) -> Group? {
            let parent = Self.forms(of: URL(fileURLWithPath: path).deletingLastPathComponent())
            if !parent.isDisjoint(with: Self.forms(of: mine)) { return .mine }
            if !parent.isDisjoint(with: Self.forms(of: macOS)) { return .macOS }
            return nil
        }

        /// Both spellings of one folder.
        ///
        /// ⚠️ A Mac's home folder is reachable as `/Users/you` and as
        /// `/System/Volumes/Data/Users/you`, and which one you get depends on who resolved the path
        /// last. Comparing one resolved path against one unresolved path is how `~/Applications`
        /// quietly stops matching on somebody's machine and two of their apps vanish from the list.
        private static func forms(of url: URL) -> Set<String> {
            [url.standardizedFileURL.path, url.resolvingSymlinksInPath().path]
        }

        private static func forms(of urls: [URL]) -> Set<String> {
            urls.reduce(into: Set<String>()) { $0.formUnion(forms(of: $1)) }
        }
    }

    /// Which of the two lists an app is on.
    enum Group: Sendable, Hashable {
        /// An app the person installed, or one that came in `~/Applications`.
        case mine
        /// An app that comes with macOS.
        case macOS
    }

    // MARK: - What it is doing while a person waits

    /// The three phases, in the order they run.
    ///
    /// Said out loud because the whole read is about thirteen seconds and a spinner over a blank
    /// panel for thirteen seconds is indistinguishable from a hang.
    enum Stage: String, CaseIterable, Sendable, Hashable {

        /// The `system_profiler` call. 7–8 seconds, and there is no progress to report inside it —
        /// it answers all at once or not at all.
        case askingMacOS

        /// Opening each app's `Info.plist`, reading its signature, its dates and its architecture.
        case readingEachApp

        /// Weighing each bundle. The slowest per-app step, and the one worth naming: a person
        /// watching "Measuring Xcode" for three seconds knows nothing is wrong.
        case measuringSizes

        var sentence: String {
            switch self {
            case .askingMacOS:
                "Asking macOS for its list of apps — this one takes a few seconds…"
            case .readingEachApp:
                "Reading each app…"
            case .measuringSizes:
                "Measuring how much space each app takes…"
            }
        }

        /// How far through the read this is, one-based, for the count beside the spinner.
        var step: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

        static var count: Int { allCases.count }
    }

    /// Where the read has got to.
    struct Progress: Sendable, Hashable {

        let stage: Stage

        /// How many apps are done in this stage, and how many there are. Both zero for
        /// `.askingMacOS`, which has nothing to count.
        let done: Int
        let total: Int

        init(stage: Stage, done: Int = 0, total: Int = 0) {
            self.stage = stage
            self.done = max(0, done)
            self.total = max(0, total)
        }

        /// What to put beside the spinner. The count is appended only where there is one, so the
        /// first phase does not read "Asking macOS… 0 of 0".
        var sentence: String {
            total > 0 ? "\(stage.sentence) \(done) of \(total)" : stage.sentence
        }

        /// `nil` where there is nothing to be a fraction of — which is a real state, and better than
        /// a bar that sits at zero for eight seconds and then jumps.
        var fraction: Double? {
            total > 0 ? Double(done) / Double(total) : nil
        }
    }

    // MARK: - What one run produced

    /// The inventory, the macOS apps kept beside it, and the row.
    ///
    /// The macOS apps travel separately rather than inside `AppsInventory` for the reason in
    /// `Folders.macOS`: they are not the person's apps, they are not counted as such, and the one
    /// place they are named is behind Options and in the `.macOS` row.
    struct Answer: Sendable, Hashable {

        /// The person's apps — 31 here, Safari included — and the count of everything else.
        let inventory: AppsInventory

        /// The 65 that come with macOS, in the order macOS reported them.
        let bundledWithMacOS: [InstalledApp]

        /// The `.installed` row.
        let row: AppsRow

        init(inventory: AppsInventory, bundledWithMacOS: [InstalledApp] = [], row: AppsRow) {
            self.inventory = inventory
            self.bundledWithMacOS = bundledWithMacOS
            self.row = row
        }

        /// What we could not read at all, if anything.
        var unreadable: Unreadable? { row.unreadable }
    }

    /// One app and the bundle it was read from.
    ///
    /// It exists for one reason: weighing a bundle needs a path, and `InstalledApp` deliberately has
    /// no path field. Nothing outside this file sees it.
    private struct Found: Sendable {
        let app: InstalledApp
        let url: URL
    }

    // MARK: - Running it

    /// **The whole inventory.** About thirteen seconds on an M3: eight for macOS's own list, five to
    /// weigh the bundles.
    ///
    /// Blocking from beginning to end — a subprocess, several hundred property lists and a directory
    /// walk — so it belongs on a detached task and never where the window is waiting to draw.
    ///
    /// ⚠️ **A cancelled run returns `nil` and nothing else.** It does not return the apps it managed
    /// to read: a list of 17 apps on a Mac with 31 is not a shorter answer, it is a wrong one, and
    /// the first thing anybody would do with it is put "17 apps" on the screen. The one exception
    /// that would be honest — the full list with some sizes missing — is not worth the field it
    /// would need, because a person who cancels is leaving.
    ///
    /// - Parameters:
    ///   - folders: Which folders hold whose apps. Injected so a test can point at a temporary one.
    ///   - report: macOS's own inventory, already gathered. Injected by tests; `nil` runs
    ///     `system_profiler` for real.
    ///   - handAdded: Apps macOS does not list. **Safari, and it took a measurement to earn the
    ///     entry** — see the header.
    ///   - measureSizes: The five-second phase. Off gives every app `bytes == nil`, which the row
    ///     draws as "not measured" rather than as zero.
    ///   - isCancelled: Checked between apps. Defaults to the surrounding task's own flag.
    ///   - progress: Called on the calling thread as each phase advances.
    static func read(folders: Folders = .standard,
                     report: Data? = nil,
                     handAdded: [URL] = [URL(fileURLWithPath: "/Applications/Safari.app")],
                     measureSizes: Bool = true,
                     fileManager: FileManager = .default,
                     isCancelled: () -> Bool = { Task.isCancelled },
                     progress: (Progress) -> Void = { _ in }) -> Answer? {

        let started = Date()

        // 1 — macOS's own list. There is no progress inside this; it answers all at once.
        progress(Progress(stage: .askingMacOS))
        let data = report ?? StartupReader.toolOutput(URL(fileURLWithPath: systemProfiler),
                                                      ["SPApplicationsDataType", "-json"],
                                                      timeout: reportTimeout)
        guard let data, let entries = Entry.all(in: data) else {
            return Answer(inventory: .notCheckedYet, row: couldNotAsk)
        }
        if isCancelled() { return nil }

        // 2 — everything macOS's list does not carry: identifiers, builds, dates, signatures.
        var mine: [Entry] = []
        var macOS: [Entry] = []
        var elsewhere = 0
        for entry in entries {
            switch folders.group(for: entry.path) {
            case .mine:  mine.append(entry)
            case .macOS: macOS.append(entry)
            case nil:    elsewhere += 1
            }
        }

        let brewed = homebrewAppNames(fileManager: fileManager)
        let total = mine.count + macOS.count + handAdded.count
        var done = 0
        progress(Progress(stage: .readingEachApp, done: done, total: total))

        // ⚠️ The bundle's path travels beside the app rather than inside it. `InstalledApp` has no
        // path field on purpose — it is written into the check history, where a path is both
        // personal and useless a year later — and phase 3 has to know where to weigh.
        var found: [Found] = []
        var bundledFound: [Found] = []
        for entry in mine {
            if isCancelled() { return nil }
            found.append(Found(app: app(from: entry, homebrew: brewed, fileManager: fileManager),
                               url: URL(fileURLWithPath: entry.path)))
            done += 1
            progress(Progress(stage: .readingEachApp, done: done, total: total))
        }
        for entry in macOS {
            if isCancelled() { return nil }
            bundledFound.append(Found(app: app(from: entry, homebrew: brewed, fileManager: fileManager),
                                      url: URL(fileURLWithPath: entry.path)))
            done += 1
            progress(Progress(stage: .readingEachApp, done: done, total: total))
        }

        // Safari, and anything else macOS declines to list. Appended last so it can be skipped
        // without a second pass when macOS does list it after all.
        let known = Set(found.map(\.app.bundleID)).union(bundledFound.map(\.app.bundleID))
        for url in handAdded {
            if isCancelled() { return nil }
            if let missing = handAddedApp(at: url, alreadyListed: known, fileManager: fileManager) {
                found.append(Found(app: missing, url: url))
            }
            done += 1
            progress(Progress(stage: .readingEachApp, done: done, total: total))
        }

        // 3 — weighing the bundles. The slow half of the slow half.
        if measureSizes {
            let weighing = found.count + bundledFound.count
            var weighed = 0
            progress(Progress(stage: .measuringSizes, done: weighed, total: weighing))

            func weigh(_ list: inout [Found]) -> Bool {
                for index in list.indices {
                    if isCancelled() { return false }
                    let bytes = bundleSize(of: list[index].url,
                                           fileManager: fileManager,
                                           isCancelled: isCancelled)
                    list[index] = Found(app: list[index].app.withBytes(bytes), url: list[index].url)
                    weighed += 1
                    progress(Progress(stage: .measuringSizes, done: weighed, total: weighing))
                }
                return true
            }
            guard weigh(&found), weigh(&bundledFound) else { return nil }
        }

        let inventory = AppsInventory(apps: found.map(\.app),
                                      otherBundles: elsewhere,
                                      gatheredAt: started)
        let bundled = bundledFound.map(\.app)
        return Answer(inventory: inventory,
                      bundledWithMacOS: bundled,
                      row: row(inventory: inventory, bundledWithMacOS: bundled))
    }

    /// `/usr/sbin/system_profiler`, spelled once.
    static let systemProfiler = "/usr/sbin/system_profiler"

    /// Generous on purpose. 7–8 seconds is the measured figure on a Mac with 422 bundles and a warm
    /// cache; a Mac with a thousand, cold, on a slow disk, is the machine that must not be told its
    /// apps are unreadable because we were impatient.
    static let reportTimeout: TimeInterval = 90

    /// The row for a Mac whose own inventory would not answer.
    ///
    /// `.notReported` rather than a refusal, and the difference matters: no permission on earth
    /// would change this answer, so there is no button to offer and no caveat for Overview to carry
    /// for ever. It still says plainly that we did not see it.
    static var couldNotAsk: AppsRow {
        AppsRow.unreadable(.installed,
                           .notReported,
                           about: "The list of apps",
                           reason: "macOS keeps this list and it did not answer this time. "
                                 + "Checking again usually works.")
    }

    // MARK: - One line of macOS's own inventory

    /// One entry as `system_profiler` writes it.
    ///
    /// Six keys, every one of them optional in practice. `AppBackups.app` in this Mac's
    /// `~/Applications` is an Automator droplet with no version, no identifier and no signature —
    /// a real app on a real Mac that would crash a reader written against the happy case.
    struct Entry: Sendable, Hashable {

        let name: String
        let path: String
        let version: String?

        /// `arch_arm_i64`, `arch_arm`, `arch_i64`, `arch_ios`, `arch_other`.
        let architecture: String?

        /// `apple`, `mac_app_store`, `identified_developer`, `unknown`.
        let obtainedFrom: String?

        /// The certificate chain, leaf first. Empty for anything unsigned or ad-hoc signed.
        let signedBy: [String]

        init(name: String,
             path: String,
             version: String? = nil,
             architecture: String? = nil,
             obtainedFrom: String? = nil,
             signedBy: [String] = []) {
            self.name = name
            self.path = path
            self.version = version
            self.architecture = architecture
            self.obtainedFrom = obtainedFrom
            self.signedBy = signedBy
        }

        /// Every entry in one `system_profiler -json` document, or `nil` where it will not parse.
        ///
        /// ⚠️ `nil` and `[]` are different answers and both are possible. `nil` is "macOS did not
        /// tell us", which becomes an unreadable row; `[]` would be "macOS says there are no apps",
        /// which is a fact, however unlikely.
        static func all(in data: Data) -> [Entry]? {
            guard let object = try? JSONSerialization.jsonObject(with: data),
                  let top = object as? [String: Any],
                  let list = top["SPApplicationsDataType"] as? [[String: Any]] else { return nil }

            return list.compactMap { item in
                guard let path = item["path"] as? String, !path.isEmpty else { return nil }
                let name = (item["_name"] as? String) ?? ""
                return Entry(name: name.isEmpty
                                 ? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                                 : name,
                             path: path,
                             version: text(item["version"]),
                             architecture: text(item["arch_kind"]),
                             obtainedFrom: text(item["obtained_from"]),
                             signedBy: (item["signed_by"] as? [String]) ?? [])
            }
        }

        /// A string that is actually a string and actually has something in it.
        private static func text(_ value: Any?) -> String? {
            guard let string = value as? String else { return nil }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    // MARK: - Turning one entry into one app

    static func app(from entry: Entry,
                    homebrew: Set<String> = [],
                    fileManager: FileManager = .default) -> InstalledApp {
        let url = URL(fileURLWithPath: entry.path)
        let plist = infoPlist(at: url)

        // ⚠️ The identifier is the join key for the whole section — updates, crashes, leftovers all
        // land on it. An app with no identifier gets its path, which is unique and true, rather than
        // a made-up one or a dropped row.
        let bundleID = string(plist?["CFBundleIdentifier"]) ?? entry.path

        let name = entry.name.isEmpty
            ? (string(plist?["CFBundleDisplayName"])
               ?? string(plist?["CFBundleName"])
               ?? bundleID)
            : entry.name

        return InstalledApp(name: name,
                            bundleID: bundleID,
                            version: entry.version ?? string(plist?["CFBundleShortVersionString"]),
                            build: string(plist?["CFBundleVersion"]),
                            bytes: nil,
                            installedAt: installedDate(of: url),
                            lastOpenedAt: lastOpened(at: entry.path),
                            architecture: architecture(entry.architecture, at: url),
                            signedBy: signature(of: entry, at: url),
                            origin: origin(of: entry, homebrew: homebrew),
                            update: .notChecked,
                            addedByHand: false)
    }

    /// An app macOS does not list, read entirely from the bundle itself.
    ///
    /// Returns `nil` when the folder is not there, or when macOS turns out to list the app after
    /// all — a claim that we added a row by hand had better be true.
    static func handAddedApp(at url: URL,
                             alreadyListed: Set<String> = [],
                             fileManager: FileManager = .default) -> InstalledApp? {
        guard fileManager.fileExists(atPath: url.path),
              let plist = infoPlist(at: url),
              let bundleID = string(plist["CFBundleIdentifier"]),
              !alreadyListed.contains(bundleID) else { return nil }

        let name = string(plist["CFBundleDisplayName"])
            ?? string(plist["CFBundleName"])
            ?? url.deletingPathExtension().lastPathComponent

        return InstalledApp(name: name,
                            bundleID: bundleID,
                            version: string(plist["CFBundleShortVersionString"]),
                            build: string(plist["CFBundleVersion"]),
                            bytes: nil,
                            installedAt: installedDate(of: url),
                            lastOpenedAt: lastOpened(at: url.path),
                            architecture: architecture(nil, at: url),
                            signedBy: signature(of: nil, at: url),
                            // Safari is macOS's, and a macOS update is what updates it. The update
                            // reader reads this field rather than knowing about Safari.
                            origin: .bundledWithMacOS,
                            update: .notChecked,
                            addedByHand: true)
    }

    // MARK: - The facts, one at a time

    /// What the app was built for.
    ///
    /// `arch_ios` is an iPhone or iPad app running on Apple silicon — it will not run on an Intel
    /// Mac, which is what `.appleSilicon` says and all it says. `arch_other` and a missing key fall
    /// through to the Mach-O header, which is where Safari's answer comes from.
    static func architecture(_ kind: String?, at url: URL) -> AppArchitecture {
        switch kind {
        case "arch_arm_i64":              return .universal
        case "arch_arm", "arch_ios":      return .appleSilicon
        case "arch_i64", "arch_i32":      return .intelOnly
        default:                          break
        }
        return architectureFromBinary(at: url)
    }

    /// The architectures in the bundle's own executable, for the entries macOS did not classify.
    static func architectureFromBinary(at url: URL) -> AppArchitecture {
        guard let listed = Bundle(url: url)?.executableArchitectures?.map(\.intValue),
              !listed.isEmpty else { return .unknown }

        let arm = listed.contains(NSBundleExecutableArchitectureARM64)
        let intel = listed.contains(NSBundleExecutableArchitectureX86_64)
            || listed.contains(NSBundleExecutableArchitectureI386)

        switch (arm, intel) {
        case (true, true):   return .universal
        case (true, false):  return .appleSilicon
        case (false, true):  return .intelOnly
        case (false, false): return .unknown
        }
    }

    /// **Who signed it — read, never assessed.**
    ///
    /// The chain comes free in the `system_profiler` call. Where it is empty the Security framework
    /// is asked directly, which distinguishes the two answers that matter: an app with no signature
    /// at all, and an app whose signature we could not read. Reporting the second as the first would
    /// be reporting zero because we could not look.
    ///
    /// Nothing here calls `SecStaticCodeCheckValidity`. See the header.
    static func signature(of entry: Entry?, at url: URL) -> SignedBy {
        if let leaf = entry?.signedBy.first,
           let name = StartupReader.organisation(inCertificateSummary: leaf) {
            return named(name)
        }
        switch signerFromDisk(at: url) {
        case let .named(name): return named(name)
        case .notSigned:       return .notSigned
        case .unreadable:      return .unreadable(.notReported)
        }
    }

    /// What the signature on disk says, in three answers rather than one optional.
    enum DiskSigner: Sendable, Hashable {
        case named(String)
        case notSigned
        case unreadable
    }

    static func signerFromDisk(at url: URL) -> DiskSigner {
        var code: SecStaticCode?
        let made = SecStaticCodeCreateWithPath(url as CFURL, [], &code)
        guard made == errSecSuccess, let code else { return .unreadable }

        var informationRef: CFDictionary?
        let read = SecCodeCopySigningInformation(code,
                                                 SecCSFlags(rawValue: kSecCSSigningInformation),
                                                 &informationRef)
        // `errSecCSUnsigned` is a fact — nothing signed this. Any other failure is a shrug, and the
        // two must not be spelled the same way.
        if read == errSecCSUnsigned { return .notSigned }
        guard read == errSecSuccess, let information = informationRef as? [String: Any] else {
            return .unreadable
        }
        guard let certificates = information[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first else {
            // Signed, but ad-hoc: there is no certificate and so no name. An Automator droplet
            // saved on this Mac is exactly this, and "not signed" is what a person means by it.
            return information[kSecCodeInfoIdentifier as String] == nil ? .unreadable : .notSigned
        }
        guard let summary = SecCertificateCopySubjectSummary(leaf) as String?,
              let name = StartupReader.organisation(inCertificateSummary: summary) else {
            return .unreadable
        }
        return .named(name)
    }

    /// Apple's own signature, or somebody's name.
    ///
    /// ⚠️ **"Apple Mac OS Application Signing" is not Apple the developer** — it is the receipt Apple
    /// staples onto a Mac App Store app, and the publisher's name is nowhere in it.
    /// `StartupReader.organisation` already turns it into "From the Mac App Store", and Apps uses
    /// that same wording rather than a second one: two sections describing one certificate two ways
    /// is worse than one slightly formal phrase.
    static func named(_ name: String) -> SignedBy {
        name == "Apple" ? .apple : .developer(name)
    }

    /// Where the app came from.
    ///
    /// ⚠️ **A TestFlight build comes out `.unknown`, and that is the honest answer.** There are six
    /// cases and none of them is TestFlight: it is not the Mac App Store, which updates apps for
    /// you; it is not a Developer ID download; it is certainly not unsigned. macOS itself files
    /// these under `obtained_from: unknown`, the signature line beside it reads "TestFlight Beta
    /// Distribution" in full, and the update row says `.testFlightBuild` outright. Six of the 31
    /// apps here are TestFlight builds, so this is not a corner.
    static func origin(of entry: Entry, homebrew: Set<String> = []) -> AppOrigin {
        if entry.path.hasPrefix("/System/") { return .bundledWithMacOS }
        if homebrew.contains(URL(fileURLWithPath: entry.path).lastPathComponent) { return .homebrew }

        switch entry.obtainedFrom {
        case "mac_app_store":        return .appStore
        case "identified_developer": return .developerID
        case "apple":                return .bundledWithMacOS
        default:
            return entry.signedBy.isEmpty ? .unsigned : .unknown
        }
    }

    /// When it arrived on this Mac.
    ///
    /// ⚠️ **Spotlight's `kMDItemDateAdded` is not this.** It reads 2026-08-25 for every app on this
    /// Mac, including ones installed in 2024, because that is when the index was last rebuilt.
    /// The file system's creation date survives an in-place update — Chrome updates itself and still
    /// reports the March day it was first downloaded — which is the fact a person means.
    static func installedDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }

    /// When it was last opened, where macOS records it — and `nil` is ordinary. See the header.
    static func lastOpened(at path: String) -> Date? {
        guard let item = MDItemCreate(nil, path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    /// The app bundle's own size, or `nil` if the walk was cancelled.
    ///
    /// ⚠️ **The bundle, and nothing else.** Chrome's own folder is 5.8 MB; the data it keeps in
    /// `~/Library/Application Support/Google` is about 5.9 GB, under a name that matches neither the
    /// app nor its identifier. One number covering both would be a guess dressed as a fact, and this
    /// is the field a person would read as "delete this and get that back".
    static func bundleSize(of url: URL,
                           fileManager: FileManager = .default,
                           isCancelled: () -> Bool = { Task.isCancelled }) -> Int64? {
        guard !isCancelled() else { return nil }

        let keys: [URLResourceKey] = [.isRegularFileKey,
                                      .totalFileAllocatedSizeKey,
                                      .fileAllocatedSizeKey]
        // Safari is a symlink into the Cryptex; enumerating the link itself finds one file of no
        // bytes and reports an empty app.
        let root = url.resolvingSymlinksInPath()

        // ⚠️ A bundle that is not there weighs nothing and must not be said to weigh nothing. An
        // enumerator over a missing folder yields no files and sums to zero, which would print
        // "0 bytes" beside an app rather than dropping the figure.
        guard fileManager.fileExists(atPath: root.path) else { return nil }

        guard let walk = fileManager.enumerator(at: root,
                                                includingPropertiesForKeys: keys,
                                                options: [],
                                                errorHandler: { _, _ in true }) else { return nil }

        var total: Int64 = 0
        var seen = 0
        for case let file as URL in walk {
            // Xcode is 200,000 files. Checking every one costs more than the walk.
            seen += 1
            if seen % 512 == 0, isCancelled() { return nil }
            guard let values = try? file.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    // MARK: - Homebrew

    /// The app bundles Homebrew installed, by bundle name.
    ///
    /// A cask moves the app into `/Applications` and keeps only a receipt in the Caskroom, so the
    /// app on disk is indistinguishable from a hand-downloaded one — same signature, same folder.
    /// The receipt is the only evidence, and it is worth reading: an app Homebrew installed is
    /// updated by `brew upgrade` and by nothing else, which is a different answer to the update
    /// question than "from its maker" gives.
    ///
    /// Both layouts are handled: the app sitting inside the version folder, which older casks and
    /// `--appdir` installs produce, and the JSON receipt under `.metadata`, which is what Homebrew 4
    /// writes.
    static func homebrewAppNames(fileManager: FileManager = .default,
                                 caskrooms: [URL] = Folders.caskrooms) -> Set<String> {
        var names: Set<String> = []
        for caskroom in caskrooms {
            guard let tokens = try? fileManager.contentsOfDirectory(at: caskroom,
                                                                    includingPropertiesForKeys: nil,
                                                                    options: [.skipsHiddenFiles])
            else { continue }
            for token in tokens {
                names.formUnion(appNames(inCask: token, fileManager: fileManager))
            }
        }
        return names
    }

    static func appNames(inCask token: URL, fileManager: FileManager = .default) -> Set<String> {
        var names: Set<String> = []

        // The app itself, where the cask still keeps a copy.
        if let versions = try? fileManager.contentsOfDirectory(at: token,
                                                               includingPropertiesForKeys: nil,
                                                               options: [.skipsHiddenFiles]) {
            for version in versions {
                if version.pathExtension == "app" {
                    names.insert(version.lastPathComponent)
                } else if let inside = try? fileManager
                    .contentsOfDirectory(at: version,
                                         includingPropertiesForKeys: nil,
                                         options: [.skipsHiddenFiles]) {
                    for item in inside where item.pathExtension == "app" {
                        names.insert(item.lastPathComponent)
                    }
                }
            }
        }

        // The receipt: .metadata/<version>/<stamp>/Casks/<token>.json
        let metadata = token.appendingPathComponent(".metadata")
        guard let walk = fileManager.enumerator(at: metadata,
                                                includingPropertiesForKeys: nil,
                                                options: [.skipsPackageDescendants],
                                                errorHandler: { _, _ in true }) else { return names }
        for case let file as URL in walk where file.pathExtension == "json" {
            names.formUnion(appNames(inReceipt: file))
        }
        return names
    }

    /// The `artifacts` of one cask receipt: `[{"app": ["Google Chrome.app"]}, …]`.
    static func appNames(inReceipt url: URL) -> Set<String> {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let cask = object as? [String: Any],
              let artifacts = cask["artifacts"] as? [Any] else { return [] }

        var names: Set<String> = []
        for artifact in artifacts {
            guard let entry = artifact as? [String: Any],
                  let apps = entry["app"] as? [Any] else { continue }
            for app in apps {
                guard let path = app as? String, path.hasSuffix(".app") else { continue }
                names.insert(URL(fileURLWithPath: path).lastPathComponent)
            }
        }
        return names
    }

    // MARK: - Turning an inventory into words

    /// The `.installed` row.
    ///
    /// ⚠️ **Three numbers, kept apart, all three said.** The apps a person recognises, the apps that
    /// come with macOS, and the bundles that are not apps at all. Any two of them added together is
    /// a number that overstates what is on the Mac, and the whole section exists to not do that.
    /// - Parameter blockShownAbove: whether the "What is installed" panel is on screen. It says the
    ///   count, the origins and where the other bundles went, one inch above this row — so when it
    ///   is there, the row must not say any of it again. **Rendered together they printed the same
    ///   paragraph twice, an inch apart** (caught in the 2026-08-27 shots, not by a test), which is
    ///   the house rule about never saying the same thing twice on one screen. The row keeps the
    ///   figure, because a row without one is not a row, and it keeps the hand-added note, which is
    ///   the one thing the count alone cannot be checked against.
    static func row(inventory: AppsInventory,
                    bundledWithMacOS: [InstalledApp] = [],
                    blockShownAbove: Bool = false) -> AppsRow {
        AppsRow(topic: .installed,
                headline: headline(inventory, alone: !blockShownAbove),
                measure: measure(inventory.apps.count),
                reason: blockShownAbove ? nil : reason(inventory, bundledWithMacOS: bundledWithMacOS),
                details: details(inventory, bundledWithMacOS: bundledWithMacOS))
    }

    /// - Parameter alone: false when the panel above has already said the count. Then this sentence
    ///   is only the part the panel does not carry.
    static func headline(_ inventory: AppsInventory, alone: Bool = true) -> String {
        let sentence: String
        switch inventory.apps.count {
        case 0:  sentence = alone ? "No apps were found in the folders apps live in."
                                  : "No apps were found in the folders apps live in."
        case 1:  sentence = alone ? "One app is installed." : "Every app you installed yourself."
        default: sentence = alone ? "\(inventory.apps.count) apps are installed."
                                  : "Every app in your Applications and Utilities folders."
        }

        // The hand-added ones are named on the row rather than behind Options. A list that quietly
        // contains a row macOS did not report is a list nobody can check.
        let added = inventory.addedByHand
        guard !added.isEmpty else { return sentence }
        let names = added.map(\.name).formatted(.list(type: .and))
        return added.count == 1
            ? "\(sentence) macOS does not list \(names), so we added it by hand."
            : "\(sentence) macOS does not list \(names), so we added them by hand."
    }

    static func measure(_ count: Int) -> String {
        count == 1 ? "1 app" : "\(count) apps"
    }

    /// ⚠️ **The other two numbers are said here, on the row, and not only behind Options.**
    ///
    /// "31 apps" on its own invites the obvious objection — somebody has seen a bigger number
    /// somewhere, and every cleaner on the market prints one. Saying in the same breath where the
    /// other 392 bundles went is the whole difference between a count and a claim. The exact pairs
    /// are behind Options as well; this is the plain-words version.
    static func reason(_ inventory: AppsInventory,
                       bundledWithMacOS: [InstalledApp] = []) -> String {
        let counted = "Counted the way a person would count them: what is in your Applications "
                    + "folders."

        var rest: [String] = []
        if !bundledWithMacOS.isEmpty {
            rest.append("\(bundledWithMacOS.count) more come with macOS")
        }
        if let elsewhere = inventory.otherBundles, elsewhere > 0 {
            rest.append("another \(elsewhere) bundles here are components, helpers and build "
                      + "products rather than apps")
        }
        guard !rest.isEmpty else { return counted }
        return "\(counted) \(rest.joined(separator: ", and "))."
    }

    /// Everything exact, behind Options.
    ///
    /// `AppsInventory.detailPairs` already carries the count, the breakdown by origin, the Intel-only
    /// figure and the other-bundles line. The two added here are the ones the inventory has no field
    /// for, and neither label repeats one of its — a `DetailPair`'s identity is its label.
    static func details(_ inventory: AppsInventory,
                        bundledWithMacOS: [InstalledApp] = []) -> [DetailPair] {
        var rows = inventory.detailPairs

        if !bundledWithMacOS.isEmpty {
            rows.append(DetailPair("Apps that come with macOS",
                                   "\(bundledWithMacOS.count) — a macOS update is what updates them"))
        }
        let added = inventory.addedByHand
        if !added.isEmpty {
            rows.append(DetailPair("Added by hand",
                                   added.map(\.name).formatted(.list(type: .and))
                                       + " — macOS does not list this app, so we read it directly"))
        }
        return rows
    }

    // MARK: - Reading one bundle

    /// An app's `Info.plist`, or `nil` where there is not one to read.
    ///
    /// ⚠️ **Three places, because a Mac has three kinds of app bundle.** An ordinary Mac app keeps it
    /// in `Contents`. An iPhone or iPad app running on Apple silicon is wrapped — the real bundle is
    /// under `WrappedBundle`, and there is no `Contents` folder at all, so a reader that looks only
    /// there gives the app no identifier and no version. `Wildbound.app` on this Mac is exactly
    /// that. The bare `Info.plist` at the root is the old flat layout, and costs one line to accept.
    static func infoPlist(at bundle: URL) -> [String: Any]? {
        for inside in ["Contents/Info.plist", "WrappedBundle/Info.plist", "Info.plist"] {
            if let plist = StartupReader.plist(at: bundle.appendingPathComponent(inside)) {
                return plist
            }
        }
        return nil
    }

    /// A property-list value that is a string with something in it.
    static func string(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - What an app knows about itself

extension InstalledApp {

    /// The same app with its size attached, so weighing can be a separate phase from reading.
    func withBytes(_ bytes: Int64?) -> InstalledApp {
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
                     update: update,
                     addedByHand: addedByHand)
    }
}

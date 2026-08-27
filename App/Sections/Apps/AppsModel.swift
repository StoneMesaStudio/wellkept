import Foundation
import Observation
import WellkeptCore

//  AppsModel.swift
//  Wellkept — App/Sections/Apps
//
//  **The one place the five Apps readers are actually called.**
//
//  `InventoryReader`, `MacOSUpdateState`, `UpdateReader`, `CrashReader` and `LeftoverReader` know
//  nothing about each other and nothing about a view. This is the seam: it runs them in the
//  section's own fixed row order, applies the update standings back onto the inventory, assembles
//  one `AppsReport`, and hands it to the screen.
//
//  Same shape as `HardwareModel` and `SecurityModel`, deliberately — three sections that are the
//  same screen with different contents.
//
//  ## ⚠️ Apps does NOT run on launch, and this file is where that promise is kept
//
//  The inventory call alone is **7–8 seconds** — measured on an M3 on 2026-08-27, on a Mac with 422
//  bundles and a warm cache — and the whole sweep is about thirteen. There is no `checkOnLaunch`
//  here and there must not be one.
//
//  ## ⚠️ The order the readers run in is not arbitrary
//
//  The inventory has to be first, because three of the other four take its list of bundle
//  identifiers as an argument: the crash reader uses it to set aside crashes from software this
//  section does not list, and the leftover reader uses it as the first half of "is this app gone".
//  Then the standings are applied **back onto the inventory** and the installed row is rebuilt from
//  it — otherwise the row's coverage figure would describe a list where nothing had been checked
//  yet, which is a number that is wrong in the flattering direction.
//
//  ## ⚠️ Consent is passed in, never read here
//
//  Whether Wellkept may ask anybody anything lives in `UpdateConsentStore`, above `AppearanceHost`,
//  and reaches `check(consent:)` as an argument. This file has no opinion about it and no way to
//  reach the key — which is what stops a check ever running with a different answer from the one
//  the person is looking at on the screen.

// MARK: - What one run produced

/// The report, plus the four things an `AppsRow` has nowhere to carry.
///
/// `AppsRow` holds only `DetailPair`s — right for Options, wrong for a screen whose whole content
/// is a list of apps, a list of crashes and a list of leftovers. So they travel beside the report
/// rather than being flattened into it.
struct AppsAnswer: Sendable, Hashable {

    let report: AppsReport

    /// The apps that actually crashed, most recent first. **Empty is the ordinary answer** — 108
    /// crash files on the measured Mac reduced to zero.
    let crashes: [CrashedApp]

    /// What removed apps left behind. **Empty is a fine answer**, and per item only — there is no
    /// section-wide total anywhere, by construction.
    let leftovers: [Leftover]

    /// macOS's own version and update settings, for the row and for Options.
    let macOS: MacOSUpdateState

    /// What the update reader did, including the answer that was in force and exactly which app
    /// names left this Mac.
    let update: UpdateReader.Answer

    /// The apps that come with macOS. **Counted separately and never folded into the list** — 65 of
    /// them here, and adding them in would double the number on the section's first line.
    let bundledWithMacOS: [InstalledApp]

    /// How far back the crash folders reached, in days. **`nil` is a real answer.**
    let crashWindowDays: Int?

    init(report: AppsReport,
         crashes: [CrashedApp] = [],
         leftovers: [Leftover] = [],
         macOS: MacOSUpdateState,
         update: UpdateReader.Answer = .notChecked,
         bundledWithMacOS: [InstalledApp] = [],
         crashWindowDays: Int? = nil) {
        self.report = report
        self.crashes = crashes
        self.leftovers = leftovers
        self.macOS = macOS
        self.update = update
        self.bundledWithMacOS = bundledWithMacOS
        self.crashWindowDays = crashWindowDays
    }

    /// The apps a person recognises, in the order the inventory gave them.
    var apps: [InstalledApp] { report.inventory.apps }

    /// How many apps would be named to Apple's App Store if update checking were switched on.
    ///
    /// Used by the consent question so it can say a number a person can weigh rather than "a small
    /// number of makers". It is worked out from the same rule `UpdateReader` uses — App Store apps
    /// that are not TestFlight builds and do not come with macOS — so the two cannot disagree.
    var appsThatWouldBeNamed: Int {
        apps.filter { app in
            app.origin == .appStore
            && !UpdateReader.isTestFlightBuild(app)
            && !app.addedByHand
        }.count
    }
}

// MARK: - The model

@MainActor
@Observable
final class AppsModel {

    // MARK: What the screen draws

    /// The last complete answer. `nil` until the first check finishes — **the ordinary state**, not
    /// an edge case: Apps never runs by itself, so this is `nil` on every launch until somebody
    /// presses the button.
    private(set) var answer: AppsAnswer?

    /// A check is running now.
    private(set) var isChecking = false

    /// What it is reading at this moment. `nil` when nothing is running.
    private(set) var stage: Stage?

    /// How far through the inventory it is. **The only phase with progress inside it**, and the one
    /// that takes eight seconds; the other four are each under a second.
    private(set) var inventoryProgress: InventoryReader.Progress?

    /// The rows that have landed so far in the run happening now. Emptied when the run finishes and
    /// `answer` takes over.
    private(set) var arrived: [AppsRow] = []

    /// What is typed into the search field above the app list.
    ///
    /// ⚠️ **Here rather than in a `@State` inside the list.** `AppearanceHost` re-identifies the
    /// whole content tree on a text-size change, which throws away every `@State` beneath it — so a
    /// search term held in the view would vanish the first time somebody pressed ⌘+ to read it.
    var searchText: String = ""

    // MARK: - The stages

    /// What the app is doing right now, in words a person can read while they wait.
    ///
    /// One case per reader, in the order they run, which is the section's own row order.
    enum Stage: String, CaseIterable, Sendable, Hashable {
        case inventory
        case macOS
        case updates
        case crashes
        case leftovers

        /// The row this stage produces.
        var topic: AppsTopic {
            switch self {
            case .inventory:  .installed
            case .macOS:      .macOS
            case .updates:    .updates
            case .crashes:    .stoppedWorking
            case .leftovers:  .removedLeftovers
            }
        }

        var sentence: String {
            switch self {
            case .inventory:
                // Said out loud because it is eight seconds of the thirteen, and a person watching
                // a still spinner has no way to tell a slow step from a stopped app.
                "Asking macOS what is installed — this is the slow part…"
            case .macOS:
                "Reading which version of macOS this Mac is running…"
            case .updates:
                "Finding out which apps have a newer version…"
            case .crashes:
                "Reading macOS's records of apps that stopped working…"
            case .leftovers:
                "Looking for files left behind by apps that are gone…"
            }
        }

        /// How far through the run this is, one-based, for the count beside the spinner.
        var step: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

        static var count: Int { allCases.count }
    }

    // MARK: - Running it

    /// **The whole Apps sweep.** About thirteen seconds on an M3, eight of them the inventory.
    ///
    /// Safe to call again; a second call while one is running is ignored rather than queued.
    ///
    /// Every blocking reader runs on a detached task — short-lived tools, property lists, a walk of
    /// `~/Library` — and none of them may happen where the window is waiting to draw. `UpdateReader`
    /// is already `async` and non-isolated, so it schedules itself off the main actor.
    ///
    /// - Parameter consent: whether this run may ask anybody whether an app is current. Passed in;
    ///   see the file header.
    func check(consent: UpdateConsent.Answer) async {
        guard !isChecking else { return }
        isChecking = true
        arrived = []
        inventoryProgress = nil
        let started = Date()
        defer {
            isChecking = false
            stage = nil
            inventoryProgress = nil
            arrived = []
        }

        // 1 — what is installed. Eight seconds, and everything below depends on it.
        stage = .inventory
        let report: @Sendable (InventoryReader.Progress) -> Void = { [weak self] progress in
            Task { @MainActor in self?.inventoryProgress = progress }
        }
        let gathered = await Task.detached(priority: .userInitiated) {
            InventoryReader.read(progress: report)
        }.value
        inventoryProgress = nil

        // ⚠️ `nil` means the read was cancelled, and it hands back nothing rather than a shorter
        // list. A partial inventory is not a smaller answer, it is a wrong one — see
        // `InventoryReader.read`. There is nothing honest to publish, so the run simply ends.
        guard let gathered else { return }
        arrived.append(gathered.row)

        // 2 — macOS itself. Off this Mac's own disk; nothing is asked of Apple.
        stage = .macOS
        let macOS = await Task.detached(priority: .userInitiated) {
            MacOSUpdateState.read()
        }.value
        arrived.append(MacOSRow.row(macOS))

        // 3 — the one step that can reach off this Mac, and only with consent.
        stage = .updates
        let update = await UpdateReader.read(apps: gathered.inventory.apps, consent: consent)
        let inventory = gathered.inventory.applying(update.standings)
        arrived.append(UpdatesRow.row(inventory: inventory, update: update))

        // Everything this section lists, macOS's own apps included. The crash reader uses it to set
        // aside crashes of software we do not list; the leftover reader uses it as the first half of
        // "is this app gone".
        let known = Set(inventory.apps.map(\.bundleID) + gathered.bundledWithMacOS.map(\.bundleID))

        // 4 — apps that stopped working.
        stage = .crashes
        let crash = await Task.detached(priority: .userInitiated) {
            CrashReader.read(appsOnThisMac: known)
        }.value
        arrived.append(crash.row)

        // 5 — what removed apps left behind. ⚠️ The one row that needs Full Disk Access, and
        // `LeftoverReader` reads the grant itself before touching anything: it never finds out by
        // trying, because trying is what puts the privacy dialog on somebody's screen.
        stage = .leftovers
        let left = await Task.detached(priority: .userInitiated) {
            LeftoverReader.read(appsOnThisMac: known)
        }.value
        arrived.append(left.row)

        // ⚠️ The installed row is rebuilt from the inventory that now carries the standings.
        // Without this the coverage on that row would describe the list as it was before anything
        // was checked — a figure that is wrong, and wrong in the flattering direction.
        let rows = arrived.map { row -> AppsRow in
            guard row.topic == .installed, row.unreadable == nil else { return row }
            return InventoryReader.row(inventory: inventory,
                                       bundledWithMacOS: gathered.bundledWithMacOS,
                                       blockShownAbove: true)
        }

        answer = AppsAnswer(report: AppsReport(inventory: inventory, rows: rows, ranAt: started),
                            crashes: crash.crashes,
                            leftovers: left.leftovers,
                            macOS: macOS,
                            update: update,
                            bundledWithMacOS: gathered.bundledWithMacOS,
                            crashWindowDays: crash.windowDays)
    }
}

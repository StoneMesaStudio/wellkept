import Foundation
import Observation
import WellkeptCore

//  SecurityModel.swift
//  Wellkept — App/Sections/Security
//
//  **The one place the six Security readers are actually called.**
//
//  The readers know nothing about each other and nothing about a view. This is the seam: it runs
//  them in the section's own fixed order, carries the measured window out of the log reader,
//  assembles one `SecurityReport`, and hands it to the screen.
//
//  It is deliberately the same shape as `HardwareModel` — a detached sweep, one report, one row up
//  to Overview — because the two sections are the same screen with different contents.
//
//  ## ⚠️ Security does NOT run on launch, and this file is where that promise is kept
//
//  The log read alone is about six seconds — measured on an M3 on 2026-08-27, and it is the
//  slowest read in the whole app. A section that took six seconds off every launch would make
//  Wellkept feel broken on the one screen where feeling broken matters most. So there is no
//  `checkOnLaunch` here at all: Security runs **on a press**, and nothing else starts it.
//
//  ## ⚠️ The rows arrive one at a time, on purpose
//
//  Seven seconds of a spinner over a blank panel is indistinguishable from a hang. So each reader
//  is awaited in turn and its row is published the moment it lands: the five fast rows fill in
//  inside a second, and the slow one sits there saying what it is doing while the log is read.
//  That is a real in-flight state rather than a frozen screen, and it costs nothing — the readers
//  were always independent.
//
//  The finished `SecurityReport` is built only when the last row is in. A half-assembled report
//  would carry a status chip and an audit line computed from five rows out of six, which is a
//  verdict about a check that had not finished.

// MARK: - What one run produced

/// The report, plus the two things a `SecurityRow` has nowhere to carry.
///
/// `SecurityRow` holds only `DetailPair`s — right for Options, wrong for a screen whose whole
/// content is a list of apps. So the grants travel beside the report rather than being flattened
/// into it.
struct SecurityAnswer: Sendable, Hashable {

    let report: SecurityReport

    /// Every app-and-permission pair. **Empty whenever the watch row is unreadable** — there is no
    /// path that draws a short list beside a refusal.
    let grants: [Grant]

    /// Identifiers we could neither place nor rule out. Counted, stated, never accused.
    let unplaceable: [String]

    /// Parts of macOS itself that use location and are not apps anybody installed.
    let systemServicesUsingLocation: Int

    init(report: SecurityReport,
         grants: [Grant] = [],
         unplaceable: [String] = [],
         systemServicesUsingLocation: Int = 0) {
        self.report = report
        self.grants = grants
        self.unplaceable = unplaceable
        self.systemServicesUsingLocation = systemServicesUsingLocation
    }

    /// The grants for one permission, in a stable order.
    func grants(for permission: WellkeptCore.Permission) -> [Grant] {
        grants.filter { $0.permission == permission }
    }

    /// The permissions anything actually holds, in the order `Permission` declares them — the
    /// watching three first. Never all twelve: a list of nine headings with nothing under them is
    /// nine chances to think something is missing.
    var permissionsHeld: [WellkeptCore.Permission] {
        WellkeptCore.Permission.allCases.filter { permission in
            grants.contains { $0.permission == permission }
        }
    }
}

// MARK: - The model

@MainActor
@Observable
final class SecurityModel {

    // MARK: What the screen draws

    /// The last complete answer. `nil` until the first check finishes — which is a real state, and
    /// the ordinary one: Security never runs by itself, so this is `nil` on every launch until
    /// somebody presses the button.
    private(set) var answer: SecurityAnswer?

    /// A check is running now.
    private(set) var isChecking = false

    /// What it is reading at this moment. `nil` when nothing is running.
    private(set) var stage: Stage?

    /// The rows that have landed so far in the run that is happening now. Emptied when the run
    /// finishes and `answer` takes over.
    private(set) var arrived: [SecurityRow] = []

    /// The protections block, published as soon as the first reader hands it over, so the top of
    /// the screen fills in while the rest is still being read.
    private(set) var arrivedBlock: ProtectionsBlock?

    // MARK: - The stages

    /// What the app is doing right now, in words a person can read while they wait.
    ///
    /// One case per reader, in the order they run, which is the section's own row order. The
    /// sentence is written for somebody watching a spinner: it says what is being read, and where
    /// a step is genuinely slow it says so rather than letting them wonder.
    enum Stage: String, CaseIterable, Sendable, Hashable {
        case protections
        case whoCanWatch
        case startsOnItsOwn
        case browserExtensions
        case reachableFrom
        case macOSFindings

        /// The row this stage produces.
        var topic: SecurityTopic {
            switch self {
            case .protections:       .protections
            case .whoCanWatch:       .whoCanWatch
            case .startsOnItsOwn:    .startsOnItsOwn
            case .browserExtensions: .browserExtensions
            case .reachableFrom:     .reachableFrom
            case .macOSFindings:     .macOSFindings
            }
        }

        var sentence: String {
            switch self {
            case .protections:
                "Reading this Mac's protections…"
            case .whoCanWatch:
                "Reading which apps can use the camera, the microphone and the screen…"
            case .startsOnItsOwn:
                "Reading what starts on its own…"
            case .browserExtensions:
                "Reading the extensions in your browsers…"
            case .reachableFrom:
                "Reading what this Mac is reachable from…"
            case .macOSFindings:
                // Said out loud because it is the one that makes a person wonder whether the app
                // has stopped. It has not; macOS's log is simply slow to search.
                "Reading macOS's own log of what it has found — this one takes a few seconds…"
            }
        }

        /// How far through the run this is, one-based, for the count beside the spinner.
        var step: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

        static var count: Int { allCases.count }
    }

    // MARK: - Running it

    /// **The whole Security sweep.** About seven seconds on an M3, nearly all of it the log read.
    ///
    /// Safe to call again; a second call while one is running is ignored rather than queued.
    ///
    /// Every reader runs on a detached task. They are all blocking — short-lived tools, property
    /// lists, a SQLite file and an `OSLogStore` query — and none of them may happen where the
    /// window is waiting to draw.
    func check() async {
        guard !isChecking else { return }
        isChecking = true
        arrived = []
        arrivedBlock = nil
        let started = Date()
        defer {
            isChecking = false
            stage = nil
            arrived = []
            arrivedBlock = nil
        }

        // 1 — the switches, and the block at the top of the screen.
        stage = .protections
        let protections = await Task.detached(priority: .userInitiated) {
            ProtectionReader.read()
        }.value
        arrivedBlock = protections.block
        arrived.append(protections.row)

        // 2 — camera, microphone, screen and control. Collapses to one sentence without Full Disk
        // Access; `GrantReader` decides that, not this file.
        stage = .whoCanWatch
        let watch = await Task.detached(priority: .userInitiated) {
            GrantReader.read()
        }.value
        arrived.append(watch.row)

        // 3 — what starts on its own.
        stage = .startsOnItsOwn
        let startup = await Task.detached(priority: .userInitiated) {
            StartupReader.read()
        }.value
        arrived.append(startup)

        // 4 — browser extensions.
        stage = .browserExtensions
        let extensions = await Task.detached(priority: .userInitiated) {
            BrowserExtensionReader.read()
        }.value
        arrived.append(extensions)

        // 5 — what can reach this Mac.
        stage = .reachableFrom
        let reachable = await Task.detached(priority: .userInitiated) {
            ReachableReader.read()
        }.value
        arrived.append(reachable)

        // 6 — the slow one.
        stage = .macOSFindings
        let found = await Task.detached(priority: .userInitiated) {
            MacOSFindingsReader.read()
        }.value
        arrived.append(found.row)

        // ⚠️ `found.measuredDays` has to travel. It is the one number `SecurityReport` cannot work
        // out for itself, and every sentence in this section that says how far back "nothing"
        // reaches depends on it. Drop it and the honest-shrug wording appears on every Mac.
        answer = SecurityAnswer(
            report: SecurityReport(block: protections.block,
                                   rows: arrived,
                                   ranAt: started,
                                   measuredDays: found.measuredDays),
            grants: watch.grants,
            unplaceable: watch.unplaceable,
            systemServicesUsingLocation: watch.systemServicesUsingLocation)
    }
}

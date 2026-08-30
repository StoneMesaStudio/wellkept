import Foundation

//  MacModels.swift
//  WellkeptCore
//
//  **The shipped table of what each Mac is, when it came out, and how long Apple will keep
//  patching what it can run.**
//
//  ## Why a table, and why it ships inside the app
//
//  Nothing on a Mac knows when the model was released. `sysctl hw.model` gives `Mac15,13` and
//  stops there; `system_profiler` reports the marketing name only on recent macOS and only
//  sometimes; and no interface anywhere reports which macOS release is the last one a machine
//  will get. Apple publishes all of it, on support pages, in prose. So it is typed out here,
//  ships with the app, and is updated with the app.
//
//  ## ⚠️ Who updates this, and when
//
//  **Whoever ships the next release of Wellkept, in September, every year.** Apple announces the
//  new macOS at WWDC in June and ships it in September, and that announcement is the one event
//  that changes this file:
//
//  1. Add the models released since the last update.
//  2. Set `newestMacOS` on every model the new release drops. That is the line that turns
//     "current" into "this is the last macOS this Mac can run" — the sentence a person actually
//     needs.
//  3. Bump `newestKnownMacOS` and add the new release to `securityUpdatesThrough(forMacOS:)`.
//  4. Bump `lastUpdated`.
//
//  Skipping it is not a crash and not a wrong answer: an unknown identifier returns `nil`, the
//  view falls back to showing the raw identifier, and `standing` returns `.unknown`, whose
//  sentence says plainly that Wellkept does not know this model. **A missing entry is honest. A
//  wrong entry is not** — so when in doubt about an identifier, leave it out.
//
//  ## The two states that are deliberately separate
//
//  The instruction, 2026-08-27: *"Not about fear, it is about security. Why not be honest? We
//  are not selling them a new machine, we are protecting them."* So the table distinguishes:
//
//  - **"This is among the oldest models this macOS supports"** — a fact about a working Mac,
//    stated once, never a warning. Nothing is wrong with it.
//  - **"This no longer receives security updates"** — the only one of these that is a problem,
//    because it is the only one where something a person cares about has actually stopped.
//
//  Everything in between — running an older macOS that is still patched — is information. A Mac
//  that will keep getting fixes for three more years does not need a badge on it for three years.

// MARK: - One model

public enum MacArchitecture: String, Sendable, Codable, Hashable, CaseIterable {
    case appleSilicon
    case intel

    public var label: String {
        switch self {
        case .appleSilicon: "Apple silicon"
        case .intel:        "Intel"
        }
    }
}

/// One line of the shipped table.
public struct MacModel: Sendable, Hashable, Codable, Identifiable {

    /// What `sysctl hw.model` returns: "Mac15,13", "MacBookPro16,1".
    public let identifier: String

    /// Apple's own words for it: "MacBook Air (15-inch, M3, 2024)". Copied from Apple's support
    /// pages rather than composed, because a person matching their Mac against a web page needs
    /// the string to be the same string.
    public let marketingName: String

    /// The calendar year Apple first shipped it.
    public let releaseYear: Int

    public let architecture: MacArchitecture

    /// "M1", "M2", "M3", "M4", or "Intel". A grouping, not the chip in the machine — a reader
    /// gets the actual chip name from the machine itself, which is more specific than this.
    public let chipFamily: String

    /// The newest macOS major version this model can run.
    ///
    /// **`nil` means no end has been announced** — the model runs the current release and Apple
    /// has not dropped it. That is not the same as "supported for ever", and the sentences below
    /// never claim it is.
    public let newestMacOS: Int?

    public var id: String { identifier }

    public init(_ identifier: String,
                _ marketingName: String,
                _ releaseYear: Int,
                _ architecture: MacArchitecture,
                _ chipFamily: String,
                newestMacOS: Int? = nil) {
        self.identifier = identifier
        self.marketingName = marketingName
        self.releaseYear = releaseYear
        self.architecture = architecture
        self.chipFamily = chipFamily
        self.newestMacOS = newestMacOS
    }
}

// MARK: - Where a Mac sits in Apple's support window

/// How long this Mac will keep getting fixed, in the five states that are actually different.
///
/// Every year in here is an **estimate**, and the sentences say so with "about". Apple does not
/// publish an end date for a macOS release; the pattern is roughly three years of security
/// updates from a release's debut, and the estimate is deliberately generous. Telling somebody
/// their Mac is unprotected when it is still being patched is the worse of the two errors — it is
/// the scareware move this whole app exists to not be.
public enum SupportStanding: Sendable, Hashable, Codable {

    /// Runs the newest macOS, and Apple has not signalled an end.
    case current

    /// Runs the newest macOS, but is among the oldest models this release supports. Nothing is
    /// wrong; it is simply the first in line when a release drops models.
    case oldestSupported(macOS: Int)

    /// This macOS is the last release this Mac will get. Security updates continue for a while.
    case lastRelease(macOS: Int, securityUpdatesThrough: Int?)

    /// A newer macOS exists that this Mac cannot run, and the one it runs is still patched.
    case behind(newestItCanRun: Int, securityUpdatesThrough: Int?)

    /// **The only state that is a problem.** The newest macOS this Mac can run has stopped
    /// getting security fixes, so a hole found in it now stays open.
    case noLongerUpdated(newestItCanRun: Int, since: Int)

    /// The model is not in the shipped table — almost always a Mac newer than this build of
    /// Wellkept. Saying so is the honest answer; guessing is not.
    case unknown

    /// The plain sentence for the "what this Mac is" block. Security, never sales.
    public var sentence: String {
        switch self {
        case .current:
            "This Mac runs the newest macOS, and Apple has not said when that will stop."
        case .oldestSupported(let macOS):
            "This is among the oldest Macs macOS \(macOS) supports. It still gets every update."
        case .lastRelease(let macOS, let through):
            through.map {
                "macOS \(macOS) is the last version this Mac can run. Apple is expected to keep fixing security holes in it until about \($0)."
            } ?? "macOS \(macOS) is the last version this Mac can run. It still gets security fixes."
        case .behind(let newest, let through):
            through.map {
                "This Mac can run macOS \(newest), not the newest one. Security fixes for macOS \(newest) are expected until about \($0)."
            } ?? "This Mac can run macOS \(newest), not the newest one. It still gets security fixes."
        case .noLongerUpdated(let newest, let since):
            "The newest macOS this Mac can run is \(newest), and security fixes for it are expected to have stopped around \(since). Holes found in it now stay open."
        case .unknown:
            "Wellkept does not recognise this model, so it cannot say how long Apple will keep updating it."
        }
    }

    /// A few words, for a row rather than a paragraph.
    public var label: String {
        switch self {
        case .current:            "Up to date"
        case .oldestSupported:    "Supported, and among the oldest"
        case .lastRelease:        "Last macOS for this Mac"
        case .behind:             "Still getting security fixes"
        case .noLongerUpdated:    "No longer getting security fixes"
        case .unknown:            "Not known"
        }
    }

    /// ⚠️ **Only `.noLongerUpdated` is a problem.** Everything else here describes a Mac that is
    /// working and protected, and a badge that sits on a working Mac for three years is a badge
    /// people learn to scroll past.
    public var severity: Severity {
        switch self {
        case .noLongerUpdated: .problem
        default:               .information
        }
    }
}

// MARK: - The table

public enum MacModels {

    /// When this table was last checked against Apple's support pages. **Bump it when you edit
    /// the table**, so a future reader can tell stale data from data that simply has not changed.
    public static let lastUpdated = "2026-08-27"

    /// The newest macOS major version this build of Wellkept has heard of.
    ///
    /// macOS 26 Tahoe. Also, as it happens, the last macOS release that supports Intel — which is
    /// why the four Intel models below carrying `newestMacOS: 26` matter: they are the audience
    /// that still exists, for about three more years.
    public static let newestKnownMacOS = 26

    /// Best estimate of the last calendar year Apple ships security updates for a macOS release.
    ///
    /// Apple announces none of this. The pattern is about three years from a release's debut. The
    /// figure for 26 is longer on purpose: it is the terminal Intel release, the machines running
    /// it have nowhere to go, and overstating the tail is the safe direction to be wrong in.
    public static func securityUpdatesThrough(forMacOS major: Int) -> Int? {
        switch major {
        case 14: 2026
        case 15: 2027
        case 26: 2029
        default: nil
        }
    }

    // MARK: Apple silicon

    /// M1 through M4. `newestMacOS` is `nil` throughout: Apple has dropped none of them.
    ///
    /// Macs newer than M4 are deliberately absent rather than guessed. An unknown identifier
    /// degrades to `.unknown`, which says so; a wrong marketing name is a lie on a screen a person
    /// might paste into an email to a repair shop.
    private static let appleSiliconModels: [MacModel] = [
        // ── M1 (2020–2022) ──────────────────────────────────────────────────────────────
        MacModel("MacBookAir10,1", "MacBook Air (M1, 2020)", 2020, .appleSilicon, "M1"),
        MacModel("MacBookPro17,1", "MacBook Pro (13-inch, M1, 2020)", 2020, .appleSilicon, "M1"),
        MacModel("Macmini9,1", "Mac mini (M1, 2020)", 2020, .appleSilicon, "M1"),
        MacModel("iMac21,1", "iMac (24-inch, M1, 2021)", 2021, .appleSilicon, "M1"),
        MacModel("iMac21,2", "iMac (24-inch, M1, 2021)", 2021, .appleSilicon, "M1"),
        MacModel("MacBookPro18,1", "MacBook Pro (16-inch, 2021)", 2021, .appleSilicon, "M1"),
        MacModel("MacBookPro18,2", "MacBook Pro (16-inch, 2021)", 2021, .appleSilicon, "M1"),
        MacModel("MacBookPro18,3", "MacBook Pro (14-inch, 2021)", 2021, .appleSilicon, "M1"),
        MacModel("MacBookPro18,4", "MacBook Pro (14-inch, 2021)", 2021, .appleSilicon, "M1"),
        MacModel("Mac13,1", "Mac Studio (2022)", 2022, .appleSilicon, "M1"),
        MacModel("Mac13,2", "Mac Studio (2022)", 2022, .appleSilicon, "M1"),

        // ── M2 (2022–2023) ──────────────────────────────────────────────────────────────
        MacModel("Mac14,2", "MacBook Air (13-inch, M2, 2022)", 2022, .appleSilicon, "M2"),
        MacModel("Mac14,7", "MacBook Pro (13-inch, M2, 2022)", 2022, .appleSilicon, "M2"),
        MacModel("Mac14,3", "Mac mini (2023)", 2023, .appleSilicon, "M2"),
        MacModel("Mac14,12", "Mac mini (2023)", 2023, .appleSilicon, "M2"),
        MacModel("Mac14,5", "MacBook Pro (14-inch, 2023)", 2023, .appleSilicon, "M2"),
        MacModel("Mac14,9", "MacBook Pro (14-inch, 2023)", 2023, .appleSilicon, "M2"),
        MacModel("Mac14,6", "MacBook Pro (16-inch, 2023)", 2023, .appleSilicon, "M2"),
        MacModel("Mac14,10", "MacBook Pro (16-inch, 2023)", 2023, .appleSilicon, "M2"),
        MacModel("Mac14,15", "MacBook Air (15-inch, M2, 2023)", 2023, .appleSilicon, "M2"),
        MacModel("Mac14,13", "Mac Studio (2023)", 2023, .appleSilicon, "M2"),
        MacModel("Mac14,14", "Mac Studio (2023)", 2023, .appleSilicon, "M2"),
        MacModel("Mac14,8", "Mac Pro (2023)", 2023, .appleSilicon, "M2"),

        // ── M3 (2023–2025) ──────────────────────────────────────────────────────────────
        MacModel("Mac15,4", "iMac (24-inch, 2023)", 2023, .appleSilicon, "M3"),
        MacModel("Mac15,5", "iMac (24-inch, 2023)", 2023, .appleSilicon, "M3"),
        MacModel("Mac15,3", "MacBook Pro (14-inch, Nov 2023)", 2023, .appleSilicon, "M3"),
        MacModel("Mac15,6", "MacBook Pro (14-inch, Nov 2023)", 2023, .appleSilicon, "M3"),
        MacModel("Mac15,8", "MacBook Pro (14-inch, Nov 2023)", 2023, .appleSilicon, "M3"),
        MacModel("Mac15,10", "MacBook Pro (14-inch, Nov 2023)", 2023, .appleSilicon, "M3"),
        MacModel("Mac15,7", "MacBook Pro (16-inch, Nov 2023)", 2023, .appleSilicon, "M3"),
        MacModel("Mac15,9", "MacBook Pro (16-inch, Nov 2023)", 2023, .appleSilicon, "M3"),
        MacModel("Mac15,11", "MacBook Pro (16-inch, Nov 2023)", 2023, .appleSilicon, "M3"),
        MacModel("Mac15,12", "MacBook Air (13-inch, M3, 2024)", 2024, .appleSilicon, "M3"),
        MacModel("Mac15,13", "MacBook Air (15-inch, M3, 2024)", 2024, .appleSilicon, "M3"),
        MacModel("Mac15,14", "Mac Studio (2025)", 2025, .appleSilicon, "M3"),

        // ── M4 (2024–2025) ──────────────────────────────────────────────────────────────
        MacModel("Mac16,2", "iMac (24-inch, 2024)", 2024, .appleSilicon, "M4"),
        MacModel("Mac16,3", "iMac (24-inch, 2024)", 2024, .appleSilicon, "M4"),
        MacModel("Mac16,1", "MacBook Pro (14-inch, Nov 2024)", 2024, .appleSilicon, "M4"),
        MacModel("Mac16,6", "MacBook Pro (14-inch, Nov 2024)", 2024, .appleSilicon, "M4"),
        MacModel("Mac16,8", "MacBook Pro (14-inch, Nov 2024)", 2024, .appleSilicon, "M4"),
        MacModel("Mac16,5", "MacBook Pro (16-inch, Nov 2024)", 2024, .appleSilicon, "M4"),
        MacModel("Mac16,7", "MacBook Pro (16-inch, Nov 2024)", 2024, .appleSilicon, "M4"),
        MacModel("Mac16,10", "Mac mini (2024)", 2024, .appleSilicon, "M4"),
        MacModel("Mac16,11", "Mac mini (2024)", 2024, .appleSilicon, "M4"),
        MacModel("Mac16,12", "MacBook Air (13-inch, M4, 2025)", 2025, .appleSilicon, "M4"),
        MacModel("Mac16,13", "MacBook Air (15-inch, M4, 2025)", 2025, .appleSilicon, "M4"),
        MacModel("Mac16,9", "Mac Studio (2025)", 2025, .appleSilicon, "M4"),
    ]

    // MARK: Intel

    /// **Every Intel Mac that can run macOS 14, which is every Intel Mac Wellkept will ever see.**
    ///
    /// Four of them run macOS 26 Tahoe, the last release that supports Intel at all. The rest
    /// stopped at Sonoma or Sequoia, and this is the half of the table where `newestMacOS` earns
    /// its keep: it is the difference between a Mac that is fine and a Mac whose security fixes
    /// have run out.
    ///
    /// Intel is also where Hardware gets *more*, not less: real NVMe S.M.A.R.T. counters are
    /// readable here and are not readable on any Apple silicon Mac.
    private static let intelModels: [MacModel] = [
        MacModel("iMacPro1,1", "iMac Pro (2017)", 2017, .intel, "Intel", newestMacOS: 15),

        MacModel("iMac19,1", "iMac (Retina 5K, 27-inch, 2019)", 2019, .intel, "Intel", newestMacOS: 15),
        MacModel("iMac19,2", "iMac (Retina 4K, 21.5-inch, 2019)", 2019, .intel, "Intel", newestMacOS: 15),
        MacModel("iMac20,1", "iMac (Retina 5K, 27-inch, 2020)", 2020, .intel, "Intel", newestMacOS: 26),
        MacModel("iMac20,2", "iMac (Retina 5K, 27-inch, 2020)", 2020, .intel, "Intel", newestMacOS: 26),

        MacModel("MacBookAir8,1", "MacBook Air (Retina, 13-inch, 2018)", 2018, .intel, "Intel", newestMacOS: 14),
        MacModel("MacBookAir8,2", "MacBook Air (Retina, 13-inch, 2019)", 2019, .intel, "Intel", newestMacOS: 14),
        MacModel("MacBookAir9,1", "MacBook Air (Retina, 13-inch, 2020)", 2020, .intel, "Intel", newestMacOS: 15),

        MacModel("MacBookPro15,1", "MacBook Pro (15-inch, 2018)", 2018, .intel, "Intel", newestMacOS: 15),
        MacModel("MacBookPro15,2", "MacBook Pro (13-inch, 2018, Four Thunderbolt 3 ports)", 2018, .intel, "Intel", newestMacOS: 15),
        MacModel("MacBookPro15,3", "MacBook Pro (15-inch, 2019)", 2019, .intel, "Intel", newestMacOS: 15),
        MacModel("MacBookPro15,4", "MacBook Pro (13-inch, 2019, Two Thunderbolt 3 ports)", 2019, .intel, "Intel", newestMacOS: 15),
        MacModel("MacBookPro16,1", "MacBook Pro (16-inch, 2019)", 2019, .intel, "Intel", newestMacOS: 26),
        MacModel("MacBookPro16,4", "MacBook Pro (16-inch, 2019)", 2019, .intel, "Intel", newestMacOS: 26),
        MacModel("MacBookPro16,2", "MacBook Pro (13-inch, 2020, Four Thunderbolt 3 ports)", 2020, .intel, "Intel", newestMacOS: 26),
        MacModel("MacBookPro16,3", "MacBook Pro (13-inch, 2020, Two Thunderbolt 3 ports)", 2020, .intel, "Intel", newestMacOS: 15),

        MacModel("Macmini8,1", "Mac mini (2018)", 2018, .intel, "Intel", newestMacOS: 15),

        MacModel("MacPro7,1", "Mac Pro (2019)", 2019, .intel, "Intel", newestMacOS: 26),
    ]

    /// The whole table, Apple silicon then Intel.
    public static let all: [MacModel] = appleSiliconModels + intelModels

    public static var appleSilicon: [MacModel] { appleSiliconModels }
    public static var intel: [MacModel] { intelModels }

    /// Identifier → model. A dictionary rather than a scan, because this is called once per
    /// launch per lookup and the table only grows.
    private static let byIdentifier: [String: MacModel] =
        Dictionary(all.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })

    /// `nil` for a Mac newer than this build. See the header: a missing entry is honest.
    public static func model(for identifier: String) -> MacModel? {
        byIdentifier[identifier]
    }

    /// Apple's own words for this model, or `nil`. A caller with `nil` shows the raw identifier —
    /// "Mac17,1" tells a person less than "MacBook Pro (14-inch, 2025)" and lies to them less than
    /// a guess would.
    public static func marketingName(for identifier: String) -> String? {
        byIdentifier[identifier]?.marketingName
    }

    /// The earliest release year among models Apple has not dropped.
    ///
    /// This is what "among the oldest models this macOS supports" means, computed rather than
    /// typed: the answer changes every September on its own, from the same edit that sets
    /// `newestMacOS` on the models being dropped.
    private static let oldestUndroppedYear: Int =
        all.filter { $0.newestMacOS == nil }.map(\.releaseYear).min() ?? 0

    /// Where this Mac sits in Apple's support window.
    ///
    /// `runningMacOS` is the major version actually booted, which is not always the newest the
    /// machine can run — somebody may simply not have updated.
    public static func standing(for identifier: String,
                                runningMacOS running: Int,
                                asOf date: Date = Date()) -> SupportStanding {
        guard let model = model(for: identifier) else { return .unknown }

        let year = Calendar.current.component(.year, from: date)

        guard let newest = model.newestMacOS else {
            // Apple has not dropped this model. The only distinction left is whether it is first
            // in line to be dropped — which is a fact about the machine, never a warning.
            return model.releaseYear == oldestUndroppedYear
                ? .oldestSupported(macOS: max(running, newestKnownMacOS))
                : .current
        }

        let through = securityUpdatesThrough(forMacOS: newest)

        if let through, year > through {
            return .noLongerUpdated(newestItCanRun: newest, since: through)
        }
        if newest >= newestKnownMacOS {
            return .lastRelease(macOS: newest, securityUpdatesThrough: through)
        }
        return .behind(newestItCanRun: newest, securityUpdatesThrough: through)
    }
}

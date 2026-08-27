import Foundation
import WellkeptCore

//  DemoData.swift
//  Wellkept — App/Shell
//
//  Invented results for all seven sections, so a finished Storage or Security screen can be
//  looked at and argued about months before its engine exists. Ported in shape from Scout's
//  `App/DemoData.swift`.
//
//  ⚠️ **Nothing here comes from this Mac, and nothing here reads it.** Every path, size, app name,
//  version and date below is made up. That is the point: a demo that read even one real value —
//  the actual free space, say — would make the invented rows beside it look real too, and the
//  first time somebody acted on one of them the app would have lied about their own machine.
//
//  The paths are real *shapes* (`~/Library/Application Support/MobileSync/Backup`) because a made-up
//  path teaches nothing about how the row will read. The folders are not consulted; only the shape
//  is borrowed.
//
//  ## ⚠️ Two Macs, not one
//
//  John, 2026-08-27, asked which machine the demo should be: *"I would give them both. The goal is
//  a healthy mac."* So demo mode offers a choice, and both are photographed:
//
//  - **A healthy Mac** — the point of the product. Everything checked, nothing wrong, and the
//    audit trail is the whole reassurance. It is not the boring case to skip; it is the case the
//    app exists to be able to show.
//  - **A Mac with problems** — the one that exercises the paths that have never run against a
//    real fault: a drive declaring failure, a battery Apple's own check calls failed, kernel
//    panics inside the week, and macOS force-quitting running programs to free memory. Nobody is
//    going to break a drive to look at that screen, so unless it is invented it never gets looked
//    at at all.
//
//  For the four sections with no engine yet the difference is a **filter, not a second set of
//  inventions**: the healthy Mac is the same list with everything at `.attention` or worse taken
//  out. Two hand-maintained copies of four sections' findings would disagree with each other inside
//  a month.
//
//  ## Hardware and Security are built out of the real row builders
//
//  The Hardware readings below are handed to `DriveReader.reading(for:)`, `BatteryReader.row(_:)`
//  and `HardwareReport.init`, and the Security rows to `ProtectionReader.row`, `GrantReader.row`,
//  `StartupReader.row`, `BrowserExtensionReader.row`, `ReachableReader.row` and
//  `MacOSFindingsReader.answer` — the same functions the real checks use. Only the *facts* are
//  invented. A demo that hand-wrote the finished sentences would photograph a screen whose wording
//  the app is no longer capable of producing, which is the failure this whole harness exists to
//  avoid from the other direction.

// MARK: - Which Mac

/// The two machines demo mode can show.
///
/// Raw values are storage — they go into `UserDefaults` under `demoMachine` — and the labels are
/// English. Renaming the option is one line in `label`, never a migration.
enum DemoMachine: String, CaseIterable, Identifiable, Sendable {
    /// Everything checked, nothing wrong. The default, because it is the product's own case.
    case healthy
    /// A drive declaring failure, a failed battery, panics, memory pressure — and, in Security,
    /// FileVault and the firewall both off, a permission held by an app that is gone, an app whose
    /// signature no longer matches, and something macOS found and dealt with.
    case problems

    var id: String { rawValue }

    var label: String {
        switch self {
        case .healthy:  "A healthy Mac"
        case .problems: "A Mac with problems"
        }
    }

    /// One line saying what the choice actually shows, so the two options are not two words a
    /// person has to click to tell apart.
    var blurb: String {
        switch self {
        case .healthy:
            "Everything checked and nothing wrong — what most Macs, most of the time, look like."
        case .problems:
            "A failing drive, a failed battery, kernel panics, a Mac running out of memory, and "
          + "FileVault and the firewall both switched off."
        }
    }
}

enum DemoData {

    // MARK: - When the demo check "ran"
    //
    // Offsets from the app's launch, resolved once, rather than a frozen calendar date. A demo
    // whose audit trail says "26 Aug 2026" reads as a broken clock the moment the year turns —
    // and the audit trail is precisely the part of Overview that is about dates being trustworthy.

    private static let launched = Date()
    private static func minutesAgo(_ m: Int) -> Date { launched.addingTimeInterval(-60 * Double(m)) }
    private static func daysAgo(_ d: Int) -> Date { launched.addingTimeInterval(-86_400 * Double(d)) }

    /// A date written the way the readers write one inside a sentence.
    private static func day(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: - The audit trail

    /// When each section last "ran", and what it concluded.
    ///
    /// **On the unwell Mac, Storage is deliberately `complete: false`.** It is the one state
    /// Overview must never get wrong — the app may not report a healthy Mac on the strength of a
    /// partial look — and a branch nobody can see is a branch nobody checks. This is how it gets
    /// looked at. On the healthy Mac every check saw everything, because otherwise "Everything
    /// looks fine" could never appear on screen at all, and that sentence is the product.
    static func records(_ machine: DemoMachine) -> [SectionID: CheckRecord] {
        let found = findings(machine)
        var out: [SectionID: CheckRecord] = [:]

        let ownRecord: Set<SectionID> = [.hardware, .security, .apps]
        for section in SectionID.checkable where !ownRecord.contains(section) {
            let mine = found.filter { $0.section == section }
            out[section] = CheckRecord(
                section: section,
                ranAt: minutesAgo(ranMinutesAgo[section] ?? 12),
                status: mine.contains(where: { $0.severity >= .attention }) ? .needsAttention : .good,
                complete: machine == .healthy || section != .storage)
        }

        // Hardware's line comes from the report itself rather than being written twice. The chip
        // on the sidebar's audit trail and the chip on the Hardware screen are then the same fact,
        // and cannot drift apart.
        out[.hardware] = hardware(machine).record

        // Security's line, for the same reason: the chip on the sidebar's audit trail and the chip
        // on the Security screen are one fact, and `SecurityReport.record` is where it lives.
        out[.security] = security(machine).report.record

        // Apps' line, for the same reason. It is always `Good`: `AppsReport.status` has no route to
        // `.needsAttention`, so the chip in the sidebar's audit trail and the chip on the Apps
        // screen are one fact that cannot drift.
        out[.apps] = apps(machine).report.record

        // Overview's own line is the whole sweep: the oldest of the six, because that is when the
        // sweep began, and honest about any partial look inside it.
        let all = Array(out.values)
        out[.overview] = CheckRecord(
            section: .overview,
            ranAt: all.map(\.ranAt).min() ?? minutesAgo(14),
            status: all.contains(where: { $0.status == .needsAttention }) ? .needsAttention : .good,
            complete: all.allSatisfy(\.complete))
        return out
    }

    private static let ranMinutesAgo: [SectionID: Int] = [
        .hardware: 14, .storage: 13, .apps: 11, .security: 11, .backup: 10, .changes: 9,
    ]

    // MARK: - What it "found"

    /// Every row demo mode shows, for one machine.
    ///
    /// ⚠️ Hardware and Security each contribute **exactly one** row here, whatever they found —
    /// their `overviewFinding`. A section that posts five rows to Overview has turned the summary
    /// into a second copy of itself, and the section a person should actually open gets lost among
    /// its own details.
    static func findings(_ machine: DemoMachine) -> [Finding] {
        let others = storage + backup + changes
        let kept = machine == .healthy ? others.filter { $0.severity < .attention } : others
        // ⚠️ Apps contributes exactly one row, `.information`, on both Macs — and it is **not**
        // filtered out of the healthy one, because `.information` is what it always is. Apps cannot
        // turn Overview amber this round: without vulnerability data a version behind is not
        // something wrong, so the row is there for the audit trail and never in "what needs you".
        return [hardware(machine).overviewFinding,
                security(machine).report.overviewFinding,
                apps(machine).report.overviewFinding]
            .compactMap { $0 } + kept
    }

    // MARK: - Hardware

    /// The whole Hardware answer for one machine, built once so its `Finding` keeps a stable `id`.
    ///
    /// ⚠️ Computed once and cached, not rebuilt per call. `HardwareReport.overviewFinding` mints a
    /// fresh `UUID`, and a `Finding` with a new identity on every draw is how a list animates
    /// itself to pieces.
    static func hardware(_ machine: DemoMachine) -> HardwareReport {
        switch machine {
        case .healthy:  healthyHardware
        case .problems: unwellHardware
        }
    }

    /// The two-step failing-drive screen, on the Mac that has one. `nil` on the healthy Mac.
    static func driveAlarm(_ machine: DemoMachine) -> DriveAlarm? {
        machine == .problems ? DriveReader.alarm(for: unwellDrives) : nil
    }

    // MARK: A healthy Mac

    private static let healthyFacts = MachineFacts(
        name: "Sample MacBook Air",
        modelName: MacModels.marketingName(for: "Mac14,2") ?? "Mac14,2",
        modelIdentifier: "Mac14,2",
        chip: "Apple M2",
        memory: "16 GB",
        driveSize: "494 GB",
        systemVersion: "macOS 26.6.2",
        systemMajorVersion: 26,
        inUseSince: daysAgo(981),
        // Obviously invented, and shaped like a serial so the repair-shop copy can be judged. A
        // demo carrying something that looks like a real serial is a screenshot nobody can share.
        serialNumber: "DEMOAIR00001",
        isVirtualMachine: false)

    private static let healthyHardware = HardwareReport(
        facts: healthyFacts,
        readings: [
            DriveReader.reading(for: [DriveFacts.exampleHealthy]),

            BatteryReader.row(BatteryReader.Facts(
                applePercent: 94,
                measuredPercent: nil,
                condition: .normal,
                failureModes: [],
                charge: 78,
                cycles: 214,
                designCycles: 1_000,
                fullChargeCapacity: 4_628,
                designCapacity: 4_920,
                pluggedIn: true,
                charging: false,
                fullyCharged: false,
                isVirtualMachine: false)),

            Reading(
                topic: .memory,
                headline: "This Mac has enough memory for what you run on it.",
                measure: nil,
                number: ReadingNumber(0, ReadingNumber.count),
                severity: .information,
                reason: "Nothing has been closed to free memory in the last 12 days. Memory is not "
                      + "under pressure right now.",
                details: [
                    DetailPair("Installed", "16 GB"),
                    DetailPair("Pressure", "Normal"),
                    DetailPair("Swap", "None in use"),
                    DetailPair("Compressed", "1.9 GB"),
                    DetailPair("Reports go back to", day(daysAgo(12))),
                    DetailPair("Thermal pressure", "Normal"),
                ]),

            Reading(
                topic: .restarts,
                headline: "This Mac has not restarted on its own.",
                measure: nil,
                number: ReadingNumber(0, ReadingNumber.count),
                severity: .information,
                reason: "Nothing since \(day(daysAgo(12))), which is as far back as macOS keeps "
                      + "these reports. A power cut leaves no report at all.",
                details: [
                    DetailPair("Kernel panics", "None found"),
                    DetailPair("Reports go back to", day(daysAgo(12))),
                    DetailPair("Read from", "/Library/Logs/DiagnosticReports"),
                ]),

            SpeedTest.reading(
                SpeedResult(read: SpeedRate(bytes: 256_000_000, seconds: 0.086),
                            readFileCount: 12,
                            write: SpeedRate(bytes: 256_000_000, seconds: 0.110),
                            ranAt: minutesAgo(14),
                            note: nil),
                history: []),
        ],
        ranAt: minutesAgo(14))

    // MARK: A Mac with problems

    /// A failing internal drive with a healthy USB disk beside it — which is also what makes the
    /// Options panel prefix every detail with the drive it belongs to.
    private static let unwellDrives = [DriveFacts.exampleFailing, DriveFacts.exampleExternal]

    private static let unwellFacts = MachineFacts(
        name: "Sample MacBook Pro",
        modelName: MacModels.marketingName(for: "MacBookPro15,1") ?? "MacBookPro15,1",
        modelIdentifier: "MacBookPro15,1",
        chip: "2.6 GHz 6-Core Intel Core i7",
        memory: "8 GB",
        driveSize: "494 GB",
        systemVersion: "macOS 15.7.1",
        systemMajorVersion: 15,
        inUseSince: daysAgo(2_760),
        serialNumber: "DEMOPRO00001",
        isVirtualMachine: false)

    private static let unwellHardware = HardwareReport(
        facts: unwellFacts,
        readings: [
            DriveReader.reading(for: unwellDrives),

            BatteryReader.row(BatteryReader.Facts(
                applePercent: 61,
                measuredPercent: nil,
                condition: .failed,
                failureModes: ["Permanent Battery Failure"],
                charge: 41,
                cycles: 1_187,
                designCycles: 1_000,
                fullChargeCapacity: 3_140,
                designCapacity: 5_088,
                pluggedIn: true,
                charging: false,
                fullyCharged: false,
                isVirtualMachine: false)),

            Reading(
                topic: .memory,
                headline: "macOS closed 3 running programs to free memory.",
                measure: "3",
                number: ReadingNumber(3, ReadingNumber.count),
                severity: .problem,
                reason: "Safari (twice) and Photos were closed by macOS in the last 7 days because "
                      + "this Mac ran out of memory. Running fewer things at once is what frees "
                      + "it up.",
                details: [
                    DetailPair("Installed", "8 GB"),
                    DetailPair("Pressure", "Warning"),
                    DetailPair("Swap", "7.4 GB of 8 GB"),
                    DetailPair("Compressed", "3.9 GB"),
                    DetailPair("Closed to free memory",
                               "Safari on \(day(daysAgo(2))) and \(day(daysAgo(5))), "
                               + "Photos on \(day(daysAgo(6)))"),
                    DetailPair("Reports go back to", day(daysAgo(9))),
                    DetailPair("Thermal pressure", "Running hot"),
                ]),

            Reading(
                topic: .restarts,
                headline: "This Mac has restarted on its own twice in the last 30 days.",
                measure: "2",
                number: ReadingNumber(2, ReadingNumber.count),
                severity: .attention,
                reason: "The most recent was on \(day(daysAgo(4))). Wellkept reports what the "
                      + "panic said about itself; it does not work out what caused it.",
                details: [
                    DetailPair("Most recent", day(daysAgo(4))),
                    DetailPair("Before that", day(daysAgo(19))),
                    DetailPair("What the panic said",
                               "Kernel trap at 0xffffff80… — the panic's own first line"),
                    DetailPair("Named in the backtrace", "com.example.vendor.driver"),
                    DetailPair("Reports go back to", day(daysAgo(30))),
                ]),

            SpeedTest.restingReading(history: []),
        ],
        ranAt: minutesAgo(14))

    // MARK: Storage

    private static let storage: [Finding] = [
        Finding(section: .storage,
                title: "61 GB of deleted files has not been released",
                reason: "A Time Machine local snapshot from 3 August is holding it. macOS frees this on its own when it needs the room, but not before.",
                severity: .attention,
                measure: "61 GB",
                verb: "Reveal in Finder"),
        Finding(section: .storage,
                title: "iPhone backups in MobileSync",
                reason: "Two backups, the newer one from March 2024. ~/Library/Application Support/MobileSync/Backup",
                severity: .information,
                measure: "84.3 GB",
                verb: "Reveal in Finder"),
        Finding(section: .storage,
                title: "Xcode DerivedData",
                reason: "Build output. Xcode writes it again whenever it needs it, so nothing here is yours.",
                severity: .information,
                measure: "41.7 GB",
                verb: "Quarantine"),
        Finding(section: .storage,
                title: "Downloads — 1,340 files, oldest from 2019",
                reason: "Your own files, so nothing is selected. Sorted largest first inside.",
                severity: .information,
                measure: "22.9 GB",
                verb: "Reveal in Finder"),
        Finding(section: .storage,
                title: "Docker.raw",
                reason: "One disk image holding every container. It grows and does not shrink on its own.",
                severity: .information,
                measure: "18.2 GB",
                verb: "Reveal in Finder"),
    ]

    // MARK: - Apps

    /// The whole Apps answer for one machine, built once so its `Finding` keeps a stable `id`.
    ///
    /// ⚠️ Computed once and cached, not rebuilt per call. `AppsReport` mints a fresh `UUID` for its
    /// Overview row, and a `Finding` with a new identity on every draw is how a list animates itself
    /// to pieces.
    ///
    /// ## ⚠️ Built out of the real row builders, exactly as Hardware and Security are
    ///
    /// Every row below comes from `InventoryReader.row`, `MacOSRow.row`, `UpdatesRow.row`,
    /// `CrashReader.answer` and `LeftoverReader.answer` — the same functions the real check calls,
    /// and for the last two the same **pure** functions, fed an invented survey. Only the facts are
    /// invented.
    ///
    /// ## ⚠️ Neither demo Mac may show anything the real readers cannot produce
    ///
    /// That rule does real work here, and three places show it:
    ///
    /// - **"Keeps itself up to date" is only ever said about an app on `SelfUpdatingApps`' list**,
    ///   and the demo looks the entry up rather than typing the standing in. Drop an app from that
    ///   list and it disappears from the demo instead of appearing there with a claim the real
    ///   reader would never make.
    /// - **Nothing is amber.** `AppsRow.severity` is a constant, so there is no arrangement of these
    ///   facts that could colour a row — which is exactly what the picture is meant to prove.
    /// - **The crash counts are what survives the filter**, not what is in the folder. Both Macs
    ///   below carry the seven kinds of report that are not crashes, because a demo that showed only
    ///   real crashes would photograph a screen whose filtering is invisible.
    static func apps(_ machine: DemoMachine) -> AppsAnswer {
        switch machine {
        case .healthy:  healthyApps
        case .problems: unwellApps
        }
    }

    // MARK: One invented app

    private static func app(_ name: String,
                            _ bundleID: String,
                            version: String,
                            build: String? = nil,
                            megabytes: Double,
                            installed: Int,
                            opened: Int?,
                            architecture: AppArchitecture = .universal,
                            signedBy: SignedBy,
                            origin: AppOrigin,
                            update: UpdateStanding,
                            addedByHand: Bool = false) -> InstalledApp {
        InstalledApp(name: name,
                     bundleID: bundleID,
                     version: version,
                     build: build,
                     bytes: Int64(megabytes * 1_000_000),
                     installedAt: daysAgo(installed),
                     lastOpenedAt: opened.map { daysAgo($0) },
                     architecture: architecture,
                     signedBy: signedBy,
                     origin: origin,
                     update: update,
                     addedByHand: addedByHand)
    }

    /// An app that looks after itself — **looked up in `SelfUpdatingApps` rather than asserted.**
    ///
    /// ⚠️ Returns `nil` when the name is not on that list, and the caller drops it. That is the
    /// enforcement of the rule in the header: the demo cannot say "keeps itself up to date" about an
    /// app the real reader would call unknown, because the standing comes from the same lookup the
    /// reader uses.
    private static func selfUpdatingApp(_ name: String,
                                        version: String,
                                        megabytes: Double,
                                        installed: Int,
                                        opened: Int?,
                                        signedBy: SignedBy,
                                        origin: AppOrigin = .developerID) -> InstalledApp? {
        guard let entry = SelfUpdatingApps.entries.first(where: { $0.name == name }),
              let standing = SelfUpdatingApps.standing(forBundleID: entry.bundleID)
        else { return nil }
        return app(entry.name, entry.bundleID,
                   version: version, megabytes: megabytes,
                   installed: installed, opened: opened,
                   signedBy: signedBy, origin: origin, update: standing)
    }

    /// The apps that come with macOS. **Counted, never listed** — 37 here, and folding them into the
    /// person's list would more than double the number on the section's first line.
    private static let macOSApps: [InstalledApp] = [
        "App Store", "Automator", "Books", "Calculator", "Calendar", "Chess", "Clock", "Contacts",
        "Dictionary", "FaceTime", "Find My", "Font Book", "Freeform", "Home", "Image Capture",
        "Mail", "Maps", "Messages", "Music", "News", "Notes", "Photo Booth", "Photos", "Podcasts",
        "Preview", "QuickTime Player", "Reminders", "Shortcuts", "Stickies", "Stocks",
        "System Settings", "TextEdit", "Time Machine", "TV", "Voice Memos", "Weather", "Terminal",
    ].map { name in
        app(name, "com.apple." + name.replacingOccurrences(of: " ", with: ""),
            version: "26.6", megabytes: 24, installed: 981, opened: nil,
            signedBy: .apple, origin: .bundledWithMacOS,
            update: .couldNotTell(.shipsWithMacOS))
    }

    /// macOS itself, through the real reader's pure half, so the row is assembled exactly as it is
    /// on a real Mac. **Nothing about a waiting update is claimed** — the caveat travels with it.
    private static func macOSState(version: String,
                                   build: String,
                                   installedDaysAgo: Int,
                                   automatic: Bool) -> MacOSUpdateState {
        MacOSUpdateState.make(
            settings: [
                "AutomaticCheckEnabled": automatic,
                "AutomaticDownload": automatic,
                "CriticalUpdateInstall": true,
                "ConfigDataInstall": true,
                "AutomaticallyInstallMacOSUpdates": automatic,
                "LastSuccessfulDate": daysAgo(1),
                "FirstOfferDateDictionary": [
                    "MSU_UPDATE_\(build)_patch_\(version)_minor": daysAgo(installedDaysAgo + 2),
                ],
                "InstallDateDictionary": [build: daysAgo(installedDaysAgo)],
            ],
            managed: nil,
            systemVersion: ["ProductVersion": version, "ProductBuildVersion": build])
    }

    // MARK: Apps — a healthy Mac

    /// **A tidy Applications folder: two updates waiting, four apps that look after themselves, and
    /// three nobody publishes a version for.**
    ///
    /// ⚠️ This is the picture the coverage sentence exists for. Six apps were genuinely checked out
    /// of fifteen installed, and the section says so in the same breath as the count — never "2
    /// updates available", which is true and leaves out the part that matters.
    private static let healthyApps: AppsAnswer = {
        let installed: [InstalledApp] = [
            // ⚠️ Absent from macOS's own inventory — a symlink into the Preboot Cryptex with
            // restricted and hidden flags — and the 4th most-launched app on the measured Mac. Added
            // by hand, and the line says so.
            app("Safari", "com.apple.Safari", version: "26.6", megabytes: 118,
                installed: 981, opened: 0, signedBy: .apple, origin: .bundledWithMacOS,
                update: .couldNotTell(.shipsWithMacOS), addedByHand: true),

            app("Pages", "com.apple.iWork.Pages", version: "15.3.1", megabytes: 812,
                installed: 640, opened: 9, signedBy: .apple, origin: .appStore, update: .current),
            app("Numbers", "com.apple.iWork.Numbers", version: "15.3.1", megabytes: 704,
                installed: 640, opened: 31, signedBy: .apple, origin: .appStore, update: .current),
            // ⚠️ macOS reports nothing at all for 6 of the 31 apps on the measured Mac, Keynote
            // among them, and it is demonstrably run. A blank here is ordinary, which is why "apps
            // you have not opened" is not a finding anywhere in this section.
            app("Keynote", "com.apple.iWork.Keynote", version: "15.3.1", megabytes: 934,
                installed: 640, opened: nil, signedBy: .apple, origin: .appStore, update: .current),

            app("Things 3", "com.culturedcode.ThingsMac", version: "3.20.4", megabytes: 61,
                installed: 412, opened: 0,
                signedBy: .developer("Cultured Code GmbH & Co. KG"), origin: .appStore,
                update: .newerAvailable("3.20.6")),
            app("Transmit", "com.panic.Transmit", version: "5.10.6", megabytes: 96,
                installed: 300, opened: 4,
                signedBy: .developer("Panic, Inc."), origin: .developerID,
                update: .newerAvailable("5.10.7")),
            app("Rectangle", "com.knollsoft.Rectangle", version: "0.87", megabytes: 12,
                installed: 220, opened: 1,
                signedBy: .developer("Ryan Hanson"), origin: .homebrew, update: .current),
            app("Fantastical", "com.flexibits.fantastical2.mac", version: "4.0.6", megabytes: 148,
                installed: 560, opened: 0,
                signedBy: .developer("Flexibits Inc."), origin: .appStore, update: .current),
            app("Bear", "net.shinyfrog.bear", version: "2.6.2", megabytes: 92,
                installed: 380, opened: 2,
                signedBy: .developer("Shiny Frog Ltd."), origin: .appStore, update: .current),
            app("Pixelmator Pro", "com.pixelmatorteam.pixelmator.x", version: "3.6.16",
                megabytes: 1_180, installed: 450, opened: 18,
                signedBy: .developer("Pixelmator Team"), origin: .appStore, update: .current),
            app("HandBrake", "fr.handbrake.HandBrake", version: "1.9.2", megabytes: 132,
                installed: 260, opened: 44,
                signedBy: .developer("HandBrake Team"), origin: .homebrew, update: .current),

            // The honest cost of the decision of 2026-08-27 not to keep a list of makers' version
            // pages. Three apps here, and the row says why rather than shrugging.
            app("BBEdit", "com.barebones.bbedit", version: "15.5.2", megabytes: 168,
                installed: 700, opened: 2,
                signedBy: .developer("Bare Bones Software, Inc."), origin: .developerID,
                update: .couldNotTell(.noSourceToAsk)),
            app("iTerm2", "com.googlecode.iterm2", version: "3.5.11", megabytes: 142,
                installed: 900, opened: 0,
                signedBy: .developer("GEORGE NACHMAN"), origin: .developerID,
                update: .couldNotTell(.noSourceToAsk)),
            app("Obsidian", "md.obsidian", version: "1.7.7", megabytes: 540,
                installed: 340, opened: 0,
                signedBy: .developer("Dynalist Inc."), origin: .developerID,
                update: .couldNotTell(.noSourceToAsk)),
            app("Signal", "org.whispersystems.signal-desktop", version: "7.35.0", megabytes: 480,
                installed: 520, opened: 1,
                signedBy: .developer("Quiet Riddle Ventures LLC"), origin: .developerID,
                update: .couldNotTell(.noSourceToAsk)),
            app("Zotero", "org.zotero.zotero", version: "7.0.11", megabytes: 410,
                installed: 290, opened: 26,
                signedBy: .developer("Corporation for Digital Scholarship"), origin: .developerID,
                update: .couldNotTell(.noSourceToAsk)),
            // "2.6.0.3141" against a storefront's "2.6.0" is the hazard 13 of 18 apps carry. We
            // have both numbers and cannot compare them honestly, so we say that.
            app("Affinity Photo 2", "com.seriflabs.affinityphoto2", version: "2.6.0",
                build: "2.6.0.3141", megabytes: 1_640, installed: 500, opened: 22,
                signedBy: .developer("Serif (Europe) Ltd"), origin: .appStore,
                update: .couldNotTell(.versionsNotComparable)),

            // A pre-release build. The storefront answers about the shipping version, which is a
            // different piece of software — so it is out of scope rather than out of date.
            app("Ivory", "com.tapbots.Ivory", version: "1.9.1", megabytes: 44,
                installed: 180, opened: 3,
                signedBy: .developer("TestFlight Beta Distribution"), origin: .unknown,
                update: .couldNotTell(.testFlightBuild)),
        ] + [
            selfUpdatingApp("Google Chrome", version: "141.0.7390.54", megabytes: 620,
                            installed: 800, opened: 0, signedBy: .developer("Google LLC")),
            selfUpdatingApp("Firefox", version: "144.0.1", megabytes: 480,
                            installed: 640, opened: 6, signedBy: .developer("Mozilla Corporation")),
            selfUpdatingApp("Visual Studio Code", version: "1.96.2", megabytes: 720,
                            installed: 520, opened: 0,
                            signedBy: .developer("Microsoft Corporation")),
            selfUpdatingApp("Slack", version: "4.44.65", megabytes: 340,
                            installed: 470, opened: 1,
                            signedBy: .developer("Slack Technologies, LLC")),
            selfUpdatingApp("Notion", version: "4.3.1", megabytes: 380,
                            installed: 410, opened: 0, signedBy: .developer("Notion Labs, Inc.")),
            selfUpdatingApp("Raycast", version: "1.85.2", megabytes: 210,
                            installed: 330, opened: 0,
                            signedBy: .developer("Raycast Technologies Inc.")),
            selfUpdatingApp("Discord", version: "0.0.340", megabytes: 290,
                            installed: 610, opened: 5,
                            signedBy: .developer("Discord Inc.")),
            selfUpdatingApp("Brave", version: "1.72.165", megabytes: 640,
                            installed: 720, opened: 34, signedBy: .developer("Brave Software, Inc.")),
        ].compactMap { $0 }

        // ⚠️ 26 apps, 37 that come with macOS, and 359 bundles that are not apps — **422 in all,
        // which is the number the measured Mac actually holds.** A cleaner would print the 422. The
        // number a person recognises is the first one, and the block says where the other two went.
        let inventory = AppsInventory(apps: installed,
                                      otherBundles: 359,
                                      gatheredAt: minutesAgo(11))
        let macOS = macOSState(version: "26.6.2", build: "25G83",
                               installedDaysAgo: 12, automatic: true)
        let update = UpdateReader.Answer(
            standings: [:],
            namedToAppStore: ["Affinity Photo 2", "Bear", "Fantastical", "Keynote", "Numbers",
                              "Pages", "Pixelmator Pro", "Things 3"],
            consent: .allowed,
            casksRead: 62)

        let known = Set(installed.map(\.bundleID) + macOSApps.map(\.bundleID))

        // 78 files in the folder, none of them an app on this Mac crashing. That is the measured
        // truth and it is the whole reason this row exists in the shape it does.
        let crash = CrashReader.answer(from: quietCrashFolder, appsOnThisMac: known, now: launched)

        let left = LeftoverReader.answer(from: LeftoverReader.Survey(candidates: tidyLibrary,
                                                                    notIdentifiers: 14),
                                         appsOnThisMac: known,
                                         runningBundleIDs: [],
                                         isRegistered: { _ in false })

        let rows = [
            InventoryReader.row(inventory: inventory, bundledWithMacOS: macOSApps,
                                blockShownAbove: true),
            MacOSRow.row(macOS),
            UpdatesRow.row(inventory: inventory, update: update),
            crash.row,
            left.row,
        ]

        return AppsAnswer(report: AppsReport(inventory: inventory,
                                             rows: rows,
                                             ranAt: minutesAgo(11)),
                          crashes: crash.crashes,
                          leftovers: left.leftovers,
                          macOS: macOS,
                          update: update,
                          bundledWithMacOS: macOSApps,
                          crashWindowDays: crash.windowDays)
    }()

    // MARK: Apps — a Mac with problems

    /// **The five paths nobody building this will otherwise see**: an app that has stopped working
    /// over and over, four updates waiting, an Intel-only app, and two removed apps that left things
    /// behind.
    ///
    /// ⚠️ **Everything here is still `.information`, and that is the point of the picture.** Nothing
    /// on this screen is amber and nothing is red. A version behind is not something wrong, an
    /// Intel-only app is a labelled fact rather than a countdown, and an app that crashes is
    /// reported without being dressed up as an emergency.
    private static let unwellApps: AppsAnswer = {
        let installed: [InstalledApp] = [
            app("Safari", "com.apple.Safari", version: "15.7", megabytes: 118,
                installed: 2_760, opened: 0, signedBy: .apple, origin: .bundledWithMacOS,
                update: .couldNotTell(.shipsWithMacOS), addedByHand: true),

            app("Pages", "com.apple.iWork.Pages", version: "14.2", megabytes: 780,
                installed: 900, opened: 40, signedBy: .apple, origin: .appStore, update: .current),
            app("Numbers", "com.apple.iWork.Numbers", version: "14.1", megabytes: 690,
                installed: 900, opened: 61, signedBy: .apple, origin: .appStore,
                update: .newerAvailable("14.2")),
            app("Keynote", "com.apple.iWork.Keynote", version: "14.2", megabytes: 910,
                installed: 900, opened: nil, signedBy: .apple, origin: .appStore, update: .current),

            app("Things 3", "com.culturedcode.ThingsMac", version: "3.19.0", megabytes: 61,
                installed: 700, opened: 12,
                signedBy: .developer("Cultured Code GmbH & Co. KG"), origin: .appStore,
                update: .newerAvailable("3.20.6")),
            app("Transmit", "com.panic.Transmit", version: "5.8.2", megabytes: 96,
                installed: 800, opened: 90,
                signedBy: .developer("Panic, Inc."), origin: .developerID,
                update: .newerAvailable("5.10.7")),
            app("Kindle", "com.amazon.Lassen", version: "7.24", megabytes: 214,
                installed: 1_500, opened: 210,
                signedBy: .developer("AMZN Mobile LLC"), origin: .appStore,
                update: .newerAvailable("7.30")),

            // ⚠️ **A plain labelled fact and nothing else.** No colour, no countdown, no "will stop
            // working". macOS 26.4 already warns at launch, only the developer can act, and nothing
            // about a Rosetta app is a security matter.
            app("Audacity", "org.audacityteam.audacity", version: "3.4.2", megabytes: 190,
                installed: 1_900, opened: 400, architecture: .intelOnly,
                signedBy: .developer("Audacity Team"), origin: .developerID,
                update: .couldNotTell(.noSourceToAsk)),

            app("Microsoft Teams", "com.microsoft.teams2", version: "24.255.1", megabytes: 1_180,
                installed: 400, opened: nil,
                signedBy: .developer("Microsoft Corporation"), origin: .developerID,
                update: .couldNotTell(.noSourceToAsk)),
            app("LibreOffice", "org.libreoffice.script", version: "25.2.5.2", megabytes: 1_460,
                installed: 600, opened: 55,
                signedBy: .developer("The Document Foundation"), origin: .developerID,
                update: .couldNotTell(.versionsNotComparable)),
            app("Adobe Acrobat Reader", "com.adobe.Reader", version: "24.002.20857",
                megabytes: 640, installed: 1_100, opened: 30,
                signedBy: .developer("Adobe Inc."), origin: .developerID,
                update: .couldNotTell(.askFailed)),
            app("iTerm2", "com.googlecode.iterm2", version: "3.4.19", megabytes: 142,
                installed: 1_400, opened: 2,
                signedBy: .developer("GEORGE NACHMAN"), origin: .developerID,
                update: .couldNotTell(.noSourceToAsk)),
            app("VLC", "org.videolan.vlc", version: "3.0.21", megabytes: 128,
                installed: 1_000, opened: 120,
                signedBy: .developer("VideoLAN"), origin: .homebrew, update: .current),
        ] + [
            selfUpdatingApp("Google Chrome", version: "139.0.7258.66", megabytes: 620,
                            installed: 1_200, opened: 0, signedBy: .developer("Google LLC")),
            selfUpdatingApp("Zoom", version: "6.0.10", megabytes: 410,
                            installed: 900, opened: 3,
                            signedBy: .developer("Zoom Video Communications, Inc.")),
            selfUpdatingApp("Slack", version: "4.41.98", megabytes: 340,
                            installed: 800, opened: 1,
                            signedBy: .developer("Slack Technologies, LLC")),
            selfUpdatingApp("Docker Desktop", version: "4.29.0", megabytes: 2_100,
                            installed: 600, opened: 7,
                            signedBy: .developer("Docker Inc")),
        ].compactMap { $0 }

        let inventory = AppsInventory(apps: installed,
                                      otherBundles: 318,
                                      gatheredAt: minutesAgo(11))
        let macOS = macOSState(version: "15.7.1", build: "24G231",
                               installedDaysAgo: 96, automatic: false)
        let update = UpdateReader.Answer(
            standings: [:],
            namedToAppStore: ["Keynote", "Kindle", "Numbers", "Pages", "Things 3"],
            consent: .allowed,
            casksRead: 9)

        let known = Set(installed.map(\.bundleID) + macOSApps.map(\.bundleID))

        let crash = CrashReader.answer(from: teamsKeepsCrashing, appsOnThisMac: known, now: launched)

        let left = LeftoverReader.answer(from: LeftoverReader.Survey(candidates: tidyLibrary + removedApps,
                                                                    notIdentifiers: 22),
                                         appsOnThisMac: known,
                                         runningBundleIDs: [],
                                         isRegistered: { _ in false })

        let rows = [
            InventoryReader.row(inventory: inventory, bundledWithMacOS: macOSApps,
                                blockShownAbove: true),
            MacOSRow.row(macOS),
            UpdatesRow.row(inventory: inventory, update: update),
            crash.row,
            left.row,
        ]

        return AppsAnswer(report: AppsReport(inventory: inventory,
                                             rows: rows,
                                             ranAt: minutesAgo(11)),
                          crashes: crash.crashes,
                          leftovers: left.leftovers,
                          macOS: macOS,
                          update: update,
                          bundledWithMacOS: macOSApps,
                          crashWindowDays: crash.windowDays)
    }()

    // MARK: Apps — the crash folder

    /// **The seven kinds of report that are not an app on this Mac crashing**, one of each.
    ///
    /// ⚠️ Present on **both** demo Macs, because the filtering is the row's entire value and a demo
    /// that showed only real crashes would photograph a screen whose work is invisible. 108 files on
    /// the measured Mac reduced to zero; these seven plus 71 uncounted notices reduce to zero too,
    /// and the row's tally says where each of them went.
    private static let notCrashes: [CrashReader.Report] = [
        // A performance notice. Nothing crashed.
        CrashReader.Report(fileName: "Sample-2026-cpu_resource.diag",
                           bundleID: "com.example.sample", appName: "Sample",
                           bugType: "226", platform: 1, at: daysAgo(4)),
        // macOS stopped it for memory. Named separately so it can never be swallowed by the
        // general bucket — Hardware's memory reading is where that answer belongs.
        CrashReader.Report(fileName: "Sample-2026-08-hang.ips",
                           bundleID: "com.example.sample", appName: "Sample",
                           bugType: "298", platform: 1, at: daysAgo(9)),
        // Filed by an app about itself, which then carried on running. Safari did this four times
        // on the measured Mac while staying open the whole time.
        CrashReader.Report(fileName: "ExcUserFault_Sample-2026-08.ips",
                           bundleID: "com.example.sample", appName: "Sample",
                           bugType: "309", platform: 1, isSelfFiled: true, at: daysAgo(11)),
        // The iPhone simulator's own machinery.
        CrashReader.Report(fileName: "SimLaunchHost-2026-08.ips",
                           bundleID: "com.apple.CoreSimulator.SimLaunchHost",
                           appName: "SimLaunchHost", bugType: "309", platform: 1, at: daysAgo(13)),
        // Built for another device, running here under the simulator.
        CrashReader.Report(fileName: "SampleiOS-2026-08.ips",
                           bundleID: "com.example.sample.ios", appName: "SampleiOS",
                           bugType: "309", platform: 2, at: daysAgo(15)),
        // A command-line tool. Nobody launched an app.
        CrashReader.Report(fileName: "sample-helper-2026-08.ips",
                           bundleID: nil, appName: "sample-helper",
                           bugType: "309", platform: 1, at: daysAgo(17)),
        // An app, but not one this section lists — something being built, or since removed.
        CrashReader.Report(fileName: "OldThing-2026-08.ips",
                           bundleID: "com.example.oldthing", appName: "Old Thing",
                           bugType: "309", platform: 1, at: daysAgo(19)),
    ]

    /// The healthy Mac's folder: 78 files, and not one of them an app crashing.
    private static let quietCrashFolder = CrashReader.Survey(
        reports: notCrashes,
        nonCrashFiles: 71,
        earliestRecord: daysAgo(24))

    /// The unwell Mac's: the same noise, plus one app that really has stopped working, five times.
    private static let teamsKeepsCrashing = CrashReader.Survey(
        reports: notCrashes + [2, 6, 8, 14, 20].map { day in
            CrashReader.Report(fileName: "Teams-2026-08-\(day).ips",
                               bundleID: "com.microsoft.teams2", appName: "Microsoft Teams",
                               bugType: "309", platform: 1, at: daysAgo(day))
        },
        nonCrashFiles: 84,
        earliestRecord: daysAgo(21))

    // MARK: Apps — the Library

    /// **Three things in the Library that look like leftovers and are not** — on both Macs.
    ///
    /// ⚠️ These are the guards doing their job, and the reason the row is worth trusting. The
    /// Keystone folder is the case that matters: an updater belonging to an installed browser, filed
    /// under a name that app has never used, and exactly what a name-matching cleaner offers to
    /// delete.
    private static let tidyLibrary: [LeftoverReader.Candidate] = [
        LeftoverReader.Candidate(identifier: "com.apple.Safari",
                                 place: .caches,
                                 path: "~/Library/Caches/com.apple.Safari",
                                 bytes: 240_000_000),
        LeftoverReader.Candidate(identifier: "com.google.Keystone",
                                 place: .applicationSupport,
                                 path: "~/Library/Application Support/com.google.Keystone",
                                 bytes: 18_000_000),
        LeftoverReader.Candidate(identifier: "com.culturedcode.ThingsMac",
                                 place: .applicationSupport,
                                 path: "~/Library/Application Support/com.culturedcode.ThingsMac",
                                 bytes: 96_000_000),
    ]

    /// Two apps that really are gone, each with a folder macOS made on its behalf.
    ///
    /// ⚠️ **Each carries its own size and there is no total anywhere.** Name-matching everything on
    /// the measured Mac produces 7.6 GB against about 350 MB genuinely orphaned — a headline number
    /// would be wrong by a factor of twenty, and it is the number a cleaner puts in a big font.
    private static let removedApps: [LeftoverReader.Candidate] = [
        LeftoverReader.Candidate(identifier: "com.superduper.SuperDuper",
                                 place: .applicationSupport,
                                 path: "~/Library/Application Support/com.superduper.SuperDuper",
                                 bytes: 148_000_000),
        LeftoverReader.Candidate(identifier: "com.superduper.SuperDuper",
                                 place: .preferences,
                                 path: "~/Library/Preferences/com.superduper.SuperDuper.plist",
                                 bytes: 24_000),
        LeftoverReader.Candidate(identifier: "com.evernote.Evernote",
                                 place: .applicationSupport,
                                 path: "~/Library/Application Support/com.evernote.Evernote",
                                 bytes: 612_000_000),
        LeftoverReader.Candidate(identifier: "com.evernote.Evernote",
                                 place: .savedApplicationState,
                                 path: "~/Library/Saved Application State/com.evernote.Evernote.savedState",
                                 bytes: 1_400_000),
        LeftoverReader.Candidate(identifier: "com.evernote.Evernote",
                                 place: .logs,
                                 path: "~/Library/Logs/com.evernote.Evernote",
                                 bytes: 3_100_000),
    ]

    // MARK: Security

    /// The whole Security answer for one machine, built once so its `Finding` keeps a stable `id`.
    ///
    /// ⚠️ Computed once and cached, not rebuilt per call. `SecurityReport.overviewFinding` mints a
    /// fresh `UUID`, and a `Finding` with a new identity on every draw is how a list animates itself
    /// to pieces.
    ///
    /// ## ⚠️ Built out of the real row builders, exactly as Hardware is
    ///
    /// Every row below comes from `ProtectionReader.row`, `GrantReader.row`, `StartupReader.row`,
    /// `BrowserExtensionReader.row`, `ReachableReader.row` and `MacOSFindingsReader.answer` — the
    /// same functions the real check calls. Only the *facts* are invented. A demo that hand-wrote
    /// the finished sentences would photograph a screen whose wording the app is no longer capable
    /// of producing, which is the failure the whole harness exists to avoid from the other side.
    static func security(_ machine: DemoMachine) -> SecurityAnswer {
        switch machine {
        case .healthy:  healthySecurity
        case .problems: unwellSecurity
        }
    }

    // MARK: Security — a healthy Mac

    /// Six rows, all clean, and the window stated.
    ///
    /// ⚠️ **This is the case the product exists to be able to show**, and the one worth reading
    /// hardest: nothing is amber, nothing is red, and the summary still says what was looked at and
    /// how far back. Lockdown Mode reports as "this Mac does not report it" here because that is
    /// true on every Mac ever made — there is no readable state for it anywhere — and a demo that
    /// quietly showed it as On would be teaching a screen the app cannot draw.
    private static let healthySecurity: SecurityAnswer = {
        let block = ProtectionsBlock(
            protections: [
                Protection(kind: .fileVault, state: .on, detail: "the disk is locked"),
                Protection(kind: .systemProtection, state: .on,
                           detail: "every protected part of macOS"),
                Protection(kind: .gatekeeper, state: .on,
                           detail: "apps are checked before they run"),
                Protection(kind: .secureBoot, state: .on, detail: "Full Security"),
                Protection(kind: .firewall, state: .on,
                           detail: "limiting connections, with stealth mode on"),
                Protection(kind: .automaticSecurityUpdates, state: .on,
                           detail: "security fixes and system files both"),
                Protection(kind: .automaticLogin, state: .off,
                           detail: "a password is asked for at startup"),
                // Not a guess and not an omission: no reading anywhere on macOS reports it.
                Protection(kind: .lockdownMode, state: .unreadable(.notReported)),
            ],
            xprotectVersion: "5361",
            xprotectUpdated: daysAgo(6))

        let protections = ProtectionReader.row(
            block: block,
            details: [
                DetailPair("Allowed to accept connections", "14 apps"),
                DetailPair("XProtect Remediator", "Version 161"),
                // ⚠️ No recovery-key sentence here. It belongs to a Mac whose disk is NOT
                // encrypted — it is the warning that turning FileVault on creates a key you can
                // lose. Repeating it on a Mac that is already encrypted is advice about a decision
                // already made, and it is the one piece of advice in this app that can cost
                // somebody every file they own.
            ],
            notes: [],
            managedSentence: nil)

        let grants = GrantReader.tidy(healthyGrants)
        let watch = GrantReader.row(grants: grants,
                                    unplaceable: ["com.example.sync.helper"],
                                    systemServicesUsingLocation: 3)

        let startup = StartupReader.row(from: healthyStartup)
        let extensions = BrowserExtensionReader.row(from: healthyExtensions)

        let reachable = ReachableReader.row(from: ReachableReader.Survey(
            sockets: [
                // Bonjour and the printing system: macOS's own, on every Mac, and proof of no
                // sharing service at all.
                ReachableReader.Socket(port: 5353, address: "*", isUDP: true),
                ReachableReader.Socket(port: 631, address: "127.0.0.1", isUDP: false),
            ],
            guestLoginEnabled: false,
            sharedFolders: []))

        let found = MacOSFindingsReader.answer(
            from: MacOSFindingsReader.Survey(
                results: [
                    MacOSFindingsReader.ScanResult(scanner: "Adload", at: minutesAgo(95),
                                                   outcome: .clean,
                                                   statusMessage: "NoThreatDetected",
                                                   statusCode: 0),
                    MacOSFindingsReader.ScanResult(scanner: "BlueTop", at: minutesAgo(96),
                                                   outcome: .clean,
                                                   statusMessage: "NoThreatDetected",
                                                   statusCode: 0),
                    MacOSFindingsReader.ScanResult(scanner: "Pirrit", at: minutesAgo(97),
                                                   outcome: .clean,
                                                   statusMessage: "NoThreatDetected",
                                                   statusCode: 0),
                    // ⚠️ The ordinary case, on purpose. About twenty of these run when the Mac is
                    // idle and one being stopped mid-flight is what a normal Tuesday looks like.
                    // A demo with a perfect twenty would teach that anything else is a fault.
                    MacOSFindingsReader.ScanResult(scanner: "KeySteal", at: minutesAgo(98),
                                                   outcome: .didNotFinish,
                                                   statusMessage: "PluginCanceled",
                                                   statusCode: 4),
                ],
                earliestRecord: daysAgo(12),
                lastActivity: minutesAgo(95),
                isAdministrator: true),
            now: launched)

        return SecurityAnswer(
            report: SecurityReport(block: block,
                                   rows: [protections, watch, startup, extensions,
                                          reachable, found.row],
                                   ranAt: minutesAgo(11),
                                   measuredDays: found.measuredDays),
            grants: grants,
            unplaceable: ["com.example.sync.helper"],
            systemServicesUsingLocation: 3)
    }()

    /// What a working Mac's permission list actually looks like: a handful of apps that need what
    /// they hold, and Wellkept itself, which holds Full Disk Access and says so.
    private static let healthyGrants: [Grant] = [
        Grant(appName: "Zoom", bundleID: "us.zoom.xos", permission: .camera,
              signature: .matches, grantedAt: daysAgo(240)),
        Grant(appName: "Zoom", bundleID: "us.zoom.xos", permission: .microphone,
              signature: .matches, grantedAt: daysAgo(240)),
        Grant(appName: "Sample Meetings", bundleID: "com.example.meetings", permission: .camera,
              signature: .matches, grantedAt: daysAgo(88)),
        Grant(appName: "Sample Meetings", bundleID: "com.example.meetings", permission: .screenRecording,
              signature: .matches, grantedAt: daysAgo(88)),
        Grant(appName: "Rectangle", bundleID: "com.knollsoft.Rectangle", permission: .accessibility,
              signature: .matches, grantedAt: daysAgo(410)),
        Grant(appName: "Wellkept", bundleID: "studio.stonemesa.wellkept", permission: .fullDiskAccess,
              signature: .matches, grantedAt: daysAgo(3), isWellkept: true),
        Grant(appName: "Sample Weather", bundleID: "com.example.weather", permission: .location,
              signature: .matches),
    ]

    private static let healthyStartup = StartupReader.Survey(
        items: [
            StartupReader.Item(label: "com.example.backups.agent",
                               name: "Sample Backups",
                               developer: "Example Software",
                               program: "/Applications/Sample Backups.app",
                               origin: .userAgent,
                               trigger: .onASchedule("every day at 2:30 AM"),
                               disabled: false,
                               file: "~/Library/LaunchAgents/com.example.backups.agent.plist"),
            StartupReader.Item(label: "com.example.sync",
                               name: "Sample Sync",
                               developer: "Example Software",
                               program: "/Applications/Sample Sync.app",
                               origin: .userAgent,
                               trigger: .atLogin,
                               disabled: false,
                               file: "~/Library/LaunchAgents/com.example.sync.plist"),
            StartupReader.Item(label: "com.example.printer.daemon",
                               name: "Sample Printer Helper",
                               developer: "Example Peripherals",
                               program: "/Library/PrivilegedHelperTools/com.example.printer",
                               origin: .globalDaemon,
                               trigger: .whenSomethingAsksForIt,
                               disabled: false,
                               file: "/Library/LaunchDaemons/com.example.printer.daemon.plist"),
        ],
        carriedInsideApps: [
            StartupReader.Item(label: "com.example.chat.helper",
                               name: "Sample Chat",
                               developer: "Example Software",
                               program: "/Applications/Sample Chat.app",
                               origin: .appBundled,
                               trigger: .atLogin,
                               disabled: false,
                               file: "/Applications/Sample Chat.app"),
        ],
        // ⚠️ The rule that defines this row. Two 181-byte files whose whole body is an empty
        // dictionary: they start nothing, they are reported as leftovers, and they are NOT counted.
        // A tool that counts files says "Example runs 2 things at login" when nothing runs, and
        // that is exactly the scare other cleaners sell.
        leftovers: [
            StartupReader.Leftover(file: "~/Library/LaunchAgents/com.example.updater.agent.plist",
                                   why: "The file names no program, so it starts nothing."),
            StartupReader.Leftover(file: "~/Library/LaunchAgents/com.example.updater.xpc.plist",
                                   why: "The file names no program, so it starts nothing."),
        ],
        filesRead: 5,
        foldersSearched: ["~/Library/LaunchAgents", "/Library/LaunchAgents", "/Library/LaunchDaemons"])

    private static let healthyExtensions = BrowserExtensionReader.Survey(
        extensions: [
            BrowserExtensionReader.Extension(
                name: "Sample Blocker",
                identifier: "com.example.blocker.extension",
                browser: .safari,
                publisher: "Example Software",
                version: "5.2",
                reach: .everySite,
                enabled: nil),
            BrowserExtensionReader.Extension(
                name: "Sample Passwords",
                identifier: "aaaabbbbccccddddeeeeffffgggghhhh",
                browser: .chrome,
                publisher: nil,
                version: "3.1.4",
                reach: .everySite,
                enabled: true),
            BrowserExtensionReader.Extension(
                name: "Sample Reader",
                identifier: "iiiijjjjkkkkllllmmmmnnnnoooopppp",
                browser: .chrome,
                publisher: nil,
                version: "1.9",
                reach: .onlyWhenYouClickIt,
                enabled: true),
        ],
        browsersSearched: [.safari, .chrome],
        // Counted, never listed. Chrome ships eight of its own and Firefox five; a tool that counts
        // them says eighteen extensions on a Mac where somebody installed three.
        shippedWithBrowser: 13,
        profilesRead: 2)

    // MARK: Security — a Mac with problems

    /// The paths nobody will otherwise see: FileVault off, the firewall off, a permission held by
    /// an app that is gone, an app whose signature no longer matches what was approved, and a real
    /// XProtect Remediator finding.
    ///
    /// ⚠️ **Still amber, never red.** All nine of Security's conditions are `.attention` by
    /// construction — see `SecurityConcern` — so this is the most alarming this section is capable
    /// of being, and that is deliberate. Every one of these is something a person may have chosen
    /// on purpose.
    private static let unwellSecurity: SecurityAnswer = {
        let block = ProtectionsBlock(
            protections: [
                Protection(kind: .fileVault, state: .off, detail: "the disk is not locked",
                           settingsPane: SystemSettingsPane.fileVault.rawValue),
                Protection(kind: .systemProtection, state: .on,
                           detail: "every protected part of macOS"),
                Protection(kind: .gatekeeper, state: .on,
                           detail: "apps are checked before they run"),
                Protection(kind: .secureBoot, state: .on, detail: "Full Security"),
                Protection(kind: .firewall, state: .off,
                           detail: "no connection is being filtered",
                           settingsPane: SystemSettingsPane.firewall.rawValue),
                Protection(kind: .automaticSecurityUpdates, state: .on,
                           detail: "security fixes and system files both"),
                Protection(kind: .automaticLogin, state: .off,
                           detail: "a password is asked for at startup"),
                Protection(kind: .lockdownMode, state: .unreadable(.notReported)),
            ],
            xprotectVersion: "5361",
            xprotectUpdated: daysAgo(9))

        let protections = ProtectionReader.row(
            block: block,
            details: [
                DetailPair("Allowed to accept connections", "Not filtered — the firewall is off"),
                DetailPair("XProtect Remediator", "Version 161"),
            ],
            // The one piece of advice in this app that can cost somebody every file they own. It
            // comes from the reader's own constant rather than being retyped, so the demo cannot
            // photograph a sentence the app no longer says.
            notes: [ProtectionReader.recoveryKeySentence],
            managedSentence: nil)

        let grants = GrantReader.tidy(unwellGrants)
        let watch = GrantReader.row(grants: grants,
                                    unplaceable: ["com.example.old.helper"],
                                    systemServicesUsingLocation: 3)

        let startup = StartupReader.row(from: unwellStartup)
        let extensions = BrowserExtensionReader.row(from: unwellExtensions)

        let reachable = ReachableReader.row(from: ReachableReader.Survey(
            sockets: [
                ReachableReader.Socket(port: 5900, address: "*", isUDP: false),
                ReachableReader.Socket(port: 22, address: "*", isUDP: false),
                ReachableReader.Socket(port: 5353, address: "*", isUDP: true),
            ],
            guestLoginEnabled: true,
            sharedFolders: [
                ReachableReader.SharedFolder(name: "Public Folder",
                                             path: "~/Public",
                                             guestAccess: true),
            ]))

        let found = MacOSFindingsReader.answer(
            from: MacOSFindingsReader.Survey(
                results: [
                    // ⚠️ The row nobody will otherwise see. macOS found it and removed it at the
                    // time — before Wellkept looked — which is why the copy calls it a record of
                    // something already handled rather than a thing to act on.
                    MacOSFindingsReader.ScanResult(scanner: "Adload", at: daysAgo(4),
                                                   outcome: .dealtWith,
                                                   statusMessage: "ThreatRemediated",
                                                   statusCode: 2),
                    MacOSFindingsReader.ScanResult(scanner: "Pirrit", at: minutesAgo(140),
                                                   outcome: .clean,
                                                   statusMessage: "NoThreatDetected",
                                                   statusCode: 0),
                    MacOSFindingsReader.ScanResult(scanner: "BlueTop", at: minutesAgo(141),
                                                   outcome: .didNotFinish,
                                                   statusMessage: "PluginCanceled",
                                                   statusCode: 4),
                ],
                earliestRecord: daysAgo(9),
                lastActivity: minutesAgo(140),
                isAdministrator: true),
            now: launched)

        return SecurityAnswer(
            report: SecurityReport(block: block,
                                   rows: [protections, watch, startup, extensions,
                                          reachable, found.row],
                                   ranAt: minutesAgo(11),
                                   measuredDays: found.measuredDays),
            grants: grants,
            unplaceable: ["com.example.old.helper"],
            systemServicesUsingLocation: 3)
    }()

    /// Two of the nine conditions live in here, and nothing else on the list is a fault.
    ///
    /// - **Loom is gone and its screen-recording permission is not.** Anything later installed
    ///   under that identity starts with the permission already granted.
    /// - **CleanShot X no longer signs as the app the permission was given to.** That is a
    ///   statement about the signature, never an accusation about the software.
    private static let unwellGrants: [Grant] = [
        Grant(appName: "Zoom", bundleID: "us.zoom.xos", permission: .camera,
              signature: .matches, grantedAt: daysAgo(700)),
        Grant(appName: "Zoom", bundleID: "us.zoom.xos", permission: .microphone,
              signature: .matches, grantedAt: daysAgo(700)),
        Grant(appName: "CleanShot X", bundleID: "com.example.cleanshot",
              permission: .screenRecording,
              stillInstalled: true, signature: .changed, grantedAt: daysAgo(520)),
        Grant(appName: "Loom", bundleID: "com.example.loom", permission: .screenRecording,
              stillInstalled: false, signature: .unknown, grantedAt: daysAgo(880)),
        Grant(appName: "Sample Remote", bundleID: "com.example.remote", permission: .accessibility,
              signature: .matches, grantedAt: daysAgo(300)),
        Grant(appName: "Wellkept", bundleID: "studio.stonemesa.wellkept", permission: .fullDiskAccess,
              signature: .matches, grantedAt: daysAgo(1), isWellkept: true),
    ]

    private static let unwellStartup = StartupReader.Survey(
        items: [
            StartupReader.Item(label: "com.example.updater.agent",
                               name: "Sample Updater",
                               developer: "Example Software",
                               program: "/Library/Application Support/Example/Updater",
                               origin: .globalAgent,
                               trigger: .keptRunning,
                               disabled: false,
                               file: "/Library/LaunchAgents/com.example.updater.agent.plist"),
            StartupReader.Item(label: "com.example.remote.daemon",
                               name: "Sample Remote Helper",
                               // ⚠️ `nil` means UNRECOGNISED, and the word for it is never
                               // "suspicious". Plenty of good software is unsigned; saying more
                               // than we know is how a health check turns into an accusation.
                               developer: nil,
                               program: "/usr/local/bin/example-remote",
                               origin: .globalDaemon,
                               trigger: .atStartup,
                               disabled: false,
                               file: "/Library/LaunchDaemons/com.example.remote.daemon.plist"),
            StartupReader.Item(label: "com.example.telemetry",
                               name: "Sample Telemetry",
                               developer: "Example Analytics",
                               program: "/Library/Application Support/Example/telemetry",
                               origin: .globalDaemon,
                               trigger: .onASchedule("every 6 hours"),
                               disabled: false,
                               file: "/Library/LaunchDaemons/com.example.telemetry.plist"),
            StartupReader.Item(label: "com.example.old.launcher",
                               name: "Sample Legacy Launcher",
                               developer: nil,
                               program: "/Applications/Sample Legacy.app",
                               origin: .userAgent,
                               trigger: .atLogin,
                               disabled: true,
                               file: "~/Library/LaunchAgents/com.example.old.launcher.plist"),
        ],
        carriedInsideApps: [],
        leftovers: [
            StartupReader.Leftover(file: "/Library/LaunchDaemons/com.example.gone.plist",
                                   why: "The program it names is not on this Mac any more."),
        ],
        filesRead: 5,
        foldersSearched: ["~/Library/LaunchAgents", "/Library/LaunchAgents", "/Library/LaunchDaemons"])

    /// Three extensions that can read every page — and the wording never accuses them, because
    /// reading every page is exactly what a password manager, a content blocker or an assistant
    /// needs in order to work at all. None of the nine conditions covers it, so this row cannot go
    /// amber however alarming the list looks.
    private static let unwellExtensions = BrowserExtensionReader.Survey(
        extensions: [
            BrowserExtensionReader.Extension(
                name: "Sample Coupons",
                identifier: "qqqqrrrrssssttttuuuuvvvvwwwwxxxx",
                browser: .chrome,
                publisher: nil,
                version: "12.0.3",
                reach: .everySite,
                enabled: true),
            BrowserExtensionReader.Extension(
                name: "Sample Passwords",
                identifier: "aaaabbbbccccddddeeeeffffgggghhhh",
                browser: .chrome,
                publisher: nil,
                version: "3.1.4",
                reach: .everySite,
                enabled: true),
            BrowserExtensionReader.Extension(
                name: "Sample Assistant",
                identifier: "yyyyzzzz0000111122223333444455556",
                browser: .chrome,
                publisher: nil,
                version: "0.9.2",
                reach: .everySite,
                enabled: true),
            BrowserExtensionReader.Extension(
                name: "Sample Blocker",
                identifier: "com.example.blocker.extension",
                browser: .safari,
                publisher: "Example Software",
                version: "5.2",
                reach: .namedSites(["example.com", "example.org"]),
                // Safari will not say which of its extensions are switched on. `nil` is that, and
                // it is never read as off.
                enabled: nil),
        ],
        browsersSearched: [.safari, .chrome],
        shippedWithBrowser: 13,
        profilesRead: 2)

    // MARK: Backup

    private static let backup: [Finding] = [
        Finding(section: .backup,
                title: "Time Machine last finished 23 days ago",
                reason: "The backup disk “Archive” has not been plugged in since 3 August. Anything written since then exists only on this Mac.",
                severity: .problem,
                measure: "23 days ago",
                verb: "Open Time Machine"),
        Finding(section: .backup,
                title: "214 GB in iCloud Drive is not in any backup",
                reason: "iCloud is sync, not backup: a file deleted here is deleted everywhere, and a Time Machine copy of a file that was never downloaded is a placeholder.",
                severity: .attention,
                measure: "214 GB"),
        Finding(section: .backup,
                title: "The Photos library is covered",
                reason: "312 GB, inside the Time Machine disk’s last complete backup — the one from 3 August.",
                severity: .information,
                measure: "312 GB"),
        Finding(section: .backup,
                title: "There is no copy off this Mac other than the Archive disk",
                reason: "One disk, kept in the same room as the Mac. A fire or a theft takes both.",
                severity: .information),
    ]

    // MARK: Changes

    private static let changes: [Finding] = [
        Finding(section: .changes,
                title: "The firewall was turned off",
                reason: "On 22 August, four days ago. Wellkept records that it changed; it cannot tell you who changed it or why.",
                severity: .information,
                measure: "4 days ago"),
        Finding(section: .changes,
                title: "Remote Login (SSH) was turned on",
                reason: "On 19 August, during the Docker Desktop update that ran the same afternoon.",
                severity: .information,
                measure: "7 days ago"),
        Finding(section: .changes,
                title: "Docker Desktop was added to your login items",
                reason: "On 19 August. It did not ask.",
                severity: .information,
                measure: "7 days ago"),
        Finding(section: .changes,
                title: "Two settings were compared and had not moved",
                reason: "FileVault and automatic macOS updates are where they were on 12 August.",
                severity: .information),
    ]
}

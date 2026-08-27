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

        for section in SectionID.checkable where section != .hardware && section != .security {
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
        let others = storage + apps + backup + changes
        let kept = machine == .healthy ? others.filter { $0.severity < .attention } : others
        return [hardware(machine).overviewFinding, security(machine).report.overviewFinding]
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

    // MARK: Apps

    private static let apps: [Finding] = [
        Finding(section: .apps,
                title: "Zoom is six versions behind",
                reason: "6.0.10 is installed. The vendor lists two security fixes since, one of them in the screen-sharing code.",
                severity: .attention,
                measure: "6.0.10 → 6.5.7",
                verb: "Open vendor page"),
        Finding(section: .apps,
                title: "Adobe Acrobat starts a background updater at login",
                reason: "AdobeARMservice runs whether or not Acrobat is open, and was not asked for separately.",
                severity: .information,
                verb: "Open Login Items"),
        Finding(section: .apps,
                title: "Docker Desktop has a newer version",
                reason: "4.29.0 installed, 4.41.2 released 11 days ago. No security note attached to it.",
                severity: .information,
                measure: "4.29.0 → 4.41.2",
                verb: "Open vendor page"),
        Finding(section: .apps,
                title: "Four apps are Intel-only",
                reason: "Audacity, Kindle, Silverlight and TextWrangler run under Rosetta on this Mac. They work; they are slower and none of them is being updated.",
                severity: .information,
                measure: "4 apps"),
        Finding(section: .apps,
                title: "112 apps, 96 of them current",
                reason: "Twelve came from the App Store, ninety-four from vendor downloads, six from Homebrew.",
                severity: .information,
                measure: "112 apps"),
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

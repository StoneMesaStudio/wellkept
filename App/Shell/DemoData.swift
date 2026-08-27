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
//  For the other five sections the difference is a **filter, not a second set of inventions**: the
//  healthy Mac is the same list with everything at `.attention` or worse taken out. Two
//  hand-maintained copies of six sections' findings would disagree with each other inside a month.
//
//  ## Hardware is built out of the real row builders
//
//  The Hardware readings below are handed to `DriveReader.reading(for:)`, `BatteryReader.row(_:)`
//  and `HardwareReport.init` — the same functions the real check uses. Only the *facts* are
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
    /// A drive declaring failure, a failed battery, panics, and memory pressure.
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
            "A failing drive, a failed battery, kernel panics and a Mac running out of memory."
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

        for section in SectionID.checkable where section != .hardware {
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
    /// ⚠️ Hardware contributes **exactly one** row here, whatever it found — `overviewFinding`.
    /// A section that posts five rows to Overview has turned the summary into a second copy of
    /// itself, and the section a person should actually open gets lost among its own details.
    static func findings(_ machine: DemoMachine) -> [Finding] {
        let others = storage + apps + security + backup + changes
        let kept = machine == .healthy ? others.filter { $0.severity < .attention } : others
        return [hardware(machine).overviewFinding].compactMap { $0 } + kept
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
                measure: "None",
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
                measure: "None",
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

    private static let security: [Finding] = [
        Finding(section: .security,
                title: "The firewall is off",
                reason: "Anything on the same Wi-Fi can reach a service running on this Mac. Screen Sharing and Remote Login are both on, so there are two.",
                severity: .problem,
                verb: "Open Firewall settings"),
        Finding(section: .security,
                title: "Five apps can record the screen",
                reason: "Two of them — CleanShot X and an old Loom install — have not been opened in over a year.",
                severity: .information,
                measure: "5 apps",
                verb: "Open Screen Recording"),
        Finding(section: .security,
                title: "FileVault is on",
                reason: "The disk is encrypted, and the recovery key is held by Apple rather than written down here.",
                severity: .information),
        Finding(section: .security,
                title: "macOS has found nothing",
                reason: "XProtect signatures are 4 days old. No malware removal has run on this Mac.",
                severity: .information,
                measure: "v5286"),
        Finding(section: .security,
                title: "Gatekeeper is on, and one app is exempt",
                reason: "An old build of HandBrake was allowed through by hand in 2023. That exemption is still in place.",
                severity: .information,
                verb: "Reveal in Finder"),
    ]

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

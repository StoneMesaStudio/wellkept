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
//  Asked on 2026-08-27, which machine the demo should be: *"I would give them both. The goal is
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

        let ownRecord: Set<SectionID> = [.hardware, .security, .apps, .storage, .changes, .backup]
        for section in SectionID.checkable where !ownRecord.contains(section) {
            let mine = found.filter { $0.section == section }
            out[section] = CheckRecord(
                section: section,
                ranAt: minutesAgo(ranMinutesAgo[section] ?? 12),
                status: mine.contains(where: { $0.severity >= .attention }) ? .needsAttention : .good,
                complete: true)
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

        // Storage's line, for the same reason — and it is the one that carries `complete: false`.
        // On the unwell Mac 54 folders could not be read, so `StorageReport.complete` is false and
        // Overview may not report a healthy Mac on the strength of that look. It comes out of the
        // report rather than being asserted here, which is what makes the branch a real one.
        out[.storage] = storage(machine).report.record

        // Changes' line, for the same reason — and it is the one that can say "Not checked" on a
        // Mac where nothing is wrong at all, because the very first look has nothing to compare
        // against and "nothing changed" would be a lie on that run.
        out[.changes] = changes(machine).record

        // Backup's line, for the same reason. On the unwell Mac it is the one that says
        // "Needs attention" because the backups are switched off — a fact read from Time Machine's
        // own settings with nothing granted, which is why this section leads with it.
        out[.backup] = backup(machine).report.record

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

    /// ⚠️ **Every checkable section now builds its own record from its own report**, so this table
    /// is the fallback for a section that does not yet — and there are none. It is kept rather than
    /// deleted because it is what a seventh section would reach for on the day it is added, and
    /// because deleting it would make `records()` stop compiling for the next person who adds one.
    private static let ranMinutesAgo: [SectionID: Int] = [
        .hardware: 14, .storage: 13, .apps: 11, .security: 11,
    ]

    // MARK: - What it "found"

    /// Every row demo mode shows, for one machine.
    ///
    /// ⚠️ Hardware and Security each contribute **exactly one** row here, whatever they found —
    /// their `overviewFinding`. A section that posts five rows to Overview has turned the summary
    /// into a second copy of itself, and the section a person should actually open gets lost among
    /// its own details.
    static func findings(_ machine: DemoMachine) -> [Finding] {
        // ⚠️ Apps contributes exactly one row, `.information`, on both Macs — and it is **not**
        // filtered out of the healthy one, because `.information` is what it always is. Apps cannot
        // turn Overview amber this round: without vulnerability data a version behind is not
        // something wrong, so the row is there for the audit trail and never in "what needs you".
        // ⚠️ Storage contributes **at most one** row, and only ever about how full the disk is —
        // never about how large somebody's folders are. `StorageReport.overviewFinding` is `nil` on
        // the healthy Mac, which is the whole point: revealing a person's own files is not a thing
        // that needs them.
        // ⚠️ Changes contributes **at most one** row, and none at all on a first look or a quiet
        // one — the audit trail already says both, and a row reporting that nothing changed is a
        // row somebody has to read to learn nothing.
        // ⚠️ Backup contributes **at most one** row, and it is about whether the person's files are
        // backed up — never about where their files happen to live. On the healthy Mac
        // `BackupReport.overviewFinding` is `nil`; on the unwell one it is the backup that has been
        // switched off for nearly four weeks with nobody told.
        return [hardware(machine).overviewFinding,
                security(machine).report.overviewFinding,
                apps(machine).report.overviewFinding,
                storage(machine).report.overviewFinding,
                backup(machine).report.overviewFinding,
                changes(machine).overviewFinding]
            .compactMap { $0 }
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

    // MARK: - Storage

    /// The whole Storage answer for one machine, built once so its `Finding` keeps a stable `id`.
    ///
    /// ⚠️ Computed once and cached, not rebuilt per call. `StorageReport` mints a fresh `UUID` for
    /// its Overview row, and a `Finding` with a new identity on every draw is how a list animates
    /// itself to pieces.
    ///
    /// ## ⚠️ Built out of the real row builders, exactly as Hardware, Security and Apps are
    ///
    /// Every row comes from `StorageScan.assemble` — the same pure function the real scan ends in —
    /// and from `JunkSweep.row`, `BigFiles.row`, `Duplicates.row` and `StorageScan.setAsideRow`
    /// inside it. Only the *facts* are invented.
    ///
    /// **Neither Mac shows anything the real readers could not produce.** Three specific things
    /// make that true rather than merely intended:
    ///
    /// - Every second figure is `SnapshotStanding.recoverable(onDisk:modifiedOn:)` — the four lines
    ///   of arithmetic the disk gets — so the rows of zeroes on the unwell Mac are a consequence of
    ///   its stuck snapshot rather than something typed in.
    /// - Every machine-junk reason is `JunkClassifier.Category.reason`, which is the sentence that
    ///   names the program that writes the thing again. Nothing here invents grounds for a tick.
    /// - No `Origin` is set by hand. It comes from `JunkClassifier.Category.origin`, or it is the
    ///   `.yours` default — which is why the four biggest things on the unwell Mac have no ticks.
    static func storage(_ machine: DemoMachine) -> StorageAnswer {
        switch machine {
        case .healthy:  healthyStorage
        case .problems: unwellStorage
        }
    }

    // MARK: One invented thing on a disk

    /// An identity that is stable per path and belongs to no real file.
    ///
    /// The inode comes from the path rather than a counter, so two calls describing the same
    /// invented file agree — `Item.id` is `<device>#<inode>`, and a list whose ids move between
    /// draws animates itself to pieces.
    private static func madeUpIdentity(_ path: String) -> ItemIdentity {
        var hash: UInt64 = 1_469_598_103
        for byte in path.utf8 { hash = (hash &* 1_099_511) ^ UInt64(byte) }
        return ItemIdentity(volumeUUID: "00000000-0000-0000-0000-00000DE30DA7",
                            volumeDevice: "/dev/disk-demo",
                            inode: hash % 8_000_000 + 1_000)
    }

    /// An aggregate's two numbers, using only the arithmetic the real scan can do.
    ///
    /// A folder total is the sum of its files' own answers: the ones written after the oldest
    /// snapshot come back whole, the ones written before it come back not at all. Expressed here as
    /// exactly that sum, so there is no figure on either demo Mac that a disk could not produce.
    private static func measured(_ onDisk: Int64, comesBack: Int64) -> Bytes {
        let back = min(max(0, comesBack), max(0, onDisk))
        return Bytes.allOfIt(SizeOnDisk(back))
             + Bytes.heldBackBySnapshot(SizeOnDisk(max(0, onDisk) - back))
    }

    /// One invented file or folder.
    ///
    /// ⚠️ `origin` defaults to `.yours` here exactly as it does on `Item` itself, so a row added to
    /// this file in a hurry is a row nobody may pre-tick and nobody may sweep.
    ///
    /// ⚠️ The second figure is **not** an argument. It is computed from the snapshot standing and
    /// the file's own date, which is the whole point of the two-number design: on the unwell Mac
    /// anything older than 4 August returns nothing, and that falls out rather than being typed.
    private static func thing(_ path: String,
                              onDisk: Int64,
                              kind: ItemKind = .file,
                              origin: Origin = .yours,
                              cloud: CloudStanding = .onThisMac,
                              handling: Handling = .notCheckedYet,
                              changedDaysAgo: Int,
                              openedDaysAgo: Int? = nil,
                              under snapshots: SnapshotStanding,
                              reason: String) -> Item {
        let changed = daysAgo(changedDaysAgo)
        return Item(identity: madeUpIdentity(path),
                    path: path,
                    bytes: snapshots.bytes(onDisk: SizeOnDisk(onDisk), modifiedOn: changed),
                    kind: kind,
                    origin: origin,
                    cloudStanding: cloud,
                    handling: handling,
                    modifiedOn: changed,
                    lastOpenedOn: openedDaysAgo.map(daysAgo),
                    reason: reason)
    }

    /// One piece of invented machine junk, in a category, with the classifier's own words.
    ///
    /// ⚠️ The reason is `JunkClassifier.Category.reason`, never typed here. That string is what
    /// makes a tick defensible — it names the program that writes the thing again — and a demo that
    /// wrote its own version would photograph a sentence the app cannot produce.
    private static func junk(_ path: String,
                             _ category: JunkClassifier.Category,
                             onDisk: Int64,
                             changedDaysAgo: Int = 3,
                             kind: ItemKind = .folder,
                             ticked: Bool = true,
                             notTickedBecause: String? = nil,
                             under snapshots: SnapshotStanding) -> JunkClassifier.Classified {
        let movable = category.mayBeTicked
        let item = thing(path,
                         onDisk: onDisk,
                         kind: kind,
                         origin: category.origin,
                         handling: movable
                            ? .notCheckedYet
                            : .cannot(JunkClassifier.whyARuntimeHasNoButton),
                         changedDaysAgo: changedDaysAgo,
                         under: snapshots,
                         reason: movable
                            ? category.reason
                            : "\(category.whatItIs) \(JunkClassifier.whyARuntimeHasNoButton)")
        let verdict: JunkClassifier.Verdict = movable
            ? .junk(category)
            : .nothingCanMoveIt(category, why: JunkClassifier.whyARuntimeHasNoButton)
        return JunkClassifier.Classified(
            item: item,
            judgement: JunkClassifier.Judgement(
                verdict: verdict,
                // ⭐ The same intersection the real classifier performs: what it decided, and what
                // `Item` itself permits. Nothing here can tick something of the person's own.
                arrivesTicked: movable && ticked && item.mayBePreSelected,
                notTickedBecause: notTickedBecause))
    }

    /// A `BigFiles.Answer` whose row is the one the real builder writes.
    private static func bigFiles(items: [Item],
                                 places: [BigFiles.Place],
                                 total: Bytes,
                                 filesSeen: Int,
                                 cloud: CloudHolding,
                                 refused: UnreadablePlaces) -> BigFiles.Answer {
        BigFiles.Answer(items: items, places: places, total: total, filesSeen: filesSeen,
                        cloudHolding: cloud, refused: refused,
                        row: BigFiles.row(items: items, places: places, total: total,
                                          filesSeen: filesSeen, cloudHolding: cloud,
                                          refused: refused))
    }

    /// A `Duplicates.Answer` whose row is the one the real builder writes.
    private static func duplicates(groups: [Duplicates.Group],
                                   insideProjects: Int,
                                   sharedBlocks: Int,
                                   hardLinksFolded: Int,
                                   filesCompared: Int,
                                   bytesRead: Int64,
                                   stoppedEarly: Bool) -> Duplicates.Answer {
        let tidiness = Bytes.sum(groups.map(\.extra))
        let calls = groups.reduce(0) { $0 + $1.judgementCalls }
        return Duplicates.Answer(groups: groups,
                                 tidiness: tidiness,
                                 judgementCalls: calls,
                                 insideProjects: insideProjects,
                                 sharedBlocks: sharedBlocks,
                                 hardLinksFolded: hardLinksFolded,
                                 filesCompared: filesCompared,
                                 bytesRead: bytesRead,
                                 stoppedEarly: stoppedEarly,
                                 refused: .sawEverything,
                                 row: Duplicates.row(groups: groups,
                                                     tidiness: tidiness,
                                                     judgementCalls: calls,
                                                     insideProjects: insideProjects,
                                                     sharedBlocks: sharedBlocks,
                                                     hardLinksFolded: hardLinksFolded,
                                                     stoppedEarly: stoppedEarly,
                                                     refused: .sawEverything))
    }

    // MARK: Storage — a healthy Mac

    /// **Modest junk, a couple of big files, nothing alarming.**
    ///
    /// The disk is comfortable, so `StorageReport.overviewFinding` is `nil` and Storage contributes
    /// nothing at all to "what needs you". That is correct, and it is the case the product exists to
    /// be able to show: a person opens Storage, sees where their room went, and there is nothing to
    /// do about any of it.
    ///
    /// The snapshot here is two days old and doing its job rather than being stuck, so most of what
    /// is offered really would come back — which is what makes the unwell Mac's rows of zeroes
    /// legible as the exception they are.
    private static let healthyStorage: StorageAnswer = {
        let snapshots = SnapshotStanding(snapshots: [
            LocalSnapshot(name: "com.apple.TimeMachine.2026-08-26-030114.local", takenOn: daysAgo(2)),
        ])

        let found = JunkSweep.Found(
            junk: [
                junk("/Users/sample/Library/Developer/Xcode/DerivedData",
                     .xcodeBuildOutput, onDisk: 8_400_000_000, changedDaysAgo: 0,
                     under: snapshots),
                junk("/Users/sample/Library/Caches/Firefox/Profiles/default/cache2/entries",
                     .contentAddressedCache, onDisk: 642_000_000, changedDaysAgo: 0,
                     under: snapshots),
            ],
            refused: .sawEverything,
            considered: 4_186)

        let mine = [
            thing("/Users/sample/Movies/Family Reunion 2025.mov",
                  onDisk: 6_240_000_000, changedDaysAgo: 140, openedDaysAgo: 61,
                  under: snapshots,
                  reason: BigFiles.Says.because(SizeOnDisk(6_240_000_000))),
            thing("/Users/sample/Documents/Thesis Archive.zip",
                  onDisk: 2_100_000_000, changedDaysAgo: 1, under: snapshots,
                  reason: BigFiles.Says.because(SizeOnDisk(2_100_000_000))),
        ]

        let big = bigFiles(
            items: mine,
            places: [
                BigFiles.Place(path: "/Users/sample/Movies", name: "Movies",
                               bytes: measured(41_300_000_000, comesBack: 12_100_000_000),
                               files: 214),
                BigFiles.Place(path: "/Users/sample/Library/Developer", name: "Library/Developer",
                               bytes: measured(22_800_000_000, comesBack: 21_400_000_000),
                               files: 96_431),
                BigFiles.Place(path: "/Users/sample/Documents", name: "Documents",
                               bytes: measured(9_600_000_000, comesBack: 1_200_000_000),
                               files: 3_882),
            ],
            total: measured(214_000_000_000, comesBack: 58_000_000_000),
            filesSeen: 412_006,
            cloud: CloudHolding(files: 1_204, apparentBytes: 9_400_000_000),
            refused: .sawEverything)

        return StorageScan.assemble(
            freeSpace: FreeSpacePicture(capacity: SizeOnDisk(494_384_795_648),
                                        actuallyFree: SizeOnDisk(268_100_000_000),
                                        finderShows: FinderFigure(281_600_000_000),
                                        snapshots: snapshots,
                                        volumeName: "this Mac's disk"),
            junk: found,
            big: big,
            dupes: duplicates(groups: [], insideProjects: 96, sharedBlocks: 14,
                              hardLinksFolded: 31, filesCompared: 2_144,
                              bytesRead: 640_000_000, stoppedEarly: false),
            summary: Quarantine.Summary(count: 0, bytes: 0, oldest: nil,
                                        readyCount: 0, unaccountedFor: 0, trouble: nil),
            snapshots: snapshots,
            now: minutesAgo(13))
    }()

    // MARK: Storage — a Mac with problems

    /// **A lot of junk, a stuck snapshot, duplicates we decline to offer, and runtimes we cannot
    /// touch.**
    ///
    /// Four things this Mac exercises that the healthy one cannot:
    ///
    /// 1. **The disk is nearly full** — 3.6% left — so `DiskPressure.nearlyFull` fires. It is the
    ///    one thing Storage may ever raise on Overview, and it raises it as a `.problem`.
    /// 2. **A local snapshot from 24 days ago is stuck**, so almost every figure's second number is
    ///    nothing at all. That column of zeroes is what the whole two-number design exists for, and
    ///    it is arithmetic here rather than assertion.
    /// 3. **1,204 duplicate sets are inside project folders and are not offered** — 94% of them, on
    ///    the real Mac this was measured on, where deleting one half of a pair breaks a build.
    /// 4. **11.6 GB of simulator runtimes are reported with no button**, because they are
    ///    root-owned read-only images and no thirty-day undo could exist for them.
    ///
    /// It is also the Mac where 54 folders could not be read — including the Trash and the Photos
    /// library, usually the two biggest wins — which is what makes its record `complete: false`.
    /// That is the one state Overview must never get wrong, and a branch nobody can see is a branch
    /// nobody checks.
    private static let unwellStorage: StorageAnswer = {
        let snapshots = SnapshotStanding(snapshots: [
            LocalSnapshot(name: "com.apple.TimeMachine.2026-08-04-062503.local", takenOn: daysAgo(24)),
        ])

        let found = JunkSweep.Found(
            junk: [
                junk("/Users/sample/Library/Developer/Xcode/DerivedData",
                     .xcodeBuildOutput, onDisk: 41_700_000_000, changedDaysAgo: 0,
                     under: snapshots),
                junk("/Users/sample/Library/Developer/CoreSimulator/Caches/dyld",
                     .contentAddressedCache, onDisk: 3_120_000_000, changedDaysAgo: 0,
                     under: snapshots),
                junk("/Users/sample/Library/Caches/Homebrew/downloads",
                     .contentAddressedCache, onDisk: 1_480_000_000, changedDaysAgo: 61,
                     under: snapshots),
                // ⚠️ The annoyance filter doing the one job it survives for: do not make me
                // download this again this week. It can only ever take a tick away.
                junk("/Users/sample/Downloads/Xcode_26.1.xip.download",
                     .halfFinishedDownload, onDisk: 1_240_000_000, changedDaysAgo: 4,
                     kind: .file, ticked: false,
                     notTickedBecause: JunkClassifier.usedThisMonth,
                     under: snapshots),
                // ⛔ Reported, never offered. No walk in this section can even reach these — they
                // mount as sealed read-only volumes, and the images behind them are root-owned.
                junk("/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime/iOS 26.0.dmg",
                     .simulatorRuntime, onDisk: 7_900_000_000, changedDaysAgo: 200,
                     kind: .diskImage, under: snapshots),
                junk("/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime/iOS 18.6.dmg",
                     .simulatorRuntime, onDisk: 3_700_000_000, changedDaysAgo: 320,
                     kind: .diskImage, under: snapshots),
            ],
            refused: .sawEverything,
            considered: 12_904)

        let mine = [
            thing("/Users/sample/Library/Application Support/MobileSync/Backup",
                  onDisk: 84_300_000_000, kind: .folder, changedDaysAgo: 380, under: snapshots,
                  reason: BigFiles.Says.because(SizeOnDisk(84_300_000_000))),
            // A place we will never offer to touch: sized, and the reason sits where a button would
            // have been.
            thing("/Users/sample/Pictures/Photos Library.photoslibrary",
                  onDisk: 61_800_000_000, kind: .bundle,
                  handling: .cannot(ScanPolicy.whyAPhotoLibraryIsNeverTouched),
                  changedDaysAgo: 2, under: snapshots,
                  reason: ScanPolicy.whyAPhotoLibraryIsNeverTouched),
            thing("/Users/sample/Documents/Virtual Machines/Docker.raw",
                  onDisk: 18_200_000_000, kind: .diskImage, changedDaysAgo: 40, under: snapshots,
                  reason: BigFiles.Says.because(SizeOnDisk(18_200_000_000))),
            // The one line lives on this row, because this one is genuinely synced.
            thing("/Users/sample/Library/Mobile Documents/com~apple~CloudDocs/Wedding Video.mov",
                  onDisk: 12_400_000_000, cloud: .bothPlaces,
                  changedDaysAgo: 210, openedDaysAgo: 190, under: snapshots,
                  reason: BigFiles.Says.because(SizeOnDisk(12_400_000_000))),
        ]

        let big = bigFiles(
            items: mine,
            places: [
                BigFiles.Place(path: "/Users/sample/Library", name: "Library",
                               bytes: measured(148_000_000_000, comesBack: 41_100_000_000),
                               files: 641_902),
                BigFiles.Place(path: "/Users/sample/Pictures", name: "Pictures",
                               bytes: measured(61_800_000_000, comesBack: 0),
                               files: 48_211),
                BigFiles.Place(path: "/Users/sample/Documents/Media", name: "Documents/Media",
                               // The measured pair from the worksheet: 14.8 GB on disk, 0.5 GB back.
                               bytes: measured(14_800_000_000, comesBack: 500_000_000),
                               files: 1_006),
            ],
            total: measured(302_000_000_000, comesBack: 22_400_000_000),
            filesSeen: 983_868,
            cloud: CloudHolding(files: 15_593, apparentBytes: 72_000_000_000),
            // ⚠️ Named rather than counted as empty. This is what makes this Mac incomplete.
            refused: UnreadablePlaces(count: 54,
                                      notable: ["your Trash", "your Photos library", "Mail",
                                                "Messages", "your Desktop"],
                                      why: .notPermitted))

        let copies = [
            thing("/Users/sample/Documents/Scans/Invoice 2024-11.pdf",
                  onDisk: 3_100_000, changedDaysAgo: 300, under: snapshots,
                  reason: Duplicates.Says.copyReason(of: 2)),
            thing("/Users/sample/Desktop/Invoice 2024-11 copy.pdf",
                  onDisk: 3_100_000, changedDaysAgo: 290, under: snapshots,
                  reason: Duplicates.Says.copyReason(of: 2)),
        ]

        return StorageScan.assemble(
            freeSpace: FreeSpacePicture(capacity: SizeOnDisk(494_384_795_648),
                                        actuallyFree: SizeOnDisk(17_900_000_000),
                                        finderShows: FinderFigure(96_400_000_000),
                                        snapshots: snapshots,
                                        volumeName: "this Mac's disk"),
            junk: found,
            big: big,
            dupes: duplicates(groups: [Duplicates.Group(copies: copies,
                                                        sharing: .separateCopies,
                                                        sharedNamesFolded: 0,
                                                        insideAProject: false)],
                              insideProjects: 1_204,
                              sharedBlocks: 96,
                              hardLinksFolded: 256,
                              filesCompared: 12_021,
                              bytesRead: 8_000_000_000,
                              stoppedEarly: true),
            summary: Quarantine.Summary(count: 3,
                                        bytes: 12_600_000_000,
                                        oldest: daysAgo(34),
                                        readyCount: 1,
                                        unaccountedFor: 0,
                                        trouble: nil),
            snapshots: snapshots,
            now: minutesAgo(13))
    }()


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

    // MARK: - Backup

    /// The whole Backup answer for one machine, built once so its `Finding` keeps a stable `id`.
    ///
    /// ⚠️ Computed once and cached, not rebuilt per call. `BackupReport` mints a fresh `UUID` for
    /// its Overview row, and a `Finding` with a new identity on every draw is how a list animates
    /// itself to pieces.
    ///
    /// ## ⚠️ Built out of the real readers, from the shape macOS actually writes
    ///
    /// The Time Machine half goes through `TimeMachineReader.Preferences.destination(from:)` — the
    /// same parser the real read uses, fed a dictionary with the same keys macOS puts in
    /// `com.apple.TimeMachine`: `LastKnownVolumeName`, `RESULT`, `SnapshotDates`,
    /// `ReferenceLocalSnapshotDate` and the rest. The row comes from `TimeMachineReader.row`, the
    /// verdict from `TimeMachineState`, the coverage rows from `CoverageReader.coverage(of:…)` and
    /// the page from `RecoveryPlan.make`. **Only the facts are invented.**
    ///
    /// ## ⭐ Neither Mac has a `Coverage` marked as a gap, and that is the section's whole argument
    ///
    /// `Coverage.isGap` is `true` only for something that lives **on this Mac and nowhere else** and
    /// is in no backup. Both demo Macs have a backup that has finished at least once, so
    /// `CoverageReader.included` answers `.yes` for every place — which is what the real reader
    /// would say, and saying anything else here would be inventing an alarm the app cannot produce.
    ///
    /// What the unwell Mac has instead is **72.2 GB in the cloud and not on this disk**, and that is
    /// deliberately *not* a gap: it is an arrangement working exactly as designed. A tool that
    /// counted it as missing would open with a 72 GB alarm about nothing. The unwell Mac's actual
    /// problem is on the row above it — Time Machine switched off, nobody told.
    static func backup(_ machine: DemoMachine) -> BackupAnswer {
        switch machine {
        case .healthy:  healthyBackup
        case .problems: unwellBackup
        }
    }

    // MARK: Backup — the shape of one invented destination

    /// A Time Machine destination, parsed by the real parser out of the keys macOS writes.
    private static func destinationRecord(name: String,
                                          successes: [Date],
                                          attempts: [Date],
                                          result: Int,
                                          bytesUsed: Int64,
                                          bytesAvailable: Int64,
                                          referenceSnapshot: Date?) -> TimeMachineReader.Preferences.Destination {
        TimeMachineReader.Preferences.destination(from: [
            "DestinationID": "6F3B1C0A-DEM0-4E2B-9A77-000000000001",
            "LastKnownVolumeName": name,
            "DestinationUUIDs": ["6F3B1C0A-DEM0-4E2B-9A77-000000000002"],
            "RESULT": NSNumber(value: result),
            "AttemptDates": attempts,
            "SnapshotDates": successes,
            "BytesUsed": NSNumber(value: bytesUsed),
            "BytesAvailable": NSNumber(value: bytesAvailable),
            "FilesystemTypeName": "apfs",
            "LastKnownEncryptionState": "Encrypted",
        ].merging(referenceSnapshot.map { ["ReferenceLocalSnapshotDate": $0] } ?? [:]) { a, _ in a })
    }

    /// The Time Machine half, through the real state, the real failure rule and the real row.
    private static func timeMachine(record: TimeMachineReader.Preferences.Destination,
                                    automaticBackupsOn: Bool,
                                    isConnected: Bool,
                                    volumePath: String?,
                                    capacity: Int64?,
                                    free: Int64?,
                                    snapshots: SnapshotStanding,
                                    now: Date) -> TimeMachineReader.Result {

        let prefs = TimeMachineReader.Preferences.Reading(
            answered: true,
            automaticBackupsOn: automaticBackupsOn,
            destinations: [record],
            lastDestinationID: record.id)

        let destination = BackupDestination(name: record.displayName,
                                            kind: record.kind,
                                            isConnected: isConnected,
                                            volumePath: volumePath,
                                            capacity: capacity.map(SizeOnDisk.init),
                                            free: free.map(SizeOnDisk.init))

        let state = TimeMachineState(
            isConfigured: true,
            automaticBackupsOn: automaticBackupsOn,
            destination: destination,
            lastSuccess: record.lastSuccess,
            // The real discard rule, not a hand-written verdict: a recorded result that a later
            // success has overtaken is about an older run and is thrown away.
            failure: TimeMachineReader.failure(for: record, isConnected: isConnected))

        let line = TimeMachineReader.snapshotSentence(snapshots: snapshots,
                                                      referencePoint: record.referenceSnapshot,
                                                      now: now)

        return TimeMachineReader.Result(
            state: state,
            row: TimeMachineReader.row(from: state, prefs: prefs, snapshots: snapshots,
                                       snapshotLine: line, now: now),
            snapshots: snapshots,
            referencePoint: record.referenceSnapshot,
            backupsRecorded: record.successes,
            snapshotLine: line)
    }

    /// The coverage half, through the real per-place builder.
    ///
    /// ⚠️ Every `Presence` is `.here(nil)`. The real reader `lstat`s and never opens anything, so it
    /// has no size to report — a demo that printed one would photograph a column the app cannot
    /// fill.
    private static func coverage(places: [CoverageReader.Place],
                                 iCloud: CoverageReader.ICloudAccount,
                                 timeMachine: TimeMachineState,
                                 cloudOnly: CoverageReader.CloudHolding,
                                 providers: [String],
                                 mirrored: Bool,
                                 fullDiskAccessHeld: Bool,
                                 now: Date) -> CoverageReader.Reading {

        var rows: [Coverage] = places.compactMap {
            CoverageReader.coverage(of: $0, presence: .here(nil), iCloud: iCloud,
                                    timeMachine: timeMachine, now: now)
        }

        // The same two extra rows `CoverageReader.read` appends, in the same order and from the
        // same sentences.
        if let sentence = cloudOnly.sentence {
            rows.append(Coverage(name: "Files that are in the cloud and not on this disk",
                                 lives: .onlyInTheCloud,
                                 included: .no,
                                 why: sentence,
                                 bytes: cloudOnly.apparent))
        }
        for provider in providers {
            rows.append(Coverage(name: provider,
                                 lives: .onAnotherDrive,
                                 included: .no,
                                 why: CoverageReader.whyAFileProviderIsNeverOpened(provider)))
        }

        return CoverageReader.Reading(coverage: rows,
                                      cloudOnly: cloudOnly,
                                      providers: providers,
                                      desktopAndDocumentsMirrored: mirrored,
                                      iCloud: iCloud,
                                      fullDiskAccessHeld: fullDiskAccessHeld,
                                      refused: .sawEverything,
                                      ranAt: now)
    }

    /// The invented Mac both pages are written for. One machine, so the page and the Hardware
    /// section cannot describe two different computers.
    private static let demoMacDescription = "Kitchen iMac — MacBook Air (M3, 2024)"

    private static func plan(macOS: String,
                             destinationName: String?,
                             fileVaultOn: Bool,
                             writtenOn: Date) -> RecoveryPlan {
        RecoveryPlan.make(macOSVersion: macOS,
                          macDescription: demoMacDescription,
                          architecture: .appleSilicon,
                          destinationName: destinationName,
                          fileVaultOn: fileVaultOn,
                          writtenOn: writtenOn)
    }

    // MARK: Backup — a healthy Mac

    /// **Backups running, the drive plugged in, and a Recovery Plan on the wall.**
    ///
    /// The last backup finished this morning, macOS has thinned its local snapshots on its own — so
    /// there is no stuck-snapshot line — and the only things "not covered" are the two that never
    /// can be: files that live in the cloud, and a sync service Wellkept refuses to walk into.
    /// Neither is a gap, and the row says so in its own words rather than in a warning.
    private static let healthyBackup: BackupAnswer = {
        let now = launched
        let record = destinationRecord(
            name: "Backups",
            successes: [daysAgo(9), daysAgo(6), daysAgo(3), daysAgo(1), minutesAgo(310)],
            attempts: [minutesAgo(310)],
            result: 0,
            bytesUsed: 486_000_000_000,
            bytesAvailable: 1_514_000_000_000,
            referenceSnapshot: nil)

        let machine = timeMachine(record: record,
                                  automaticBackupsOn: true,
                                  isConnected: true,
                                  volumePath: "/Volumes/Backups",
                                  capacity: 2_000_000_000_000,
                                  free: 1_514_000_000_000,
                                  // Backups are finishing, so macOS thins its own snapshots within
                                  // about a day. Nothing is stuck and nothing is said.
                                  snapshots: .none,
                                  now: now)

        let iCloud = CoverageReader.ICloudAccount(
            signedIn: true,
            standings: ["com.apple.Dataclass.Ubiquity": .on,
                        "com.apple.Dataclass.Photos": .on,
                        "com.apple.Dataclass.Notes": .on],
            unreadable: nil)

        let reading = coverage(
            places: [.homeFolder, .photos, .mail, .messages, .contacts, .notes,
                     .iCloudDrive, .safari, .music],
            iCloud: iCloud,
            timeMachine: machine.state,
            cloudOnly: CoverageReader.CloudHolding(files: 2_140,
                                                   apparent: SizeOnDisk(8_400_000_000),
                                                   measured: true),
            providers: ["Dropbox"],
            mirrored: false,
            fullDiskAccessHeld: true,
            now: now)

        let today = plan(macOS: "26.6.2", destinationName: "Backups", fileVaultOn: true,
                         writtenOn: now)
        // Printed a fortnight ago, for the macOS this Mac is still on. Current, so the page says
        // nothing about reprinting.
        let printed = plan(macOS: "26.6.2", destinationName: "Backups", fileVaultOn: true,
                           writtenOn: daysAgo(14))

        return BackupModel.assemble(machine: machine,
                                    coverage: reading,
                                    planForToday: today,
                                    onRecord: printed,
                                    destination: nil,
                                    agentIsOn: false,
                                    now: minutesAgo(10))
    }()

    // MARK: Backup — a Mac with problems

    /// **Switched off for nearly four weeks, the drive not seen since August, and no page printed.**
    ///
    /// ⚠️ The headline is *"switched off"*, not *"failing"*, and the difference is the point. The
    /// destination is configured, the last backup finished, and nothing is broken — somebody turned
    /// automatic backups off and was never told. `TimeMachineStanding` tests `switchedOff` before
    /// it tests failure precisely so this Mac cannot be described as faulty.
    ///
    /// ⭐ It also carries the finding that ties this section to Storage: the one local snapshot
    /// still on the disk **is** Time Machine's reference point, to the second, so the space Storage
    /// says is being held is released by letting one backup finish.
    private static let unwellBackup: BackupAnswer = {
        let now = launched
        let lastSuccess = daysAgo(26)
        let record = destinationRecord(
            name: "Archive",
            successes: [daysAgo(88), daysAgo(61), daysAgo(40), lastSuccess],
            attempts: [lastSuccess],
            result: 0,
            bytesUsed: 430_000_000_000,
            bytesAvailable: 62_000_000_000,
            // Held to the second of the snapshot below — which is what macOS actually does, and
            // why the sentence can say what the snapshot is FOR.
            referenceSnapshot: lastSuccess)

        let machine = timeMachine(
            record: record,
            automaticBackupsOn: false,
            isConnected: false,
            volumePath: nil,
            capacity: nil,
            free: nil,
            snapshots: SnapshotStanding(snapshots: [
                LocalSnapshot(name: "com.apple.TimeMachine.2026-08-25-062503.local",
                              takenOn: lastSuccess),
            ]),
            now: now)

        // Four of twenty-four services state themselves; the rest say nothing at all, and there is
        // no honest way to read a missing key as "off".
        let iCloud = CoverageReader.ICloudAccount(
            signedIn: true,
            standings: ["com.apple.Dataclass.Ubiquity": .on,
                        "com.apple.Dataclass.Notes": .on],
            unreadable: nil)

        let reading = coverage(
            places: [.homeFolder, .photos, .mail, .messages, .contacts, .notes,
                     .iCloudDrive, .safari, .music],
            iCloud: iCloud,
            timeMachine: machine.state,
            // ⚠️ Named and skipped, never downloaded. Copying these would mean pulling 72 GB onto a
            // Mac with 95 GB free, over somebody's own internet, to make a second copy of files
            // that already have one.
            cloudOnly: CoverageReader.CloudHolding(files: 12_412,
                                                   apparent: SizeOnDisk(72_200_000_000),
                                                   measured: true),
            providers: ["Google Drive"],
            mirrored: true,
            // ⚠️ **The unwell Mac has not given Wellkept Full Disk Access, and that is the second
            // most valuable thing on this screen.** Without it a backup contains no mail, no
            // messages, no photos, no contacts, no Safari data and no Trash — not partial,
            // *nothing* — and macOS refuses silently with no error at all. The row says so, names
            // the six, and offers the one button that changes it.
            fullDiskAccessHeld: false,
            now: now)

        let today = plan(macOS: "26.6.2", destinationName: "Archive", fileVaultOn: true,
                         writtenOn: now)

        return BackupModel.assemble(machine: machine,
                                    coverage: reading,
                                    planForToday: today,
                                    // Nobody has printed the page. It is the one row on this screen
                                    // that costs nothing to fix and is fixed by a printer.
                                    onRecord: nil,
                                    destination: nil,
                                    agentIsOn: false,
                                    now: minutesAgo(10))
    }()

    // MARK: - Changes

    /// The whole Changes answer for one machine, built once so its `Finding` keeps a stable `id`.
    ///
    /// ## ⚠️ Built by the real diff, out of two real snapshots
    ///
    /// Both reports below come out of `Diff.report`, the same function the real check calls, fed
    /// two `Snapshot`s of an invented Mac. Nothing here hand-writes a finished sentence: every line
    /// on the screen is composed by `Change.sentence`, `MacOSUpdate.sentence` and
    /// `ChangesReport.summary` from the facts underneath it. A demo that typed the sentences would
    /// photograph a screen the app is no longer capable of drawing.
    ///
    /// ⛔ **The verdict is injected, and it has to be.** `Diff.report` otherwise asks
    /// `Attribution.verdict(for:)`, which reads *this* Mac's install record and boot log — and demo
    /// mode's whole promise is that nothing on screen came from this machine.
    ///
    /// ⛔ **Neither Mac names an app as the cause of anything.** `Cause` has no case that could, and
    /// `ChangesSectionTests` checks the demo text for it anyway. "Sample Remote" appears as the app
    /// that *holds* a permission, which is what the reader actually knows, never as the thing that
    /// granted it.
    static func changes(_ machine: DemoMachine) -> ChangesReport {
        switch machine {
        case .healthy:  healthyChanges
        case .problems: unwellChanges
        }
    }

    // MARK: Changes — the shape of one invented snapshot

    /// The invented machine both snapshots are taken on. Identical across the pair, because
    /// `Snapshot.comparable(with:)` refuses to compare two different Macs — and rightly.
    private static let demoMachineIdentifier = "Mac15,3"

    private static func snapshot(takenAt: Date,
                                 systemVersion: String,
                                 watched: [String: String],
                                 settings: [String: String]) -> Snapshot {
        Snapshot(takenAt: takenAt,
                 bootedAt: takenAt.addingTimeInterval(-3_600 * 30),
                 systemVersion: systemVersion,
                 machine: demoMachineIdentifier,
                 appVersion: "0.1.0",
                 watched: watched,
                 // Lockdown Mode is unreadable on every Mac Apple has ever shipped, so it is
                 // recorded as unread rather than silently missing — and `Diff.unread` drops it
                 // from the face, because a caveat nobody can ever clear teaches people to stop
                 // reading caveats.
                 unreadable: [WatchedKey(.protections, "lockdownMode").storageKey:
                                Unreadable.notReported.rawValue],
                 settings: settings,
                 excludedDomains: SnapshotStore.churnDomains.map(\.domain))
    }

    /// A quiet Mac's watched values: everything on, nothing listening, a couple of dozen things
    /// starting at login, and four apps holding a permission each.
    private static func settledValues(systemVersion: String,
                                      loginItems: Int,
                                      profiles: Int = 0,
                                      firewall: String = "On",
                                      automaticSecurityUpdates: String = "On",
                                      extraGrants: [(String, WellkeptCore.Permission)] = []) -> [String: String] {
        var out: [String: String] = [:]

        for (kind, state) in [(ProtectionKind.fileVault, "On"),
                              (.systemProtection, "On"),
                              (.gatekeeper, "On"),
                              (.secureBoot, "On"),
                              (.firewall, firewall),
                              (.automaticSecurityUpdates, automaticSecurityUpdates),
                              (.automaticLogin, "Off")] {
            out[WatchedKey(.protections, kind.rawValue).storageKey] = state
        }

        // ⚠️ "Not seen listening", never "Off". macOS gives no reading that proves a sharing
        // service is switched off, and a snapshot that recorded one as off would make a later
        // build report a change that never happened. `Diff.values` spells it exactly this way.
        for service in ReachableReader.Service.allCases {
            out[WatchedKey(.reachableFrom, service.rawValue).storageKey] = "Not seen listening"
        }

        out[WatchedKey(.startsOnItsOwn, "userAgent").storageKey] = String(loginItems)
        out[WatchedKey(.startsOnItsOwn, "globalDaemon").storageKey] = "9"
        out[WatchedKey(.startsOnItsOwn, "cron").storageKey] = "0"
        out[WatchedKey(.startsOnItsOwn, "configurationProfile").storageKey] = String(profiles)

        let grants: [(String, WellkeptCore.Permission)] = [
            ("us.zoom.xos", .camera),
            ("us.zoom.xos", .microphone),
            ("com.knollsoft.Rectangle", .accessibility),
            ("com.example.weather", .location),
        ] + extraGrants
        for (bundleID, permission) in grants {
            out[Diff.instanceKey(WatchedKey(.whoCanWatch, permission.rawValue), instance: bundleID)] = "Allowed"
        }

        out[WatchedKey(.macOSItself, "systemVersion").storageKey] = systemVersion
        return out
    }

    /// The full capture, in miniature.
    ///
    /// Real snapshots hold about eleven thousand values; a dozen is enough to make the one number
    /// the face actually prints — *"6 other values also changed"* — come out of the same arithmetic
    /// the real one uses rather than being typed in.
    private static func capturedSettings(_ moved: Int) -> [String: String] {
        var out: [String: String] = [:]
        for index in 0..<60 {
            out[SnapshotStore.settingKey(domain: "com.apple.dock", key: "demo-\(index)")] = "steady"
        }
        for index in 0..<moved {
            out[SnapshotStore.settingKey(domain: "com.apple.finder", key: "demo-\(index)")] = "moved-\(index)"
        }
        return out
    }

    /// The names behind the bundle identifiers in the grant keys, so a row can say "Sample Remote"
    /// rather than "com.example.remote".
    private static let changeNames = [
        "us.zoom.xos": "Zoom",
        "com.knollsoft.Rectangle": "Rectangle",
        "com.example.weather": "Sample Weather",
        "com.example.remote": "Sample Remote",
    ]

    // MARK: Changes — a healthy Mac

    /// **A quiet journal.** One macOS update, two harmless things that moved during it, and a
    /// handful of values Wellkept keeps but does not describe.
    ///
    /// ⚠️ This is the case the product exists to be able to show, and it is the one worth reading
    /// hardest. Nothing is amber. The macOS version going up is never a fault and three more login
    /// items is a fact about a Mac somebody installed software on — neither carries a `safeValue`,
    /// so neither can reach `.attention` however the screen is drawn.
    private static let healthyChanges: ChangesReport = {
        let update = MacOSUpdate(
            version: "26.6.2",
            installedAt: daysAgo(2),
            // ⭐ The strongest sentence this section has, and the wording is the whole point:
            // *changed during*, never *the update changed it*.
            outage: Outage(wentDown: daysAgo(2),
                           cameBack: daysAgo(2).addingTimeInterval(292),
                           precision: .toTheSecond))

        let earlier = snapshot(takenAt: daysAgo(4),
                               systemVersion: "26.6.1",
                               watched: settledValues(systemVersion: "26.6.1", loginItems: 14),
                               settings: capturedSettings(0))
        let later = snapshot(takenAt: minutesAgo(9),
                             systemVersion: "26.6.2",
                             watched: settledValues(systemVersion: "26.6.2", loginItems: 15),
                             settings: capturedSettings(6))

        return Diff.report(earlier: earlier,
                           latest: later,
                           now: minutesAgo(9),
                           names: changeNames,
                           verdict: Attribution.Verdict(cause: .duringMacOSUpdate(update),
                                                        confidence: .consistent,
                                                        macWasOffOrAsleep: true,
                                                        outageUnreadable: nil))
    }()

    // MARK: Changes — a Mac with problems

    /// **The four paths nobody will otherwise see**, in one window: the firewall off, a
    /// configuration profile that appeared, an app that gained the screen, and a switch an
    /// organisation now holds.
    ///
    /// ⚠️ **The organisation's switch is stated and never raised.** A Mac configured by an employer
    /// is not a Mac with something wrong with it, and the person reading the screen cannot act on
    /// it — so `Cause.mayRaiseSeverity` drops it to `.information` while the row still says plainly
    /// what happened. That branch has no other way of getting looked at.
    ///
    /// ⚠️ The outage here is measured **to the minute**, not to the second, so the weaker sentence —
    /// *"about six minutes"* — gets photographed too. The shutdown record has minute resolution and
    /// the boot instant does not; claiming seconds from two minute-resolution readings would be
    /// inventing them.
    private static let unwellChanges: ChangesReport = {
        let update = MacOSUpdate(
            version: "26.6.2",
            installedAt: daysAgo(3),
            outage: Outage(wentDown: daysAgo(3),
                           cameBack: daysAgo(3).addingTimeInterval(370),
                           precision: .toTheMinute))

        let earlier = snapshot(takenAt: daysAgo(6),
                               systemVersion: "26.6.1",
                               watched: settledValues(systemVersion: "26.6.1", loginItems: 21),
                               settings: capturedSettings(0))
        let later = snapshot(
            takenAt: minutesAgo(9),
            systemVersion: "26.6.2",
            watched: settledValues(systemVersion: "26.6.2",
                                   loginItems: 21,
                                   profiles: 1,
                                   firewall: "Off",
                                   automaticSecurityUpdates: "Off",
                                   extraGrants: [("com.example.remote", .screenRecording)]),
            settings: capturedSettings(41))

        return Diff.report(earlier: earlier,
                           latest: later,
                           now: minutesAgo(9),
                           // The one cause this app can state outright, because the profile is a
                           // readable file that names the setting it forces.
                           organisationSets: [WatchedKey(.protections, "automaticSecurityUpdates")],
                           names: changeNames,
                           verdict: Attribution.Verdict(cause: .duringMacOSUpdate(update),
                                                        confidence: .consistent,
                                                        macWasOffOrAsleep: true,
                                                        outageUnreadable: nil))
    }()
}

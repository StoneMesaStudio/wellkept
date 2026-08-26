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

enum DemoData {

    // MARK: - When the demo check "ran"
    //
    // Offsets from the app's launch, resolved once, rather than a frozen calendar date. A demo
    // whose audit trail says "26 Aug 2026" reads as a broken clock the moment the year turns —
    // and the audit trail is precisely the part of Overview that is about dates being trustworthy.

    private static let launched = Date()
    private static func minutesAgo(_ m: Int) -> Date { launched.addingTimeInterval(-60 * Double(m)) }

    // MARK: - The audit trail

    /// When each section last "ran", and what it concluded.
    ///
    /// **Storage is deliberately `complete: false`.** It is the one state Overview must never get
    /// wrong — the app may not report a healthy Mac on the strength of a partial look — and a
    /// branch nobody can see is a branch nobody checks. This is how it gets looked at.
    static let records: [SectionID: CheckRecord] = {
        var out: [SectionID: CheckRecord] = [:]
        for section in SectionID.checkable {
            let found = findings.filter { $0.section == section }
            out[section] = CheckRecord(
                section: section,
                ranAt: minutesAgo(ranMinutesAgo[section] ?? 12),
                status: found.contains(where: { $0.severity >= .attention }) ? .needsAttention : .good,
                complete: section != .storage)
        }
        // Overview's own line is the whole sweep: the oldest of the six, because that is when the
        // sweep began, and honest about the partial look inside it.
        out[.overview] = CheckRecord(
            section: .overview,
            ranAt: out.values.map(\.ranAt).min() ?? minutesAgo(14),
            status: .needsAttention,
            complete: false)
        return out
    }()

    private static let ranMinutesAgo: [SectionID: Int] = [
        .hardware: 14, .storage: 13, .apps: 11, .security: 11, .backup: 10, .changes: 9,
    ]

    // MARK: - What it "found"

    static let findings: [Finding] = hardware + storage + apps + security + backup + changes

    // MARK: Hardware

    private static let hardware: [Finding] = [
        Finding(section: .hardware,
                title: "The startup disk is 91% full",
                reason: "Below about 10% free, macOS stops taking local snapshots and writes slow down. 84 GB of what is on there is listed under Storage.",
                severity: .attention,
                measure: "91%",
                verb: "Open Storage"),
        Finding(section: .hardware,
                title: "Battery health is 82%, over term 486 cycles",
                reason: "Apple counts a battery as consumed below 80%. At this rate that is roughly a year away — it is not a fault today.",
                severity: .information,
                measure: "82%"),
        Finding(section: .hardware,
                title: "The drive reports no errors",
                reason: "SMART status: Verified. 41 TB written over 3 years, which is ordinary for a drive this age.",
                severity: .information),
        Finding(section: .hardware,
                title: "Nothing has overheated in the last 30 days",
                reason: "No thermal throttling recorded. The fans have not run above 2,100 rpm.",
                severity: .information),
        Finding(section: .hardware,
                title: "24 GB of memory, and the Mac has not swapped today",
                reason: "1.4 GB of swap is in use, all of it from before the last restart.",
                severity: .information,
                measure: "24 GB"),
    ]

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

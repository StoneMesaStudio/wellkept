import Foundation
import IOKit
import IOKit.storage
import IOKit.storage.ata
import WellkeptCore

//  DriveReader.swift
//  Wellkept — App/Hardware
//
//  **Is this drive healthy?** — the first row of the Hardware section, for the drive this Mac
//  starts from and for anything plugged into it.
//
//  ## ⚠️ The Hardware / Storage boundary, decided here so neither section has to guess
//
//  **Hardware owns "is this drive healthy". Storage owns "what is on it".** They read the same
//  hardware and they must never say the same thing twice — DESIGN §8: the container is the answer,
//  and what is inside does not repeat it.
//
//  | | Hardware (this file) | Storage |
//  |---|---|---|
//  | The drive's own verdict on itself | **owns it** | never mentions it |
//  | Wear, spare capacity, error counts | **owns it** | never mentions it |
//  | How full the drive is | states it once, behind Options, as inventory | **owns it**, and owns flagging it |
//  | What the space is going to | never | **owns it** |
//  | An external drive that says it is failing | **owns it** | may list its contents, may not judge it |
//
//  Two rules fall out of that table, and both are enforced in this file rather than left to
//  whoever writes the views:
//
//  1. **A full drive is never a problem here.** `fullness` is read and reported, and it can never
//     move `Reading.severity`. A drive at 96% is Storage's finding, on Storage's screen, with
//     Storage's list of what is taking the room. If Hardware flagged it too, a person would be
//     told the same thing twice and would have to work out whether it was one problem or two.
//  2. **A failing external drive is Hardware's row**, even though the same drive appears in
//     Storage as a place with files on it. "This drive is failing" is a health verdict; nothing in
//     Storage says it.
//
//  ## ⚠️ What this Mac will and will not tell us — measured, 2026-08-27
//
//  The section's working document says drive wear is unreadable on Apple silicon, on the strength
//  of a probe that opened `IONVMeSMARTUserClient` against the NVMe **controller**
//  (`AppleANS3CGv2Controller`) and got `kIOReturnUnsupported`. **That was the wrong node.** Opened
//  the documented way — `IOCreatePlugInInterfaceForService` against the block **device** that
//  advertises `NVMe SMART Capable`, which on this M3 is `IOEmbeddedNVMeBlockDevice` — the same API
//  returns a full 512-byte SMART page: 1% of rated life used, spare 100 against a threshold of 99,
//  2,215 power-on hours, 197 power cycles, 10 unsafe shutdowns, no media errors, 42 TB written.
//  Re-verified by hand from Swift before this file was written. It costs no permission, no
//  subprocess and no root.
//
//  Three things follow, and only the first is a change of plan:
//
//  - **The wear numbers exist on Apple silicon after all.** They are read where they are offered
//    and the row degrades to Apple's verdict alone where they are not — one code path, no
//    architecture branch, because "did the device answer?" is a better question than "what chip is
//    this?" for an external enclosure that may pass SMART through on either kind of Mac.
//  - **"94% life remaining, roughly 3 years at your current rate" stays dead.** The percentage is
//    real; the years were arithmetic on a manufacturer's estimate of a workload nobody has
//    measured. A number this file can defend is worth printing. A forecast is not.
//  - **Worn is not failing, and this file never blurs them.** `PERCENTAGE_USED` at 100 means the
//    drive has written what its maker rated it for. It is not a fault, it cannot be cleared, and
//    marking it one would produce exactly the warning-nobody-can-act-on this app exists to avoid.
//    The word "failing" appears only where the drive itself declares a fault.
//
//  ## Where each fact comes from, and what it costs
//
//  | Fact | Source | Permission |
//  |---|---|---|
//  | Model, serial, firmware, medium | `Device Characteristics` in the IORegistry | none |
//  | Connection | `Protocol Characteristics` | none |
//  | Capacity, BSD name | the whole `IOMedia` under the device | none |
//  | Apple's verdict | the NVMe SMART page, or ATA `SMARTReturnStatus` | none |
//  | Wear, spare, hours, errors, bytes written | the NVMe SMART page | none |
//  | How full | the mounted volume's own capacity figures | none |
//
//  **None of it needs Full Disk Access**, and nothing here spawns `system_profiler` or `diskutil`.
//  Everything is read-only: no drive is opened for writing, nothing is mounted or unmounted, and
//  the one ATA call that would change a device's own settings — `SMARTEnableDisableOperations` —
//  is deliberately never made. If a drive has SMART switched off, this file reports that it could
//  not read it rather than switching it on behind the person's back.

// MARK: - One drive

/// One physical drive, as this Mac describes it.
///
/// Value type, no IOKit handles: everything is read once and the registry objects are released
/// before this leaves the reader, so a view can hold it, a test can build one by hand, and demo
/// mode can invent a failing drive without a failing drive.
struct DriveFacts: Sendable, Hashable, Identifiable {

    // MARK: The drive's own verdict

    /// What the drive says about itself, in the three states that actually occur.
    ///
    /// ⚠️ **`.failing` is set only from the drive's own declaration** — the NVMe critical-warning
    /// byte, or the ATA threshold-exceeded flag. It is never inferred from wear, age, error counts
    /// or how full something is. That restraint is the whole reason the word is worth anything on
    /// the one screen where it matters.
    enum Verdict: String, Sendable, Hashable, Codable {
        /// The drive checked itself and found nothing wrong. Apple prints this as "Verified".
        case verified
        /// The drive is declaring a fault. Apple prints this as "Failing".
        case failing
        /// Nothing answered. Most USB enclosures do not pass SMART through, and that is normal.
        case notReported

        /// Apple's own word for this state, for quoting verbatim. `nil` where there is no verdict
        /// to quote — this file never invents one.
        var appleWord: String? {
            switch self {
            case .verified:    "Verified"
            case .failing:     "Failing"
            case .notReported: nil
            }
        }
    }

    /// How the drive is attached.
    ///
    /// ⚠️ Thunderbolt and USB4 enclosures both report `PCI-Express` at an external location — the
    /// IORegistry has no Thunderbolt interconnect constant. "Thunderbolt" is what a person calls
    /// that socket, so that is what this says.
    enum Connection: Sendable, Hashable {
        case internalDrive
        case usb
        case thunderbolt
        case fireWire
        case sdCard
        case externalSATA
        /// Something the shipped list does not name, kept in the machine's own words rather than
        /// flattened to "Other".
        case other(String)

        var label: String {
            switch self {
            case .internalDrive:   "Internal"
            case .usb:             "USB"
            case .thunderbolt:     "Thunderbolt"
            case .fireWire:        "FireWire"
            case .sdCard:          "SD card"
            case .externalSATA:    "External SATA"
            case .other(let name): name
            }
        }

        var isInternal: Bool { self == .internalDrive }
    }

    /// The NVMe SMART page, in the seven numbers worth showing a person.
    ///
    /// Everything here is the drive's own counter. Nothing is derived, averaged or forecast.
    struct Wear: Sendable, Hashable, Codable {
        /// The NVMe critical-warning byte, kept raw so a new bit in a future revision is not
        /// silently discarded by an enum that has never heard of it.
        let criticalWarning: UInt8
        /// Spare blocks left, as a percentage of what the drive shipped with.
        let availableSpare: UInt8
        /// The percentage at which the drive itself starts warning.
        let spareThreshold: UInt8
        /// How much of the drive's rated write life is used. **Can legitimately exceed 100.**
        let percentageUsed: UInt8
        let powerOnHours: UInt64
        let powerCycles: UInt64
        let unsafeShutdowns: UInt64
        /// Errors the drive could not correct. Rare, and each one is data that was lost.
        let mediaErrors: UInt64
        /// NVMe data units written. One unit is 1,000 blocks of 512 bytes.
        let dataUnitsWritten: UInt64

        /// The drive has used up the spare blocks it keeps to replace failed ones. **A fault the
        /// drive is declaring**, and the NVMe equivalent of Apple's "Failing".
        var spareBelowThreshold: Bool { criticalWarning & 0x01 != 0 }
        /// The drive was over or under its own temperature limit at the moment we looked.
        ///
        /// ⚠️ **Reported, never escalated.** This section refuses to print a temperature at all —
        /// the reading moved 62 → 79 → 58 °C in three minutes on an idle Mac — and a momentary
        /// thermal state is not a drive fault. It appears as a line behind Options and changes no
        /// severity anywhere.
        var overTemperature: Bool { criticalWarning & 0x02 != 0 }
        /// The drive says its own reliability has degraded. A declared fault.
        var reliabilityDegraded: Bool { criticalWarning & 0x04 != 0 }
        /// The drive has put itself into read-only mode. A declared fault, and usually the last
        /// thing a drive does before it stops answering.
        var readOnly: Bool { criticalWarning & 0x08 != 0 }
        /// The drive's volatile-memory backup has failed. A declared fault.
        var backupFailed: Bool { criticalWarning & 0x10 != 0 }

        /// Whether the drive is declaring a fault, as opposed to being worn, hot or busy.
        var declaresFault: Bool {
            spareBelowThreshold || reliabilityDegraded || readOnly || backupFailed
        }

        /// Bytes written over the drive's life. NVMe counts in units of 1,000 × 512 bytes.
        var bytesWritten: Int64 {
            let units = Double(dataUnitsWritten) * 512_000
            return units > Double(Int64.max) ? Int64.max : Int64(units)
        }
    }

    /// How full a drive is — read here, owned by Storage. See the boundary table at the top.
    struct Fullness: Sendable, Hashable, Codable {
        let volumeName: String
        let totalBytes: Int64
        let freeBytes: Int64

        var usedBytes: Int64 { max(0, totalBytes - freeBytes) }
        /// 0…100, rounded. `nil` for a volume that reports no capacity at all.
        var percentUsed: Int? {
            guard totalBytes > 0 else { return nil }
            return Int((Double(usedBytes) / Double(totalBytes) * 100).rounded())
        }
    }

    // MARK: What was read

    /// The IORegistry entry ID of the block device. Stable for as long as the drive is attached,
    /// which is longer than any screen this appears on.
    let id: UInt64
    /// "disk0". Kept because it is what every other tool on the Mac calls this drive.
    let bsdName: String
    /// "APPLE SSD AP0512Z", or the vendor's name for it.
    let model: String
    let vendor: String?
    let serialNumber: String?
    let firmwareRevision: String?
    /// Whole-drive capacity in bytes, as the media reports it. `nil` where it did not.
    let capacityBytes: Int64?
    let connection: Connection
    /// "Solid State" or "Rotational", where the device says. Old spinning drives are the ones that
    /// actually fail, so it is worth knowing which kind is being talked about.
    let mediumType: String?
    let isRemovable: Bool
    /// The drive this Mac started from. Exactly one, on a Mac that booted.
    let isStartupDrive: Bool
    let verdict: Verdict
    /// The wear page, where the drive offered one.
    let wear: Wear?
    /// The biggest mounted volume on this drive, where one is mounted.
    let fullness: Fullness?

    /// What to call this drive on screen: the volume's name if it has one, else the model.
    ///
    /// A person recognises "Backup T7" and does not recognise "Samsung PSSD T7 Shield" — but a
    /// drive with nothing mounted has no volume name at all, and the model is then the only
    /// honest handle.
    var displayName: String { fullness?.volumeName ?? model }

    /// The line the row leads with for this drive, in Apple's own words where there are any.
    var verdictSentence: String {
        switch verdict {
        case .verified:
            isStartupDrive
                ? "Apple reports this drive as healthy."
                : "Apple reports “\(displayName)” as healthy."
        case .failing:
            isStartupDrive
                ? "Apple's own drive check reports this drive as “Failing”."
                : "Apple's own drive check reports “\(displayName)” as “Failing”."
        case .notReported:
            Unreadable.notReported.sentence(about: "This drive's own health check")
        }
    }
}

// MARK: - The row

/// **The drive row: what this Mac's drives say about themselves.**
///
/// Three entry points, and the split matters. `drives()` touches the machine. `reading(for:)` and
/// `alarm(for:)` are pure functions of what it found, which is what lets demo mode — and a test —
/// exercise the failing screen on a Mac whose drive is fine. See `DriveFacts.exampleFailing`.
enum DriveReader {

    // MARK: The one call the section makes

    /// Read every drive and build the row.
    ///
    /// Cheap: one IORegistry pass, one SMART page per drive that offers one, and one `statfs` per
    /// mounted volume. Free of side effects and safe to call from any thread.
    static func read() -> Reading { reading(for: drives()) }

    // MARK: The row, as a pure function

    /// Build the drive row from drives already read.
    ///
    /// The precedence is deliberate and is the whole judgement of this file:
    ///
    /// 1. **Any drive declaring a fault** — a problem, and it outranks everything, internal or not.
    /// 2. **Errors the drive could not correct** — attention. Not a declared fault, but data that
    ///    was lost, and a person is entitled to know before it happens again.
    /// 3. **The startup drive's verdict** — good if the drive verified itself.
    /// 4. **Nothing answered** — `.notReported`, which keeps the check complete. Most USB
    ///    enclosures do not pass SMART through and there is nothing wrong with that.
    ///
    /// Wear and fullness appear at every step and decide nothing at any of them.
    static func reading(for drives: [DriveFacts]) -> Reading {
        guard let startup = drives.first(where: \.isStartupDrive) ?? drives.first else {
            return Reading.unreadable(.drive, .notReported, about: "This Mac's drive")
        }

        let details = detailPairs(for: drives)

        // 1. A declared fault, anywhere. The failing drive becomes the subject of the row even
        //    when it is a drive somebody plugged in five minutes ago — see the boundary table.
        if let failing = drives.first(where: { $0.verdict == .failing }) {
            // ⚠️ **No figure on this row, deliberately.** The wear number is still recorded — the
            // history is the one thing that cannot be rebuilt later — but it is not shown. A
            // person reading "Failing" next to "118% worn" now has a percentage to think about
            // instead of files to copy, and 118% invites a question that costs the afternoon.
            return Reading(
                topic: .drive,
                headline: failing.verdictSentence,
                measure: nil,
                number: wearNumber(failing),
                severity: .problem,
                reason: failing.isStartupDrive
                    ? "Copy your files off this Mac now, then contact Apple Support."
                    : "Copy your files off “\(failing.displayName)” now, while it still answers.",
                details: details)
        }

        // 2. Uncorrectable errors: the drive is not declaring a fault, but it has already lost
        //    data at least once. Never the word "failing" — the drive has not said it.
        if let damaged = drives.first(where: { ($0.wear?.mediaErrors ?? 0) > 0 }),
           let errors = damaged.wear?.mediaErrors {
            return Reading(
                topic: .drive,
                headline: damaged.isStartupDrive
                    ? "This drive has data it could not read back."
                    : "“\(damaged.displayName)” has data it could not read back.",
                measure: wearMeasure(damaged),
                number: wearNumber(damaged),
                severity: .attention,
                reason: "The drive counts \(errors.formatted()) \(errors == 1 ? "block" : "blocks") "
                      + "it could not correct. It is still reporting itself as healthy, so this is "
                      + "a reason to make sure the drive is backed up rather than a fault to act on today.",
                details: details)
        }

        // 3 and 4. The startup drive's own verdict carries the row.
        switch startup.verdict {
        case .verified:
            return Reading(
                topic: .drive,
                headline: startup.verdictSentence,
                measure: wearMeasure(startup),
                number: wearNumber(startup),
                severity: .information,
                reason: pastRatedLife(startup)
                    ? "It has written more than the maker rates it for and is still checking out "
                      + "healthy. That is wear, not a fault."
                    : nil,
                details: details)

        case .failing:
            // Unreachable — case 1 catches it. Left explicit rather than folded into a default, so
            // that adding a verdict later fails to compile instead of falling into "not reported".
            return Reading(topic: .drive,
                           headline: startup.verdictSentence,
                           severity: .problem,
                           reason: "Copy your files off this Mac now, then contact Apple Support.",
                           details: details)

        case .notReported:
            // ⚠️ `.notReported`, never `.notPermitted`. Nothing refused us: this drive does not
            // offer a health check. Marking it "not permitted" would put a caveat Overview can
            // never clear on every Mac with a plain USB disk attached.
            return Reading.unreadable(
                .drive,
                .notReported,
                about: "This drive's own health check",
                reason: startup.connection.isInternal
                    ? "This Mac's drive does not offer a health check of its own. Everything else "
                      + "below was read normally."
                    : "Most drives in a USB case keep their health check to themselves. Everything "
                      + "else below was read normally.",
                details: details)
        }
    }

    // MARK: The failing screen

    /// **What the section shows when a drive says it is failing.**
    ///
    /// ⚠️ This is the one screen in Hardware that has to be right and that has never been seen
    /// against a real fault. It says two things and nothing else:
    ///
    /// 1. Get the files off, now.
    /// 2. Talk to somebody who can replace it.
    ///
    /// It quotes Apple's own verdict, names no component, quotes no price, and uses the word
    /// "failing" only because the drive used it first. Everything else a person might want —
    /// wear, hours, error counts — is still behind Options and is deliberately not on this screen:
    /// a page of numbers is what a person reads instead of copying their files off.
    ///
    /// `nil` when nothing is failing, which is the answer on every Mac this will ever ship to but
    /// one. If two drives are failing at once this is about the first — which `drives()` has
    /// already sorted to be the startup drive, the same one the row's headline names.
    static func alarm(for drives: [DriveFacts]) -> DriveAlarm? {
        guard let failing = drives.first(where: { $0.verdict == .failing }) else { return nil }
        return DriveAlarm(failing)
    }

    // MARK: - Reading the machine

    /// Every physical drive attached to this Mac, startup drive first.
    ///
    /// Disk images are excluded. A mounted `.dmg`, an Xcode simulator runtime and a Time Machine
    /// sparsebundle all appear here as block storage devices, and reporting the health of a file
    /// pretending to be a drive is noise at best.
    static func drives() -> [DriveFacts] {
        let volumes = mountedVolumesByDevice()
        let startupDevice = deviceID(forVolumeAt: URL(fileURLWithPath: "/", isDirectory: true))

        var iterator: io_iterator_t = IO_OBJECT_NULL
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOBlockStorageDevice"),
                                           &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var found: [DriveFacts] = []
        while case let device = IOIteratorNext(iterator), device != IO_OBJECT_NULL {
            defer { IOObjectRelease(device) }
            guard !isDiskImage(device) else { continue }
            let id = entryID(device)
            guard let facts = read(device: device,
                                   id: id,
                                   isStartupDrive: id == startupDevice,
                                   fullness: volumes[id]) else { continue }
            found.append(facts)
        }

        // Startup drive, then the rest of the internal ones, then whatever is plugged in — the
        // order a person would list them in, and stable between runs, which a set-derived order
        // is not.
        return found.sorted { a, b in
            if a.isStartupDrive != b.isStartupDrive { return a.isStartupDrive }
            if a.connection.isInternal != b.connection.isInternal { return a.connection.isInternal }
            return a.bsdName.localizedStandardCompare(b.bsdName) == .orderedAscending
        }
    }

    private static func read(device: io_service_t,
                             id: UInt64,
                             isStartupDrive: Bool,
                             fullness: DriveFacts.Fullness?) -> DriveFacts? {
        let characteristics = dictionary(device, kIOPropertyDeviceCharacteristicsKey) ?? [:]
        let protocols = dictionary(device, kIOPropertyProtocolCharacteristicsKey) ?? [:]

        let model = text(characteristics[kIOPropertyProductNameKey]) ?? "Not reported"
        let media = wholeMedia(under: device)
        defer { if let media { IOObjectRelease(media) } }

        let wear = nvmeWear(device)
        let verdict = verdict(device: device, wear: wear)

        return DriveFacts(
            id: id,
            bsdName: media.flatMap { text(property($0, "BSD Name")) } ?? "—",
            model: model,
            vendor: text(characteristics[kIOPropertyVendorNameKey]),
            serialNumber: text(characteristics[kIOPropertyProductSerialNumberKey]),
            firmwareRevision: text(characteristics[kIOPropertyProductRevisionLevelKey]),
            capacityBytes: media.flatMap { (property($0, "Size") as? NSNumber)?.int64Value },
            connection: connection(protocols),
            mediumType: text(characteristics[kIOPropertyMediumTypeKey]),
            isRemovable: media.flatMap { flag(property($0, "Removable")) } ?? false,
            isStartupDrive: isStartupDrive,
            verdict: verdict,
            wear: wear,
            fullness: fullness)
    }

    /// Apple's verdict for one device.
    ///
    /// NVMe first, because it is the one that answers on every Mac that ships today; ATA second,
    /// for the SATA drives in 2019–2020 iMacs — spinning disks and Fusion Drives, which are
    /// precisely the drives that still fail in the field. Neither is required to answer.
    private static func verdict(device: io_service_t, wear: DriveFacts.Wear?) -> DriveFacts.Verdict {
        if let wear { return wear.declaresFault ? .failing : .verified }
        if let exceeded = ataThresholdExceeded(device) { return exceeded ? .failing : .verified }
        return .notReported
    }

    // MARK: - Details behind Options

    /// Everything worth keeping, per drive, in a fixed order.
    ///
    /// ⚠️ Labels are prefixed with the drive's name once there is more than one drive, and
    /// de-duplicated afterwards. `DetailPair.id` **is** its label, so two drives contributing a
    /// row called "Capacity" would collide in any list that draws them.
    static func detailPairs(for drives: [DriveFacts]) -> [DetailPair] {
        let prefixed = drives.count > 1
        var rows: [DetailPair] = []
        var seen: Set<String> = []

        for drive in drives {
            for pair in detailPairs(for: drive, prefixed: prefixed) {
                if seen.insert(pair.label).inserted {
                    rows.append(pair)
                } else {
                    // Two drives with the same name — two identical Samsung cases, say. The BSD
                    // name is the one handle macOS guarantees is unique, and it is what every
                    // other tool on the Mac would call them.
                    let unique = "\(pair.label) (\(drive.bsdName))"
                    seen.insert(unique)
                    rows.append(DetailPair(unique, pair.value, sensitive: pair.sensitive))
                }
            }
        }
        return rows
    }

    private static func detailPairs(for drive: DriveFacts, prefixed: Bool) -> [DetailPair] {
        func label(_ text: String) -> String {
            prefixed ? "\(drive.displayName) — \(text)" : text
        }

        var rows: [DetailPair] = [DetailPair(label("Model"), drive.model)]

        if let vendor = drive.vendor, !vendor.isEmpty, !drive.model.localizedCaseInsensitiveContains(vendor) {
            rows.append(DetailPair(label("Made by"), vendor))
        }
        rows.append(DetailPair(label("Connection"), drive.connection.label))
        if let medium = drive.mediumType {
            rows.append(DetailPair(label("Type"), medium))
        }
        // The startup drive's capacity is already in the "what this Mac is" block above. Repeating
        // it here would be the same fact twice on one screen — DESIGN §8.
        if !drive.isStartupDrive, let bytes = drive.capacityBytes {
            rows.append(DetailPair(label("Capacity"), MachineReader.capacityText(bytes: bytes)))
        }

        rows.append(DetailPair(label("The drive's own check"),
                               drive.verdict.appleWord ?? Unreadable.notReported.sentence))

        if let wear = drive.wear {
            rows.append(DetailPair(label("Wear"),
                                   "\(wear.percentageUsed)% of the write life it is rated for"))
            rows.append(DetailPair(label("Spare capacity"),
                                   "\(wear.availableSpare)%, and the drive warns below \(wear.spareThreshold)%"))
            rows.append(DetailPair(label("Powered on"), "\(wear.powerOnHours.formatted()) hours"))
            rows.append(DetailPair(label("Started up"), "\(wear.powerCycles.formatted()) times"))
            rows.append(DetailPair(label("Lost power unexpectedly"),
                                   "\(wear.unsafeShutdowns.formatted()) times"))
            rows.append(DetailPair(label("Written over its life"),
                                   MachineReader.capacityText(bytes: wear.bytesWritten)))
            rows.append(DetailPair(label("Blocks it could not correct"),
                                   wear.mediaErrors == 0 ? "None" : wear.mediaErrors.formatted()))
            if wear.overTemperature {
                rows.append(DetailPair(label("Temperature"),
                                       "The drive was above its own limit when we looked."))
            }
        }

        // Inventory, not a verdict. Storage owns whether this number is a problem.
        if let fullness = drive.fullness, let percent = fullness.percentUsed {
            rows.append(DetailPair(
                label("Space used"),
                "\(MachineReader.capacityText(bytes: fullness.usedBytes)) of "
                + "\(MachineReader.capacityText(bytes: fullness.totalBytes)) — \(percent)% full"))
        }

        if let firmware = drive.firmwareRevision, !firmware.isEmpty {
            rows.append(DetailPair(label("Firmware"), firmware))
        }
        if let serial = drive.serialNumber, !serial.isEmpty {
            rows.append(DetailPair(label("Serial number"), serial, sensitive: true))
        }
        return rows
    }

    // MARK: - The figure on the row

    /// The wear figure, where the drive gave one.
    ///
    /// **"1% worn", never "1% used."** The same row's Options carry "72% full", and a person
    /// reading two percentages a line apart will merge them. "Worn" cannot be misread as space.
    private static func wearMeasure(_ drive: DriveFacts) -> String? {
        drive.wear.map { "\($0.percentageUsed)% worn" }
    }

    /// The same figure as arithmetic, so the reading history can eventually say "2 points more
    /// worn than last year". It is the only number on this row that moves slowly enough to be
    /// worth keeping.
    private static func wearNumber(_ drive: DriveFacts) -> ReadingNumber? {
        drive.wear.map { ReadingNumber(Double($0.percentageUsed), ReadingNumber.percent) }
    }

    private static func pastRatedLife(_ drive: DriveFacts) -> Bool {
        (drive.wear?.percentageUsed ?? 0) >= 100
    }

    // MARK: - IORegistry plumbing

    private static func property(_ service: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }

    private static func dictionary(_ service: io_service_t, _ key: String) -> [String: Any]? {
        property(service, key) as? [String: Any]
    }

    /// A registry value as a trimmed string, or `nil` for an empty one.
    ///
    /// Some of these arrive as `CFString` and some as `CFData` holding a C string, and which is
    /// which is not documented anywhere that stays true between releases. The data case stops at
    /// the terminator: a serial number carrying an invisible NUL matches nothing and prints badly.
    private static func text(_ raw: Any?) -> String? {
        let value: String?
        switch raw {
        case let string as String: value = string
        case let data as Data:     value = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
        default:                   value = nil
        }
        guard let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cleaned.isEmpty else { return nil }
        return cleaned
    }

    /// `Removable`, `Whole` and friends come back as `CFBoolean` on some devices and as a number
    /// on others. Both are the same fact.
    private static func flag(_ raw: Any?) -> Bool? {
        switch raw {
        case let value as Bool:     value
        case let value as NSNumber: value.boolValue
        default:                    nil
        }
    }

    private static func entryID(_ service: io_service_t) -> UInt64 {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(service, &id)
        return id
    }

    /// A mounted disk image is a file, not a drive. It reports itself as block storage all the
    /// same — an Xcode simulator runtime and a Time Machine sparsebundle both show up here.
    private static func isDiskImage(_ device: io_service_t) -> Bool {
        if IOObjectConformsTo(device, "AppleDiskImageDevice") != 0 { return true }
        let protocols = dictionary(device, kIOPropertyProtocolCharacteristicsKey) ?? [:]
        let interconnect = text(protocols[kIOPropertyPhysicalInterconnectTypeKey])
        return interconnect == kIOPropertyPhysicalInterconnectTypeVirtual
            || text(protocols[kIOPropertyPhysicalInterconnectLocationKey]) == kIOPropertyInterconnectFileKey
    }

    private static func connection(_ protocols: [String: Any]) -> DriveFacts.Connection {
        let interconnect = text(protocols[kIOPropertyPhysicalInterconnectTypeKey]) ?? ""
        let location = text(protocols[kIOPropertyPhysicalInterconnectLocationKey]) ?? ""
        let external = location == kIOPropertyExternalKey

        // A drive the machine calls internal is "Internal" and nothing else. Which fabric it hangs
        // off is true, and it is not what anybody is asking. `Internal/External` — a bus that can
        // be either — is left to the interconnect below rather than guessed at.
        if location == kIOPropertyInternalKey { return .internalDrive }

        switch interconnect {
        case kIOPropertyPhysicalInterconnectTypeUSB:              return .usb
        case kIOPropertyPhysicalInterconnectTypeFireWire:         return .fireWire
        case kIOPropertyPhysicalInterconnectTypeSecureDigital:    return .sdCard
        case kIOPropertyPhysicalInterconnectTypeSerialATA,
             kIOPropertyPhysicalInterconnectTypeATA:              return external ? .externalSATA : .internalDrive
        case kIOPropertyPhysicalInterconnectTypePCIExpress,
             kIOPropertyPhysicalInterconnectTypePCI:              return external ? .thunderbolt : .internalDrive
        case kIOPropertyPhysicalInterconnectTypeAppleFabric:      return .internalDrive
        case "":                                                  return external ? .other("External") : .internalDrive
        default:                                                  return .other(interconnect)
        }
    }

    /// The whole-disk `IOMedia` beneath a block device — "disk0", not "disk0s2".
    ///
    /// Walked explicitly rather than with a recursive property search, which would find whichever
    /// partition the search happened to reach first and report a slice's size as the drive's.
    private static func wholeMedia(under service: io_service_t) -> io_service_t? {
        var iterator: io_iterator_t = IO_OBJECT_NULL
        guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while case let child = IOIteratorNext(iterator), child != IO_OBJECT_NULL {
            if IOObjectConformsTo(child, "IOMedia") != 0, flag(property(child, "Whole")) == true {
                return child                       // handed to the caller, which releases it
            }
            if let deeper = wholeMedia(under: child) {
                IOObjectRelease(child)
                return deeper
            }
            IOObjectRelease(child)
        }
        return nil
    }

    // MARK: - Volumes

    /// The biggest mounted volume on each drive, keyed by the drive's registry entry ID.
    ///
    /// "Biggest" is doing real work here. A Mac mounts seven volumes from one APFS container —
    /// Macintosh HD, Data, VM, Preboot, Update, xART, iSCPreboot — and picking the first would
    /// report the drive as 3% full because it landed on a 500 MB system volume.
    private static func mountedVolumesByDevice() -> [UInt64: DriveFacts.Fullness] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey,
                                      .volumeAvailableCapacityKey, .volumeIsLocalKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                              options: []) else { return [:] }

        var out: [UInt64: DriveFacts.Fullness] = [:]
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsLocal == true,
                  let total = values.volumeTotalCapacity, total > 0,
                  let free = values.volumeAvailableCapacity,
                  let device = deviceID(forVolumeAt: url) else { continue }

            let fullness = DriveFacts.Fullness(volumeName: values.volumeName ?? "Untitled",
                                               totalBytes: Int64(total),
                                               freeBytes: Int64(free))
            if let existing = out[device], existing.totalBytes >= fullness.totalBytes { continue }
            out[device] = fullness
        }
        return out
    }

    /// The block device a mounted volume actually lives on.
    ///
    /// Three steps, and each one exists because of a real shape on a real Mac:
    ///
    /// 1. `statfs` gives "/dev/disk3s1s1" for `/` — a **snapshot** of a volume inside a synthesised
    ///    APFS container, which is what macOS boots from.
    /// 2. A snapshot has no `IOMedia` of its own, so the trailing `sN` segments are dropped one at
    ///    a time until something matches: disk3s1s1 → disk3s1 → disk3.
    /// 3. From there the parent chain is walked up to the first real block device —
    ///    AppleAPFSMedia → container scheme → disk0s2 → partition scheme → disk0 → the NVMe device.
    ///
    /// ⚠️ A Fusion Drive's container spans two devices, and this returns whichever one the chain
    /// reaches. The volume is then attributed to one of the two drives rather than to both, which
    /// is wrong in a way nobody can see and right in the way that matters: both drives are still
    /// listed and both are still health-checked.
    private static func deviceID(forVolumeAt url: URL) -> UInt64? {
        guard var name = bsdName(forVolumeAt: url) else { return nil }

        while !name.isEmpty {
            let media = IOServiceGetMatchingService(kIOMainPortDefault,
                                                    IOBSDNameMatching(kIOMainPortDefault, 0, name))
            if media != IO_OBJECT_NULL {
                defer { IOObjectRelease(media) }
                return blockDevice(above: media)
            }
            guard let cut = name.range(of: "s", options: .backwards),
                  cut.lowerBound != name.startIndex else { return nil }
            name = String(name[..<cut.lowerBound])
        }
        return nil
    }

    private static func bsdName(forVolumeAt url: URL) -> String? {
        var info = statfs()
        guard statfs(url.path, &info) == 0 else { return nil }
        let device = withUnsafePointer(to: &info.f_mntfromname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
        guard device.hasPrefix("/dev/") else { return nil }
        return String(device.dropFirst("/dev/".count))
    }

    private static func blockDevice(above media: io_service_t) -> UInt64? {
        var entry = media
        IOObjectRetain(entry)
        while entry != IO_OBJECT_NULL {
            if IOObjectConformsTo(entry, "IOBlockStorageDevice") != 0 {
                let id = entryID(entry)
                IOObjectRelease(entry)
                return id
            }
            var parent: io_service_t = IO_OBJECT_NULL
            let result = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent)
            IOObjectRelease(entry)
            guard result == KERN_SUCCESS else { return nil }
            entry = parent
        }
        return nil
    }
}

// MARK: - SMART, the two plug-ins

extension DriveReader {

    // The CFPlugIn UUIDs. Functions rather than stored constants: `CFUUID` is not `Sendable`, so a
    // global `let` of one is main-actor isolated under Swift 6 and unusable from a reader that has
    // to run off the main thread.
    private static func uuid(_ b: [UInt8]) -> CFUUID {
        CFUUIDGetConstantUUIDWithBytes(nil, b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                                       b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])
    }
    private static func plugInInterfaceID() -> CFUUID {
        uuid([0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4,
              0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F])
    }
    private static func nvmeUserClientTypeID() -> CFUUID {
        uuid([0xAA, 0x0F, 0xA6, 0xF9, 0xC2, 0xD6, 0x45, 0x7F,
              0xB1, 0x0B, 0x59, 0xA1, 0x32, 0x53, 0x29, 0x2F])
    }
    private static func nvmeInterfaceID() -> CFUUID {
        uuid([0xCC, 0xD1, 0xDB, 0x19, 0xFD, 0x9A, 0x4D, 0xAF,
              0xBF, 0x95, 0x12, 0x45, 0x4B, 0x23, 0x0A, 0xB6])
    }
    private static func ataUserClientTypeID() -> CFUUID {
        uuid([0x24, 0x51, 0x4B, 0x7A, 0x28, 0x04, 0x11, 0xD6,
              0x8A, 0x02, 0x00, 0x30, 0x65, 0x70, 0x48, 0x66])
    }
    private static func ataInterfaceID() -> CFUUID {
        uuid([0x08, 0xAB, 0xE2, 0x1C, 0x20, 0xD4, 0x11, 0xD6,
              0x8D, 0xF6, 0x00, 0x03, 0x93, 0x5A, 0x76, 0xB2])
    }

    /// **`IONVMeSMARTInterface`, hand-declared.**
    ///
    /// ⚠️ `NVMeSMARTLibExternal.h` ships in the macOS SDK but is **not in IOKit's module map**, so
    /// Swift cannot import it and there is no bridging header in this target to put it in. The
    /// alternative to declaring the interface here is not having drive wear at all.
    ///
    /// Only the leading fields are declared — the COM guts, the version pair and the one function
    /// actually called. Everything after `SMARTReadData` is left off deliberately: a shorter
    /// declaration cannot be wrong about fields it does not have, and the offsets of the fields it
    /// does have are checked at run time by `layoutMatchesC()` before a single call is made
    /// through it.
    private struct NVMeSMARTInterface {
        var _reserved: UnsafeMutableRawPointer?
        var QueryInterface: (@convention(c) (UnsafeMutableRawPointer?, CFUUIDBytes,
                                             UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> HRESULT)?
        var AddRef: (@convention(c) (UnsafeMutableRawPointer?) -> ULONG)?
        var Release: (@convention(c) (UnsafeMutableRawPointer?) -> ULONG)?
        var version: UInt16
        var revision: UInt16
        var SMARTReadData: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> IOReturn)?
    }

    /// Whether the struct above lands where the C header says it does.
    ///
    /// ⚠️ **This is a real guard, not a formality.** Swift does not promise C layout for its own
    /// structs; it happens to lay this one out in declaration order with natural alignment, which
    /// is what the C compiler does. If that ever stops being true, calling through the struct would
    /// jump to whatever is at the wrong offset. Checked first, every time: a mismatch means the
    /// wear numbers are simply not read, and the row degrades to Apple's verdict — the same as on a
    /// drive that never offered them.
    private static func layoutMatchesC() -> Bool {
        let layout = MemoryLayout<NVMeSMARTInterface>.self
        return layout.offset(of: \.QueryInterface) == 8
            && layout.offset(of: \.AddRef) == 16
            && layout.offset(of: \.Release) == 24
            && layout.offset(of: \.version) == 32
            && layout.offset(of: \.revision) == 34
            && layout.offset(of: \.SMARTReadData) == 40
    }

    /// The NVMe SMART page for one device, or `nil` where it does not offer one.
    ///
    /// Read-only in the strongest sense available: NVMe's SMART log is a Get Log Page command, and
    /// there is no NVMe equivalent of the ATA call that would switch SMART on. Nothing here can
    /// change the drive.
    ///
    /// Byte offsets are from NVM Express 1.4 §5.14.1.2 (SMART / Health Information log), read out
    /// of a raw buffer rather than into a mirrored C struct. `NVMeSMARTData` has a `uint16_t` at
    /// offset 1 followed by single bytes — a packed layout that a Swift struct would silently pad,
    /// and reading `PERCENTAGE_USED` from the wrong offset is how a healthy drive gets reported at
    /// 200% worn.
    private static func nvmeWear(_ device: io_service_t) -> DriveFacts.Wear? {
        guard flag(property(device, "NVMe SMART Capable")) == true, layoutMatchesC() else { return nil }

        var plugIn: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0
        guard IOCreatePlugInInterfaceForService(device, nvmeUserClientTypeID(), plugInInterfaceID(),
                                                &plugIn, &score) == KERN_SUCCESS,
              let plugIn, let plugInInterface = plugIn.pointee else { return nil }
        defer { IODestroyPlugInInterface(plugIn) }

        var raw: UnsafeMutableRawPointer?
        let queried = withUnsafeMutablePointer(to: &raw) { pointer -> HRESULT in
            plugInInterface.pointee.QueryInterface(plugIn,
                                                   CFUUIDGetUUIDBytes(nvmeInterfaceID()),
                                                   pointer)
        }
        guard queried == S_OK, let raw else { return nil }

        let smart = raw.assumingMemoryBound(to: UnsafeMutablePointer<NVMeSMARTInterface>?.self)
        defer { _ = smart.pointee?.pointee.Release?(raw) }

        guard let readData = smart.pointee?.pointee.SMARTReadData else { return nil }
        var page = [UInt8](repeating: 0, count: 512)
        let result = page.withUnsafeMutableBytes { readData(raw, $0.baseAddress) }
        guard result == kIOReturnSuccess else { return nil }

        // The counters are 128-bit little-endian; the low 64 bits are read and the high 64 ignored.
        // A drive would have to write 8 zettabytes or run for two thousand million years to
        // overflow one, so the loss is theoretical, and a 128-bit integer here would buy nothing a
        // person could read.
        func low64(_ offset: Int) -> UInt64 {
            (0..<8).reduce(UInt64(0)) { $0 | UInt64(page[offset + $1]) << (8 * UInt64($1)) }
        }

        return DriveFacts.Wear(criticalWarning: page[0],
                               availableSpare: page[3],
                               spareThreshold: page[4],
                               percentageUsed: page[5],
                               powerOnHours: low64(128),
                               powerCycles: low64(112),
                               unsafeShutdowns: low64(144),
                               mediaErrors: low64(160),
                               dataUnitsWritten: low64(48))
    }

    /// ATA's own answer to "has this drive exceeded a threshold" — `true` means failing.
    ///
    /// This is where Apple's "S.M.A.R.T. status: Failing" comes from on a SATA drive, and SATA is
    /// what the 2019 and 2020 iMacs shipped with: spinning disks and Fusion Drives, the drives that
    /// still genuinely die. `IOATASMARTInterface` is imported from the SDK — unlike the NVMe one,
    /// `ATASMARTLib.h` **is** in IOKit's module map, so nothing is hand-declared here.
    ///
    /// ⚠️ **`SMARTEnableDisableOperations` is deliberately never called.** It would turn SMART on
    /// for a drive that has it off — a change to somebody's hardware settings, made silently, by a
    /// read-only health check, to get a number. A drive with SMART disabled is reported as not
    /// answering, which is the truth.
    ///
    /// ⚠️ **Untested against real hardware.** Nobody on this project has a SATA Mac; the failure
    /// path (return `nil`, report "not reported") is the one that runs on every machine it has
    /// been tried on.
    private static func ataThresholdExceeded(_ device: io_service_t) -> Bool? {
        guard flag(property(device, kIOPropertySMARTCapableKey)) == true else { return nil }

        var plugIn: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0
        guard IOCreatePlugInInterfaceForService(device, ataUserClientTypeID(), plugInInterfaceID(),
                                                &plugIn, &score) == KERN_SUCCESS,
              let plugIn, let plugInInterface = plugIn.pointee else { return nil }
        defer { IODestroyPlugInInterface(plugIn) }

        var raw: UnsafeMutableRawPointer?
        let queried = withUnsafeMutablePointer(to: &raw) { pointer -> HRESULT in
            plugInInterface.pointee.QueryInterface(plugIn,
                                                   CFUUIDGetUUIDBytes(ataInterfaceID()),
                                                   pointer)
        }
        guard queried == S_OK, let raw else { return nil }

        let smart = raw.assumingMemoryBound(to: UnsafeMutablePointer<IOATASMARTInterface>?.self)
        defer { _ = smart.pointee?.pointee.Release?(raw) }

        var exceeded: DarwinBoolean = false
        guard let status = smart.pointee?.pointee.SMARTReturnStatus,
              status(raw, &exceeded) == kIOReturnSuccess else { return nil }
        return exceeded.boolValue
    }
}

// MARK: - The failing screen

/// **What Wellkept shows a person whose drive has just told them it is failing.**
///
/// Two steps, in order, and nothing else. This screen is not where the app demonstrates how much
/// it knows: somebody reading it has minutes or days of working drive left, and every extra line
/// competes with "copy your files off".
///
/// The rules it is built to, all of them checkable by reading the strings below:
///
/// - **Apple's verdict is quoted, never paraphrased.** `verdictQuote` is the word the drive's own
///   check produced, in quotation marks, so a person can match it against what Disk Utility says.
/// - **No component is named and no price is quoted.** We do not know what is wrong inside the
///   enclosure and we do not know what anybody charges. Guessing either would be the app pretending
///   to be a repair estimate.
/// - **The word "failing" is used because the drive used it**, not because we decided.
/// - **The serial number is carried, not shown**, so the second step can hand it over when a person
///   is on the phone — with the same `sensitive` flag the repair-shop copy honours.
struct DriveAlarm: Sendable, Hashable, Identifiable {

    /// One of the two things to do, with the one control that does it.
    struct Step: Sendable, Hashable, Identifiable {
        /// The button's words, or `nil` for a step that is a sentence and no button — which is what
        /// an external drive's second step is, because we do not know who made it.
        let title: String?
        /// The one line saying what this step is for.
        let sentence: String
        /// A section of this app to go to.
        let section: SectionID?
        /// Somewhere outside the app.
        let url: URL?

        var id: String { sentence }
    }

    let id: UInt64
    /// What to call the drive: its volume name, or its model.
    let driveName: String
    let isStartupDrive: Bool
    /// Apple's own word, quoted: "Failing".
    let verdictQuote: String
    /// The row's sentence, quoting that word.
    let headline: String
    /// Exactly two, in the order they must be done.
    let steps: [Step]
    /// Ready for the second step. `nil` on a drive that reports none.
    let serialNumber: String?
    /// Model and serial in one line, for reading down a telephone.
    let identification: String

    init(_ drive: DriveFacts) {
        self.id = drive.id
        self.driveName = drive.displayName
        self.isStartupDrive = drive.isStartupDrive
        self.verdictQuote = drive.verdict.appleWord ?? "Failing"
        self.headline = drive.verdictSentence
        self.serialNumber = drive.serialNumber
        self.identification = [drive.model, drive.serialNumber]
            .compactMap { $0 }
            .joined(separator: " · ")

        let copyOff = Step(
            title: "Open Backup",
            sentence: drive.isStartupDrive
                ? "Copy your files off this Mac now, before the drive stops answering."
                : "Copy your files off “\(drive.displayName)” now, before it stops answering.",
            section: .backup,
            url: nil)

        // Apple can only help with the drive Apple sold. For a drive in somebody else's case,
        // sending a person to Apple Support wastes the one afternoon they have.
        let getItReplaced = drive.isStartupDrive
            ? Step(title: "Contact Apple Support",
                   sentence: "Apple Support can tell you what happens next. Have the serial number ready.",
                   section: nil,
                   url: URL(string: "https://support.apple.com/repair"))
            : Step(title: nil,
                   sentence: "This drive is not part of your Mac. Whoever made it can tell you whether it is still under warranty.",
                   section: nil,
                   url: nil)

        self.steps = [copyOff, getItReplaced]
    }
}

// MARK: - Drives that do not exist

/// **Invented drives, for demo mode and for the screenshots.**
///
/// ⚠️ The failing screen is the one screen in this section that must be right and that has never
/// run against a real fault — nobody is going to break a drive to look at it. These exist so it can
/// be drawn, argued about and photographed on a Mac whose drive is fine:
///
/// ```swift
/// DriveReader.reading(for: [DriveFacts.exampleFailing])   // the problem row
/// DriveReader.alarm(for: [DriveFacts.exampleFailing])     // the two steps
/// ```
///
/// Nothing here is read from any machine. The numbers are shaped like a real drive's — a four-year
/// old 512 GB SSD — because round numbers in a screenshot teach nothing about how the row will read.
extension DriveFacts {

    /// A healthy internal SSD, three years in. The Mac the product is for.
    static let exampleHealthy = DriveFacts(
        id: 1,
        bsdName: "disk0",
        model: "APPLE SSD AP0512Z",
        vendor: nil,
        serialNumber: "0000000000000000",
        firmwareRevision: "561.100.",
        capacityBytes: 500_277_792_768,
        connection: .internalDrive,
        mediumType: "Solid State",
        isRemovable: false,
        isStartupDrive: true,
        verdict: .verified,
        wear: Wear(criticalWarning: 0,
                   availableSpare: 100,
                   spareThreshold: 99,
                   percentageUsed: 4,
                   powerOnHours: 9_140,
                   powerCycles: 812,
                   unsafeShutdowns: 26,
                   mediaErrors: 0,
                   dataUnitsWritten: 168_400_000),
        fullness: Fullness(volumeName: "Macintosh HD",
                           totalBytes: 494_384_795_648,
                           freeBytes: 141_000_000_000))

    /// The same drive, declaring a fault: spare blocks exhausted and reliability degraded — the two
    /// bits that make Apple's own check print "Failing".
    static let exampleFailing = DriveFacts(
        id: 2,
        bsdName: "disk0",
        model: "APPLE SSD AP0512Z",
        vendor: nil,
        serialNumber: "0000000000000000",
        firmwareRevision: "561.100.",
        capacityBytes: 500_277_792_768,
        connection: .internalDrive,
        mediumType: "Solid State",
        isRemovable: false,
        isStartupDrive: true,
        verdict: .failing,
        wear: Wear(criticalWarning: 0x05,
                   availableSpare: 3,
                   spareThreshold: 10,
                   percentageUsed: 118,
                   powerOnHours: 41_600,
                   powerCycles: 3_140,
                   unsafeShutdowns: 214,
                   mediaErrors: 1_042,
                   dataUnitsWritten: 1_240_000_000),
        fullness: Fullness(volumeName: "Macintosh HD",
                           totalBytes: 494_384_795_648,
                           freeBytes: 63_000_000_000))

    /// A USB drive that keeps its health check to itself — the normal case for anything in a cheap
    /// enclosure, and the one that proves "not reported" is not a fault.
    static let exampleExternal = DriveFacts(
        id: 3,
        bsdName: "disk4",
        model: "Samsung PSSD T7 Shield",
        vendor: "Samsung",
        serialNumber: nil,
        firmwareRevision: nil,
        capacityBytes: 2_000_398_934_016,
        connection: .usb,
        mediumType: "Solid State",
        isRemovable: true,
        isStartupDrive: false,
        verdict: .notReported,
        wear: nil,
        fullness: Fullness(volumeName: "Backup T7",
                           totalBytes: 2_000_000_000_000,
                           freeBytes: 640_000_000_000))
}

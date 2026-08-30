import AppKit
import Foundation
import IOKit
import SystemConfiguration
import WellkeptCore

//  MachineReader.swift
//  Wellkept — App/Hardware
//
//  **What this Mac is** — the block at the top of the Hardware section, and the text a person can
//  hand to a repair shop.
//
//  ## Inventory, never a verdict
//
//  Nothing in this file can produce a `Reading`, and that is deliberate. `MachineFacts` carries no
//  status because there is no arrangement of a name, a model and a chip that constitutes a fault:
//  a 2019 iMac is not broken for being a 2019 iMac. The five diagnosed topics — drive, battery,
//  memory, restarts, speed — belong to the four readers and to `SpeedTest`. This block is the
//  identification card they sit under.
//
//  The one exception is not really an exception. `MachineFacts.standing(asOf:)` says whether Apple
//  still ships security fixes for what this Mac can run, and only the case where those fixes have
//  actually stopped is ever promoted to a problem. Decided 2026-08-27: *"Not about fear, it is about
//  security. Why not be honest? We are not selling them a new machine, we are protecting them."*
//  So the sentence is framed as security, it never counts down to a month, and it never suggests
//  buying anything. The promotion happens inside `HardwareReport`; this file only supplies the
//  facts it reasons about.
//
//  ## Where each fact comes from, and what it costs
//
//  | Fact | Source | Permission |
//  |---|---|---|
//  | Name | `SCDynamicStoreCopyComputerName` — the name in Sharing settings | none |
//  | Model identifier | `sysctl hw.model`, then the IORegistry | none |
//  | Marketing name | `MacModels`, the shipped table | none |
//  | Chip | `sysctl machdep.cpu.brand_string` (+ core count and clock on Intel) | none |
//  | Memory | `ProcessInfo.physicalMemory` | none |
//  | Drive size | the root volume's total capacity | none |
//  | macOS | `ProcessInfo.operatingSystemVersion` | none |
//  | In use since | when Setup Assistant finished, else when this account was made | none |
//  | Serial number | IORegistry, `IOPlatformExpertDevice` | none |
//
//  **None of it needs Full Disk Access**, which is the whole section's promise to somebody who
//  tapped "Finish later". Nothing here launches a subprocess either: `system_profiler` takes
//  seconds, prints more than is asked for, and is a spawn a hardened-runtime app does not need to
//  make to learn its own model number.
//
//  ## ⚠️ Two units, on purpose
//
//  Memory is reported in **binary** GB and the drive in **decimal** GB, because that is how each
//  one is sold and how macOS itself reports it: 8,589,934,592 bytes of RAM is "8 GB", and a drive
//  of 494,384,795,648 bytes is "494 GB". Using one unit for both would make one of the two rows
//  disagree with System Information on the same machine, and a person checking us against Apple
//  finds the disagreement before they find anything else we got right.

enum MachineReader {

    // MARK: - The whole block

    /// Read everything in the "what this Mac is" block.
    ///
    /// Cheap enough to call on every check — a handful of `sysctl` calls, one IORegistry lookup and
    /// two `stat`s — and free of side effects, so it is safe from any thread and safe to call
    /// twice.
    static func read() -> MachineFacts {
        let virtual = VirtualMachine.current
        let identifier = modelIdentifier(preferring: virtual.hardwareModel)
        let version = ProcessInfo.processInfo.operatingSystemVersion

        return MachineFacts(
            name: computerName(),
            modelName: MacModels.marketingName(for: identifier) ?? identifier,
            modelIdentifier: identifier,
            chip: chipName(),
            memory: memoryText(bytes: ProcessInfo.processInfo.physicalMemory),
            driveSize: driveSizeText(),
            systemVersion: systemVersionText(version),
            systemMajorVersion: version.majorVersion,
            inUseSince: inUseSince(),
            serialNumber: serialNumber(),
            isVirtualMachine: virtual.isVirtual
        )
    }

    // MARK: - Name

    /// What the Mac calls itself: the name in Sharing settings, "Ada's MacBook Air".
    ///
    /// `ProcessInfo.hostName` is the fallback rather than the first choice because it returns the
    /// Bonjour name — "Adas-MacBook-Air.local" — which is the same fact with the apostrophes and
    /// spaces beaten out of it. The `.local` suffix is dropped so the fallback at least reads like
    /// a name.
    static func computerName() -> String {
        if let name = SCDynamicStoreCopyComputerName(nil, nil) as String?,
           !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name
        }
        let host = ProcessInfo.processInfo.hostName
        let trimmed = host.hasSuffix(".local") ? String(host.dropLast(6)) : host
        return trimmed.isEmpty ? "This Mac" : trimmed
    }

    // MARK: - Model

    /// "Mac15,13".
    ///
    /// `VirtualMachine` has already read `hw.model` to decide whether this is a guest, so the value
    /// is passed in rather than read twice — and inside a guest it is the string that gave the
    /// guest away, which is exactly what should be shown.
    ///
    /// The IORegistry is the fallback for the one case `sysctl` does not cover: a machine where
    /// `hw.model` comes back empty. The property there is a `CFData` holding a C string, trailing
    /// NUL included, and an identifier carrying an invisible extra character matches nothing in
    /// `MacModels`.
    static func modelIdentifier(preferring model: String) -> String {
        if !model.isEmpty { return model }
        return platformProperty("model") ?? "Unknown"
    }

    // MARK: - Chip

    /// "Apple M3", or "2.3 GHz 8-Core Intel Core i9-9880H".
    ///
    /// Apple silicon needs no help: the brand string is already the marketing name of the chip.
    /// Intel's is a part number with decoration — `Intel(R) Core(TM) i9-9880H CPU @ 2.30GHz` — so
    /// it is recomposed into the shape System Information uses, with the core count and the clock
    /// in front. The SKU is kept, unlike Apple's own row: it is one of the two things a repair shop
    /// asks for, and dropping it to look tidier would make this block worse at the job it exists
    /// for.
    static func chipName() -> String {
        let brand = (VirtualMachine.sysctlString("machdep.cpu.brand_string") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !brand.isEmpty else { return "Not reported" }

        // Apple silicon: "Apple M3" is already the answer.
        guard brand.lowercased().contains("intel") else { return brand }

        var name = brand
            .replacingOccurrences(of: "(R)", with: "")
            .replacingOccurrences(of: "(TM)", with: "")
        var clock: String?

        // "… CPU @ 2.30GHz" — the tail is the clock, and it is the only place some Intel Macs
        // report it at all: `hw.cpufrequency` returns 0 on several of them.
        if let at = name.range(of: " CPU @ ") ?? name.range(of: " @ ") {
            clock = tidyClock(String(name[at.upperBound...]))
            name = String(name[..<at.lowerBound])
        } else if let hertz = VirtualMachine.sysctlInt("hw.cpufrequency"), hertz > 0 {
            clock = tidyClock("\(Double(hertz) / 1_000_000_000) GHz")
        }

        name = name.split(separator: " ").joined(separator: " ")

        let cores = VirtualMachine.sysctlInt("hw.physicalcpu").flatMap { $0 > 0 ? "\($0)-Core" : nil }
        return [clock, cores, name].compactMap { $0 }.joined(separator: " ")
    }

    /// "2.30GHz" → "2.3 GHz". A trailing zero on a clock speed is noise, and Apple does not print
    /// one either.
    private static func tidyClock(_ raw: String) -> String? {
        let text = raw.replacingOccurrences(of: "GHz", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(text), value > 0 else { return nil }
        let rounded = (value * 10).rounded() / 10
        let formatted = rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
        return "\(formatted) GHz"
    }

    // MARK: - Memory and drive

    /// Installed memory, in the binary GB every Mac is sold in: "8 GB", "36 GB".
    static func memoryText(bytes: UInt64) -> String {
        guard bytes > 0 else { return "Not reported" }
        let gigabytes = Double(bytes) / 1_073_741_824
        // RAM comes in whole binary gigabytes. A fraction here means the number was measured
        // rather than reported, so it is shown rather than rounded away.
        if abs(gigabytes - gigabytes.rounded()) < 0.01 {
            return "\(Int(gigabytes.rounded())) GB"
        }
        return String(format: "%.1f GB", gigabytes)
    }

    /// The size of the drive this Mac started from, in the decimal GB it was sold in.
    ///
    /// The root volume's total capacity is the APFS container's capacity, which is the whole drive
    /// — not the slice the system volume happens to be using. `nil` becomes the house phrase rather
    /// than a zero: reporting "0 GB" because we could not look is the one thing this section never
    /// does.
    static func driveSizeText() -> String {
        let root = URL(fileURLWithPath: "/", isDirectory: true)
        guard let values = try? root.resourceValues(forKeys: [.volumeTotalCapacityKey]),
              let bytes = values.volumeTotalCapacity, bytes > 0 else {
            return Unreadable.notReported.sentence
        }
        return capacityText(bytes: Int64(bytes))
    }

    /// "494 GB", "1 TB", "2 TB" — decimal, the way drives are sold and the way Finder counts.
    static func capacityText(bytes: Int64) -> String {
        let gigabytes = Double(bytes) / 1_000_000_000
        if gigabytes >= 999.5 {
            let terabytes = gigabytes / 1_000
            let rounded = (terabytes * 10).rounded() / 10
            return rounded == rounded.rounded()
                ? "\(Int(rounded)) TB"
                : String(format: "%.1f TB", rounded)
        }
        return "\(Int(gigabytes.rounded())) GB"
    }

    // MARK: - macOS

    /// "macOS 26.6.2", or "macOS 26.6" where there is no patch.
    ///
    /// Built from the numbers rather than from `operatingSystemVersionString`, which is
    /// "Version 26.6.2 (Build 25G100)" — a build number nobody asked for, in a shape that changes
    /// between releases.
    static func systemVersionText(_ version: OperatingSystemVersion) -> String {
        version.patchVersion == 0
            ? "macOS \(version.majorVersion).\(version.minorVersion)"
            : "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    // MARK: - In use since

    /// When this Mac was first set up, as well as it can honestly be told.
    ///
    /// There is no interface that answers this. Two file dates come close, in this order:
    ///
    /// 1. **`/private/var/db/.AppleSetupDone`** — written the moment Setup Assistant finished. This
    ///    is the real answer when it exists, and it is a `stat` on a world-executable directory, so
    ///    no permission is involved.
    /// 2. **The home folder's creation date** — when this account was made. On a Mac with one
    ///    account these are days apart; on a second-hand Mac the account date is arguably the more
    ///    useful of the two anyway.
    ///
    /// Anything before 2000 or in the future is discarded rather than shown. A clock that has been
    /// wrong, a restored backup or a filesystem with no creation date all produce a date that is
    /// obviously nonsense, and `MachineFacts` treats `nil` as "we do not know" — which is a real
    /// answer, where 1970 is a bug we printed.
    static func inUseSince(now: Date = Date()) -> Date? {
        let candidates = ["/private/var/db/.AppleSetupDone", NSHomeDirectory()]
        for path in candidates {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  let created = attributes[.creationDate] as? Date,
                  plausible(created, now: now) else { continue }
            return created
        }
        return nil
    }

    private static func plausible(_ date: Date, now: Date) -> Bool {
        guard date <= now else { return false }
        var components = DateComponents()
        components.year = 2000
        let floor = Calendar(identifier: .gregorian).date(from: components) ?? .distantPast
        return date >= floor
    }

    // MARK: - Serial number

    /// The serial number engraved on the machine, or `nil`.
    ///
    /// `nil` is common and normal: a virtual machine usually has none, and a board that has been
    /// replaced sometimes reports an empty string. `MachineFacts` omits the row entirely rather
    /// than printing a placeholder, which is why nothing here invents one.
    static func serialNumber() -> String? {
        platformProperty(kIOPlatformSerialNumberKey)
    }

    /// One property of `IOPlatformExpertDevice`, as a string.
    ///
    /// The registry stores some of these as `CFString` and some as `CFData` holding a C string, and
    /// which is which is not documented anywhere that stays true. Both are handled, and the data
    /// case stops at the NUL rather than decoding the terminator into the string.
    private static func platformProperty(_ key: String) -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("IOPlatformExpertDevice"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        guard let raw = IORegistryEntryCreateCFProperty(service, key as CFString,
                                                        kCFAllocatorDefault, 0)?
            .takeRetainedValue() else { return nil }

        let text: String?
        if let string = raw as? String {
            text = string
        } else if let data = raw as? Data {
            text = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
        } else {
            text = nil
        }

        guard let cleaned = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cleaned.isEmpty else { return nil }
        return cleaned
    }
}

// MARK: - Copy for a repair shop

/// **The text of the "copy this for a repair shop" button, and the promise that goes with it.**
///
/// ## Why this is a type and not two lines in a view
///
/// The rule is that the person sees **exactly** what is about to be pasted, serial number included,
/// before anything reaches the clipboard. A view that builds a preview string and then builds a
/// clipboard string has two strings that are equal today and will differ the first time somebody
/// edits one of them — and the failure is invisible, because the preview is the only part anybody
/// looks at.
///
/// So there is one string. `text` is what is shown, `copyToPasteboard()` puts that same stored
/// string on the clipboard, and there is no path that composes it a second time.
///
/// Quietly copying an identifying number is precisely the behaviour this app exists to catch other
/// software doing.
struct RepairShopCopy: Sendable, Hashable {

    /// Exactly what will be pasted. Show this, verbatim, before offering the button.
    let text: String

    /// The identifying lines this text contains — a serial number, or anything else marked
    /// `sensitive`. Empty when the person chose to leave them out, or when there were none.
    let sensitive: [DetailPair]

    /// The identifying lines that were left out. Non-empty only when `includeSerial` was `false`.
    let omitted: [DetailPair]

    /// Whether this report has anything identifying in it at all, whether or not it was included.
    /// This is what decides if the screen offers the choice — a Mac that reports no serial number
    /// should not be shown a switch that changes nothing.
    var hasSensitive: Bool { !sensitive.isEmpty || !omitted.isEmpty }

    /// The one line beside the preview naming what is in it. `nil` when nothing identifying is
    /// included, because there is then nothing a person needs told.
    ///
    /// This is explanation, not clutter: the consequence of pressing a button, on the button,
    /// once — DESIGN §12.4.
    var caution: String? {
        guard !sensitive.isEmpty else { return nil }
        // ⚠️ **The label's last segment, not the whole label.** `DriveReader` prefixes every detail
        // with the drive it belongs to once there is more than one drive, so the raw labels here
        // are "Serial number" and "Macintosh HD — Serial number" — and lower-casing those whole
        // produced "This includes the serial number and the macintosh hd — serial number.", which
        // is both ungrammatical and says the same thing twice. What a person needs told is what
        // KIND of identifying line is in the text, once each.
        let kinds = sensitive
            .map { $0.label.split(separator: "—").last.map(String.init) ?? $0.label }
            .map { "the \($0.trimmingCharacters(in: .whitespaces).lowercased())" }
        var seen = Set<String>()
        let names = kinds.filter { seen.insert($0).inserted }
        return "This includes \(joined(names))."
    }

    /// Build the text for one report.
    ///
    /// `includeSerial` is the user's choice, and it is honoured in one place: `clipboardText`
    /// filters on the same `sensitive` flag that decides what `sensitive` and `omitted` list here,
    /// so the summary beside the preview cannot disagree with the preview.
    init(_ report: HardwareReport, includeSerial: Bool = true) {
        self.text = report.clipboardText(includeSerial: includeSerial)

        let identifying = report.facts.detailPairs.filter(\.sensitive)
            + report.readings.flatMap { $0.details.filter(\.sensitive) }
        self.sensitive = includeSerial ? identifying : []
        self.omitted = includeSerial ? [] : identifying
    }

    /// Put it on the clipboard. Returns `false` only if the pasteboard refused it.
    ///
    /// ⚠️ Call this **after** the person has seen `text`, never as part of drawing the screen.
    @MainActor
    @discardableResult
    func copyToPasteboard() -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    /// "a, b and c" — the list in a sentence, not a comma-separated dump.
    private func joined(_ items: [String]) -> String {
        switch items.count {
        case 0:  return ""
        case 1:  return items[0]
        case 2:  return "\(items[0]) and \(items[1])"
        default: return "\(items.dropLast().joined(separator: ", ")) and \(items[items.count - 1])"
        }
    }
}

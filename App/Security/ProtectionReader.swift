import Foundation
import WellkeptCore

//  ProtectionReader.swift
//  Wellkept — App/Security
//
//  **What is protecting this Mac** — the block at the top of the Security section, and the first
//  of its six rows.
//
//  Eight switches and one data version: FileVault · System Integrity Protection · Gatekeeper ·
//  secure boot · the firewall · automatic security updates · automatic login · Lockdown Mode ·
//  XProtect.
//
//  ## Inventory at the top, one verdict underneath
//
//  `ProtectionsBlock` carries no status and cannot say Needs attention — it is the list of what
//  each switch is set to, in the same spirit as the "what this Mac is" block in Hardware. Deciding
//  whether any of it is worth a look happens exactly once, in the `.protections` row, and only
//  through the nine named conditions in `SecurityConcern`. There is no other route: `SecurityRow`
//  computes its own severity from the concerns it was handed.
//
//  ## Where each fact comes from, and what it costs
//
//  Measured by hand on an M3 running macOS 26.6.2, 2026-08-27. Every one is read-only, none raises
//  a dialog, and **not one of them needs Full Disk Access** — this whole block works for somebody
//  who tapped "Finish later".
//
//  | Switch | Source | Notes |
//  |---|---|---|
//  | FileVault | `diskutil info -plist /System/Volumes/Data`, key `FileVault` | A boolean, so nothing to mistranslate |
//  | System Integrity Protection | `csr_get_active_config()` via `dlsym` | Returns the exact bitmask, so a partly-disabled Mac can be described exactly |
//  | Gatekeeper | `spctl --status` | The one place we read English words; `spctl` does not translate them |
//  | Secure boot | `system_profiler SPiBridgeDataType -json`, `ibridge_secure_boot` | ⚠️ **Localized value** — goes through `AppleWords` |
//  | Firewall | `system_profiler SPFirewallDataType -json` | One call, structured, ~70 ms |
//  | Automatic security updates | `/Library/Preferences/com.apple.SoftwareUpdate.plist` | World-readable; the managed copy is read first |
//  | Automatic login | `/Library/Preferences/com.apple.loginwindow.plist`, key `autoLoginUser` | World-readable |
//  | Lockdown Mode | — | **Nothing reports it. Anywhere.** |
//  | XProtect | `/Library/Apple/System/Library/CoreServices/XProtect.bundle` | Version 5357 here, data written 21 Aug |
//
//  The two `system_profiler` reporters are fetched in **one** spawn — `system_profiler
//  SPFirewallDataType SPiBridgeDataType -json` returns both top-level keys, verified today.
//
//  ## ⚠️ The four things this file is careful not to say
//
//  1. **The firewall preference file every article names is gone in macOS 26.** `com.apple.alf` no
//     longer exists as a readable property list on this Mac. Code that reads it does not fail
//     loudly — it reports a firewall that is off, on a Mac whose firewall is on. A confident wrong
//     answer about a security switch is worse than no answer, and it is why this reader spawns a
//     tool instead of opening a file.
//  2. **Lockdown Mode is never "off".** Apple publishes no state for it — not a preference, not an
//     API, not a reporter. The row says this Mac does not report it, and the check stays complete,
//     because no permission on earth would change that.
//  3. **We can say the disk is locked. We cannot say whether there is a key.** Whether a FileVault
//     recovery key exists, and which accounts can unlock this Mac, both need an administrator
//     password — so both are `.notGrantable` details rather than silent absences. That is the fact
//     that matters most about FileVault, it is the one we cannot get, and saying so is better than
//     a row that quietly implies we checked.
//  4. **The boot-security block is Apple silicon and T2 only, and nobody has run it on Intel** —
//     which this app ships to. An iMac 19,1 or 20,1 has no controller chip and reports no
//     `SPiBridgeDataType` at all. That path returns "this Mac does not report it" rather than a
//     guess. ⚠️ **Untested against real Intel hardware; nobody in this project owns one that can
//     run macOS 14.**
//
//  ## ⚠️ And the one it is careful not to imply
//
//  Never the words "you should". Anywhere in this file. The FileVault sentence is the single piece
//  of advice in this whole app that can cost somebody every file they own — turn encryption on,
//  lose the recovery key, lose the lot — so it states what a recovery key is for and stops. The
//  person decides.

enum ProtectionReader {

    // MARK: - What one run produced

    /// The block for the top of the section, and the `.protections` row beneath it.
    struct Result: Sendable, Hashable {
        /// Inventory. Never a verdict.
        let block: ProtectionsBlock
        /// The row, with whatever concerns the block's switches raised.
        let row: SecurityRow
    }

    /// **Read every protection on this Mac.**
    ///
    /// Blocking — three short-lived tools and a handful of property lists, about 400 ms altogether
    /// on this Mac. Call it off the main thread. Free of side effects, so it is safe from any
    /// thread and safe to call twice.
    static func read(timeout: TimeInterval = 8,
                     fileManager: FileManager = .default) -> Result {

        // One spawn for both reporters. Verified 2026-08-27: passing two data types returns one
        // JSON object with one top-level key each.
        let profiler = systemProfiler(["SPFirewallDataType", "SPiBridgeDataType"], timeout: timeout)
        let firewallItem = (profiler?["SPFirewallDataType"] as? [[String: Any]])?.first
        let controllerItem = (profiler?["SPiBridgeDataType"] as? [[String: Any]])?.first

        let managed = ManagedMac.read(controller: controllerMDM(controllerItem),
                                      fileManager: fileManager)

        let readings = [
            fileVault(volume: fileVaultVolume(timeout: timeout)),
            systemProtection(config: systemProtectionConfig()),
            gatekeeper(spctlOutput: gatekeeperStatus(timeout: timeout)),
            secureBoot(controller: controllerItem),
            firewall(item: firewallItem),
            automaticSecurityUpdates(settings: propertyList(at: softwareUpdateSettings),
                                     managed: propertyList(at: managedSoftwareUpdateSettings)),
            automaticLogin(settings: propertyList(at: loginWindowSettings),
                           hasStoredPassword: fileManager.fileExists(atPath: storedLoginPassword.path)),
            lockdownMode(),
        ]
        // `ProtectionsBlock.init` re-sorts into `ProtectionKind` order, so the order these were
        // written in above is a readability choice and nothing more.

        let xprotect = xprotectData(fileManager: fileManager)

        let block = ProtectionsBlock(protections: readings.map(\.protection),
                                     xprotectVersion: xprotect.version,
                                     xprotectUpdated: xprotect.updated,
                                     isManaged: managed.isManaged)

        var details = readings
            .sorted { $0.kind.rank < $1.kind.rank }
            .flatMap(\.details)
        if let remediator = xprotect.remediatorVersion {
            details.append(DetailPair("XProtect Remediator", remediator))
        }
        details += managed.detailPairs

        let notes = readings.sorted { $0.kind.rank < $1.kind.rank }.flatMap(\.notes)

        return Result(block: block,
                      row: row(block: block,
                               details: details,
                               notes: notes,
                               managedSentence: managed.sentence))
    }

    // MARK: - One switch, as this file reads it

    /// A switch, plus everything the block itself has nowhere to carry.
    ///
    /// `Protection` holds a state and one already-formatted qualifier. That is right for the block,
    /// which is a list, and not enough for the row underneath it — which has an Options disclosure
    /// for the exact figures and a `reason` line for the sentences that qualify what a state means.
    /// So a reader hands back all three and the row assembles them.
    struct ProtectionReading: Sendable, Hashable {

        let kind: ProtectionKind
        let state: ProtectionState

        /// The short clause that sits beside the state in the block: `Protection.detailPair` renders
        /// it as "On — the disk is locked", so it is written lower case and continues the state
        /// word rather than repeating it.
        let detail: String?

        /// Everything more exact, for the row's Options disclosure.
        let details: [DetailPair]

        /// Sentences for the row's `reason`. Shown on the row, never behind a disclosure.
        let notes: [String]

        /// The raw value of a `SystemSettingsPane` case, or `nil`.
        let settingsPane: String?

        /// The one thing a reader is built from.
        ///
        /// ⚠️ **The pane is offered only where this switch is not doing its job.** A block that
        /// sprouts a button beside every protection on a healthy Mac is a screen asking to be
        /// fiddled with, and this section reports rather than fixes. `isProtecting` is asked of the
        /// specific switch because `automaticLogin` runs the other way round — off is its healthy
        /// state — and a rule written in terms of "on" would put a tick beside a Mac that signs
        /// itself in.
        init(_ kind: ProtectionKind,
             _ state: ProtectionState,
             detail: String? = nil,
             details: [DetailPair] = [],
             notes: [String] = [],
             pane: SystemSettingsPane? = nil) {
            self.kind = kind
            self.state = state
            self.detail = detail
            self.details = details
            self.notes = notes
            self.settingsPane = state.isProtecting(kind) == false ? pane?.rawValue : nil
        }

        /// The switch, as the block will hold it. Whether an organisation set it is asked here, in
        /// one place, rather than by each reader.
        var protection: Protection {
            Protection(kind: kind,
                       state: state,
                       detail: detail,
                       setByOrganisation: ManagedMac.sets(kind),
                       settingsPane: settingsPane)
        }

        /// A switch this Mac would not answer about.
        ///
        /// It carries **no Options row of its own**: the block above already prints the house
        /// sentence beside the switch's name, and repeating it two inches lower is the "never say
        /// the same thing twice on one screen" rule broken for no gain. `details` here is for the
        /// things the block cannot say — the Intel firmware password, the word the machine actually
        /// used.
        static func unreadable(_ kind: ProtectionKind,
                               _ why: Unreadable = .notReported,
                               details: [DetailPair] = [],
                               notes: [String] = []) -> ProtectionReading {
            ProtectionReading(kind, .unreadable(why), details: details, notes: notes)
        }
    }

    // MARK: - FileVault

    /// **Is the disk locked?**
    ///
    /// `diskutil info -plist` reports two things that are easy to confuse, and getting them the
    /// wrong way round would report every Apple silicon Mac as protected:
    ///
    /// - `Encryption` — the APFS volume is encrypted. On Apple silicon this is **true whether or
    ///   not FileVault is on**, because the data volume is always encrypted at rest; with FileVault
    ///   off the key simply is not protected by anybody's password. The IORegistry's `Encrypted`
    ///   property says the same thing and is the same trap.
    /// - `FileVault` — the key is protected by a password. **This is the one a person means.**
    ///
    /// So this reads `FileVault` and nothing else.
    ///
    /// ⚠️ Verified only on a Mac with FileVault **on**. Nobody has switched it off to watch what
    /// the key does, and nobody is going to. Where the key is missing entirely the answer is "this
    /// Mac does not report it" rather than a guess in either direction.
    static func fileVault(volume: [String: Any]?) -> ProtectionReading {
        guard let on = volume?["FileVault"] as? Bool else {
            return .unreadable(.fileVault)
        }

        if on {
            return ProtectionReading(
                .fileVault, .on,
                detail: "the disk is locked",
                details: [
                    DetailPair("FileVault recovery key", unreadable: .notGrantable),
                    DetailPair("Who can unlock this Mac", unreadable: .notGrantable),
                ],
                pane: .fileVault)
        }

        return ProtectionReading(
            .fileVault, .off,
            detail: "the disk is not locked",
            notes: [recoveryKeySentence],
            pane: .fileVault)
    }

    /// **The one piece of advice in this app that can cost somebody every file they own.**
    ///
    /// It appears on the row itself, never behind Options, and it never says "you should". John's
    /// decision, 2026-08-27. Turning FileVault on is the right move for most people, and it is also
    /// the move that loses a whole machine's worth of files when the key is gone — and we cannot
    /// see whether a key exists, because that needs an administrator password. So the sentence says
    /// what the key is for, and the person decides.
    static let recoveryKeySentence =
        "Turning FileVault on creates a recovery key. Without that key — or an account that can "
      + "unlock this Mac — encrypted files cannot be got back by anybody, Apple included."

    // MARK: - System Integrity Protection

    /// **Exactly which parts of System Integrity Protection are switched off.**
    ///
    /// `csr_get_active_config` hands back the whole bitmask rather than a yes or a no, which is why
    /// it is worth reaching for a symbol Apple never put in a header: a Mac with only the kernel
    /// debugger allowed and a Mac with the system volume unsealed are both "SIP off" to every tool
    /// that asks the yes-or-no question, and they are not remotely the same machine.
    ///
    /// The state turns on one bit — *protected parts of macOS can be changed* — because that is
    /// what a person means by "SIP is off". Anything else set is `.reduced`. Both raise the same
    /// one of the nine conditions, whose title is the blunt "System Integrity Protection is off",
    /// so the row's own sentence lists precisely what was turned off and is what makes a
    /// partly-disabled Mac read accurately.
    static func systemProtection(config: UInt32?) -> ProtectionReading {
        guard let config else { return .unreadable(.systemProtection) }

        guard config != 0 else {
            return ProtectionReading(.systemProtection, .on)
        }

        let relaxed = csrFlags.filter { config & $0.bit != 0 }.map(\.name)
        let filesystemUnprotected = config & (1 << 1) != 0

        let listed = relaxed.isEmpty
            ? "in a way this Mac does not name"
            : list(relaxed)

        return ProtectionReading(
            .systemProtection,
            filesystemUnprotected ? .off : .reduced,
            detail: relaxed.count == 1
                ? "one of its protections is turned off"
                : "\(relaxed.count) of its protections are turned off",
            details: [DetailPair("System Integrity Protection, turned off", listed)],
            notes: ["System Integrity Protection is not fully on: \(listed). That is done "
                  + "deliberately, from the recovery system, and it cannot happen by accident."])
    }

    /// The bits `csr_get_active_config` returns, and what each one allows, in plain words.
    ///
    /// These are the kernel's own flags, and they have not been renumbered in the ten years the
    /// interface has existed. A bit we have no name for is left out rather than printed as a number
    /// nobody can act on.
    static let csrFlags: [(bit: UInt32, name: String)] = [
        (1 << 0,  "unsigned kernel extensions can load"),
        (1 << 1,  "protected parts of macOS can be changed"),
        (1 << 2,  "one program can attach to another"),
        (1 << 3,  "the kernel can be debugged"),
        (1 << 4,  "Apple's internal settings are allowed"),
        (1 << 5,  "system tracing is unrestricted"),
        (1 << 6,  "startup settings can be rewritten"),
        (1 << 7,  "device configuration is unrestricted"),
        (1 << 8,  "any recovery system may be started"),
        (1 << 9,  "kernel extensions can load without approval"),
        (1 << 10, "the rule about which apps may run can be overridden"),
        (1 << 11, "the system volume's seal is not enforced"),
    ]

    /// The live bitmask, or `nil` on a machine where the symbol is not there.
    ///
    /// ⚠️ **`dlsym`, not a link-time reference.** `csr_get_active_config` is exported by
    /// `libsystem_kernel` and has never been given a public header, so linking against it directly
    /// would be a build that breaks on the day Apple stops exporting it. Looked up by name, its
    /// disappearance is a `nil` and a row saying this Mac does not report it — the honest answer to
    /// a question the machine has stopped answering.
    ///
    /// `-2` is `RTLD_DEFAULT`: search every image already loaded, which is where this lives.
    static func systemProtectionConfig() -> UInt32? {
        typealias GetActiveConfig = @convention(c) (UnsafeMutablePointer<UInt32>) -> Int32
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "csr_get_active_config")
        else { return nil }

        var config: UInt32 = 0
        guard unsafeBitCast(symbol, to: GetActiveConfig.self)(&config) == 0 else { return nil }
        return config
    }

    // MARK: - Gatekeeper

    /// **Are apps checked before they run?**
    ///
    /// `spctl --status` prints `assessments enabled` or `assessments disabled`, plus a second line
    /// about developer-signed apps. It is the one place in this file that compares English words,
    /// and it is safe to: `spctl` is a plain command-line tool whose strings are compiled in and
    /// never translated. `system_profiler`, which *is* translated, has no Gatekeeper reporter at
    /// all — there is no structured route to this.
    ///
    /// **The exception list is a `.notGrantable` detail, not a silent absence.** Which individual
    /// apps have been waved through lives in a database only root can open, and no permission a
    /// person could grant would change that — so the row says we could not see it rather than
    /// implying the list is empty.
    static func gatekeeper(spctlOutput: String?) -> ProtectionReading {
        let line = spctlOutput?
            .split(separator: "\n")
            .first { $0.localizedCaseInsensitiveContains("assessments") }
            .map { $0.lowercased() }

        guard let line else { return .unreadable(.gatekeeper) }

        // ⚠️ "disabled" contains "abled", so the order of these two tests is the whole correctness
        // of the function.
        if line.contains("disabled") {
            return ProtectionReading(.gatekeeper, .off,
                                     detail: "apps are not checked before they run",
                                     details: [gatekeeperExceptions],
                                     pane: .privacyAndSecurity)
        }
        if line.contains("enabled") {
            return ProtectionReading(.gatekeeper, .on,
                                     detail: "apps are checked the first time they run",
                                     details: [gatekeeperExceptions],
                                     pane: .privacyAndSecurity)
        }
        return .unreadable(.gatekeeper)
    }

    /// Apps waved through individually. Root only, and no grant exists that would change it.
    static let gatekeeperExceptions =
        DetailPair("Apps allowed through Gatekeeper individually", unreadable: .notGrantable)

    // MARK: - Secure boot

    /// **Is this Mac verifying, at startup, that macOS is the one Apple signed?**
    ///
    /// ⚠️ **The keys are stable and the values are translated.** `ibridge_secure_boot` reads
    /// `Full Security` here and *Sécurité maximale* on a French Mac — verified against Apple's own
    /// table today — so every value below goes through `AppleWords` and not one is compared as an
    /// English string. `system_profiler` refuses `-AppleLanguages` outright, so asking it in English
    /// is not on the table.
    ///
    /// Two vocabularies are mapped because Apple uses two: T2 Macs say Full / Medium / No Security,
    /// Apple silicon says Full / Reduced / Permissive Security.
    ///
    /// ⚠️ **Apple silicon and T2 only. Untested on Intel**, which this app ships to. An iMac 19,1 or
    /// 20,1 has no controller chip, reports no `SPiBridgeDataType`, and lands on the "this Mac does
    /// not report it" path deliberately rather than by accident. That path also states the Intel
    /// firmware password as unseeable, because on those machines it is the protection this row
    /// would otherwise have been about.
    static func secureBoot(controller: [String: Any]?) -> ProtectionReading {
        guard let raw = controller?["ibridge_secure_boot"] as? String,
              !raw.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .unreadable(.secureBoot,
                               details: [DetailPair("Startup firmware password",
                                                    unreadable: .notGrantable)])
        }

        let policy = bootPolicyDetails(controller: controller)
        let meaning = AppleWords.meaning(of: raw, from: .controller, keys: secureBootKeys)

        // ⚠️ Where a language collapses two levels onto one word, take the **less** secure reading
        // and say the doubt out loud — the rule `BatteryReader` already follows. Guessing the
        // flattering side of an ambiguity is how a reduced-security Mac reports as fully secure.
        // `SecureBootLevel.allCases` is ordered least secure first so that `first` is that rule.
        guard let level = SecureBootLevel.allCases.first(where: meaning.couldBe) else {
            // The machine said something Apple's own table has never produced. Show what it said
            // rather than a blank, and claim nothing about it.
            return .unreadable(.secureBoot,
                               details: [DetailPair("Secure boot, as this Mac words it", raw)] + policy)
        }

        var notes: [String] = []
        if meaning.isAmbiguous {
            notes.append("This Mac's language uses one word for more than one secure-boot setting, "
                       + "so this is the safer of the readings it could be.")
        }

        // The level is the block's own qualifier — "On — full security" — so it gets no second row
        // of its own in Options. What goes there is the rest of the boot policy, which the block
        // has nowhere to put.
        guard level != .full else {
            return ProtectionReading(.secureBoot, .on,
                                     detail: level.label.lowercased(),
                                     details: policy,
                                     notes: notes)
        }

        return ProtectionReading(
            .secureBoot,
            level == .unverified ? .off : .reduced,
            detail: level.label.lowercased(),
            details: policy,
            notes: notes + [
                "Secure boot is below full security. That is set from the recovery system and is "
              + "usually done on purpose — to run software Apple does not allow, or an operating "
              + "system that is not macOS."])
    }

    /// How much of the startup chain is verified.
    ///
    /// ⚠️ **Ordered least secure first**, so that taking the first match out of an ambiguity takes
    /// the cautious reading. The order is load-bearing, not cosmetic.
    enum SecureBootLevel: String, CaseIterable, Sendable, Hashable {
        case unverified, permissive, reduced, full

        var label: String {
            switch self {
            case .unverified: "No security"
            case .permissive: "Permissive security"
            case .reduced:    "Reduced security"
            case .full:       "Full security"
            }
        }
    }

    /// Apple's **English keys**, which are the stable half. What appears on the screen is whatever
    /// this Mac's language turns them into, and `AppleWords` runs that backwards.
    static let secureBootKeys: [String: SecureBootLevel] = [
        "Full Security": .full,
        "Medium Security": .reduced,
        "Reduced Security": .reduced,
        "Permissive Security": .permissive,
        "No Security": .unverified,
    ]

    /// The rest of the controller's boot policy, for Options: whether the system volume is still
    /// sealed, and whether any kernel extension may load. Both come back as localized
    /// Enabled/Disabled or Yes/No, so both go through `AppleWords`.
    static func bootPolicyDetails(controller: [String: Any]?) -> [DetailPair] {
        var rows: [DetailPair] = []

        if let sealed = flag(controller?["ibridge_sb_ssv"]) {
            rows.append(DetailPair("Signed system volume",
                                   sealed ? "Sealed — macOS is verified at every startup"
                                          : "Not sealed"))
        }
        if let anyKext = flag(controller?["ibridge_sb_other_kext"]) {
            rows.append(DetailPair("Kernel extensions",
                                   anyKext ? "Any kernel extension may load"
                                           : "Only approved kernel extensions may load"))
        }
        return rows
    }

    // MARK: - Firewall

    /// **Which programs on this Mac may accept a connection from another machine.**
    ///
    /// The mode comes back as Apple's own key — `spfirewall_globalstate_limit_connections` —
    /// which `AppleWords` matches exactly; a future macOS that prints the translated sentence
    /// instead is caught by the same call running the table backwards. See the header for why this
    /// reader spawns a tool rather than reading the preference file the internet recommends.
    static func firewall(item: [String: Any]?) -> ProtectionReading {
        guard let item, let raw = item["spfirewall_globalstate"] as? String else {
            return .unreadable(.firewall)
        }

        let meaning = AppleWords.meaning(of: raw, from: .firewall, keys: firewallModeKeys)
        // Least protective first, so an ambiguity resolves the cautious way.
        guard let mode = FirewallMode.allCases.first(where: meaning.couldBe) else {
            return .unreadable(.firewall,
                               details: [DetailPair("Firewall, as this Mac words it", raw)])
        }

        // No "Firewall mode" row: the block above already prints `mode.clause` beside the word
        // Firewall, and an Options disclosure that opens onto the sentence you just read is a
        // disclosure that teaches people not to open it.
        var details: [DetailPair] = []

        if let stealth = flag(item["spfirewall_stealthenabled"], from: .firewall) {
            details.append(DetailPair("Stealth mode",
                                      stealth
                                        ? "On — this Mac does not answer probes from the network"
                                        : "Off — this Mac answers probes from the network"))
        }
        if let logging = flag(item["spfirewall_loggingenabled"], from: .firewall) {
            details.append(DetailPair("Firewall log", logging ? "On" : "Off"))
        }

        // ⚠️ Count the apps that were actually allowed, not the size of the list. The list also
        // holds apps that were explicitly blocked, and calling the total "allowed" would put a
        // bigger number on the row than is true.
        if let apps = item["spfirewall_applications"] as? [String: String] {
            let allowed = apps.values.filter { $0.localizedCaseInsensitiveContains("allow") }.count
            details.append(DetailPair("Apps allowed to accept connections", "\(allowed)"))
        }

        return ProtectionReading(.firewall,
                                 mode == .off ? .off : .on,
                                 detail: mode.clause,
                                 details: details,
                                 pane: .firewall)
    }

    /// The three settings macOS's firewall has.
    ///
    /// ⚠️ **Ordered least protective first**, for the same cautious-reading reason as
    /// `SecureBootLevel`.
    enum FirewallMode: String, CaseIterable, Sendable, Hashable {
        case off, limited, blockAll

        /// The clause that continues "On — " or "Off — " on the block's row. That row is the only
        /// place the mode is printed, so there is no second, standing-alone wording to keep in step
        /// with it.
        var clause: String {
            switch self {
            case .off:      "every incoming connection is allowed"
            case .limited:  "only chosen services and apps may accept connections"
            case .blockAll: "everything incoming is blocked except the essentials"
            }
        }
    }

    static let firewallModeKeys: [String: FirewallMode] = [
        "spfirewall_globalstate_allow_all": .off,
        "spfirewall_globalstate_limit_connections": .limited,
        "spfirewall_globalstate_block_all": .blockAll,
    ]

    // MARK: - Automatic security updates

    /// **Is macOS taking Apple's security fixes on its own?**
    ///
    /// Two keys, and both have to be on for the answer to be yes:
    ///
    /// - `CriticalUpdateInstall` — the security responses Apple ships between releases.
    /// - `ConfigDataInstall` — the XProtect malware definitions, which are the fast-moving half.
    ///
    /// One on and one off is `.reduced`, because that is what it is: some fixes arrive by
    /// themselves and some wait for somebody to remember.
    ///
    /// ⚠️ **A missing key is not a "no".** macOS defaults both to on and writes them out at first
    /// boot, so a file with neither key is a file we do not understand rather than a Mac with the
    /// switches off. That path reports "this Mac does not report it", which is honest in both
    /// directions — no false alarm, and no false comfort either.
    ///
    /// The managed copy in `/Library/Managed Preferences` is read first and wins, because on an
    /// enrolled Mac that is the value which actually takes effect.
    static func automaticSecurityUpdates(settings: [String: Any]?,
                                         managed: [String: Any]?) -> ProtectionReading {
        func value(_ key: String) -> Bool? {
            (managed?[key] as? Bool) ?? (settings?[key] as? Bool)
        }

        let fixes = value("CriticalUpdateInstall")
        let definitions = value("ConfigDataInstall")
        let both = [fixes, definitions].compactMap { $0 }

        guard !both.isEmpty else { return .unreadable(.automaticSecurityUpdates) }

        var details = [
            DetailPair("Security fixes install on their own", onOff(fixes)),
            DetailPair("Malware definitions update on their own", onOff(definitions)),
        ]
        if let full = value("AutomaticallyInstallMacOSUpdates") {
            details.append(DetailPair("macOS updates install on their own", full ? "On" : "Off"))
        }

        if both.count == 2, both.allSatisfy({ $0 }) {
            return ProtectionReading(.automaticSecurityUpdates, .on,
                                     detail: "fixes and malware definitions both arrive on their own",
                                     details: details,
                                     pane: .softwareUpdate)
        }
        if both.contains(true) {
            return ProtectionReading(.automaticSecurityUpdates, .reduced,
                                     detail: "some of it arrives on its own, some does not",
                                     details: details,
                                     pane: .softwareUpdate)
        }
        return ProtectionReading(.automaticSecurityUpdates, .off,
                                 detail: "fixes arrive only when somebody installs them",
                                 details: details,
                                 pane: .softwareUpdate)
    }

    /// "On", "Off", or the house sentence — never a blank, and never a guessed "Off".
    static func onOff(_ value: Bool?) -> String {
        guard let value else { return Unreadable.notReported.sentence }
        return value ? "On" : "Off"
    }

    // MARK: - Automatic login

    /// **Does this Mac sign somebody in without asking for a password?**
    ///
    /// ⚠️ **The one switch here where being on is the concern**, which `ProtectionKind` already
    /// knows — `onIsTheSafeState` is false for it — and which is why every reading in this file
    /// asks about its own switch rather than about "on". A rule written the other way round would
    /// put a tick beside a Mac that signs itself in.
    ///
    /// `autoLoginUser` is written into `/Library/Preferences/com.apple.loginwindow.plist` when the
    /// setting is switched on and removed when it is switched off, so its absence is a real "off"
    /// rather than a failure to look: the file itself is world-readable and *was* read. The
    /// obscured password macOS stores at `/etc/kcpassword` corroborates — root-only to read, but
    /// its existence is visible to anybody, and a Mac with automatic login on has one.
    static func automaticLogin(settings: [String: Any]?,
                               hasStoredPassword: Bool) -> ProtectionReading {
        guard let settings else { return .unreadable(.automaticLogin) }

        let account = (settings["autoLoginUser"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let account, !account.isEmpty else {
            // No row restating "off" — the block above says it. The only thing worth an Options row
            // here is the leftover file, which is not visible anywhere else.
            var details: [DetailPair] = []
            if hasStoredPassword {
                // The setting is off and the leftover file is still there. Worth stating exactly,
                // and worth not calling a problem: without the setting it does nothing.
                details.append(DetailPair("Left behind",
                                          "A stored startup password from an earlier setting is "
                                        + "still on this Mac, unused."))
            }
            return ProtectionReading(.automaticLogin, .off,
                                     detail: "a password is asked for at startup",
                                     details: details,
                                     pane: .usersAndGroups)
        }

        return ProtectionReading(
            .automaticLogin, .on,
            detail: "somebody is signed in at startup with no password",
            details: [
                DetailPair("Signed in automatically as", account, sensitive: true),
                DetailPair("Startup password stored on this Mac", hasStoredPassword ? "Yes" : "No"),
            ],
            notes: ["Anybody who opens the lid or presses the power button is signed in as this "
                  + "person. FileVault still protects the disk while the Mac is fully shut down."],
            pane: .usersAndGroups)
    }

    // MARK: - Lockdown Mode

    /// **Nothing on this Mac reports Lockdown Mode. Not a preference, not an API, not a reporter.**
    ///
    /// So the row says this Mac does not report it, and it must never say "off" — a person who
    /// switched Lockdown Mode on because they are targeted personally is exactly the person who
    /// should not be told by a health check that it is off.
    ///
    /// `.notReported` rather than a refusal: the check stays complete, because no permission would
    /// have helped, and there is nothing to put a button on. The case exists in `ProtectionKind` so
    /// that this is stated once, out loud, instead of the switch being quietly missing from the
    /// list.
    static func lockdownMode() -> ProtectionReading {
        .unreadable(.lockdownMode)
    }

    // MARK: - XProtect

    /// XProtect's data version, when that data was last written, and the scanner's version.
    ///
    /// Two separate things share the name: `XProtect.bundle` holds the malware definitions macOS
    /// checks apps against, and `XProtect.app` is the scanner that goes looking. The block reports
    /// the definitions, because a definition file that has not changed in a year is the fact that
    /// matters; the scanner's version goes behind Options.
    ///
    /// **The date is the file's own, never today's.** `xprotectUpdated` is `nil` where it could not
    /// be read, and `ProtectionsBlock` prints the house sentence for that — a stand-in date would
    /// print today for a Mac whose definitions have not updated since last summer.
    static func xprotectData(bundle: URL = xprotectBundle,
                             scanner: URL = xprotectScanner,
                             fileManager: FileManager = .default)
    -> (version: String?, updated: Date?, remediatorVersion: String?) {

        let info = propertyList(at: bundle.appending(path: "Contents/Info.plist"))

        // ⚠️ The newest of the definition files, not the bundle folder's own date. Replacing a file
        // inside a bundle does not always touch the folder, and the folder's date is touched by
        // things that are not an update.
        let resources = bundle.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        let updated = ((try? fileManager.contentsOfDirectory(atPath: resources.path)) ?? [])
            .map { resources.appending(path: $0) }
            .compactMap { try? fileManager.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date }
            .max()

        let scannerInfo = propertyList(at: scanner.appending(path: "Contents/Info.plist"))

        return (info?["CFBundleShortVersionString"] as? String,
                updated,
                scannerInfo?["CFBundleShortVersionString"] as? String)
    }

    static let xprotectBundle =
        URL(filePath: "/Library/Apple/System/Library/CoreServices/XProtect.bundle",
            directoryHint: .isDirectory)

    static let xprotectScanner =
        URL(filePath: "/Library/Apple/System/Library/CoreServices/XProtect.app",
            directoryHint: .isDirectory)

    // MARK: - The row

    /// **The `.protections` row: one sentence, one figure, and whatever the nine allow.**
    ///
    /// Every concern here comes from `Protection.concern`, which already returns `nil` for a switch
    /// an organisation set — so the sentence written here and the concern list underneath it can
    /// never disagree. That matters more than it looks: `SecurityReport.init` filters
    /// organisation-set concerns out of a row whose words it did not write, and a headline built
    /// from concerns that were later dropped would sit there contradicting itself.
    static func row(block: ProtectionsBlock,
                    details: [DetailPair],
                    notes: [String],
                    managedSentence: String?) -> SecurityRow {

        let readable = block.protections.filter(\.state.wasRead)

        guard !readable.isEmpty else {
            // Nothing at all answered. Not a refusal: no permission would have helped with any of
            // these, so the check stays complete and no button is offered.
            return .unreadable(.protections, .notReported,
                               about: "This Mac's protections",
                               reason: "Not one of the switches this section looks at answered. "
                                     + "That is unusual, and it is not a finding about the Mac.",
                               details: details)
        }

        let concerns = block.protections.compactMap(\.concern)
        var reason = notes

        // The audit sentence — John's addition, 2026-08-26. A clean result has to carry the
        // evidence that it *is* a clean result, or it is indistinguishable from a check that never
        // ran.
        let silent = block.protections.filter { !$0.state.wasRead }.map(\.kind.label)
        if !silent.isEmpty {
            reason.append(silent.count == 1
                ? "\(silent[0]) is the one thing here this Mac does not report, so this can say "
                + "neither on nor off for it."
                : "\(list(silent)) are the things here this Mac does not report, so this can say "
                + "neither on nor off for them.")
        }

        if let managedSentence { reason.append(managedSentence) }

        let headline = switch concerns.count {
        case 0:  "Everything this Mac would tell us about is set the way it protects you."
        case 1:  "One of these protections is worth a look."
        default: "\(concerns.count) of these protections are worth a look."
        }

        return SecurityRow(topic: .protections,
                           headline: headline,
                           measure: "\(readable.count) of \(block.protections.count) read",
                           concerns: concerns,
                           reason: reason.isEmpty ? nil : reason.joined(separator: " "),
                           details: details)
    }

    /// "A, B and C".
    static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + (items.last ?? "")
    }

    // MARK: - Where the files are

    static let softwareUpdateSettings =
        URL(filePath: "/Library/Preferences/com.apple.SoftwareUpdate.plist")

    /// What an organisation's profile pushed, which overrides the file above.
    static let managedSoftwareUpdateSettings =
        URL(filePath: "/Library/Managed Preferences/com.apple.SoftwareUpdate.plist")

    static let loginWindowSettings =
        URL(filePath: "/Library/Preferences/com.apple.loginwindow.plist")

    /// The obscured password macOS stores when automatic login is switched on. Root-only to read;
    /// its existence is visible to anybody, and existence is all this reader wants.
    static let storedLoginPassword = URL(filePath: "/etc/kcpassword")

    /// A property list, or `nil` — a missing file, an unreadable one and a malformed one are the
    /// same answer to this reader, and every caller turns `nil` into the house sentence rather than
    /// into a zero.
    static func propertyList(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              let plist = try? PropertyListSerialization.propertyList(from: data,
                                                                     options: [],
                                                                     format: nil)
        else { return nil }
        return plist as? [String: Any]
    }

    // MARK: - Apple's Yes / No / Enabled / Disabled

    /// One of Apple's boolean words, whatever language this Mac says it in.
    ///
    /// ⚠️ **The reporter that prints the word does not always own the word.** `SPFirewallReporter`'s
    /// own table has no entry for "Yes" at all, yet `spfirewall_stealthenabled` comes back as `Yes`
    /// — verified today. So the named reporter's table is tried first, and the controller's table,
    /// which does carry every language's Yes / No / Enabled / Disabled, is the fallback. Last comes
    /// a direct English comparison, which is exactly as good as having no table and no worse.
    ///
    /// `nil` where none of the three recognised it, and every caller leaves the row out rather than
    /// printing a guess.
    static func flag(_ value: Any?, from reporter: AppleWords.Reporter = .controller) -> Bool? {
        if let already = value as? Bool { return already }
        guard let text = value as? String else { return nil }

        for table in [reporter, .controller] {
            if let certain = AppleWords.meaning(of: text, from: table, keys: booleanKeys).certainValue {
                return certain
            }
        }

        switch text.trimmingCharacters(in: .whitespaces).lowercased() {
        case "yes", "enabled", "true", "on":   return true
        case "no", "disabled", "false", "off": return false
        default:                               return nil
        }
    }

    /// Apple's English keys for the two answers, from the controller's own table.
    static let booleanKeys: [String: Bool] = [
        "Yes": true, "Enabled": true,
        "No": false, "Disabled": false,
    ]

    // MARK: - The three tools

    /// `system_profiler`, asked for several reporters at once.
    ///
    /// One spawn for two reporters: passing more than one data type returns one JSON object with
    /// one top-level key each, verified on this Mac today. Two spawns for two facts is two chances
    /// for a hardened-runtime app to be blocked, and twice the wait.
    static func systemProfiler(_ types: [String], timeout: TimeInterval) -> [String: Any]? {
        guard let data = run(URL(filePath: "/usr/sbin/system_profiler"),
                             arguments: types + ["-json"],
                             timeout: timeout) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// `spctl --status`, as text. See `gatekeeper(spctlOutput:)` for why this one is words.
    static func gatekeeperStatus(timeout: TimeInterval) -> String? {
        run(URL(filePath: "/usr/sbin/spctl"), arguments: ["--status"], timeout: timeout)
            .flatMap { String(data: $0, encoding: .utf8) }
    }

    /// FileVault, from the data volume — falling back to the startup volume.
    ///
    /// The data volume is the one FileVault protects; the system volume is read-only and sealed and
    /// is a different question. Both are asked because a Mac laid out in a way nobody here has seen
    /// should degrade to the house sentence rather than to a wrong boolean.
    static func fileVaultVolume(timeout: TimeInterval) -> [String: Any]? {
        for path in ["/System/Volumes/Data", "/"] {
            guard let data = run(URL(filePath: "/usr/sbin/diskutil"),
                                 arguments: ["info", "-plist", path],
                                 timeout: timeout),
                  let plist = try? PropertyListSerialization.propertyList(from: data,
                                                                         options: [],
                                                                         format: nil),
                  let volume = plist as? [String: Any],
                  volume["FileVault"] != nil
            else { continue }
            return volume
        }
        return nil
    }

    /// The controller chip's two MDM flags, in the shape `ManagedMac` wants them.
    static func controllerMDM(_ controller: [String: Any]?) -> ManagedMac.ControllerMDM {
        ManagedMac.ControllerMDM(deviceApproved: flag(controller?["ibridge_sb_device_mdm"]),
                                 userApproved: flag(controller?["ibridge_sb_manual_mdm"]))
    }

    // MARK: - Running one, with a watchdog

    /// Run a tool and take its output, or `nil` on any failure at all.
    ///
    /// Ported from `BatteryReader`, including the ordering that matters: the pipe is drained
    /// **before** `waitUntilExit`. A child filling the pipe buffer while the parent waits for it to
    /// exit is a deadlock, and it is the kind that only appears on the machine with an unusual
    /// amount to say — a Mac with two hundred apps in the firewall list, for instance.
    ///
    /// The watchdog is not paranoia about these three tools. It is that this section holds the
    /// window's check open, and a tool that blocks on something would hold it open for as long as
    /// it liked.
    static func run(_ tool: URL, arguments: [String], timeout: TimeInterval) -> Data? {
        guard FileManager.default.isExecutableFile(atPath: tool.path) else { return nil }

        let process = Process()
        process.executableURL = tool
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }

        let watchdog = Watchdog(process)
        let killer = DispatchWorkItem { watchdog.terminate() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: killer)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()

        guard process.terminationStatus == 0, !data.isEmpty else { return nil }
        return data
    }

    /// One `Process` reference, read by two threads, doing exactly one thing.
    ///
    /// `Process` is not `Sendable` and the watchdog runs on another queue. This is the narrowest
    /// possible admission of that, and it is `private` so nothing else can widen it.
    private final class Watchdog: @unchecked Sendable {
        private let process: Process
        init(_ process: Process) { self.process = process }
        func terminate() { if process.isRunning { process.terminate() } }
    }
}

// MARK: - Drawing order

private extension ProtectionKind {
    /// Where this switch sits in the block, so the row's details and sentences come out in the same
    /// order the block draws in, whatever order the readers were written in above.
    var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

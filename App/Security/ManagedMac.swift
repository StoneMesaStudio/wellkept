import Foundation
import WellkeptCore

//  ManagedMac.swift
//  Wellkept — App/Security
//
//  **Is somebody else in charge of this Mac, and which switches did they set?**
//
//  ## Why this file exists at all
//
//  A work laptop and a family laptop look identical to a health check. They are not the same
//  machine. On a managed Mac the firewall, FileVault and the update policy were chosen by an IT
//  department, pushed down as a configuration profile, and are frequently **not changeable by the
//  person sitting in front of them** — the pane is greyed out, or it flips back within the hour.
//
//  Report those as faults and Wellkept stops being a health check and becomes an accusation about
//  somebody's employer, aimed at the one person in the building who cannot act on it and who has
//  something to lose by trying. The decision, 2026-08-27: **a management fact is never a
//  problem.** Not amber, not red, not a nag.
//
//  So this file answers two separate questions, and they are genuinely separate:
//
//  1. **Is this Mac enrolled with an organisation at all?** — `read()`. That is the sentence at the
//     bottom of the protections block, and it decides nothing on its own.
//  2. **Did a profile set *this particular switch*?** — `sets(_:)`. That is what actually silences
//     a concern and drops a button, and it is deliberately per-switch. A Mac enrolled only to push
//     a Wi-Fi certificate has not had its firewall chosen for it, and blanket-silencing every
//     concern the moment enrolment is detected would hide real findings on the machines most
//     likely to have them.
//
//  ## ⚠️ What is deliberately not done here
//
//  - **Nothing is enumerated out of `/var/db/ConfigurationProfiles/Store`.** Measured on one real Mac,
//    2026-08-27: that directory answers `Operation not permitted` to an ordinary read. The tool
//    Apple ships for it raises an authorization dialog, and an earlier research round put a system
//    password box on somebody's screen doing exactly that. If a fact needs elevation, the fact is
//    that it needs elevation.
//  - **No subprocess.** Everything below is a file existence check or a CoreFoundation call. The
//    controller chip's own MDM flags are passed in by `ProtectionReader`, which was already running
//    `system_profiler` for the boot-security block; asking for them twice would be a second spawn
//    for a fact already in hand.
//  - **No claim that a Mac is *not* managed.** Absence of every marker below is reported as "we
//    found no sign of it", which is what it is. There are enrolment styles nobody here has seen.
//
//  ## The markers, and what each one actually proves
//
//  Measured on an M3 running macOS 26, 2026-08-27, unenrolled.
//
//  | Marker | Proves |
//  |---|---|
//  | `/Library/Managed Preferences` exists, non-empty | A profile is actively pushing settings **now** |
//  | `…/Settings/.cloudConfigProfileInstalled` | Enrolled through Automated Device Enrolment |
//  | `…/Settings/.cloudConfigRecordFound` | This serial is in an organisation's Apple Business/School account |
//  | `…/Settings/.cloudConfigNoActivationRecord` | The opposite — Apple was asked and said no record. **Present on this Mac.** |
//  | `ibridge_sb_device_mdm` = Yes | The controller chip grants MDM privileged operations, approved by enrolment |
//  | `ibridge_sb_manual_mdm` = Yes | The same, approved by the person at the keyboard |
//
//  ⚠️ **`.provisioningProfilesAreInstalled` is present on this Mac and means nothing here.** It is
//  a developer signing artefact — every Mac with an Xcode beta build on it has one. Counting it
//  would report a solo developer's laptop as company property, which is the false positive this
//  whole file is written to avoid.

enum ManagedMac {

    // MARK: - What the controller chip said

    /// The two MDM flags `SPiBridgeDataType` reports, handed over by `ProtectionReader` rather than
    /// fetched again.
    ///
    /// ⚠️ **`nil` is not `false`.** An Intel Mac without a T2 chip reports no controller at all, and
    /// a machine that reports nothing has not told us it is unmanaged — it has told us nothing. The
    /// distinction is the difference between "no sign of enrolment" and "definitely not enrolled",
    /// and only the first of those is ever true here.
    struct ControllerMDM: Sendable, Hashable {

        /// `ibridge_sb_device_mdm` — "DEP Approved Privileged MDM Operations". Set where the
        /// machine was enrolled automatically, by serial number, before anybody opened the lid.
        let deviceApproved: Bool?

        /// `ibridge_sb_manual_mdm` — "User Approved Privileged MDM Operations". Set where a person
        /// accepted an enrolment profile themselves.
        let userApproved: Bool?

        /// The controller was not read, or does not exist on this hardware.
        static let notReported = ControllerMDM(deviceApproved: nil, userApproved: nil)

        /// Whether either flag is a definite yes. `nil` where neither was reported.
        var saysEnrolled: Bool? {
            let flags = [deviceApproved, userApproved].compactMap { $0 }
            guard !flags.isEmpty else { return nil }
            return flags.contains(true)
        }
    }

    // MARK: - The answer

    /// What we found out about who configures this Mac.
    struct Enrolment: Sendable, Hashable {

        /// At least one marker says an organisation is involved.
        ///
        /// This is what reaches `ProtectionsBlock.isManaged`, and on its own it changes only the
        /// words. Silencing a concern is `sets(_:)`'s job, per switch.
        let isManaged: Bool

        /// Enrolled through Automated Device Enrolment — the machine was bought into an
        /// organisation's account and enrolled itself. Usually not removable by the person using it.
        let automaticallyEnrolled: Bool

        /// A person accepted the enrolment themselves. Usually removable by that person.
        let userApproved: Bool

        /// `/Library/Managed Preferences` exists and holds something — a profile is pushing
        /// settings right now, as opposed to enrolment having happened at some point.
        let hasManagedPreferences: Bool

        /// Exactly which markers were seen, in the order they are checked, for the Options
        /// disclosure. This is the audit trail: a person who disagrees with our conclusion can see
        /// what we actually looked at, which is the only thing that lets them disagree.
        let evidence: [String]

        /// Nothing found. Not the same as "definitely a personal Mac" — see the type note on
        /// `ControllerMDM`.
        static let noSignOfIt = Enrolment(isManaged: false,
                                          automaticallyEnrolled: false,
                                          userApproved: false,
                                          hasManagedPreferences: false,
                                          evidence: [])

        /// The sentence for the block, or `nil` on a Mac with no sign of enrolment.
        ///
        /// ⚠️ No imperative, no colour, no apology. It is a fact about the machine in the same
        /// register as its model number.
        var sentence: String? {
            guard isManaged else { return nil }
            if automaticallyEnrolled {
                return "This Mac is enrolled with an organisation, which chooses some of its "
                     + "settings. Those settings are not yours to change here."
            }
            if userApproved {
                return "This Mac is enrolled with an organisation, which chooses some of its "
                     + "settings."
            }
            return "Something on this Mac is applying settings chosen elsewhere — a configuration "
                 + "profile, or an organisation this Mac is enrolled with."
        }

        /// The evidence, as Options rows. Empty on an unenrolled Mac, so nothing is drawn.
        var detailPairs: [DetailPair] {
            evidence.enumerated().map { index, line in
                DetailPair(index == 0 ? "Managed because" : "Also", line)
            }
        }
    }

    // MARK: - Reading it

    /// Look for every marker, and report what was actually seen.
    ///
    /// Cheap: four file-existence checks and one directory listing, no subprocess and no permission.
    /// Safe from any thread and safe to call twice.
    ///
    /// - Parameter controller: the two MDM flags from `SPiBridgeDataType`, where they were read.
    static func read(controller: ControllerMDM = .notReported,
                     fileManager: FileManager = .default) -> Enrolment {

        var evidence: [String] = []

        let managedPreferences = hasContents(managedPreferencesFolder, fileManager: fileManager)
        if managedPreferences {
            evidence.append("A configuration profile is applying settings to this Mac now.")
        }

        let automatic = fileManager.fileExists(atPath: automaticEnrolmentMarker.path)
            || fileManager.fileExists(atPath: activationRecordMarker.path)
        if automatic {
            evidence.append("This Mac is registered to an organisation with Apple, and enrolled "
                          + "itself when it was first switched on.")
        }

        // The controller chip's flags. Read second because they are the least explanatory of the
        // three — they say privileged management operations are permitted, which is a consequence
        // of enrolment rather than a description of it.
        let deviceApproved = controller.deviceApproved == true
        let userApproved = controller.userApproved == true
        if deviceApproved {
            evidence.append("This Mac's security chip allows management operations that were "
                          + "approved when it was enrolled.")
        }
        if userApproved {
            evidence.append("Somebody using this Mac approved management operations for it.")
        }

        // ⚠️ `saysEnrolled` rather than `deviceApproved || userApproved`, because it is the one
        // place the nil-is-not-false rule is written down: a Mac whose controller said nothing has
        // not said no.
        let managed = managedPreferences || automatic || controller.saysEnrolled == true

        return Enrolment(isManaged: managed,
                         automaticallyEnrolled: automatic || deviceApproved,
                         userApproved: userApproved,
                         hasManagedPreferences: managedPreferences,
                         evidence: evidence)
    }

    // MARK: - Which switch a profile actually set

    /// **Whether a configuration profile is forcing this particular switch.**
    ///
    /// This is the one that matters. `Protection.init` drops the System Settings button when it is
    /// true, and `SecurityReport.init` drops the concern — so a switch an employer set is stated as
    /// a fact, labelled as theirs, and never counted against the person using the machine.
    ///
    /// `CFPreferencesAppValueIsForced` is public CoreFoundation and is exactly the right question:
    /// it asks whether the value would come from the managed layer rather than from anything the
    /// user could write. No permission, no subprocess, and it answers correctly for a Mac that is
    /// enrolled but has no policy for this particular setting — which blanket enrolment detection
    /// cannot do.
    static func sets(_ kind: ProtectionKind) -> Bool {
        forcedSettings(for: kind).contains { isForced($0.key, in: $0.domain) }
    }

    /// Whether one preference key is being forced by a profile.
    static func isForced(_ key: String, in domain: String) -> Bool {
        CFPreferencesAppValueIsForced(key as CFString, domain as CFString)
    }

    /// The preference keys a configuration profile uses to take each switch away from the user.
    ///
    /// ⚠️ **Three switches are absent on purpose, and it is not an oversight.**
    ///
    /// - **Secure boot** and **System Integrity Protection** are set in the recovery environment
    ///   with the machine's own firmware password or an owner's credentials. No profile can reach
    ///   them, so no profile can be blamed for them.
    /// - **Lockdown Mode** has no readable state at all, so there is nothing for a profile to have
    ///   set from our point of view.
    static func forcedSettings(for kind: ProtectionKind) -> [(domain: String, key: String)] {
        switch kind {
        case .fileVault:
            [("com.apple.MCX", "dontAllowFDEDisable"),
             ("com.apple.MCX", "dontAllowFDEEnable"),
             ("com.apple.MCXFileVault", "Enable")]
        case .firewall:
            [("com.apple.security.firewall", "EnableFirewall"),
             ("com.apple.security.firewall", "GlobalState"),
             ("com.apple.security.firewall", "EnableStealthMode"),
             ("com.apple.alf", "globalstate")]
        case .gatekeeper:
            [("com.apple.systempolicy.control", "EnableAssessment"),
             ("com.apple.systempolicy.control", "AllowIdentifiedDevelopers")]
        case .automaticSecurityUpdates:
            [("com.apple.SoftwareUpdate", "CriticalUpdateInstall"),
             ("com.apple.SoftwareUpdate", "ConfigDataInstall"),
             ("com.apple.SoftwareUpdate", "AutomaticCheckEnabled")]
        case .automaticLogin:
            [("com.apple.loginwindow", "com.apple.login.mcx.DisableAutoLoginClient"),
             ("com.apple.loginwindow", "DisableFDEAutoLogin"),
             ("com.apple.loginwindow", "autoLoginUser")]
        case .secureBoot, .systemProtection, .lockdownMode:
            []
        }
    }

    // MARK: - Where the markers live

    /// Settings a profile is pushing right now. Absent on a Mac nobody manages — verified on this
    /// Mac, 2026-08-27.
    static let managedPreferencesFolder = URL(filePath: "/Library/Managed Preferences",
                                              directoryHint: .isDirectory)

    /// Automated Device Enrolment left a profile behind.
    static let automaticEnrolmentMarker =
        URL(filePath: "/var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled")

    /// Apple was asked about this serial number and returned an organisation's record.
    ///
    /// Its opposite — `.cloudConfigNoActivationRecord`, which is what this Mac has — is deliberately
    /// **not** treated as proof of anything. A Mac can be enrolled by hand without ever having an
    /// activation record, so the absence of a record rules nothing out.
    static let activationRecordMarker =
        URL(filePath: "/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound")

    /// A directory that exists and holds at least one thing.
    ///
    /// Existence alone is not enough: an empty `/Library/Managed Preferences` is left behind by an
    /// enrolment that has since been removed, and reporting that Mac as managed would silence real
    /// findings on a machine nobody manages any more.
    private static func hasContents(_ folder: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return false }
        let contents = try? fileManager.contentsOfDirectory(atPath: folder.path)
        return !(contents ?? []).filter { !$0.hasPrefix(".") }.isEmpty
    }
}

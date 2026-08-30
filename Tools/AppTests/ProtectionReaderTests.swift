import Testing
import Foundation
import WellkeptCore

//  ProtectionReaderTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **The promises the protections block makes, checked by a machine rather than remembered.**
//
//  Everything here is one of two kinds, and the split is deliberate:
//
//  1. **Fixture tests** — a dictionary typed out below, run through one reader. They give the same
//     answer on an M3, on an Intel Mac Pro and on a build machine, and they are how the states
//     nobody here can produce get tested at all: nobody is switching FileVault off, disabling
//     System Integrity Protection, or turning on automatic login to see what happens.
//  2. **One live invariant test** — it reads this Mac and asserts nothing about what it finds, only
//     that the shape holds. That is the only thing a live test can honestly assert, and the
//     `system_profiler`, `spctl` and `diskutil` calls are all read-only.
//
//  ⚠️ **Not one expectation below names a value from this particular Mac.** A test that asserts
//  FileVault is on is a test that fails on somebody else's laptop, and the fix somebody reaches for
//  is to delete the test.

// MARK: - 1. The switch that runs the other way round

@Suite struct AutomaticLoginTests {

    /// ⚠️ **The single highest-value test in this file.** `automaticLogin` is the one protection
    /// where *on* is the concern, and the whole reader is written around `isProtecting(kind)` rather
    /// than around "is it on". Get it backwards and Wellkept draws a tick beside a Mac that signs
    /// itself in with no password — the exact opposite of the finding.
    @Test func automaticLoginOnIsTheConcernAndOffIsHealthy() {
        let on = ProtectionReader.automaticLogin(settings: ["autoLoginUser": "someone"],
                                                 hasStoredPassword: true)
        #expect(on.state == .on)
        #expect(on.protection.isProtecting == false)
        #expect(on.protection.concern == .automaticLoginOn)

        let off = ProtectionReader.automaticLogin(settings: ["GuestEnabled": false],
                                                 hasStoredPassword: false)
        #expect(off.state == .off)
        #expect(off.protection.isProtecting == true)
        #expect(off.protection.concern == nil)
    }

    /// The account name is somebody's short user name on their own screenshot. It is marked
    /// sensitive so the "copy this" paths can show what they are about to reveal.
    @Test func theAccountNameIsMarkedSensitive() {
        let on = ProtectionReader.automaticLogin(settings: ["autoLoginUser": "jane"],
                                                 hasStoredPassword: true)
        let named = on.details.first { $0.value == "jane" }
        #expect(named?.sensitive == true)
    }

    /// An empty string is not an account. macOS has been seen to leave the key behind with nothing
    /// in it, and reading that as "automatic login is on" would raise a concern about a Mac that
    /// asks for a password every time.
    @Test func anEmptyAccountNameIsNotAutomaticLogin() {
        let blank = ProtectionReader.automaticLogin(settings: ["autoLoginUser": "  "],
                                                    hasStoredPassword: false)
        #expect(blank.state == .off)
    }

    /// A file we could not open is never an "off". The whole app's first rule.
    @Test func anUnreadableFileIsNotAnOff() {
        let unread = ProtectionReader.automaticLogin(settings: nil, hasStoredPassword: false)
        #expect(unread.state == .unreadable(.notReported))
        #expect(unread.protection.concern == nil)
        #expect(unread.protection.isProtecting == nil)
    }
}

// MARK: - 2. Lockdown Mode is never "off"

@Suite struct LockdownModeTests {

    /// ⚠️ Apple publishes no state for Lockdown Mode anywhere. A person who switched it on because
    /// they are targeted personally is exactly the person who must not be told by a health check
    /// that it is off.
    @Test func lockdownModeIsNeverReportedAsOff() {
        let reading = ProtectionReader.lockdownMode()
        #expect(reading.state == .unreadable(.notReported))
        #expect(reading.state.label == Unreadable.notReported.sentence)
        #expect(reading.protection.concern == nil)
    }

    /// It costs no button and no caveat: nothing could be granted that would show it, so the check
    /// stays complete. That is the whole reason `.notGrantable` and `.notReported` both exist
    /// alongside `.notPermitted`.
    @Test func lockdownModeLeavesTheCheckComplete() {
        #expect(Unreadable.notReported.stillComplete)
        #expect(!Unreadable.notReported.mayOfferRemedy)
    }
}

// MARK: - 3. System Integrity Protection, bit by bit

@Suite struct SystemProtectionTests {

    @Test func aZeroConfigIsFullyOn() {
        let reading = ProtectionReader.systemProtection(config: 0)
        #expect(reading.state == .on)
        #expect(reading.protection.concern == nil)
    }

    /// The bit that means *protected parts of macOS can be changed* is what a person means by "SIP
    /// is off". Anything else set is a reduction, and both raise the same one of the nine — there
    /// is no tenth condition to reach for.
    @Test func theFilesystemBitIsWhatOffMeans() {
        let unrestrictedFilesystem = ProtectionReader.systemProtection(config: 1 << 1)
        #expect(unrestrictedFilesystem.state == .off)
        #expect(unrestrictedFilesystem.protection.concern == .systemProtectionOff)

        let debuggerOnly = ProtectionReader.systemProtection(config: 1 << 3)
        #expect(debuggerOnly.state == .reduced)
        #expect(debuggerOnly.protection.concern == .systemProtectionOff)
    }

    /// The row has to name exactly what was turned off, because the concern's own title is the
    /// blunt "System Integrity Protection is off" and a Mac with only tracing relaxed deserves
    /// better than that sentence on its own.
    @Test func theRowNamesWhatWasActuallyTurnedOff() {
        let reading = ProtectionReader.systemProtection(config: (1 << 3) | (1 << 5))
        let listed = reading.details.first { $0.label.contains("turned off") }?.value ?? ""
        #expect(listed.contains("the kernel can be debugged"))
        #expect(listed.contains("system tracing is unrestricted"))
        #expect(reading.notes.contains { $0.contains("recovery system") })
    }

    /// A machine that will not answer is not a machine with SIP off.
    @Test func anUnreadableConfigIsNotAnOff() {
        let reading = ProtectionReader.systemProtection(config: nil)
        #expect(reading.state.wasRead == false)
        #expect(reading.protection.concern == nil)
    }

    /// The flags are the kernel's own numbering and each bit is distinct. A duplicated bit would
    /// make one relaxation print as two.
    @Test func everyFlagBitIsDistinct() {
        let bits = ProtectionReader.csrFlags.map(\.bit)
        #expect(Set(bits).count == bits.count)
    }
}

// MARK: - 4. Gatekeeper — the one place English words are read

@Suite struct GatekeeperTests {

    /// ⚠️ "disabled" contains "abled". Testing for "enabled" first would report a Mac with
    /// Gatekeeper switched off as protected, which is the worst single mistake available in this
    /// file.
    @Test func disabledIsNotMistakenForEnabled() {
        let off = ProtectionReader.gatekeeper(spctlOutput: "assessments disabled\n")
        #expect(off.state == .off)
        #expect(off.protection.concern == .gatekeeperWeakened)

        let on = ProtectionReader.gatekeeper(spctlOutput: "assessments enabled\ndeveloper id enabled\n")
        #expect(on.state == .on)
        #expect(on.protection.concern == nil)
    }

    /// The second line is about developer-signed apps and is not the answer to this question.
    @Test func onlyTheAssessmentsLineIsRead() {
        let mixed = ProtectionReader.gatekeeper(spctlOutput: "developer id disabled\nassessments enabled\n")
        #expect(mixed.state == .on)
    }

    @Test func noOutputIsNotAnOff() {
        #expect(ProtectionReader.gatekeeper(spctlOutput: nil).state.wasRead == false)
        #expect(ProtectionReader.gatekeeper(spctlOutput: "something else entirely").state.wasRead == false)
    }

    /// Which apps were waved through individually needs root, and no permission a person could
    /// grant would change that. It says so rather than implying the list is empty.
    @Test func theExceptionListSaysItCouldNotBeSeen() {
        let on = ProtectionReader.gatekeeper(spctlOutput: "assessments enabled")
        let exceptions = on.details.first { $0.label.contains("individually") }
        #expect(exceptions?.value == Unreadable.notGrantable.sentence)
    }
}

// MARK: - 5. The firewall

@Suite struct FirewallTests {

    private func item(_ state: String, stealth: String = "No") -> [String: Any] {
        ["spfirewall_globalstate": state,
         "spfirewall_stealthenabled": stealth,
         "spfirewall_loggingenabled": "No",
         "spfirewall_applications": ["a": "spfirewall_allow_all",
                                     "b": "spfirewall_allow_all",
                                     "c": "spfirewall_deny_all"]]
    }

    @Test func theThreeModesReadCorrectly() {
        #expect(ProtectionReader.firewall(item: item("spfirewall_globalstate_allow_all")).state == .off)
        #expect(ProtectionReader.firewall(item: item("spfirewall_globalstate_limit_connections")).state == .on)
        #expect(ProtectionReader.firewall(item: item("spfirewall_globalstate_block_all")).state == .on)
    }

    @Test func onlyTheOffModeRaisesTheConcern() {
        let off = ProtectionReader.firewall(item: item("spfirewall_globalstate_allow_all"))
        #expect(off.protection.concern == .firewallOff)

        let blocking = ProtectionReader.firewall(item: item("spfirewall_globalstate_block_all"))
        #expect(blocking.protection.concern == nil)
    }

    /// ⚠️ The list also holds apps that were explicitly **blocked**. Counting the whole list as
    /// "allowed to accept connections" puts a bigger number on the row than is true — the kind of
    /// inflated figure the scarier cleaners sell.
    @Test func onlyTheAllowedAppsAreCounted() {
        let reading = ProtectionReader.firewall(item: item("spfirewall_globalstate_limit_connections"))
        let allowed = reading.details.first { $0.label.contains("Apps allowed") }
        #expect(allowed?.value == "2")
    }

    /// The preference file every article names is gone in macOS 26, so a firewall we could not read
    /// is common enough to get right — and it is never an "off".
    @Test func anAbsentReporterIsNotAnOff() {
        #expect(ProtectionReader.firewall(item: nil).state.wasRead == false)
        #expect(ProtectionReader.firewall(item: nil).protection.concern == nil)
    }

    /// A mode string Apple has never printed is shown back verbatim rather than guessed at.
    @Test func anUnknownModeIsShownRatherThanGuessed() {
        let odd = ProtectionReader.firewall(item: ["spfirewall_globalstate": "spfirewall_globalstate_something_new"])
        #expect(odd.state.wasRead == false)
        #expect(odd.details.contains { $0.value == "spfirewall_globalstate_something_new" })
    }

    /// Least protective first, so an ambiguity resolves the cautious way.
    @Test func theModesAreOrderedLeastProtectiveFirst() {
        #expect(ProtectionReader.FirewallMode.allCases.first == .off)
    }
}

// MARK: - 6. Secure boot, in whatever language

@Suite struct SecureBootTests {

    @Test func fullSecurityIsOnAndRaisesNothing() {
        let reading = ProtectionReader.secureBoot(controller: ["ibridge_secure_boot": "Full Security"])
        #expect(reading.state == .on)
        #expect(reading.protection.concern == nil)
    }

    /// Apple uses two vocabularies — T2 Macs say Medium Security, Apple silicon says Reduced
    /// Security — and both mean the same thing to a person.
    @Test func bothOfApplesVocabulariesAreUnderstood() {
        for word in ["Medium Security", "Reduced Security", "Permissive Security"] {
            let reading = ProtectionReader.secureBoot(controller: ["ibridge_secure_boot": word])
            #expect(reading.state == .reduced, "\(word) should read as reduced")
            #expect(reading.protection.concern == .bootSecurityReduced)
        }
        let none = ProtectionReader.secureBoot(controller: ["ibridge_secure_boot": "No Security"])
        #expect(none.state == .off)
        #expect(none.protection.concern == .bootSecurityReduced)
    }

    /// ⚠️ **Ordered least secure first, and the order is load-bearing.** Where a language collapses
    /// two levels onto one word, the reader takes the first match — which has to be the cautious
    /// reading, or a reduced-security Mac reports as fully secure on the strength of a translation.
    @Test func theLevelsAreOrderedLeastSecureFirst() {
        #expect(ProtectionReader.SecureBootLevel.allCases
            == [.unverified, .permissive, .reduced, .full])
    }

    /// ⚠️ An Intel Mac without a controller chip reports no `SPiBridgeDataType` at all. That is not
    /// a Mac with secure boot off, and it is the path nobody in this project has been able to run on
    /// real hardware.
    @Test func aMacWithNoControllerChipIsNotAMacWithSecureBootOff() {
        let reading = ProtectionReader.secureBoot(controller: nil)
        #expect(reading.state.wasRead == false)
        #expect(reading.protection.concern == nil)
        // On those machines the startup firmware password is the protection this row would have
        // been about, and it needs an administrator to read.
        #expect(reading.details.contains { $0.value == Unreadable.notGrantable.sentence })
    }

    /// The boot policy behind Options is Yes/No and Enabled/Disabled, which Apple translates.
    @Test func theBootPolicyRowsReadApplesBooleans() {
        let rows = ProtectionReader.bootPolicyDetails(controller: ["ibridge_sb_ssv": "Enabled",
                                                                  "ibridge_sb_other_kext": "No"])
        #expect(rows.contains { $0.label == "Signed system volume" && $0.value.contains("Sealed") })
        #expect(rows.contains { $0.label == "Kernel extensions" && $0.value.contains("Only approved") })
    }
}

// MARK: - 7. FileVault, and the sentence that can cost somebody everything

@Suite struct FileVaultTests {

    /// ⚠️ `Encryption` is true on every Apple silicon Mac whether or not FileVault is on. Reading
    /// that key instead of `FileVault` would report every one of them as protected.
    @Test func onlyTheFileVaultKeyIsBelieved() {
        let encryptedButUnlocked = ProtectionReader.fileVault(
            volume: ["Encryption": true, "EncryptionThisVolumeProper": true, "FileVault": false])
        #expect(encryptedButUnlocked.state == .off)
        #expect(encryptedButUnlocked.protection.concern == .fileVaultOff)
    }

    @Test func aMissingKeyIsNotAnOff() {
        let reading = ProtectionReader.fileVault(volume: ["Encryption": true])
        #expect(reading.state.wasRead == false)
        #expect(reading.protection.concern == nil)
    }

    /// **The recovery-key sentence goes on the row, never behind Options**, and it never says "you
    /// should". The decision, 2026-08-27: it is the one piece of advice in this app that can cost
    /// somebody every file they own.
    @Test func theRecoveryKeySentenceIsOnTheRowAndGivesNoOrders() {
        let off = ProtectionReader.fileVault(volume: ["FileVault": false])
        #expect(off.notes.contains(ProtectionReader.recoveryKeySentence))
        #expect(off.details.isEmpty, "the recovery-key sentence must not be hidden behind Options")

        let sentence = ProtectionReader.recoveryKeySentence.lowercased()
        #expect(!sentence.contains("you should"))
        #expect(!sentence.contains("make sure"))
    }

    /// We can say the door is locked. We cannot say whether there is a key, or who can open it —
    /// both need an administrator password, so both say so rather than being quietly absent.
    @Test func whatWeCannotSeeAboutFileVaultSaysSoRatherThanBeingMissing() {
        let on = ProtectionReader.fileVault(volume: ["FileVault": true])
        #expect(on.state == .on)
        let unseeable = on.details.filter { $0.value == Unreadable.notGrantable.sentence }
        #expect(unseeable.count == 2)
        #expect(unseeable.contains { $0.label.contains("recovery key") })
        #expect(unseeable.contains { $0.label.contains("unlock") })
    }
}

// MARK: - 8. Automatic security updates

@Suite struct AutomaticSecurityUpdateTests {

    @Test func bothHalvesHaveToBeOn() {
        let on = ProtectionReader.automaticSecurityUpdates(
            settings: ["CriticalUpdateInstall": true, "ConfigDataInstall": true], managed: nil)
        #expect(on.state == .on)
        #expect(on.protection.concern == nil)

        let half = ProtectionReader.automaticSecurityUpdates(
            settings: ["CriticalUpdateInstall": true, "ConfigDataInstall": false], managed: nil)
        #expect(half.state == .reduced)
        #expect(half.protection.concern == .automaticSecurityUpdatesOff)

        let off = ProtectionReader.automaticSecurityUpdates(
            settings: ["CriticalUpdateInstall": false, "ConfigDataInstall": false], managed: nil)
        #expect(off.state == .off)
        #expect(off.protection.concern == .automaticSecurityUpdatesOff)
    }

    /// ⚠️ **A missing key is not a "no".** macOS defaults both to on, so a file with neither key is
    /// a file we do not understand — no false alarm, and no false comfort either.
    @Test func aFileWithNeitherKeyIsUnreadableRatherThanOff() {
        let reading = ProtectionReader.automaticSecurityUpdates(settings: ["Something": 1], managed: nil)
        #expect(reading.state.wasRead == false)
        #expect(reading.protection.concern == nil)
    }

    /// On an enrolled Mac the managed copy is the value that actually takes effect.
    @Test func theManagedCopyWins() {
        let reading = ProtectionReader.automaticSecurityUpdates(
            settings: ["CriticalUpdateInstall": true, "ConfigDataInstall": true],
            managed: ["CriticalUpdateInstall": false])
        #expect(reading.state == .reduced)
    }
}

// MARK: - 9. A managed Mac is never accused

@Suite struct ManagedMacTests {

    /// ⚠️ **The rule this whole file exists for.** A switch an organisation set is stated as a fact,
    /// labelled as theirs, given no button — pressing it would not work — and never counted against
    /// the person using the machine.
    @Test func anOrganisationSetSwitchIsAFactAndNotAFault() {
        let theirs = Protection(kind: .firewall,
                                state: .off,
                                detail: "every incoming connection is allowed",
                                setByOrganisation: true,
                                settingsPane: SystemSettingsPane.firewall.rawValue)
        #expect(theirs.concern == nil)
        #expect(theirs.settingsPane == nil, "a pane a person cannot change is a button that does nothing")
        #expect(theirs.detailPair.value.contains("set by an organisation"))

        let theirsToo = SecurityReport(
            block: ProtectionsBlock(protections: [theirs]),
            rows: [SecurityRow(topic: .protections, headline: "x", concerns: [.firewallOff])])
        #expect(theirsToo.concerns.isEmpty)
        #expect(theirsToo.status == .good)
    }

    /// Three switches cannot be set by any profile: two live in the recovery environment, and the
    /// third has no readable state at all. Claiming an organisation set one of those would be
    /// blaming an employer for something no employer can reach.
    @Test func theRecoveryOnlySwitchesAreNeverBlamedOnAnOrganisation() {
        for kind in [ProtectionKind.secureBoot, .systemProtection, .lockdownMode] {
            #expect(ManagedMac.forcedSettings(for: kind).isEmpty)
            #expect(ManagedMac.sets(kind) == false)
        }
    }

    /// Every switch a profile *can* take over is listed, or the concern would be reported to
    /// somebody who cannot act on it.
    @Test func everySettableSwitchHasKeysToCheck() {
        for kind in [ProtectionKind.fileVault, .firewall, .gatekeeper,
                     .automaticSecurityUpdates, .automaticLogin] {
            #expect(!ManagedMac.forcedSettings(for: kind).isEmpty, "\(kind.rawValue) has no keys")
        }
    }

    /// ⚠️ Not one marker fires on a Mac nobody manages, and the developer signing artefact every
    /// Mac with an Xcode build on it carries is deliberately not one of them.
    @Test func nothingIsInventedFromAnEmptyMachine() {
        let nothing = ManagedMac.Enrolment.noSignOfIt
        #expect(nothing.isManaged == false)
        #expect(nothing.sentence == nil)
        #expect(nothing.detailPairs.isEmpty)
    }

    /// The controller chip not reporting is not the controller chip saying no.
    @Test func aSilentControllerChipSaysNothingEitherWay() {
        #expect(ManagedMac.ControllerMDM.notReported.saysEnrolled == nil)
        #expect(ManagedMac.ControllerMDM(deviceApproved: false, userApproved: nil)
            .saysEnrolled == false)
        #expect(ManagedMac.ControllerMDM(deviceApproved: false, userApproved: true)
            .saysEnrolled == true)
    }

    /// A managed Mac says so plainly, once, with no imperative and no colour.
    @Test func theManagedSentenceGivesNoOrders() {
        let managed = ManagedMac.Enrolment(isManaged: true,
                                           automaticallyEnrolled: true,
                                           userApproved: false,
                                           hasManagedPreferences: true,
                                           evidence: ["A configuration profile is applying settings."])
        let sentence = (managed.sentence ?? "").lowercased()
        #expect(!sentence.isEmpty)
        #expect(!sentence.contains("you should"))
        #expect(!sentence.contains("problem"))
        #expect(!managed.detailPairs.isEmpty, "the evidence is the audit trail")
    }
}

// MARK: - 10. The row the block produces

@Suite struct ProtectionRowTests {

    private func block(_ protections: [Protection], managed: Bool = false) -> ProtectionsBlock {
        ProtectionsBlock(protections: protections, isManaged: managed)
    }

    /// A clean row carries the evidence that it is clean — what was read, and what this Mac would
    /// not say. Added 2026-08-26: a clean result with no audit trail is indistinguishable
    /// from a check that never ran.
    @Test func aCleanRowSaysWhatItCouldNotSee() {
        let row = ProtectionReader.row(
            block: block([Protection(kind: .fileVault, state: .on),
                          Protection(kind: .lockdownMode, state: .unreadable(.notReported))]),
            details: [], notes: [], managedSentence: nil)

        #expect(row.status == .good)
        #expect(row.severity == .information)
        #expect(row.measure == "1 of 2 read")
        #expect(row.reason?.contains("Lockdown Mode") == true)
        #expect(row.complete)
    }

    /// The row's severity is computed from its concerns and cannot be declared. A reader that wants
    /// amber has to name which of the nine it is.
    @Test func concernsAreWhatMakeTheRowAmber() {
        let row = ProtectionReader.row(
            block: block([Protection(kind: .fileVault, state: .off),
                          Protection(kind: .firewall, state: .off)]),
            details: [], notes: [ProtectionReader.recoveryKeySentence], managedSentence: nil)

        #expect(row.concerns == [.fileVaultOff, .firewallOff])
        #expect(row.severity == .attention)
        #expect(row.status == .needsAttention)
        #expect(row.headline.contains("2"))
        #expect(row.reason?.contains("recovery key") == true)
    }

    /// ⚠️ **Nothing in Security is ever `.problem`.** Amber says "worth a look"; red would say "you
    /// have done something wrong", and this section is not in a position to know that.
    @Test func nothingHereIsEverRed() {
        let row = ProtectionReader.row(
            block: block(ProtectionKind.allCases.map { Protection(kind: $0, state: .off) }),
            details: [], notes: [], managedSentence: nil)
        #expect(row.severity == .attention)
        #expect(row.severity != .problem)
    }

    /// A block that answered nothing is a `.notReported` row, not a refusal: no permission would
    /// have helped, so the check stays complete and no button is drawn.
    @Test func aBlockThatAnsweredNothingStillLeavesTheCheckComplete() {
        let row = ProtectionReader.row(
            block: block(ProtectionKind.allCases.map {
                Protection(kind: $0, state: .unreadable(.notReported))
            }),
            details: [], notes: [], managedSentence: nil)

        #expect(row.status == .notChecked)
        #expect(row.complete)
        #expect(row.remedy == nil)
        #expect(row.concerns.isEmpty)
    }

    /// The managed sentence lands on the row, so the section says it once rather than eight times.
    @Test func theManagedSentenceReachesTheRow() {
        let row = ProtectionReader.row(
            block: block([Protection(kind: .fileVault, state: .on)], managed: true),
            details: [], notes: [], managedSentence: "An organisation configures this Mac.")
        #expect(row.reason?.contains("organisation") == true)
    }
}

// MARK: - 11. On this Mac, whatever this Mac happens to be

@Suite struct ProtectionReaderLiveTests {

    /// ⚠️ **This test reads the real machine, and asserts nothing about what it finds.** Every
    /// expectation is about the shape, because the shape is the only thing that is the same on an
    /// M3, on an Intel Mac Pro, and on a build machine with FileVault off.
    ///
    /// It is read-only: `system_profiler`, `spctl --status` and `diskutil info -plist`, plus three
    /// world-readable property lists. Nothing here can raise an authorization dialog, and that is
    /// not an accident — an earlier research round put a system password box on somebody's screen,
    /// which is why this section's rule is that a fact needing elevation *is* the finding.
    @Test func theWholeBlockReadsOnThisMacWithoutLyingAboutAnything() {
        let result = ProtectionReader.read()

        // Every switch appears, once, in the fixed order — including the ones this Mac will not
        // answer about, which say so rather than being quietly missing.
        #expect(result.block.protections.map(\.kind) == ProtectionKind.allCases)

        // Lockdown Mode is never "off". Not on any Mac, not ever.
        #expect(result.block.protection(.lockdownMode)?.state.wasRead == false)
        #expect(result.block.protection(.lockdownMode)?.state != .off)

        // Nothing needs Full Disk Access, so nothing here may ever mark the check incomplete —
        // that caveat is reserved for a refusal somebody can actually lift.
        #expect(result.row.complete)
        #expect(result.row.remedy == nil)

        // A concern can only be one of the nine, and only ever amber.
        for concern in result.row.concerns {
            #expect(SecurityConcern.allCases.contains(concern))
            #expect(concern.severity == .attention)
        }

        // The row and the block cannot disagree about what was found.
        #expect(result.row.concerns == result.block.protections.compactMap(\.concern))
    }

    /// XProtect's date is the file's own or nothing at all. **Never today's**, which would print a
    /// reassuring date for a Mac whose definitions have not updated since last summer.
    @Test func theXProtectDateIsNeverAStandIn() {
        let xprotect = ProtectionReader.xprotectData()
        if let updated = xprotect.updated {
            #expect(updated < Date(), "the definitions cannot have been written in the future")
        }
        // A version we could not read is nil, and `ProtectionsBlock` turns that into the house
        // sentence rather than a blank.
        let block = ProtectionsBlock(protections: [], xprotectVersion: nil, xprotectUpdated: nil)
        #expect(block.detailPairs.contains { $0.value == Unreadable.notReported.sentence })
    }

    /// The whole run has to fit inside a press. It is the second slowest read in the section, after
    /// the six-second log query that settled Security not running on launch.
    @Test func theWholeBlockReadsInUnderThreeSeconds() {
        let started = Date()
        _ = ProtectionReader.read()
        #expect(Date().timeIntervalSince(started) < 3)
    }
}

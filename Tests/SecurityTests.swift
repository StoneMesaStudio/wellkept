import Testing
import Foundation
import WellkeptCore

//  SecurityTests.swift
//  WellkeptTests
//
//  ⭐ **The promises the Security vocabulary is built on, checked by a machine rather than
//  remembered.**
//
//  Six readers are written against `Security.swift` in parallel, by people who will not read each
//  other's files. Every rule below is one somebody could undo in a single well-meaning line, and
//  every one of them is invisible from the outside when it breaks — an amber row nobody named, a
//  caveat on Overview that no button can clear, an employer's setting reported to an employee as
//  their own fault.
//
//   1. **The row order never changes**, and raw values are storage while labels are English.
//   2. **Amber is a closed list of nine**, and a row cannot become amber by any other route.
//   3. **A management fact is never a problem** — enforced in one place, not six.
//   4. **We could not look is never a zero, never a Good, and never a permanent caveat.**
//   5. **Good never stands alone**, and the word "safe" is never a verdict.
//   6. **One row goes up to Overview**, never one per finding.
//
//  ⚠️ Nothing here reads this Mac. Every value is typed out, so the suite gives the same answer on
//  an M3, on an Intel Mac Pro, and on a build machine.

// MARK: - 1. The rows, and what is storage versus what is English

@Suite struct SecurityRowOrderTests {

    /// ⚠️ **`allCases` IS the panel, top to bottom, and it never sorts.** The order was decided on
    /// 2026-08-27 and is not a rendering detail: a person who learns that browser extensions are
    /// the fourth row should still find them there next week, on a Mac where something else has
    /// gone quiet.
    @Test func theRowOrderIsFixed() {
        #expect(SecurityTopic.allCases == [
            .protections, .whoCanWatch, .startsOnItsOwn,
            .browserExtensions, .reachableFrom, .macOSFindings,
        ])
        #expect(SecurityTopic.allCases.map(\.order) == Array(0..<SecurityTopic.allCases.count))
    }

    /// A report built out of order comes back in order. Readers finish when they finish — the log
    /// query alone takes about six seconds — and the panel must not depend on who won the race.
    @Test func aReportPutsRowsBackIntoTheFixedOrder() {
        let report = SecurityReport(block: .unknown, rows: [
            SecurityRow(topic: .macOSFindings, headline: "Nothing found."),
            SecurityRow(topic: .protections, headline: "The protections we can see are on."),
            SecurityRow(topic: .reachableFrom, headline: "Nothing is listening."),
        ])
        #expect(report.rows.map(\.topic) == [.protections, .reachableFrom, .macOSFindings])
    }

    /// A duplicate row is dropped rather than drawn twice. Two readers filing the same topic is a
    /// bug, and drawing both is the version of that bug a person has to work out for themselves.
    @Test func aDuplicateRowIsDropped() {
        let report = SecurityReport(block: .unknown, rows: [
            SecurityRow(topic: .protections, headline: "First."),
            SecurityRow(topic: .protections, headline: "Second."),
        ])
        #expect(report.rows.count == 1)
        #expect(report.rows.first?.headline == "First.")
    }

    /// ⚠️ **A raw value is storage; a label is English**, and `whoCanWatch` is the case that proves
    /// they are allowed to drift apart for ever.
    ///
    /// John's call, 2026-08-27: the screen is labelled for what it lists — camera, microphone,
    /// screen and control — not "Who can watch you". Same rows, different temperature: that title
    /// tells somebody they are being watched before they have read a line, and for almost everyone
    /// nothing is wrong.
    @Test func theRowIsNamedForWhatItListsRatherThanForWhatItFears() {
        #expect(SecurityTopic.whoCanWatch.rawValue == "whoCanWatch")
        #expect(SecurityTopic.whoCanWatch.label == "Camera, microphone, screen and control")
        #expect(!SecurityTopic.whoCanWatch.label.lowercased().contains("watch"))
    }

    /// Every row has words and a sentence, so no row can reach the screen as a bare identifier.
    @Test func everyRowHasWordsOfItsOwn() {
        for topic in SecurityTopic.allCases {
            #expect(!topic.label.isEmpty)
            #expect(!topic.explanation.isEmpty)
            #expect(topic.label != topic.rawValue, "\(topic.rawValue) is showing its raw value")
        }
        #expect(Set(SecurityTopic.allCases.map(\.label)).count == SecurityTopic.allCases.count)
    }
}

// MARK: - 2. ⭐ Amber is a closed list of nine

@Suite struct NineAmberConditionsTests {

    /// ⚠️ **Nine. John kept all nine on 2026-08-27 and struck none.**
    ///
    /// A tenth is a conversation with him, not a pull request — and this is what makes that true
    /// rather than aspirational. Six readers written in parallel would otherwise arrive with ten,
    /// twelve, twenty conditions between them, each defensible alone and collectively a screen of
    /// amber on a healthy Mac.
    @Test func thereAreExactlyNineAndTheyAreTheNineJohnKept() {
        #expect(SecurityConcern.allCases.count == 9)
        #expect(SecurityConcern.allCases == [
            .fileVaultOff,
            .firewallOff,
            .gatekeeperWeakened,
            .systemProtectionOff,
            .bootSecurityReduced,
            .automaticSecurityUpdatesOff,
            .automaticLoginOn,
            .signatureChangedSinceApproved,
            .permissionHeldByMissingApp,
        ])
    }

    /// ⚠️ **Nothing in Security is ever a problem.** Every one of the nine is a setting somebody may
    /// have chosen deliberately, or a machine an employer configured. Amber says "worth a look";
    /// red would say "you have done something wrong", and this section is not in a position to know
    /// that.
    @Test func everyConcernIsAmberAndNoneIsRed() {
        for concern in SecurityConcern.allCases {
            #expect(concern.severity == .attention,
                    "\(concern.rawValue) is not amber — Security has no red")
            #expect(concern.severity != .problem)
        }
    }

    /// Each one says what is true and why it matters, and **none of them tells the user what to
    /// do**. No imperatives: the section states the fact and offers the pane.
    @Test func noConcernGivesAnOrder() {
        for concern in SecurityConcern.allCases {
            #expect(!concern.title.isEmpty)
            #expect(!concern.explanation.isEmpty)
            let words = "\(concern.title) \(concern.explanation)".lowercased()
            #expect(!words.contains("you should"), "\(concern.rawValue) is giving advice")
            #expect(!words.contains("you must"), "\(concern.rawValue) is giving an order")
            #expect(!words.contains("turn on"), "\(concern.rawValue) is telling the user what to do")
        }
    }

    /// ⚠️ **A row cannot be amber without naming which of the nine it is.** `severity` is computed
    /// from `concerns`, not declared beside them, so there is no way for a reader to invent a tenth
    /// condition by writing `.attention` in a constructor.
    @Test func aRowIsAmberOnlyWhenItNamesAConcern() {
        let plain = SecurityRow(topic: .reachableFrom, headline: "Nothing is listening.")
        #expect(plain.severity == .information)
        #expect(plain.status == .good)

        let named = SecurityRow(topic: .protections,
                                headline: "This Mac's disk is not encrypted.",
                                concerns: [.fileVaultOff])
        #expect(named.severity == .attention)
        #expect(named.status == .needsAttention)
    }

    /// Concerns come back de-duplicated and in the fixed order, so two runs on the same Mac produce
    /// the same list in the same order whatever order the reader found things in.
    @Test func concernsAreTidiedIntoTheFixedOrder() {
        let row = SecurityRow(topic: .protections,
                              headline: "Two switches are off.",
                              concerns: [.firewallOff, .fileVaultOff, .firewallOff])
        #expect(row.concerns == [.fileVaultOff, .firewallOff])
    }

    /// Six of the nine are about a switch, and the last two are about apps. That mapping is what
    /// makes "a management fact is never a problem" enforceable in one place.
    @Test func everySwitchConcernPointsAtItsSwitch() {
        #expect(SecurityConcern.fileVaultOff.protection == .fileVault)
        #expect(SecurityConcern.bootSecurityReduced.protection == .secureBoot)
        #expect(SecurityConcern.signatureChangedSinceApproved.protection == nil)
        #expect(SecurityConcern.permissionHeldByMissingApp.protection == nil)

        // And back the other way, so a switch and its concern cannot disagree about each other.
        for concern in SecurityConcern.allCases {
            guard let kind = concern.protection else { continue }
            #expect(kind.concern == concern, "\(kind.rawValue) and \(concern.rawValue) disagree")
        }
    }

    /// ⚠️ **Lockdown Mode has no readable state anywhere**, so it has no amber condition — and its
    /// row must never say "off". Saying off about something nothing can read is the confident wrong
    /// answer this product exists to avoid.
    @Test func lockdownModeRaisesNothingBecauseNothingCanReadIt() {
        #expect(ProtectionKind.lockdownMode.concern == nil)

        let row = Protection(kind: .lockdownMode, state: .unreadable(.notReported))
        #expect(row.concern == nil)
        #expect(row.isProtecting == nil, "an unread switch reported a verdict")
        #expect(row.state.label != "Off")
    }

    /// ⚠️ **Automatic login is the one where being on is the concern.** A view that ticks "on" as
    /// good would otherwise congratulate somebody on a Mac that signs itself in with no password.
    @Test func automaticLoginIsTheOneWhereOnIsTheWrongWay() {
        #expect(ProtectionKind.automaticLogin.onIsTheSafeState == false)
        for kind in ProtectionKind.allCases where kind != .automaticLogin {
            #expect(kind.onIsTheSafeState)
        }

        #expect(Protection(kind: .automaticLogin, state: .on).concern == .automaticLoginOn)
        #expect(Protection(kind: .automaticLogin, state: .off).concern == nil)
        #expect(Protection(kind: .fileVault, state: .off).concern == .fileVaultOff)
        #expect(Protection(kind: .fileVault, state: .on).concern == nil)
    }

    /// Reduced is not off, and it raises the concern anyway. Gatekeeper with exceptions and secure
    /// boot below Full Security are both "on, but not at full strength" — calling either one off
    /// would be wrong in a way that matters to somebody who reduced it deliberately.
    @Test func reducedIsItsOwnStateAndStillCounts() {
        let boot = Protection(kind: .secureBoot, state: .reduced, detail: "Permissive Security")
        #expect(boot.state.label == "Reduced")
        #expect(boot.isProtecting == false)
        #expect(boot.concern == .bootSecurityReduced)
    }
}

// MARK: - 3. ⭐ A management fact is never a problem

@Suite struct ManagedMacTests {

    /// ⚠️ **The whole point of detecting a managed Mac.** A Mac whose settings were chosen by an
    /// employer is not a Mac with faults, and a health check that says otherwise is an accusation
    /// aimed at somebody who cannot act on it.
    @Test func anOrganisationSetSwitchRaisesNothing() {
        let managed = Protection(kind: .firewall, state: .off, setByOrganisation: true)
        #expect(managed.concern == nil)
        #expect(managed.isProtecting == false, "the reading is still honest, it is just not a fault")
    }

    /// ⚠️ **Enforced in one place, so six readers cannot each forget.** A reader that hands in the
    /// concern anyway has it dropped before it reaches the status chip, Overview or the audit
    /// trail.
    @Test func aConcernAboutAManagedSwitchIsDroppedByTheReport() {
        let block = ProtectionsBlock(
            protections: [Protection(kind: .firewall, state: .off, setByOrganisation: true)],
            isManaged: true)

        let report = SecurityReport(block: block, rows: [
            SecurityRow(topic: .protections,
                        headline: "The firewall is off.",
                        concerns: [.firewallOff]),
        ])

        #expect(report.concerns.isEmpty, "an employer's setting reached the user as their fault")
        #expect(report.status == .good)
        #expect(report.overviewFinding == nil)
    }

    /// A concern about something the organisation did **not** set survives on the same Mac. Managed
    /// does not mean silent.
    @Test func aManagedMacStillReportsWhatItsOwnerDid() {
        let block = ProtectionsBlock(
            protections: [
                Protection(kind: .firewall, state: .off, setByOrganisation: true),
                Protection(kind: .fileVault, state: .off),
            ],
            isManaged: true)

        let report = SecurityReport(block: block, rows: [
            SecurityRow(topic: .protections,
                        headline: "Two switches are off.",
                        concerns: [.firewallOff, .fileVaultOff]),
        ])

        #expect(report.concerns == [.fileVaultOff])
        #expect(report.status == .needsAttention)
        #expect(report.overviewFinding?.reason.contains("organisation") == true,
                "a managed Mac's Overview row does not say the settings are not this person's")
    }

    /// A button that cannot work is not offered. A pane a person has no authority over is a door
    /// that opens onto a greyed-out switch.
    @Test func aManagedSwitchOffersNoButton() {
        let managed = Protection(kind: .fileVault,
                                 state: .off,
                                 setByOrganisation: true,
                                 settingsPane: "privacyAndSecurity")
        #expect(managed.settingsPane == nil)

        let ordinary = Protection(kind: .fileVault, state: .off, settingsPane: "privacyAndSecurity")
        #expect(ordinary.settingsPane == "privacyAndSecurity")
    }

    /// The block says it is managed, and says so as a fact rather than as a finding. It carries no
    /// status at all — inventory, never a verdict.
    @Test func theBlockStatesManagementAsAFact() {
        let block = ProtectionsBlock(protections: [], isManaged: true)
        #expect(block.detailPairs.contains { $0.value.lowercased().contains("organisation") })
    }
}

// MARK: - 4. We could not look is never a zero, never a Good, never a permanent caveat

@Suite struct SecurityUnreadableTests {

    /// ⚠️ **The rule the whole section rests on.** Without Full Disk Access eleven of the twelve
    /// permissions read exactly zero. "No app can see your camera" would be the most comforting
    /// sentence this app could print and the most dishonest.
    @Test func aRowWeCouldNotReadCarriesNoFigure() {
        let sneaky = SecurityRow(topic: .whoCanWatch,
                                 headline: "ignored",
                                 measure: "0 apps",
                                 concerns: [.permissionHeldByMissingApp],
                                 unreadable: .notPermitted)
        #expect(sneaky.measure == nil, "an unread row kept a figure — it will print as zero apps")
        #expect(sneaky.concerns.isEmpty, "an unread row raised a concern about what it did not see")
        #expect(sneaky.status == .notChecked)
        #expect(sneaky.severity == .information)
    }

    /// The house sentence, unchanged from Hardware. One wording for the whole app, so six sections
    /// cannot invent six ways of saying nothing.
    @Test func theHouseSentenceIsTheSameSentence() {
        let row = SecurityRow.unreadable(.whoCanWatch, .notPermitted)
        #expect(row.headline == "Camera, microphone, screen and control — we were not allowed to look.")

        let named = SecurityRow.unreadable(.protections, .notGrantable, about: "The recovery key")
        #expect(named.headline == "The recovery key — there is no permission that would let us see it.")
    }

    /// ⚠️ **The bug this section forced into the open.** Every root-only Security fact — the
    /// FileVault recovery key, which accounts can unlock the Mac, Gatekeeper's exception list, the
    /// Intel firmware password, Apple's own login-items store — is a refusal nobody can lift.
    ///
    /// Under the old two-state `Unreadable`, each one made the check incomplete, so **100% of Macs,
    /// including a flawlessly configured one**, would have carried "I could not see everything" on
    /// Overview for ever, with no button anywhere that could clear it.
    @Test func aRootOnlyFactDoesNotLeaveEveryMacPermanentlyIncomplete() {
        let report = SecurityReport(block: .unknown, rows: [
            SecurityRow.unreadable(.protections, .notGrantable, about: "The FileVault recovery key"),
            SecurityRow(topic: .macOSFindings, headline: "macOS found nothing."),
        ], measuredDays: 12)

        #expect(report.complete, "every Mac on earth is now permanently 'incomplete'")
        #expect(report.record.complete)
        #expect(report.status == .good)

        // Still said out loud. What was dropped is the caveat nobody could clear, not the fact.
        #expect(report.unreadableTopics.map(\.why) == [.notGrantable])
    }

    /// Full Disk Access is the opposite: a refusal that a person can lift, so the caveat belongs on
    /// Overview because pressing something clears it.
    @Test func aRefusedGrantIsWhatMakesTheCheckIncomplete() {
        let report = SecurityReport(block: .unknown, rows: [
            SecurityRow.unreadable(.whoCanWatch, .notPermitted,
                                   remedy: Remedy(title: "Open Settings",
                                                  settingsPane: "fullDiskAccess")),
        ])
        #expect(!report.complete)
        #expect(!report.record.complete)
        #expect(report.record.section == .security)
        #expect(report.row(.whoCanWatch)?.remedy != nil)
    }

    /// And only that one gets a button. A "Fix this" under "there is no permission that would let
    /// us see it" is a button that cannot work.
    @Test func onlyARefusalSomebodyCanLiftGetsAButton() {
        let offered = Remedy(title: "Open Settings", settingsPane: "fullDiskAccess")
        #expect(SecurityRow.unreadable(.protections, .notGrantable, remedy: offered).remedy == nil)
        #expect(SecurityRow.unreadable(.protections, .notReported, remedy: offered).remedy == nil)
        #expect(SecurityRow.unreadable(.protections, .notPermitted, remedy: offered).remedy == offered)
        #expect(SecurityRow(topic: .protections, headline: "Fine.", remedy: offered).remedy == nil)
    }

    /// A section that read nothing at all is Not checked. A section that read five rows and was
    /// refused the sixth **was** checked.
    @Test func anEmptyReportIsNotCheckedButAPartlyRefusedOneIsNot() {
        #expect(SecurityReport(block: .unknown, rows: []).status == .notChecked)
        #expect(SecurityReport(block: .unknown, rows: [
            SecurityRow.unreadable(.whoCanWatch, .notPermitted),
        ]).status == .good)
    }

    /// The placeholder block before anything has been read says so on every switch. Nothing in it
    /// is a guess dressed as a fact, and in particular nothing in it says "off".
    @Test func theUncheckedBlockClaimsNothing() {
        for protection in ProtectionsBlock.unknown.protections {
            #expect(protection.state.wasRead == false)
            #expect(protection.isProtecting == nil)
            #expect(protection.concern == nil)
            #expect(protection.state.label != "Off")
        }
    }
}

// MARK: - 5. Good never stands alone, and "safe" is never a verdict

@Suite struct GoodNeverStandsAloneTests {

    /// ⚠️ **The measured window, never an assumed one.** `OSLogStore` reaches back about a
    /// fortnight, and how far is set by how chatty this Mac has been — so it differs between two
    /// Macs and between two weeks on the same Mac. "macOS found nothing" is only worth anything
    /// beside how far back that "nothing" reaches.
    @Test func theCleanSentenceCarriesItsScopeAndItsWindow() {
        let report = SecurityReport(block: .unknown, rows: [
            SecurityRow(topic: .macOSFindings, headline: "macOS found nothing."),
        ], measuredDays: 12)

        #expect(report.status == .good)
        #expect(report.summary.contains("12 days"))
        #expect(report.summary.contains("protections we can see"))
    }

    /// ⚠️ **A window we could not measure is said, not invented.** Printing an assumed 14 would be
    /// a number nobody measured, on the one sentence in the section that is a claim about time.
    @Test func anUnmeasuredWindowIsNeverGuessed() {
        let report = SecurityReport(block: .unknown, rows: [
            SecurityRow(topic: .macOSFindings, headline: "macOS found nothing."),
        ])
        #expect(!report.summary.contains("14"))
        #expect(!report.windowClause.contains("14"))
        #expect(report.windowClause.contains("how far back"))
    }

    /// A run that was refused something says so in the same sentence, rather than claiming a scope
    /// it did not have.
    @Test func anIncompleteRunNarrowsItsOwnClaim() {
        let report = SecurityReport(block: .unknown, rows: [
            SecurityRow(topic: .macOSFindings, headline: "macOS found nothing."),
            SecurityRow.unreadable(.whoCanWatch, .notPermitted),
        ], measuredDays: 9)
        #expect(report.summary.contains("were allowed to see"))
    }

    /// ⚠️ **The word "safe" never appears as a verdict.** Wellkept is not watching in real time and
    /// must not imply that it is — the one sentence that would make somebody stop looking is the
    /// one this section may never print.
    @Test func theWordSafeIsNeverAVerdict() {
        let clean = SecurityReport(block: .unknown, rows: [
            SecurityRow(topic: .macOSFindings, headline: "macOS found nothing."),
        ], measuredDays: 12)

        let words = "\(clean.summary) \(clean.windowClause)".lowercased()
        #expect(!words.contains("safe"))
        #expect(!words.contains("secure"))
        #expect(!words.contains("protected"))
    }
}

// MARK: - 6. One row goes up to Overview

@Suite struct SecurityOverviewTests {

    /// ⚠️ **One row, not one per finding.** A section that posts nine rows to Overview has turned
    /// the summary into a second copy of itself, and the section a person should actually open gets
    /// lost among its own details.
    @Test func nineConcernsProduceOneOverviewRow() {
        let report = SecurityReport(block: .unknown, rows: [
            SecurityRow(topic: .protections,
                        headline: "Several switches are off.",
                        concerns: [.fileVaultOff, .firewallOff, .systemProtectionOff]),
            SecurityRow(topic: .whoCanWatch,
                        headline: "An app has changed.",
                        concerns: [.signatureChangedSinceApproved]),
        ])

        let finding = report.overviewFinding
        #expect(finding != nil)
        #expect(finding?.section == .security)
        #expect(finding?.severity == .attention)
        #expect(finding?.title == SecurityConcern.fileVaultOff.title)
        #expect(finding?.reason.contains("3 more in Security") == true)
        #expect(report.concerns.count == 4)
    }

    /// A clean Mac sends nothing up. Overview lists only what needs you.
    @Test func aCleanRunSendsNothingUp() {
        let report = SecurityReport(block: .unknown, rows: SecurityTopic.allCases.map {
            SecurityRow(topic: $0, headline: "Nothing here needs you.")
        }, measuredDays: 12)
        #expect(report.overviewFinding == nil)
        #expect(report.status == .good)
        #expect(report.complete)
    }

    /// The Overview row carries the reason, always. A flagged item with no reason is an accusation;
    /// the reason is what lets a person disagree with us.
    @Test func theOverviewRowAlwaysCarriesItsReason() {
        let report = SecurityReport(block: .unknown, rows: [
            SecurityRow(topic: .whoCanWatch,
                        headline: "A permission is held by an app that is gone.",
                        concerns: [.permissionHeldByMissingApp]),
        ])
        #expect(report.overviewFinding?.reason.isEmpty == false)
        #expect(report.overviewFinding?.measure == nil, "one concern does not need a count")
    }
}

// MARK: - 7. One app, one permission

@Suite struct GrantTests {

    /// ⚠️ **Eleven of the twelve need Full Disk Access; Location is the one that does not.**
    /// Measured on this Mac, 2026-08-27 — and it is the strongest true reason to grant the
    /// permission, which setup was previously selling on storage.
    @Test func onlyLocationReadsWithoutFullDiskAccess() {
        let free = Permission.allCases.filter { !$0.needsFullDiskAccessToRead }
        #expect(free == [.location])
        #expect(Permission.allCases.count == 12)
    }

    /// The three that make concern 8 a concern — the camera, the microphone and the screen. An app
    /// that changed identity while holding your contacts is worth knowing about; an app that
    /// changed identity while holding your camera is the one this rule is for.
    @Test func theWatchingThreeAreTheWatchingThree() {
        #expect(Permission.allCases.filter(\.watchesYou) == [.camera, .microphone, .screenRecording])
    }

    /// A changed signature on a watching permission is amber. On any other permission it is not —
    /// the list would otherwise fill with amber on any Mac whose apps have updated.
    @Test func aChangedSignatureIsAmberOnlyWhereItWatchesYou() {
        let camera = Grant(appName: "Something", bundleID: "com.example.thing",
                           permission: .camera, signature: .changed)
        #expect(camera.concern == .signatureChangedSinceApproved)

        let calendars = Grant(appName: "Something", bundleID: "com.example.thing",
                              permission: .calendars, signature: .changed)
        #expect(calendars.concern == nil)
    }

    /// A permission held by an app that is gone is the ninth condition — and it is reported instead
    /// of the signature, not as well: an app that is not there cannot have its signature compared,
    /// and saying both would be reporting the same absence twice.
    @Test func aMissingAppIsReportedOnceRatherThanTwice() {
        let ghost = Grant(appName: "Gone", bundleID: "com.example.gone",
                          permission: .camera, stillInstalled: false, signature: .unknown)
        #expect(ghost.concern == .permissionHeldByMissingApp)
    }

    /// ⚠️ **An unchecked signature is not an accused one.** `.unknown` is neither a match nor a
    /// change, and it raises nothing.
    @Test func anUncheckedSignatureRaisesNothing() {
        let unchecked = Grant(appName: "Zoom", bundleID: "us.zoom.xos",
                              permission: .camera, signature: .unknown)
        #expect(unchecked.concern == nil)
    }

    /// One row per app-and-permission pair, not per app. "Zoom has the camera" and "Zoom has the
    /// microphone" are two things a person may feel differently about, and merging them hides the
    /// one they would have removed.
    @Test func identityIsTheAppAndThePermissionTogether() {
        let camera = Grant(appName: "Zoom", bundleID: "us.zoom.xos", permission: .camera)
        let microphone = Grant(appName: "Zoom", bundleID: "us.zoom.xos", permission: .microphone)
        #expect(camera.id != microphone.id)
    }

    /// ⚠️ **Wellkept holds Full Disk Access, so Wellkept appears in its own list.** John's call,
    /// 2026-08-27: say so rather than filter ourselves out. An app that quietly removes itself from
    /// the list of apps that can read your disk is doing the thing this app exists to catch other
    /// software doing.
    @Test func wellkeptCanSayThatItIsInItsOwnList() {
        let us = Grant(appName: "Wellkept", bundleID: "studio.stonemesa.wellkept",
                       permission: .fullDiskAccess, isWellkept: true)
        #expect(us.isWellkept)
        #expect(us.concern == nil)
    }
}

// MARK: - 8. ⭐ A Mac that could be read is never reported incomplete
//
//  ⚠️ **The regression guard on the bug that was found on 2026-08-27 and fixed the same day.**
//
//  `Unreadable` had two cases. Every root-only Security fact — the FileVault recovery key, who can
//  unlock the Mac, Gatekeeper's exception list, the Intel firmware password, Apple's own login-items
//  store — came back as the refused one, which set `complete = false`. Not on an unusual Mac: on
//  **every** Mac, including one where nothing at all was wrong, for ever, with no button anywhere
//  that could clear it.
//
//  That is the warning-nobody-can-clear this entire product exists to avoid, and it was two lines
//  from shipping. The third case is the fix; this suite is what keeps it fixed.

@Suite struct CompletenessRegressionTests {

    /// A run where all six rows read is complete, and says so in the audit trail as well as in the
    /// section's own sentence. This is the ordinary Mac and it must never wear a caveat.
    @Test func aMacThatWasFullyReadIsComplete() {
        let report = Self.wholeSection()

        #expect(report.rows.count == SecurityTopic.allCases.count)
        #expect(report.complete)
        #expect(report.record.complete)
        #expect(report.unreadableTopics.isEmpty)
        // The face prints "but it could not see everything" off `record.complete`. This is the
        // exact value that sentence hangs on.
        #expect(report.record.status == .good)
        #expect(report.summary.contains("protections we can see"),
                "a fully-read Mac narrowed its own claim as though something had been refused")
    }

    /// ⚠️ **The whole table, in one test.** Three refusal kinds, six rows, one refusal at a time:
    /// the run is incomplete **if and only if** the refusal is one a person can actually lift.
    ///
    /// Getting this backwards in either direction is a shipped bug. Too strict, and every Mac is
    /// permanently incomplete. Too lax, and a Mac that refused Full Disk Access reports a clean
    /// bill of health for a look it was never allowed to take.
    @Test func onlyARefusalSomebodyCanLiftMakesARunIncomplete() {
        for topic in SecurityTopic.allCases {
            for why in Unreadable.allCases {
                let rows = SecurityTopic.allCases.map { candidate in
                    candidate == topic
                        ? SecurityRow.unreadable(candidate, why)
                        : SecurityRow(topic: candidate, headline: "Nothing here needs you.")
                }
                let report = SecurityReport(block: .unknown, rows: rows, measuredDays: 12)

                #expect(report.complete == (why != .notPermitted),
                        "\(topic.rawValue) refused with \(why.rawValue) got completeness wrong")
                #expect(report.record.complete == report.complete)
                // Either way the fact is still said out loud. What the third case dropped is the
                // caveat nobody could clear, never the sentence explaining what was not seen.
                #expect(report.unreadableTopics.map(\.topic) == [topic])
                #expect(report.row(topic)?.headline.isEmpty == false)
            }
        }
    }

    /// The three cases, and which of them a person can do something about. `.notGrantable` is the
    /// case that was missing, and it is the one nearly every Security refusal actually is.
    @Test func theThreeRefusalsDoThreeDifferentThings() {
        #expect(Unreadable.allCases.count == 3)

        #expect(Unreadable.notReported.stillComplete)
        #expect(!Unreadable.notReported.wasRefused)
        #expect(!Unreadable.notReported.mayOfferRemedy)

        #expect(!Unreadable.notPermitted.stillComplete)
        #expect(Unreadable.notPermitted.wasRefused)
        #expect(Unreadable.notPermitted.mayOfferRemedy)

        #expect(Unreadable.notGrantable.stillComplete)
        #expect(Unreadable.notGrantable.wasRefused)
        #expect(!Unreadable.notGrantable.mayOfferRemedy,
                "a button under “there is no permission that would let us see it”")
    }

    /// ⚠️ **Raw values were added, not renumbered.** They travel in a saved `CheckRecord`, so
    /// renaming one silently reclassifies a Mac's history — and the two that existed before the fix
    /// have to keep meaning what they meant.
    @Test func theRefusalRawValuesArePermanent() {
        #expect(Unreadable.notReported.rawValue == "notReported")
        #expect(Unreadable.notPermitted.rawValue == "notPermitted")
        #expect(Unreadable.notGrantable.rawValue == "notGrantable")
    }

    /// Five root-only facts on one Mac, all of them stated, and the run is still complete. This is
    /// the shape of a real healthy Mac's Security check rather than an invented corner.
    @Test func aMacFullOfRootOnlyRefusalsIsStillAMacWeCouldRead() {
        let report = SecurityReport(block: .unknown, rows: [
            SecurityRow(topic: .protections,
                        headline: "Everything this Mac reports is set the way it protects you.",
                        details: [
                            DetailPair("Recovery key", unreadable: .notGrantable),
                            DetailPair("Who can unlock this Mac", unreadable: .notGrantable),
                            DetailPair("Gatekeeper exceptions", unreadable: .notGrantable),
                        ]),
            SecurityRow(topic: .whoCanWatch, headline: "Nine apps hold a permission."),
            SecurityRow.unreadable(.startsOnItsOwn, .notGrantable,
                                   about: "Apple's own list of login items"),
            SecurityRow(topic: .browserExtensions, headline: "Five extensions are installed."),
            SecurityRow(topic: .reachableFrom, headline: "AirPlay Receiver is listening."),
            SecurityRow(topic: .macOSFindings, headline: "macOS's own scanners found nothing."),
        ], measuredDays: 13)

        #expect(report.complete, "every Mac on earth is permanently 'incomplete' again")
        #expect(report.status == .good)
        #expect(report.overviewFinding == nil)
    }

    /// A whole, clean, fully-read section. Used by more than one test above, so the shape of "the
    /// ordinary Mac" is written down once.
    static func wholeSection(measuredDays: Int = 12) -> SecurityReport {
        SecurityReport(block: ProtectionsBlock(
            protections: [
                Protection(kind: .fileVault, state: .on),
                Protection(kind: .systemProtection, state: .on),
                Protection(kind: .gatekeeper, state: .on),
                Protection(kind: .secureBoot, state: .on, detail: "Full Security"),
                Protection(kind: .firewall, state: .on, detail: "limiting incoming connections"),
                Protection(kind: .automaticSecurityUpdates, state: .on),
                Protection(kind: .automaticLogin, state: .off),
                Protection(kind: .lockdownMode, state: .unreadable(.notReported)),
            ],
            xprotectVersion: "5357"),
        rows: SecurityTopic.allCases.map {
            SecurityRow(topic: $0, headline: "Nothing here needs you.")
        }, measuredDays: measuredDays)
    }
}

// MARK: - 9. Raw values are storage; labels are English

@Suite struct SecurityStorageWordsTests {

    /// ⚠️ **Every topic raw value, pinned.** These are what a stored report is keyed by. Renaming
    /// one is a silent data migration; renaming a *label* is a wording change that costs nothing,
    /// and the two are kept apart on purpose — `whoCanWatch` has already drifted, deliberately.
    @Test func everyTopicRawValueIsPermanent() {
        #expect(SecurityTopic.allCases.map(\.rawValue) == [
            "protections", "whoCanWatch", "startsOnItsOwn",
            "browserExtensions", "reachableFrom", "macOSFindings",
        ])
    }

    /// The switches too — they key the block, and the block is what a Changes comparison will one
    /// day diff against yesterday's.
    @Test func everySwitchRawValueIsPermanent() {
        #expect(ProtectionKind.allCases.map(\.rawValue) == [
            "fileVault", "systemProtection", "gatekeeper", "secureBoot",
            "firewall", "automaticSecurityUpdates", "automaticLogin", "lockdownMode",
        ])
        #expect(Permission.allCases.map(\.rawValue).first == "camera")
        #expect(Permission.allCases.map(\.rawValue).contains("screenRecording"))
    }

    /// A report survives being written down and read back. Nothing in Security is stored yet — and
    /// the day it is, the shape has to already work, because the alternative is discovering it
    /// against a file somebody's Mac already wrote.
    @Test func aRowSurvivesBeingStoredAndReadBack() throws {
        let row = SecurityRow(topic: .whoCanWatch,
                              headline: "Nine apps hold a permission.",
                              measure: "9 apps",
                              concerns: [.permissionHeldByMissingApp],
                              reason: "One of them is no longer installed.",
                              details: [DetailPair("Camera", "3 apps")])
        let data = try JSONEncoder().encode(row)
        let back = try JSONDecoder().decode(SecurityRow.self, from: data)
        #expect(back == row)
        #expect(back.severity == .attention)
        #expect(back.status == .needsAttention)
    }
}

// MARK: - 10. A managed Mac is described, never blamed

@Suite struct ManagedMacHasNoImperativesTests {

    /// A Mac where an organisation has turned three protections off. Every one of them is stated as
    /// a fact, none of them is a finding, and nothing on the screen suggests the person reading it
    /// has done anything wrong — because they cannot change any of it.
    @Test func aWorkMacWithThreeSwitchesOffIsGoodAndSaysWhy() {
        let report = Self.workMac()

        #expect(report.status == .good)
        #expect(report.concerns.isEmpty)
        #expect(report.overviewFinding == nil)
        #expect(report.complete)

        // The facts are still on the block, labelled for what they are.
        #expect(report.block.detailPairs.filter { $0.value.contains("set by an organisation") }.count == 3)
        #expect(report.block.detailPairs.contains { $0.value.contains("An organisation configures") })
    }

    /// ⚠️ **No imperative reaches the screen on a managed Mac**, on the row, in the summary, or in
    /// the audit trail — and no button either, because the pane behind it opens onto a switch this
    /// person cannot move.
    @Test func nothingAManagedMacSaysTellsAnybodyToDoAnything() {
        let report = Self.workMac()
        var everySentence = [report.summary, report.windowClause]
        everySentence += report.rows.flatMap { [$0.headline, $0.reason ?? ""] }
        everySentence += report.block.detailPairs.map(\.value)

        for sentence in everySentence {
            let words = sentence.lowercased()
            for order in ["you should", "you must", "you need to", "turn on", "turn off", "fix "] {
                #expect(!words.contains(order), "a managed Mac is being given an order: “\(sentence)”")
            }
        }

        for protection in report.block.protections where protection.setByOrganisation {
            #expect(protection.settingsPane == nil, "\(protection.kind.rawValue) offers a dead button")
        }
    }

    /// Managed does not mean silent. A switch the organisation did **not** set still speaks — and
    /// the Overview row it produces names the organisation so the person is not left thinking every
    /// setting on the machine is theirs.
    @Test func theOneThingTheOrganisationDidNotSetIsStillReported() {
        let report = SecurityReport(block: ProtectionsBlock(
            protections: [
                Protection(kind: .firewall, state: .off, setByOrganisation: true),
                Protection(kind: .automaticLogin, state: .on),
            ],
            isManaged: true),
        rows: [
            SecurityRow(topic: .protections,
                        headline: "Two switches are not in the protecting position.",
                        concerns: [.firewallOff, .automaticLoginOn]),
        ], measuredDays: 12)

        #expect(report.concerns == [.automaticLoginOn])
        #expect(report.status == .needsAttention)
        #expect(report.overviewFinding?.title == SecurityConcern.automaticLoginOn.title)
        #expect(report.overviewFinding?.reason.contains("organisation") == true)
        #expect(report.overviewFinding?.severity == .attention)
    }

    /// ⚠️ **Every one of the nine, dropped when an organisation set it.** Not the seven somebody
    /// remembered — all seven that belong to a switch, checked one at a time, plus proof that the
    /// two app-shaped ones are untouched by enrolment, because no employer sets those.
    @Test func everySwitchConcernIsDroppedWhenAnOrganisationSetIt() {
        for concern in SecurityConcern.allCases {
            guard let kind = concern.protection else { continue }
            let report = SecurityReport(block: ProtectionsBlock(
                protections: [Protection(kind: kind,
                                         state: kind == .automaticLogin ? .on : .off,
                                         setByOrganisation: true)],
                isManaged: true),
            rows: [SecurityRow(topic: concern.topic, headline: "One switch.", concerns: [concern])],
            measuredDays: 12)

            #expect(report.concerns.isEmpty, "\(concern.rawValue) reached the user as their fault")
            #expect(report.status == .good)
        }

        // And the two that are about apps, on the same managed Mac, are unaffected.
        let apps = SecurityReport(block: ProtectionsBlock(
            protections: [Protection(kind: .firewall, state: .off, setByOrganisation: true)],
            isManaged: true),
        rows: [SecurityRow(topic: .whoCanWatch,
                           headline: "An app is gone and its permission is not.",
                           concerns: [.permissionHeldByMissingApp])],
        measuredDays: 12)
        #expect(apps.concerns == [.permissionHeldByMissingApp])
    }

    static func workMac() -> SecurityReport {
        SecurityReport(block: ProtectionsBlock(
            protections: [
                Protection(kind: .fileVault, state: .on),
                Protection(kind: .firewall, state: .off, setByOrganisation: true,
                           settingsPane: "firewall"),
                Protection(kind: .gatekeeper, state: .reduced, setByOrganisation: true),
                Protection(kind: .automaticSecurityUpdates, state: .off, setByOrganisation: true),
            ],
            xprotectVersion: "5357",
            isManaged: true),
        rows: [
            SecurityRow(topic: .protections,
                        headline: "Three of this Mac's protections are set by an organisation.",
                        concerns: [.firewallOff, .gatekeeperWeakened, .automaticSecurityUpdatesOff],
                        reason: "An organisation configures this Mac, so these are not this "
                              + "account's settings to change."),
            SecurityRow(topic: .whoCanWatch, headline: "Nine apps hold a permission."),
            SecurityRow(topic: .startsOnItsOwn, headline: "Five things start on their own."),
            SecurityRow(topic: .browserExtensions, headline: "Three extensions are installed."),
            SecurityRow(topic: .reachableFrom, headline: "Nothing was seen listening."),
            SecurityRow(topic: .macOSFindings, headline: "macOS's own scanners found nothing."),
        ], measuredDays: 12)
    }
}

// MARK: - 11. Holding a permission is not a finding

@Suite struct HoldingAPermissionIsOrdinaryTests {

    /// ⚠️ **Twelve apps holding all twelve permissions, and the answer is Good.** This is the
    /// commonest screen in the section, and the temptation — a row of amber beside every app that
    /// can see the camera — is exactly what turns a health check into the thing people uninstall.
    @Test func aMacWhereEveryPermissionIsHeldIsStillAGoodMac() {
        var grants: [Grant] = []
        for (index, permission) in Permission.allCases.enumerated() {
            grants.append(Grant(appName: "App \(index)",
                                bundleID: "com.example.app\(index)",
                                permission: permission,
                                signature: .matches))
        }

        #expect(grants.count == 12)
        #expect(grants.compactMap(\.concern).isEmpty)

        let row = SecurityRow(topic: .whoCanWatch,
                              headline: "Twelve apps hold a permission between them.",
                              measure: "12 apps",
                              concerns: grants.compactMap(\.concern))
        #expect(row.severity == .information)
        #expect(row.status == .good)
    }

    /// The two that do count, side by side with the ten that do not — same apps, same permissions,
    /// one changed signature and one app that is gone.
    @Test func aChangedSignatureAndAGhostAreTheOnlyTwoThatSpeak() {
        let grants = [
            Grant(appName: "Zoom", bundleID: "us.zoom.xos", permission: .camera, signature: .matches),
            Grant(appName: "Zoom", bundleID: "us.zoom.xos", permission: .microphone, signature: .matches),
            Grant(appName: "Something", bundleID: "com.example.thing",
                  permission: .screenRecording, signature: .changed),
            Grant(appName: "An app that is gone", bundleID: "com.example.gone",
                  permission: .microphone, stillInstalled: false),
            Grant(appName: "Wellkept", bundleID: "studio.stonemesa.wellkept",
                  permission: .fullDiskAccess, signature: .matches, isWellkept: true),
        ]

        let raised = grants.compactMap(\.concern)
        #expect(raised.count == 2)

        let row = SecurityRow(topic: .whoCanWatch,
                              headline: "Five apps hold a permission.",
                              measure: "5 apps",
                              concerns: raised)
        #expect(row.concerns == [.signatureChangedSinceApproved, .permissionHeldByMissingApp])
        #expect(row.severity == .attention)
    }

    /// ⚠️ A changed signature on Contacts is not amber, and a changed signature on the camera is.
    /// All twelve, one at a time — because the difference is the whole reason concern 8 is narrow.
    @Test func onlyTheWatchingThreeCareAboutAChangedSignature() {
        for permission in Permission.allCases {
            let grant = Grant(appName: "Something", bundleID: "com.example.thing",
                              permission: permission, signature: .changed)
            #expect((grant.concern != nil) == permission.watchesYou,
                    "\(permission.rawValue) got concern 8 wrong")
        }
    }
}

// MARK: - 12. The window is measured, and the sentence says the number that was measured

@Suite struct MeasuredWindowTests {

    /// ⚠️ **Whatever the log actually reached back to is the number on the screen.** No default, no
    /// rounding to a fortnight, no constant. It was 14 days on this Mac in the morning and 13 by
    /// the afternoon — a number typed into the code would have been wrong inside a working day.
    @Test func theSentenceCarriesTheNumberItWasGiven() {
        for days in [1, 2, 7, 9, 12, 13, 14, 30, 90] {
            let report = SecurityReport(block: .unknown, rows: [
                SecurityRow(topic: .macOSFindings, headline: "macOS's own scanners found nothing."),
            ], measuredDays: days)

            let expected = days == 1 ? "in the last day" : "in the last \(days) days"
            #expect(report.windowClause == expected)
            #expect(report.summary.contains(expected))

            // And no other number sneaks in beside it.
            for other in [1, 7, 12, 13, 14, 30, 90] where other != days {
                #expect(!report.summary.contains("last \(other) day"),
                        "a \(days)-day window printed \(other) as well")
            }
        }
    }

    /// A window nobody could measure is admitted, and `nil` is a real answer rather than a bug. The
    /// shrug is the one sentence in the section that must never be replaced with a plausible
    /// number.
    @Test func anUnmeasuredWindowStaysUnmeasured() {
        let report = SecurityReport(block: .unknown, rows: [
            SecurityRow(topic: .macOSFindings, headline: "macOS's own scanners found nothing."),
        ])
        #expect(report.measuredDays == nil)
        #expect(report.windowClause == "in the records it still keeps, which do not say how far back they go")
        for digit in "0123456789" { #expect(!report.windowClause.contains(digit)) }
    }

    /// A window of zero days is not a window. It comes back as the shrug rather than "in the last 0
    /// days", which would be a sentence that means nothing and sounds precise.
    @Test func zeroDaysIsNotPrintedAsAWindow() {
        for days in [0, -1] {
            let report = SecurityReport(block: .unknown, rows: [
                SecurityRow(topic: .macOSFindings, headline: "Nothing."),
            ], measuredDays: days)
            #expect(!report.windowClause.contains("0 days"))
            #expect(report.windowClause.contains("how far back"))
        }
    }
}

// MARK: - 13. "Safe" is never a verdict — the whole section, not one sentence

@Suite struct NothingCallsThisMacSafeTests {

    /// ⚠️ **Every sentence a finished run can put on the screen**, across a clean Mac, a Mac with
    /// every one of the nine raised, a refused Mac and a managed one — swept for the one word this
    /// section may never use as a verdict.
    ///
    /// Wellkept looks when it is asked and never again. "Safe" says something is true *now*, and
    /// the moment somebody believes that, the app has replaced their judgement with its own.
    @Test func noSentenceAnyRunCanProduceCallsThisMacSafe() {
        var sentences: [String] = []

        for report in Self.everyShapeOfRun() {
            sentences += [report.summary, report.windowClause]
            sentences += report.rows.flatMap { [$0.headline, $0.reason ?? "", $0.measure ?? ""] }
            sentences += report.block.detailPairs.flatMap { [$0.label, $0.value] }
            if let finding = report.overviewFinding {
                sentences += [finding.title, finding.reason, finding.measure ?? ""]
            }
        }

        #expect(sentences.count > 100, "the sweep looked at almost nothing")
        for sentence in sentences {
            let words = sentence.lowercased()
            #expect(!words.contains("safe"), "“\(sentence)”")
            #expect(!words.contains("you are secure"), "“\(sentence)”")
            #expect(!words.contains("no threats"), "“\(sentence)”")
            #expect(!words.contains("virus-free"), "“\(sentence)”")
        }
    }

    /// Good never stands alone: the clean sentence always carries what was looked at and how far
    /// back, and it changes when the run could not see everything.
    @Test func theCleanSentenceNeverStandsOnItsOwn() {
        let whole = CompletenessRegressionTests.wholeSection(measuredDays: 12)
        #expect(whole.summary.contains("protections we can see"))
        #expect(whole.summary.contains("in the last 12 days"))

        let partial = SecurityReport(block: whole.block, rows: [
            SecurityRow(topic: .protections, headline: "Everything reported is set to protect you."),
            SecurityRow.unreadable(.whoCanWatch, .notPermitted,
                                   remedy: Remedy(title: "Open Settings",
                                                  settingsPane: "fullDiskAccess")),
        ], measuredDays: 12)
        #expect(partial.summary.contains("were allowed to see"))
        #expect(!partial.complete)
    }

    static func everyShapeOfRun() -> [SecurityReport] {
        let allNine = SecurityReport(block: .unknown, rows: SecurityTopic.allCases.map { topic in
            SecurityRow(topic: topic,
                        headline: "\(topic.label) — something here is worth a look.",
                        concerns: SecurityConcern.allCases.filter { $0.topic == topic },
                        reason: topic.explanation)
        }, measuredDays: 12)

        let refused = SecurityReport(block: .unknown, rows: [
            SecurityRow(topic: .protections, headline: "Everything reported is set to protect you."),
            SecurityRow.unreadable(.whoCanWatch, .notPermitted,
                                   remedy: Remedy(title: "Open Settings",
                                                  settingsPane: "fullDiskAccess")),
            SecurityRow.unreadable(.startsOnItsOwn, .notGrantable,
                                   about: "Apple's own list of login items"),
            SecurityRow.unreadable(.macOSFindings, .notReported),
        ])

        return [CompletenessRegressionTests.wholeSection(),
                allNine,
                refused,
                ManagedMacHasNoImperativesTests.workMac(),
                SecurityReport(block: .unknown, rows: [])]
    }
}

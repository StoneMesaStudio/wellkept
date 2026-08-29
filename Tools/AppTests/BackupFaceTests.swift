import Foundation
import Testing
import WellkeptCore

//  BackupFaceTests.swift
//  Wellkept — Tools/AppTests
//
//  **What the Backup screen promises: the two demo Macs, the row the gate holds shut, and the page
//  a person prints.**
//
//  These live in `Tools/AppTests` because it is the only bundle that compiles `App` — `DemoData`,
//  `BackupModel`, `BackupRows`, `RecoveryPlanDocument` and `RecoveryPlanStore` are app-target
//  types, and `WellkeptTests` links only `WellkeptCore`.
//
//  ## What is tested here, and what is not
//
//  `TimeMachineReaderTests` and `CoverageReaderTests` test the readings; `BackupEngineTests` and
//  `BackupProofTests` test the copier. **Nothing here reads this Mac, prints anything, or touches a
//  drive.** What is tested here is what the *screen* promises:
//
//  - ⛔ **The engine is offered to nobody.** The row is present, it explains itself, it carries no
//    button, and its refusal is `RehearsalGate`'s own sentence rather than a second wording.
//  - ⭐ **"Switched off" is not "failing."** The unwell Mac's backup is configured, its last one
//    finished, and nobody was told it stopped. That is the finding this section exists to produce,
//    and it must not read as a fault in the machine.
//  - ⚠️ **The cloud is never counted as missing.** 72.2 GB in the cloud is an arrangement, not a
//    gap, on either Mac.
//  - ⛔ **Nothing on the printed page holds a value Wellkept could know**, and nothing anywhere
//    promises to rebuild somebody's Mac.

// MARK: - The two demo Macs

@Suite("Backup — the section screen and its two demo Macs")
@MainActor
struct BackupFaceTests {

    private var bothMacs: [BackupAnswer] {
        [DemoData.backup(.healthy), DemoData.backup(.problems)]
    }

    /// Everything a person could read on the screen for one demo Mac, flattened — the headline, the
    /// lines under it, every row's three facts, every coverage sentence, and the Overview row. A
    /// promise about wording that only holds above the fold is not a promise.
    private func words(_ answer: BackupAnswer) -> [String] {
        let report = answer.report
        var out = [report.summary]
        out += report.linesUnderTheHeadline
        for row in report.rows {
            out += row.facts
            out.append(row.topic.label)
            out.append(row.topic.explanation)
            if let withheld = row.withheld { out.append(withheld) }
            if let remedy = row.remedy { out.append(remedy.title) }
            for pair in row.details { out.append(pair.label); out.append(pair.value) }
            for item in row.coverage {
                out.append(item.name)
                out.append(item.why)
                out.append(item.sentence)
            }
        }
        if let finding = report.overviewFinding {
            out.append(finding.title)
            out.append(finding.reason)
        }
        return out
    }

    // MARK: The shape both Macs keep

    @Test("Four rows, in the fixed order, on both Macs")
    func fourRowsInOrder() {
        for answer in bothMacs {
            #expect(answer.report.rows.map(\.topic) ==
                    [.appleBackup, .notCovered, .wellkeptBackup, .recoveryPlan])
        }
    }

    /// ⛔ **The promise this section may not make.** A whole-Mac copy is impossible unprivileged and
    /// Migration Assistant accepting a data-only volume is unverified. `RehearsalGateGuardTests`
    /// reads the source; this reads what actually reaches a screen.
    @Test("Neither demo Mac promises to rebuild anybody's Mac")
    func thePromiseIsNotMade() {
        for answer in bothMacs {
            for line in words(answer) {
                #expect(line.lowercased().contains(Backup.promiseWeDoNotMake) == false,
                        "the demo screen promises to rebuild the Mac: \(line)")
            }
        }
    }

    /// ⚠️ **The distinction the section is built on.** `Coverage.isGap` is true only for something
    /// that lives on this Mac and nowhere else. Neither demo Mac may mark a cloud row or a sync
    /// provider as missing.
    @Test("Nothing in the cloud is ever counted as a gap")
    func theCloudIsNeverAGap() {
        for answer in bothMacs {
            for row in answer.report.rows {
                for item in row.coverage where item.lives != .onlyOnThisMac {
                    #expect(item.isGap == false,
                            "\(item.name) lives \(item.lives.label) and was counted as missing")
                }
            }
        }
    }

    /// ⭐ The engine exists and is offered to nobody, on every screen in every build so far.
    @Test("Wellkept's own backup is present, explained, and has no button")
    func theEngineIsWithheld() {
        // ⚠️ If this ever fails it means somebody recorded a rehearsal. That is the right way for
        // it to fail, and the fix is to record what the row should say once the gate is open.
        #expect(RehearsalGate.mayBeOffered == false,
                "a rehearsal has been recorded — this suite's expectations need revisiting")

        for answer in bothMacs {
            let row = try? #require(answer.report.row(.wellkeptBackup))
            guard let row else { continue }
            #expect(row.withheld == RehearsalGate.faceLine)
            #expect(row.remedy == nil, "a withheld row is offering a button")
            #expect(row.severity == .information,
                    "the gate is not a fault in somebody's Mac and may not be coloured like one")
            #expect(row.status == .good)
        }
    }

    /// The refusal on the row is the gate's own sentence, not a paraphrase written on a screen.
    @Test("The refusal is one sentence, in one place")
    func theRefusalHasOneWording() {
        let row = BackupRows.wellkeptBackup(destination: "Spare 2 TB", agentIsOn: false)
        #expect(row.withheld == RehearsalGate.Missing.rehearsal.sentence)
        #expect(row.reason == RehearsalGate.faceLine)
        // It says what has NOT happened, rather than that a feature is unavailable.
        #expect(RehearsalGate.faceLine.contains("restoring from it"))
    }

    // MARK: ⭐ The healthy Mac

    @Test("The healthy Mac's backup is running, and nothing needs anybody")
    func healthyMac() throws {
        let answer = DemoData.backup(.healthy)
        let report = answer.report

        #expect(report.status == .good)
        #expect(report.complete)
        #expect(report.overviewFinding == nil,
                "a Mac whose backups are running sent a row to Overview")
        #expect(report.gaps.isEmpty)
        #expect(answer.timeMachine.state.standing(now: report.ranAt) == .working)
        #expect(answer.timeMachine.state.destination?.isConnected == true)

        // macOS thins its own snapshots when backups are finishing, so there is nothing to say.
        #expect(answer.timeMachine.snapshotLine == nil)

        let plan = try #require(report.row(.recoveryPlan))
        #expect(plan.severity == .information)
        #expect(report.recoveryPlan?.isStale(currentMacOS: answer.planForToday.macOSVersion) == false)
    }

    // MARK: ⭐ The Mac with problems

    /// ⭐ **"Your backup is off and nobody told you" is both truer and more useful than "your backup
    /// is broken."** The destination is configured, the last one finished, and nothing is failing.
    @Test("The unwell Mac is switched off, and it is not described as broken")
    func unwellMac() throws {
        let answer = DemoData.backup(.problems)
        let report = answer.report
        let now = report.ranAt

        #expect(answer.timeMachine.state.standing(now: now) == .switchedOff)
        #expect(answer.timeMachine.state.standing(now: now).isAMalfunction == false)
        #expect(answer.timeMachine.state.failure == nil,
                "a Mac with automatic backups off is not a Mac with a failure")
        #expect(answer.timeMachine.state.isConfigured)
        #expect(answer.timeMachine.state.destination?.isConnected == false)

        #expect(report.status == .needsAttention)
        let finding = try #require(report.overviewFinding)
        #expect(finding.severity == .problem)
        #expect(finding.section == .backup)

        // ⭐ The snapshot Storage reports as stuck IS Time Machine's reference point, and the line
        // says what it is for rather than quoting a figure.
        let line = try #require(answer.timeMachine.snapshotLine)
        #expect(line.contains("the point the next backup starts from"))
        for unit in ["GB", "MB", "KB", "bytes", "%"] {
            #expect(line.contains(unit) == false, "the snapshot line quotes a figure: \(unit)")
        }
    }

    /// ⚠️ 72.2 GB in the cloud is named, sized and skipped — and it is not a gap.
    @Test("The unwell Mac names its cloud files without calling them missing")
    func theCloudRowIsNamedNotAlarming() throws {
        let answer = DemoData.backup(.problems)
        let row = try #require(answer.report.row(.notCovered))

        let cloud = try #require(row.coverage.first { $0.lives == .onlyInTheCloud })
        #expect(cloud.isGap == false)
        #expect(cloud.bytes != nil, "the cloud row has no figure, so it is an assertion")
        #expect(row.severity == .information,
                "files living in the cloud turned the row amber")

        // The provider is named, and the account it belongs to is not.
        let provider = try #require(row.coverage.first { $0.lives == .onAnotherDrive })
        #expect(provider.name == "Google Drive")
        #expect(provider.name.contains("@") == false)
    }

    /// A Mac with no page printed says so, and offers the one button that fixes it.
    @Test("No Recovery Plan printed is an attention, with something to press")
    func noRecoveryPlan() throws {
        let answer = DemoData.backup(.problems)
        let row = try #require(answer.report.row(.recoveryPlan))
        #expect(row.severity == .attention)
        #expect(row.status == .needsAttention)
        #expect(row.remedy?.title == "Write the Recovery Plan")
        // ⚠️ Not a settings pane. This is the one button in the section that makes something.
        #expect(row.remedy?.settingsPane == nil)
    }

    // MARK: Every button goes somewhere real

    /// Every remedy that names a pane names one that resolves. A wrong anchor still opens *a* pane,
    /// which is why this is checked rather than eyeballed.
    @Test("Every settings button on either Mac resolves to a real pane")
    func everyPaneResolves() {
        for answer in bothMacs {
            for row in answer.report.rows {
                guard let raw = row.remedy?.settingsPane else { continue }
                #expect(SystemSettingsPane(rawValue: raw) != nil,
                        "\(row.topic.label) points at a pane that does not exist: \(raw)")
            }
        }
    }
}

// MARK: - The Recovery Plan row

@Suite("Backup — the Recovery Plan row and its lifetime")
struct RecoveryPlanRowTests {

    private func plan(macOS: String, writtenOn: Date = Date(), fileVaultOn: Bool = true) -> RecoveryPlan {
        RecoveryPlan.make(macOSVersion: macOS,
                          macDescription: "Test Mac",
                          architecture: .appleSilicon,
                          destinationName: "Spare 2 TB",
                          fileVaultOn: fileVaultOn,
                          writtenOn: writtenOn)
    }

    @Test("A page written for this macOS is current and says nothing about reprinting")
    func currentPage() {
        let today = plan(macOS: "26.6.2")
        let row = BackupRows.recoveryPlan(onRecord: plan(macOS: "26.6.2"), today: today)
        #expect(row.severity == .information)
        #expect(row.headline == "Your Recovery Plan is current.")
    }

    /// ⚠️ **Migration Assistant refuses a backup made on a newer macOS than the machine being
    /// restored to**, so a point release is enough to make the page wrong in exactly the case it
    /// exists for.
    @Test("A point release is enough to make the page out of date")
    func aPointReleaseIsEnough() throws {
        let row = BackupRows.recoveryPlan(onRecord: plan(macOS: "26.6.2"),
                                          today: plan(macOS: "26.6.3"))
        #expect(row.severity == .attention)
        let reason = try #require(row.reason)
        #expect(reason.contains("26.6.2") && reason.contains("26.6.3"))
    }

    /// The row is never a `.problem`. Not having printed a page is not a malfunction, and
    /// `BackupRow` clamps this topic on its own so the two cannot disagree.
    @Test("The Recovery Plan row can never be a problem")
    func neverAProblem() {
        for onRecord in [nil, plan(macOS: "25.1")] as [RecoveryPlan?] {
            let row = BackupRows.recoveryPlan(onRecord: onRecord, today: plan(macOS: "26.6.2"))
            #expect(row.severity <= .attention)
        }
    }
}

// MARK: - ⭐ The page a person prints

@Suite("Backup — the printed Recovery Plan")
struct RecoveryPlanDocumentTests {

    private func plan(fileVaultOn: Bool) -> RecoveryPlan {
        RecoveryPlan.make(macOSVersion: "26.6.2",
                          macDescription: "Kitchen iMac",
                          architecture: .appleSilicon,
                          destinationName: "Spare 2 TB",
                          fileVaultOn: fileVaultOn,
                          writtenOn: Date(timeIntervalSince1970: 1_780_000_000))
    }

    /// ⭐ **One document, two renderings.** Every word the sheet draws is a word the printer prints,
    /// because both read the same blocks. A preview that could drift from what is printed is the
    /// bug this arrangement exists to prevent.
    @Test("Everything in the blocks reaches the ink")
    func theSheetAndThePaperSayTheSameThing() {
        let page = plan(fileVaultOn: true)
        let ink = RecoveryPlanDocument.attributed(page).string

        for block in RecoveryPlanDocument.blocks(for: page) {
            switch block {
            case .title(let t), .subtitle(let t), .heading(let t), .paragraph(let t):
                #expect(ink.contains(t), "the paper is missing: \(t)")
            case .step(_, let title, let whatToDo, let why):
                #expect(ink.contains(title) && ink.contains(whatToDo) && ink.contains(why))
            case .warning(let title, let body, _):
                #expect(ink.contains(title) && ink.contains(body))
            case .blank(let label, let whereToFindIt, _):
                #expect(ink.contains(label) && ink.contains(whereToFindIt))
            }
        }
    }

    /// ⭐ **macOS 26 moved the FileVault recovery key out of Apple's escrow into the Passwords app.**
    /// The warning has to be the first thing on the page, because it is the only item that is
    /// useless unless it is read months before it is needed.
    @Test("On a Mac with FileVault on, the key warning leads the page")
    func theKeyWarningLeads() throws {
        let blocks = RecoveryPlanDocument.blocks(for: plan(fileVaultOn: true))
        let firstWarning = try #require(blocks.firstIndex { if case .warning(_, _, true) = $0 { return true }; return false })
        let firstStep = blocks.firstIndex { if case .step = $0 { return true }; return false } ?? .max
        #expect(firstWarning < firstStep, "the must-do-today warning is below the steps")

        guard case .warning(_, let body, _) = blocks[firstWarning] else { return }
        #expect(body.contains("Passwords app"))
        #expect(body.contains("Apple ID"), "the page does not say the old escrow route is gone")
    }

    /// ⛔ **There is nowhere on this page to put a secret**, and the page says so out loud.
    @Test("Every blank is a ruled line and the page admits Wellkept cannot fill it")
    func nothingSecretIsPrinted() {
        let page = plan(fileVaultOn: true)
        let text = RecoveryPlanDocument.plainText(for: page)

        #expect(text.contains(RecoveryPlanDocument.whatWellkeptCannotWriteHere))
        for blank in page.blanks {
            #expect(text.contains(blank.label))
            #expect(text.contains(String(repeating: "_", count: blank.lineLength)),
                    "\(blank.label) has no line to write on")
        }
        // Structural, not a promise: `RecoveryBlank` has no value property, so there is nothing for
        // a renderer to leak even by accident.
        let fields = Mirror(reflecting: page.blanks[0]).children.compactMap(\.label)
        #expect(fields.sorted() == ["label", "lineLength", "whereToFindIt"])
    }

    /// ⚠️ The page is useless on the Mac it is about, and that has to be the first thing on it.
    @Test("The instruction to print it is at the top")
    func printItComesFirst() {
        let blocks = RecoveryPlanDocument.blocks(for: plan(fileVaultOn: false))
        #expect(blocks.count > 3)
        if case .paragraph(let text) = blocks[2] {
            #expect(text == RecoveryPlan.printIt)
        } else {
            Issue.record("the third block is not the instruction to print the page")
        }
    }

    /// ⛔ No step needs Wellkept, and the page says so.
    @Test("Nothing on the page needs this app")
    func nothingNeedsWellkept() throws {
        let page = plan(fileVaultOn: true)
        let text = RecoveryPlanDocument.plainText(for: page)
        #expect(text.lowercased().contains(Backup.promiseWeDoNotMake) == false)
        let warning = try #require(page.warnings.first { $0.title.contains("Wellkept") })
        #expect(warning.body.contains("plays no part"))
    }

    @Test("The saved file is named for the Mac and the day")
    func theFileName() {
        let name = RecoveryPlanDocument.fileName(for: plan(fileVaultOn: true))
        #expect(name.hasSuffix(".pdf"))
        #expect(name.contains("Kitchen iMac"))
        #expect(name.contains("/") == false)
    }
}

// MARK: - Remembering that a page was printed

@Suite("Backup — the record of the printed page")
struct RecoveryPlanStoreTests {

    private func sandbox() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "wellkept-plan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A page written down comes back the same page")
    func roundTrip() throws {
        let folder = try sandbox()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "RecoveryPlan.json")

        let page = RecoveryPlan.make(macOSVersion: "26.6.2",
                                     macDescription: "Kitchen iMac",
                                     architecture: .appleSilicon,
                                     destinationName: "Spare 2 TB",
                                     fileVaultOn: true,
                                     writtenOn: Date(timeIntervalSince1970: 1_780_000_000))

        #expect(RecoveryPlanStore.record(page, at: file))
        let back = try #require(RecoveryPlanStore.read(at: file))
        #expect(back == page)
    }

    /// A missing record and an unreadable one are the same answer: no paper. Neither is an error,
    /// because the person is in the same position either way.
    @Test("A missing or corrupt record reads as no page, never as a failure")
    func missingIsNotAnError() throws {
        let folder = try sandbox()
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(RecoveryPlanStore.read(at: folder.appending(path: "nothing.json")) == nil)

        let rubbish = folder.appending(path: "rubbish.json")
        try Data("not json".utf8).write(to: rubbish)
        #expect(RecoveryPlanStore.read(at: rubbish) == nil)
    }

    /// The uninstaller cannot go stale: everything Wellkept writes is declared in one list.
    @Test("The record is declared where the uninstaller looks")
    func theUninstallerKnowsAboutIt() throws {
        let folder = try sandbox()
        defer { try? FileManager.default.removeItem(at: folder) }

        let url = StorageManifest.recoveryPlanRecord(home: folder)
        #expect(url.lastPathComponent == "RecoveryPlan.json")
        // ⚠️ Compared by path with the trailing slash taken off. Foundation hands a directory's URL
        // back with one and a file's without, so two URLs naming the same folder are neither `==`
        // nor equal by `path` — the same trailing-slash trap that made the backup engine look for
        // every previous version at an absolute path inside the drive.
        func folderPath(_ url: URL) -> String {
            let text = url.path(percentEncoded: false)
            return text.hasSuffix("/") && text.count > 1 ? String(text.dropLast()) : text
        }
        #expect(folderPath(url.deletingLastPathComponent())
                == folderPath(StorageManifest.supportDirectory(home: folder)))

        let page = RecoveryPlan.make(macOSVersion: "26.6.2", macDescription: "Kitchen iMac",
                                     architecture: .appleSilicon, destinationName: nil,
                                     fileVaultOn: false)
        #expect(RecoveryPlanStore.record(page, at: url))

        let entry = StorageManifest.entries(home: folder).first { $0.url == url }
        let found = try #require(entry, "the Recovery Plan record is not in the uninstaller's list")
        // Wellkept's own bookkeeping — no secret in it, so no question to ask about it.
        #expect(found.disposition == .delete)
    }
}

// MARK: - The model's own arithmetic

@Suite("Backup — what the model works out before it draws anything")
struct BackupModelFactsTests {

    /// The page writes "macOS \(version)" itself. A plan whose version read "macOS macOS 26.6.2"
    /// would also never match the current one, so it would claim to be out of date forever.
    @Test("The macOS version loses its prefix exactly once")
    func theVersionString() {
        #expect(BackupModel.version(from: "macOS 26.6.2") == "26.6.2")
        #expect(BackupModel.version(from: "26.6.2") == "26.6.2")
        #expect(BackupModel.version(from: "  macOS 26.6  ") == "26.6")
    }

    /// A household with two of these ends up with two pages, so the name leads.
    @Test("The page names the Mac before the model")
    func theMacDescription() {
        let facts = MachineFacts(name: "Kitchen iMac",
                                 modelName: "iMac (24-inch, M3, 2023)",
                                 modelIdentifier: "Mac15,4",
                                 chip: "Apple M3",
                                 memory: "16 GB",
                                 driveSize: "494 GB",
                                 systemVersion: "macOS 26.6.2",
                                 systemMajorVersion: 26,
                                 inUseSince: nil,
                                 serialNumber: nil,
                                 isVirtualMachine: false)
        let described = BackupModel.description(of: facts)
        #expect(described.hasPrefix("Kitchen iMac"))
        #expect(described.contains("iMac (24-inch, M3, 2023)"))
        // ⛔ The serial number is identifying and has no business on a page kept in a drawer.
        #expect(described.contains("Mac15,4") == false)
    }

    /// ⚠️ **`completeness` stays `nil` until a Wellkept backup has actually been made.**
    /// `BackupCompleteness` describes a run that happened; inventing one would put "this backup is
    /// complete" on a Mac with no backup at all.
    @Test("A check that made no backup reports no completeness")
    func noCompletenessWithoutARun() {
        for machine in DemoMachine.allCases {
            #expect(DemoData.backup(machine).report.completeness == nil)
        }
    }
}

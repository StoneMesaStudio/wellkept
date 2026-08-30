// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import AppKit
import SwiftUI
import Testing
import WellkeptCore

//  BackupShot.swift
//  ViewShots
//
//  ⭐ **Pictures of the Backup screens — the face, the coverage list, the row the gate holds shut,
//  the refusal, and the Recovery Plan as it is printed.**
//
//  ## ⛔ Nothing here reads this Mac, and on this section that is not a nicety
//
//  Backup is the section that can copy somebody's whole home folder. Every picture below is drawn
//  from typed-out readings and `DemoData`; **`BackupModel.check()` is never called**, no drive is
//  looked at, Time Machine is never asked anything, and not one of these renders presses a button.
//
//  ## ⚠️ The two pictures worth the most, and what to look at in them
//
//  - **The row the gate holds shut.** `RehearsalGate.performed` is `nil` in every build so far, so
//    `BackupRows.wellkeptBackup` puts `RehearsalGate.faceLine` where the button would be. Look at
//    what it says: *nobody has erased a drive and restored from it yet* — a sentence about what has
//    not happened, not a feature that is "unavailable". And look at the colour it is **not**: there
//    is no amber and no red anywhere on that row, because nothing is wrong with the person's Mac.
//    A person told a feature is unavailable goes looking for the fault; there isn't one.
//  - **Full Disk Access refused.** Without the grant a backup contains no mail, no messages, no
//    photos, no contacts, no Safari data and no Trash — not partial, *nothing* — and macOS says so
//    with no error at all. The picture is what that looks like: the row says it was not allowed to
//    look, the coverage rows read "we could not check", and the completeness sentence underneath
//    names all six. Nothing on that screen claims a number it did not measure.
//
//  ## What else to look at
//
//  - **The coverage list is not an accusation.** Only a thing that lives on this Mac and nowhere
//    else is tagged. The 65.4 GB in iCloud carries no tag, no amber, and its own sentence saying
//    why it is not a gap — a tool that flagged it would open with a 65 GB alarm about an
//    arrangement working exactly as designed.
//  - **The Recovery Plan is blanks and ruled lines.** There is nowhere on it to write a value, and
//    `RecoveryBlank` has no field to put one in. It is the page you print **while the Mac still
//    works**, and the FileVault warning leads it because macOS 26 moved the recovery key out of
//    Apple's escrow into the Passwords app.
//  - **At 200% text**, the two long refusal sentences and the coverage rows keep their columns
//    rather than pushing the figures out of the readable width.
//
//      bin/make-shots.sh

@Suite("View shots — Backup", .serialized)
@MainActor
struct BackupShot {

    // MARK: - Fixtures

    /// A shell state positioned on Backup.
    ///
    /// ⚠️ `demoMode` and `demoMachine` write to `UserDefaults.standard`, which under `xctest` is the
    /// test process's own domain rather than the app's. Nothing this touches survives the run.
    private func state(demo: DemoMachine? = nil, optionsOpen: Bool = false) -> AppState {
        let app = AppState()
        app.demoMode = demo != nil
        if let demo { app.demoMachine = demo }
        app.selection = .backup
        if optionsOpen { app.openOptions.insert(.backup) }
        return app
    }

    /// The window: the rail beside the pane, which is the shape `RootView` builds.
    private func window(_ app: AppState) -> some View {
        HStack(spacing: 0) {
            Sidebar()
            BackupView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .pageGround()
        .environment(app)
    }

    /// A block of the section's own views inside the page's own chrome, for the pictures that are
    /// of one part rather than of the whole screen.
    ///
    /// ⚠️ Same shape as `SecurityRefusedShot.page`: the real pane width with the real
    /// `.readableColumn()` cap inside it, so a picture shows the wrapping the app actually does
    /// rather than the wrapping a narrow frame would invent.
    private func page(_ view: some View) -> some View {
        StableScrollView {
            VStack(alignment: .leading, spacing: Space.section) { view }
                .padding(Space.page)
                .readableColumn()
        }
        .fillsPane()
        .pageGround()
    }

    private func bothAppearances(_ view: some View, width: CGFloat, height: CGFloat,
                                 _ number: Int, _ name: String) {
        ShotWriter.write(view, width: width, height: height,
                         name: "\(number)-\(name)-light", scheme: .light)
        ShotWriter.write(view, width: width, height: height,
                         name: "\(number + 1)-\(name)-dark", scheme: .dark)
    }

    /// Run a block with the app's text size turned up. Restored whatever happens.
    private func atLargestText(_ body: () -> Void) {
        let key = AppearancePrefs.textScaleKey
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(Double(AppFont.maxScale), forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        body()
    }

    private enum PageHeight {
        static let face: CGFloat = 1_400
        static let whole: CGFloat = 3_200
        static let atLargestText: CGFloat = 5_200
    }

    // MARK: - The faces

    /// **Nothing has been checked** — which is every launch, because nothing here starts on its own.
    @Test("Backup, never checked")
    func neverChecked() {
        let size = Layout.windowDefault
        bothAppearances(window(state()), width: size.width, height: size.height,
                        600, "backup-never-checked")
    }

    /// **A healthy Mac**: a backup that ran, a drive that is plugged in, nothing to do.
    @Test("Backup, the healthy demo Mac")
    func healthyMac() {
        let size = Layout.windowDefault
        bothAppearances(window(state(demo: .healthy)),
                        width: size.width, height: PageHeight.whole,
                        602, "backup-healthy")
    }

    /// **A Mac with problems.** ⚠️ The finding to read is the one this section exists to produce:
    /// a backup that stopped and nobody was told.
    @Test("Backup, the demo Mac with problems")
    func problemMac() {
        let size = Layout.windowDefault
        bothAppearances(window(state(demo: .problems)),
                        width: size.width, height: PageHeight.whole,
                        604, "backup-problems")
    }

    @Test("Backup at 200% text")
    func atTwoHundredPercent() {
        let size = Layout.windowDefault
        atLargestText {
            bothAppearances(window(state(demo: .problems)),
                            width: size.width, height: PageHeight.atLargestText,
                            606, "backup-200-problems")
        }
    }

    // MARK: - ⭐ The row the gate holds shut

    /// ⛔ **The engine is built and it is offered to nobody.**
    ///
    /// This is the real row, from the real builder, in the state every build has been in so far.
    /// Nothing is typed out here except the drive's name: `RehearsalGate.performed` is `nil`, so the
    /// sentence in the picture is the gate's own.
    @Test("Backup, Wellkept's own backup held shut by the gate")
    func theGateIsShut() {
        let row = BackupRows.wellkeptBackup(destination: "Spare 2 TB", agentIsOn: false)
        let card = page(
            VStack(alignment: .leading, spacing: Space.section) {
                BackupTopicCard(row: row) { EmptyView() }
                DetailPairGrid(pairs: Array(row.details.prefix(6)))
            }
        )
        bothAppearances(card, width: Layout.windowDefault.width, height: 2_300,
                        610, "backup-gate-shut")

        atLargestText {
            bothAppearances(page(BackupTopicCard(row: row) { EmptyView() }),
                            width: Layout.windowDefault.width, height: 2_000,
                            612, "backup-200-gate-shut")
        }
    }

    // MARK: - ⭐ The coverage list

    /// **What is and is not in a backup, and where each thing actually lives.**
    ///
    /// The figures are this Mac's, measured on 2026-08-29, typed out rather than read: 65.4 GB of
    /// `~/Documents` is in iCloud and not on the disk, and 6.5 GB is a Google Drive folder that is
    /// never opened. Neither is a gap. The one row that is a gap is the one that lives here and
    /// nowhere else.
    @Test("Backup, the coverage list")
    func theCoverageList() {
        let card = page(
            VStack(alignment: .leading, spacing: Space.section) {
                BackupTopicCard(row: BackupShotMac.notCovered) {
                    CoverageList(coverage: BackupShotMac.coverage)
                }
                DisasterTable()
            }
        )
        bothAppearances(card, width: Layout.windowDefault.width, height: 2_800,
                        620, "backup-coverage")

        atLargestText {
            bothAppearances(page(CoverageList(coverage: BackupShotMac.coverage)),
                            width: Layout.windowDefault.width, height: 3_000,
                            622, "backup-200-coverage")
        }
    }

    // MARK: - ⚠️ Full Disk Access refused

    /// ⚠️ **The likeliest screen in the section**, because setup's last step offers "Finish later".
    ///
    /// Without the grant macOS hands over none of somebody's mail, messages, photos, contacts,
    /// Safari data or Trash, and reports no error. So this screen says it was not allowed to look,
    /// the rows that depended on it say they could not check, and the sentence underneath names all
    /// six. **Nothing here prints a number that would look like good news.**
    @Test("Backup, Full Disk Access refused")
    func fullDiskAccessRefused() {
        let refused = BackupCompleteness(fullDiskAccessHeld: false)
        let card = page(
            VStack(alignment: .leading, spacing: Space.section) {
                BackupTopicCard(row: BackupShotMac.notCoveredRefused) {
                    CoverageList(coverage: BackupShotMac.coverageRefused)
                }
                VStack(alignment: .leading, spacing: Space.block) {
                    Text(refused.headline).font(.appHeadline)
                    ForEach(refused.missingSentences, id: \.self) { line in
                        Text(line)
                            .font(.appCallout)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        )
        bothAppearances(card, width: Layout.windowDefault.width, height: 2_200,
                        630, "backup-refused")
    }

    // MARK: - ⭐ The Recovery Plan, as it prints

    /// ⭐ **The page, as ink on paper, from the identical attributed string the printer is given.**
    ///
    /// `PrintedPage` below draws `RecoveryPlanDocument.attributed(_:)` — the identical attributed
    /// string `RecoveryPlanDocument.page(_:info:)` hands to `NSPrintOperation` — at the paper's own
    /// text width and margins. Nothing about the type here is this file's: the fonts, the spacing,
    /// the indents and the ruled lines are the document's own.
    ///
    /// ⛔ Every value on it is a blank with a ruled line. There is no field, and `RecoveryBlank` has
    /// nowhere to put a value even if a future screen wanted to fill one in — which is what makes it
    /// impossible for this app to print somebody's FileVault recovery key.
    @Test("Backup, the Recovery Plan as it prints")
    func theRecoveryPlanAsItPrints() {
        // ⚠️ **Taller than one sheet, on purpose.** The document runs past a single page of US
        // Letter — the printer paginates it — and cropping the picture at 792 points would show
        // only the half of the page somebody would think to check.
        let page = PrintedPage.image(of: BackupShotMac.plan, width: Paper.textWidth)
        let paper = VStack(spacing: 0) {
            Image(nsImage: page)
                .resizable()
                .frame(width: page.size.width, height: page.size.height)
                .padding(Paper.margin)
                .background(Color.white)
        }
        .padding(Space.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .pageGround()

        bothAppearances(paper,
                        width: Paper.width + Space.page * 2,
                        height: page.size.height + Paper.margin * 2 + Space.page * 2,
                        640, "backup-recovery-plan-printed")
    }

    /// The same page **on screen**, in the sheet somebody actually presses Print from.
    ///
    /// ⚠️ Shot at the sheet's own natural size rather than in a frame of my choosing: given a frame
    /// larger than it wants, it centres a band in the middle of it and the picture stops being of a
    /// screen anybody ever sees.
    @Test("Backup, the Recovery Plan sheet")
    func theRecoveryPlanSheet() {
        let view = RecoveryPlanView(plan: BackupShotMac.plan)
            .padding(Space.page)
            .pageGround()
        bothAppearances(view, width: 1_360, height: 1_180, 644, "backup-recovery-plan-sheet")
    }
}

// MARK: - The paper

/// US Letter with the three-quarter-inch margins `RecoveryPlanDocument` sets on its own
/// `NSPrintInfo` — enough that nothing lands in a printer's unprintable border, which is where a
/// hand-written FileVault key would otherwise end up.
private enum Paper {
    static let width: CGFloat = 612
    static let margin: CGFloat = 54
    static var textWidth: CGFloat { width - margin * 2 }
}

/// **The printed page itself** — `RecoveryPlanDocument.attributed(_:)` drawn at the paper's own
/// text width.
///
/// ⚠️ Not a drawing *of* the page: it is the identical attributed string the printer is handed, so
/// the fonts, the spacing, the indents and the ruled lines are the document's own and nothing about
/// the type is this file's. The ink is `NSColor.black` in both appearances, because paper has only
/// one.
///
/// ⚠️ It goes into a bitmap rather than onto the screen through an `NSViewRepresentable`, and that
/// is not fussiness: hosted in SwiftUI the text view is handed the proposed height, overflows it,
/// and AppKit anchors the overflow at the **bottom** — so the photograph began at step 5, with the
/// title, the FileVault warning and the first four steps above the frame. A picture of the wrong
/// half of a page is worse than no picture, because it looks exactly like the page.
@MainActor
private enum PrintedPage {

    static func image(of plan: RecoveryPlan, width: CGFloat) -> NSImage {
        let ink = RecoveryPlanDocument.attributed(plan)

        // ⚠️ Measured with the same options it is drawn with. Anything else and the last paragraph
        // is clipped by however much the two disagree.
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let measured = ink.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude), options: options)
        let size = NSSize(width: width, height: ceil(measured.height) + 8)

        let image = NSImage(size: size)
        // ⚠️ **Flipped.** Unflipped, AppKit draws from the bottom up and the picture comes out
        // starting at step 5, with the title and the FileVault warning off the top of the page.
        image.lockFocusFlipped(true)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        ink.draw(with: NSRect(origin: .zero, size: size), options: options)
        image.unlockFocus()
        return image
    }
}

// MARK: - The Mac in the pictures

/// A Mac typed out, so a picture of a backup screen can be taken without reading a backup.
///
/// ⚠️ Everything is built from the real vocabulary rather than from finished sentences, so a
/// picture can never show wording the app is no longer capable of producing. The figures are the
/// ones measured on one real Mac on 2026-08-29 — 65.4 GB in iCloud, 6.5 GB in a Google Drive folder —
/// because a made-up number in a picture is how a made-up number reaches a screen.
@MainActor
enum BackupShotMac {

    /// The coverage rows on a Mac whose backup is working and that has Full Disk Access.
    static let coverage: [Coverage] = [
        Coverage(name: "Your documents",
                 lives: .onlyOnThisMac,
                 included: .yes,
                 why: "In the last Time Machine backup, which finished four days ago.",
                 bytes: SizeOnDisk(41_200_000_000),
                 needsFullDiskAccess: false),
        Coverage(name: "Your mail",
                 lives: .onlyOnThisMac,
                 included: .yes,
                 why: "Wellkept can see that it is here and cannot read its size without Full Disk Access.",
                 bytes: nil,
                 needsFullDiskAccess: true),
        Coverage(name: "Your photos",
                 lives: .inTheCloudAndHere,
                 included: .yes,
                 why: "iCloud Photos is on, so there is a copy here and a copy in iCloud.",
                 bytes: nil,
                 needsFullDiskAccess: true),
        // ⭐ The row that is actually a gap — and the only kind that can be one.
        Coverage(name: "Your virtual machines",
                 lives: .onlyOnThisMac,
                 included: .no,
                 why: "They are on this Mac and in no backup. If the disk fails they are gone.",
                 bytes: SizeOnDisk(96_000_000_000),
                 needsFullDiskAccess: false),
        // ⚠️ 65.4 GB, and not a gap. There is nothing here to copy.
        Coverage(name: "Documents kept in iCloud",
                 lives: .onlyInTheCloud,
                 included: .no,
                 why: "These are in iCloud and not on this disk. Copying them would mean downloading them first.",
                 bytes: SizeOnDisk(65_400_000_000),
                 needsFullDiskAccess: false),
        // ⛔ Named, never opened. Reading it is what starts the download.
        Coverage(name: "Google Drive",
                 lives: .onAnotherDrive,
                 included: .no,
                 why: CoverageReader.whyAFileProviderIsNeverOpened("Google Drive"),
                 bytes: nil,
                 needsFullDiskAccess: false),
    ]

    /// The same Mac with the permission refused: what was here is still provable, what it holds is
    /// not, and nothing pretends otherwise.
    static let coverageRefused: [Coverage] = [
        Coverage(name: "Your mail",
                 lives: .onlyOnThisMac,
                 included: .notKnown(.notPermitted),
                 why: CoverageReader.whatFullDiskAccessCosts,
                 bytes: nil,
                 needsFullDiskAccess: true),
        Coverage(name: "Your messages",
                 lives: .onlyOnThisMac,
                 included: .notKnown(.notPermitted),
                 why: CoverageReader.whatFullDiskAccessCosts,
                 bytes: nil,
                 needsFullDiskAccess: true),
        Coverage(name: "Your photos",
                 lives: .onlyOnThisMac,
                 included: .notKnown(.notPermitted),
                 why: CoverageReader.whatFullDiskAccessCosts,
                 bytes: nil,
                 needsFullDiskAccess: true),
        Coverage(name: "Your documents",
                 lives: .onlyOnThisMac,
                 included: .yes,
                 why: "In the last Time Machine backup, which finished four days ago.",
                 bytes: SizeOnDisk(41_200_000_000),
                 needsFullDiskAccess: false),
    ]

    static var notCovered: BackupRow {
        BackupRow(topic: .notCovered,
                  headline: "One thing on this Mac is in no backup.",
                  measure: "96 GB",
                  reason: "It lives here and nowhere else. Everything else on the list either is in "
                        + "a backup or has a second copy somewhere that is not this disk.",
                  severity: .attention,
                  coverage: coverage)
    }

    /// ⚠️ The refused row. It carries the one button that can actually change the answer.
    static var notCoveredRefused: BackupRow {
        BackupRow.unreadable(.notCovered, .notPermitted,
                             about: "What is not covered",
                             reason: "Mail, Messages and Photos are the three people restore most "
                                   + "often, and without Full Disk Access macOS hands over none of "
                                   + "them and reports no error at all.",
                             remedy: Remedy(title: "Open Full Disk Access",
                                            settingsPane: "fullDiskAccess"))
    }

    /// The page for a Mac on Apple silicon with FileVault on, which is the arrangement the warning
    /// at the top of the page is about.
    static let plan = RecoveryPlan.make(
        macOSVersion: "26.1",
        macDescription: "MacBook Pro (M4 Pro, 2025)",
        architecture: .appleSilicon,
        destinationName: "Spare 2 TB",
        fileVaultOn: true,
        writtenOn: Date(timeIntervalSince1970: 1_787_000_000))
}

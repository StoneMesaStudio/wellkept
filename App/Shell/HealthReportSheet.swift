// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import SwiftUI
import WellkeptCore

//  HealthReportSheet.swift
//  Wellkept — App/Shell
//
//  ⭐ **Shows the person the whole page before any of it leaves the app.**
//
//  ## The convention this obeys, and why there is only one
//
//  Hardware settled it on 2026-08-27, in `RepairShopSheet`: a screen that is about to hand
//  something identifying to somebody else shows exactly what it is about to hand over, and the
//  preview and the payload are **one string**, not two that agree today. This page carries the
//  Mac's name and — unless the person switches it off — its serial number, so it is the same
//  situation one level up and it gets the same answer rather than a second convention.
//
//  So: `HealthReportDocument.plainText(for:)` is what is displayed, and
//  `HealthReportDocument.attributed(_:)` is what is printed, and both come from
//  `HealthReportDocument.blocks(for:)`. There is no third list of what the page says.
//
//  ## ⚠️ Both menu items land here, and that is deliberate
//
//  **Save as PDF…** and **Print…** both open this sheet; neither prints or writes anything on its
//  own. ⌘P on a page carrying a serial number, with no chance to look at it first, is exactly the
//  thing this app exists to catch other software doing. The menu item chooses which verb is the
//  default button, and nothing else.
//
//  ## The serial-number switch appears only when there is one
//
//  Same rule as the repair-shop sheet: a Mac that reports no serial number is not offered a switch
//  that changes nothing. A control that does nothing is worse than an absent one, because somebody
//  who flips it believes something happened.

// MARK: - Building the report from the window's own state

extension AppState {

    /// **The report, from what Overview already holds.** Nothing here reads the Mac.
    ///
    /// Every input is something the window is already showing: the findings Overview lists, the
    /// audit trail behind **What was checked**, the machine block Hardware produced, whether a
    /// permission was off, and whether anybody has answered the update-check question. That is what
    /// makes the page checkable against the screen — ⛔ it states no figure the app would not state
    /// on screen, because it has no figure the screen did not give it.
    ///
    /// ⚠️ **Demo mode is carried through rather than blocked.** A page made while sample results
    /// were showing says so in its first caveat and in its own headline. Refusing to make one
    /// instead would leave the demo unphotographable and, worse, would make "did this come from a
    /// real Mac?" a question the page could not answer for itself.
    func healthReport(includeSerial: Bool = true, now: Date = Date()) -> HealthReport {
        HealthReport(writtenOn: now,
                     machine: reportMachineFacts,
                     includeSerial: includeSerial,
                     findings: needsYou,
                     records: records,
                     permissionsOff: reportPermissionsOff,
                     appUpdateChecking: reportUpdateChecking,
                     sampleResults: demoMode)
    }

    /// Whether there is anything to make a report out of. The File menu's two items are greyed
    /// until this is true, with the reason in their `.help`.
    var canMakeHealthReport: Bool { !records.isEmpty }

    /// Hardware's block. In demo mode it comes from the invented Mac, so that a sample page is a
    /// sample page all the way down rather than a real machine's name on top of invented rows.
    private var reportMachineFacts: MachineFacts? {
        demoMode ? DemoData.hardware(demoMachine).facts : hardware.report?.facts
    }

    /// Every permission that was off, with what each cost, **in the app's own words**.
    ///
    /// ⚠️ The sentences are `FullDiskAccess.shortfall(for:)` — the identical strings each section's
    /// own face shows. The page does not paraphrase them, so a person comparing the paper against
    /// the screen finds the same sentence twice rather than two descriptions of one refusal.
    private var reportPermissionsOff: [PermissionShortfall] {
        // ⚠️ Demo mode has no permissions story: nothing was read, so nothing was refused. Reading
        // this Mac's real grant here would put a true fact about this machine onto a page about an
        // invented one.
        guard !demoMode, !PermissionCenter.shared.fullDiskAccessGranted else { return [] }
        let sentences = FullDiskAccess.affectedSections.compactMap { FullDiskAccess.shortfall(for: $0) }
        guard !sentences.isEmpty else { return [] }
        return [PermissionShortfall(permission: "Full Disk Access", sentences: sentences)]
    }

    /// `true` allowed · `false` declined · **`nil` nobody has been asked.** The third state is the
    /// one that matters: a page that collapsed it into "no" would say the person declined something
    /// they were never offered.
    private var reportUpdateChecking: Bool? {
        switch updateConsent.answer {
        case .allowed:  true
        case .declined: false
        case .notAsked: nil
        }
    }

    /// Put the report on screen. Both File-menu items come through here.
    func presentHealthReport(_ intent: HealthReportSheet.Intent) {
        sheet = SheetRoute(id: "health-report") { [self] in
            HealthReportSheet(intent: intent) { includeSerial in
                self.healthReport(includeSerial: includeSerial)
            }
        }
    }
}

// MARK: - The sheet

struct HealthReportSheet: View {

    /// Which menu item opened this. It decides the default button and nothing else — **neither
    /// value prints or saves anything without a press.**
    enum Intent: String, Sendable, Hashable, CaseIterable {
        case save
        case print

        /// The heading. It names what the person came to do, so the sheet reads as the step before
        /// that rather than as an interruption of it.
        var heading: String {
            switch self {
            case .save:  String(localized: "Save this report as a PDF")
            case .print: String(localized: "Print this report")
            }
        }

        /// The button. ⚠️ **The same two words as the File-menu items they came from**, so nobody
        /// has to work out whether the sheet's button is the thing they clicked.
        var title: String {
            switch self {
            case .save:  String(localized: "Save as PDF…")
            case .print: String(localized: "Print…")
            }
        }
    }

    let intent: Intent

    /// Builds the report at the person's current serial-number choice. A closure rather than a
    /// finished value because the switch changes what is on the page, and a preview built once
    /// would stop matching the moment it was flipped.
    let make: (Bool) -> HealthReport

    @State private var includeSerial = true
    /// What the last press did, in a sentence. `nil` before anything has been pressed, and after a
    /// cancel — closing a print panel is a decision, not a failure.
    @State private var outcome: String?
    @Environment(\.dismiss) private var dismiss

    private var report: HealthReport { make(includeSerial) }
    private var text: String { HealthReportDocument.plainText(for: report) }

    /// Whether the machine block has anything identifying in it at all, whether or not it is
    /// currently included. What decides if the switch is offered.
    private var hasSerialNumber: Bool { make(true).carriesSerialNumber }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.gutter) {
            Text(intent.heading).sectionHeading()

            Text(Self.whatYouAreLookingAt)
                .font(.appBody)
                .fixedSize(horizontal: false, vertical: true)

            // Selectable, and scrolling inside its own box. The page runs to two sheets of paper on
            // a Mac with something wrong with it, and a sheet that grew to fit would run off the
            // bottom of the screen.
            ScrollView {
                Text(text)
                    .font(.appCallout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Space.gutter)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor), in: Radius.shape(Radius.control))
            .overlay(Radius.shape(Radius.control)
                .strokeBorder(Theme.hairlineInk, lineWidth: Hairline.thin))

            if hasSerialNumber {
                Toggle("Include the serial number", isOn: $includeSerial)
                    .font(.appCallout)
            }

            // The one line naming what is in it, once, beside the button that sends it. The
            // caveats are already on the page above — this is about the act, not about the Mac.
            if let caution = Self.caution(for: report) {
                Text(caution)
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let outcome {
                Text(outcome)
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Space.gutter) {
                Spacer(minLength: 0)
                Button("Cancel") { dismiss() }
                    .buttonStyle(.app)
                    .keyboardShortcut(.cancelAction)

                // Both verbs are on the sheet whichever item opened it: somebody who chose Print
                // and then decides to email it instead should not have to close this and go back to
                // the menu.
                //
                // ⚠️ **The one that was chosen goes last, on the right.** macOS puts the default
                // button in the trailing position, and the first picture of this sheet had the
                // bronze one wedged between Cancel and Print — which reads as three peers rather
                // than as a choice with a default.
                ForEach(orderedVerbs, id: \.self) { verb in
                    Button(verb.title) { finish(run(verb)) }
                        .buttonStyle(verb == intent ? .appProminent : .app)
                        .conditionalDefaultAction(verb == intent)
                }
            }
        }
        .padding(Space.page)
        .frame(width: SheetMetrics.width(640), height: SheetMetrics.height(620))
        .pageGround()
    }

    /// The two verbs, with the chosen one last so it lands in the trailing position macOS reserves
    /// for the default.
    private var orderedVerbs: [Intent] {
        Intent.allCases.filter { $0 != intent } + [intent]
    }

    private func run(_ verb: Intent) -> HealthReportDocument.Outcome {
        switch verb {
        case .save:  HealthReportDocument.savePDF(report)
        case .print: HealthReportDocument.print(report)
        }
    }

    /// ⚠️ **A cancel says nothing and closes nothing.** Somebody who backed out of the print panel
    /// is still looking at the page they were about to print, which is where they want to be.
    private func finish(_ result: HealthReportDocument.Outcome) {
        switch result {
        case .cancelled:
            outcome = nil
        case .done(let sentence):
            outcome = sentence
            dismiss()
        case .failed(let sentence):
            outcome = sentence
        }
    }

    /// The sentence above the preview. The whole promise of this sheet, in two lines.
    static let whatYouAreLookingAt = String(localized: """
        This is the whole report, exactly as it will be printed or saved. Nothing is printed and no \
        file is written until you press one of the buttons below.
        """)

    /// The one line beside the buttons naming what the page identifies. `nil` where the page names
    /// no machine at all, because there is then nothing a person needs told.
    ///
    /// ⚠️ It is about the act of handing the page over, and it is the only sentence on this sheet
    /// the caveats on the page do not already carry.
    static func caution(for report: HealthReport) -> String? {
        guard let name = report.machineName else { return nil }
        return report.carriesSerialNumber
            ? String(localized: "This page names \(name) and carries its serial number.")
            : String(localized: "This page names \(name). The serial number is left off.")
    }
}

// MARK: - The default button, without two copies of the same button

private extension View {
    /// `.keyboardShortcut(.defaultAction)` applied only when this is the item that was chosen.
    ///
    /// ⚠️ Written as a modifier rather than as an `if` around two `Button`s. SwiftUI treats the two
    /// branches of an `if` as different views, so a Save button in one branch and a Save button in
    /// the other are two identities — and the focus ring, the press state and any animation restart
    /// every time the condition flips.
    @ViewBuilder
    func conditionalDefaultAction(_ isDefault: Bool) -> some View {
        if isDefault { keyboardShortcut(.defaultAction) } else { self }
    }
}

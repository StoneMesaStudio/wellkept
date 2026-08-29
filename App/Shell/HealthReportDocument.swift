// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import AppKit
import Foundation
import WellkeptCore

//  HealthReportDocument.swift
//  Wellkept — App/Shell
//
//  ⭐ **The health report as a piece of paper: one list of blocks, three renderings, no fourth.**
//
//  ## The rule this file inherits
//
//  `RecoveryPlanDocument` settled it two days earlier and nothing here re-decides it: **the sheet
//  draws blocks, the printer prints blocks, and the plain-text version is the same blocks.** There
//  is no second list of what the page says. A preview that can drift from what is handed over is
//  the exact bug `RepairShopCopy` was written to avoid — it holds one string rather than a preview
//  and a payload — and this is that rule one level up.
//
//  So: if a block is not in `blocks(for:)`, it is not on the page, in any medium. And if it is,
//  the person saw it on the sheet before they pressed anything.
//
//  ## ⚠️ Why the printer is fed a text view rather than a picture of the screen
//
//  Same answer as the Recovery Plan. `ImageRenderer` hands back one very tall image and a printer
//  slices it at whatever height the paper happens to be — through the middle of a line, which on
//  this page could be through the middle of the sentence saying a check never ran. `NSTextView`
//  paginates at line boundaries because that is what it is for.
//
//  ## ⛔ What this page will not do
//
//  - **No score.** There is no block that can hold one. See `HealthReport`.
//  - **No figure the app would not put on a screen.** Every measure printed is a `Finding.measure`,
//    already formatted by the section that measured it. Nothing here computes anything.
//  - **No sentence claiming a quarantine gave space back.** `QuarantineWordsTests` fails the build
//    on the word, and the reason is measured: setting 391 MB aside moved free space by −8 KiB.

enum HealthReportDocument {

    // MARK: - ⭐ One document, in blocks

    /// One piece of the page. **The single source of what the page says and in what order.**
    enum Block: Sendable, Hashable, Identifiable {

        /// The name at the top — the Mac's name, because a household with two Macs ends up with
        /// two of these pages.
        case title(String)

        /// The dated line under it.
        case subtitle(String)

        /// ⭐ The verdict, in one sentence. Exactly one of these on the page, always.
        case verdict(String)

        /// A heading over a run of blocks.
        case heading(String)

        /// A paragraph of plain words.
        case paragraph(String)

        /// ⚠️ **Something the reader has to know before believing the rest.** These are the blocks
        /// that make the page honest away from the screen it was printed on.
        case caveat(title: String, body: String)

        /// One thing that needs a person. `measure` is the section's own formatted figure, or `nil`.
        case finding(section: String, title: String, reason: String, measure: String?)

        /// One line of the audit trail.
        case audit(section: String, status: String, when: String, sawEverything: Bool)

        /// One row of the machine block.
        case detail(label: String, value: String)

        /// The footer.
        case footer(String)

        var id: String {
            switch self {
            case .title(let t):                     "title|\(t)"
            case .subtitle(let t):                  "subtitle|\(t)"
            case .verdict(let t):                   "verdict|\(t)"
            case .heading(let t):                   "heading|\(t)"
            case .paragraph(let t):                 "paragraph|\(t)"
            case .caveat(let t, _):                 "caveat|\(t)"
            case .finding(let s, let t, _, _):      "finding|\(s)|\(t)"
            case .audit(let s, _, _, _):            "audit|\(s)"
            case .detail(let label, _):             "detail|\(label)"
            case .footer(let t):                    "footer|\(t)"
            }
        }
    }

    // MARK: - ⭐ The one list

    /// **What the page says, in the order it says it.**
    ///
    /// The order is the order the reader needs, which is not the order of the app's sidebar:
    ///
    /// 1. **The verdict**, because it is the answer.
    /// 2. **The caveats**, immediately — before the findings, not after them. A qualification below
    ///    a list is a qualification most people never reach, and this page's failure mode is being
    ///    read as a clean bill of health.
    /// 3. **What needs you.**
    /// 4. **What was checked**, all seven, which is the audit trail John asked for by name.
    /// 5. **What this Mac is**, which is what a repair shop actually wants.
    static func blocks(for report: HealthReport) -> [Block] {
        var blocks: [Block] = [
            .title(report.title),
            .subtitle(report.subtitle),
            .verdict(report.headline),
        ]

        if !report.caveats.isEmpty {
            blocks.append(.heading(String(localized: "Read this first")))
            for caveat in report.caveats {
                blocks.append(.caveat(title: caveat.title, body: caveat.body))
            }
        }

        blocks.append(.heading(String(localized: "What needs you")))
        if report.findings.isEmpty {
            blocks.append(.paragraph(HealthReport.nothingNeedsYou))
        } else {
            blocks.append(.paragraph(HealthReport.findingsIntro))
            for finding in report.findings {
                blocks.append(.finding(section: finding.section.title,
                                       title: finding.title,
                                       reason: finding.reason,
                                       measure: finding.measure))
            }
        }

        // ⭐ Always all seven, and always present — even on a page where nothing ran. It is the
        // evidence behind the verdict, and a verdict with the evidence left off is an opinion.
        blocks.append(.heading(String(localized: "What was checked")))
        blocks.append(.paragraph(HealthReport.auditIntro))
        for line in report.audit {
            // ⚠️ `sawOnlyPart`, not `!sawEverything`. A check that never ran saw nothing, not part
            // — see `HealthReport.AuditLine.sawOnlyPart`.
            blocks.append(.audit(section: line.section.title,
                                 status: line.status.label,
                                 when: line.whenSentence,
                                 sawEverything: !line.sawOnlyPart))
        }

        if !report.machine.isEmpty {
            blocks.append(.heading(String(localized: "What this Mac is")))
            blocks.append(.paragraph(HealthReport.machineIntro))
            for pair in report.machine {
                blocks.append(.detail(label: pair.label, value: pair.value))
            }
        }

        blocks.append(.footer(HealthReport.provenance))
        return blocks
    }

    /// What the file is called when it is saved rather than printed.
    static func fileName(for report: HealthReport) -> String {
        let stamp = report.writtenOn.formatted(
            .iso8601.year().month().day().dateSeparator(.dash))
        let safe = report.title.replacingOccurrences(of: "/", with: "-")
        return "\(safe) \(stamp).pdf"
    }

    // MARK: - The page as text

    /// The whole page as plain text.
    ///
    /// ⚠️ **This is what the sheet's preview shows.** Not a summary of the page and not a
    /// description of it — the page, from the same blocks the printer gets, so that what somebody
    /// reads before pressing Print is what comes out of the printer.
    static func plainText(for report: HealthReport) -> String {
        var lines: [String] = []
        for block in blocks(for: report) {
            switch block {
            case .title(let text):
                lines.append(text)
            case .subtitle(let text):
                lines.append(text)
                lines.append("")
            case .verdict(let text):
                lines.append(text)
                lines.append("")
            case .heading(let text):
                // ⚠️ **Not upper-cased.** `RecoveryPlanDocument` shouts its headings here because its
                // plain text is a side channel — the sheet draws that page from blocks natively. This
                // page's plain text *is* the preview somebody reads before pressing Print, so a
                // heading in a different case from the printed one is a preview that differs from the
                // payload, which is the whole thing this file exists to prevent.
                lines.append("")
                lines.append(text)
                lines.append("")
            case .paragraph(let text):
                lines.append(text)
                lines.append("")
            case .caveat(let title, let body):
                lines.append(title)
                lines.append(body)
                lines.append("")
            case .finding(let section, let title, let reason, let measure):
                lines.append(measure.map { "\(section) — \(title)  (\($0))" }
                             ?? "\(section) — \(title)")
                lines.append("   \(reason)")
                lines.append("")
            case .audit(let section, let status, let when, let sawEverything):
                var line = "\(section): \(status) — \(when)"
                if !sawEverything { line += String(localized: "  (saw part of this Mac)") }
                lines.append(line)
            case .detail(let label, let value):
                lines.append("\(label): \(value)")
            case .footer(let text):
                lines.append("")
                lines.append(text)
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - The page as ink

    /// The type on the paper. Fixed points, deliberately: somebody who made the app's window type
    /// larger has not asked for a bigger piece of paper.
    ///
    /// ⚠️ Computed rather than stored. `NSFont` is not `Sendable`, so a stored global of one is a
    /// compile error under Swift 6 strict concurrency. AppKit caches fonts; these are cheap.
    private enum Ink {
        static var title: NSFont { .systemFont(ofSize: 20, weight: .semibold) }
        static var subtitle: NSFont { .systemFont(ofSize: 10, weight: .regular) }
        static var verdict: NSFont { .systemFont(ofSize: 15, weight: .semibold) }
        static var heading: NSFont { .systemFont(ofSize: 13, weight: .semibold) }
        static var body: NSFont { .systemFont(ofSize: 11, weight: .regular) }
        static var strong: NSFont { .systemFont(ofSize: 11, weight: .semibold) }
        static var quiet: NSFont { .systemFont(ofSize: 9.5, weight: .regular) }
    }

    /// The page, set for a printer.
    ///
    /// ⚠️ Black on white, always, whatever the app's appearance is. `NSColor.textColor` is dynamic
    /// and would come out white on a Mac in dark mode — which prints as nothing at all.
    static func attributed(_ report: HealthReport) -> NSAttributedString {
        let page = NSMutableAttributedString()

        func paragraphStyle(spaceBefore: CGFloat = 0,
                            spaceAfter: CGFloat = 6,
                            indent: CGFloat = 0) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacingBefore = spaceBefore
            style.paragraphSpacing = spaceAfter
            style.headIndent = indent
            style.firstLineHeadIndent = indent
            style.lineSpacing = 1.5
            return style
        }

        func add(_ text: String, font: NSFont, style: NSParagraphStyle) {
            page.append(NSAttributedString(string: text + "\n",
                                           attributes: [.font: font,
                                                        .foregroundColor: NSColor.black,
                                                        .paragraphStyle: style]))
        }

        for block in blocks(for: report) {
            switch block {
            case .title(let text):
                add(text, font: Ink.title, style: paragraphStyle(spaceAfter: 2))
            case .subtitle(let text):
                add(text, font: Ink.subtitle, style: paragraphStyle(spaceAfter: 12))
            case .verdict(let text):
                add(text, font: Ink.verdict, style: paragraphStyle(spaceAfter: 8))
            case .heading(let text):
                add(text, font: Ink.heading, style: paragraphStyle(spaceBefore: 14, spaceAfter: 6))
            case .paragraph(let text):
                add(text, font: Ink.body, style: paragraphStyle())
            case .caveat(let title, let body):
                add(title, font: Ink.strong, style: paragraphStyle(spaceBefore: 8, spaceAfter: 2))
                add(body, font: Ink.body, style: paragraphStyle(spaceAfter: 4))
            case .finding(let section, let title, let reason, let measure):
                let heading = measure.map { "\(section) — \(title)  (\($0))" }
                    ?? "\(section) — \(title)"
                add(heading, font: Ink.strong, style: paragraphStyle(spaceBefore: 8, spaceAfter: 2))
                add(reason, font: Ink.body, style: paragraphStyle(spaceAfter: 4, indent: 20))
            case .audit(let section, let status, let when, let sawEverything):
                var line = "\(section): \(status) — \(when)"
                if !sawEverything { line += String(localized: "  (saw part of this Mac)") }
                add(line, font: Ink.body, style: paragraphStyle(spaceAfter: 2))
            case .detail(let label, let value):
                add("\(label): \(value)", font: Ink.body, style: paragraphStyle(spaceAfter: 2))
            case .footer(let text):
                add(text, font: Ink.quiet, style: paragraphStyle(spaceBefore: 16, spaceAfter: 0))
            }
        }

        return page
    }

    // MARK: - ⭐ Printing and saving

    /// What happened when somebody pressed a button on the sheet.
    ///
    /// ⚠️ Same three cases as the Recovery Plan's, and `cancelled` says nothing on purpose:
    /// closing a print panel is a decision, not a failure, and an app that reports it back as one
    /// is an app that argues with you.
    enum Outcome: Sendable, Equatable {
        case done(String)
        case cancelled
        case failed(String)

        var sentence: String? {
            switch self {
            case .done(let words):   words
            case .cancelled:         nil
            case .failed(let words): words
            }
        }
    }

    /// Paper, in points. US Letter with three-quarter-inch margins — enough that nothing lands in
    /// a printer's unprintable border.
    private static func printInfo() -> NSPrintInfo {
        // ⚠️ A copy. `NSPrintInfo.shared` is the app's own settings object; changing its margins
        // changes them for everything else that ever prints.
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.topMargin = 54
        info.bottomMargin = 54
        info.leftMargin = 54
        info.rightMargin = 54
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        return info
    }

    /// The text view the printer is handed.
    ///
    /// ⚠️ **A TextKit 1 stack, built by hand.** `NSTextView(frame:)` on macOS 14 gives a TextKit 2
    /// view whose `layoutManager` is `nil`, so the height measurement below silently returns zero
    /// and the printer gets a view with nothing in it. Handing the initialiser a container that
    /// already has a layout manager is what pins it to TextKit 1.
    @MainActor
    private static func page(_ report: HealthReport, info: NSPrintInfo) -> NSTextView {
        let width = info.paperSize.width - info.leftMargin - info.rightMargin

        let storage = NSTextStorage(attributedString: attributed(report))
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)

        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)

        layout.ensureLayout(for: container)
        let height = max(layout.usedRect(for: container).height, 1)

        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: height),
                              textContainer: container)
        view.isEditable = false
        view.isSelectable = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        // White paper, not the appearance of the window this was launched from.
        view.drawsBackground = true
        view.backgroundColor = .white
        view.textContainerInset = .zero
        return view
    }

    /// **Send the page to a printer**, through macOS's own print panel.
    ///
    /// The panel is the person's: it carries Apple's own "PDF ▸ Save as PDF", the page range and
    /// the printer list. Wellkept does not reimplement any of it and does not print without it.
    ///
    /// ⚠️ **Only ever from the sheet.** The page carries the Mac's name and, unless the person
    /// turned it off, its serial number — so nothing calls this without having shown them the page
    /// first. That is Hardware's convention, settled on 2026-08-27, and this does not invent a
    /// second one.
    @MainActor
    static func print(_ report: HealthReport) -> Outcome {
        let info = printInfo()
        let operation = NSPrintOperation(view: page(report, info: info), printInfo: info)
        operation.jobTitle = report.title
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        guard operation.run() else { return .cancelled }
        return .done(String(localized: "The report went to the printer."))
    }

    /// **Write the page to a PDF the person chooses.** Offered beside Print because the print
    /// panel's own PDF menu is a place people do not look, and because emailing a PDF is the thing
    /// John actually described wanting.
    @MainActor
    static func savePDF(_ report: HealthReport) -> Outcome {
        let panel = NSSavePanel()
        panel.title = String(localized: "Save Report")
        panel.nameFieldStringValue = fileName(for: report)
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }

        let info = printInfo()
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let operation = NSPrintOperation(view: page(report, info: info), printInfo: info)
        operation.jobTitle = report.title
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else {
            return .failed(String(localized: "The report could not be saved to \(url.lastPathComponent)."))
        }
        return .done(String(localized: "The report was saved as \(url.lastPathComponent)."))
    }
}

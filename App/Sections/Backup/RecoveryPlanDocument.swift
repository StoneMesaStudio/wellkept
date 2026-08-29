// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import AppKit
import Foundation
import WellkeptCore

//  RecoveryPlanDocument.swift
//  Wellkept — App/Sections/Backup
//
//  ⭐ **The Recovery Plan as a piece of paper: one list of blocks, two renderings, no third.**
//
//  ## ⚠️ The constraint that decides everything in this file
//
//  **Instructions that live only on the dead Mac are worthless.** A person reads this page at the
//  moment their Mac shows a question mark, which is exactly the moment they cannot open an app on
//  it. So the deliverable here is not a screen. It is ink, and the screen is a preview of the ink.
//
//  That is why `blocks(for:)` exists. The sheet draws blocks, the printer prints blocks, and there
//  is no second list of what the page says. A preview that could drift from the paste is the bug
//  `RepairShopCopy` was written to avoid — it holds one string rather than a preview and a payload —
//  and this is the same rule one level up: one document, two renderers.
//
//  ## ⛔ There is no value on this page that Wellkept knows
//
//  The FileVault recovery key, the Apple Account password and the backup drive's password are
//  **blanks**. `RecoveryBlank` has a label, a place to look, and a line length — and no value
//  property, ever. macOS 26 moved the FileVault key out of Apple's escrow and into the Passwords
//  app, so "I can get it back with my Apple ID" is no longer true; what Wellkept can do is make
//  somebody press **Show** and write it on the line **while the Mac still works**. What it must
//  never do is print it, and there is nowhere in the type to put it if it tried.
//
//  ## Why the printer is fed a text view rather than a picture of the screen
//
//  `ImageRenderer` would hand back one very tall image, and a printer would slice it at whatever
//  height the paper happens to be — through the middle of a line, mid-sentence, at the exact place
//  somebody is reading in a panic. `NSTextView` paginates at line boundaries because that is what
//  it is for. The page is text; it is printed as text.

enum RecoveryPlanDocument {

    // MARK: - ⭐ One document, in blocks

    /// One piece of the printed page. **The single source of what the page says and in what
    /// order** — the sheet and the printer each turn this into their own medium, and neither owns
    /// the words.
    enum Block: Sendable, Hashable, Identifiable {

        /// The name at the top. Names the Mac, because a household with two ends up with two pages.
        case title(String)

        /// Everything that dates the page, in one line: when, which macOS, which kind of Mac.
        case subtitle(String)

        /// A heading over a run of blocks.
        case heading(String)

        /// A paragraph of plain words.
        case paragraph(String)

        /// One numbered step: what to do, and why. ⚠️ **The why is never optional.** A step
        /// somebody understands is a step they can adapt when the screen in front of them does not
        /// match the page — which, on the worst day, it will not.
        case step(number: Int, title: String, whatToDo: String, why: String)

        /// A warning. `urgent` is the ones that have to be done **today**, while the Mac still
        /// works, and it is the difference between a page that helps and a page that is too late.
        case warning(title: String, body: String, urgent: Bool)

        /// A line to fill in by hand, with where to find the thing. ⛔ No value: see the header.
        case blank(label: String, whereToFindIt: String, lineLength: Int)

        var id: String {
            switch self {
            case .title(let t):                  "title|\(t)"
            case .subtitle(let t):               "subtitle|\(t)"
            case .heading(let t):                "heading|\(t)"
            case .paragraph(let t):              "paragraph|\(t)"
            case .step(let n, let t, _, _):      "step|\(n)|\(t)"
            case .warning(let t, _, let urgent): "warning|\(urgent)|\(t)"
            case .blank(let label, _, _):        "blank|\(label)"
            }
        }
    }

    // MARK: - ⭐ The one list

    /// **What the page says, in the order it says it.**
    ///
    /// The order is not a manual's order. It is the order somebody needs on the worst day: the
    /// thing that must be done today first, then the instruction not to make the irreversible
    /// mistake, then the steps, then the blanks. `RecoveryPlan.make` already put the steps in that
    /// order and this does not re-sort them.
    static func blocks(for plan: RecoveryPlan) -> [Block] {
        var blocks: [Block] = [
            .title(plan.title),
            .subtitle(plan.subtitle),
            .paragraph(RecoveryPlan.printIt),
        ]

        // ⚠️ The must-do-today warning is lifted to the top rather than left in the list. A person
        // reading this page in Recovery cannot act on it — it is the one item that is useless
        // unless it is read months early, so it is the one item that goes where it will be read.
        if let today = plan.warningForToday {
            blocks.append(.heading("Do this today, while the Mac still works"))
            blocks.append(.warning(title: today.title, body: today.body, urgent: true))
        }

        if !plan.steps.isEmpty {
            blocks.append(.heading("On the day the Mac will not start"))
            for (index, step) in plan.steps.enumerated() {
                blocks.append(.step(number: index + 1,
                                    title: step.title,
                                    whatToDo: step.whatToDo,
                                    why: step.why))
            }
        }

        let rest = plan.warnings.filter { $0 != plan.warningForToday }
        if !rest.isEmpty {
            blocks.append(.heading("Worth knowing"))
            for warning in rest {
                blocks.append(.warning(title: warning.title,
                                       body: warning.body,
                                       urgent: warning.mustBeDoneWhileTheMacStillWorks))
            }
        }

        if !plan.blanks.isEmpty {
            blocks.append(.heading("Fill these in by hand"))
            // ⛔ Said on the paper, not only in a comment. Somebody who finds this page in a drawer
            // in two years should be able to tell from the page itself that the app never knew.
            blocks.append(.paragraph(whatWellkeptCannotWriteHere))
            for blank in plan.blanks {
                blocks.append(.blank(label: blank.label,
                                     whereToFindIt: blank.whereToFindIt,
                                     lineLength: blank.lineLength))
            }
        }

        return blocks
    }

    /// ⛔ **The sentence on the paper about the empty lines.**
    static let whatWellkeptCannotWriteHere = """
        Wellkept cannot read any of these and never will — no app can read your FileVault recovery \
        key or your passwords. Write them here by hand, in ink, and keep this page somewhere other \
        than beside the Mac.
        """

    /// What the printed file is called when it is saved rather than printed.
    static func fileName(for plan: RecoveryPlan) -> String {
        let stamp = plan.writtenOn.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let safe = plan.title.replacingOccurrences(of: "/", with: "-")
        return "\(safe) \(stamp).pdf"
    }

    // MARK: - The page as text

    /// The whole page as plain text, for anywhere a person wants it without a printer.
    static func plainText(for plan: RecoveryPlan) -> String {
        var lines: [String] = []
        for block in blocks(for: plan) {
            switch block {
            case .title(let text):
                lines.append(text)
            case .subtitle(let text):
                lines.append(text)
                lines.append("")
            case .heading(let text):
                lines.append("")
                lines.append(text.uppercased())
                lines.append("")
            case .paragraph(let text):
                lines.append(text)
                lines.append("")
            case .step(let number, let title, let whatToDo, let why):
                lines.append("\(number). \(title)")
                lines.append("   \(whatToDo)")
                lines.append("   Why: \(why)")
                lines.append("")
            case .warning(let title, let body, _):
                lines.append(title)
                lines.append(body)
                lines.append("")
            case .blank(let label, let whereToFindIt, let lineLength):
                lines.append("\(label):  \(String(repeating: "_", count: lineLength))")
                lines.append("   \(whereToFindIt)")
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - The page as ink

    /// The type on the paper. Fixed points, deliberately: this is a sheet of paper, and it does not
    /// follow the app's text-size setting. Somebody who has made the window's type larger has not
    /// asked for a bigger piece of paper.
    private enum Ink {
        // ⚠️ Computed, not stored. `NSFont` is not `Sendable`, so a stored global of one is a
        // compile error under Swift 6 strict concurrency — and it would be shared mutable state
        // besides. These are cheap: AppKit caches fonts.
        static var title: NSFont { .systemFont(ofSize: 20, weight: .semibold) }
        static var subtitle: NSFont { .systemFont(ofSize: 10, weight: .regular) }
        static var heading: NSFont { .systemFont(ofSize: 13, weight: .semibold) }
        static var body: NSFont { .systemFont(ofSize: 11, weight: .regular) }
        static var strong: NSFont { .systemFont(ofSize: 11, weight: .semibold) }
        static var quiet: NSFont { .systemFont(ofSize: 9.5, weight: .regular) }
        /// The rule under a blank. Monospaced so a run of underscores is a straight line rather
        /// than a dotted one, which is what a proportional font makes of it.
        static var rule: NSFont { .monospacedSystemFont(ofSize: 11, weight: .regular) }
    }

    /// The page, set for a printer.
    ///
    /// ⚠️ Black on white, always, whatever the app's appearance is. `NSColor.textColor` is dynamic
    /// and would come out white on a Mac in dark mode — which prints as nothing at all.
    static func attributed(_ plan: RecoveryPlan) -> NSAttributedString {
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

        for block in blocks(for: plan) {
            switch block {
            case .title(let text):
                add(text, font: Ink.title, style: paragraphStyle(spaceAfter: 2))
            case .subtitle(let text):
                add(text, font: Ink.subtitle, style: paragraphStyle(spaceAfter: 12))
            case .heading(let text):
                add(text, font: Ink.heading, style: paragraphStyle(spaceBefore: 14, spaceAfter: 6))
            case .paragraph(let text):
                add(text, font: Ink.body, style: paragraphStyle())
            case .step(let number, let title, let whatToDo, let why):
                add("\(number).  \(title)", font: Ink.strong,
                    style: paragraphStyle(spaceBefore: 8, spaceAfter: 2))
                add(whatToDo, font: Ink.body, style: paragraphStyle(spaceAfter: 2, indent: 20))
                add("Why: \(why)", font: Ink.quiet, style: paragraphStyle(spaceAfter: 4, indent: 20))
            case .warning(let title, let body, _):
                add(title, font: Ink.strong, style: paragraphStyle(spaceBefore: 8, spaceAfter: 2))
                add(body, font: Ink.body, style: paragraphStyle(spaceAfter: 4))
            case .blank(let label, let whereToFindIt, let lineLength):
                add(label, font: Ink.strong, style: paragraphStyle(spaceBefore: 10, spaceAfter: 2))
                add(String(repeating: "_", count: lineLength), font: Ink.rule,
                    style: paragraphStyle(spaceAfter: 2))
                add(whereToFindIt, font: Ink.quiet, style: paragraphStyle(spaceAfter: 4))
            }
        }

        return page
    }

    // MARK: - ⭐ Printing and saving

    /// What happened when somebody pressed a button on the sheet.
    enum Outcome: Sendable, Equatable {
        /// It went to the printer, or to a file, and the page is on record.
        case done(String)
        /// The person closed the panel. **Not an error, and it says nothing.**
        case cancelled
        /// It genuinely failed.
        case failed(String)

        var sentence: String? {
            switch self {
            case .done(let words):   words
            case .cancelled:         nil
            case .failed(let words): words
            }
        }
    }

    /// Paper, in points. US Letter margins of three quarters of an inch — enough that nothing lands
    /// in a printer's unprintable border, which is where a hand-written FileVault key would end up.
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
    private static func page(_ plan: RecoveryPlan, info: NSPrintInfo) -> NSTextView {
        let width = info.paperSize.width - info.leftMargin - info.rightMargin

        let storage = NSTextStorage(attributedString: attributed(plan))
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
    /// The panel is the person's: it carries Apple's own "PDF ▸ Save as PDF", the page range, and
    /// the printer list. Wellkept does not reimplement any of it and does not print without it.
    @MainActor
    static func print(_ plan: RecoveryPlan) -> Outcome {
        let info = printInfo()
        let operation = NSPrintOperation(view: page(plan, info: info), printInfo: info)
        operation.jobTitle = plan.title
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        guard operation.run() else { return .cancelled }
        return .done("Your Recovery Plan went to the printer. Keep it somewhere that is not this Mac.")
    }

    /// **Write the page to a PDF the person chooses.**
    ///
    /// Offered beside Print because the panel's own PDF menu is a place people do not look, and
    /// because a page saved to a phone or another Mac is a page that survives this one. ⚠️ It is
    /// still not as good as paper: a PDF on the Mac that will not start is a PDF you cannot open.
    /// The sheet says so.
    @MainActor
    static func savePDF(_ plan: RecoveryPlan) -> Outcome {
        let panel = NSSavePanel()
        panel.title = "Save Recovery Plan"
        panel.nameFieldStringValue = fileName(for: plan)
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }

        let info = printInfo()
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let operation = NSPrintOperation(view: page(plan, info: info), printInfo: info)
        operation.jobTitle = plan.title
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else {
            return .failed("The Recovery Plan could not be saved to \(url.lastPathComponent).")
        }
        return .done("Your Recovery Plan was saved as \(url.lastPathComponent). "
                     + "A file on this Mac is not a page in a drawer — print one too.")
    }
}

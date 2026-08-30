// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation

//  HealthReport.swift
//  WellkeptCore
//
//  ⭐ **The page a person hands to somebody else.**
//
//  It was approved as question 34 of `SHELL-QUESTIONS.md`, and the want described is a
//  specific one: *"mail this to the person who fixes my Mac."* So the deliverable is not a screen.
//  It is a page — printed, or saved as a PDF and attached to an email — and it is read by somebody
//  who was not sitting in front of the Mac when the checks ran.
//
//  That reader is the whole reason this type exists rather than a function that formats whatever
//  Overview happens to be showing.
//
//  ## ⛔ The three things a page can do that a screen cannot, and the guards against each
//
//  **1. It outlives its own caveats.** On screen, "Storage could not see everything" sits three
//  inches above the list it qualifies, and both go away together. On paper the list travels and the
//  caveat can be left behind — so `caveats` is computed in `init` from the same inputs as the
//  findings, and there is no initialiser that takes a finished list of caveats. A report cannot be
//  built without them.
//
//  **2. It gets read as a clean bill of health.** A page with no findings on it looks like good
//  news whatever the words say. So `isCleanBillOfHealth` is a single computed answer, `headline`
//  returns `everythingLooksFine` if and only if that answer is true, and the four ways it can be
//  false — a check that never ran, a check that saw part of the Mac, a permission that was off,
//  sample results — each independently forbid the clean sentence. This is the rule the whole app is
//  built on, stated once, in a value nobody has to remember to consult.
//
//  **3. It carries a serial number to a stranger.** `includeSerial` is the person's own choice and
//  it is honoured here, in the one place the machine block is assembled, so a preview built from
//  this report cannot disagree with the PDF built from the same report. Hardware settled the
//  convention on 2026-08-27 — see `RepairShopCopy`, which holds one string rather than a preview
//  and a payload — and this is that convention one level up: **one report, several renderings.**
//
//  ## ⛔ Never a score
//
//  There is no number on this page that grades the Mac, and there is nowhere in this type to put
//  one. `SectionStatus` has three words and no rank; `Severity` sorts but does not total. A page
//  that said "84/100" would be graded on how little happened to be installed, and it would be the
//  first thing anybody read.
//
//  ## Where the sentences come from
//
//  The framing — the headline, the section titles, the line about what the audit trail is — is this
//  file's own, because it is about this page. **Everything that is a claim about the app is quoted
//  rather than paraphrased**: what a permission costs comes from the app's own per-section
//  sentences, handed in as `PermissionShortfall`; what declining the update check costs comes from
//  `Privacy.Departure.appUpdateCheck.cost`, which is the register. Nothing about privacy is written
//  twice — see the header of `Privacy.swift`.

// MARK: - What a permission being off actually cost

/// One permission that was off when the checks ran, and what each affected section lost by it.
///
/// ⚠️ **The sentences are handed in, never written here.** They are the app's own
/// `FullDiskAccess.shortfall(for:)` strings — the same words the section's own face shows — so the
/// page and the screen cannot describe the same refusal two different ways.
public struct PermissionShortfall: Sendable, Hashable {

    /// What macOS calls it: "Full Disk Access".
    public let permission: String

    /// What each affected section lost, in that section's own terms, in sidebar order.
    public let sentences: [String]

    public init(permission: String, sentences: [String]) {
        self.permission = permission
        self.sentences = sentences
    }
}

// MARK: - The report

public struct HealthReport: Sendable, Hashable {

    // MARK: One line of the audit trail

    /// One of the seven, and when it ran.
    ///
    /// ⚠️ **`ranAt` is optional and that is the point.** The developer asked for the audit trail by name —
    /// *"an audit trail for reassurance of what was checked please"* — and a list that quietly
    /// omitted the checks that never ran would be reassurance about nothing. All seven appear,
    /// every time, and the ones that did not run say so.
    public struct AuditLine: Sendable, Hashable, Identifiable {

        public let section: SectionID
        /// `nil` when this check has never been run.
        public let ranAt: Date?
        public let status: SectionStatus
        /// `false` when a permission stopped this check seeing everything.
        public let sawEverything: Bool

        public var id: String { section.rawValue }

        public init(section: SectionID, ranAt: Date?, status: SectionStatus, sawEverything: Bool) {
            self.section = section
            self.ranAt = ranAt
            self.status = status
            self.sawEverything = sawEverything
        }

        /// When it ran, or the plain statement that it did not. Never a dash: a dash on a page
        /// somebody else is reading is a shrug, and this line's whole job is to be unambiguous.
        public var whenSentence: String {
            guard let ranAt else { return String(localized: "Not run") }
            return ShortDate.stamp(ranAt)
        }

        /// ⚠️ **Whether this row should say the check saw only part of the Mac.**
        ///
        /// Not simply `!sawEverything`. A check that never ran saw *nothing*, not part — and the
        /// first printed page said "Apps: Not checked — Not run (saw part of this Mac)", which
        /// claims a look that never happened. The row already says "Not run"; the caveat about a
        /// short look belongs only to a check that actually looked.
        public var sawOnlyPart: Bool { ranAt != nil && !sawEverything }

        /// The line as one string, for a rendering that has one column rather than four.
        public var line: String {
            var text = "\(section.title): \(status.label) — \(whenSentence)"
            if sawOnlyPart { text += String(localized: " (saw part of this Mac)") }
            return text
        }
    }

    // MARK: A caveat that travels with the page

    /// Something the reader has to know before they believe anything else on the page.
    public struct Caveat: Sendable, Hashable, Identifiable {
        public let title: String
        public let body: String

        public var id: String { title }

        public init(title: String, body: String) {
            self.title = title
            self.body = body
        }
    }

    // MARK: What is on the page

    public let writtenOn: Date

    /// What the Mac calls itself, from Hardware's own block. `nil` when Hardware has not run.
    public let machineName: String?

    /// Hardware's "what this Mac is" block, already filtered by the person's serial-number choice.
    /// Empty when Hardware has not run.
    public let machine: [DetailPair]

    /// Whether a serial number is actually on this page. Not "whether one was offered" — what a
    /// person needs told before they hand the page over is what it contains.
    public let carriesSerialNumber: Bool

    /// What needs a person, worst first, exactly as Overview lists it. **One row per section**,
    /// because that is what the sections publish; this type does not re-expand them.
    public let findings: [Finding]

    /// All seven, in sidebar order, always.
    public let audit: [AuditLine]

    /// Everything the reader has to know before believing the rest. Computed, never handed in.
    public let caveats: [Caveat]

    /// True only when every one of the six checks ran and every one of them saw the whole machine.
    public let sawEverything: Bool

    /// True when this page describes invented results rather than this Mac.
    public let sampleResults: Bool

    // MARK: - Building one

    /// Assemble the page.
    ///
    /// ⚠️ There is deliberately no initialiser that takes `caveats`, `headline` or `sawEverything`.
    /// All three are conclusions about the inputs, and a caller that could supply them could supply
    /// a page saying the Mac is fine on evidence that says otherwise.
    ///
    /// - Parameters:
    ///   - machine: Hardware's facts, or `nil` if Hardware has not run.
    ///   - includeSerial: the person's own choice, made on the sheet that shows them the page.
    ///   - findings: what needs a person, already sorted worst-first by the caller.
    ///   - records: the audit trail as the app holds it. Missing sections become "Not run".
    ///   - permissionsOff: every permission that was off, with what each cost. Empty is the
    ///     ordinary case.
    ///   - appUpdateChecking: `true` allowed, `false` declined, **`nil` nobody has been asked** —
    ///     the same three states as the stored key, because collapsing them would put a page in
    ///     somebody's hands claiming apps were checked when the question was never put.
    ///   - sampleResults: demo mode. A page produced from invented rows says so first.
    public init(writtenOn: Date = Date(),
                machine: MachineFacts? = nil,
                includeSerial: Bool = true,
                findings: [Finding],
                records: [SectionID: CheckRecord],
                permissionsOff: [PermissionShortfall] = [],
                appUpdateChecking: Bool? = nil,
                sampleResults: Bool = false) {

        self.writtenOn = writtenOn
        self.machineName = machine?.name
        self.machine = machine?.detailPairs.filter { includeSerial || !$0.sensitive } ?? []
        self.carriesSerialNumber = self.machine.contains(where: \.sensitive)
        self.findings = findings
        self.sampleResults = sampleResults

        // ⭐ All seven, from `allCases`, every time. Never `records.keys` — a page built from the
        // keys that happen to be present is a page whose audit trail shrinks exactly when it
        // matters most.
        self.audit = SectionID.allCases.map { section in
            let record = records[section]
            return AuditLine(section: section,
                             ranAt: record?.ranAt,
                             status: record?.status ?? .notChecked,
                             sawEverything: record?.complete ?? false)
        }

        let neverRan = SectionID.checkable.filter { records[$0] == nil }
        let sawPart = SectionID.checkable.filter { records[$0]?.complete == false }

        self.sawEverything = neverRan.isEmpty && sawPart.isEmpty && permissionsOff.isEmpty

        self.caveats = Self.caveats(sampleResults: sampleResults,
                                    neverRan: neverRan,
                                    sawPart: sawPart,
                                    permissionsOff: permissionsOff,
                                    appUpdateChecking: appUpdateChecking,
                                    carriesSerialNumber: self.carriesSerialNumber,
                                    machineName: self.machineName)
    }

    // MARK: - The verdict

    /// ⛔ **The one sentence this page may not say lightly**, and the only place it is written.
    public static let everythingLooksFine = String(localized: "Everything looks fine.")

    /// **Whether this page is entitled to say the Mac looks fine.**
    ///
    /// Four independent vetoes, and any one of them is enough: something needs a person, a check
    /// never ran, a check saw part of the machine, or the rows are invented. A page that cleared
    /// three of the four and failed the fourth is not "mostly clean" — it is a page whose reader
    /// would draw a conclusion nobody measured.
    public var isCleanBillOfHealth: Bool {
        findings.isEmpty && sawEverything && !sampleResults
    }

    /// The verdict, in one sentence. ⛔ Never a score, and never `everythingLooksFine` unless
    /// `isCleanBillOfHealth` is true — that equivalence is asserted in `HealthReportTests`.
    public var headline: String {
        if sampleResults {
            return String(localized: "These are sample results. Wellkept did not look at this Mac.")
        }
        if !sawEverything {
            return String(localized: """
                Wellkept could not see all of this Mac, so this is not a clean bill of health.
                """)
        }
        if findings.isEmpty { return Self.everythingLooksFine }
        return findings.count == 1
            ? String(localized: "One thing needs you.")
            : String(localized: "\(Words.sentenceCase(Words.spelled(findings.count))) things need you.")
    }

    /// The dated line under the headline. The clean state is the sentence **and** the date, and
    /// on a page that somebody else reads weeks later the date is the more load-bearing half.
    public var subtitle: String {
        let stamp = ShortDate.stamp(writtenOn)
        guard let machineName else { return String(localized: "Checked \(stamp).") }
        return String(localized: "\(machineName) — checked \(stamp).")
    }

    /// The title of the document itself: what the file is called, what the print job is called,
    /// and what sits at the top of the page.
    public var title: String {
        guard let machineName else { return String(localized: "Wellkept — a health check") }
        return String(localized: "Wellkept — \(machineName)")
    }

    /// What the audit trail is, said once above it. It is the part of the page the reader is most
    /// likely to skip and most likely to need.
    public static let auditIntro = String(localized: """
        Every check Wellkept can run is listed here, whether or not it was run, with the time it \
        last ran. A check that is not listed as run told this page nothing.
        """)

    /// What the list of findings is, said once above it. Names the rule that makes the list short:
    /// one row per section, and nothing that is merely large.
    public static let findingsIntro = String(localized: """
        One line per check, and only the checks that found something a person has to decide about. \
        A large folder is not on this list; a large folder is not a problem, it is large.
        """)

    /// The line under the machine block, where there is one on the page.
    public static let machineIntro = String(localized: """
        What this Mac is, as this Mac reports it.
        """)

    /// Said on the page when nothing needs anybody. Not the same sentence as the headline: the
    /// headline is the verdict, and this is what stands in place of the list.
    public static let nothingNeedsYou = String(localized: """
        Nothing Wellkept checked needs a person right now.
        """)

    /// ⛔ **The footer, and it is not decoration.** A page in somebody's inbox has no app around it
    /// to explain what it is or where the numbers came from.
    ///
    /// ⚠️ It says what Wellkept did, and it makes no privacy promise. The absolute claim was struck
    /// on 2026-08-27 and every canonical sentence about what leaves this Mac lives in `Privacy` —
    /// a footer is not the place to grow a fourth copy of one. See the header of `Privacy.swift`.
    public static let provenance = String(localized: """
        Written by Wellkept, on the Mac named above, from what that Mac reports about itself. \
        Wellkept reads; it never deletes anything. Somebody chose to send you this page.
        """)

    // MARK: - The caveats

    /// ⛔ **Built here, from the same inputs as everything else on the page, and impossible to
    /// omit.** The failure this prevents is specific: a report that arrives with its qualifications
    /// left on the screen it was printed from, and is read as a clean bill of health nobody claimed.
    private static func caveats(sampleResults: Bool,
                                neverRan: [SectionID],
                                sawPart: [SectionID],
                                permissionsOff: [PermissionShortfall],
                                appUpdateChecking: Bool?,
                                carriesSerialNumber: Bool,
                                machineName: String?) -> [Caveat] {
        var out: [Caveat] = []

        // First, because it invalidates every other line on the page.
        if sampleResults {
            out.append(Caveat(
                title: String(localized: "Nothing on this page was read from a real Mac"),
                body: String(localized: """
                    Wellkept was showing sample results when this page was made. Every figure below \
                    is invented, and none of it describes the Mac this page came from.
                    """)))
        }

        if !neverRan.isEmpty {
            out.append(Caveat(
                title: neverRan.count == 1
                    ? String(localized: "One check was not run")
                    : String(localized: "\(Words.sentenceCase(Words.spelled(neverRan.count))) checks were not run"),
                body: String(localized: """
                    \(Words.list(neverRan.map(\.title))) had not been run when this page was made, \
                    so this page says nothing about \(neverRan.count == 1 ? "it" : "them").
                    """)))
        }

        if !sawPart.isEmpty {
            out.append(Caveat(
                title: String(localized: "Part of this Mac was hidden"),
                body: String(localized: """
                    \(Words.list(sawPart.map(\.title))) could not see everything, so what is \
                    reported for \(sawPart.count == 1 ? "it" : "them") is what Wellkept could see, \
                    not everything there is.
                    """)))
        }

        // ⚠️ The sentences are the app's own, quoted. See `PermissionShortfall`.
        for shortfall in permissionsOff {
            out.append(Caveat(
                title: String(localized: "\(shortfall.permission) was off"),
                body: shortfall.sentences.joined(separator: " ")))
        }

        // ⚠️ Three states, and the middle one is a real answer. Quoted from the register rather
        // than paraphrased — see the header of `Privacy.swift`.
        switch appUpdateChecking {
        case .some(true):
            break
        case .some(false):
            out.append(Caveat(
                title: String(localized: "App update checking was switched off"),
                body: Privacy.Departure.appUpdateCheck.cost))
        case .none:
            out.append(Caveat(
                title: String(localized: "App update checking had not been asked about"),
                body: String(localized: """
                    Nobody had answered the question yet, so no app on this Mac was checked against \
                    its maker.
                    """) + " " + Privacy.Departure.appUpdateCheck.cost))
        }

        // Last, because it is about the page rather than about the Mac — and it is the one line
        // the person holding the page is expected to act on before sending it.
        if carriesSerialNumber {
            out.append(Caveat(
                title: String(localized: "This page carries a serial number"),
                body: String(localized: """
                    The serial number and the name of the Mac are on this page. That is what a \
                    repair shop asks for, and it is also what identifies the machine — send it to \
                    somebody you chose to send it to.
                    """)))
        } else if machineName != nil {
            out.append(Caveat(
                title: String(localized: "This page names the Mac"),
                body: String(localized: """
                    The name of the Mac is on this page. The serial number was left off at your \
                    request.
                    """)))
        }

        return out
    }

    // MARK: - Words

    /// Joining, for the sentences above. `Count` in `OverviewView` does the same job for the
    /// screen; this file cannot reach it — nothing in `WellkeptCore` imports the app — and a
    /// public duplicate of it here would be two things to keep in step for the sake of one comma.
    enum Words {

        private static let small = ["zero", "one", "two", "three", "four", "five", "six",
                                    "seven", "eight", "nine", "ten", "eleven", "twelve"]

        /// Small numbers written out, digits past twelve. **The same rule the screen uses**, so the
        /// paper and the window do not disagree about how to say the same count — a page that read
        /// "3 things need you" beside a screen reading "Three things need you" is two apps.
        static func spelled(_ n: Int) -> String {
            n >= 0 && n < small.count ? small[n] : "\(n)"
        }

        /// Sentence case without touching the rest — `capitalized` would turn "two things" into
        /// "Two Things". (`Storage.swift` has a `fileprivate` one of these; this is the second, and
        /// two `fileprivate` helpers are cheaper than one shared `String` extension nobody owns.)
        static func sentenceCase(_ text: String) -> String {
            guard let first = text.first else { return text }
            return String(first).uppercased() + text.dropFirst()
        }

        /// "Storage" · "Storage and Apps" · "Storage, Apps and Security".
        static func list(_ items: [String]) -> String {
            switch items.count {
            case 0: ""
            case 1: items[0]
            case 2: "\(items[0]) and \(items[1])"
            default: "\(items.dropLast().joined(separator: ", ")) and \(items[items.count - 1])"
            }
        }
    }
}


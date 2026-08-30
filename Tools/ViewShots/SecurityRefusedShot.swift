//
//  SecurityRefusedShot.swift
//  ViewShots
//
//  **The two Security screens `DemoData` cannot show: Full Disk Access refused, and a Mac an
//  organisation configures.**
//
//  `SecurityShot.swift` photographs the four screens demo mode can reach — never checked, both demo
//  Macs, Options open. Demo mode offers two machines because that is a product decision,
//  and these two states are not machines: one is a permission this app was refused, and the other is
//  a Mac whose settings belong to somebody else. Neither has anywhere to live in `DemoData`, and
//  both are screens somebody will actually see.
//
//  ## ⚠️ The refusal is the likeliest real screen in the whole section
//
//  Measured on one real Mac, 2026-08-27: without Full Disk Access, **eleven of the twelve permissions
//  read exactly zero.** Not "fewer" — zero. So the camera / microphone / screen row collapses to one
//  sentence rather than printing a near-empty list, and Location, which reads fine without the
//  grant, is hidden with the rest. One populated row surrounded by refusals reads as *"we checked
//  and found almost nothing"*, which is the single sentence this section promised never to say.
//
//  Setup's last step offers "Finish later", so this is not a corner: it is what the section looks
//  like for everybody who has not granted the permission, which under `xctest` includes this
//  harness.
//
//  ## ⚠️ A management fact is never a problem, and this is where that is looked at
//
//  The work Mac below hands `SecurityReport` three concerns and gets none of them back, because each
//  belongs to a switch an organisation set. That drop happens in one place for all six readers, and
//  the picture is where somebody can see what it produces: no amber, no imperative, and no button
//  onto a pane this person has no authority over. The alternative is a health check that tells an
//  employee their employer has misconfigured their Mac, aimed at somebody who cannot act on it.
//
//  ## Why these two are photographed as the block and the rows
//
//  `SecurityView` reads its answer from `SecurityModel`, and only a real run of the real readers can
//  fill that in — which is exactly the guarantee that stops a render from starting a six-second
//  sweep of this machine. So these two use the section's own `ProtectionsBlockView` and
//  `SecurityRowView` directly. The views are real; what is outside the frame is the heading and the
//  button, which the four full-page shots in `SecurityShot.swift` already cover.
//
//      bin/make-shots.sh
//

import AppKit
import SwiftUI
import Testing
import WellkeptCore

// MARK: - The two Macs

/// A refused Mac and a work Mac, typed out.
///
/// ⚠️ **Nothing here reads this Mac.** Every app name, count and date is invented, which is what
/// makes it possible to photograph a Mac that refused a permission without refusing one, and a Mac
/// an employer configures without enrolling this one.
///
/// Both are built out of the real vocabulary rather than out of finished sentences, so a picture can
/// never show wording the app is no longer capable of producing.
enum SecurityShotMac {

    /// ⚠️ **Full Disk Access refused.**
    ///
    /// Two rows collapse to a sentence apiece, each carrying the one button that can actually clear
    /// it. The other four still report what they saw — going quiet everywhere would be its own kind
    /// of lie, and four of the six read perfectly well without the grant.
    static var refused: SecurityAnswer {
        let block = healthyBlock()
        let report = SecurityReport(block: block, rows: [
            SecurityRow(topic: .protections,
                        headline: "Everything this Mac would tell us about is set the way it protects you.",
                        measure: "7 of 8",
                        reason: "Lockdown Mode is the one thing here this Mac does not report, so "
                              + "this can say neither on nor off for it.",
                        details: block.detailPairs),
            SecurityRow.unreadable(.whoCanWatch, .notPermitted,
                                   reason: "Eleven of the twelve permissions read exactly zero "
                                         + "without it, so this shows nothing rather than a short "
                                         + "list that would look like good news.",
                                   remedy: Remedy(title: "Open System Settings…",
                                                  settingsPane: "fullDiskAccess")),
            SecurityRow(topic: .startsOnItsOwn,
                        headline: "Five things start on their own.",
                        measure: "5 items",
                        reason: "Two of the files found here start nothing at all and are not "
                              + "counted. This list is built from the startup files themselves and "
                              + "can differ from the one in System Settings.",
                        details: [
                            DetailPair("Backup", "Runs every day at 2:30 AM"),
                            DetailPair("Dropbox", "Starts when you log in"),
                            DetailPair("Google software updater", "Every 60 minutes"),
                        ]),
            SecurityRow(topic: .browserExtensions,
                        headline: "Five extensions are installed, and three can read every page you open.",
                        measure: "5 extensions",
                        reason: "That is what a password manager, a content blocker or an assistant "
                              + "needs in order to work at all, so it is worth knowing rather than "
                              + "worth worrying about.",
                        details: [
                            DetailPair("1Blocker Scripts", "Safari · every site"),
                            DetailPair("iCloud Passwords", "Chrome · every site"),
                        ]),
            SecurityRow(topic: .reachableFrom,
                        headline: "AirPlay Receiver is listening, and one folder is shared with guests.",
                        reason: "Nothing above says a service is switched off. This Mac can prove "
                              + "one is on and can never prove one is not.",
                        details: [
                            DetailPair("AirPlay Receiver", "Listening · reachable on the local network"),
                            DetailPair("Public folder", "Shared · guests allowed"),
                        ]),
            SecurityRow.unreadable(.macOSFindings, .notPermitted,
                                   reason: "What macOS has already blocked is one of the things "
                                         + "this permission covers.",
                                   remedy: Remedy(title: "Open System Settings…",
                                                  settingsPane: "fullDiskAccess")),
        ], measuredDays: nil)

        // ⚠️ **No grants beside a refusal, by construction.** There is no path in this app that draws
        // a short list next to "we were not allowed to look".
        return SecurityAnswer(report: report)
    }

    /// **A Mac an organisation configures.**
    ///
    /// Three protections set by an employer. Each is stated as a fact, none of them is a finding,
    /// and the three concerns handed to `SecurityReport` below are all dropped before anything sees
    /// them.
    static var managed: SecurityAnswer {
        let block = ProtectionsBlock(
            protections: [
                Protection(kind: .fileVault, state: .on, detail: "the disk is locked"),
                Protection(kind: .systemProtection, state: .on,
                           detail: "every protected part of macOS"),
                Protection(kind: .gatekeeper, state: .reduced, setByOrganisation: true),
                Protection(kind: .secureBoot, state: .on, detail: "full security"),
                Protection(kind: .firewall, state: .off, setByOrganisation: true),
                Protection(kind: .automaticSecurityUpdates, state: .off, setByOrganisation: true),
                Protection(kind: .automaticLogin, state: .off),
                Protection(kind: .lockdownMode, state: .unreadable(.notReported)),
            ],
            xprotectVersion: "5357",
            xprotectUpdated: daysAgo(6),
            isManaged: true)

        let report = SecurityReport(block: block, rows: [
            SecurityRow(topic: .protections,
                        headline: "Three of this Mac's protections are chosen by an organisation.",
                        measure: "3 of 8",
                        // ⚠️ Handed in deliberately, and every one of them is dropped by
                        // `SecurityReport.init` because it belongs to a switch the organisation set.
                        // That is the whole mechanism, exercised rather than described.
                        concerns: [.gatekeeperWeakened, .firewallOff, .automaticSecurityUpdatesOff],
                        reason: "An organisation configures this Mac. These are not this account's "
                              + "settings, and the panes that hold them are not this account's to "
                              + "open.",
                        details: block.detailPairs),
            SecurityRow(topic: .whoCanWatch,
                        headline: "Five apps hold a permission between them.",
                        measure: "5 apps",
                        reason: "One of them is the meeting client this Mac's organisation "
                              + "installed. Wellkept is in this list too, because it holds Full "
                              + "Disk Access.",
                        details: [
                            DetailPair("Camera", "2 apps"),
                            DetailPair("Microphone", "1 app"),
                            DetailPair("Screen recording", "1 app"),
                            DetailPair("Full Disk Access", "1 app — Wellkept, which is this app"),
                        ]),
            SecurityRow(topic: .startsOnItsOwn,
                        headline: "Eleven things start on their own.",
                        measure: "11 items",
                        reason: "Six of them come from configuration profiles this Mac's "
                              + "organisation installed.",
                        details: [
                            DetailPair("Company agent", "Kept running · MegaCorp IT"),
                            DetailPair("Endpoint reporter", "Starts when the Mac starts · MegaCorp IT"),
                        ]),
            SecurityRow(topic: .browserExtensions,
                        headline: "Four extensions are installed, and one can read every page you open.",
                        measure: "4 extensions",
                        details: [DetailPair("Company single sign-on", "Chrome · every site")]),
            SecurityRow(topic: .reachableFrom,
                        headline: "Remote Management is listening and reachable on the local network.",
                        reason: "That is how an organisation administers a Mac it configures.",
                        details: [DetailPair("Remote Management",
                                             "Listening · reachable on the local network")]),
            SecurityRow(topic: .macOSFindings,
                        headline: "macOS's own scanners found nothing in the last 13 days.",
                        measure: "24 scans",
                        details: [DetailPair("Records reach back to", "13 days")]),
        ], measuredDays: 13)

        return SecurityAnswer(report: report, grants: managedGrants)
    }

    // MARK: Parts

    /// A Mac with every switch in the position that protects somebody, and Lockdown Mode saying so.
    /// Used by the refused Mac, whose protections read perfectly well without the permission.
    static func healthyBlock() -> ProtectionsBlock {
        ProtectionsBlock(
            protections: [
                Protection(kind: .fileVault, state: .on, detail: "the disk is locked"),
                Protection(kind: .systemProtection, state: .on,
                           detail: "every protected part of macOS"),
                Protection(kind: .gatekeeper, state: .on, detail: "only apps macOS recognises"),
                Protection(kind: .secureBoot, state: .on, detail: "full security"),
                Protection(kind: .firewall, state: .on, detail: "limiting incoming connections"),
                Protection(kind: .automaticSecurityUpdates, state: .on),
                Protection(kind: .automaticLogin, state: .off),
                Protection(kind: .lockdownMode, state: .unreadable(.notReported)),
            ],
            xprotectVersion: "5357",
            xprotectUpdated: daysAgo(6))
    }

    static let managedGrants: [Grant] = [
        Grant(appName: "Zoom", bundleID: "us.zoom.xos", permission: .camera, signature: .matches),
        Grant(appName: "Zoom", bundleID: "us.zoom.xos", permission: .microphone, signature: .matches),
        Grant(appName: "Company meeting client", bundleID: "com.megacorp.meet",
              permission: .screenRecording, signature: .matches),
        Grant(appName: "Company meeting client", bundleID: "com.megacorp.meet",
              permission: .camera, signature: .matches),
        Grant(appName: "Wellkept", bundleID: "studio.stonemesa.wellkept",
              permission: .fullDiskAccess, signature: .matches, isWellkept: true),
    ]

    static func daysAgo(_ days: Int) -> Date {
        Date(timeIntervalSinceNow: -Double(days) * 86_400)
    }
}

// MARK: - The pictures

@Suite("View shots — Security, refused and managed", .serialized)
@MainActor
struct SecurityRefusedShot {

    /// The block and the six rows, drawn by the section's own views inside the page's own chrome.
    private func page(_ answer: SecurityAnswer) -> some View {
        StableScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                // The one place these pictures read this Mac, and it is the honest one: the notice
                // is a real part of the real face, and it draws exactly when the grant is off.
                PermissionNoticeLine(section: .security)

                Text(answer.report.summary)
                    .font(.appTitle3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ProtectionsBlockView(block: answer.report.block)

                VStack(spacing: 0) {
                    ForEach(Array(answer.report.rows.enumerated()), id: \.element.id) { index, row in
                        SecurityRowView(row: row, index: index, block: answer.report.block)
                    }
                }
            }
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

    /// Run a block with the app's text size turned up.
    ///
    /// ⚠️ The setting is the real one and it is global for the duration of the render, which is why
    /// this suite is `.serialized` and why `bin/make-shots.sh` disables parallel testing. Restored
    /// whatever happens, including a failed expectation.
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

    // MARK: The two screens

    /// ⚠️ **Full Disk Access refused — the collapsed single-sentence state.**
    ///
    /// What to look at in this picture: one sentence rather than a short list, a button that can
    /// actually clear it, **no figure anywhere on those two rows**, and four rows that still say
    /// what they found. If a "0 apps" ever appears here, the section is reporting a zero because it
    /// could not look.
    @Test("Security, with Full Disk Access refused")
    func fullDiskAccessRefused() {
        bothAppearances(page(SecurityShotMac.refused),
                        width: Layout.windowDefault.width, height: 2_400,
                        120, "security-refused")
    }

    /// **A Mac an organisation configures.** No amber, no imperative, and no button onto a pane this
    /// person cannot change — a description rather than an accusation.
    @Test("Security, a Mac an organisation configures")
    func managedMac() {
        bothAppearances(page(SecurityShotMac.managed),
                        width: Layout.windowDefault.width, height: 2_400,
                        122, "security-managed")
    }

    // MARK: The same two at 200% text
    //
    // ⚠️ **A row of app names and permissions is what breaks first when the type doubles.** The
    // refusal is one long sentence with a button beside it, and the work Mac's protections block is
    // eight switches each carrying "(set by an organisation)" — the two shapes in this section most
    // likely to come apart at 200%, and neither is reachable from demo mode.

    @Test("Security at 200% text — refused and managed")
    func bothAtLargestText() {
        atLargestText {
            let width = Layout.windowDefault.width
            bothAppearances(page(SecurityShotMac.refused), width: width, height: 5_200,
                            124, "security-200-refused")
            bothAppearances(page(SecurityShotMac.managed), width: width, height: 5_200,
                            126, "security-200-managed")
        }
    }

    /// **The floor size, at 200% text.** 1020 × 640 is a size this window can genuinely be dragged
    /// to, and a refusal whose button falls off the bottom of the pane at that size is a refusal
    /// nobody can clear.
    @Test("Refused and managed at 200% text, at the smallest the window goes")
    func atTheFloorSizeWithLargestText() {
        atLargestText {
            let size = Layout.windowMinimum
            bothAppearances(page(SecurityShotMac.refused),
                            width: size.width, height: size.height, 128, "security-200-refused-floor")
        }
    }

    /// **At 200% text these two still hold the readable column.**
    ///
    /// The failure this catches is invisible to every other test in the build: a measurement written
    /// as a literal instead of through `AppFont.pt`, which holds at 100% and pushes words out past
    /// the 700-point column when the type doubles. A column that holds leaves bare ground in the
    /// right-hand tenth of a 2000-point window; a row that has spread fills it with words.
    @Test("At 200% text the refused and managed screens hold the readable column")
    func theColumnHoldsAtLargestText() {
        atLargestText {
            for (name, answer) in [("refused", SecurityShotMac.refused),
                                   ("managed", SecurityShotMac.managed)] {
                guard let rep = ShotWriter.render(
                    page(answer)
                        .frame(width: 2000, height: 900)
                        .environment(\.colorScheme, .light)
                        .environment(\.palette, Palette(level: .calm, scheme: .light)),
                    width: 2000, height: 900, scheme: .light)
                else { Issue.record("\(name): nothing rendered"); continue }

                let edge = ShotWriter.distinctColours(in: rep, fromFraction: 0.90, toFraction: 0.99)
                print("PROBE security-200-\(name) right-edge colours at 2000pt: \(edge)")
                #expect(edge <= 3, """
                    security (\(name)) at 200% text: the right-hand tenth of a 2000-point window \
                    has \(edge) distinct colours in it, so a row is drawing out there. The content \
                    column is 700 points and centres — something in the section is sized with a \
                    literal instead of through AppFont.pt.
                    """)
            }
        }
    }
}

// MARK: - The two Macs have to be what they claim

/// ⭐ **A picture of a Mac that is not the Mac it says it is certifies nothing.**
///
/// Each claim below is checked through the same computed properties the screen reads, so a fixture
/// cannot quietly become a different Mac than the caption on the picture says.
///
/// This suite is in `ViewShots` rather than in `WellkeptTests` for the same structural reason
/// `DemoMachineTests` is: `WellkeptTests` compiles `Tests/` against the `WellkeptCore` package alone
/// and cannot see `SecurityAnswer` or `DemoData`.
@Suite("Security — the refused and managed Macs are what they claim")
struct SecurityShotMacTests {

    // MARK: The refusal

    /// ⚠️ **The refused Mac is incomplete, and it is the only one of the four that is.** A refusal a
    /// person can lift belongs on Overview, because pressing something clears it — which is exactly
    /// what separates it from the root-only facts that leave the check complete.
    @Test func onlyTheRefusedMacIsIncomplete() throws {
        let refused = SecurityShotMac.refused.report
        #expect(!refused.complete)
        #expect(!refused.record.complete)
        #expect(refused.record.section == .security)

        for other in [DemoData.security(.healthy).report,
                      DemoData.security(.problems).report,
                      SecurityShotMac.managed.report] {
            #expect(other.complete, "a fully-read Mac is being reported as incomplete")
        }
    }

    /// ⚠️ **An unread row carries no figure, no concern, and a button that works.** "0 apps can see
    /// your camera" would be the most comforting sentence this app could print and the most
    /// dishonest.
    @Test func theRefusedRowSaysNothingItDidNotSee() throws {
        let watch = try #require(SecurityShotMac.refused.report.row(.whoCanWatch))
        #expect(watch.unreadable == .notPermitted)
        #expect(watch.measure == nil, "an unread row is printing a figure")
        #expect(watch.concerns.isEmpty, "an unread row raised a concern about what it did not see")
        #expect(watch.severity == .information)
        #expect(watch.status == .notChecked)
        #expect(watch.remedy != nil, "a refusal a person could lift, with no way to lift it")
        #expect(watch.remedy?.settingsPane == "fullDiskAccess")
    }

    /// ⚠️ **No list beside a refusal, and Location goes with the rest.** One populated row surrounded
    /// by refusals reads as "we checked and found almost nothing", which is the thing this section
    /// promised never to say.
    @Test func theRefusedMacDrawsNoListAtAll() {
        let answer = SecurityShotMac.refused
        #expect(answer.grants.isEmpty)
        #expect(answer.systemServicesUsingLocation == 0, "Location was left showing on its own")
        #expect(answer.unplaceable.isEmpty)
    }

    /// It still reports the four rows it could read. Going quiet everywhere would be its own kind of
    /// lie: the protections, the startup items, the browser extensions and the sockets all read
    /// perfectly well without the permission.
    @Test func theRefusedMacStillReportsWhatItCouldSee() {
        let report = SecurityShotMac.refused.report
        #expect(report.rows.filter { $0.unreadable == nil }.count == 4)
        #expect(report.unreadableTopics.map(\.topic) == [.whoCanWatch, .macOSFindings])
        #expect(report.status == .good)
        #expect(report.summary.contains("were allowed to see"),
                "the summary claims a scope the run did not have")
    }

    /// ⚠️ **A window nobody measured is admitted rather than invented.** The refused Mac could not
    /// read the log at all, so the sentence shrugs instead of printing a plausible fortnight.
    @Test func theRefusedMacInventsNoWindow() {
        let report = SecurityShotMac.refused.report
        #expect(report.measuredDays == nil)
        #expect(report.windowClause.contains("how far back"))
        for digit in "0123456789" {
            #expect(!report.windowClause.contains(digit), "a number appeared in the shrug")
        }
    }

    // MARK: The work Mac

    /// ⚠️ **Three concerns in, none out.** The work Mac is Good, because every one of the three
    /// belongs to a switch the organisation set — dropped in one place so six readers cannot each
    /// forget.
    @Test func theWorkMacIsGoodBecauseTheOrganisationSetIt() {
        let managed = SecurityShotMac.managed.report
        #expect(managed.status == .good)
        #expect(managed.concerns.isEmpty, "an employer's setting reached the user as their fault")
        #expect(managed.overviewFinding == nil)
        #expect(managed.record.status == .good)
        #expect(managed.block.isManaged)
    }

    /// The readings themselves stay honest — they are simply not faults. And no button is offered
    /// onto a pane this person has no authority over.
    @Test func theWorkMacIsStillHonestAboutWhatIsOff() {
        let organisationSet = SecurityShotMac.managed.report.block.protections
            .filter(\.setByOrganisation)
        #expect(organisationSet.count == 3)

        for protection in organisationSet {
            #expect(protection.isProtecting == false, "the reading stopped being honest")
            #expect(protection.concern == nil)
            #expect(protection.settingsPane == nil, "\(protection.kind.rawValue) offers a dead button")
            #expect(protection.detailPair.value.contains("set by an organisation"))
        }
    }

    /// ⚠️ **No imperative anywhere on the work Mac** — on a row, in the summary, or in the block.
    /// Every one of those settings is beyond this person's reach, and telling them to change it is
    /// the version of this section that becomes an accusation about somebody's employer.
    @Test func theWorkMacGivesNobodyAnOrder() {
        let managed = SecurityShotMac.managed.report
        var sentences = [managed.summary, managed.windowClause]
        sentences += managed.rows.flatMap { [$0.headline, $0.reason ?? ""] }
        sentences += managed.block.detailPairs.map(\.value)

        for sentence in sentences {
            let words = sentence.lowercased()
            for order in ["you should", "you must", "you need to", "turn on", "turn off", "fix "] {
                #expect(!words.contains(order), "the work Mac says “\(order)”: \(sentence)")
            }
        }
    }

    // MARK: Both, and the two demo Macs beside them

    /// ⚠️ **None of the four says a *named* sharing service is off**, because no Mac can prove one
    /// is. "Remote Login: Off" on a Mac somebody can log into looks exactly like "Remote Login: Off"
    /// on a Mac nobody can, and the person reading has no way to tell which they have.
    ///
    /// The check names the five services rather than hunting for the word "off", and the reason is
    /// worth keeping: the real row's own copy contains the sentence *"a service that is switched off
    /// and one we simply could not see look the same from here, so nothing above says a service is
    /// off"* — which is the promise being kept, in a sentence a substring search calls a violation.
    @Test func noMacInAnyPictureSaysANamedServiceIsOff() throws {
        for report in Self.everyMac {
            let row = try #require(report.row(.reachableFrom))
            let words = "\(row.headline) \(row.reason ?? "")".lowercased()

            for service in ReachableReader.Service.allCases {
                let name = service.label.lowercased()
                for claim in ["\(name) is off", "\(name) is switched off", "\(name) is not on",
                              "\(name): off", "\(name) — off"] {
                    #expect(!words.contains(claim), "the row claims “\(claim)”")
                }
            }

            for pair in row.details {
                #expect(pair.value != "Off", "\(pair.label) is being reported as off")
                #expect(!pair.value.hasPrefix("Off "), "\(pair.label) is being reported as off")
                // "Not seen listening" is allowed and is the right wording — but only while it
                // carries the caveat that makes it honest. Without that clause it is "off" in a
                // costume.
                if pair.value.hasPrefix("Not seen") {
                    #expect(pair.value.lowercased().contains("no way to prove"),
                            "\(pair.label) states an absence with no caveat: \(pair.value)")
                }
            }
        }
    }

    /// ⚠️ **The word "safe" appears on none of the four**, in any sentence any of them can put on the
    /// screen. Wellkept looks when it is asked and never again; the one sentence that would make
    /// somebody stop looking is the one this section may never print.
    @Test func notOneOfTheMacsInThePicturesCallsItselfSafe() {
        var sentences: [String] = []
        for report in Self.everyMac {
            sentences += [report.summary, report.windowClause]
            sentences += report.rows.flatMap { [$0.headline, $0.reason ?? ""] }
            sentences += report.block.detailPairs.flatMap { [$0.label, $0.value] }
        }

        #expect(sentences.count > 100, "the sweep looked at almost nothing")
        for sentence in sentences {
            #expect(!sentence.lowercased().contains("safe"), "“\(sentence)”")
        }
    }

    /// Every Mac in every picture draws its rows in the fixed order. A panel that reshuffles between
    /// runs is a panel a person has to re-read every time they open it.
    @Test func everyMacInThePicturesUsesTheFixedRowOrder() {
        for report in Self.everyMac {
            let order = report.rows.map(\.topic)
            #expect(order == SecurityTopic.allCases.filter(order.contains))
        }
    }

    /// ⚠️ **Nothing red, on any of the four.** All nine of this section's conditions are `.attention`
    /// by construction, so a red tag in any Security picture means something reached past
    /// `SecurityConcern` to set a severity by hand.
    @Test func nothingInAnyPictureIsRed() {
        for report in Self.everyMac {
            for row in report.rows {
                #expect(row.severity != .problem, "\(row.topic.rawValue) reached red")
            }
            #expect(report.overviewFinding?.severity != .problem)
        }
    }

    static var everyMac: [SecurityReport] {
        [DemoData.security(.healthy).report,
         DemoData.security(.problems).report,
         SecurityShotMac.refused.report,
         SecurityShotMac.managed.report]
    }
}

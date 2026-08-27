import Foundation
import Testing
import WellkeptCore

//  InventoryReaderTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **The four promises the inventory makes, checked by a machine rather than remembered.**
//
//  1. **The three numbers stay apart.** 31 apps, 65 that come with macOS, 327 other bundles. Add any
//     two of them together and the section's first line overstates what is on the Mac.
//  2. **We read who signed an app and never claim to verify one.** There is no case for it in the
//     type; these tests hold the wording as well.
//  3. **Intel-only is a fact, not a warning.** No countdown, no colour, no route to Overview.
//  4. **Never report zero because we could not look.** A report that will not parse is an unreadable
//     row, and a cancelled run is nothing at all — never a short list.
//
//  Nearly everything here is a fixture: entries typed out below, taken verbatim from what
//  `system_profiler` printed on this Mac on 2026-08-27. The one live test reads the real machine and
//  asserts nothing about what it finds, only that the shape holds — because a test that asserts this
//  Mac has 31 apps fails on everybody else's, and the fix somebody reaches for is to delete it.

// MARK: - Fixtures

private enum Fixture {

    /// Six entries in the shape `system_profiler` writes: two the person would call apps, two that
    /// come with macOS, two that are not apps at all. The real Mac's ratio is 30 : 65 : 327.
    static let report = json([
        entry(name: "Google Chrome",
              path: "/Applications/Google Chrome.app",
              version: "152.0.7977.64",
              arch: "arch_arm_i64",
              obtained: "identified_developer",
              signed: ["Developer ID Application: Google LLC (EQHXZ8M8AV)",
                       "Developer ID Certification Authority",
                       "Apple Root CA"]),
        entry(name: "LibreOffice",
              path: "/Applications/LibreOffice.app",
              version: "26.2.2.2",
              arch: "arch_arm",
              obtained: "identified_developer",
              signed: ["Developer ID Application: The Document Foundation (7P5S3ZLCN7)"]),
        entry(name: "App Store",
              path: "/System/Applications/App Store.app",
              version: "3.0",
              arch: "arch_arm_i64",
              obtained: "apple",
              signed: ["macOS Software Signing"]),
        entry(name: "Disk Utility",
              path: "/System/Applications/Utilities/Disk Utility.app",
              version: "24.0",
              arch: "arch_arm_i64",
              obtained: "apple",
              signed: ["macOS Software Signing"]),
        entry(name: "Bug Reporter",
              path: "/System/Library/CoreServices/Applications/Bug Reporter.app",
              version: "1.0",
              arch: "arch_arm_i64",
              obtained: "apple",
              signed: ["macOS Software Signing"]),
        entry(name: "WellkeptTests-Runner",
              path: "/Users/someone/Library/Developer/Xcode/DerivedData/x/Runner.app",
              version: "1.0",
              arch: "arch_arm_i64",
              obtained: "unknown",
              signed: ["Apple Development: Someone (HZWDHYHFKJ)"]),
    ])

    static func entry(name: String,
                      path: String,
                      version: String? = nil,
                      arch: String? = nil,
                      obtained: String? = nil,
                      signed: [String] = []) -> [String: Any] {
        var item: [String: Any] = ["_name": name, "path": path, "signed_by": signed]
        if let version { item["version"] = version }
        if let arch { item["arch_kind"] = arch }
        if let obtained { item["obtained_from"] = obtained }
        return item
    }

    static func json(_ items: [[String: Any]]) -> Data {
        // `try!` is right here: a fixture that will not serialise is a broken test, not a failure
        // worth reporting as a result.
        try! JSONSerialization.data(withJSONObject: ["SPApplicationsDataType": items])
    }

    /// One run over the fixture, with the disk left alone.
    static func read(_ data: Data? = nil,
                     handAdded: [URL] = [],
                     isCancelled: () -> Bool = { false },
                     progress: (InventoryReader.Progress) -> Void = { _ in })
        -> InventoryReader.Answer? {
        InventoryReader.read(report: data ?? report,
                             handAdded: handAdded,
                             measureSizes: false,
                             isCancelled: isCancelled,
                             progress: progress)
    }
}

// MARK: - 1. The three numbers, kept apart

@Suite struct InventoryCountsTests {

    /// ⭐ **The single most important expectation in this file.** Walking the file system finds 422
    /// bundles on the Mac this was written against; the number a person recognises is 31. A reader
    /// that folded macOS's own apps or Xcode's build products into the list would be wrong by a
    /// factor of three on the section's very first line, in the direction that sells cleaners.
    @Test func theThreeNumbersNeverBecomeOne() {
        let answer = Fixture.read()
        #expect(answer?.inventory.apps.count == 2)
        #expect(answer?.bundledWithMacOS.count == 2)
        #expect(answer?.inventory.otherBundles == 2)
    }

    /// The row's figure counts the person's apps and nothing else.
    @Test func theMeasureIsThePersonsAppsAlone() {
        let answer = Fixture.read()
        #expect(answer?.row.measure == "2 apps")
        #expect(answer?.row.headline.contains("2 apps") == true)
        // 6 is the total in the report, 4 is apps-plus-macOS. Neither may be the headline.
        #expect(answer?.row.headline.contains("6") == false)
        #expect(answer?.row.headline.contains("4 apps") == false)
    }

    /// The other two numbers are still said — on the row, not hidden. Saying only the flattering
    /// half is the failure mode this section is built against.
    @Test func theOtherTwoNumbersAreStillSaidOutLoud() {
        let reason = Fixture.read()?.row.reason ?? ""
        #expect(reason.contains("2 more come with macOS"))
        #expect(reason.contains("another 2 bundles here are components"))
    }

    /// A `DetailPair`'s identity is its label. Two pairs with one label is a duplicate id in the
    /// view that draws them, and the second one silently does not appear.
    @Test func noTwoDetailsShareALabel() {
        guard let answer = Fixture.read() else { return #expect(Bool(false)) }
        let labels = answer.row.details.map(\.label)
        #expect(Set(labels).count == labels.count)
    }

    /// One app reads as one app, not "1 apps".
    @Test func oneAppIsSingular() {
        #expect(InventoryReader.measure(1) == "1 app")
        #expect(InventoryReader.measure(0) == "0 apps")
        #expect(InventoryReader.headline(AppsInventory(apps: [Sample.chrome]))
            == "One app is installed.")
    }
}

// MARK: - 2. Which list an app is on

@Suite struct InventoryFolderTests {

    /// The four folders, decided by where macOS says the app is — never by walking them.
    @Test func theFoldersDecideWhichListNotWhatAnAppIs() {
        let folders = InventoryReader.Folders.standard
        #expect(folders.group(for: "/Applications/Firefox.app") == .mine)
        #expect(folders.group(for: "/Applications/Utilities/Something.app") == .mine)
        #expect(folders.group(for: "/System/Applications/Mail.app") == .macOS)
        #expect(folders.group(for: "/System/Applications/Utilities/Terminal.app") == .macOS)
        #expect(folders.group(for: "/System/Library/CoreServices/Finder.app") == nil)
        #expect(folders.group(for: "/Applications/Xcode.app/Contents/Applications/Instruments.app")
            == nil)
    }

    /// ⚠️ The home folder answers to two paths, and which one you get depends on who resolved it
    /// last. Compare one form against the other and `~/Applications` quietly stops matching.
    @Test func theHomeFolderIsRecognisedByBothItsNames() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folders = InventoryReader.Folders.standard
        #expect(folders.group(for: "\(home)/Applications/Thing.app") == .mine)
        #expect(folders.group(for: "/System/Volumes/Data\(home)/Applications/Thing.app") == .mine)
    }

    /// An app one folder deeper than a folder we list is not in that folder. `/Applications/Foo.app`
    /// is an app; `/Applications/Foo.app/Contents/Applications/Bar.app` is a helper inside it, and
    /// there are seven of those on this Mac.
    @Test func nestedHelpersAreNotApps() {
        let answer = Fixture.read()
        #expect(answer?.inventory.apps.contains { $0.name == "Bug Reporter" } == false)
    }
}

// MARK: - 3. Who signed it — and never a word about verifying it

@Suite struct InventorySignatureTests {

    /// The four certificate summaries this Mac actually produces.
    @Test func theCertificatesThisMacActuallyProduces() {
        #expect(InventoryReader.named("Apple") == .apple)
        #expect(InventoryReader.named("Google LLC") == .developer("Google LLC"))
        #expect(InventoryReader.named("The Document Foundation")
            == .developer("The Document Foundation"))
        #expect(InventoryReader.named("TestFlight Beta Distribution")
            == .developer("TestFlight Beta Distribution"))
    }

    /// The chain comes free in macOS's own report, leaf first, and the leaf is the only one that
    /// names anybody.
    @Test func theSignerComesFromTheReportWithoutTouchingTheDisk() {
        let google = InventoryReader.Entry(
            name: "Google Chrome",
            path: "/nowhere/Google Chrome.app",
            signedBy: ["Developer ID Application: Google LLC (EQHXZ8M8AV)",
                       "Developer ID Certification Authority"])
        #expect(InventoryReader.signature(of: google, at: URL(fileURLWithPath: google.path))
            == .developer("Google LLC"))
    }

    /// ⚠️ **"Apple Mac OS Application Signing" is not Apple the developer.** It is the receipt Apple
    /// staples onto a Mac App Store app; the publisher's name is nowhere in it. Reporting "Apple"
    /// for BBEdit would be wrong about who wrote the software.
    @Test func theMacAppStoreReceiptIsNotCreditedToApple() {
        let bbedit = InventoryReader.Entry(name: "BBEdit",
                                           path: "/nowhere/BBEdit.app",
                                           signedBy: ["Apple Mac OS Application Signing"])
        let signed = InventoryReader.signature(of: bbedit, at: URL(fileURLWithPath: bbedit.path))
        #expect(signed != .apple)
        #expect(signed.name?.contains("Mac App Store") == true)
    }

    /// ⚠️ **A bundle we could not read is not a bundle nobody signed.** `spctl` is banned and
    /// verification is never claimed, so the one thing this field must get right is the difference
    /// between "no signature" and "no answer".
    @Test func aSignatureWeCouldNotReadIsNotReportedAsUnsigned() {
        let missing = URL(fileURLWithPath: "/nowhere/at/all/Ghost.app")
        #expect(InventoryReader.signerFromDisk(at: missing) == .unreadable)

        let ghost = InventoryReader.Entry(name: "Ghost", path: missing.path)
        let signed = InventoryReader.signature(of: ghost, at: missing)
        #expect(signed == .unreadable(.notReported))
        #expect(signed.wasRead == false)
    }

    /// ⛔ **No label anywhere in this section may claim an app was verified, checked or found safe.**
    /// 11 of the 31 apps on this Mac fail full verification and not one has been tampered with; 8 of
    /// them fail because somebody added a Finder tag.
    @Test func nothingClaimsAnAppWasVerified() {
        let banned = ["verified", "valid signature", "trusted", "safe", "passed", "tamper"]
        guard let answer = Fixture.read() else { return #expect(Bool(false)) }

        var words = answer.row.facts
        words += answer.row.details.map { "\($0.label) \($0.value)" }
        words += answer.inventory.apps.flatMap(\.detailPairs).map { "\($0.label) \($0.value)" }
        words += answer.inventory.apps.map { $0.signedBy.label }

        for text in words.map({ $0.lowercased() }) {
            for word in banned {
                #expect(text.contains(word) == false, "\(text) claims \(word)")
            }
        }
    }
}

// MARK: - 4. Intel only is a fact, and never a warning

@Suite struct InventoryArchitectureTests {

    /// The five values `system_profiler` prints on this Mac, plus the iOS one.
    @Test func theArchitecturesMacOSReports() {
        let nowhere = URL(fileURLWithPath: "/nowhere/Thing.app")
        #expect(InventoryReader.architecture("arch_arm_i64", at: nowhere) == .universal)
        #expect(InventoryReader.architecture("arch_arm", at: nowhere) == .appleSilicon)
        #expect(InventoryReader.architecture("arch_i64", at: nowhere) == .intelOnly)
        #expect(InventoryReader.architecture("arch_i32", at: nowhere) == .intelOnly)
        // An iPhone app on an Apple silicon Mac. It will not run on an Intel Mac, which is exactly
        // and only what `.appleSilicon` says.
        #expect(InventoryReader.architecture("arch_ios", at: nowhere) == .appleSilicon)
    }

    /// ⚠️ **A word we do not know is not guessed at.** Picking one is how a universal app ends up
    /// labelled Intel on somebody's screen.
    @Test func anArchitectureWeCannotReadIsNotInvented() {
        let nowhere = URL(fileURLWithPath: "/nowhere/Thing.app")
        #expect(InventoryReader.architecture("arch_other", at: nowhere) == .unknown)
        #expect(InventoryReader.architecture(nil, at: nowhere) == .unknown)
    }

    /// ⚠️ **The ruling of 2026-08-27, held by a test so nobody "fixes" it.** An Intel-only app gets a
    /// plain labelled fact and nothing else: no countdown, no "will stop working", never a colour.
    /// macOS already warns at launch, nothing about Rosetta is a security matter, and only the
    /// developer can act.
    @Test func intelOnlyIsAPlainFactWithNoWarningAnywhereNearIt() {
        let intel = InstalledApp(name: "Old Thing",
                                 bundleID: "com.example.old",
                                 version: "1.0",
                                 architecture: .intelOnly)
        let inventory = AppsInventory(apps: [intel, Sample.chrome], otherBundles: 0)
        let row = InventoryReader.row(inventory: inventory)

        #expect(inventory.intelOnly.count == 1)
        #expect(row.severity == .information)
        #expect(row.status == .good)

        let pairs = intel.detailPairs
        #expect(pairs.contains { $0.label == "Built for" && $0.value == "Intel only" })

        let alarms = ["stop working", "will not work", "no longer", "before ", "deadline",
                      "unsupported", "problem", "risk"]
        let text = (row.facts + row.details.map(\.value) + pairs.map(\.value))
            .joined(separator: " ")
            .lowercased()
        for alarm in alarms {
            #expect(text.contains(alarm) == false, "the row says \(alarm) about an Intel app")
        }
    }
}

// MARK: - 5. Where an app came from

@Suite struct InventoryOriginTests {

    @Test func theOriginsMacOSCanTellUsApart() {
        #expect(InventoryReader.origin(of: .init(name: "Pages",
                                                 path: "/Applications/Pages.app",
                                                 obtainedFrom: "mac_app_store",
                                                 signedBy: ["Apple Mac OS Application Signing"]))
            == .appStore)
        #expect(InventoryReader.origin(of: .init(name: "Firefox",
                                                 path: "/Applications/Firefox.app",
                                                 obtainedFrom: "identified_developer",
                                                 signedBy: ["Developer ID Application: Mozilla"]))
            == .developerID)
        #expect(InventoryReader.origin(of: .init(name: "Mail",
                                                 path: "/System/Applications/Mail.app",
                                                 obtainedFrom: "apple",
                                                 signedBy: ["macOS Software Signing"]))
            == .bundledWithMacOS)
        #expect(InventoryReader.origin(of: .init(name: "Droplet",
                                                 path: "/Users/x/Applications/Droplet.app",
                                                 obtainedFrom: "unknown"))
            == .unsigned)
    }

    /// ⚠️ **A TestFlight build is `.unknown`, and that is the honest answer.** There are six cases
    /// and none of them is TestFlight. It is not the Mac App Store, which updates apps for you; it
    /// is not a Developer ID download; it is plainly not unsigned. macOS files it under
    /// `obtained_from: unknown` itself, and the signer line beside it says so in full. Six of the 31
    /// apps on this Mac are TestFlight builds, so this is not a corner.
    @Test func aTestFlightBuildIsNotCalledTheAppStore() {
        let beta = InventoryReader.Entry(name: "Lode",
                                         path: "/Applications/Lode.app",
                                         obtainedFrom: "unknown",
                                         signedBy: ["TestFlight Beta Distribution"])
        #expect(InventoryReader.origin(of: beta) == .unknown)
        #expect(InventoryReader.signature(of: beta, at: URL(fileURLWithPath: beta.path)).name
            == "TestFlight Beta Distribution")
    }

    /// An app Homebrew installed is updated by `brew upgrade` and by nothing else, which is a
    /// different answer to the update question than "from its maker" gives — so the receipt wins
    /// over the signature.
    @Test func homebrewWinsOverTheSignature() {
        let chrome = InventoryReader.Entry(name: "Google Chrome",
                                           path: "/Applications/Google Chrome.app",
                                           obtainedFrom: "identified_developer",
                                           signedBy: ["Developer ID Application: Google LLC"])
        #expect(InventoryReader.origin(of: chrome) == .developerID)
        #expect(InventoryReader.origin(of: chrome, homebrew: ["Google Chrome.app"]) == .homebrew)
    }

    /// Homebrew 4 moves the app out of the Caskroom and leaves a JSON receipt behind. The receipt is
    /// the only evidence left that Homebrew put it there.
    @Test func aHomebrewReceiptNamesTheAppItInstalled() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wellkept-caskroom-\(UUID().uuidString)")
        let casks = root.appendingPathComponent("visual-studio-code/.metadata/1.1/2026/Casks")
        try FileManager.default.createDirectory(at: casks, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let receipt = ["artifacts": [["app": ["Visual Studio Code.app"]],
                                     ["binary": ["code"]]]]
        try JSONSerialization.data(withJSONObject: receipt)
            .write(to: casks.appendingPathComponent("visual-studio-code.json"))

        #expect(InventoryReader.homebrewAppNames(caskrooms: [root])
            .contains("Visual Studio Code.app"))
    }

    /// A Caskroom that is not there is not an error, and it is not an empty answer worth reporting.
    /// Most Macs have no Homebrew at all.
    @Test func noHomebrewIsNotAFailure() {
        let nowhere = URL(fileURLWithPath: "/nowhere/Caskroom")
        #expect(InventoryReader.homebrewAppNames(caskrooms: [nowhere]).isEmpty)
    }
}

// MARK: - 6. Apps macOS does not list

@Suite struct InventoryHandAddedTests {

    /// Builds a bundle that stands in for Safari: an `Info.plist` and nothing else, which is all
    /// this reader opens.
    private func bundle(id: String, name: String, version: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wellkept-apps-\(UUID().uuidString)")
        let app = root.appendingPathComponent("\(name).app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"),
                                                withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": id,
                                   "CFBundleName": name,
                                   "CFBundleShortVersionString": version,
                                   "CFBundleVersion": "\(version).99"]
        try PropertyListSerialization
            .data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    /// ⚠️ **Safari is absent from macOS's own inventory** — a symlink into the Preboot Cryptex with
    /// restricted and hidden flags — and it is the 4th most-launched app on this Mac. Its
    /// `Info.plist` reads fine by path, so the only thing missing was the row.
    @Test func anAppMacOSDoesNotListIsAddedAndSaidOutLoud() throws {
        let safari = try bundle(id: "com.example.Safari", name: "Safari", version: "26.6.2")
        defer { try? FileManager.default.removeItem(at: safari.deletingLastPathComponent()) }

        guard let answer = Fixture.read(handAdded: [safari]) else { return #expect(Bool(false)) }
        let added = answer.inventory.addedByHand
        #expect(added.count == 1)
        #expect(added.first?.name == "Safari")
        #expect(added.first?.version == "26.6.2")
        #expect(added.first?.build == "26.6.2.99")
        #expect(added.first?.origin == .bundledWithMacOS)

        // ⚠️ Adding a row silently would be inventing one. The row says it, on the row.
        #expect(answer.row.headline.contains("Safari"))
        #expect(answer.row.headline.contains("by hand"))
        #expect(answer.row.details.contains { $0.label == "Added by hand" })
        // And the app's own panel says it too, wherever it is drawn.
        #expect(added.first?.detailPairs.contains { $0.label == "Listing" } == true)
    }

    /// If macOS starts listing Safari tomorrow, the row must stop claiming we added it. A hand-added
    /// count that is wrong is worse than no hand-added count.
    @Test func anAppMacOSDoesListIsNotClaimedAsHandAdded() throws {
        let app = try bundle(id: "com.example.Twice", name: "Twice", version: "2.0")
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }

        let report = Fixture.json([Fixture.entry(name: "Twice",
                                                 path: app.path,
                                                 version: "2.0",
                                                 arch: "arch_arm_i64",
                                                 obtained: "identified_developer")])
        // The bundle is in a temporary folder, so it is in neither list — which is the point: it is
        // counted once, wherever it lands, and never twice.
        let answer = InventoryReader.read(folders: .init(mine: [app.deletingLastPathComponent()],
                                                         macOS: []),
                                          report: report,
                                          handAdded: [app],
                                          measureSizes: false)
        #expect(answer?.inventory.apps.count == 1)
        #expect(answer?.inventory.addedByHand.isEmpty == true)
        #expect(answer?.row.headline.contains("by hand") == false)
    }

    /// A folder that is not there is not a row.
    @Test func anAppThatIsNotThereIsNotInvented() {
        #expect(InventoryReader.handAddedApp(at: URL(fileURLWithPath: "/nowhere/Ghost.app")) == nil)
    }

    /// ⚠️ **An iPhone app on an Apple silicon Mac has no `Contents` folder.** The real bundle is
    /// under `WrappedBundle`, and a reader that looks only in `Contents` gives it no identifier and
    /// no version — so it joins to nothing in the update, crash and leftover rows. `Wildbound.app`
    /// on this Mac is exactly that shape.
    @Test func aWrappedIPhoneAppStillHasAnIdentifier() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wellkept-wrapped-\(UUID().uuidString)")
        let app = root.appendingPathComponent("Wildbound.app")
        let wrapped = app.appendingPathComponent("WrappedBundle")
        try FileManager.default.createDirectory(at: wrapped, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let info: [String: Any] = ["CFBundleIdentifier": "com.example.wildbound",
                                   "CFBundleShortVersionString": "0.1.0"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: wrapped.appendingPathComponent("Info.plist"))

        let read = InventoryReader.app(from: .init(name: "Wildbound",
                                                   path: app.path,
                                                   version: "0.1.0",
                                                   architecture: "arch_ios",
                                                   obtainedFrom: "unknown"))
        #expect(read.bundleID == "com.example.wildbound")
        #expect(read.architecture == .appleSilicon)
    }
}

// MARK: - 7. Never report zero because we could not look

@Suite struct InventoryRefusalTests {

    /// ⚠️ A report that will not parse gives an unreadable row — **never "0 apps installed"**, which
    /// is the same sentence a Mac with nothing on it would produce.
    @Test func aReportThatWillNotParseIsAnUnreadableRowNotAnEmptyMac() {
        guard let answer = Fixture.read(Data("not json".utf8)) else { return #expect(Bool(false)) }
        #expect(answer.row.unreadable == .notReported)
        #expect(answer.row.measure == nil)
        #expect(answer.row.status == .notChecked)
        #expect(answer.inventory.apps.isEmpty)
        #expect(answer.inventory.otherBundles == nil)
    }

    /// ⚠️ **No permission on earth changes this answer, so there is no button and no caveat.**
    /// `.notPermitted` here would put a line on Overview that nobody could ever clear — the exact
    /// warning-nobody-can-clear this app exists to avoid.
    @Test func theUnreadableRowOffersNoButtonAndLeavesTheCheckComplete() {
        let row = InventoryReader.couldNotAsk
        #expect(row.remedy == nil)
        #expect(row.complete)
        #expect(row.unreadable?.mayOfferRemedy == false)
    }

    /// An empty report is a different answer from an unparseable one, and both are possible.
    @Test func anEmptyListIsAFactAndAnUnreadableOneIsNot() {
        #expect(InventoryReader.Entry.all(in: Fixture.json([]))?.isEmpty == true)
        #expect(InventoryReader.Entry.all(in: Data("{}".utf8)) == nil)
        #expect(InventoryReader.Entry.all(in: Data()) == nil)
    }

    /// An entry with no identifier, no version and no signature is a real app on this Mac — an
    /// Automator droplet in `~/Applications`. It gets a row, not a crash and not a dropped line.
    @Test func anAppWithNothingInItsPlistStillGetsARow() {
        let droplet = InventoryReader.Entry(name: "AppBackups",
                                            path: "/Users/x/Applications/AppBackups.app",
                                            obtainedFrom: "unknown")
        let app = InventoryReader.app(from: droplet)
        #expect(app.name == "AppBackups")
        #expect(app.bundleID == "/Users/x/Applications/AppBackups.app")
        #expect(app.version == nil)
        #expect(app.versionText == Unreadable.notReported.sentence)
        #expect(app.sizeText == nil)
    }
}

// MARK: - 8. Cancelling, and saying what it is doing

@Suite struct InventoryProgressTests {

    /// ⚠️ **A cancelled run is nothing at all — never a short list.** 17 apps on a Mac with 31 is not
    /// a shorter answer, it is a wrong one, and the first thing anybody would do with it is put
    /// "17 apps" on the screen.
    @Test func aCancelledRunReturnsNothingRatherThanAShortList() {
        #expect(Fixture.read(isCancelled: { true }) == nil)
    }

    /// Cancelled between apps, not only before the first one.
    @Test func cancellingPartWayThroughStillReturnsNothing() {
        var reads = 0
        let answer = Fixture.read(isCancelled: {
            reads += 1
            return reads > 3
        })
        #expect(answer == nil)
    }

    /// The read is about thirteen seconds, and a spinner over a blank panel for thirteen seconds is
    /// indistinguishable from a hang. Each phase says what it is doing, in words.
    @Test func everyPhaseSaysWhatItIsDoing() {
        var seen: [InventoryReader.Progress] = []
        _ = Fixture.read(progress: { seen.append($0) })

        #expect(seen.first?.stage == .askingMacOS)
        #expect(seen.contains { $0.stage == .readingEachApp })
        for step in seen {
            #expect(step.sentence.isEmpty == false)
            #expect(step.done <= step.total || step.total == 0)
        }
        // The last thing a person is told is that the last app is done.
        let reading = seen.filter { $0.stage == .readingEachApp }
        #expect(reading.last?.done == reading.last?.total)
        #expect(reading.last?.fraction == 1)
    }

    /// The first phase has nothing to count, and a bar that sits at zero for eight seconds and then
    /// jumps is worse than no bar.
    @Test func thePhaseWithNothingToCountDoesNotPretendToCount() {
        let asking = InventoryReader.Progress(stage: .askingMacOS)
        #expect(asking.fraction == nil)
        #expect(asking.sentence == InventoryReader.Stage.askingMacOS.sentence)
        #expect(asking.sentence.contains("0 of 0") == false)

        let reading = InventoryReader.Progress(stage: .readingEachApp, done: 3, total: 31)
        #expect(reading.sentence.contains("3 of 31"))
    }

    /// Three phases, in the order they run, each numbered for the count beside the spinner.
    @Test func theStagesAreNumberedInTheOrderTheyRun() {
        #expect(InventoryReader.Stage.count == 3)
        #expect(InventoryReader.Stage.askingMacOS.step == 1)
        #expect(InventoryReader.Stage.readingEachApp.step == 2)
        #expect(InventoryReader.Stage.measuringSizes.step == 3)
    }
}

// MARK: - 9. Sizes

@Suite struct InventorySizeTests {

    /// ⚠️ **The bundle, and nothing else.** Chrome's own folder is 5.8 MB; what it keeps in
    /// `~/Library` is about 5.9 GB, under a name matching neither the app nor its identifier. One
    /// number covering both would be a guess dressed as a fact, and it is the field a person reads
    /// as "delete this and get that back".
    @Test func aBundleIsWeighedAndNothingElseIs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wellkept-size-\(UUID().uuidString)")
        let app = root.appendingPathComponent("Thing.app/Contents")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 40_000).write(to: app.appendingPathComponent("payload"))
        defer { try? FileManager.default.removeItem(at: root) }

        let bytes = InventoryReader.bundleSize(of: root.appendingPathComponent("Thing.app"),
                                               isCancelled: { false })
        #expect((bytes ?? 0) >= 40_000)
    }

    /// ⚠️ **A size we did not measure is nil, never zero.** "0 bytes" beside an app is a fact about
    /// the app; nil is a fact about us, and `sizeText` drops it rather than printing a nought.
    @Test func aBundleWeDidNotWeighIsNotZeroBytes() {
        let unweighed = InstalledApp(name: "Thing", bundleID: "com.example.thing")
        #expect(unweighed.bytes == nil)
        #expect(unweighed.sizeText == nil)

        let answer = Fixture.read()   // measureSizes: false
        #expect(answer?.inventory.apps.allSatisfy { $0.bytes == nil } == true)
    }

    /// Cancelling in the middle of Xcode's 200,000 files stops, and says nothing about its size.
    @Test func aCancelledWalkReportsNoSizeAtAll() {
        #expect(InventoryReader.bundleSize(of: URL(fileURLWithPath: "/Applications"),
                                           isCancelled: { true }) == nil)
    }

    /// ⚠️ A bundle that is not there weighs nothing, and must not be said to weigh nothing. An
    /// enumerator over a missing folder sums to zero, and "0 bytes" beside an app is a claim about
    /// the app rather than about us.
    @Test func aBundleThatIsNotThereHasNoSizeRatherThanNoBytes() {
        #expect(InventoryReader.bundleSize(of: URL(fileURLWithPath: "/nowhere/Ghost.app"),
                                           isCancelled: { false }) == nil)
    }
}

// MARK: - 10. "Last opened" is a fact, never a finding

@Suite struct InventoryLastOpenedTests {

    /// ⚠️ macOS reports nothing at all for **6 of the 31 apps here — including Keynote and Teams,
    /// both demonstrably run**. A blank is harmless. "You have not opened this in two years" built
    /// on the same blank is an accusation that would be wrong six times out of thirty-one on a Mac
    /// where nothing is wrong.
    @Test func aBlankLastOpenedIsNeverTurnedIntoAnAccusation() {
        let never = InstalledApp(name: "Keynote",
                                 bundleID: "com.apple.iWork.Keynote",
                                 version: "15.3.1",
                                 lastOpenedAt: nil)
        let inventory = AppsInventory(apps: [never], otherBundles: 0)
        let row = InventoryReader.row(inventory: inventory)

        #expect(never.detailPairs.contains { $0.label == "Last opened" })
        let text = (row.facts + row.details.map(\.value)).joined(separator: " ").lowercased()
        for accusation in ["not opened", "never opened", "unused", "haven't", "have not used",
                           "abandoned"] {
            #expect(text.contains(accusation) == false, "the row says \(accusation)")
        }
    }

    /// Spotlight answers for a path that is there and says nothing for one that is not. Both are
    /// ordinary.
    @Test func spotlightIsAskedAndItsSilenceIsAccepted() {
        #expect(InventoryReader.lastOpened(at: "/nowhere/at/all/Ghost.app") == nil)
    }
}

// MARK: - 11. This Mac, asserting only the shape

@Suite struct InventoryLiveTests {

    /// The one test that reads the real machine. It asserts **nothing** about what is on it: a test
    /// that expects 31 apps fails on everybody else's Mac, and the fix somebody reaches for is to
    /// delete the test.
    ///
    /// What it is actually for is the day Apple changes the JSON. `system_profiler` is read-only,
    /// takes no permission and raises no dialog.
    @Test func theRealMacAnswersInTheShapeWeExpect() {
        guard let answer = InventoryReader.read(measureSizes: false) else {
            // A cancelled run inside a test is not a failure of the reader.
            return
        }
        guard answer.row.unreadable == nil else {
            // macOS declined this time. That is a real state and it is drawn as one.
            #expect(answer.inventory.apps.isEmpty)
            return
        }

        #expect(answer.inventory.apps.isEmpty == false)
        #expect(answer.row.severity == .information)
        #expect(answer.row.status == .good)
        #expect((answer.inventory.otherBundles ?? -1) >= 0)

        for app in answer.inventory.apps + answer.bundledWithMacOS {
            #expect(app.name.isEmpty == false)
            #expect(app.bundleID.isEmpty == false)
            #expect(app.update == .notChecked)      // the update reader has not run
            #expect(app.lineFacts.count == 3)       // three facts on a line, never eight
        }

        // Every app that comes with macOS says so, and none of them is on the person's list.
        #expect(answer.bundledWithMacOS.allSatisfy { $0.origin == .bundledWithMacOS })
        let mine = Set(answer.inventory.apps.map(\.bundleID))
        #expect(answer.bundledWithMacOS.contains { mine.contains($0.bundleID) } == false)
    }
}

// MARK: - Samples

private enum Sample {
    static let chrome = InstalledApp(name: "Google Chrome",
                                     bundleID: "com.google.Chrome",
                                     version: "152.0.7977.64",
                                     architecture: .universal,
                                     signedBy: .developer("Google LLC"),
                                     origin: .developerID)
}

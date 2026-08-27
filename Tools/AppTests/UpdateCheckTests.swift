import Foundation
import Testing
import WellkeptCore

//  UpdateCheckTests.swift
//  ViewShots — Tools/AppTests
//
//  ⭐ **The guards on the one thing in this app that leaves the Mac, and on the one comparison that
//  can embarrass it.**
//
//  Every case below is a real app measured on 2026-08-27. None of them is invented: each is a way a
//  plain `!=` tells somebody something untrue about software they are running perfectly well.
//
//  Nothing here touches the network. The reader is exercised with consent withheld, with apps that
//  never reach the storefront, and with the storefront's own JSON handed in as a fixture — which is
//  how the Pages guard is tested without asking Apple about anybody's apps.

// MARK: - ⭐ The comparison

@Suite struct VersionComparisonTests {

    /// **The measurement this whole file exists for.** Apple's storefront says Pages is 15.3 and the
    /// installed copy says 15.3.1. A plain "is it different" test calls it outdated and advises a
    /// downgrade — on three apps, on the measured Mac.
    @Test func installedAheadOfTheStorefrontIsCurrent() {
        let standing = VersionComparison.standing(installed: "15.3.1", current: "15.3")
        #expect(standing == .current)
        #expect(!standing.hasNewerVersion)
        #expect(standing.newerVersion == nil)
    }

    @Test func aGenuinelyNewerVersionIsReportedWithItsNumber() {
        let standing = VersionComparison.standing(installed: "15.3", current: "15.3.1")
        #expect(standing == .newerAvailable("15.3.1"))
        // The guard built into `UpdateStanding`: nothing can claim a newer version without naming it.
        #expect(standing.newerVersion == "15.3.1")
    }

    @Test func sameVersionIsCurrent() {
        #expect(VersionComparison.standing(installed: "26.6", current: "26.6") == .current)
        #expect(VersionComparison.standing(installed: "1.0", current: "1.0.0") == .current)
    }

    /// A zero-padded scheme compares against itself perfectly well — the refusal is about mixing
    /// schemes, not about padding.
    @Test func aPaddedSchemeComparesAgainstItself() {
        #expect(VersionComparison.compare(installed: "02.06.00.51", current: "02.06.00.51") == .same)
        #expect(VersionComparison.compare(installed: "02.06.00.51", current: "02.06.00.52") == .currentIsNewer)
    }

    /// ⚠️ Padded against unpadded is two different schemes wearing the same dots.
    @Test func paddedAgainstUnpaddedIsRefused() {
        let standing = VersionComparison.standing(installed: "02.06.00.51", current: "2.6.1")
        #expect(standing == .couldNotTell(.versionsNotComparable))
    }

    @Test func aDateAgainstAVersionIsRefused() {
        #expect(VersionComparison.compare(installed: "2026.08.27", current: "3.1") == .notComparable)
        #expect(VersionComparison.compare(installed: "20260827", current: "3.1") == .notComparable)
    }

    /// Two dates in the same shape are comparable, because they are the same scheme.
    @Test func twoDatesInTheSameShapeCompare() {
        #expect(VersionComparison.compare(installed: "2026.08.20", current: "2026.08.27") == .currentIsNewer)
    }

    @Test func anythingWithLettersOrSpacesIsRefused() {
        for pair in [("1.2.3-beta", "1.2.4"),
                     ("1.2.3 (4567)", "1.2.4"),
                     ("2.0rc1", "2.0"),
                     ("", "1.0"),
                     ("build-77", "build-78")] {
            #expect(VersionComparison.compare(installed: pair.0, current: pair.1) == .notComparable,
                    "\(pair.0) vs \(pair.1) must not be ranked")
        }
    }

    /// Identical strings are answerable whatever shape they are — checked before any parsing, and it
    /// is what rescues the date-versioned and padded apps from a permanent shrug.
    @Test func identicalStringsAreAlwaysComparable() {
        #expect(VersionComparison.compare(installed: "1.2.3 (4567)", current: "1.2.3 (4567)") == .same)
        #expect(VersionComparison.standing(installed: "2026-08-27", current: "2026-08-27") == .current)
    }

    @Test func componentCountsMoreThanOneApartAreRefused() {
        #expect(VersionComparison.compare(installed: "1", current: "1.2.3.4") == .notComparable)
        // One apart is ordinary — 15.3 against 15.3.1 is the Pages case.
        #expect(VersionComparison.compare(installed: "1.2", current: "1.2.3") == .currentIsNewer)
    }

    @Test func aMissingVersionIsNeverAnAnswer() {
        #expect(VersionComparison.standing(installed: nil, current: "1.0") == .couldNotTell(.versionsNotComparable))
        #expect(VersionComparison.standing(installed: "1.0", current: nil) == .couldNotTell(.versionsNotComparable))
    }

    @Test func aLeadingVIsDroppedButNothingElseIs() {
        #expect(VersionComparison.compare(installed: "v1.2.3", current: "1.2.4") == .currentIsNewer)
        #expect(VersionComparison.normalise(" 1.2.3 ") == "1.2.3")
        // Not a version prefix — "version" is a word, and dropping the v would leave "ersion".
        #expect(VersionComparison.parse("version") == nil)
    }

    /// ⭐ **The blanket rule, stated as a test.** Over every hazardous pair measured on this Mac,
    /// `.newerAvailable` may appear only where the published version is unambiguously greater.
    @Test func neverClaimsNewerWithoutAnUnambiguousComparison() {
        let hazards: [(installed: String, current: String)] = [
            ("15.3.1", "15.3"),        // Pages
            ("02.06.00.51", "2.6.1"),  // a padded scheme
            ("2026.08.27", "3.1"),     // a date
            ("1.2.3 (4567)", "1.2.4"), // a build number in the string
            ("4.51.191", "4.51.191"),  // Slack, current
            ("26.6", "26.6"),          // Xcode, current
        ]
        for pair in hazards {
            let standing = VersionComparison.standing(installed: pair.installed, current: pair.current)
            #expect(!standing.hasNewerVersion,
                    "\(pair.installed) against \(pair.current) must never read as out of date")
        }
    }
}

// MARK: - ⭐ Consent

@MainActor
@Suite struct UpdateConsentTests {

    /// A defaults store nobody else is using, so a test can never read or write the real answer —
    /// and it is thrown away afterwards rather than left behind on the Mac running the gate.
    ///
    /// A fresh suite per call because Swift Testing runs tests inside a suite concurrently: one
    /// shared name would have these four tests writing over each other.
    private func withStore(_ body: (UserDefaults) -> Void) {
        let name = "studio.stonemesa.wellkept.tests." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: name) else { return }
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }

    @Test func theKeyComesFromThePrivacyRegisterAndNotFromAStringLiteral() {
        #expect(UpdateConsent.key == Privacy.Departure.appUpdateCheck.settingsKey)
        #expect(UpdateConsent.key == "checkAppUpdates")
    }

    /// ⚠️ **The bug this prevents.** `UserDefaults.bool(forKey:)` returns `false` for a key nobody has
    /// written, which makes "we have not asked yet" indistinguishable from "you said no" — so the
    /// question never gets asked and the feature silently never works.
    @Test func anUnsetKeyIsNotAskedRatherThanDeclined() {
        withStore { defaults in
            #expect(UpdateConsent.read(from: defaults) == .notAsked)
            #expect(defaults.bool(forKey: UpdateConsent.key) == false)
            #expect(UpdateConsent.read(from: defaults) != .declined)
        }
    }

    @Test func bothAnswersSurviveARoundTrip() {
        withStore { defaults in
            UpdateConsent.write(.allowed, to: defaults)
            #expect(UpdateConsent.read(from: defaults) == .allowed)
            UpdateConsent.write(.declined, to: defaults)
            #expect(UpdateConsent.read(from: defaults) == .declined)
            UpdateConsent.write(.notAsked, to: defaults)
            #expect(UpdateConsent.read(from: defaults) == .notAsked)
            #expect((defaults.object(forKey: UpdateConsent.key) as? Bool) == nil)
        }
    }

    @Test func onlyAllowedIsAllowed() {
        #expect(UpdateConsent.Answer.allowed.isAllowed)
        #expect(!UpdateConsent.Answer.declined.isAllowed)
        #expect(!UpdateConsent.Answer.notAsked.isAllowed)
    }

    @Test func theStoreMirrorsTheKey() {
        withStore { defaults in
            let model = UpdateConsentStore(store: defaults)
            #expect(!model.hasBeenAsked)
            model.allow()
            #expect(model.isAllowed)
            #expect(model.hasBeenAsked)
            #expect(UpdateConsent.read(from: defaults) == .allowed)
            model.setAllowed(false)
            #expect(!model.isAllowed)
            #expect(model.hasBeenAsked)
            model.forget()
            #expect(!model.hasBeenAsked)
        }
    }

    /// The sheet quotes the register rather than writing its own privacy sentences — the failure
    /// that produced three drifting copies of "Nothing leaves your Mac" before 2026-08-27.
    @Test func theSheetQuotesTheRegister() {
        let lines = UpdateConsent.Words.registerLines
        #expect(lines.count == 2)
        let text = lines.map(\.value).joined(separator: " ")
        #expect(text.contains(Privacy.Departure.appUpdateCheck.whatLeaves))
        #expect(text.contains(Privacy.Departure.appUpdateCheck.cost))
    }

    @Test func theScopeLineNamesARealNumberOrIsLeftOut() {
        #expect(UpdateConsent.Words.scope(appCount: nil) == nil)
        #expect(UpdateConsent.Words.scope(appCount: 9)?.contains("9") == true)
        #expect(UpdateConsent.Words.scope(appCount: 1)?.contains("one app") == true)
        #expect(UpdateConsent.Words.scope(appCount: 0)?.contains("nothing would be sent") == true)
    }
}

// MARK: - ⭐ Apple's storefront, parsed from a fixture

@Suite struct AppStoreVersionsTests {

    /// The two records verified by hand on 2026-08-27: Xcode answers as a Mac app, and
    /// `com.apple.Pages` answers with the **iPhone** record for the same universal purchase.
    private let fixture = Data("""
    {"resultCount": 3, "results": [
      {"bundleId": "com.apple.dt.Xcode", "kind": "mac-software", "version": "26.6",
       "trackName": "Xcode", "currentVersionReleaseDate": "2026-06-25T21:59:17Z"},
      {"bundleId": "com.apple.Pages", "kind": "software", "version": "15.3",
       "trackName": "Pages: Create Documents"},
      {"bundleId": "com.tinyspeck.slackmacgap", "kind": "mac-software", "version": "4.51.191",
       "trackName": "Slack for Desktop"}
    ]}
    """.utf8)

    /// ⚠️ **The Pages guard.** A universal purchase answers with an iPhone record whose version
    /// belongs to a different piece of software; ranking a Mac build against it is the same bug in a
    /// better disguise.
    @Test func onlyMacRecordsCount() {
        let records = AppStoreVersions.records(fromJSON: fixture)
        #expect(records.count == 2)
        #expect(records["com.apple.pages"] == nil)
        #expect(records["com.apple.dt.xcode"]?.version == "26.6")
        #expect(records["com.tinyspeck.slackmacgap"]?.version == "4.51.191")
    }

    @Test func releaseDatesAreReadWhereTheyAreThere() {
        let records = AppStoreVersions.records(fromJSON: fixture)
        #expect(records["com.apple.dt.xcode"]?.releasedAt != nil)
    }

    @Test func rubbishIsNoAnswerRatherThanACrash() {
        #expect(AppStoreVersions.records(fromJSON: Data("not json".utf8)).isEmpty)
        #expect(AppStoreVersions.records(fromJSON: Data()).isEmpty)
        #expect(AppStoreVersions.records(fromJSON: Data(#"{"results": "nope"}"#.utf8)).isEmpty)
    }

    /// One request, comma-separated — verified against the real service on 2026-08-27, and the
    /// reason "one request" is true rather than aspirational.
    @Test func identifiersAreBatchedIntoOneQuery() {
        let url = AppStoreVersions.url(for: ["com.a.one", "com.b.two"], region: "GB")
        let text = url?.absoluteString ?? ""
        #expect(text.contains("com.a.one,com.b.two"))
        #expect(text.contains("country=GB"))
        // No entity parameter: with `entity=macSoftware` the storefront answers about the iPhone app
        // for a universal purchase. Fewer answers, no wrong ones.
        #expect(!text.contains("entity="))
        #expect(AppStoreVersions.url(for: [], region: "US") == nil)
    }

    @Test func theStorefrontIsTheUsersOwnRegion() {
        #expect(AppStoreVersions.region(locale: Locale(identifier: "en_GB")) == "GB")
        #expect(AppStoreVersions.region(locale: Locale(identifier: "fr_FR")) == "FR")
        // No region at all still has to produce something askable.
        #expect(AppStoreVersions.region(locale: Locale(identifier: "eo")) == "US")
    }

    /// The session carries nothing that could identify anybody.
    @Test func theSessionCarriesNoIdentity() {
        let session = AppStoreVersions.session()
        defer { session.finishTasksAndInvalidate() }
        let config = session.configuration
        #expect(config.httpCookieAcceptPolicy == .never)
        #expect(config.httpShouldSetCookies == false)
        #expect(config.urlCache == nil)
        #expect((config.httpAdditionalHeaders?["User-Agent"] as? String) == nil)
    }
}

// MARK: - ⭐ Homebrew, read from a file

@Suite struct HomebrewCaskTests {

    @Test func theCatalogueParsesFromAJWSEnvelope() {
        let payload = #"[{"token":"firefox","version":"142.0","artifacts":[{"app":["Firefox.app"]}]}]"#
        let envelope = try! JSONSerialization.data(withJSONObject: ["payload": payload])
        let records = HomebrewCasks.catalogue(fromJSON: envelope)
        #expect(records["firefox"]?.version == "142.0")
        #expect(records["firefox"]?.appNames == ["firefox"])
    }

    @Test func theCatalogueAlsoParsesFromABareArray() {
        let data = Data(#"[{"token":"iterm2","version":"3.5.0","artifacts":[{"app":["iTerm.app"]}]}]"#.utf8)
        #expect(HomebrewCasks.catalogue(fromJSON: data)["iterm2"]?.appNames == ["iterm"])
    }

    @Test func anUnknownShapeContributesNothingRatherThanAGuess() {
        #expect(HomebrewCasks.catalogue(fromJSON: Data("{}".utf8)).isEmpty)
        #expect(HomebrewCasks.appNames(inArtifacts: ["uninstall": "x"]).isEmpty)
        #expect(HomebrewCasks.appNames(inArtifacts: nil).isEmpty)
    }

    @Test func versionsCompareAndTheSentinelDoesNot() {
        #expect(HomebrewCasks.standing(installed: "1.2.3", current: "1.2.4") == .newerAvailable("1.2.4"))
        #expect(HomebrewCasks.standing(installed: "1.2.4", current: "1.2.4") == .current)
        #expect(HomebrewCasks.standing(installed: "1.2.5", current: "1.2.4") == .current)
        #expect(HomebrewCasks.standing(installed: "latest", current: "1.2.4")
                == .couldNotTell(.versionsNotComparable))
        #expect(HomebrewCasks.standing(installed: "1.2.4", current: nil)
                == .couldNotTell(.noSourceToAsk))
    }

    /// Homebrew writes some cask versions as `version,revision`. Both halves are ranked, in order,
    /// and a comma on one side only is two different schemes.
    @Test func theRevisionHalfOfACaskVersionIsRanked() {
        #expect(HomebrewCasks.standing(installed: "3.4.5,100", current: "3.4.5,101")
                == .newerAvailable("3.4.5,101"))
        #expect(HomebrewCasks.standing(installed: "3.4.5,101", current: "3.4.5,101") == .current)
        #expect(HomebrewCasks.standing(installed: "3.4.5", current: "3.4.5,101")
                == .couldNotTell(.versionsNotComparable))
    }

    /// ⚠️ A catalogue older than a month is not evidence about today, and reports nothing rather
    /// than something months behind.
    @Test func aStaleCatalogueAnswersNothing() {
        let installed = [HomebrewCasks.InstalledCask(token: "firefox", version: "140.0")]
        let catalogue = ["firefox": HomebrewCasks.CaskRecord(token: "firefox",
                                                             version: "142.0",
                                                             appNames: ["firefox"])]
        let stale = HomebrewCasks.standings(installed: installed, catalogue: catalogue, fresh: false)
        #expect(stale["firefox"] == .couldNotTell(.askFailed))

        let fresh = HomebrewCasks.standings(installed: installed, catalogue: catalogue, fresh: true)
        #expect(fresh["firefox"] == .newerAvailable("142.0"))
    }

    @Test func matchingIsOnTheAppNameWithoutItsExtension() {
        #expect(HomebrewCasks.matchKey("Visual Studio Code.app") == "visual studio code")
        #expect(HomebrewCasks.matchKey(" Firefox ") == "firefox")
    }

    /// Reading the real Mac must never throw or hang, whether or not Homebrew is installed here.
    @Test func readingThisMacIsSafeWhetherOrNotBrewIsHere() {
        let answer = HomebrewCasks.read()
        #expect(answer.caskCount >= 0)
    }
}

// MARK: - ⭐ macOS's own update state

@Suite struct MacOSUpdateStateTests {

    /// The three real key shapes from `/Library/Preferences/com.apple.SoftwareUpdate.plist` on this
    /// Mac, 2026-08-27.
    @Test func applesUpdateKeysDecode() {
        let minor = MacOSUpdateState.decode(updateKey: "MSU_UPDATE_25G83_patch_26.6.2_minor")
        #expect(minor.build == "25G83")
        #expect(minor.version == "26.6.2")
        #expect(!minor.isSecurityResponse)

        let response = MacOSUpdateState.decode(updateKey: "MSU_UPDATE_25D771280a_patch_26.3.1_rsr")
        #expect(response.build == "25D771280a")
        #expect(response.version == "26.3.1")
        #expect(response.isSecurityResponse)

        // The install dictionary is keyed with a bare build. Kept as a dated event rather than
        // dropped — a key we cannot decode is still a thing that happened.
        let bare = MacOSUpdateState.decode(updateKey: "25G83")
        #expect(bare.build == "25G83")
        #expect(bare.version == nil)
    }

    private var settings: [String: Any] {
        [
            "AutomaticDownload": true,
            "CriticalUpdateInstall": true,
            "ConfigDataInstall": true,
            "AutomaticallyInstallMacOSUpdates": true,
            "LastSuccessfulDate": Date(timeIntervalSince1970: 1_756_000_000),
            "FirstOfferDateDictionary": [
                "MSU_UPDATE_25G83_patch_26.6.2_minor": Date(timeIntervalSince1970: 1_755_000_000),
                "MSU_UPDATE_25G76_patch_26.6.1_minor": Date(timeIntervalSince1970: 1_754_000_000),
            ],
            "InstallDateDictionary": [
                "25G83": Date(timeIntervalSince1970: 1_755_500_000),
            ],
        ]
    }

    @Test func theSettingsAreReadAndAnAbsentKeyIsNotAGuess() {
        let state = MacOSUpdateState.make(settings: settings, managed: nil, systemVersion: nil)
        #expect(state.securityFixes == true)
        #expect(state.systemDataFiles == true)
        #expect(state.installsMacOSUpdates == true)
        // ⚠️ `AutomaticCheckEnabled` is absent on the measured Mac — macOS only writes it when
        // somebody changes it. Absent stays `nil`, and the row says this Mac does not say.
        #expect(state.automaticChecking == nil)
        #expect(!state.managed)
        #expect(state.unreadable == nil)
    }

    @Test func aProfileWins() {
        let state = MacOSUpdateState.make(settings: settings,
                                          managed: ["CriticalUpdateInstall": false],
                                          systemVersion: nil)
        #expect(state.securityFixes == false)
        #expect(state.managed)
    }

    @Test func theHistoryIsNewestFirstAndBorrowsTheVersionFromTheOffer() {
        let state = MacOSUpdateState.make(settings: settings, managed: nil, systemVersion: nil)
        #expect(state.history.count == 3)
        #expect(state.history.first?.date == Date(timeIntervalSince1970: 1_755_500_000))
        // The install dictionary knows only "25G83"; the version comes from the offer with the same
        // build, which is the only place it exists.
        let install = try! #require(state.installed.first)
        #expect(install.version == "26.6.2")
        #expect(install.name.contains("26.6.2"))
        #expect(state.offered.count == 2)
        #expect(state.installHistorySentence?.contains("one update") == true)
    }

    @Test func anUnreadableSettingsFileIsReportedRatherThanGuessedAt() {
        let state = MacOSUpdateState.make(settings: nil, managed: nil, systemVersion: nil)
        #expect(state.unreadable == .notReported)
        // ⚠️ `.notReported`, never `.notPermitted`: the file is world-readable, so no permission
        // exists that would have helped, and a caveat nobody can clear must not reach Overview.
        #expect(state.unreadable?.stillComplete == true)
        // The version still comes back, because it comes from somewhere else and is still true.
        #expect(state.productVersion != nil)
    }

    @Test func theVersionIsReadFromTheSystem() {
        let state = MacOSUpdateState.make(settings: settings,
                                          managed: nil,
                                          systemVersion: ["ProductVersion": "26.6.2",
                                                          "ProductBuildVersion": "25G83"])
        #expect(state.versionText == "macOS 26.6.2 (25G83)")
        #expect(state.headline == "This Mac is running macOS 26.6.2 (25G83).")
    }

    /// ⚠️ **The claim this type must never make.** Whether an update is waiting right now is only
    /// knowable by asking Apple, and nothing here asks. `RecommendedUpdates` — macOS's cached answer
    /// to its own last check — is deliberately not read.
    @Test func nothingHereClaimsAnUpdateIsWaiting() {
        let state = MacOSUpdateState.make(settings: settings, managed: nil, systemVersion: nil)
        let words = (state.detailPairs.map(\.value) + [state.headline]).joined(separator: " ").lowercased()
        for forbidden in ["update available", "updates available", "waiting", "out of date", "pending"] {
            #expect(!words.contains(forbidden), "the macOS row must not say \"\(forbidden)\"")
        }
        #expect(MacOSUpdateState.waitingCaveat.contains("Software Update"))
    }

    /// Reading the real Mac must never throw or hang.
    @Test func readingThisMacIsSafe() {
        let state = MacOSUpdateState.read()
        #expect(state.productVersion != nil)
    }
}

// MARK: - ⭐ The reader, with nothing leaving the Mac

@Suite struct UpdateReaderTests {

    private func app(_ name: String,
                     _ bundleID: String,
                     version: String? = "1.0",
                     signedBy: SignedBy = .unreadable(.notReported),
                     origin: AppOrigin = .developerID,
                     update: UpdateStanding = .notChecked,
                     addedByHand: Bool = false) -> InstalledApp {
        InstalledApp(name: name, bundleID: bundleID, version: version,
                     signedBy: signedBy, origin: origin, update: update, addedByHand: addedByHand)
    }

    /// ⚠️ **Six of the 31 apps on the measured Mac.** macOS files a TestFlight build under
    /// `obtained_from: unknown`, so `AppOrigin` cannot tell — the signature can, and it reads
    /// "TestFlight Beta Distribution". The storefront answers about the *shipping* version, which is
    /// a different piece of software, so comparing them would tell six people their beta is behind
    /// every time for ever.
    @Test func aTestFlightBuildIsRecognisedFromItsSignature() async {
        let beta = app("Some Beta", "studio.stonemesa.test.beta",
                       signedBy: .developer("TestFlight Beta Distribution"),
                       origin: .unknown)
        #expect(UpdateReader.isTestFlightBuild(beta))
        #expect(!UpdateReader.isTestFlightBuild(app("Ordinary", "studio.stonemesa.test.ordinary",
                                                    signedBy: .developer("Stone Mesa Studio, LLC"))))

        let result = await UpdateReader.read(apps: [beta], consent: .allowed)
        #expect(result.standings["studio.stonemesa.test.beta"] == .couldNotTell(.testFlightBuild))
        // Out of scope for coverage: it neither flatters the figure nor counts against it.
        #expect(!UpdateUnknown.testFlightBuild.isInScope)
    }

    /// ⭐ **The cost of "no", exactly as the privacy register already promised it.** Every row reads
    /// "Not checked", nothing is named to anybody, and the section still works.
    @Test func consentWithheldMeansEveryRowIsNotChecked() async {
        let apps = [app("Xcode", "com.apple.dt.Xcode", origin: .appStore),
                    app("Google Chrome", "com.google.Chrome"),
                    app("Safari", "com.apple.Safari", origin: .bundledWithMacOS, addedByHand: true)]

        for answer in [UpdateConsent.Answer.declined, .notAsked] {
            let result = await UpdateReader.read(apps: apps, consent: answer)
            #expect(result.standings.count == 3)
            #expect(result.standings.values.allSatisfy { $0 == .notChecked })
            #expect(result.namedToAppStore.isEmpty)
            #expect(result.disclosureSentence.contains("Nothing was sent"))
            // Nothing is checked and nothing is in scope, so the coverage pair says so rather than
            // implying we looked.
            let coverage = UpdateCoverage.measuring(apps.map { $0.withUpdate(.notChecked) })
            #expect(coverage.checked == 0)
            #expect(coverage.checkable == 0)
        }
    }

    /// With consent given but nothing here that the storefront could answer about, the reader makes
    /// no request at all — which is what makes this test safe to run in a gate with no network.
    @Test func theLocalSourcesAnswerWithoutAskingAnybody() async {
        let apps = [
            // Ships with macOS — answered by the macOS row, not repeated here.
            app("Safari", "com.apple.Safari", origin: .bundledWithMacOS, addedByHand: true),
            app("TextEdit", "com.apple.TextEdit", origin: .bundledWithMacOS),
            // On Wellkept's own short list of apps that update themselves.
            app("Google Chrome", "com.google.Chrome"),
            app("Visual Studio Code", "com.microsoft.VSCode"),
            // Nobody publishes a version for this one. The honest cost of the maker-list decision.
            app("Some Utility", "studio.stonemesa.wellkept.test.utility"),
            // Already decided by the inventory, which is the only thing that can see the bundle.
            app("A Beta", "studio.stonemesa.wellkept.test.beta",
                update: .couldNotTell(.testFlightBuild)),
        ]

        let result = await UpdateReader.read(apps: apps, consent: .allowed)

        #expect(result.standings["com.apple.Safari"] == .couldNotTell(.shipsWithMacOS))
        #expect(result.standings["com.apple.TextEdit"] == .couldNotTell(.shipsWithMacOS))
        #expect(result.standings["com.google.Chrome"] == .keepsItselfUpToDate)
        #expect(result.standings["com.microsoft.VSCode"] == .keepsItselfUpToDate)
        #expect(result.standings["studio.stonemesa.wellkept.test.utility"] == .couldNotTell(.noSourceToAsk))
        // ⚠️ Never overwritten. The reader cannot see a bundle on disk and so cannot recognise a
        // TestFlight build; the inventory can, and its answer stands.
        #expect(result.standings["studio.stonemesa.wellkept.test.beta"] == .couldNotTell(.testFlightBuild))

        #expect(result.namedToAppStore.isEmpty)
        #expect(result.disclosureSentence.contains("Nothing was sent"))
    }

    /// ⚠️ **"Keeps itself up to date" and "cannot be checked" are opposite messages**, and collapsing
    /// them makes a well-kept Mac look neglected. They are also counted differently: a self-updating
    /// app is in scope, was never compared, and is **not** one of the ones we could not check.
    ///
    /// Two apps here, one of each. The caveat is about one app, not two — and if this ever reads
    /// "2", Chrome is being reported as unknown on the summary line while its own row says the
    /// opposite four lines below.
    @Test func selfUpdatingIsNotTheSameAsUncheckable() async {
        let apps = [app("Google Chrome", "com.google.Chrome"),
                    app("Some Utility", "studio.stonemesa.wellkept.test.utility")]
        let result = await UpdateReader.read(apps: apps, consent: .allowed)

        let updated = apps.map { $0.withUpdate(result.standings[$0.bundleID] ?? .notChecked) }
        let coverage = UpdateCoverage.measuring(updated)
        #expect(coverage.checked == 0)
        #expect(coverage.checkable == 2)
        #expect(coverage.selfUpdating == 1)
        #expect(coverage.unchecked == 1)
        #expect(coverage.sentence.contains("the one app"))

        // And the sentence the section actually shows keeps the two apart, in both directions.
        let tally = UpdateTally.measuring(updated)
        #expect(tally.sentenceWithCoverage.contains("One app keeps itself up to date."))
        #expect(!tally.sentenceWithCoverage.contains("2 more apps could not be checked"))
    }

    /// The standings drop straight into the inventory, which is the whole point of keying them by
    /// bundle identifier.
    @Test func theStandingsApplyToAnInventory() async {
        let apps = [app("Google Chrome", "com.google.Chrome"),
                    app("Safari", "com.apple.Safari", origin: .bundledWithMacOS, addedByHand: true)]
        let result = await UpdateReader.read(apps: apps, consent: .allowed)
        let inventory = AppsInventory(apps: apps).applying(result.standings)
        #expect(inventory.app("com.google.Chrome")?.update == .keepsItselfUpToDate)
        #expect(inventory.tally.newerAvailable == 0)
    }

    /// What the section shows afterwards: the exact list of what was named, so the disclosure can be
    /// checked rather than taken on trust.
    @Test func theDisclosureNamesWhatLeft() {
        let none = UpdateReader.Answer(standings: [:], namedToAppStore: [],
                                       consent: .allowed, casksRead: 0)
        #expect(none.disclosureSentence.contains("Nothing was sent"))

        let one = UpdateReader.Answer(standings: [:], namedToAppStore: ["Xcode"],
                                      consent: .allowed, casksRead: 0)
        #expect(one.disclosureSentence.contains("one app"))
        #expect(one.disclosureSentence.contains("Xcode"))

        let several = UpdateReader.Answer(standings: [:],
                                          namedToAppStore: ["Keynote", "Slack", "Xcode"],
                                          consent: .allowed, casksRead: 0)
        #expect(several.disclosureSentence.contains("3 apps"))
        #expect(several.disclosureSentence.contains("Keynote"))
        #expect(several.disclosureSentence.contains("Xcode"))
    }
}

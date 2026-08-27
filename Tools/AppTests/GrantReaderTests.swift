// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import SQLite3
import Testing
import WellkeptCore

//  GrantReaderTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  **The screen that lists who can watch you, held to the two rules that stop it being an anxiety
//  machine.**
//
//  Almost every test here is about something *not* happening: a permission held is not coloured, a
//  helper that LaunchServices has never heard of is not declared missing, a changed signature on
//  the contacts list is not the concern that a changed signature on the camera is.
//
//  ⚠️ **These tests build their own TCC databases.** They have to: this Mac's real one needs Full
//  Disk Access, which no test runner has, so a suite that read the real store would be a suite that
//  is skipped on every machine it runs on. What is exercised against a real file is the thing that
//  matters most — the SQLite reader, against a database with Apple's schema, one with a different
//  schema, and one with no rows.
//
//  Everything is written to a fresh directory under the temporary folder and removed afterwards.
//  Nothing here reads or writes anything belonging to the person running it.

//  ⚠️ `Permission` is spelled out as `WellkeptCore.Permission` below: `App/Permissions.swift` owns
//  the bare name in this target, for the permission *this* app asks for.

@Suite struct GrantReaderTests {

    // MARK: - ⚠️ Full Disk Access refused: the whole screen, not part of it

    /// The rule this screen exists under. Eleven of the twelve permissions read exactly zero
    /// without the grant, so a partial list is not a partial list — it is Location on its own,
    /// surrounded by refusals, reading as "we checked and found almost nothing".
    @Test func aRefusedGrantCollapsesTheWholeScreenIncludingLocation() {
        let found = GrantReader.read(fullDiskAccess: false,
                                     sources: .machine,
                                     lookups: .refusingEverything)

        #expect(found.wasRefused)
        #expect(found.grants.isEmpty, "Location must be hidden too, not left standing alone")
        #expect(found.systemServicesUsingLocation == 0)
        #expect(found.row.unreadable == .notPermitted)
        #expect(found.row.status == .notChecked)
    }

    /// It is the one refusal a person can lift, so it is the one that carries a button and the one
    /// that marks the check incomplete.
    @Test func theRefusedRowCarriesTheButtonAndReportsItselfIncomplete() {
        let row = GrantReader.refusedRow()

        #expect(row.remedy != nil, "Full Disk Access is grantable — this row must offer the pane")
        #expect(row.remedy?.settingsPane == SystemSettingsPane.fullDiskAccess.rawValue)
        #expect(row.complete == false)
        #expect(row.measure == nil, "never a number for something we did not look at")
        #expect(row.concerns.isEmpty, "a row we could not read has found nothing, either way")
    }

    /// A fresh grant does not reach a running app, and somebody who taps Finish later, switches it
    /// on and comes back will otherwise conclude the app is broken. Named in SECURITY-QUESTIONS.md
    /// as a way of looking wrong while being right, so the row says it.
    @Test func theRefusedRowSaysAGrantNeedsARelaunch() {
        let values = GrantReader.refusedRow().details.map(\.value).joined(separator: " ")
        #expect(values.contains("already"), "the row must warn that a new grant needs a relaunch")
    }

    // MARK: - ⚠️ macOS 27 moves the store

    /// A schema we do not recognise says so. It does not crash, and — the part that matters — it
    /// does not come back with an empty list, which would read as good news.
    @Test func anUnrecognisedSchemaSaysSoRatherThanShowingNothing() throws {
        let folder = try TempFolder()
        let database = folder.url.appending(path: "TCC.db")
        #expect(Fixture.build(["CREATE TABLE access (thing TEXT, other TEXT)"], at: database))

        let found = GrantReader.read(fullDiskAccess: true,
                                     sources: folder.sources(user: database, system: database),
                                     lookups: .refusingEverything)

        #expect(found.grants.isEmpty)
        #expect(found.row.unreadable == .notReported)
        // ⚠️ `.notReported`, never `.notPermitted`. We already hold the only permission there is,
        // so there is no button and no caveat a person could ever clear.
        #expect(found.row.remedy == nil)
        #expect(found.row.complete, "an unclearable caveat on Overview is the thing to avoid")
    }

    /// A store that is not where it has always been is the same answer by a different route.
    @Test func aMissingStoreSaysSoRatherThanShowingNothing() throws {
        let folder = try TempFolder()
        let nowhere = folder.url.appending(path: "gone.db")

        let found = GrantReader.read(fullDiskAccess: true,
                                     sources: folder.sources(user: nowhere, system: nowhere),
                                     lookups: .refusingEverything)

        #expect(found.row.unreadable == .notReported)
        #expect(found.grants.isEmpty)
    }

    /// ⚠️ The subtle one. The right schema, zero rows — which cannot be true on a Mac that just
    /// demonstrated it holds Full Disk Access, because that grant is itself a row. Reporting "no
    /// app holds any permission" here is the most reassuring wrong answer this app can produce.
    @Test func anEmptyStoreIsTreatedAsChangedRatherThanAsGoodNews() throws {
        let folder = try TempFolder()
        let database = folder.url.appending(path: "TCC.db")
        #expect(Fixture.build([Fixture.schema], at: database))

        let found = GrantReader.read(fullDiskAccess: true,
                                     sources: folder.sources(user: database, system: database),
                                     lookups: .refusingEverything)

        #expect(found.row.unreadable == .notReported)
        #expect(found.row.headline.contains("Which apps"))
    }

    // MARK: - Reading a database that is the shape we know

    @Test func aRealShapedDatabaseYieldsTheGrantsInIt() throws {
        let folder = try TempFolder()
        let database = folder.url.appending(path: "TCC.db")
        #expect(Fixture.build([
            Fixture.schema,
            Fixture.grant("kTCCServiceCamera", "com.example.video"),
            Fixture.grant("kTCCServiceMicrophone", "com.example.video"),
            Fixture.grant("kTCCServiceScreenCapture", "com.example.share"),
        ], at: database))

        let scan = GrantReader.scan(database)
        #expect(scan.wasUnderstood)
        #expect(scan.rows.count == 3)

        var resolver = GrantReader.Resolver(lookups: .findingEverything, ourBundleID: "unrelated")
        let grants = GrantReader.tidy(resolver.grants(from: scan.rows))

        #expect(grants.count == 3)
        #expect(Set(grants.map(\.permission)) == [.camera, .microphone, .screenRecording])
        let allPresent = grants.allSatisfy(\.stillInstalled)
        let noneFlagged = grants.allSatisfy { $0.concern == nil }
        #expect(allPresent)
        #expect(noneFlagged, "holding a permission is not a finding")
        #expect(grants.first?.grantedAt != nil, "last_modified is read where the column is there")
    }

    /// ⚠️ A *denied* entry is a row in the same table. Listing it under "apps that hold the camera"
    /// would be true in the database and backwards on the screen.
    @Test func deniedAndUndecidedEntriesAreNotGrants() throws {
        let folder = try TempFolder()
        let database = folder.url.appending(path: "TCC.db")
        #expect(Fixture.build([
            Fixture.schema,
            Fixture.grant("kTCCServiceCamera", "com.example.refused", authValue: 0),
            Fixture.grant("kTCCServiceCamera", "com.example.unasked", authValue: 1),
            Fixture.grant("kTCCServiceCamera", "com.example.limited", authValue: 3),
        ], at: database))

        var resolver = GrantReader.Resolver(lookups: .findingEverything, ourBundleID: "unrelated")
        let grants = resolver.grants(from: GrantReader.scan(database).rows)

        #expect(grants.map(\.bundleID) == ["com.example.limited"],
                "only allowed (2) and allowed-but-limited (3) are grants")
    }

    /// Services outside the twelve are skipped rather than crammed into the nearest row. A
    /// thirteenth permission appearing because Apple shipped a new service is a change nobody
    /// agreed to.
    @Test func servicesOutsideTheTwelveAreIgnored() throws {
        let folder = try TempFolder()
        let database = folder.url.appending(path: "TCC.db")
        #expect(Fixture.build([
            Fixture.schema,
            Fixture.grant("kTCCServiceSystemPolicyDownloadsFolder", "com.example.a"),
            Fixture.grant("kTCCServiceBluetoothAlways", "com.example.b"),
        ], at: database))

        var resolver = GrantReader.Resolver(lookups: .findingEverything, ourBundleID: "unrelated")
        #expect(resolver.grants(from: GrantReader.scan(database).rows).isEmpty)
    }

    /// The reader asks both stores for every service rather than believing which one owns what.
    /// Screen recording has moved between them across releases.
    @Test func bothStoresAreAskedForEveryService() throws {
        let folder = try TempFolder()
        let user = folder.url.appending(path: "user.db")
        let system = folder.url.appending(path: "system.db")
        #expect(Fixture.build([Fixture.schema,
                               Fixture.grant("kTCCServiceCamera", "com.example.video")], at: user))
        #expect(Fixture.build([Fixture.schema,
                               Fixture.grant("kTCCServiceScreenCapture", "com.example.share")], at: system))

        let found = GrantReader.read(fullDiskAccess: true,
                                     sources: folder.sources(user: user, system: system),
                                     lookups: .findingEverything)

        #expect(Set(found.grants.map(\.permission)) == [.camera, .screenRecording])
    }

    /// One store gone and the other readable is still an answer — losing the whole row because one
    /// of two files moved would be throwing away what we did read. ⚠️ But half a list is stated as
    /// half a list: a silent half would take screen recording and control of this Mac off the
    /// screen with no word said, which is reporting zero because we could not look.
    @Test func oneReadableStoreIsEnoughAndSaysItIsOnlyHalf() throws {
        let folder = try TempFolder()
        let user = folder.url.appending(path: "user.db")
        #expect(Fixture.build([Fixture.schema,
                               Fixture.grant("kTCCServiceCamera", "com.example.video")], at: user))

        let found = GrantReader.read(fullDiskAccess: true,
                                     sources: folder.sources(user: user,
                                                             system: folder.url.appending(path: "gone.db")),
                                     lookups: .findingEverything)

        #expect(found.row.unreadable == nil)
        #expect(found.grants.count == 1)
        #expect(found.row.reason?.contains("not all of them") == true)
        #expect(found.row.details.contains { $0.label == "Part of the list is missing" })
    }

    /// And when both stores read, the caveat is not there — a warning on every healthy Mac is how
    /// an app teaches people to ignore its warnings.
    @Test func twoReadableStoresCarryNoCaveat() {
        let row = GrantReader.row(grants: [.stub("Zoom", "us.zoom.xos", .camera)])
        #expect(row.reason?.contains("not all of them") == false)
        #expect(row.details.allSatisfy { $0.label != "Part of the list is missing" })
    }

    /// A store that has dropped `csreq` still gives up the four columns that matter.
    @Test func aStoreMissingTheOptionalColumnsStillReads() throws {
        let folder = try TempFolder()
        let database = folder.url.appending(path: "TCC.db")
        #expect(Fixture.build([
            "CREATE TABLE access (service TEXT, client TEXT, client_type INTEGER, auth_value INTEGER)",
            "INSERT INTO access VALUES ('kTCCServiceCamera', 'com.example.video', 0, 2)",
        ], at: database))

        let scan = GrantReader.scan(database)
        #expect(scan.wasUnderstood)
        #expect(scan.rows.count == 1)
        #expect(scan.rows.first?.requirement == nil)
        #expect(scan.rows.first?.lastModified == nil)
    }

    // MARK: - ⚠️ "No longer installed" is claimed only where we are sure

    /// A path grant is easy: the file is there or it is not.
    @Test func aPathThatIsGoneIsCertainlyGone() {
        let placement = GrantReader.Resolver.place(.path("/Applications/Vanished.app/Contents/MacOS/Vanished"),
                                                   lookups: .refusingEverything)
        #expect(placement == .missing)
    }

    /// ⚠️ The false-accusation guard. LaunchServices registers applications; it does not register
    /// every helper tool and XPC service that holds a permission. "Never heard of it" is not
    /// "it was uninstalled", and concern 9 is amber.
    @Test func aHelperInsideAnInstalledAppIsNeverDeclaredMissing() {
        let lookups = GrantReader.Lookups.finding(["com.example.suite": "/Applications/Suite.app"])

        #expect(GrantReader.Resolver.place(.bundle("com.example.suite.helper"), lookups: lookups)
                == .uncertain)
        #expect(GrantReader.Resolver.place(.bundle("com.example.suite.helper.renderer"), lookups: lookups)
                == .uncertain)
    }

    /// This app does not accuse Apple's own daemons of being leftovers.
    @Test func applesOwnPlumbingIsNeverDeclaredMissing() {
        #expect(GrantReader.Resolver.place(.bundle("com.apple.mediaanalysisd"),
                                           lookups: .refusingEverything) == .uncertain)
    }

    /// And the case concern 9 exists for: a third-party identifier that nothing on this Mac claims,
    /// with no installed parent to explain it.
    @Test func anOrphanedThirdPartyIdentifierIsMissing() {
        #expect(GrantReader.Resolver.place(.bundle("com.example.deleted"),
                                           lookups: .refusingEverything) == .missing)
    }

    /// Uncertainty falls towards "installed", because the other direction is an amber accusation
    /// built on not knowing.
    @Test func uncertaintyNeverRaisesAConcern() {
        #expect(GrantReader.Placement.uncertain.stillInstalled)
        #expect(GrantReader.Placement.missing.stillInstalled == false)

        var resolver = GrantReader.Resolver(lookups: .refusingEverything, ourBundleID: "unrelated")
        let grant = resolver.grant(from: GrantReader.RawRow(service: "kTCCServiceCamera",
                                                            client: "com.apple.somedaemon",
                                                            clientType: 0,
                                                            authValue: 2,
                                                            requirement: nil,
                                                            lastModified: nil))
        #expect(grant?.concern == nil)
        #expect(resolver.unplaceable.contains("com.apple.somedaemon"))
    }

    // MARK: - ⚠️ Exactly two things go amber

    @Test func holdingAPermissionIsNotAFinding() {
        let row = GrantReader.row(grants: [
            .stub("Zoom", "us.zoom.xos", .camera),
            .stub("Zoom", "us.zoom.xos", .microphone),
            .stub("Screens", "com.edovia.screens", .screenRecording),
            .stub("Keyboard Maestro", "com.stairways.km", .accessibility),
            .stub("Karabiner", "org.pqrs.karabiner", .inputMonitoring),
        ])

        #expect(row.concerns.isEmpty)
        #expect(row.status == .good)
        #expect(row.severity == .information)
        #expect(row.measure == "4 apps")
    }

    /// Concern 8, and the boundary that keeps it from being a third condition: a changed signature
    /// is amber for the camera, the microphone and the screen — the three where the wrong software
    /// watching silently is the harm — and a plain fact everywhere else.
    @Test func aChangedSignatureIsAmberOnlyForTheThreeThatWatchYou() {
        let watching = GrantReader.row(grants: [.stub("Zoom", "us.zoom.xos", .camera, signature: .changed)])
        #expect(watching.concerns == [.signatureChangedSinceApproved])
        #expect(watching.status == .needsAttention)

        let notWatching = GrantReader.row(grants: [.stub("Zoom", "us.zoom.xos", .contacts, signature: .changed)])
        #expect(notWatching.concerns.isEmpty)
        #expect(notWatching.status == .good)
    }

    @Test func aPermissionHeldByAMissingAppIsAmber() {
        let row = GrantReader.row(grants: [
            .stub("com.example.deleted", "com.example.deleted", .screenRecording, installed: false),
        ])
        #expect(row.concerns == [.permissionHeldByMissingApp])
    }

    /// ⚠️ The severity cannot be reached any other way. Twelve apps holding everything, and the row
    /// is still Good — which is the whole difference between a health check and a scare.
    @Test func nothingElseCanColourThisRow() {
        let many = WellkeptCore.Permission.allCases.enumerated().map { index, permission in
            Grant.stub("App \(index)", "com.example.app\(index)", permission)
        }
        let row = GrantReader.row(grants: many)

        #expect(row.status == .good)
        #expect(row.severity == .information)
        #expect(row.measure == "12 apps")
    }

    /// The sentence that stops a list of twenty from reading as twenty problems.
    @Test func theReasonSaysThatHoldingAPermissionIsFine() {
        let reason = GrantReader.row(grants: [.stub("Zoom", "us.zoom.xos", .camera)]).reason ?? ""
        #expect(reason.contains("not a problem"))
    }

    // MARK: - Wellkept is in its own list

    /// An app that quietly removes itself from the list of apps that can read your disk has
    /// answered the question of whether to trust it.
    @Test func wellkeptListsItselfAndSaysSo() {
        let row = GrantReader.row(grants: [
            .stub("Wellkept", "studio.stonemesa.wellkept", .fullDiskAccess, isWellkept: true),
            .stub("Zoom", "us.zoom.xos", .camera),
        ])

        #expect(row.reason?.contains("Wellkept is on the list itself") == true)
        #expect(row.details.contains { $0.value.contains("Wellkept") })
    }

    @Test func ourOwnBundleIdentifierIsRecognised() {
        var resolver = GrantReader.Resolver(lookups: .findingEverything,
                                            ourBundleID: "studio.stonemesa.wellkept")
        let grant = resolver.grant(from: GrantReader.RawRow(service: "kTCCServiceSystemPolicyAllFiles",
                                                            client: "studio.stonemesa.wellkept",
                                                            clientType: 0,
                                                            authValue: 2,
                                                            requirement: nil,
                                                            lastModified: nil))
        #expect(grant?.isWellkept == true)
    }

    // MARK: - Location

    /// ⚠️ `clients.plist` records, per app, when it last received a location. Printing that would
    /// make a section about who is watching you into a thing that watches you. The set is the
    /// enforcement, not the promise.
    @Test func locationTimestampsAreNeverAmongTheFieldsWeRead() {
        #expect(GrantReader.locationFieldsRead == ["Authorized", "BundleId", "BundlePath"])

        for field in GrantReader.locationFieldsRead {
            #expect(!field.lowercased().contains("time"),
                    "\(field) looks like a last-used time — this row does not report those")
        }
    }

    /// Proven rather than promised: a client carrying every timestamp the real file carries comes
    /// back with none of them attached.
    @Test func aLocationGrantCarriesNoTimestamp() {
        let scan = GrantReader.locationGrants(from: [
            "uuid:icom.example.maps:": [
                "Authorized": true,
                "BundleId": "com.example.maps",
                "BundlePath": "/Applications/Maps.app",
                "LocationTimeStopped": Date(timeIntervalSince1970: 1_750_000_000),
                "ReceivingLocationInformationTimeStopped": Date(timeIntervalSince1970: 1_750_000_000),
            ],
        ], lookups: .findingEverything)

        #expect(scan.grants.count == 1)
        #expect(scan.grants.first?.grantedAt == nil)
        #expect(scan.grants.first?.permission == .location)
    }

    @Test func onlyAuthorisedClientsAreLocationGrants() {
        let scan = GrantReader.locationGrants(from: [
            "a": ["Authorized": true, "BundleId": "com.example.a", "BundlePath": "/Applications/A.app"],
            "b": ["Authorized": false, "BundleId": "com.example.b", "BundlePath": "/Applications/B.app"],
            "c": ["BundleId": "com.example.c", "BundlePath": "/Applications/C.app"],
        ], lookups: .findingEverything)

        #expect(scan.grants.map(\.bundleID) == ["com.example.a"])
    }

    /// macOS's own frameworks use location. They are real, they are not something anybody chose,
    /// and they are counted rather than listed beside a person's apps or dropped in silence.
    @Test func partsOfMacOSAreCountedNotListed() {
        let scan = GrantReader.locationGrants(from: [
            "a": ["Authorized": true, "BundleId": "com.example.a", "BundlePath": "/Applications/A.app"],
            "b": ["Authorized": true, "BundlePath": "/System/Library/PrivateFrameworks/PassKitCore.framework"],
            "c": ["Authorized": true, "BundlePath": "/System/Library/PrivateFrameworks/FindMyDevice.framework"],
        ], lookups: .findingEverything)

        #expect(scan.grants.count == 1)
        #expect(scan.systemServices == 2)

        let row = GrantReader.row(grants: scan.grants, systemServicesUsingLocation: scan.systemServices)
        #expect(row.details.contains { $0.label == "Location — parts of macOS" })
        #expect(row.concerns.isEmpty, "macOS using location is not a finding")
    }

    // MARK: - The list is stable and the labels are unique

    /// Two runs on an unchanged Mac must produce the same list in the same order. SQLite promises
    /// nothing about row order, and Apple Events writes one row per target app.
    @Test func theListIsDeduplicatedAndOrdered() {
        let jumbled: [Grant] = [
            .stub("Zoom", "us.zoom.xos", .microphone),
            .stub("Alfred", "com.runningwithcrayons.alfred", .accessibility),
            .stub("Zoom", "us.zoom.xos", .camera),
            .stub("Zoom", "us.zoom.xos", .camera),
            .stub("Beeper", "com.beeper.app", .camera),
        ]
        let tidied = GrantReader.tidy(jumbled)

        #expect(tidied.count == 4, "one app, one permission, one row")
        #expect(tidied.map(\.permission) == [.camera, .camera, .microphone, .accessibility])
        #expect(tidied.prefix(2).map(\.appName) == ["Beeper", "Zoom"])
        #expect(GrantReader.tidy(tidied) == tidied, "tidying twice changes nothing")
    }

    /// ⚠️ `DetailPair.id` is its label, so two pairs with the same label collide in a list and one
    /// silently does not draw. RestartReader learned this on a Mac in a boot loop.
    @Test func everyOptionsLabelIsUnique() {
        let row = GrantReader.row(
            grants: [
                .stub("Zoom", "us.zoom.xos", .camera, signature: .changed),
                .stub("Zoom", "us.zoom.helper", .microphone, signature: .changed),
                .stub("Ghost", "com.example.ghost", .screenRecording, installed: false),
                .stub("Ghost", "com.example.ghost2", .accessibility, installed: false),
                .stub("Wellkept", "studio.stonemesa.wellkept", .fullDiskAccess, isWellkept: true),
            ],
            unplaceable: ["com.apple.somedaemon"],
            systemServicesUsingLocation: 3)

        let labels = row.details.map(\.label)
        #expect(Set(labels).count == labels.count, "duplicate Options labels: \(labels)")
    }

    /// A long list is summarised, not unrolled. The full list is what the screen draws; Options
    /// carries the count.
    @Test func theOptionsRosterIsCapped() {
        let many = (0..<20).map { Grant.stub("App \($0)", "com.example.app\($0)", .camera) }
        let value = GrantReader.row(grants: many).details.first { $0.label == "Camera" }?.value ?? ""

        #expect(value.hasPrefix("20 apps — "))
        #expect(value.contains("and 12 more"))
    }

    // MARK: - Identity

    @Test func theClientTypeDecidesHowAnIdentityIsRead() {
        #expect(GrantReader.Identity(client: "com.example.a", clientType: 0) == .bundle("com.example.a"))
        #expect(GrantReader.Identity(client: "/usr/local/bin/tool", clientType: 1) == .path("/usr/local/bin/tool"))
        // An unknown type falls back to the shape of the string rather than to a guess.
        #expect(GrantReader.Identity(client: "/usr/local/bin/tool", clientType: 9) == .path("/usr/local/bin/tool"))
        #expect(GrantReader.Identity(client: "com.example.a", clientType: 9) == .bundle("com.example.a"))
    }

    /// The signature check wants the bundle, not the executable inside it: a requirement written
    /// for the bundle fails against the inner binary for a reason that has nothing to do with the
    /// app having changed.
    @Test func theEnclosingAppBundleIsFound() {
        // Compared as paths: walking up produces a directory-flavoured URL, which spells the same
        // place with a trailing slash. Harmless everywhere it is used, and not worth a URL equality
        // test that would fail on the punctuation.
        #expect(GrantReader.Resolver.bundle(containing: URL(filePath: "/Applications/Zoom.app/Contents/MacOS/zoom.us"))
                .path == "/Applications/Zoom.app")
        #expect(GrantReader.Resolver.bundle(containing: URL(filePath: "/usr/local/bin/tool"))
                .path == "/usr/local/bin/tool")
    }

    // MARK: - The vocabulary this row is allowed to reach

    /// Every service we map must land on one of the twelve, and the three that raise concern 8 must
    /// still be the three that watch you.
    @Test func theServiceMapStaysInsideTheTwelve() {
        let mapped = Set(GrantReader.Resolver.permissions.values)
        #expect(mapped.isSubset(of: Set(WellkeptCore.Permission.allCases)))
        #expect(mapped.count == GrantReader.Resolver.permissions.count, "two services, one permission")

        let watching = Set(WellkeptCore.Permission.allCases.filter(\.watchesYou))
        #expect(watching == [.camera, .microphone, .screenRecording])
    }
}

// MARK: - Fixtures

private extension Grant {
    /// A grant with only the fields a row-building test cares about.
    static func stub(_ name: String,
                     _ bundleID: String,
                     _ permission: WellkeptCore.Permission,
                     installed: Bool = true,
                     signature: SignatureStanding = .unknown,
                     isWellkept: Bool = false) -> Grant {
        Grant(appName: name,
              bundleID: bundleID,
              permission: permission,
              stillInstalled: installed,
              signature: signature,
              grantedAt: nil,
              isWellkept: isWellkept)
    }
}

private extension GrantReader.Lookups {

    /// LaunchServices knows nothing and no file exists — the shape a test wants when it is checking
    /// what happens with no machine underneath.
    static let refusingEverything = GrantReader.Lookups(
        applicationURL: { _ in nil },
        signature: { _, _ in .unknown },
        fileExists: { _ in false }
    )

    /// Everything resolves to a plausible place and nothing is ever accused.
    static let findingEverything = GrantReader.Lookups(
        applicationURL: { URL(filePath: "/Applications/\($0).app") },
        signature: { _, _ in .matches },
        fileExists: { _ in true }
    )

    /// LaunchServices knows exactly these bundle identifiers.
    static func finding(_ known: [String: String]) -> GrantReader.Lookups {
        GrantReader.Lookups(
            applicationURL: { known[$0].map { URL(filePath: $0) } },
            signature: { _, _ in .matches },
            fileExists: { _ in false }
        )
    }
}

/// A directory of our own, removed when the test finishes. Nothing outside it is ever touched.
private struct TempFolder: ~Copyable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "wellkept-grants-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func sources(user: URL, system: URL) -> GrantReader.Sources {
        GrantReader.Sources(userDatabase: user,
                            systemDatabase: system,
                            // A path inside our own folder that does not exist, so no test ever
                            // reads this Mac's real location file by accident.
                            locationClients: url.appending(path: "no-clients.plist"),
                            ourBundleID: "studio.stonemesa.wellkept")
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}

/// Builds a TCC-shaped database, so the SQLite reader is exercised against a real file.
private enum Fixture {

    /// Apple's schema, cut down to the columns this reader names. The order matters: `grant(_:_:)`
    /// below inserts positionally.
    static let schema = """
        CREATE TABLE access (
            service TEXT NOT NULL,
            client TEXT NOT NULL,
            client_type INTEGER NOT NULL,
            auth_value INTEGER NOT NULL,
            csreq BLOB,
            last_modified INTEGER
        )
        """

    /// One row. `auth_value` 2 is allowed, which is what most of these want.
    static func grant(_ service: String,
                      _ client: String,
                      clientType: Int = 0,
                      authValue: Int = 2,
                      lastModified: Int = 1_750_000_000) -> String {
        "INSERT INTO access VALUES ('\(service)', '\(client)', \(clientType), \(authValue), "
      + "NULL, \(lastModified))"
    }

    /// One statement at a time, prepared and stepped. No string is ever built from anything but the
    /// literals above.
    static func build(_ statements: [String], at url: URL) -> Bool {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let database
        else { sqlite3_close(database); return false }
        defer { sqlite3_close(database) }

        for sql in statements {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                sqlite3_finalize(statement)
                return false
            }
            let step = sqlite3_step(statement)
            sqlite3_finalize(statement)
            guard step == SQLITE_DONE else { return false }
        }
        return true
    }
}

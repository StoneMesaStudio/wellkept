// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import WellkeptCore

//  LeftoverReaderTests.swift
//  ViewShots — the bundle that compiles the app target
//
//  ⭐ **Every test here is a folder on a real Mac that a name-matching cleaner would have offered to
//  delete.**
//
//  This is the screen where being wrong costs somebody their work. So the suite is written the other
//  way round from a normal one: most of it proves that something is **not** reported. Three of them
//  name the actual traps measured on 2026-08-27 — the owner's PHP installation, an ad blocker that
//  is installed and running, and Chrome's updater.
//
//  Nothing here reads this Mac except the two live tests at the end, which assert shape and not
//  contents.

private func candidate(_ identifier: String,
                       _ place: LeftoverReader.Place,
                       bytes: Int64? = 1_000) -> LeftoverReader.Candidate {
    LeftoverReader.Candidate(identifier: identifier,
                             place: place,
                             path: "/Users/x/Library/\(place.directory)/\(identifier)",
                             bytes: bytes)
}

/// The measured Mac's Applications folder, as far as these tests need it.
private let installed: Set<String> = [
    "com.google.Chrome",        // and its updater is com.google.Keystone.Agent
    "com.khanov.BlockerX",      // 1Blocker, with ten extensions under it
    "com.apple.Safari",
    "com.microsoft.teams2",
]

private func noAppRegistered(_: String) -> Bool { false }

// MARK: - ⭐ The three traps

@Suite struct LeftoverTrapTests {

    /// ⚠️ **The trap that defines the file.** `~/Library/Application Support/Herd` has no app, no
    /// Spotlight entry, and is the owner's PHP and Composer. It is safe because "Herd" is not a
    /// bundle identifier — and that is the rule, not luck.
    @Test func aFolderNamedAfterAProductIsNeverEvidence() {
        for name in ["Herd", "Google", "Adobe", "Firefox", "MobileSync"] {
            #expect(!LeftoverReader.isBundleIdentifier(name), "\(name) is not an identifier")
            #expect(LeftoverReader.guarded(name,
                                           appsOnThisMac: installed,
                                           runningBundleIDs: [],
                                           isRegistered: noAppRegistered) == .notAnIdentifier)
        }
    }

    /// ⚠️ **Six "orphaned browser profiles" on this Mac belong to 1Blocker, which is installed and
    /// working.** They are filed under the app's identifier plus a suffix.
    @Test func anExtensionOfAnInstalledAppIsNotAnOrphan() {
        for extensionID in ["com.khanov.BlockerX.MacWebExtension",
                            "com.khanov.BlockerX.SafariExtension",
                            "com.khanov.BlockerX.MacBlockTrackersExtension"] {
            #expect(LeftoverReader.guarded(extensionID,
                                           appsOnThisMac: installed,
                                           runningBundleIDs: [],
                                           isRegistered: noAppRegistered)
                    == .partOfAnAppThatIsStillHere)
        }
    }

    /// ⚠️ **Chrome's updater is `com.google.Keystone.Agent`, and Chrome is `com.google.Chrome`.**
    /// The prefix rule does not catch it. Only the publisher rule stands between that folder and a
    /// Chrome that quietly stops updating.
    @Test func anUpdaterFromTheSameMakerIsLeftAlone() {
        #expect(LeftoverReader.guarded("com.google.Keystone.Agent",
                                       appsOnThisMac: installed,
                                       runningBundleIDs: [],
                                       isRegistered: noAppRegistered)
                == .sameMakerAsAnInstalledApp)
        #expect(LeftoverReader.guarded("com.google.GoogleUpdater",
                                       appsOnThisMac: installed,
                                       runningBundleIDs: [],
                                       isRegistered: noAppRegistered)
                == .sameMakerAsAnInstalledApp)
    }
}

// MARK: - The rest of the guards

@Suite struct LeftoverGuardTests {

    @Test func macOSsOwnFoldersAreLeftAlone() {
        #expect(LeftoverReader.guarded("com.apple.SafariTechnologyPreview",
                                       appsOnThisMac: installed,
                                       runningBundleIDs: [],
                                       isRegistered: noAppRegistered) == .macOSOwnsIt)
    }

    /// ⚠️ Group containers are shared. One folder can hold data for four apps of which three are
    /// installed, so Wellkept does not reason about them at all.
    @Test func sharedContainersAreNeverTouched() {
        for shared in ["group.com.apple.notes",
                       "systemgroup.com.apple.configurationprofiles",
                       "UBF8T346G9.com.microsoft.oneauth",
                       "EQHXZ8M8AV.group.com.google.drivefs"] {
            #expect(LeftoverReader.guarded(shared,
                                           appsOnThisMac: installed,
                                           runningBundleIDs: [],
                                           isRegistered: noAppRegistered) == .sharedBetweenApps)
        }
    }

    @Test func aTeamIdentifierIsTenCharactersOfUpperCaseAndDigits() {
        #expect(LeftoverReader.hasTeamPrefix("UBF8T346G9.com.microsoft.teams"))
        #expect(LeftoverReader.hasTeamPrefix("243LU875E5.groups.com.apple.podcasts"))
        #expect(!LeftoverReader.hasTeamPrefix("com.google.Chrome"))
        #expect(!LeftoverReader.hasTeamPrefix("de.beyondco.herd"))
    }

    @Test func anInstalledAppIsNotALeftover() {
        #expect(LeftoverReader.guarded("com.google.Chrome",
                                       appsOnThisMac: installed,
                                       runningBundleIDs: [],
                                       isRegistered: noAppRegistered) == .theAppIsStillHere)
    }

    /// ⚠️ **macOS's own register knows about apps outside the four folders the inventory walks.**
    /// Chrome's updater lives inside Application Support and is a real, installed app.
    @Test func launchServicesCanOverruleTheInventory() {
        #expect(LeftoverReader.guarded("net.example.hidden",
                                       appsOnThisMac: installed,
                                       runningBundleIDs: [],
                                       isRegistered: { _ in true }) == .theAppIsStillHere)
    }

    @Test func somethingRunningRightNowIsNotDead() {
        #expect(LeftoverReader.guarded("net.example.helper",
                                       appsOnThisMac: installed,
                                       runningBundleIDs: ["net.example.helper"],
                                       isRegistered: noAppRegistered) == .somethingIsRunningIt)
    }

    /// The one that survives every guard: a removed app, from a maker with nothing else installed.
    @Test func aGenuinelyRemovedAppSurvives() {
        #expect(LeftoverReader.guarded("com.operasoftware.Opera",
                                       appsOnThisMac: installed,
                                       runningBundleIDs: [],
                                       isRegistered: noAppRegistered) == nil)
    }

    /// Two parts is a namespace, not an app. "org.swift" and "wb.tests" are not app identifiers.
    @Test func threePartsAreRequired() {
        #expect(!LeftoverReader.isBundleIdentifier("org.swift"))
        #expect(!LeftoverReader.isBundleIdentifier("beyondco.herd"))
        #expect(LeftoverReader.isBundleIdentifier("de.beyondco.herd"))
        #expect(LeftoverReader.isBundleIdentifier("com.samuellaska.AdBuster.Blocker"))
        #expect(!LeftoverReader.isBundleIdentifier("com..broken"))
        #expect(!LeftoverReader.isBundleIdentifier("Adobe Photoshop 2024"))
    }
}

// MARK: - ⭐ Was it ever an app at all

@Suite struct LeftoverEvidenceTests {

    /// ⚠️ **A preferences file proves nothing.** Any shell script can write one. On the measured Mac
    /// this single rule removed CUPS's printing settings, Swift Package Manager's cache and twelve
    /// throwaway test containers.
    @Test func settingsAndCachesAloneAreNotProofAnAppWasHere() {
        let onlyWeakPlaces = [
            candidate("org.cups.PrintingPrefs", .preferences),
            candidate("org.swift.swiftpm", .caches),
            candidate("com.test.backupprefs", .preferences),
        ]
        let (leftovers, unproven) = LeftoverReader.gather(onlyWeakPlaces)
        #expect(leftovers.isEmpty)
        #expect(unproven == 3)
    }

    @Test func onlyFourPlacesAreMadeByMacOSForAnApp() {
        let proving = LeftoverReader.Place.allCases.filter(\.provesAnAppWasHere)
        #expect(proving == [.containers, .savedApplicationState, .applicationSupport, .webKit])
    }

    /// Once one strong place proves an app was here, everything filed under it is listed — including
    /// the settings and caches that were not proof on their own.
    @Test func onceProvenTheWeakPlacesAreListedToo() {
        let group = [
            candidate("de.beyondco.herd", .webKit, bytes: 4_000),
            candidate("de.beyondco.herd", .preferences, bytes: 500),
            candidate("de.beyondco.herd", .caches, bytes: 20_000),
        ]
        let (leftovers, unproven) = LeftoverReader.gather(group)
        #expect(unproven == 0)
        #expect(leftovers.count == 1)
        #expect(leftovers[0].paths.count == 3)
        #expect(leftovers[0].bytes == 24_500)
    }

    /// ⚠️ **Eight sandbox folders for eight Safari extensions are one removed app, not eight.** A
    /// screen with eight rows for one thing somebody deleted once looks like an infestation.
    @Test func extensionsCollapseIntoTheAppTheyBelongedTo() {
        let group = (1...8).map {
            candidate("com.samuellaska.AdBuster.Ext\($0)", .containers, bytes: 100)
        }
        let (leftovers, _) = LeftoverReader.gather(group)
        #expect(leftovers.count == 1)
        #expect(leftovers[0].bundleID == "com.samuellaska.AdBuster")
        #expect(leftovers[0].paths.count == 8)
    }

    @Test func theAppIdentifierIsTheFirstThreeParts() {
        #expect(LeftoverReader.appIdentifier(of: "com.samuellaska.AdBuster.Blocker")
                == "com.samuellaska.AdBuster")
        #expect(LeftoverReader.appIdentifier(of: "de.beyondco.herd") == "de.beyondco.herd")
    }

    /// ⚠️ **A partial size is worse than no size.** A walk turned away part-way returns less than the
    /// truth, and less than the truth reads exactly like a measurement.
    @Test func onePathWeCouldNotWeighLosesTheWholeFigure() {
        let group = [
            candidate("com.gone.App", .containers, bytes: 5_000),
            candidate("com.gone.App", .caches, bytes: nil),
        ]
        let (leftovers, _) = LeftoverReader.gather(group)
        #expect(leftovers.count == 1)
        #expect(leftovers[0].bytes == nil)
        #expect(leftovers[0].sizeText == nil)
    }

    /// The name comes from the identifier, and the row says so — the app's own name went with the
    /// app.
    @Test func theNameIsBuiltFromTheIdentifierAndAdmitsIt() {
        #expect(LeftoverReader.displayName(for: "co.magiclasso.MagicLassoMacApp")
                == "Magic Lasso Mac App")
        #expect(LeftoverReader.displayName(for: "com.operasoftware.Opera") == "Opera")
        #expect(LeftoverReader.displayName(for: "de.beyondco.herd") == "herd")

        let reason = LeftoverReader.reason(for: "com.operasoftware.Opera", places: [.applicationSupport])
        #expect(reason.contains("com.operasoftware.Opera"))
        #expect(reason.contains("the app's own name went with the app"))
    }

    /// Every leftover carries why we believe the app is gone. A flagged item with no reason is an
    /// accusation.
    @Test func everyLeftoverSaysWhyWeThinkTheAppIsGone() {
        let (leftovers, _) = LeftoverReader.gather([candidate("com.gone.App", .containers)])
        #expect(leftovers.count == 1)
        #expect(!leftovers[0].reason.isEmpty)
        #expect(leftovers[0].reason.contains("no app with the identifier"))
    }
}

// MARK: - The row

@Suite struct LeftoverRowTests {

    static func survey() -> LeftoverReader.Survey {
        LeftoverReader.Survey(candidates: [
            // Kept: two genuinely removed apps.
            candidate("com.operasoftware.Opera", .applicationSupport, bytes: 285),
            candidate("co.magiclasso.MagicLassoMacApp.WebExtension", .containers, bytes: 994),
            candidate("co.magiclasso.MagicLassoMacApp.ShareExtension", .containers, bytes: 512),
            // Set aside, one per guard that fires on the measured Mac.
            candidate("com.khanov.BlockerX.MacWebExtension", .containers),
            candidate("com.google.Keystone.Agent", .preferences),
            candidate("com.apple.Safari", .caches),
            candidate("group.com.apple.notes", .applicationSupport),
            // Never an app: a preferences file on its own.
            candidate("org.cups.PrintingPrefs", .preferences),
        ], notIdentifiers: 143)
    }

    static func answer() -> LeftoverReader.Answer {
        LeftoverReader.answer(from: survey(),
                              appsOnThisMac: installed,
                              runningBundleIDs: [],
                              isRegistered: noAppRegistered)
    }

    @Test func twoRemovedAppsAreFoundAndTheRestAreLeftAlone() {
        let answer = Self.answer()
        #expect(answer.leftovers.count == 2)
        #expect(Set(answer.leftovers.map(\.bundleID))
                == ["com.operasoftware.Opera", "co.magiclasso.MagicLassoMacApp"])
        #expect(answer.row.headline == "2 apps are gone and left something behind.")
    }

    /// ⚠️ **The ruling this whole file is built on: the measure is a count of apps, never a size.**
    /// "Reclaim 7.6 GB" is the cleaner's headline, and on the measured Mac it is wrong by a factor
    /// of twenty.
    @Test func theMeasureIsAppsAndNeverBytes() {
        let answer = Self.answer()
        #expect(answer.row.measure == "2 apps")
        for unit in ["GB", "MB", "KB", "bytes"] {
            #expect(answer.row.measure?.contains(unit) != true, "no size in the measure: \(unit)")
        }
    }

    /// ⚠️ **There is no section-wide total anywhere.** Each app's size is its own; adding them up
    /// would be a guess, because an app's real footprint often sits in a folder named after the
    /// company rather than the app.
    @Test func thereIsNoTotalAnywhereOnTheRow() {
        let answer = Self.answer()
        let noTotal = answer.row.details.first { $0.label == "No total" }
        #expect(noTotal != nil)
        #expect(answer.leftovers.allSatisfy { $0.bytes != nil })
        // Each carries its own, and nothing on the row adds them together.
        #expect(answer.leftovers.map(\.bytes) == [Int64(1_506), Int64(285)])
    }

    /// Every guard that fired is counted where somebody can check it and disagree.
    @Test func everyThingLeftAloneIsCountedAndExplained() {
        let answer = Self.answer()
        let labels = answer.row.details.map(\.label)
        #expect(labels.contains("Left alone — 143"))   // the names that are not identifiers
        #expect(labels.contains { $0.hasPrefix("Left alone — ") })

        let explanations = answer.row.details.map(\.value).joined(separator: " ")
        #expect(explanations.contains(LeftoverReader.Guard.partOfAnAppThatIsStillHere.explanation))
        #expect(explanations.contains(LeftoverReader.Guard.sameMakerAsAnInstalledApp.explanation))
        #expect(explanations.contains(LeftoverReader.Guard.neverAnAppInTheFirstPlace.explanation))
    }

    /// ⚠️ The row says, in its own words, that nothing is offered for removal. It does not leave a
    /// disabled button to be explained.
    @Test func theRowSaysNothingIsRemovedYet() {
        let answer = Self.answer()
        #expect(answer.row.reason?.contains("does not remove these yet") == true)
        #expect(answer.row.details.contains { $0.label == "Removing them" })
        #expect(LeftoverReader.Removal.available == false)
    }

    /// Group containers are named as a place we deliberately do not look.
    @Test func whereWeDidNotLookIsStated() {
        let answer = Self.answer()
        let pair = answer.row.details.first { $0.label == "Where we did not look" }
        #expect(pair?.value.contains("Group containers") == true)
    }

    @Test func aCleanMacGetsAPlainSentenceAndNoFigure() {
        let answer = LeftoverReader.answer(from: LeftoverReader.Survey(candidates: []),
                                           appsOnThisMac: installed,
                                           runningBundleIDs: [],
                                           isRegistered: noAppRegistered)
        #expect(answer.leftovers.isEmpty)
        #expect(answer.row.headline == "Nothing here belonged to an app that has been removed.")
        #expect(answer.row.measure == nil)
        #expect(answer.row.severity == .information)
        #expect(answer.row.status == .good)
    }

    /// ⚠️ Never report zero because we could not look.
    @Test func aLibraryWeCouldNotReadIsNotAnEmptyOne() {
        let answer = LeftoverReader.answer(from: LeftoverReader.Survey(candidates: nil),
                                           appsOnThisMac: installed,
                                           runningBundleIDs: [],
                                           isRegistered: noAppRegistered)
        #expect(answer.row.unreadable == .notPermitted)
        #expect(answer.row.measure == nil)
        #expect(answer.row.status == .notChecked)
        #expect(answer.leftovers.isEmpty)
    }

    /// The section's ceiling holds here too, whatever is found.
    @Test func leftoversNeverRaiseTheSeverity() {
        #expect(Self.answer().row.severity == AppsRow.severityCeiling)
    }

    /// ⚠️ **Nothing that a guard rejected is ever weighed**, and this is not tidiness. Weighing
    /// first meant adding up Apple's own caches and every installed app's container: it blew a
    /// two-minute test timeout on the measured Mac. Only what survives all seven guards is walked.
    @Test func onlySurvivorsAreWeighed() {
        final class Counter: @unchecked Sendable { var weighed: [String] = [] }
        let counter = Counter()

        _ = LeftoverReader.answer(from: Self.survey(),
                                  appsOnThisMac: installed,
                                  runningBundleIDs: [],
                                  isRegistered: noAppRegistered,
                                  weigh: { counter.weighed.append($0.identifier); return $0.bytes })

        // Three genuine leftovers plus the CUPS preferences file, which survives the seven guards
        // and is dropped later for never having been an app. A plist costs nothing to weigh; the
        // multi-gigabyte caches below are the ones that must never be touched.
        #expect(counter.weighed.count == 4)
        #expect(!counter.weighed.contains("com.apple.Safari"))
        #expect(!counter.weighed.contains("com.khanov.BlockerX.MacWebExtension"))
        #expect(!counter.weighed.contains("com.google.Keystone.Agent"))
    }
}

// MARK: - The hooks the removal half will need

@Suite struct LeftoverRemovalHookTests {

    /// A plan carries exactly the paths that were shown, and nothing inferred.
    @Test func aPlanIsExactlyWhatTheRowShowed() {
        let leftover = Leftover(appName: "Opera",
                                bundleID: "com.operasoftware.Opera",
                                paths: ["/Users/x/Library/Application Support/com.operasoftware.Opera"],
                                bytes: 285,
                                reason: "Gone.")
        let plan = LeftoverReader.Removal.plan(for: leftover)
        #expect(plan.id == leftover.id)
        #expect(plan.paths == leftover.paths)
        #expect(plan.bytes == leftover.bytes)
        #expect(plan.appName == "Opera")
    }

    /// The identity a selection is keyed by has to survive a re-scan, which is why it is the bundle
    /// identifier and not a path or an index.
    @Test func theIdentityIsTheBundleIdentifier() {
        let leftover = Leftover(appName: "Opera",
                                bundleID: "com.operasoftware.Opera",
                                paths: ["/a", "/b"],
                                reason: "Gone.")
        #expect(leftover.id == "com.operasoftware.Opera")
    }

    /// The promise the engine has to keep is written down now, so it is built to rather than
    /// described afterwards.
    @Test func thePromiseIsThirtyDaysAndNothingDeleted() {
        #expect(LeftoverReader.Removal.promise.contains("Nothing is deleted"))
        #expect(LeftoverReader.Removal.promise.contains("30 days"))
    }
}

// MARK: - Reading this Mac, live

@Suite struct LeftoverReaderLiveTests {

    /// It runs here and produces a row. The contents change with what is installed, so what is
    /// asserted is the shape.
    @Test func itReadsThisMacWithoutFallingOver() {
        let answer = LeftoverReader.read(appsOnThisMac: ["com.apple.Safari"])
        #expect(answer.row.topic == .removedLeftovers)
        #expect(answer.row.severity == AppsRow.severityCeiling)
        #expect(!answer.row.headline.isEmpty)
    }

    /// ⚠️ The section's claim that Apps needs no Full Disk Access rests on this passing on an
    /// ordinary account.
    @Test func theLibraryReadsWithoutFullDiskAccess() {
        #expect(LeftoverReader.survey(fullDiskAccess: false).candidates != nil)
    }

    /// ⚠️ **The live guard against the worst outcome.** Whatever this Mac happens to hold, nothing
    /// reported may belong to an app that is installed or running right now.
    @Test func nothingReportedBelongsToSoftwareThatIsHere() {
        let running = LeftoverReader.runningBundleIDs()
        let answer = LeftoverReader.read(appsOnThisMac: [])
        for leftover in answer.leftovers {
            guard let id = leftover.bundleID else { continue }
            #expect(!running.contains(id), "\(id) is running and must not be listed")
            #expect(!LeftoverReader.isRegisteredWithLaunchServices(id),
                    "\(id) is installed and must not be listed")
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Testing
import Foundation
import WellkeptCore

//  ChangesTests.swift
//  WellkeptTests — links WellkeptCore only
//
//  **The vocabulary of the Changes section, and the four promises inside it that somebody could
//  undo in a single well-meaning line.**
//
//  1. A description that says only one thing cannot be written by accident.
//  2. `Cause` and `Confidence` can never contradict each other.
//  3. An outage never claims seconds it did not measure.
//  4. A key written into a snapshot survives being read back.

// MARK: - ⭐ The three-part description

@Suite("Every watched thing says all three things")
struct ChangesDescriptionTests {

    /// John, 2026-08-28: *"Let's show him up and do it better."* Better was defined concretely —
    /// what the setting does, what turning it off costs you, and why it might have changed. This is
    /// the test that stops the third field being filled by repeating the first.
    @Test func everyWatchedThingSaysAllThreeThings() {
        for watched in Watched.all {
            #expect(watched.description.isComplete,
                    "\(watched.key.storageKey) does not carry three separate sentences")
        }
    }

    @Test func theCatalogueCoversEverythingWellkeptAlreadyReads() {
        // Seven protections plus Lockdown Mode, five sharing services, four kinds of startup item,
        // twelve permissions, and macOS itself.
        #expect(Watched.inTopic(.protections).count == ProtectionKind.allCases.count)
        #expect(Watched.inTopic(.reachableFrom).count == 5)
        #expect(Watched.inTopic(.startsOnItsOwn).count == 4)
        #expect(Watched.inTopic(.whoCanWatch).count == Permission.allCases.count)
        #expect(Watched.inTopic(.macOSItself).count == 1)
    }

    @Test func noTwoWatchedThingsShareAKey() {
        let keys = Watched.all.map(\.key.storageKey)
        #expect(Set(keys).count == keys.count)
    }

    /// A description that quietly went missing would take its row off the screen without failing
    /// anything, because an undescribed change is counted rather than listed.
    @Test func everyKeyCanBeLookedUp() {
        for watched in Watched.all {
            #expect(Watched.of(watched.key)?.title == watched.title)
        }
    }

    /// ⚠️ Only the four permissions that let software act as you or see everything carry a safe
    /// value. Camera and microphone deliberately do not: macOS asked, by name, and somebody said
    /// yes — that is not a Mac with something wrong with it.
    @Test func onlyTheStrongestPermissionsAreWorthAttention() {
        let flagged = Watched.inTopic(.whoCanWatch).filter { $0.safeValue != nil }.map(\.key.name)
        #expect(Set(flagged) == ["accessibility", "inputMonitoring", "screenRecording", "fullDiskAccess"])
    }

    /// ⚠️ The sharing services never store "Off". There is no reading on macOS that proves one is
    /// switched off, and a snapshot recording one as off would make a later build find a change
    /// that never happened.
    @Test func sharingServicesNeverCallAnythingOff() {
        for watched in Watched.inTopic(.reachableFrom) {
            #expect(watched.safeValue == "Not seen listening")
        }
    }

    @Test func anIncompleteDescriptionIsRejected() {
        let repeated = Watched.Description(does: "It does the thing that it does.",
                                           costOfTurningItOff: "It does the thing that it does.",
                                           whyItMightHaveChanged: "It does the thing that it does.")
        #expect(!repeated.isComplete)

        let stub = Watched.Description(does: "It encrypts the disk so nobody else can read it.",
                                       costOfTurningItOff: "N/A",
                                       whyItMightHaveChanged: "Unknown.")
        #expect(!stub.isComplete)
    }
}

// MARK: - ⛔ The case that must never exist

@Suite("Nothing in Changes ever names an app as the cause")
struct ChangesCauseGuardTests {

    /// Words that would mean somebody had added a way to blame software.
    static let forbidden = ["app", "process", "culprit", "blame", "responsible", "author", "wrote"]

    static func changesSource() -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // the repository
        let file = root.appendingPathComponent("Core/Sources/WellkeptCore/Changes.swift")
        return (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    }

    @Test("The scanner reads the file")
    func scannerWorks() {
        #expect(ChangesCauseGuardTests.changesSource().contains("public enum Cause"))
    }

    /// ⛔ Nothing an unprivileged app can read records which process wrote a setting. A case named
    /// `.changedByAnApp` would put somebody's software on screen beside a security warning on the
    /// strength of a coincidence.
    @Test("No `Cause` case names an app, a process or a culprit")
    func noCauseNamesSoftware() {
        let text = ChangesCauseGuardTests.changesSource()
        guard let start = text.range(of: "public enum Cause") else {
            Issue.record("the Cause enum was not found — this guard is no longer guarding anything")
            return
        }
        // The enum body ends at the first line that closes it at column zero.
        let body = text[start.lowerBound...].components(separatedBy: "\n}").first ?? ""

        var offenders: [String] = []
        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("case ") else { continue }   // comments carry the reasoning
            let lowered = trimmed.lowercased()
            for word in Self.forbidden where lowered.contains(word) {
                offenders.append(trimmed)
            }
        }
        #expect(offenders.isEmpty, "a Cause case names software: \(offenders)")
    }

    /// The four cases that are allowed to exist, so removing one is as visible as adding a fifth.
    @Test("Unknown is an ordinary answer and it is still there")
    func unknownSurvives() {
        #expect(Cause.unknown.clause == "we cannot tell what changed it")
        #expect(Cause.unknown.mayRaiseSeverity)
        #expect(!Cause.setByAnOrganisation.mayRaiseSeverity)
    }
}

// MARK: - Cause and confidence cannot contradict each other

@Suite("A change never claims confidence it has no cause for")
struct ChangeConfidenceTests {

    private static func window() -> Window {
        Window(after: Date(timeIntervalSince1970: 1_000), before: Date(timeIntervalSince1970: 2_000))
    }

    @Test func anUnknownCauseIsAlwaysNoEvidence() {
        let change = Change(key: WatchedKey(.protections, "firewall"), what: "Firewall",
                            from: "On", to: "Off", window: Self.window(),
                            cause: .unknown, confidence: .certain)
        #expect(change.confidence == .noEvidence)
    }

    @Test func aKnownCauseIsNeverNoEvidence() {
        let update = MacOSUpdate(version: "26.6.2", installedAt: Date())
        let change = Change(key: WatchedKey(.protections, "firewall"), what: "Firewall",
                            from: "On", to: "Off", window: Self.window(),
                            cause: .duringMacOSUpdate(update), confidence: .noEvidence)
        #expect(change.confidence == .consistent)
    }

    @Test func anOrganisationIsTheOneCertainty() {
        let change = Change(key: WatchedKey(.protections, "fileVault"), what: "FileVault",
                            from: "On", to: "Off", window: Self.window(),
                            cause: .setByAnOrganisation)
        #expect(change.confidence == .certain)
    }

    /// ⚠️ A setting an organisation forces is never raised. A health check that flags it is an
    /// accusation aimed at somebody who cannot act on it.
    @Test func anOrganisationSetSwitchIsNeverAmber() {
        let watched = Watched.of(WatchedKey(.protections, "fileVault"))
        let organisation = Change(key: WatchedKey(.protections, "fileVault"), what: "FileVault",
                                  from: "On", to: "Off", window: Self.window(),
                                  cause: .setByAnOrganisation)
        let anybodyElse = Change(key: WatchedKey(.protections, "fileVault"), what: "FileVault",
                                 from: "On", to: "Off", window: Self.window())
        #expect(organisation.severity(watched) == .information)
        #expect(anybodyElse.severity(watched) == .attention)
    }

    /// ⚠️ There is no route to `.problem`. Whether the resulting state is a problem is the Security
    /// section's question, answered there once.
    @Test func aChangeNeverReachesProblem() {
        for watched in Watched.all {
            let change = Change(key: watched.key, what: watched.title,
                                from: "anything", to: "something else", window: Self.window())
            #expect(change.severity(watched) != .problem)
        }
    }

    @Test func movingBackToTheSafeValueIsJustInformation() {
        let watched = Watched.of(WatchedKey(.protections, "firewall"))
        let change = Change(key: WatchedKey(.protections, "firewall"), what: "Firewall",
                            from: "Off", to: "On", window: Self.window())
        #expect(change.severity(watched) == .information)
    }
}

// MARK: - The outage never invents seconds

@Suite("An outage says only what it measured")
struct OutageTests {

    private static func outage(_ seconds: TimeInterval, _ precision: OutagePrecision) -> Outage {
        let start = Date(timeIntervalSince1970: 1_787_623_457)
        return Outage(wentDown: start, cameBack: start.addingTimeInterval(seconds),
                      precision: precision)
    }

    /// The measured case on this Mac: shutdown 20:04:17, boot 20:07:29.
    @Test func secondsAreSpelledOutWhenBothEndsWereMeasured() {
        #expect(Self.outage(192, .toTheSecond).sentence == "three minutes and twelve seconds")
    }

    /// ⚠️ Two minute-resolution readings cannot produce "and 52 seconds". Saying so would be
    /// inventing the most persuasive part of the sentence.
    @Test func minutePrecisionNeverClaimsSeconds() {
        let said = Self.outage(192, .toTheMinute).sentence
        #expect(said == "about three minutes")
        #expect(!said.contains("second"))
    }

    @Test func aShortOutageStillGetsAMinute() {
        #expect(Self.outage(20, .toTheMinute).sentence == "about one minute")
        #expect(Self.outage(20, .toTheSecond).sentence == "twenty seconds" || Self.outage(20, .toTheSecond).sentence == "20 seconds")
    }

    @Test func exactMinutesDropTheSecondsClause() {
        #expect(Self.outage(240, .toTheSecond).sentence == "four minutes")
    }

    /// ⭐ The wording John was shown, and the half of it that matters most.
    @Test func theSentenceSaysDuringAndNeverBecause() {
        let update = MacOSUpdate(version: "26.6.2",
                                 installedAt: Date(timeIntervalSince1970: 1_787_623_732),
                                 outage: Self.outage(292, .toTheSecond))
        let said = update.sentence
        #expect(said.contains("while your Mac was off for the macOS 26.6.2 update"))
        #expect(said.contains("four minutes and fifty-two seconds")
                || said.contains("four minutes and 52 seconds"))
        #expect(!said.lowercased().contains("the update changed"))
        #expect(!said.lowercased().contains("caused"))
    }

    /// On a standard account the boot record is unreadable, so the sentence honestly loses its
    /// strongest half rather than keeping the shape and inventing the number.
    @Test func withoutABootRecordTheClaimGetsWeaker() {
        let update = MacOSUpdate(version: "26.6.2", installedAt: Date(), outage: nil)
        #expect(update.sentence == "this changed in the same period as the macOS 26.6.2 update")
        #expect(!update.sentence.contains("off for"))
    }
}

// MARK: - Keys survive the round trip

@Suite("A key written into a snapshot reads back as itself")
struct WatchedKeyTests {

    @Test func everyCatalogueKeyRoundTrips() {
        for watched in Watched.all {
            let back = WatchedKey(storageKey: watched.key.storageKey)
            #expect(back == watched.key)
        }
    }

    /// A key written by a build that watched something this one does not is a normal thing to meet
    /// in a file that outlives a release, not an error.
    @Test func anUnknownTopicIsRefusedRatherThanGuessed() {
        #expect(WatchedKey(storageKey: "somethingElse.firewall") == nil)
        #expect(WatchedKey(storageKey: "protections") == nil)
        #expect(WatchedKey(storageKey: ".firewall") == nil)
        #expect(WatchedKey(storageKey: "protections.") == nil)
    }

    /// ⚠️ `allCases` is the row order and it never sorts.
    @Test func theRowOrderIsFixed() {
        #expect(ChangesTopic.allCases.map(\.rawValue)
                == ["protections", "reachableFrom", "startsOnItsOwn", "whoCanWatch", "macOSItself"])
    }
}

// MARK: - What the section says about itself

@Suite("The report never says nothing changed when it could not look")
struct ChangesReportTests {

    private static func change(_ name: String, from: String, to: String) -> Change {
        Change(key: WatchedKey(.protections, name), what: name, from: from, to: to,
               window: Window(after: Date(timeIntervalSince1970: 1_000),
                              before: Date(timeIntervalSince1970: 2_000)))
    }

    /// ⚠️ The first launch is `.notChecked`, never `.good`. Saying nothing changed on the day we
    /// started looking is the confident wrong answer the product exists to avoid.
    @Test func theFirstLookIsNotAVerdict() {
        let report = ChangesReport(ranAt: Date(), previous: nil, changes: [])
        #expect(report.isFirstLook)
        #expect(report.status == .notChecked)
        #expect(report.summary.contains("first look"))
    }

    @Test func aQuietMacReadsAsGood() {
        let report = ChangesReport(ranAt: Date(), previous: Date(timeIntervalSince1970: 1_000),
                                   changes: [])
        #expect(report.status == .good)
        #expect(report.summary.hasPrefix("Nothing Wellkept watches has changed"))
    }

    @Test func aChangedSwitchNeedsAttention() {
        let report = ChangesReport(ranAt: Date(), previous: Date(timeIntervalSince1970: 1_000),
                                   changes: [Self.change("firewall", from: "On", to: "Off")])
        #expect(report.status == .needsAttention)
        #expect(report.worst == .attention)
    }

    /// ⚠️ Counted, never listed. The number appears in the sentence and no row is drawn for it.
    @Test func undescribedChangesAreCountedInWords() {
        let report = ChangesReport(ranAt: Date(), previous: Date(timeIntervalSince1970: 1_000),
                                   changes: [], undescribed: 41)
        #expect(report.summary.contains("41 other values also changed"))
        #expect(report.changes.isEmpty)
    }

    /// **John's answer 4, 2026-08-28.** A run that could not see the privacy grants may not report
    /// a clean bill of health.
    @Test func aRefusedGrantStopsTheSectionSayingGood() {
        let report = ChangesReport(ranAt: Date(), previous: Date(timeIntervalSince1970: 1_000),
                                   changes: [], privacyChangedButUnreadable: true)
        #expect(!report.complete)
        #expect(report.status == .notChecked)
    }

    /// ⚠️ A refusal nobody can lift leaves the check complete and still says plainly that we did
    /// not see it. A caveat nobody can clear is how an app teaches people to ignore its warnings.
    @Test func aRefusalNobodyCanLiftStillCountsAsComplete() {
        let report = ChangesReport(ranAt: Date(), previous: Date(timeIntervalSince1970: 1_000),
                                   changes: [], outageUnreadable: .notGrantable)
        #expect(report.complete)
        #expect(report.status == .good)
    }

    /// ⚠️ A Mac asleep or switched off between snapshots has to be said, not glossed.
    @Test func timeTheMacWasOffIsSaidOutLoud() {
        let report = ChangesReport(ranAt: Date(), previous: Date(timeIntervalSince1970: 1_000),
                                   changes: [], macWasOffOrAsleep: true)
        #expect(report.summary.contains("asleep or switched off"))
    }

    @Test func worstComesFirst() {
        let quiet = Self.change("automaticLogin", from: "Off", to: "Off")
        let loud = Self.change("firewall", from: "On", to: "Off")
        let report = ChangesReport(ranAt: Date(), previous: Date(timeIntervalSince1970: 1_000),
                                   changes: [quiet, loud])
        #expect(report.ordered.first?.key.name == "firewall")
    }

    @Test func aWindowThatSpannedSleepSaysSo() {
        let window = Window(after: Date(timeIntervalSince1970: 1_000),
                            before: Date(timeIntervalSince1970: 500_000),
                            macWasOffOrAsleep: true)
        #expect(window.sentence(now: Date(timeIntervalSince1970: 500_000))
                    .contains("asleep or switched off"))
    }
}

// MARK: - ⛔ The type itself cannot hold an app's name

/// ⭐ **Asserted structurally, because a screen is the wrong place to check this.**
///
/// `ChangesCauseGuardTests` above reads the source and fails on a case whose *name* mentions
/// software. That is worth having, and it is not enough on its own: a case called `.attributed`
/// carrying a bundle identifier would sail past it. So this suite proves the shape of the thing —
/// four cases, exactly one of which carries anything at all, and that one carries a version, an
/// instant and an outage. **There is nowhere in `Cause` to put an app's name**, which is a
/// stronger statement than "no code currently puts one there".
///
/// The measurement behind all of it: nothing an unprivileged app can read on macOS records which
/// process wrote a setting, and the one log that might forgets within a day. Every attribution to
/// an app would therefore be a guess printed beside a security warning.
@Suite("The cause type has nowhere to put an app")
struct ChangesCauseShapeTests {

    /// ⚠️ **This function is the test.** It switches over `Cause` with no `default`, so the day
    /// somebody adds a fifth case the build stops here and they have to come and read the comment
    /// above before they can carry on. A runtime assertion could not do that.
    private func shape(of cause: Cause) -> String {
        switch cause {
        case .duringMacOSUpdate: "an update was recorded in the same window"
        case .whileYouWereUsingTheMac: "the Mac was awake throughout"
        case .setByAnOrganisation: "a profile forces it"
        case .unknown: "nothing we can read says anything"
        }
    }

    @Test("There are four causes and the switch over them is exhaustive")
    func fourCausesAndNoMore() {
        let update = MacOSUpdate(version: "26.6.2", installedAt: Date())
        let all: [Cause] = [.duringMacOSUpdate(update), .whileYouWereUsingTheMac,
                            .setByAnOrganisation, .unknown]
        #expect(Set(all.map(shape(of:))).count == 4)
    }

    /// ⛔ **The only thing a cause carries, field by field.** A `bundleID`, a `process` or an
    /// `app` added to `MacOSUpdate` would be a way to name software without touching `Cause` at
    /// all, and the source scan would not see it.
    @Test("The one cause that carries anything carries three facts, and none of them is an app")
    func theUpdatePayloadCannotNameSoftware() throws {
        let update = MacOSUpdate(version: "26.6.2",
                                 installedAt: Date(timeIntervalSince1970: 1_787_623_732),
                                 outage: Outage(wentDown: Date(timeIntervalSince1970: 1_787_623_440),
                                                cameBack: Date(timeIntervalSince1970: 1_787_623_732),
                                                precision: .toTheSecond))
        let encoded = try JSONEncoder().encode(update)
        let fields = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(Set(fields.keys) == ["version", "installedAt", "outage"],
                "MacOSUpdate gained a field: \(fields.keys.sorted())")

        let forbidden = ["app", "bundle", "process", "name", "by", "author", "culprit"]
        for key in fields.keys {
            let lowered = key.lowercased()
            for word in forbidden {
                #expect(lowered != word && !lowered.hasPrefix(word),
                        "\(key) is a place to put an app's identity")
            }
        }
    }

    /// ⚠️ **A privacy grant row names an app, and that is not an accusation.** "Zoom — Screen
    /// recording" says which permission moved; the *cause* beside it still says we cannot tell what
    /// did it. The two halves of the row are allowed to be different, and this is the test that
    /// keeps the app's name out of the half that assigns blame.
    @Test("An app's name appears in what changed and never in why")
    func theAppNameStaysOutOfTheCause() {
        let window = Window(after: Date(timeIntervalSince1970: 1_000),
                            before: Date(timeIntervalSince1970: 2_000))
        let change = Change(key: WatchedKey(.whoCanWatch, "screenRecording"),
                            what: "Zoom — Screen recording",
                            from: "Not allowed", to: "Allowed",
                            window: window, cause: .unknown)

        #expect(change.what.contains("Zoom"))
        #expect(!change.cause.clause.contains("Zoom"))
        #expect(change.cause.clause == "we cannot tell what changed it")

        // The whole row's sentence mentions the app once, as the subject of the change, and never
        // as the agent of it.
        let sentence = change.sentence(now: Date(timeIntervalSince1970: 2_000))
        #expect(sentence.hasPrefix("Zoom — Screen recording went from"))
        #expect(sentence.hasSuffix("we cannot tell what changed it."))
    }

    /// The same row on a Mac that updated in the window. The update is named; the app is not
    /// implicated, and the update is not implicated either.
    @Test("Even with an update in the window, nothing is accused")
    func anUpdateInTheWindowAccusesNobody() {
        let update = MacOSUpdate(version: "26.6.2", installedAt: Date(timeIntervalSince1970: 1_500))
        let change = Change(key: WatchedKey(.whoCanWatch, "camera"),
                            what: "Zoom — Camera", from: "Not allowed", to: "Allowed",
                            window: Window(after: Date(timeIntervalSince1970: 1_000),
                                           before: Date(timeIntervalSince1970: 2_000)),
                            cause: .duringMacOSUpdate(update))
        let sentence = change.sentence(now: Date(timeIntervalSince1970: 2_000)).lowercased()
        #expect(sentence.contains("in the same period as the macos 26.6.2 update"))
        #expect(!sentence.contains("zoom changed"))
        #expect(!sentence.contains("caused"))
        #expect(change.confidence == .consistent, "a coincidence was upgraded to a certainty")
    }
}

// MARK: - Counted, never listed — at any count

/// ⚠️ **The number is allowed to be enormous and it still never becomes rows.**
///
/// This is the version-one scope decision, expressed as an invariant rather than as a note in a
/// document. The general settings journal — a curated description for every key on the Mac — waits
/// for version two. Until then a difference nobody can explain adds one to a sentence, because a
/// row nobody can explain is a row that worries somebody for no reason.
@Suite("Undescribed changes never become rows")
struct UndescribedCountTests {

    private static func report(_ count: Int) -> ChangesReport {
        ChangesReport(ranAt: Date(timeIntervalSince1970: 2_000),
                      previous: Date(timeIntervalSince1970: 1_000),
                      changes: [], undescribed: count)
    }

    @Test("No count produces a row", arguments: [0, 1, 2, 41, 1_000, 100_000])
    func noCountEverProducesARow(count: Int) {
        let report = Self.report(count)
        #expect(report.changes.isEmpty)
        #expect(report.ordered.isEmpty)
        for topic in ChangesTopic.allCases { #expect(report.changes(in: topic).isEmpty) }
        #expect(report.undescribed == count)
    }

    /// And a huge number does not make the section amber. Whether a value we cannot describe
    /// matters is not something we know, and colouring it would be inventing an opinion.
    @Test("A great many unexplained values is still not a fault")
    func aLargeCountIsNotAProblem() {
        let report = Self.report(11_224)
        #expect(report.worst == .information)
        #expect(report.status == .good)
        #expect(report.summary.contains("11224 other values also changed")
                || report.summary.contains("11,224 other values also changed"))
    }

    /// One is written as a word, because "1 other values" is a machine talking.
    @Test("One is a word, and the plural agrees with itself")
    func theSentenceAgreesWithItself() {
        #expect(Self.report(1).summary.contains("One other value also changed"))
        #expect(Self.report(2).summary.contains("2 other values also changed"))
        #expect(!Self.report(0).summary.contains("other value"))
    }

    /// A negative count is a bug upstream, and it must not print "-3 other values".
    @Test("A nonsense count is clamped rather than printed")
    func aNegativeCountIsClamped() {
        #expect(Self.report(-3).undescribed == 0)
        #expect(!Self.report(-3).summary.contains("-3"))
    }
}

// MARK: - A Mac that was off says so

/// ⚠️ **"Nothing changed since Tuesday" reads as five days of use.** If the Mac was shut for four
/// of them, that sentence has quietly overstated how much happened while anybody was watching —
/// and it is the sentence a person uses to decide whether the report means anything.
@Suite("A Mac that was off between snapshots says so rather than reporting a quiet week")
struct MacWasOffTests {

    @Test("A quiet report still says the Mac was off")
    func aQuietReportStillSaysIt() {
        let report = ChangesReport(ranAt: Date(timeIntervalSince1970: 500_000),
                                   previous: Date(timeIntervalSince1970: 1_000),
                                   changes: [], macWasOffOrAsleep: true)
        #expect(report.changes.isEmpty)
        #expect(report.summary.contains("Nothing Wellkept watches has changed"))
        #expect(report.summary.contains("asleep or switched off for part of that time"),
                "a report over a period the Mac spent switched off read as a quiet week")
    }

    /// The same fact on the row, not only in the summary. A person reading one row has not read the
    /// summary, and the caveat belongs to the window rather than to the section.
    @Test("The row's own window carries it too")
    func theRowCarriesItAsWell() {
        let window = Window(after: Date(timeIntervalSince1970: 1_000),
                            before: Date(timeIntervalSince1970: 500_000),
                            macWasOffOrAsleep: true)
        let change = Change(key: WatchedKey(.protections, "firewall"), what: "Firewall",
                            from: "On", to: "Off", window: window)
        #expect(change.sentence(now: Date(timeIntervalSince1970: 500_000))
                    .contains("this Mac was asleep or switched off for part of it"))
    }

    /// ⚠️ **"Off" is provable and "asleep" is not.** Nothing unprivileged distinguishes a sleeping
    /// Mac from an idle one after the fact, so the sentence says both and claims neither.
    @Test("It never claims to know which of the two it was")
    func itNeverClaimsToKnowWhich() {
        let window = Window(after: Date(timeIntervalSince1970: 1_000),
                            before: Date(timeIntervalSince1970: 500_000),
                            macWasOffOrAsleep: true)
        let said = window.sentence(now: Date(timeIntervalSince1970: 500_000))
        #expect(said.contains("asleep or switched off"))
        #expect(!said.contains("was asleep for"))
        #expect(!said.contains("was switched off for"))
    }

    /// A window with the flag clear says nothing at all about sleep, rather than saying it was
    /// awake — which we also cannot prove.
    @Test("A window with nothing to say about sleep says nothing")
    func silenceWhereThereIsNoEvidence() {
        let window = Window(after: Date(timeIntervalSince1970: 1_000),
                            before: Date(timeIntervalSince1970: 500_000))
        let said = window.sentence(now: Date(timeIntervalSince1970: 500_000))
        #expect(!said.lowercased().contains("asleep"))
        #expect(!said.lowercased().contains("awake"))
    }
}

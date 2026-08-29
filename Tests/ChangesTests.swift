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

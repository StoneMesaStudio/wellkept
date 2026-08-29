// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation

//  RehearsalGate.swift
//  WellkeptCore
//
//  ⛔⛔ **THE GATE. Nothing in the backup engine may be offered to anybody until somebody has
//  erased a drive and restored from it on real hardware.**
//
//  ## Why this file exists, in full
//
//  **A backup is proven by erasing a drive and restoring from it. It is never proven by a passing
//  test suite, and no restore has ever been performed with this code.**
//
//  That is not caution and it is not process. It is the honest state of the evidence on 2026-08-29,
//  and every one of these was measured rather than assumed:
//
//  - **Migration Assistant accepting a data-only APFS volume is UNVERIFIED**, and Apple's own string
//    inside Migration Assistant argues against it: *"Volume does not contain an installation of
//    macOS or OS X."* The entire shape of the destination rests on a claim nobody has tested.
//  - **Without Full Disk Access a backup contains no mail, no messages, no photos, no contacts, no
//    Safari data and no Trash** — not partial, *nothing* — and macOS refuses **silently, with no
//    error**. A run can finish, report success, and hold none of the things people actually restore.
//  - **Half a backup is worse than none.** It converts a risk somebody knows about into a belief
//    they never check. A person who believes they are backed up stops thinking about it, and finds
//    out on the one day the answer matters.
//  - **`copyfile` loses the creation date, launders the download-provenance tag, inflates sparse
//    files and ignores hard links.** All four are repairable, and all four were found by measuring
//    rather than by reasoning — which is the argument for measuring the restore too.
//
//  The research verdict was that a backup engine could not honestly ship. **John removed that
//  blocker on 2026-08-29 by agreeing to buy a spare drive and rehearse a real restore**, on this
//  condition, in his words: nothing in the engine is offered to anybody until that rehearsal has
//  been walked on real hardware. Not a green test suite — a real drive, a real backup, a real
//  Migration Assistant restore.
//
//  ⚠️ His other condition was that **the gate is a shipped, visible thing in the code, not a note in
//  a document.** So it is a type, not a comment:
//
//  ## How it is enforced — three layers, and the first one is the compiler
//
//  1. ⭐ **`Pass` cannot be constructed outside this file.** Its initialiser is `fileprivate`. A
//     copier is declared as `func run(…, permittedBy: RehearsalGate.Pass)`, which means code that
//     has not asked the gate **cannot call it at all**. This is not a convention somebody can
//     forget; it is a compile error.
//  2. **`Tests/RehearsalGateGuardTests.swift` reads this repository's own Swift** and fails the
//     build if any file writes with a copy primitive without naming a `Pass`, or if anything
//     outside a test bundle reaches for the debug-only door below.
//  3. **The face says so.** `faceLine` is the sentence that stands where the button would be. The
//     engine may be built, tested and demonstrated. It may not be **offered**. Hiding the row
//     instead would be the app pretending the feature does not exist, which is a different lie.
//
//  ## What flipping it looks like
//
//  Exactly one edit, in one place: fill in `performed` below with the four facts. It is `nil`
//  today, and it stays `nil` until a human has walked the rehearsal and written down what hardware,
//  what macOS, and on what date. A test asserts that a recorded rehearsal has all four facts and a
//  date that is not in the future, so a placeholder cannot open the gate.
//
//  ⛔ **Do not flip this to make a test pass, a demo work, or a build go green.** There is no
//  legitimate reason for this constant to change except a person having actually done it.

// MARK: - The gate

public enum RehearsalGate {

    // MARK: ── ⭐ The single constant ───────────────────────────────────────────────────────────

    /// **What was rehearsed, on what hardware, on what macOS, and when.**
    ///
    /// Four facts and no verdict: there is no `succeeded` flag here, because a rehearsal that did
    /// not succeed is not recorded — it is repeated. Writing the facts down is the act that opens
    /// the gate, and the facts are what somebody reading this in a year needs in order to know
    /// whether the evidence still applies to the machine in front of them.
    public struct Rehearsal: Sendable, Hashable, Codable {

        /// The day the restore was actually walked.
        public let performedOn: Date

        /// What it was walked on, specifically enough to be worth something: the Mac, the drive,
        /// and how the drive was formatted. "Mac mini M4, Samsung T7 2 TB, APFS (Encrypted)".
        public let hardware: String

        /// The macOS the backup was made on and restored to. ⚠️ **Migration Assistant refuses a
        /// backup made on a newer macOS than the machine being restored to**, so this is not
        /// bookkeeping — it is the boundary of what the rehearsal proves.
        public let macOS: String

        /// How the restore was performed. "Migration Assistant, from the drive, after a clean
        /// install."
        public let restoredWith: String

        /// What actually happened, including anything that went wrong and had to be worked around.
        /// A rehearsal with nothing to say about it was probably not looked at closely.
        public let notes: String

        public init(performedOn: Date,
                    hardware: String,
                    macOS: String,
                    restoredWith: String,
                    notes: String) {
            self.performedOn = performedOn
            self.hardware = hardware
            self.macOS = macOS
            self.restoredWith = restoredWith
            self.notes = notes
        }

        /// Whether all four facts are actually filled in and the date is not in the future.
        ///
        /// ⚠️ A rehearsal that fails this **does not open the gate**, and a test fails the build on
        /// it. It is the guard against somebody putting a placeholder here to get past a refusal.
        public func isProperlyRecorded(now: Date = Date()) -> Bool {
            func filled(_ s: String) -> Bool {
                !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return filled(hardware) && filled(macOS) && filled(restoredWith) && filled(notes)
                && performedOn <= now
        }

        /// The line for Help and for the Options block, so a person can see what was actually proved.
        public var sentence: String {
            "A real restore was walked on \(performedOn.formatted(date: .abbreviated, time: .omitted)) "
            + "— \(hardware), macOS \(macOS), \(restoredWith)."
        }

        public var detailPairs: [DetailPair] {
            [DetailPair("Rehearsed on", performedOn.formatted(date: .abbreviated, time: .omitted)),
             DetailPair("Hardware", hardware),
             DetailPair("macOS", macOS),
             DetailPair("Restored with", restoredWith),
             DetailPair("What happened", notes)]
        }
    }

    /// ⛔⛔ **`nil` until a human has erased a drive and restored from it.**
    ///
    /// To open the gate, replace `nil` with the four facts:
    ///
    /// ```swift
    /// public static let performed: Rehearsal? = Rehearsal(
    ///     performedOn: DateComponents(calendar: .current, year: 2026, month: 9, day: 6).date!,
    ///     hardware: "Mac mini (M3, 2024), Samsung T7 2 TB, erased as APFS (Encrypted)",
    ///     macOS: "26.6.2",
    ///     restoredWith: "Migration Assistant, after a clean install from Recovery",
    ///     notes: "Everything came back. Mail, Messages and Photos checked by hand ...")
    /// ```
    ///
    /// ⚠️ Nothing else in this app needs changing to open it. That is deliberate: one edit, one
    /// place, and the person making it has to write down what they did.
    public static let performed: Rehearsal? = nil

    /// Whether the rehearsal has been walked **and** properly recorded.
    public static var hasBeenRehearsed: Bool {
        performed?.isProperlyRecorded() ?? false
    }

    // MARK: ── ⚠️ The second proof, for the background piece ─────────────────────────────────────

    /// **A thing that was measured rather than assumed, with the date and the method.**
    ///
    /// Used for one question so far, and it is a question nobody has answered: **does an
    /// `SMAppService.agent` inherit the app's Full Disk Access?** If it does not, every backup the
    /// background piece makes on a schedule silently contains no mail, no messages and no photos,
    /// and macOS reports no error at all. The person would find out on the day they restored.
    ///
    /// ⚠️ It is a **separate** proof from the rehearsal because it is a separate risk. The
    /// foreground app can be trusted with the grant the moment the restore has been walked; the
    /// background piece cannot be trusted with it until somebody has watched it hold one.
    public struct Proof: Sendable, Hashable, Codable {

        /// What was shown to be true.
        public let what: String

        /// How it was shown. "Ran the agent with the app quit and confirmed it read
        /// ~/Library/Mail; the app's grant was the only one in place."
        public let how: String

        public let measuredOn: Date

        public init(what: String, how: String, measuredOn: Date) {
            self.what = what
            self.how = how
            self.measuredOn = measuredOn
        }

        public func isProperlyRecorded(now: Date = Date()) -> Bool {
            !what.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !how.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && measuredOn <= now
        }

        public var detailPairs: [DetailPair] {
            [DetailPair("What was proved", what),
             DetailPair("How", how),
             DetailPair("Measured", measuredOn.formatted(date: .abbreviated, time: .omitted))]
        }
    }

    /// ⛔ **`nil` until somebody has watched the background piece read a Full-Disk-Access-protected
    /// folder while the app was not running.** See `Backup.whatTheBackgroundPieceMustProveFirst`.
    public static let agentHoldsFullDiskAccess: Proof? = nil

    /// Whether the background piece has been proved to inherit the grant.
    public static var agentIsProved: Bool {
        agentHoldsFullDiskAccess?.isProperlyRecorded() ?? false
    }

    // MARK: ── ⭐ The token ──────────────────────────────────────────────────────────────────────

    /// ⭐ **Permission to write to a drive. It cannot be made outside this file.**
    ///
    /// A function that copies somebody's files takes one of these, and a caller that has not asked
    /// the gate has nothing to hand it. That is the enforcement — not a check inside the function
    /// that somebody can forget to write, but a parameter the compiler will not let them omit.
    ///
    /// ```swift
    /// // The shape every copy entry point takes:
    /// func run(_ plan: BackupPlan, to destination: URL, permittedBy pass: RehearsalGate.Pass) -> …
    /// ```
    public struct Pass: Sendable, Hashable, CustomStringConvertible {

        /// The rehearsal this pass rests on. `nil` only for the debug-only testing door below,
        /// which is why `isForTestingOnly` exists and why the description says so out loud.
        public let rehearsal: Rehearsal?

        /// What the pass was granted for — the destination, or the words a test gave.
        public let grantedFor: String

        /// ⚠️ True for the debug-only door. Anything writing to a real drive must refuse a pass
        /// that admits to this.
        public let isForTestingOnly: Bool

        /// ⭐ `fileprivate`. Only `RehearsalGate` can make one. Do not widen this, ever.
        fileprivate init(rehearsal: Rehearsal?, grantedFor: String, isForTestingOnly: Bool) {
            self.rehearsal = rehearsal
            self.grantedFor = grantedFor
            self.isForTestingOnly = isForTestingOnly
        }

        public var description: String {
            isForTestingOnly
                ? "RehearsalGate.Pass(FOR TESTING ONLY — \(grantedFor))"
                : "RehearsalGate.Pass(\(grantedFor))"
        }
    }

    // MARK: ── The answer ───────────────────────────────────────────────────────────────────────

    /// What is missing, when the gate says no.
    public enum Missing: String, Sendable, Codable, CaseIterable, Hashable, Identifiable {

        /// Nobody has erased a drive and restored from it.
        case rehearsal

        /// Nobody has shown the background piece inherits Full Disk Access.
        case agentFullDiskAccess

        public var id: String { rawValue }

        /// The plain sentence. ⚠️ **It says what has not happened, not "this feature is
        /// unavailable".** A person told a feature is unavailable assumes it is broken; a person
        /// told nobody has tested the restore yet knows exactly what they are waiting for.
        public var sentence: String {
            switch self {
            case .rehearsal:
                "Wellkept's own backup is not being offered yet. A backup is only proven by erasing a drive and restoring from it, and that has not been done with this version. Until it has, Wellkept will not copy your files."
            case .agentFullDiskAccess:
                "The background piece is not being allowed to back up yet. It has not been shown that it can read your mail, messages and photos on its own — and if it cannot, macOS gives it nothing and reports no error."
            }
        }
    }

    /// Why the gate said no.
    public struct Refusal: Sendable, Hashable, Equatable {

        /// Everything that is missing, in the order it is explained.
        public let missing: [Missing]

        /// What was being asked for.
        public let asked: String

        /// The whole refusal, as the sentences a person reads.
        public var sentences: [String] { missing.map(\.sentence) }

        /// The refusal as one paragraph.
        public var sentence: String { sentences.joined(separator: " ") }
    }

    /// The gate's answer. ⚠️ There is no third case, and no way to get a `Pass` out of a `.refused`.
    public enum Decision: Sendable, Equatable {
        case granted(Pass)
        case refused(Refusal)

        public var pass: Pass? { if case .granted(let p) = self { return p }; return nil }
        public var refusal: Refusal? { if case .refused(let r) = self { return r }; return nil }
        public var isGranted: Bool { pass != nil }
    }

    // MARK: ── ⭐ The one call every writer makes ────────────────────────────────────────────────

    /// ⭐ **Ask before writing anything to a drive.** Every copy entry point in the app calls this,
    /// or takes a `Pass` from somebody who did.
    ///
    /// - Parameter destination: what is about to be written to, in words a person would recognise.
    ///   It is carried on the pass so a refusal, a log line and a report all name the same thing.
    public static func permissionToWrite(to destination: String) -> Decision {
        guard let performed, performed.isProperlyRecorded() else {
            return .refused(Refusal(missing: [.rehearsal], asked: destination))
        }
        return .granted(Pass(rehearsal: performed, grantedFor: destination, isForTestingOnly: false))
    }

    /// ⚠️ **The background piece asks a harder question**, and has to clear both proofs.
    ///
    /// A scheduled backup that silently contains no mail is worse than a manual one, because nobody
    /// is watching when it runs and nobody is told when it holds nothing.
    public static func permissionForTheBackgroundPiece(to destination: String) -> Decision {
        var missing: [Missing] = []
        if !hasBeenRehearsed { missing.append(.rehearsal) }
        if !agentIsProved { missing.append(.agentFullDiskAccess) }
        guard missing.isEmpty, let performed else {
            return .refused(Refusal(missing: missing, asked: destination))
        }
        return .granted(Pass(rehearsal: performed, grantedFor: destination, isForTestingOnly: false))
    }

    // MARK: ── What the screen says instead of a button ─────────────────────────────────────────

    /// ⭐ Whether the Wellkept-backup row may carry its button at all.
    ///
    /// ⚠️ **This gates being offered, not being shown.** The row still draws, still explains what
    /// the engine does, and still says plainly why it is not on offer. Hiding it would be the app
    /// pretending the feature does not exist.
    public static var mayBeOffered: Bool { hasBeenRehearsed }

    /// ⭐ **The sentence that stands where the button would be.**
    public static let faceLine = Missing.rehearsal.sentence

    /// The line for the background piece, wherever it is offered.
    public static let backgroundPieceLine = Missing.agentFullDiskAccess.sentence

    /// The paragraph for Help, saying what the gate is and why an app would do this to itself.
    public static let helpParagraph = """
        Wellkept can copy your home folder to a drive, and it will not do it yet. A backup is only \
        proven by erasing a drive and restoring everything from it, and that has not been done with \
        this version of Wellkept. Until somebody has actually walked that restore, this part of the \
        app stays switched off — a backup you have never restored from is a belief, not a backup.
        """

    /// What the Options block shows about the gate, whichever side of it this build is on.
    public static var detailPairs: [DetailPair] {
        guard let performed, performed.isProperlyRecorded() else {
            return [DetailPair("Restore rehearsal", "Not performed"),
                    DetailPair("Wellkept's own backup", "Not offered")]
        }
        return performed.detailPairs
            + [DetailPair("Wellkept's own backup", "Offered")]
            + (agentHoldsFullDiskAccess?.detailPairs ?? [
                DetailPair("Background piece", "Not proved — scheduled backups are not offered")
              ])
    }

    // MARK: ── ⚠️ The debug-only door ───────────────────────────────────────────────────────────

    #if DEBUG
    /// ⚠️ **A pass for a test, and for nothing else.**
    ///
    /// The engine has to be exercised before the rehearsal — that is how the rehearsal becomes
    /// possible at all. So there is one door, and it is fenced three ways: it is compiled out of a
    /// release build, the pass it makes says `isForTestingOnly` out loud, and
    /// `Tests/RehearsalGateGuardTests.swift` fails the build if any file outside a test bundle
    /// names it.
    ///
    /// ⛔ It is never a way to ship the feature. A copier that writes to a real drive must refuse a
    /// pass whose `isForTestingOnly` is true.
    public static func passForTesting(_ reason: String) -> Pass {
        Pass(rehearsal: nil, grantedFor: reason, isForTestingOnly: true)
    }
    #endif
}

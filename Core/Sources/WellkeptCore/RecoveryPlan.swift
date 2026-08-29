// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation

//  RecoveryPlan.swift
//  WellkeptCore
//
//  ⭐ **One page to print, for the day the Mac will not start.**
//
//  ## Why this is the row that survives everything else
//
//  It needs **no drive, no administrator, no background piece and no network**. It is the only part
//  of this section that is not gated, not measured against a permission, and not waiting on a
//  rehearsal — because it is not software. It is a page.
//
//  ⚠️ **Instructions that live only on the dead Mac are worthless.** That is the whole design
//  constraint and it is easy to forget while writing a screen: a person reads this at the moment
//  their Mac shows a question mark, which is precisely the moment they cannot open an app on it.
//  So every type below is built to be printed and carried — and the page carries **blanks a person
//  fills in by hand**, because the two facts that matter most are ones this app is not allowed to
//  know.
//
//  ## ⚠️ The two things that changed, and why the page has a lifetime
//
//  1. **macOS 26 moved the FileVault recovery key out of Apple's escrow and into the Passwords
//     app.** *"I can get it back with my Apple ID"* is **no longer true.** Wellkept can never read
//     that key — nothing unprivileged can — but it can make somebody press **Show** and write it
//     down **while the Mac still works.** Nobody else says this, and it is the single most useful
//     sentence in this section.
//  2. **Migration Assistant refuses a backup made on a newer macOS than the machine being restored
//     to.** So the page records **the macOS version it was written for**, and says so when that
//     version has moved on. It is a document with a lifetime, not a one-off.
//
//  ## What is deliberately not here
//
//  - ⛔ **No bootable backup.** That idea is dead and must never be proposed again. This page
//    replaces it.
//  - ⛔ **No macOS installer on the drive.** On Apple silicon, Recovery downloads its own installer
//    and never reads one from your drive. An 18.4 GB installer helps in exactly one case — another
//    working Mac and bad internet — and costs everybody else 18.4 GB.
//  - ⛔ **No step that needs Wellkept.** Our software plays no part in a machine restore, and a
//    recovery page that required the app you cannot run would be a joke at somebody's expense.

// MARK: - Which kind of Mac

/// **How this Mac gets into Recovery, and where its installer comes from.**
///
/// `MacArchitecture` itself belongs to `MacModels.swift` and has two cases, which is correct: a Mac
/// is one or the other. This page has a third possibility — **we could not tell** — and it is
/// carried as an optional rather than as a third case, so nothing else in the app has to grow a
/// branch for a state only this page has.
///
/// ⚠️ **Intel is untested.** The owner's 2015 iMac cannot run macOS 14, so nothing in this app has
/// ever been run on an Intel Mac. The instruction below is Apple's published one, not a measured
/// one.
extension MacArchitecture {

    /// **How to start up in Recovery on this Mac**, and only on this Mac.
    ///
    /// The page prints one instruction, not two. A page that says "if you have an Apple silicon
    /// Mac, do this; otherwise do that" asks somebody to identify their own processor at the worst
    /// possible moment.
    public var howToReachRecovery: String {
        switch self {
        case .appleSilicon:
            "Shut the Mac down completely. Press and hold the power button until the screen says "
            + "\"Loading startup options\", then let go and choose Options ▸ Continue."
        case .intel:
            "Shut the Mac down completely. Press the power button, then immediately hold "
            + "Command and R together until you see the Apple logo."
        }
    }

    /// Where the installer comes from. ⛔ Apple silicon does not read one from your drive, so no
    /// version of this app ships an 18.4 GB installer onto somebody's backup by default.
    public var whereTheInstallerComesFrom: String {
        switch self {
        case .appleSilicon:
            "Recovery downloads macOS itself over the internet. You do not need an installer on "
            + "the backup drive, and one there would not be used."
        case .intel:
            "Recovery downloads macOS itself over the internet."
        }
    }

    /// The instruction for a Mac we could not identify. Both routes, oldest last, described by the
    /// year somebody can read off the About screen rather than by the name of a processor.
    public static let howToReachRecoveryWhenWeDoNotKnow =
        "Shut the Mac down completely. On a Mac made in 2021 or later, hold the power button until "
        + "the screen says \"Loading startup options\". On an older one, press the power button and "
        + "immediately hold Command and R."

    public static let whereTheInstallerComesFromWhenWeDoNotKnow =
        "Recovery downloads macOS itself over the internet. You do not need an installer on the "
        + "backup drive."
}

// MARK: - One step

/// One thing to do, in the order to do it.
public struct RecoveryStep: Sendable, Hashable, Codable, Identifiable {

    /// The instruction, as an imperative in plain words. This is what somebody reads first.
    public let title: String

    /// What to actually do. One or two sentences, no jargon.
    public let whatToDo: String

    /// **Why** — always present. A step somebody understands is a step they can adapt when the
    /// screen in front of them does not match the page.
    public let why: String

    public var id: String { title }

    public init(title: String, whatToDo: String, why: String) {
        self.title = title
        self.whatToDo = whatToDo
        self.why = why
    }
}

// MARK: - One warning

/// Something that will bite, said before it does.
public struct RecoveryWarning: Sendable, Hashable, Codable, Identifiable {

    public let title: String
    public let body: String

    /// ⭐ Marks the one warning that leads the page. Exactly one is true, and it is the FileVault
    /// key: it is the only thing on the page that has to be done **before** anything goes wrong.
    public let mustBeDoneWhileTheMacStillWorks: Bool

    public var id: String { title }

    public init(title: String, body: String, mustBeDoneWhileTheMacStillWorks: Bool = false) {
        self.title = title
        self.body = body
        self.mustBeDoneWhileTheMacStillWorks = mustBeDoneWhileTheMacStillWorks
    }
}

// MARK: - ⭐ A blank the person fills in

/// **A line on the printed page for something written by hand.**
///
/// ⭐ **This type has no value property, and it never will.** That is the enforcement, not the
/// comment: it is structurally impossible for Wellkept to print somebody's FileVault recovery key
/// or their Apple Account password, because there is nowhere in this type to put one. A test walks
/// the type and fails the build if a field that could hold a secret ever appears.
///
/// The app cannot read any of these anyway — nothing unprivileged can read a recovery key. But
/// "cannot" is a fact about today's macOS and "has nowhere to put it" is a fact about this code,
/// and only the second one survives an entitlement being granted later.
public struct RecoveryBlank: Sendable, Hashable, Codable, Identifiable {

    /// What goes on the line: "FileVault recovery key".
    public let label: String

    /// Where to get it, in one sentence — the part people actually get stuck on.
    public let whereToFindIt: String

    /// Roughly how much room the line needs when printed. A recovery key is 28 characters and does
    /// not fit on a line sized for a phone number.
    public let lineLength: Int

    public var id: String { label }

    public init(label: String, whereToFindIt: String, lineLength: Int = 32) {
        self.label = label
        self.whereToFindIt = whereToFindIt
        self.lineLength = lineLength
    }
}

// MARK: - ⭐ The plan

/// **The whole printed page, as data.**
///
/// Nothing here draws anything. A printer, a PDF and a screen all render the same list, and the
/// content is settled in one place so the printed page and the on-screen page cannot say different
/// things — which is the failure mode for exactly this kind of document.
public struct RecoveryPlan: Sendable, Hashable, Codable {

    /// The day this page's contents were made.
    public let writtenOn: Date

    /// ⭐ **The macOS this page was written for.** Migration Assistant refuses a backup made on a
    /// newer macOS than the machine being restored to, so this is the boundary of what the page is
    /// good for, not a footnote.
    public let macOSVersion: String

    /// Which Mac, in the words on the About screen: "MacBook Pro (14-inch, M3, 2024)".
    public let macDescription: String

    /// `nil` when we could not tell which kind of Mac this is.
    public let architecture: MacArchitecture?

    /// Where the backup lives, in the words on the drive: "JDS Backup". `nil` when there is no
    /// backup — in which case the page says so, loudly, rather than pretending.
    public let destinationName: String?

    /// Whether FileVault is on. It decides whether the recovery-key warning leads the page or sits
    /// further down as a "if you ever switch this on" note.
    public let fileVaultOn: Bool

    public let steps: [RecoveryStep]
    public let warnings: [RecoveryWarning]
    public let blanks: [RecoveryBlank]

    public init(writtenOn: Date,
                macOSVersion: String,
                macDescription: String,
                architecture: MacArchitecture?,
                destinationName: String?,
                fileVaultOn: Bool,
                steps: [RecoveryStep],
                warnings: [RecoveryWarning],
                blanks: [RecoveryBlank]) {
        self.writtenOn = writtenOn
        self.macOSVersion = macOSVersion
        self.macDescription = macDescription
        self.architecture = architecture
        self.destinationName = destinationName
        self.fileVaultOn = fileVaultOn
        self.steps = steps
        self.warnings = warnings
        self.blanks = blanks
    }

    // MARK: ── The lifetime ──────────────────────────────────────────────────────────────────────

    /// ⚠️ **Whether this page is out of date and should be reprinted.**
    ///
    /// Any change at all counts, not just a major one. Migration Assistant's rule is "newer than",
    /// and 26.6.2 against 26.6.3 is newer than — so a page that quietly tolerated point releases
    /// would be wrong in exactly the case it exists for. Reprinting is cheap; discovering the
    /// mismatch in Recovery is not.
    public func isStale(currentMacOS: String) -> Bool {
        macOSVersion.trimmingCharacters(in: .whitespaces)
            != currentMacOS.trimmingCharacters(in: .whitespaces)
    }

    /// The line telling somebody to print it again, or `nil` when the page is still current.
    public func reprintLine(currentMacOS: String) -> String? {
        guard isStale(currentMacOS: currentMacOS) else { return nil }
        return """
            Your Recovery Plan was written for macOS \(macOSVersion) and this Mac is now on \
            \(currentMacOS). Print it again — a backup made on a newer macOS cannot be restored \
            onto an older one, and the page says which is which.
            """
    }

    /// The title on the printed page. It names the Mac, because a household with two of them ends
    /// up with two of these.
    public var title: String { "Recovery Plan — \(macDescription)" }

    /// The line under the title. Every fact that dates the page, in one line.
    public var subtitle: String {
        let when = writtenOn.formatted(date: .abbreviated, time: .omitted)
        let kind = architecture?.label ?? "Mac"
        return "Written \(when) · macOS \(macOSVersion) · \(kind)"
    }

    /// ⚠️ The instruction at the very top, above everything.
    public static let printIt = """
        Print this page and keep it somewhere that is not this Mac. On the day you need it, this \
        Mac will not be able to show it to you.
        """

    /// The one warning that has to be acted on today, if there is one.
    public var warningForToday: RecoveryWarning? {
        warnings.first(where: \.mustBeDoneWhileTheMacStillWorks)
    }

    // MARK: ── ⭐ The standard plan ───────────────────────────────────────────────────────────────

    /// **Build the page from what this Mac is.**
    ///
    /// The steps are in the order somebody actually needs them on the worst day, which is not the
    /// order a manual would use:
    ///
    /// 1. **Do not erase the backup drive** goes first because the worst irreversible mistake
    ///    available happens in the first ten minutes, while somebody is trying things.
    /// 2. **Try again** goes second because it is free and it works surprisingly often.
    /// 3. Recovery, the disk password, reinstalling, Migration Assistant, then checking that the
    ///    things people actually restore came back.
    /// 9. **Do not erase the backup for a week** goes last for the same reason step 1 goes first.
    public static func make(macOSVersion: String,
                            macDescription: String,
                            architecture: MacArchitecture?,
                            destinationName: String?,
                            fileVaultOn: Bool,
                            writtenOn: Date = Date()) -> RecoveryPlan {

        let backupName = destinationName ?? "your backup drive"

        let steps: [RecoveryStep] = [
            RecoveryStep(
                title: "Do not erase anything yet.",
                whatToDo: "Leave \(backupName) alone. Do not let any setup screen format it, and do not \"reinitialise\" it when a dialog offers to.",
                why: "It is the only copy of your files. Everything else on this page can be tried again; this cannot."),

            RecoveryStep(
                title: "Try starting the Mac once more.",
                whatToDo: "Hold the power button down for ten seconds until it goes completely dark, let go, wait a few seconds, and press it again.",
                why: "A Mac that will not start is often a Mac that did not finish shutting down. This costs a minute and fixes it more often than anything else on this page."),

            RecoveryStep(
                title: "Start up in Recovery.",
                whatToDo: architecture?.howToReachRecovery ?? MacArchitecture.howToReachRecoveryWhenWeDoNotKnow,
                why: "Recovery is a small copy of macOS that lives on the Mac itself. It is there even when the Mac will not start normally."),

            RecoveryStep(
                title: "Unlock the disk when it asks.",
                whatToDo: fileVaultOn
                    ? "Recovery will ask for the password of an account on this Mac. If no password works, use the FileVault recovery key from the blank at the bottom of this page."
                    : "Recovery may ask for the password of an account on this Mac.",
                why: fileVaultOn
                    ? "FileVault is on, so the disk is encrypted. Without either a password or the recovery key, nothing on the disk can be read by anybody, including you."
                    : "It is checking who you are before it lets you change anything."),

            RecoveryStep(
                title: "Reinstall macOS if you have to.",
                whatToDo: "Choose Reinstall macOS. \(architecture?.whereTheInstallerComesFrom ?? MacArchitecture.whereTheInstallerComesFromWhenWeDoNotKnow) It takes a while and it needs internet.",
                why: "This replaces the system and leaves your files alone. Only erase the disk first if Disk Utility says it cannot be repaired."),

            RecoveryStep(
                title: "Say yes when it offers to transfer your information.",
                whatToDo: "When the Mac restarts and asks whether you want to transfer information, connect \(backupName) and choose \"From a Mac, Time Machine backup, or startup disk\".",
                why: "That is Migration Assistant, and it is how your files come back. If you skip it here you can run it later from Applications ▸ Utilities, but doing it now is simpler."),

            RecoveryStep(
                title: "If Migration Assistant will not accept the backup.",
                whatToDo: "The most likely reason is that the backup was made on a newer macOS than the one you just installed. Let the Mac finish, install any macOS update it offers, then run Migration Assistant again from Applications ▸ Utilities.",
                why: "Migration Assistant refuses a backup made on a newer version of macOS than the Mac it is restoring onto. Updating the Mac first removes the objection."),

            RecoveryStep(
                title: "Check the things that are easy to miss.",
                whatToDo: "Open Mail, Messages and Photos and confirm your things are actually there before you do anything else.",
                why: "Those are the ones a backup is most likely to be missing, and they are the ones nobody checks until months later."),

            RecoveryStep(
                title: "Leave the backup drive alone for a week.",
                whatToDo: "Use the restored Mac normally for a week before you erase \(backupName) or start backing up over it.",
                why: "Something missing usually turns up in the first few days of ordinary use, and by then it is too late if the only copy has been written over."),
        ]

        var warnings: [RecoveryWarning] = []

        if fileVaultOn {
            warnings.append(RecoveryWarning(
                title: "Write your FileVault recovery key down today.",
                body: """
                    FileVault is on, so this disk cannot be read without a password or the recovery \
                    key. macOS 26 no longer keeps that key with Apple — it is in the Passwords app \
                    on this Mac, which is the Mac you will not be able to start. Getting it back \
                    with your Apple ID does not work any more. Open Passwords now, find the \
                    FileVault recovery key, press Show, and copy it onto the line at the bottom of \
                    this page.
                    """,
                mustBeDoneWhileTheMacStillWorks: true))
        } else {
            warnings.append(RecoveryWarning(
                title: "If you ever switch FileVault on, come back and reprint this.",
                body: """
                    FileVault encrypts the disk, and it comes with a recovery key. Since macOS 26 \
                    that key lives in the Passwords app on this Mac rather than with Apple, so it \
                    has to be written down somewhere else while the Mac still works.
                    """))
        }

        warnings.append(RecoveryWarning(
            title: "This page is no use on the Mac it is about.",
            body: RecoveryPlan.printIt))

        if destinationName == nil {
            warnings.append(RecoveryWarning(
                title: "There is no backup for this page to point at.",
                body: """
                    Wellkept could not find a backup of this Mac. Every step below assumes there is \
                    a drive with your files on it. Until there is one, this page can help you start \
                    the Mac up — it cannot get your files back.
                    """))
        }

        warnings.append(RecoveryWarning(
            title: "None of this needs Wellkept.",
            body: """
                Everything on this page is done with macOS's own tools. Wellkept plays no part in \
                getting a Mac working again, and you do not need to install it to use your backup.
                """))

        let blanks: [RecoveryBlank] = [
            RecoveryBlank(
                label: "FileVault recovery key",
                whereToFindIt: "Passwords app ▸ search for \"FileVault\" ▸ press Show. Wellkept cannot read this and never will — write it here by hand.",
                lineLength: 32),
            RecoveryBlank(
                label: "Apple Account email",
                whereToFindIt: "System Settings, at the top. Write the address, not the password.",
                lineLength: 32),
            RecoveryBlank(
                label: "Where the Apple Account password is kept",
                whereToFindIt: "Wherever you actually keep it. Do not write the password here — write where it is.",
                lineLength: 32),
            RecoveryBlank(
                label: "Password for the backup drive, if it is encrypted",
                whereToFindIt: "The one you set when the drive was formatted. Without it the backup cannot be opened.",
                lineLength: 32),
            RecoveryBlank(
                label: "Where the backup drive is kept",
                whereToFindIt: "The drawer, the office, the other house. Whoever is reading this may not be you.",
                lineLength: 40),
            RecoveryBlank(
                label: "Someone who can help, and their number",
                whereToFindIt: "The person you would actually call.",
                lineLength: 40),
        ]

        return RecoveryPlan(writtenOn: writtenOn,
                            macOSVersion: macOSVersion,
                            macDescription: macDescription,
                            architecture: architecture,
                            destinationName: destinationName,
                            fileVaultOn: fileVaultOn,
                            steps: steps,
                            warnings: warnings,
                            blanks: blanks)
    }

    /// The Options block for the row.
    public var detailPairs: [DetailPair] {
        var pairs = [DetailPair("Written", writtenOn.formatted(date: .abbreviated, time: .omitted)),
                     DetailPair("Written for macOS", macOSVersion),
                     DetailPair("This Mac", macDescription),
                     DetailPair("Kind", architecture?.label ?? "Not known"),
                     DetailPair("FileVault", fileVaultOn ? "On" : "Off")]
        pairs.append(DetailPair("Backup named on the page", destinationName ?? "None found"))
        return pairs
    }
}

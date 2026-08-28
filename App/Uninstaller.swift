import AppKit
import Foundation

//  Uninstaller.swift
//  Wellkept — App
//
//  Takes Wellkept off the Mac. Ported from Scout's `App/Uninstaller.swift`, which is the only
//  shipped Developer ID uninstaller in the house.
//
//  Reachable from **Help ▸ Uninstall Wellkept** — DESIGN §10 asks for it by name, and it is the
//  bargain an unsandboxed app makes in exchange for being allowed to read the whole disk.
//
//  ## The order is fixed by macOS, not by taste
//
//  1. **Unregister any background item.** Once the bundle moves, macOS can no longer find it at
//     the path it was registered from, and the Background Task Management row survives — for
//     years, listing an app that is not there, with no way for the user to clear it. Nothing is
//     registered yet, which is why step 1 is currently a comment; it is written as a step anyway
//     so the first helper cannot be added without seeing where it goes.
//  2. **Delete the leftovers.**
//  3. **Trash the bundle last.**
//
//  ⚠️ **NEVER `sfltool resetbtm`.** It is the answer that turns up first in a search, it does
//  clear the stale row, and it does it by resetting the Background Task Management database for
//  **every app on the machine** — every login item and every helper the user has ever approved,
//  silently disabled. It is not a repair, it is collateral damage.
//
//  ## Two things this gets right that a generic uninstaller does not
//
//  **Quarantine belongs to the user.** It holds their own files, so the app does not get to
//  decide. It asks, with two real outcomes and no third option that leaves them buried.
//
//  **Backups are never touched.** The uninstaller says where they are and stops there.

@MainActor
enum Uninstaller {

    /// What the user chose to do with their quarantined items.
    enum QuarantineChoice {
        case restore
        case moveTo(URL)
        /// The user backed out of the whole uninstall.
        case cancelled
    }

    // MARK: - Running it

    /// Ask, then do it.
    static func run() {
        NSApp.activate(ignoringOtherApps: true)

        let entries = StorageManifest.entries()
        let reading = Quarantine.reading()

        // ⚠️ **An unreadable ledger stops the uninstall before it starts.** Wellkept cannot say what
        // is in quarantine, so it cannot get the person's own files out — and removing the app now
        // would leave them in a folder belonging to something that no longer exists. Saying nothing
        // and reporting an empty quarantine is exactly the "never report zero because we could not
        // look" failure, in the one place where zero means somebody's files are unaccounted for.
        if let trouble = reading.trouble, !warnAboutTheRecord(trouble) { return }

        let quarantined = reading.records

        // The quarantine question comes FIRST, before the confirmation — a person deciding whether
        // to remove the app is entitled to know their own files are getting out safely before they
        // agree to anything. Skipped entirely when there is nothing in quarantine.
        var handoverNote: String?
        if !quarantined.isEmpty {
            switch askAboutQuarantine(quarantined) {
            case .cancelled:
                return
            case .restore:
                // ⚠️ **The engine's own sentence, not a reason invented here.** The first version of
                // this branch told every person that anything left behind was left behind "because
                // something is already at the place they came from" — one of seven possible reasons,
                // asserted as though it had been checked. A file on a disk that is not plugged in,
                // or one whose folder could not be made again, got a confident wrong explanation and
                // no way to act on it.
                let report = Quarantine.restore(quarantined)
                var note = report.sentence
                if !report.stuck.isEmpty {
                    note += " They are still in "
                        + StorageManifest.quarantineDirectory().path(percentEncoded: false) + "."
                }
                handoverNote = note
            case .moveTo(let folder):
                let stuck = Quarantine.handOver(quarantined, to: folder)
                let moved = quarantined.count - stuck.count
                let there = folder.path(percentEncoded: false)
                handoverNote = stuck.isEmpty
                    ? (quarantined.count == 1
                       ? "Your quarantined item is in \(there)."
                       : "Your \(quarantined.count) quarantined items are in \(there).")
                    : "\(moved) of \(quarantined.count) moved to \(there). The other "
                      + "\(stuck.count) could not be moved and are still in "
                      + StorageManifest.quarantineDirectory().path(percentEncoded: false) + "."
            }
        }

        guard confirm(entries) else { return }

        unregisterBackgroundItems()

        let survived = StorageManifest.delete(entries)
        // Empty-only, never recursive — see the note on `tidyEmptyFolders`. An emptied quarantine
        // folder left on the disk is litter; a recursive delete of it would be the exact failure
        // the quarantine exists to prevent.
        StorageManifest.tidyEmptyFolders()
        // macOS holds the defaults in memory and writes them back on quit, which would recreate
        // the plist that was just deleted — with `setupFinished` still in it, so a reinstall would
        // skip setup.
        StorageManifest.forgetPreferences()

        let app = Bundle.main.bundleURL
        var trashed = true
        do {
            var trashURL: NSURL?
            try FileManager.default.trashItem(at: app, resultingItemURL: &trashURL)
        } catch {
            trashed = false
        }

        finish(trashed: trashed, at: app, survived: survived,
               left: entries.filter { $0.disposition == .leave }, handoverNote: handoverNote)
    }

    /// Step 1, and it is deliberately empty.
    ///
    /// Wellkept ships no privileged helper, no login item and no menu-bar agent, so there is
    /// nothing registered with `SMAppService` to take back. The step exists so that whoever adds
    /// the first one adds `try? SMAppService.daemon(plistName:).unregister()` **here**, before
    /// anything moves — see the ordering note at the top of this file for what it costs to get
    /// that wrong.
    private static func unregisterBackgroundItems() {}

    // MARK: - What the dialogs say
    //
    // Written once and used twice, so `preview()` cannot drift from the real thing. The wording is
    // the whole design here: it is the last thing a person reads before an action with no undo.

    static func quarantineQuestion(_ records: [QuarantineRecord]) -> (title: String, body: String) {
        let count = records.count
        let title = count == 1
            ? "One of your files is in Wellkept's quarantine"
            : "\(count) of your files are in Wellkept's quarantine"

        return (title, """
            Wellkept set these aside for you and never deleted them. Removing the app should not \
            decide their fate, so pick one:

            Put Them Back returns each item to where it came from. Anything whose old place is \
            now occupied is left alone rather than written over.

            Move Them… puts them all in a folder you choose.
            """)
    }

    static func confirmation(_ entries: [StorageManifest.Entry]) -> (title: String, body: String) {
        var lines = ["Wellkept will move to the Trash. This cannot be undone."]

        let deleting = entries.filter { $0.disposition == .delete }
        if !deleting.isEmpty {
            let inventory = deleting
                .map { "\($0.title.localizedLowercase) (\(StorageManifest.readable($0.bytes)))" }
                .formatted(.list(type: .and))
            // The total is only worth saying when there is more than one figure to add up. With a
            // single item it renders as "check history (4 KB) — 4 KB in all", which is the same
            // number twice and reads as a machine talking.
            let total = deleting.count > 1
                ? " — \(StorageManifest.readable(deleting.reduce(0) { $0 + $1.bytes })) in all"
                : ""
            lines.append("It will also delete \(inventory)\(total).")
        }

        // Named before the button is pressed rather than after, because "will it take my backups"
        // is the question a person asks at exactly this moment.
        if let backups = entries.first(where: { $0.disposition == .leave }) {
            lines.append("Your backups in \(backups.url.path(percentEncoded: false)) are left "
                         + "exactly as they are. Wellkept does not touch them.")
        }

        lines.append("""
            Wellkept cannot switch off the permissions you granted it. \
            \(StorageManifest.permissionsOnlyTheUserCanRemove.formatted(.list(type: .and))) will \
            keep listing Wellkept in System Settings until you remove it there yourself.
            """)

        return ("Remove Wellkept from this Mac?", lines.joined(separator: "\n\n"))
    }

    static func closing(trashed: Bool, at app: URL,
                        survived: [StorageManifest.Entry],
                        left: [StorageManifest.Entry],
                        handoverNote: String?) -> (title: String, body: String) {
        var lines: [String] = []

        if let handoverNote { lines.append(handoverNote) }
        if !trashed {
            lines.append("Drag it there yourself: \(app.path(percentEncoded: false))")
        }
        if !survived.isEmpty {
            let names = survived.map(\.title.localizedLowercase).formatted(.list(type: .and))
            lines.append("Wellkept could not delete its \(names). They are still where they were.")
        }
        if let backups = left.first {
            lines.append("Your backups are still in \(backups.url.path(percentEncoded: false)).")
        }
        lines.append("""
            \(StorageManifest.permissionsOnlyTheUserCanRemove.formatted(.list(type: .and))) still \
            list Wellkept. Open each one and remove it to finish.
            """)

        return (trashed ? "Wellkept is in the Trash" : "Wellkept could not move itself to the Trash",
                lines.joined(separator: "\n\n"))
    }

    // MARK: - Putting them on screen

    /// ⚠️ Told before anything is agreed to, and the destructive button is not the default.
    ///
    /// Returns whether to carry on. Carrying on is allowed — the person may not care, and an app
    /// that refuses to uninstall itself is worse than one that warns — but it is never the quiet
    /// path, and the folder is named so they can go and get their files by hand.
    private static func warnAboutTheRecord(_ trouble: LedgerTrouble) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Wellkept cannot read its record of your set-aside files"
        alert.informativeText = trouble.sentence + "\n\nIf you remove Wellkept now, those files "
            + "stay where they are and nothing will be able to put them back for you. You can open "
            + "that folder and move them yourself first."

        let carryOn = alert.addButton(withTitle: "Remove Wellkept Anyway")
        carryOn.hasDestructiveAction = true
        let stop = alert.addButton(withTitle: "Stop")
        carryOn.keyEquivalent = ""
        stop.keyEquivalent = "\r"

        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func askAboutQuarantine(_ records: [QuarantineRecord]) -> QuarantineChoice {
        let words = quarantineQuestion(records)
        let alert = NSAlert()
        alert.messageText = words.title
        alert.informativeText = words.body
        alert.addButton(withTitle: "Put Them Back")
        alert.addButton(withTitle: "Move Them…")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .restore
        case .alertSecondButtonReturn:
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.prompt = "Move Here"
            panel.message = "Where should Wellkept put your quarantined items?"
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Desktop")
            // Backing out of the folder chooser is not consent to the other option, and it is not
            // consent to uninstall either. Ask again from the top.
            guard panel.runModal() == .OK, let folder = panel.url else {
                return askAboutQuarantine(records)
            }
            return .moveTo(folder)
        default:
            return .cancelled
        }
    }

    private static func confirm(_ entries: [StorageManifest.Entry]) -> Bool {
        let words = confirmation(entries)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = words.title
        alert.informativeText = words.body

        let remove = alert.addButton(withTitle: "Remove Wellkept")
        remove.hasDestructiveAction = true
        let cancel = alert.addButton(withTitle: "Cancel")

        // Return cancels. An uninstaller is the last dialog that should answer itself with the
        // destructive verb.
        remove.keyEquivalent = ""
        cancel.keyEquivalent = "\r"

        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func finish(trashed: Bool, at app: URL,
                               survived: [StorageManifest.Entry],
                               left: [StorageManifest.Entry],
                               handoverNote: String?) {
        let words = closing(trashed: trashed, at: app, survived: survived,
                            left: left, handoverNote: handoverNote)
        let alert = NSAlert()
        alert.messageText = words.title
        alert.informativeText = words.body
        alert.addButton(withTitle: "Open Privacy & Security")
        alert.addButton(withTitle: "Quit")

        if alert.runModal() == .alertFirstButtonReturn {
            SystemSettingsPane.privacyAndSecurity.open()
        }
        NSApp.terminate(nil)
    }

    // MARK: - Reviewing the words without arming the button

    /// What the dialogs would say, and what would be deleted. Deletes nothing.
    ///
    /// The wording is the design, and it should be reviewable without running the thing it
    /// describes. Wire it to a launch argument (`Wellkept --uninstall-preview`) or call it from a
    /// test; either way the strings under review are the strings that ship, because both come from
    /// the same three functions above.
    static func preview() -> String {
        let entries = StorageManifest.entries()
        let reading = Quarantine.reading()
        let quarantined = reading.records
        let ask = confirmation(entries)
        let done = closing(trashed: true, at: Bundle.main.bundleURL, survived: [],
                           left: entries.filter { $0.disposition == .leave },
                           handoverNote: nil)

        var report = "WOULD DELETE\n------------\n"
        let deleting = entries.filter { $0.disposition == .delete }
        if deleting.isEmpty {
            report += "(nothing — Wellkept has written nothing outside its bundle)\n"
        }
        for item in deleting {
            report += item.title.padding(toLength: 22, withPad: " ", startingAt: 0)
            report += StorageManifest.readable(item.bytes).padding(toLength: 10, withPad: " ", startingAt: 0)
            report += "\(item.url.path(percentEncoded: false))\n"
        }
        report += "\(Bundle.main.bundleURL.path(percentEncoded: false)) → Trash\n"

        report += "\nWOULD LEAVE ALONE\n-----------------\n"
        let left = entries.filter { $0.disposition == .leave }
        if left.isEmpty { report += "(no backups recorded)\n" }
        for item in left {
            report += "\(item.title): \(item.url.path(percentEncoded: false))\n"
        }

        report += "\nWOULD ASK ABOUT\n---------------\n"
        if let trouble = reading.trouble {
            report += "THE RECORD CANNOT BE READ — the uninstall stops here.\n\n"
            report += "\(trouble.sentence)\n"
        } else if quarantined.isEmpty {
            report += "(quarantine is empty — the question is skipped)\n"
        } else {
            let words = quarantineQuestion(quarantined)
            report += "\(words.title)\n\n\(words.body)\n"
            report += "\n[ Put Them Back ]   [ Move Them… ]   [ Cancel ]\n"
        }

        report += "\nCONFIRMATION\n------------\n\(ask.title)\n\n\(ask.body)\n"
        report += "\n[ Remove Wellkept ]   [ Cancel ]  ← Cancel is what Return does\n"
        report += "\nCLOSING\n-------\n\(done.title)\n\n\(done.body)\n"
        report += "\n[ Open Privacy & Security ]   [ Quit ]\n"
        return report
    }
}

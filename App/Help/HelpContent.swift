import Foundation
import WellkeptCore

//  HelpContent.swift
//  Wellkept — App/Help
//
//  The help, authored as data so it renders in one consistent browser. Modelled on Lode's
//  `App/Support/HelpContent.swift`.
//
//  ## Why the documentation is in the app rather than on the website
//
//  DESIGN §14.6, and Engst's practice in SetShot: the answer to "how does this work" belongs where
//  the question is asked, it has to be searchable, and its text has to be selectable so somebody
//  can paste a sentence into an email. A help page that lives on stonemesastudio.com is a help
//  page that is unavailable to the one person most likely to need it — someone whose Mac is not
//  well.
//
//  ⚠️ **This never opens itself.** SetShot shows its docs on first launch; Wellkept does not,
//  because its first launch already has a welcome page and a permission to ask for, and a third
//  window on top of those is a wall rather than a welcome. It is one click from the Help menu, and
//  ⌘? from anywhere.
//
//  ## What belongs here
//
//  Three pages, and they are chosen rather than accumulated: what this is, what it will never do,
//  and how to get it off the Mac. The middle one is the reason the other two are short — an
//  unsandboxed app that reads your whole disk is asking for a great deal of trust, and the only
//  currency it has to pay with is a plain, specific list of what it refuses to do.

/// One rendered block. Paragraphs and bullets carry inline markdown (`**bold**`, `*italic*`).
enum HelpBlock: Hashable, Sendable {
    case heading(String)
    case paragraph(String)
    case bullet(String)
    /// A consequence worth setting apart — never a decoration, and never used twice in a row.
    case note(String)

    /// The words, for search. Search has to reach the body of an article, not only its title:
    /// somebody looking for "quarantine" is looking for a sentence, and they do not know which
    /// page it is on. That is the whole reason the content is data.
    var text: String {
        switch self {
        case .heading(let t), .paragraph(let t), .bullet(let t), .note(let t): t
        }
    }
}

struct HelpArticle: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// One line, shown under the title in the list.
    let summary: String
    let blocks: [HelpBlock]

    var searchText: String {
        ([title, summary] + blocks.map(\.text)).joined(separator: "\n")
    }
}

enum HelpLibrary {

    /// The running build, read from the bundle and **never typed into the copy**. A version number
    /// written into a sentence is a version number that is wrong one release later, and nothing
    /// fails when it does.
    ///
    /// Absent is not zero: with no `Info.plist` entry to read — a test host, a stripped bundle —
    /// the line is left out rather than rendered as a half-finished "Version ".
    static var versionLine: String? {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String, !short.isEmpty else {
            return nil
        }
        let build = (info?["CFBundleVersion"] as? String).flatMap { $0.isEmpty ? nil : " (build \($0))" } ?? ""
        return "You are running **version \(short)\(build)**. Quote it if you report a problem — "
             + "it is the first thing anyone will ask."
    }

    /// The seven sections, as bullets, **generated from the vocabulary rather than retyped.**
    ///
    /// The Help menu was the other consumer of the section list in Lode, and it is exactly the
    /// place a rename rots unseen: renaming a section would leave a help page describing one that
    /// no longer exists, and nothing but a reader would notice.
    private static var sectionBullets: [HelpBlock] {
        SectionID.allCases.map { .bullet("**\($0.title)** — \($0.question)") }
    }

    static let all: [HelpArticle] = [

        HelpArticle(
            id: "what-is-wellkept",
            title: "What Wellkept is",
            summary: "A health check for your Mac, and what it looks at.",
            blocks: [
                .paragraph("**Wellkept** is a health check for your Mac, made by **Stone Mesa Studio**. It looks at this machine and tells you what it finds, in plain words. It is free and open source, under the GPL version 3."),
                .paragraph("Seven sections, each named for a question you would actually ask:"),
            ]
            + sectionBullets
            + [
                .heading("How it behaves"),
                .paragraph("**Nothing changes on your Mac unless you press a button.** Wellkept has no schedule, no background scanning and no automatic tidying, and it quits when you close its window. Every section has one button, and one plain sentence above it saying what pressing it will do."),
                .paragraph("**Hardware is read once when the app opens**, because it is read-only — it asks the drive, the battery and the memory what they say about themselves and writes nothing. Every other section waits to be asked. There is no daily check and nothing runs while the app is closed."),
                .paragraph("What it finds is remembered, with the date, so **Overview** can tell you what was checked and when. There is never a score — a number invites you to chase it, and a Mac with nothing wrong would end up graded on how little happened to be installed on it."),
                // ⚠️ DELETE THIS NOTE as each section lands. Hardware is done; the other five are
                // not, and a help page that claims a working Storage scan before there is one is
                // worse than no help page at all.
                .note("**Hardware** is the only section that works in this build. The other five are here and the app looks finished, but they do not check anything yet — their buttons are greyed out and say so."),
            ]
            + (versionLine.map { [HelpBlock.paragraph($0)] } ?? [])),

        HelpArticle(
            id: "never",
            title: "What Wellkept will never do",
            summary: "The promises, specifically.",
            blocks: [
                .paragraph("Wellkept runs outside Apple's sandbox and can read your whole disk. That is the only way to answer the questions it asks, and it is worth being exact about what it does with the privilege."),

                .heading("It never deletes anything"),
                .paragraph("There is no delete. Things Wellkept sets aside go to a **quarantine** you can browse, and you have thirty days to put any of it back. Emptying that quarantine is your decision and nobody else's."),

                .heading("It never touches your own files uninvited"),
                .paragraph("**Machine junk** — caches, logs, old installers, the things your Mac makes for itself and will make again — may arrive pre-selected, because nothing is lost when it goes."),
                .paragraph("**Your own files are never pre-selected.** A large folder is not a problem, it is large. Wellkept's job there is to show you what is taking the room, sorted and sized, and then get out of the way."),

                .heading("It never changes your Mac on a schedule"),
                .paragraph("Automatic means *looking*. Manual means *touching*. Backup is the one exception, and only because a backup that waits to be asked is a backup that does not exist."),

                .heading("Nothing leaves this Mac"),
                .paragraph("There is no account, no sign-in, no analytics and no tracking. The single exception is **checking for updates**: to find out whether a newer version of an app exists, Wellkept has to ask the people who make it, and that necessarily tells them a copy is installed somewhere. That is unavoidable, so it is said here rather than discovered."),

                .heading("It never touches your backups"),
                .paragraph("Not to check them, not to tidy them, and not when you remove the app. Wellkept will tell you where they are and what is not covered by them. It will not write to them."),

                .heading("It is never in your way"),
                .paragraph("It asks for a permission once. If you say no, or say *finish later*, it will not raise it again on its own — the sections simply report what they could see, and say what they could not."),
            ]),

        HelpArticle(
            id: "remove",
            title: "Removing Wellkept",
            summary: "How to take it off, and what survives.",
            blocks: [
                .paragraph("Choose **Help ▸ Uninstall Wellkept**. It asks first, and it tells you what it is about to delete before you agree."),

                .heading("What it deletes"),
                .bullet("Its settings — appearance, text size, and the mark that says setup has run."),
                .bullet("Its record of every check it has run on this Mac."),
                .bullet("Saved window state and caches."),
                .bullet("The app itself, which goes to the Trash."),
                .paragraph("Because the *setup has run* mark goes with everything else, installing Wellkept again later starts you at the welcome page — while an ordinary update leaves you exactly where you were."),

                .heading("What it asks you about"),
                .paragraph("If anything of yours is sitting in **quarantine**, Wellkept stops and asks what should happen to it: put each item back where it came from, or move the lot to a folder you choose. It will not decide that for you, and it will not leave your files buried in a folder the app no longer exists to open."),

                .heading("What it leaves alone"),
                .paragraph("**Your backups.** The uninstaller names the place they are in and stops there."),

                .heading("What you have to finish yourself"),
                .paragraph("macOS does not let an app switch off a permission you granted it — an app that could revoke its own permissions could grant them too. So **Full Disk Access** and **Files and Folders** will keep listing Wellkept in System Settings until you open each one and remove it. The uninstaller offers to take you there."),

                .note("Dragging the app to the Trash by hand works too, but it leaves the settings, the history and anything in quarantine behind. The uninstaller exists so that nothing of Wellkept's outlives it without your say-so."),
            ]),
    ]

    /// Articles matching a search, title and body alike. An empty query is everything.
    ///
    /// Case- and diacritic-insensitive: somebody typing "quarantine" should find a sentence that
    /// begins the word with a capital, and `localizedStandardContains` is the one comparison on
    /// this platform that behaves the way Finder's search behaves.
    static func matching(_ query: String) -> [HelpArticle] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.searchText.localizedStandardContains(trimmed) }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Foundation
import WellkeptCore

//  SelfUpdatingApps.swift
//  Wellkept — App/Support
//
//  **Wellkept's own list of apps that keep themselves up to date.**
//
//  ## Why there is a list here at all, when the other one was declined
//
//  On 2026-08-27 the question was whether Wellkept should ship a hand-maintained list of about
//  fifteen makers' version pages, so the update check could reach apps that publish nothing
//  machine-readable. It was declined, and the reason was the standing maintenance promise:
//
//  > *"I don't know that I want that responsibility. They frequently release updates."*
//
//  That was the right call, and this list is not a way around it. **The difference is what happens
//  when the list is wrong**, and the two cases are not close:
//
//  | | A list of vendor version endpoints | This list |
//  |---|---|---|
//  | How often it goes stale | Constantly — a moved URL, a changed page, a new format | Rarely — an app almost never stops updating itself |
//  | What a stale entry does | Reports a **wrong version**, or none | Labels a row "keeps itself up to date" instead of "cannot be checked" |
//  | Who finds out | The user, from a bad answer | Nobody, because both rows are honest |
//
//  A wrong endpoint tells somebody their current app is out of date, or that an outdated one is
//  fine. A wrong entry here swaps one truthful sentence for another truthful sentence. That is a
//  maintenance burden worth taking, and the one declined is not.
//
//  ## Why not just say "cannot be checked" for all of them
//
//  Because the two sentences carry opposite meanings, and collapsing them makes a well-kept Mac look
//  neglected. Chrome, Firefox, VS Code and Claude are *more* reliably current than most App Store
//  software — they update themselves in the background, usually within a day. Filing them under "we
//  could not tell" would put the best-maintained apps on the Mac into the same bucket as the ones
//  nobody publishes a version for.
//
//  There is a measured reason to keep them out of the comparison entirely, too. **Chrome looks two
//  versions behind on this Mac and is current**: Google ships a staged rollout, so the version at
//  the top of their public list was serving to nobody. Comparing a self-updating app against its
//  publisher's newest announcement is not a check, it is a coin toss.
//
//  ## The rules this list is kept under
//
//  1. **It is ours, and it is short.** Anyone can read the whole thing in under a minute and
//     disagree with an entry. That is the audit story; there is no other one.
//  2. **Bundle identifiers only.** A name match would catch "Firefox Developer Edition" by accident
//     and miss an app somebody renamed.
//  3. **An entry earns its place by shipping an updater the user cannot easily switch off** —
//     Google Update, Mozilla's updater, Squirrel, Electron's auto-updater. "Has a Check for Updates
//     menu item" is not enough: that is a person remembering, not an app updating itself.
//  4. **When in doubt, leave it out.** The default answer, `UpdateUnknown.noSourceToAsk`, is honest.
//     A wrong entry here is cheap but it is not free.
//  5. **Wellkept is not on this list**, and must never be. It does not update itself: it checks, and
//     asks. See `App/Onboarding/WelcomeView.swift` — this is the second of the two things the app
//     ever sends anywhere, and it is disclosed and switchable like the first.

/// The apps Wellkept knows update themselves, and the answer it gives for them.
///
/// The one thing the rest of the app should call is ``standing(forBundleID:)``.
enum SelfUpdatingApps {

    /// One entry, kept as a record rather than a bare string so the reason for it travels with it.
    /// A future reader deciding whether to drop an entry needs to know why somebody added it.
    struct Entry: Sendable, Hashable {
        /// The bundle identifier, lower-cased for comparison.
        let bundleID: String
        /// What the app is called, so the list reads as a list of apps.
        let name: String
        /// The mechanism that does the updating. This is the field that justifies the entry.
        let updater: String
    }

    /// **The whole list.** Alphabetical by name, so an addition goes in an obvious place and a
    /// duplicate is visible on sight.
    ///
    /// Fifteen entries as of 2026-08-27, chosen under rule 4 — every one of them is an app whose
    /// updater is switched on out of the box and whose identifier is not in dispute. Several
    /// obvious candidates were left off for want of a bundle identifier somebody had actually
    /// checked. If this ever needs a hundred entries, the approach was wrong and the conversation to
    /// have is with the developer, not a hundredth line.
    static let entries: [Entry] = [
        Entry(bundleID: "com.brave.Browser",             name: "Brave",              updater: "Sparkle, on by default"),
        Entry(bundleID: "com.anthropic.claudefordesktop", name: "Claude",            updater: "Electron's auto-updater"),
        Entry(bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor",             updater: "Electron's auto-updater"),
        Entry(bundleID: "com.discordapp.Discord",        name: "Discord",            updater: "Electron's auto-updater"),
        Entry(bundleID: "com.docker.docker",             name: "Docker Desktop",     updater: "Docker's own updater"),
        Entry(bundleID: "com.figma.Desktop",             name: "Figma",              updater: "Electron's auto-updater"),
        Entry(bundleID: "org.mozilla.firefox",           name: "Firefox",            updater: "Mozilla's background updater"),
        Entry(bundleID: "com.google.Chrome",             name: "Google Chrome",      updater: "Google Update — a staged rollout, which is why it is never compared"),
        Entry(bundleID: "com.microsoft.edgemac",         name: "Microsoft Edge",     updater: "Microsoft AutoUpdate"),
        Entry(bundleID: "notion.id",                     name: "Notion",             updater: "Electron's auto-updater"),
        Entry(bundleID: "com.obsproject.obs-studio",     name: "OBS Studio",         updater: "Sparkle, on by default"),
        Entry(bundleID: "com.raycast.macos",             name: "Raycast",            updater: "Raycast's own updater"),
        Entry(bundleID: "com.tinyspeck.slackmacgap",     name: "Slack",              updater: "Squirrel"),
        Entry(bundleID: "com.microsoft.VSCode",          name: "Visual Studio Code", updater: "Squirrel"),
        Entry(bundleID: "us.zoom.xos",                   name: "Zoom",               updater: "Zoom's own updater"),
    ]

    /// Bundle identifiers, lower-cased, for the one lookup this file exists to answer.
    ///
    /// Built once. Nineteen string comparisons would be cheap enough, but this runs once per app in
    /// a loop that already takes seven seconds, and a set costs nothing to be correct about.
    private static let identifiers: Set<String> = Set(entries.map { $0.bundleID.lowercased() })

    /// Whether this app is one of the ones we know updates itself.
    ///
    /// Case-insensitive: bundle identifiers are conventionally lower-case and are compared
    /// case-insensitively by macOS, and an app that capitalised one would otherwise slip the list.
    static func isSelfUpdating(bundleID: String) -> Bool {
        identifiers.contains(bundleID.lowercased())
    }

    /// The entry, for a view that wants to name the updater in Options.
    static func entry(forBundleID bundleID: String) -> Entry? {
        let key = bundleID.lowercased()
        return entries.first { $0.bundleID.lowercased() == key }
    }

    /// **The answer for an app on this list**, or `nil` for an app that is not on it.
    ///
    /// ⚠️ `nil` means "this file has nothing to say", not "it cannot be checked". The caller decides
    /// what to do next — usually try the App Store, and otherwise report
    /// `UpdateUnknown.noSourceToAsk`. Returning a `.couldNotTell` from here would let this file's
    /// silence look like a finding.
    static func standing(forBundleID bundleID: String) -> UpdateStanding? {
        isSelfUpdating(bundleID: bundleID) ? .keepsItselfUpToDate : nil
    }
}

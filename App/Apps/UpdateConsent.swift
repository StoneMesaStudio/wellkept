// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import Observation
import SwiftUI
import WellkeptCore

//  UpdateConsent.swift
//  Wellkept — App/Apps
//
//  ⭐ **The one question this app asks before anything about this Mac leaves it.**
//
//  Checking whether an app is current is the only thing the Apps section does that reaches off the
//  machine. The instruction on 2026-08-27 was **inform and consent**:
//
//  > *"Information leaving the computer to benefit their experience and app functionality is
//  > disclosed and optional, but just like not granting whole disc access, you lose functionality.
//  > Inform and consent."*
//
//  So it is neither silently on nor buried in Settings. The first time somebody presses **Check
//  apps**, the section says what checking involves — that we ask Apple's storefront what the
//  current version of an app is, and that asking necessarily tells them a copy is installed
//  somewhere — and offers to do it or not. The answer is remembered. It lives in Settings
//  afterwards, and it can be changed there for ever.
//
//  ## ⚠️ Three states, not two, and the third one is the whole point
//
//  The stored key is an **optional** `Bool`, and *absent* is a real answer meaning **nobody has been
//  asked yet**. Reading a missing key with `UserDefaults.bool(forKey:)` returns `false`, which looks
//  safe and is in fact the bug: it makes "we have not asked" indistinguishable from "you said no",
//  so the ask never happens and the feature quietly never works. Reading it as `true` is the
//  opposite bug and a far worse one — it turns inform-and-consent into a default nobody was told
//  about, which is the exact thing this file exists to prevent.
//
//  `UserDefaults.object(forKey:) as? Bool` is the only correct read, and it is written once, here.
//
//  ## ⚠️ Not one sentence about privacy is written in this file
//
//  They all come from `Privacy.Departure.appUpdateCheck` in `WellkeptCore`, which is the register of
//  everything that leaves this Mac. The welcome page, Help, Settings and this sheet therefore make
//  **one** promise rather than four that drift. The framing around them — the question, the two
//  verbs, the line saying it can be changed later — is this screen's own, because it is about this
//  screen and not about privacy.
//
//  ## What "no" costs, exactly
//
//  Every app's line reads **"Not checked"**. Not "could not tell", which is a different sentence
//  about a different situation — see `UpdateStanding.notChecked`. The rest of the section is
//  untouched: the inventory, the sizes, the origins, the architectures, the macOS row, the crash
//  history and the leftovers all work identically, because none of them leaves the Mac.
//
//  ⚠️ **A "no" withholds the answer, not merely the network.** Two of the sources — the list of
//  apps that update themselves, and Homebrew's local metadata — need no network at all, and it is
//  tempting to keep answering from those. We do not, because the sentence already shipped to the
//  user in `Privacy.Departure.appUpdateCheck.cost` says the section "does not know whether any of
//  them is current". Splitting the answer by which fact happened to need a request is a distinction
//  nobody consented to and nobody could predict from the switch's own words.

// MARK: - The answer, and where it lives

/// Whether Wellkept may ask anybody whether an app has a newer version.
enum UpdateConsent {

    /// The three states. **`notAsked` is not a synonym for `declined`.**
    enum Answer: Sendable, Hashable, CaseIterable {
        /// Nobody has been asked. The first press of **Check apps** puts the question on screen.
        case notAsked
        /// Yes — ask, and tell me what you find.
        case allowed
        /// No. Every app's line reads "Not checked", and nothing about this Mac is named to anybody.
        case declined

        /// For Settings, which draws this as one switch and has no third position.
        var isAllowed: Bool { self == .allowed }
    }

    /// The stored key, taken from the privacy register rather than typed here.
    ///
    /// ⚠️ Never write the literal `"checkAppUpdates"` anywhere. The key is a fact about a
    /// `Privacy.Departure`, and a second copy of it is a second thing to keep in step.
    static var key: String { Privacy.Departure.appUpdateCheck.settingsKey }

    /// The departure this consent is about — the register entry, for any screen that wants to quote
    /// it rather than paraphrase it.
    static var departure: Privacy.Departure { .appUpdateCheck }

    /// **The only correct read of the key.**
    ///
    /// `object(forKey:) as? Bool` rather than `bool(forKey:)`, because the absence of the key is one
    /// of the three answers and `bool(forKey:)` cannot express it.
    static func read(from store: UserDefaults) -> Answer {
        guard let stored = store.object(forKey: key) as? Bool else { return .notAsked }
        return stored ? .allowed : .declined
    }

    /// Write the answer back. `notAsked` genuinely removes the key, so "ask me again" is a state the
    /// app can return to rather than a fourth value nothing understands.
    static func write(_ answer: Answer, to store: UserDefaults) {
        switch answer {
        case .notAsked: store.removeObject(forKey: key)
        case .allowed:  store.set(true, forKey: key)
        case .declined: store.set(false, forKey: key)
        }
    }
}

// MARK: - The words on the sheet

extension UpdateConsent {

    /// The framing this screen owns. Everything about privacy comes from `Privacy.Departure`.
    enum Words {

        /// The question, as a question. A person can answer it without reading the rest.
        static let title = String(localized: "Should Wellkept check whether your apps are current?")

        /// One line of framing, above the register's own sentences.
        ///
        /// It says the two things a person needs before deciding: that this is the only part of the
        /// section that reaches off the Mac, and that everything else works either way.
        static let intro = String(localized: """
            This is the only part of Wellkept that asks anybody anything. Everything else in this \
            section is read from this Mac.
            """)

        /// Said whichever way they answer, because a decision that feels permanent is a decision
        /// people avoid making.
        static let changeable = String(localized: """
            You can change this later in Settings, as often as you like.
            """)

        /// Yes. Prominent, because a person who has read the page and wants the feature should not
        /// have to hunt for the button.
        static let allowVerb = String(localized: "Check for updates")

        /// No. Plain wording, no guilt, no "not now" — "not now" is a promise to nag.
        static let declineVerb = String(localized: "Don't check")

        /// **Exactly how many apps would be named, on this Mac, today.**
        ///
        /// The abstract version of this disclosure is "a small number of makers". The useful version
        /// is a number the person can weigh, and it is knowable — the inventory has already run by
        /// the time this sheet appears. `nil` where the count is not known, in which case the line
        /// is left out rather than padded with a guess.
        static func scope(appCount: Int?) -> String? {
            guard let appCount else { return nil }
            switch appCount {
            case 0:
                return String(localized: """
                    On this Mac, nothing would be sent: none of the apps installed here publishes a \
                    version we can ask about.
                    """)
            case 1:
                return String(localized: """
                    On this Mac that means naming one app to Apple's App Store, and nothing else.
                    """)
            default:
                return String(localized: """
                    On this Mac that means naming \(appCount) apps to Apple's App Store, and \
                    nothing else.
                    """)
            }
        }

        /// The two register sentences, in the order they have to be read: what goes out, then what
        /// saying no costs.
        static var registerLines: [DetailPair] { UpdateConsent.departure.detailPairs }
    }
}

// MARK: - The stored answer, for the window

/// The consent answer, as something a view can watch.
///
/// ⚠️ **Owned above `AppearanceHost`, like everything else that must survive a text-size change.**
/// A ⌘+ press re-identifies the whole content tree and throws away every `@State` beneath it; a
/// consent sheet held in a `@State` inside the Apps face would vanish mid-question the first time
/// somebody made the text bigger to read it.
@MainActor
@Observable
final class UpdateConsentStore {

    /// The answer as it stands. Mirrored into a stored property so SwiftUI can see it change —
    /// `UserDefaults` on its own is invisible to observation.
    private(set) var answer: UpdateConsent.Answer

    @ObservationIgnored private let store: UserDefaults

    init(store: UserDefaults = .standard) {
        self.store = store
        answer = UpdateConsent.read(from: store)
    }

    /// Whether this run may ask anybody anything.
    var isAllowed: Bool { answer.isAllowed }

    /// Whether the question has ever been put. `false` is what makes the sheet appear on the first
    /// press of **Check apps**, and nothing else in the app should infer it from the boolean.
    var hasBeenAsked: Bool { answer != .notAsked }

    func allow() { set(.allowed) }
    func decline() { set(.declined) }

    /// For the Settings switch, which has two positions and no memory of the third.
    func setAllowed(_ allowed: Bool) { set(allowed ? .allowed : .declined) }

    /// Put the app back to never-having-asked. Used by the uninstaller and by tests; there is no
    /// button for it, because a person who wants to be asked again can simply use the switch.
    func forget() { set(.notAsked) }

    /// Re-read the key, for the case where Settings and the section are both on screen.
    func refresh() { answer = UpdateConsent.read(from: store) }

    private func set(_ new: UpdateConsent.Answer) {
        UpdateConsent.write(new, to: store)
        answer = new
    }
}

// MARK: - The sheet

/// **The ask.** One question, the register's two sentences, two buttons.
///
/// It is a sheet rather than a page in the setup flow on purpose. Setup happens before anybody has
/// seen the Apps section, and a question about app updates asked there is a question with no
/// context — the answer people give to a question they do not understand yet is "no", permanently.
/// Asked on the first press of **Check apps**, it is a question about the thing they just pressed.
///
/// ⚠️ **It scrolls, and the buttons do not.** The sheet is a fixed size and the text scale goes to
/// 200%; a fixed-height page whose content has grown is how a Continue button ends up below the fold
/// with nothing to say it is there. That bug has already been fixed once, on the welcome page.
struct UpdateConsentAsk: View {

    /// How many apps would actually be named, if the answer is yes. `nil` where it is not known.
    var storeAppCount: Int?

    /// Yes.
    var onAllow: () -> Void
    /// No.
    var onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.block) {
            Text(UpdateConsent.Words.title)
                .font(.appTitle)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            StableScrollView {
                VStack(alignment: .leading, spacing: Space.section) {
                    Text(UpdateConsent.Words.intro)
                        .font(.appBody)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // The register's own sentences: what leaves, then what saying no costs. Quoted,
                    // never paraphrased — see the file header.
                    ForEach(UpdateConsent.Words.registerLines) { pair in
                        VStack(alignment: .leading, spacing: Space.hairline) {
                            Text(pair.label)
                                .font(.appHeadline)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(pair.value)
                                .font(.appBody)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let scope = UpdateConsent.Words.scope(appCount: storeAppCount) {
                        Text(scope)
                            .font(.appBody)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text(UpdateConsent.Words.changeable)
                        .font(.appCallout)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.bottom, Space.block)
            }

            HStack(spacing: Space.gutter) {
                Spacer(minLength: 0)
                // "No" first, in reading order, so the affirmative is not the one under the cursor.
                Button(UpdateConsent.Words.declineVerb, action: onDecline)
                    .buttonStyle(.app)
                    .controlSize(.large)
                Button(UpdateConsent.Words.allowVerb, action: onAllow)
                    .buttonStyle(.appProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.page)
        .frame(width: SheetMetrics.width(560), height: SheetMetrics.height(440))
        .pageGround()
    }
}

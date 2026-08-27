import Foundation
import WellkeptCore

//  MacOSRow.swift
//  Wellkept — App/Sections/Apps
//
//  **The `.macOS` row: what this Mac is running, and nothing about what it might be missing.**
//
//  `MacOSUpdateState` is read by `UpdateReader.swift` and knows how to describe itself. This file
//  is the seam that turns it into an `AppsRow`, and it exists for one reason: nobody else may.
//
//  ## ⚠️ This row never asks Apple anything
//
//  Every value behind it comes off this Mac's own disk — `SystemVersion.plist` for the version,
//  `com.apple.SoftwareUpdate.plist` for the settings and the history. Wellkept does not contact
//  Apple's update servers, and it must not: the one thing in this section that reaches off the Mac
//  is the app-version check, which is disclosed and switchable, and quietly adding a second would
//  make that disclosure a lie.
//
//  Which is why `MacOSUpdateState.waitingCaveat` is printed **on the row** rather than behind
//  Options. A dated list of updates already installed reads, to anybody skimming, as a statement
//  about right now — and "macOS is up to date" is exactly the sentence this row is not entitled to
//  say. Software Update can answer that question; we can only say what has already happened here.

enum MacOSRow {

    /// The row.
    ///
    /// ⚠️ **The settings being unreadable does not make the row unreadable.** We still know which
    /// version is running, which is the row's headline and most of its value — so the row stands and
    /// says the settings half is missing. Collapsing it to the house refusal sentence would throw
    /// away a fact we have in order to report one we do not.
    static func row(_ state: MacOSUpdateState) -> AppsRow {
        guard state.productVersion != nil else {
            // Nothing at all. `SystemVersion.plist` is world-readable on every Mac, so this means
            // something far more broken than a missed update — and `.notReported` rather than a
            // refusal, because no permission on earth would change the answer.
            return AppsRow.unreadable(.macOS,
                                      .notReported,
                                      about: "The version of macOS",
                                      reason: MacOSUpdateState.waitingCaveat,
                                      details: state.detailPairs)
        }

        return AppsRow(topic: .macOS,
                       headline: state.headline,
                       measure: state.productVersion,
                       reason: reason(state),
                       details: state.detailPairs)
    }

    /// Why the row says what it says: what has already happened here, whether the settings could be
    /// read, and the caveat that keeps the past tense from reading as the present.
    static func reason(_ state: MacOSUpdateState) -> String {
        var parts: [String] = []

        if let history = state.installHistorySentence {
            parts.append(history)
        }

        if state.unreadable != nil {
            parts.append("This Mac's update settings could not be read, so what installs on its "
                       + "own is not shown here.")
        } else if state.managed {
            parts.append("Some of these settings are fixed by whoever manages this Mac rather than "
                       + "by this Mac's own preferences.")
        }

        // Always last, and always present. See the file header.
        parts.append(MacOSUpdateState.waitingCaveat)
        return parts.joined(separator: " ")
    }
}

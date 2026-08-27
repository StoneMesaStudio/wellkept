import SwiftUI
import WellkeptCore

//  InstalledAppsList.swift
//  Wellkept — App/Sections/Apps
//
//  **Every app on this Mac, one line each, searchable.**
//
//  This is the densest thing in the product. On a Mac with 200 apps it has to stay readable and it
//  has to stay fast, and those two pull in opposite directions — so both are decided here rather
//  than left to whichever screen draws it.
//
//  ## ⚠️ Four facts on the line, and the fifth line is where a list stops being read
//
//  Name, version, who signed it, and whether it is current. Those are the four a person is actually
//  asking about. Size, build, architecture, identifier and dates are all real and all belong behind
//  **Options** — `InstalledApp.detailPairs` already carries them. A line with eight facts on it is a
//  line nobody reads, and the failure is invisible because the screen still looks full.
//
//  The two exceptions are **"Built for Intel only"** and **"Last opened"**, which sit on a quiet
//  third line as plain labelled facts. Both are ruled on in `APPS-QUESTIONS.md`:
//
//  - **Intel-only is never coloured, never a countdown, and never says "will stop working."**
//    Nothing about a Rosetta app is a security matter, macOS 26.4 already warns at launch, and only
//    the developer can act. This deliberately cuts the other way from Hardware's ruling on security
//    updates, and the reason is that the two facts are not alike.
//  - **"Last opened" is blank for 6 of the 31 apps on the measured Mac, including Keynote and
//    Teams, both demonstrably run.** So a blank is harmless and expected, and "apps you have not
//    opened" is not a finding anywhere in this app.
//
//  ## ⚠️ Why this is not behind Options
//
//  DESIGN's rule is hide detail, never hide capability. The list *is* the section — everything else
//  on the screen is a sentence about it — and a disclosure over the thing the section exists to
//  show would be hiding the capability and keeping the summary.
//
//  ## Speed
//
//  `LazyVStack`, so 200 rows cost what is on screen rather than 200 rows of layout, and the filter
//  is a single lower-cased pass over four fields. The search term lives on `AppsModel`, above
//  `AppearanceHost`, so a ⌘+ press does not empty a field somebody was typing into.

// MARK: - The list

struct InstalledAppsList: View {
    let apps: [InstalledApp]
    /// The search field's text. A binding rather than local state — see the file header.
    @Binding var searchText: String

    /// Alphabetical, case- and diacritic-insensitively, so "Ábaco" and "iTerm" land where a person
    /// looks for them rather than where their code points fall.
    private var sorted: [InstalledApp] {
        apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var shown: [InstalledApp] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return sorted }
        return sorted.filter { Self.matches($0, term) }
    }

    /// What a search looks at: the name, the identifier, the signer, and the version.
    ///
    /// ⚠️ **Not the update standing.** Typing "current" would then match every app that is, which
    /// looks like a filter and is not one — the standing is a sentence, and matching prose is how a
    /// search quietly returns the wrong set.
    static func matches(_ app: InstalledApp, _ term: String) -> Bool {
        let fields = [app.name, app.bundleID, app.signedBy.name ?? "", app.version ?? ""]
        return fields.contains { $0.localizedCaseInsensitiveContains(term) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.block) {
            HStack(alignment: .firstTextBaseline, spacing: Space.gutter) {
                Text("Every app on this Mac")
                    .font(.appHeadline)
                Spacer(minLength: Space.row)
                Text(countSentence)
                    .font(.appCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            AppSearchField(text: $searchText)

            if shown.isEmpty {
                InlineEmptyNote(symbol: "magnifyingglass",
                                text: apps.isEmpty
                                    ? "No apps were found in the folders apps live in."
                                    : "Nothing here matches “\(searchText)”.")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, app in
                        AppLine(app: app, index: index)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "31 apps" or "Showing 4 of 31".
    ///
    /// ⚠️ The denominator is on screen whenever a filter is. A count of matches with the total
    /// hidden is the one number on this page somebody could read as "you have four apps".
    private var countSentence: String {
        let total = apps.count
        guard shown.count != total else {
            return total == 1 ? "1 app" : "\(total) apps"
        }
        return "Showing \(shown.count) of \(total)"
    }
}

// MARK: - One app's line

/// One app: name and standing on the first line, version and signer on the second, the two labelled
/// facts on a third where there is anything to say.
struct AppLine: View {
    let app: InstalledApp
    let index: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.gutter) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.appCallout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                Text(secondLine)
                    .font(.appCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let third = thirdLine {
                    Text(third)
                        .font(.appCaption)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: Space.row)

            // ⚠️ **Never coloured, in any of the five states.** `UpdateStanding` has no "outdated"
            // and this section cannot go amber; a version behind is a fact, not a fault. The one
            // difference in ink is the grey on "we could not tell", which is the absence of an
            // answer rather than a worse one.
            Text(app.update.label)
                .font(.appCaption)
                .foregroundStyle(app.update.wasChecked || app.update == .keepsItselfUpToDate
                                 ? Theme.textSecondary
                                 : Theme.textTertiary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: AppFont.pt(190), alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appRow(index, compact: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenLabel)
    }

    /// Version and who signed it. **Signed, never verified** — `SignedBy` has no case that means
    /// "verified" and this line must never imply one.
    private var secondLine: String {
        var parts = ["Version \(app.versionText)"]
        if let signer = app.signedBy.name {
            parts.append("Signed by \(signer)")
        } else if case .notSigned = app.signedBy {
            parts.append("Not signed")
        }
        parts.append(app.origin.label)
        return parts.joined(separator: " · ")
    }

    /// The two labelled facts, where there is anything to say. `nil` on most apps, which is right.
    private var thirdLine: String? {
        var parts: [String] = []
        // Plain, labelled, never a countdown. See the file header.
        if app.architecture == .intelOnly {
            parts.append("Built for Intel only")
        }
        if let opened = app.lastOpenedAt {
            parts.append("Last opened \(opened.formatted(date: .abbreviated, time: .omitted))")
        }
        if app.addedByHand {
            parts.append("macOS does not list this app")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// What a screen reader gets: the same facts, as a sentence, in the same order.
    private var spokenLabel: String {
        [app.name, secondLine, thirdLine, app.update.label]
            .compactMap { $0 }
            .joined(separator: ". ")
    }
}

// MARK: - The search field

/// A search field in the app's own face.
///
/// ⚠️ Not `.textFieldStyle(.roundedBorder)`. That box is drawn by AppKit, which hardcodes the system
/// font at the current control size and drops the environment font entirely — the same reason
/// `Controls.swift` replaces the bordered buttons. `.plain` is drawn by SwiftUI and honours
/// `.appBody`, so the field grows with the app's text size along with everything beside it.
struct AppSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: Space.row) {
            Image(systemName: "magnifyingglass")
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)

            TextField("Search apps", text: $text)
                .textFieldStyle(.plain)
                .font(.appCallout)
                // The prompt is the label, so a screen reader is not told "Search apps, Search
                // apps" — but it must still have one when the field has text in it.
                .accessibilityLabel("Search apps")

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.appCallout)
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, Space.block)
        .padding(.vertical, AppFont.pt(6))
        .background(Theme.stripe, in: Radius.shape(Radius.control))
        .overlay {
            Radius.shape(Radius.control)
                .strokeBorder(Theme.hairlineInk, lineWidth: Hairline.thin)
        }
    }
}

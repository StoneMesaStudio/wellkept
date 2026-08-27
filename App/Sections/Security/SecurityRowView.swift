import SwiftUI
import WellkeptCore

//  SecurityRowView.swift
//  Wellkept — App/Sections/Security
//
//  **One row of the six, the concerns it raised, and the label-above-value pairs behind Options.**
//
//  The same shape as `ReadingRow` in Hardware, and deliberately so: a person who has learned one
//  panel has learned both. Topic and status, the sentence, the figure, the reason. That is the
//  whole row on a Mac with nothing wrong.
//
//  ## What is different here: the row can name what it found
//
//  A Hardware row is one reading, so its headline *is* the finding. A Security row can raise up to
//  nine named conditions at once, and its headline is a count — "2 of these protections are worth
//  a look." Left there, the row would be a number with no content. So each concern is drawn
//  underneath, in the words `SecurityConcern` already owns: what is true, why it is worth a look,
//  and the one button that opens the pane which can change it.
//
//  ## ⚠️ Three rules this file cannot bend
//
//  1. **The row's colour comes from `SecurityRow.severity`, which is computed from the concerns.**
//     There is no way to paint a row amber from here, and that is the point — six readers written
//     in parallel would otherwise have arrived with twenty conditions between them.
//  2. **Nothing in Security is `.problem`.** All nine concerns are `.attention`, so the strongest
//     colour this screen can take is amber. That is enforced in `SecurityConcern`, not here.
//  3. **A button only where there is somewhere to send someone.** The pane comes from the block's
//     own `Protection.settingsPane`, which `Protection.init` already drops on a switch an
//     organisation set. So a managed Mac loses its buttons without this file knowing anything about
//     management — a button that cannot work is worse than no button.

// MARK: - One of the six rows

struct SecurityRowView: View {
    let row: SecurityRow
    let index: Int
    /// Where the concern buttons find their pane. The row itself carries no pane for a concern —
    /// only the block knows which switch is which, and whether an organisation set it.
    var block: ProtectionsBlock?

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.hairline) {
            HStack(alignment: .firstTextBaseline, spacing: Space.row) {
                Text(row.topic.label)
                    .font(.appHeadline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.row)
                StatusChip(status: row.status)
            }

            // The answer. A row we could not read carries the house sentence in supporting ink
            // rather than in a colour: "we did not look" is the absence of an answer, and a hue
            // would make it read as one.
            Text(row.headline)
                .font(.appBody)
                .foregroundStyle(headlineInk)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)

            // `SecurityRow.init` guarantees there is no figure on a row we could not read, which is
            // the rule against reporting a zero we never measured — enforced somewhere other than
            // here.
            //
            // ⚠️ **Never coloured, which is where this differs from Hardware on purpose.** A
            // Hardware measure is the finding — "macOS closed 3 running programs" — so the amber 3
            // is the answer. Every measure in Security is an inventory count instead: "7 of 8
            // read", "5 apps", "12 days". Painting those amber would say the count is the thing
            // that is wrong, and on the protections row it would put a warning colour on the number
            // of switches we successfully read.
            if let measure = row.measure {
                Figure(measure, size: 20, weight: .semibold)
                    .padding(.top, 2)
            }

            if let reason = row.reason {
                Text(reason)
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 2)
            }

            // What was actually found, named. Never behind a disclosure: a flagged row whose
            // content is hidden is an accusation the person cannot examine.
            if !row.concerns.isEmpty {
                VStack(alignment: .leading, spacing: Space.block) {
                    ForEach(row.concerns) { concern in
                        ConcernView(concern: concern, pane: pane(for: concern))
                    }
                }
                .padding(.top, Space.row)
            }

            // ⚠️ Only a row that was **refused, and could be un-refused**, gets this button.
            // `SecurityRow.init` drops a remedy on any other kind of row, so there is no
            // arrangement of this view that offers a door with no room behind it. The log read on a
            // standard account is the case that proves it: no permission would help, so that row
            // says so and offers nothing.
            if let remedy = row.remedy {
                Button(remedy.title) { open(remedy.settingsPane) }
                    .buttonStyle(.app)
                    .controlSize(.small)
                    .padding(.top, Space.hairline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appRow(index)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(row.topic.label), \(row.status.label)")
    }

    /// The row's own colour, where there is something worth a look.
    ///
    /// `.information` resolves to `.primary` rather than to a hue — a revealed fact is not a fault.
    private var headlineInk: Color {
        if row.unreadable != nil { return Theme.textSecondary }
        return row.severity >= .attention ? palette.color(for: row.severity) : Color.primary
    }

    /// Which System Settings pane can change this, if any.
    private func pane(for concern: SecurityConcern) -> SystemSettingsPane? {
        guard let kind = concern.protection,
              let raw = block?.protection(kind)?.settingsPane
        else { return nil }
        return SystemSettingsPane(rawValue: raw)
    }

    @MainActor private func open(_ raw: String?) {
        guard let raw, let pane = SystemSettingsPane(rawValue: raw) else { return }
        pane.open()
    }
}

// MARK: - One named condition

/// One of the nine, in the words it owns, with the one button that leads somewhere.
///
/// ⚠️ **No imperatives.** `SecurityConcern.title` and `.explanation` state what is true and why it
/// is worth knowing; neither says "you should". The button is an offer to open the pane, not
/// advice about what to do once it is open. The single exception in this whole section is the
/// FileVault recovery-key sentence, which arrives inside the row's own reason.
struct ConcernView: View {
    let concern: SecurityConcern
    var pane: SystemSettingsPane?

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    var body: some View {
        let tint = palette.color(for: concern.severity)

        VStack(alignment: .leading, spacing: Space.row) {
            // ⚠️ **No severity tag here, and that is deliberate.** The row above already carries a
            // "Needs attention" chip, and every one of the nine conditions is the same severity —
            // so a tag on each block would repeat the row's own word once per finding and tell
            // nobody anything. DESIGN §8: never say the same thing twice on one screen. The colour
            // is carried by the wash and, under Differentiate Without Color, by the border.
            Text(concern.title)
                .font(.appHeadline)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(concern.explanation)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let pane {
                Button(Self.words(for: pane)) { pane.open() }
                    .buttonStyle(.app)
                    .controlSize(.small)
            }
        }
        .padding(Space.block)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: Radius.shape(Radius.control))
        // The border is the second channel: under Differentiate Without Color the wash says
        // nothing at all, and this block has to keep reading as a finding rather than as a card.
        .overlay {
            Radius.shape(Radius.control)
                .strokeBorder(tint.opacity(differentiate ? 0.85 : 0.30),
                              lineWidth: differentiate ? Hairline.selection : Hairline.thin)
        }
        .accessibilityElement(children: .contain)
        // The severity is spoken here because the tag was dropped from the block. A colour a
        // screen reader cannot see is not a channel at all.
        .accessibilityLabel("\(concern.severity.label): \(concern.title)")
    }

    /// The button's words. It names where it goes, because a button called "Fix" on a screen that
    /// changes nothing would be a lie about what this app does.
    static func words(for pane: SystemSettingsPane) -> String {
        switch pane {
        case .fileVault:          "Open FileVault settings…"
        case .firewall:           "Open Firewall settings…"
        case .softwareUpdate:     "Open Software Update…"
        case .usersAndGroups:     "Open Users & Groups…"
        case .fullDiskAccess:     "Open Full Disk Access…"
        case .filesAndFolders:    "Open Files & Folders…"
        case .removableVolumes:   "Open Removable Volumes…"
        case .privacyAndSecurity: "Open Privacy & Security…"
        }
    }
}

// MARK: - A row that has not arrived yet

/// The placeholder for a row whose reader is still working, during a run.
///
/// ⚠️ **It is a real state and it lasts about six seconds**, nearly all of it the log read. Without
/// it the panel would be five rows and a hole, which reads as a screen that failed rather than one
/// that is still going. It says which row is coming and nothing about what it will contain — a
/// placeholder that guessed at a status would be a verdict from a check that had not run.
struct SecurityRowPlaceholder: View {
    let topic: SecurityTopic
    let index: Int
    /// True for the row being read at this moment. The others are simply queued.
    var active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.hairline) {
            HStack(alignment: .firstTextBaseline, spacing: Space.row) {
                Text(topic.label)
                    .font(.appHeadline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.row)
                if active {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
            }

            Text(active ? "Reading this now…" : "Waiting its turn.")
                .font(.appBody)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appRow(index)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(topic.label), \(active ? "reading now" : "waiting")")
    }
}

// MARK: - The details behind Options

/// One topic's worth of "everything more exact", under its own heading.
struct SecurityRowDetails: View {
    let row: SecurityRow

    var body: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            Text(row.topic.label)
                .font(.appHeadline)
                .fixedSize(horizontal: false, vertical: true)

            // What the row means. One sentence, once, where somebody has gone looking for it.
            Text(row.topic.explanation)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if row.details.isEmpty {
                InlineEmptyNote(symbol: "tray",
                                text: "Nothing more exact than the line above — this Mac reports "
                                    + "no further detail here.")
            } else {
                DetailPairGrid(pairs: row.details)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

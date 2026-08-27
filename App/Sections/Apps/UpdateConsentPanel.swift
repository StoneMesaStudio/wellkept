import SwiftUI
import WellkeptCore

//  UpdateConsentPanel.swift
//  Wellkept — App/Sections/Apps
//
//  ⭐ **The ask, in the page rather than over it.**
//
//  John, 2026-08-27: *"Inform and consent."* This is the inform half made visible, and it is
//  arguably the most important thing on this screen — it is the moment that decides whether
//  somebody trusts the rest of the app.
//
//  ## ⚠️ Why this is not `UpdateConsentAsk`, which asks the same question
//
//  That view is the **sheet** form: a fixed-size box that carries its own `StableScrollView` so its
//  buttons cannot be pushed below the fold at 200% text. Correct for a sheet, and unusable here —
//  `StableScrollView` is built on a `GeometryReader`, which is greedy, so nesting one inside the
//  section's own scrolling page hands it the whole visible height and produces a scroll view inside
//  a scroll view. The page would scroll, and the question inside it would scroll separately.
//
//  So this is the same question laid out for a page that already scrolls. **Every sentence comes
//  from `UpdateConsent.Words` and `Privacy.Departure`** — the two views share every word they say
//  and differ only in how they are boxed, which is the only kind of duplication that cannot drift.
//
//  ## ⚠️ A panel, not a modal wall
//
//  A sheet in front of a section somebody just pressed a button on is a thing to get past. Sitting
//  in the page, above the results it governs, it is plainly a question about the thing they
//  pressed — and it cannot be dismissed by clicking away from it, which a sheet can.
//
//  ## What to check by eye
//
//  - The register's own sentences, quoted rather than paraphrased.
//  - **"Don't check" comes first in reading order**, so the affirmative is not the button under the
//    cursor. Saying no is a supported way to run this section, not a failure to complete a step.
//  - The real number of apps that would be named, where a run has already produced one. "A small
//    number of makers" is the abstract version; a number is the one somebody can weigh.

struct UpdateConsentPanel: View {

    /// How many apps would actually be named, if the answer is yes. `nil` before the first run has
    /// produced an inventory, in which case the line is left out rather than padded with a guess.
    var storeAppCount: Int?

    var onAllow: () -> Void
    var onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.block) {
            Text(UpdateConsent.Words.title)
                .font(.appTitle3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            Text(UpdateConsent.Words.intro)
                .font(.appBody)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // What goes out, then what saying no costs — in that order, because the second is what
            // makes the first a decision rather than a demand. Quoted from the register.
            ForEach(UpdateConsent.Words.registerLines) { pair in
                VStack(alignment: .leading, spacing: Space.hairline) {
                    Text(pair.label)
                        .font(.appHeadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(pair.value)
                        .font(.appCallout)
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

            // Said whichever way they answer, because a decision that feels permanent is a decision
            // people avoid making.
            Text(UpdateConsent.Words.changeable)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // ⚠️ A wrapping stack, not an `HStack`. At 200% text two large buttons do not fit side
            // by side in a 700-point column, and an `HStack` would compress them until the labels
            // truncated — "Don't check" reading as "Don't ch…" on the one screen where the words
            // are the whole point.
            //
            // ⚠️ **No `Spacer` inside the horizontal option.** A `Spacer` has an unbounded ideal
            // width, so `ViewThatFits` measures the row as never fitting and silently takes the
            // stacked layout at every text size. The first render of this panel stacked two short
            // buttons in a 700-point column for exactly that reason. The leading alignment is put
            // on the result instead, where it costs nothing to measure.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.gutter) { buttons }
                VStack(alignment: .leading, spacing: Space.row) { buttons }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Space.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.stripe, in: Radius.shape(Radius.control))
        .overlay {
            Radius.shape(Radius.control)
                .strokeBorder(Theme.hairlineInk, lineWidth: Hairline.thin)
        }
        .accessibilityElement(children: .contain)
    }

    /// "No" first, in reading order. See the file header.
    @ViewBuilder private var buttons: some View {
        Button(UpdateConsent.Words.declineVerb, action: onDecline)
            .buttonStyle(.app)
            .controlSize(.large)
        Button(UpdateConsent.Words.allowVerb, action: onAllow)
            .buttonStyle(.appProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
    }
}

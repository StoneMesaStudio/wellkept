import SwiftUI
import WellkeptCore

//  UpdateCheckSetting.swift
//  Wellkept — App/Sections/Apps
//
//  **Where the answer lives afterwards.**
//
//  The question itself is asked on the Apps screen, on the first press of **Check apps**, because
//  that is where it has any context. This is the same switch on the page a person goes to when they
//  have changed their mind — Settings ▸ Permissions, which is already the page about what Wellkept
//  is allowed to do.
//
//  ## ⚠️ It quotes the privacy register rather than paraphrasing it
//
//  `Privacy.Departure.appUpdateCheck` owns both sentences — what leaves, and what saying no costs.
//  Three screens describing the same departure in three sets of words is exactly the drift that
//  produced the correction of 2026-08-27, when Permissions claimed "nothing it reads leaves this
//  Mac" while the welcome page said something narrower and Help said a third thing.
//
//  ## ⚠️ Two positions, and the third is not reachable from here
//
//  `UpdateConsent.Answer` has three states, and "nobody has been asked" is a real one — it is what
//  makes the first press of Check apps put the question on screen. A switch cannot express it, and
//  it must not try: a person who has already answered does not need to be asked again, and there is
//  no honest control that means "forget my answer". `UpdateConsentStore.setAllowed` is the two-way
//  door; `forget()` exists for the uninstaller and for tests.

struct UpdateCheckSetting: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let store = app.updateConsent

        VStack(alignment: .leading, spacing: Space.row) {
            HStack(alignment: .firstTextBaseline, spacing: Space.gutter) {
                Text(UpdateConsent.departure.title)
                    .font(.appTitle3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.row)
                Toggle("", isOn: Binding(get: { store.isAllowed },
                                         set: { store.setAllowed($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel(UpdateConsent.departure.title)
            }

            // Quoted, never paraphrased. See the file header.
            ForEach(UpdateConsent.departure.detailPairs) { pair in
                VStack(alignment: .leading, spacing: 2) {
                    Text(pair.label)
                        .font(.appCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(pair.value)
                        .font(.appCallout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // ⚠️ Said only before anybody has answered. Afterwards it would be the app telling
            // somebody about a question they have already been asked, which reads as a nag.
            if !store.hasBeenAsked {
                Text("Wellkept has not asked yet. It will, the first time you check your apps.")
                    .font(.appCaption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
}

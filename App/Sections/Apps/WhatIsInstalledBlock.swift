import SwiftUI
import WellkeptCore

//  WhatIsInstalledBlock.swift
//  Wellkept — App/Sections/Apps
//
//  **What is installed.** The identification card the five rows sit under, the same job
//  `MachineBlock` does in Hardware and `ProtectionsBlockView` does in Security.
//
//  ## ⚠️ Inventory, never a verdict
//
//  There is no status chip on this block and there never will be. A list of apps is not a fault,
//  and nothing in this round of Apps constitutes one either. It is drawn on its own card, above the
//  rows and visibly separate from them, so nothing here can be mistaken for something the app is
//  telling you to act on.
//
//  ## ⚠️ The number is 31, and the other 391 are one line
//
//  Walking the file system on the measured Mac finds **422 bundles**: 294 belong to macOS, 81 are
//  Xcode build products and Automator droplets in the home folder, 12 are under `/Library`, 7 are
//  nested inside other apps. The number a person recognises is 31, and a block that opened with
//  "422 apps" would be wrong by a factor of three on its very first line — wrong in the direction
//  that sells cleaners.
//
//  So the block leads with the count a person would count themselves, and says in the same breath
//  where the rest went. Saying it is what turns a number into a claim somebody can check; leaving
//  it out is what invites the obvious objection that they have seen a bigger number somewhere.

struct WhatIsInstalledBlock: View {
    let inventory: AppsInventory
    /// The apps that come with macOS. **Counted separately, always**, and a macOS update is what
    /// updates them.
    var bundledWithMacOS: [InstalledApp] = []
    /// True while the check is still running, so the card can appear before the rest of the screen
    /// rather than after it.
    var stillReading = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.block) {
            VStack(alignment: .leading, spacing: 2) {
                Text("What is installed")
                    .font(.appCaption)
                    .foregroundStyle(Theme.textSecondary)
                Text(headline)
                    .font(.appTitle3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: AppFont.pt(180)),
                                         spacing: Space.gutter,
                                         alignment: .topLeading)],
                      alignment: .leading,
                      spacing: Space.block) {
                ForEach(pairs) { pair in
                    DetailPairCell(pair: pair)
                }
            }

            // ⚠️ The other 391, said on the card and not only behind Options. See the file header.
            Text(scopeSentence)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if stillReading {
                Text("Still reading — the rest of this section is on its way.")
                    .font(.appCaption)
                    .foregroundStyle(Theme.textTertiary)
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

    /// The count a person recognises, in words.
    private var headline: String {
        switch inventory.apps.count {
        case 0:  "No apps were found in the folders apps live in"
        case 1:  "One app"
        default: "\(inventory.apps.count) apps"
        }
    }

    /// The breakdown of the apps a person recognises, by where each one came from.
    ///
    /// ⚠️ **The count and the other-bundles line are dropped, because both are already said above
    /// and below.** DESIGN §8: never say the same thing twice on one screen.
    ///
    /// ⚠️ **The macOS apps are NOT added as a pair here**, and that is not an omission. The grid is
    /// a breakdown of this list, and one of the 26 has `.bundledWithMacOS` as its origin — Safari.
    /// A second "37" beside that "1", under a label three words from the same, is two numbers about
    /// two different sets with nothing to tell them apart. The sentence below says the 37, with the
    /// word "more" doing the work.
    private var pairs: [DetailPair] {
        inventory.detailPairs.filter {
            $0.label != "Apps" && $0.label != "Other bundles on this Mac"
        }
    }

    /// Where the other bundles went, in plain words.
    ///
    /// ⚠️ `nil` from `otherBundles` is not zero. Nothing counted them, and saying "0" would claim a
    /// measurement nobody took.
    private var scopeSentence: String {
        var parts = ["Counted the way a person would count them: what is in your Applications "
                   + "folders."]
        if !bundledWithMacOS.isEmpty {
            parts.append("\(bundledWithMacOS.count) more come with macOS, and a macOS update is "
                       + "what updates those.")
        }
        if let elsewhere = inventory.otherBundles, elsewhere > 0 {
            parts.append("Another \(elsewhere) bundles on this Mac are components, helpers and "
                       + "build products rather than apps, so they are not counted here.")
        }
        if !inventory.addedByHand.isEmpty {
            let names = inventory.addedByHand.map(\.name).formatted(.list(type: .and))
            parts.append("macOS does not list \(names), so Wellkept read "
                       + (inventory.addedByHand.count == 1 ? "it" : "them") + " directly.")
        }
        return parts.joined(separator: " ")
    }
}

import SwiftUI
import WellkeptCore

//  ProtectionsBlockView.swift
//  Wellkept — App/Sections/Security
//
//  **What is protecting this Mac.** The inventory the six rows sit under.
//
//  ## ⚠️ Inventory, never a verdict — the same rule as `MachineBlock`
//
//  There is no status chip on this block and there never will be, and nothing in it is ever
//  painted amber. It lists what each protection is set to; deciding whether any of that is worth
//  a look happens exactly once, in the Protections row underneath, through `SecurityConcern`.
//  Colouring a switch here as well would say the same thing twice on one screen and would put the
//  section's only judgement in two places that can disagree.
//
//  That is not a cosmetic choice. Somebody who turned FileVault off on a spare Mac in a locked
//  office has not made a mistake, and a red block at the top of the screen before they have read a
//  word tells them they have.
//
//  ## What is in it
//
//  FileVault, system protection, Gatekeeper, secure boot, the firewall and the rest — whatever
//  `ProtectionsBlock` holds, in its own fixed order — then XProtect's data version and the day it
//  last changed. XProtect is not a switch, which is why it is a version and a date rather than an
//  On, and why it lives on the block instead of among the switches.
//
//  ## ⚠️ "On" is what we read, not what we assume
//
//  Every value comes from `Protection.state.label`, so a switch this Mac does not report prints the
//  house sentence — "this Mac does not report it" — rather than an Off nobody measured. Lockdown
//  Mode is that case on every Mac: there is no readable state for it anywhere.

struct ProtectionsBlockView: View {
    let block: ProtectionsBlock

    /// Drawn while the rest of the section is still being read. It changes one line — a note
    /// saying the panel below is still filling in — and nothing else, so the block does not move
    /// under the reader when the run finishes.
    var stillReading = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.block) {
            VStack(alignment: .leading, spacing: 2) {
                Text("What is protecting this Mac")
                    .font(.appCaption)
                    .foregroundStyle(Theme.textSecondary)
                Text(headline)
                    .font(.appTitle3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: AppFont.pt(200)),
                                         spacing: Space.gutter,
                                         alignment: .topLeading)],
                      alignment: .leading,
                      spacing: Space.block) {
                ForEach(block.detailPairs) { pair in
                    DetailPairCell(pair: pair)
                }
            }

            // ⚠️ A management fact is never a problem, so it is stated here in the inventory and
            // nowhere else. It explains why some rows below carry no button, which is otherwise
            // the app looking broken on exactly the Macs it is least able to help.
            if block.isManaged {
                Text("Some of these are chosen by an organisation rather than on this Mac, so "
                     + "Wellkept reports them and offers nothing to change.")
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if stillReading {
                Text("Still reading the rest of this section.")
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(Space.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("What is protecting this Mac")
    }

    /// The count, as a plain sentence. It is a tally of what answered, **not** a score: the number
    /// that is off is deliberately absent, because that is the judgement and it belongs to the row
    /// below.
    private var headline: String {
        let read = block.protections.filter(\.state.wasRead).count
        let total = block.protections.count
        guard total > 0 else { return "Nothing here has been read yet." }
        if read == total {
            return total == 1
                ? "One protection, and this Mac reported it."
                : "\(total) protections, and this Mac reported all of them."
        }
        if read == 0 {
            return "This Mac reported none of the \(total) protections here."
        }
        return "\(read) of \(total) protections, as this Mac reports them."
    }
}

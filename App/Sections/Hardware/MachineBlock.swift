import SwiftUI
import WellkeptCore

//  MachineBlock.swift
//  Wellkept — App/Sections/Hardware
//
//  **What this Mac is.** The identification card the five readings sit under.
//
//  ## ⚠️ Inventory, never a verdict
//
//  There is no status chip on this block and there never will be. A 2019 iMac is not broken for
//  being a 2019 iMac, and there is no arrangement of a name, a model and a chip that constitutes a
//  fault. It is drawn on its own card, above the findings and visibly separate from them, so that
//  nothing here can be mistaken for something the app is telling you to act on.
//
//  The one line that genuinely tells a person something is the macOS support standing — whether
//  Apple still ships security fixes for what this Mac can run. John, 2026-08-27: *"Not about fear,
//  it is about security. Why not be honest? We are not selling them a new machine, we are
//  protecting them."* So it is said plainly, framed as security, and it is the only line in this
//  block that ever takes a colour — and only in the one state where the fixes have actually
//  stopped.
//
//  ## The serial number
//
//  Last in the block, marked sensitive by `MachineFacts.detailPairs`, and click-to-copy — because
//  the thing a person does with a serial number is read it to somebody or paste it into a form.
//  The repair-shop copy shows exactly what it is about to paste, serial included, **before**
//  anything reaches the clipboard. Something that quietly copies an identifying number is doing
//  the thing this app exists to catch other software doing.

struct MachineBlock: View {
    let facts: MachineFacts
    /// What the "Copy for a repair shop" button raises. Passed in rather than reached for, so this
    /// view has no opinion about how a sheet gets on screen.
    var showRepairCopy: () -> Void

    @Environment(\.palette) private var palette

    private var standing: SupportStanding { facts.standing() }

    /// Everything but the name, which is already the heading above the grid. Filtered by label
    /// rather than rebuilt here, so a field added to `MachineFacts.detailPairs` still appears.
    private var pairs: [DetailPair] {
        facts.detailPairs.filter { $0.label != "Name" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.block) {
            VStack(alignment: .leading, spacing: 2) {
                Text("What this Mac is")
                    .font(.appCaption)
                    .foregroundStyle(Theme.textSecondary)
                Text(facts.name)
                    .font(.appTitle3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: AppFont.pt(180)),
                                         spacing: Space.gutter,
                                         alignment: .topLeading)],
                      alignment: .leading,
                      spacing: Space.block) {
                ForEach(pairs) { pair in
                    DetailPairCell(pair: pair, copyable: pair.sensitive)
                }
            }

            // Security, never sales. `.information` in every state but one, and that one says the
            // fixes have stopped rather than that the machine is old.
            Text(standing.sentence)
                .font(.appCallout)
                .foregroundStyle(standing.severity >= .attention
                                 ? palette.color(for: standing.severity)
                                 : Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if facts.isVirtualMachine {
                Text("This is a virtual machine, so every reading below describes a simulated Mac "
                     + "rather than real hardware.")
                    .font(.appCallout)
                    .foregroundStyle(palette.color(for: Severity.attention))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Copy for a repair shop…") { showRepairCopy() }
                .buttonStyle(.app)
                // The ellipsis and this line together: the button opens something that shows you
                // the text first. Nothing is on the clipboard until you have read it.
                .help("Shows exactly what will be copied before anything is copied.")
        }
        .padding(Space.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }
}

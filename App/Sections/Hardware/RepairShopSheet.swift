import SwiftUI
import WellkeptCore

//  RepairShopSheet.swift
//  Wellkept — App/Sections/Hardware
//
//  **Shows exactly what it is about to paste, before anything reaches the clipboard.**
//
//  There is one string here, not two. `RepairShopCopy.text` is what is displayed *and* what is
//  copied, so a preview cannot drift from the paste — which is the whole reason that type holds a
//  single string rather than a preview and a payload.
//
//  The serial-number switch is offered only when the report actually contains something
//  identifying (`hasSensitive`). A Mac that reports no serial should not be shown a switch that
//  changes nothing; a control that does nothing is worse than an absent one, because a person who
//  flips it believes something happened.

struct RepairShopSheet: View {
    let report: HardwareReport

    @State private var includeSerial = true
    @Environment(\.dismiss) private var dismiss

    private var copy: RepairShopCopy { RepairShopCopy(report, includeSerial: includeSerial) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.gutter) {
            Text("Copy for a repair shop").sectionHeading()

            Text("This is exactly what will be put on the clipboard. Nothing is copied until you "
                 + "press the button.")
                .font(.appBody)
                .fixedSize(horizontal: false, vertical: true)

            // Selectable, and scrolling inside its own box: the report is longer than the sheet on
            // a Mac with three drives attached, and a sheet that grows to fit it would run off the
            // bottom of the screen.
            ScrollView {
                Text(copy.text)
                    .font(.appCallout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Space.gutter)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor), in: Radius.shape(Radius.control))
            .overlay(Radius.shape(Radius.control)
                .strokeBorder(Theme.hairlineInk, lineWidth: Hairline.thin))

            if copy.hasSensitive {
                Toggle("Include the serial number", isOn: $includeSerial)
                    .font(.appCallout)
            }

            if let caution = copy.caution {
                Text(caution)
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Space.gutter) {
                Spacer(minLength: 0)
                Button("Cancel") { dismiss() }
                    .buttonStyle(.app)
                    .keyboardShortcut(.cancelAction)
                Button("Copy to Clipboard") {
                    copy.copyToPasteboard()
                    dismiss()
                }
                .buttonStyle(.appProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.page)
        .frame(width: SheetMetrics.width(560), height: SheetMetrics.height(560))
        .pageGround()
    }
}

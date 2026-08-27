import AppKit
import SwiftUI
import WellkeptCore

//  DriveAlarmView.swift
//  Wellkept — App/Sections/Hardware
//
//  **What a person sees when their drive has just told them it is failing.**
//
//  Two steps, in order, and nothing else. Somebody reading this has minutes or days of working
//  drive left, and every extra line on the screen competes with "copy your files off". So it sits
//  at the very top of the section — above the machine block, above the sentence, above the button
//  — because it is the answer to the question the section asks, and the one arrangement that would
//  be indefensible is making a person scroll past their own model number to reach it.
//
//  Everything it says comes from `DriveAlarm`, which quotes Apple's own verdict verbatim, names no
//  component, quotes no price, and uses the word "failing" only because the drive used it first.
//  This view adds no judgement of its own; it draws two steps and a line of identification.
//
//  ⚠️ **The second step has no button on an external drive**, by design. Apple cannot help with a
//  drive Apple did not sell, and sending somebody to an Apple Support page wastes the one afternoon
//  they have. `Step.title` is `nil` there and this view draws the sentence alone.

struct DriveAlarmView: View {
    let alarm: DriveAlarm
    /// Where "Open Backup" goes. Passed in because navigation belongs to the shell, not here.
    var goTo: (SectionID) -> Void

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    var body: some View {
        VStack(alignment: .leading, spacing: Space.block) {
            // The tag sits **above** the sentence rather than beside it. Beside it, the sentence
            // wraps into the narrow column left over and hangs off the tag's right edge — which is
            // ugly at 100% text and unreadable at 200%, on the one screen in the app that has to
            // be read at a glance.
            VStack(alignment: .leading, spacing: Space.row) {
                SeverityTag(severity: .problem)
                Text(alarm.headline)
                    .font(.appTitle3)
                    .foregroundStyle(palette.problem)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Do these two things, in this order.")
                .font(.appBody)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Space.gutter) {
                ForEach(Array(alarm.steps.enumerated()), id: \.element.id) { index, step in
                    stepView(index: index, step: step)
                }
            }

            // Model and serial on one line, for reading down a telephone. Selectable, because the
            // other thing people do with it is paste it into a support form.
            Text(alarm.identification)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.problem.opacity(0.08), in: Radius.shape(Radius.card))
        .overlay(Radius.shape(Radius.card)
            // Heavier under Differentiate Without Color, where the wash behind it says nothing —
            // and the wash is never the only signal anyway: the word "PROBLEM" is on the first line.
            .strokeBorder(palette.problem.opacity(differentiate ? 0.9 : 0.4),
                          lineWidth: differentiate ? Hairline.selection : Hairline.thin))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func stepView(index: Int, step: DriveAlarm.Step) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.gutter) {
            Figure("\(index + 1).", size: 15, weight: .bold)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: AppFont.pt(22), alignment: .leading)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Space.row) {
                Text(step.sentence)
                    .font(.appBody)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                if let title = step.title {
                    Button(title) { perform(step) }
                        .buttonStyle(index == 0 ? .appProminent : .app)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor private func perform(_ step: DriveAlarm.Step) {
        if let section = step.section { goTo(section) }
        if let url = step.url { NSWorkspace.shared.open(url) }
    }
}

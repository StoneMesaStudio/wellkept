// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Stone Mesa Studio, LLC

import SwiftUI
import WellkeptCore

//  FreeSpaceBlock.swift
//  Wellkept — App/Sections/Storage
//
//  ⭐ **The top of the Storage face: the real free-space number, Finder's underneath, and one line
//  saying what the difference is.**
//
//  Decided 2026-08-28: *"Lead with the real one. Ours has to add up. So: the real number leads, with
//  Finder's printed underneath and one line saying what the difference is. We are not contradicting
//  Finder, we are explaining it, which is the one thing no other tool on the Mac does."*
//
//  Measured on one real Mac in the same second: **109.8 GB actually free, 177.9 GB printed by Finder.**
//  Both correct. Finder's answers a different question — how much macOS believes it *could* free
//  under pressure — and it is not a number arithmetic works on: delete 12 GB and it does not go up
//  by 12, because the purgeable pool moves underneath.
//
//  ## ⚠️ Nothing here composes a sentence
//
//  Every line under the headline comes from `StorageReport.linesUnderTheHeadline`, in order:
//  Finder's figure · the difference · **the stuck Time Machine snapshot** · what we were refused ·
//  the files that are in iCloud and not here · and the gap between what macOS says is used and what
//  the scan accounted for. That list is unconditional by construction, which is what makes it
//  impossible to draw this section's totals without also saying what they do not cover.
//
//  ## ⚠️ The snapshot line has no button, and that is deliberate
//
//  It is the reason almost nothing on this screen returns any room today, so leaving it out would
//  make our own numbers look broken. But Backup does not exist yet, and a button that opened
//  something we have not built would be worse than a sentence. One flat line.
//
//  ## ⛔ There is no "Other" slice here
//
//  Our scan accounted for 244 GB of a disk macOS says has 357 GB in use. Every competitor invents a
//  wedge labelled "Other" and puts the difference in it. `MeasuredGap.sentence` names the causes
//  instead — the snapshot, the folders we were refused, filesystem bookkeeping — and says plainly
//  that it is a difference rather than a category.

struct FreeSpaceBlock: View {

    let report: StorageReport

    private var picture: FreeSpacePicture { report.freeSpace }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.block) {

            // ⭐ The real number, and it is the biggest thing on the screen.
            HStack(alignment: .firstTextBaseline, spacing: Space.gutter) {
                Figure(picture.actuallyFree.text, size: 34, weight: .bold)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("free of \(picture.capacity.text)")
                        .font(.appHeadline)
                    Text(picture.volumeName)
                        .font(.appCaption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            // Spoken as one phrase. Read out piecemeal it becomes "109.8 GB" then "free of 494 GB"
            // then a volume name, which is three facts where there is one.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(picture.headline) on \(picture.volumeName)")
            .accessibilityAddTraits(.isSummaryElement)

            CapacityBar(used: picture.used, capacity: picture.capacity)

            // How full it is, and only when that is worth saying. `.comfortable` has no reason and
            // draws nothing — a line saying the disk is fine is a line nobody needed.
            if let reason = picture.pressure.reason {
                HStack(alignment: .firstTextBaseline, spacing: Space.row) {
                    SeverityTag(severity: picture.pressure.severity)
                    Text(reason)
                        .font(.appCallout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // ⭐ Finder's figure, the explanation, the snapshot, the refusals, iCloud, and the gap —
            // in the order `WellkeptCore` puts them, never re-ordered or filtered here.
            if !report.linesUnderTheHeadline.isEmpty {
                VStack(alignment: .leading, spacing: Space.row) {
                    ForEach(Array(report.linesUnderTheHeadline.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.appCallout)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard()
    }
}

/// How full the disk is, as a proportion.
///
/// ⚠️ **Achromatic.** Bronze appears in exactly three places in this app — the selected sidebar
/// row, the main button, and section headings — and a bar across the top of a face would be a
/// fourth. The bar restates the two numbers above it and is hidden from a screen reader for the
/// same reason.
private struct CapacityBar: View {
    let used: SizeOnDisk
    let capacity: SizeOnDisk

    private var share: Double {
        guard capacity.bytes > 0 else { return 0 }
        return min(1, max(0, Double(used.bytes) / Double(capacity.bytes)))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Radius.shape(AppFont.pt(Radius.small))
                    .fill(Theme.hairlineInk)
                Radius.shape(AppFont.pt(Radius.small))
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: max(2, geometry.size.width * share))
            }
        }
        .frame(height: AppFont.pt(8))
        .accessibilityHidden(true)
    }
}

import SwiftUI
import WellkeptCore

//  GrantList.swift
//  Wellkept — App/Sections/Security
//
//  **Which apps can use the camera, the microphone, the screen, or control this Mac.**
//
//  This is the one screen in Security whose content is a list rather than a sentence, which is why
//  it exists as its own view: `SecurityRow` carries only `DetailPair`s, and a hundred apps flattened
//  into label-and-value pairs is a specification sheet, not a list of who can watch you.
//
//  ## ⚠️ Holding a permission is not a problem, and the copy leads with that
//
//  A video app needs the camera. A screen-sharing app needs the screen. A window manager needs
//  control of this Mac. Twenty entries here is what a working Mac looks like, and a screen that
//  presents them as twenty findings sends somebody off revoking the permissions their own software
//  depends on. Only two things in this list are ever coloured — an app whose signature no longer
//  matches what was approved, and a permission still held by an app that is gone — and those two
//  are the whole of it.
//
//  ## ⚠️ "Held", never "using"
//
//  Nothing unprivileged on macOS distinguishes a permission being held from one being exercised
//  right now, so the word "using" does not appear here. Saying a camera is in use when we cannot
//  see that would be the most frightening sentence this app is capable of producing, and it would
//  be a guess.
//
//  ## Wellkept is in its own list
//
//  It holds Full Disk Access, which is how it read the list at all. Settled 2026-08-27: say
//  so. An app that quietly filters itself out of the list of software that can read your disk is
//  doing the thing this one exists to catch other software doing.

struct GrantList: View {
    let answer: SecurityAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: Space.section) {
            if answer.grants.isEmpty {
                InlineEmptyNote(symbol: "checkmark.circle",
                                text: "Nothing on this Mac holds any of these permissions.")
            } else {
                ForEach(answer.permissionsHeld) { permission in
                    PermissionGroup(permission: permission,
                                    grants: answer.grants(for: permission))
                }
            }

            footnotes
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The two things about the list itself, rather than about anything in it.
    @ViewBuilder private var footnotes: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            if answer.systemServicesUsingLocation > 0 {
                Text("\(answer.systemServicesUsingLocation) parts of macOS itself also use "
                     + "location. They are not apps anybody installed, so they are counted here "
                     + "and not listed.")
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // ⚠️ Stated, never accused. Background helpers and XPC services hold permissions and are
            // not registered as applications, so an identifier we cannot place is far more often a
            // helper than anything else. Guessing "no longer installed" here would be an amber
            // accusation built on not knowing.
            if !answer.unplaceable.isEmpty {
                Text(answer.unplaceable.count == 1
                     ? "One identifier on the list could not be matched to an app on this Mac. "
                       + "That is usually a background helper rather than anything missing."
                     : "\(answer.unplaceable.count) identifiers on the list could not be matched to "
                       + "apps on this Mac. Those are usually background helpers rather than "
                       + "anything missing.")
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - One permission, and everything holding it

private struct PermissionGroup: View {
    let permission: WellkeptCore.Permission
    let grants: [Grant]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            HStack(alignment: .firstTextBaseline, spacing: Space.row) {
                Text(permission.label)
                    .font(.appHeadline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.row)
                Text(grants.count == 1 ? "1 app" : "\(grants.count) apps")
                    .font(.appCaption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Text(permission.explanation)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(Array(grants.enumerated()), id: \.element.id) { index, grant in
                    GrantRow(grant: grant, index: index)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - One app holding one permission

private struct GrantRow: View {
    let grant: Grant
    let index: Int

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: Space.row) {
                Text(grant.appName)
                    .font(.appCallout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.row)
                // ⚠️ The day, never the minute. macOS records a timestamp, and printing "at
                // 10:38 AM" beside an app name from two years ago is precision nobody asked for
                // that pushes the name into an ellipsis at any real text size.
                if let granted = grant.grantedAt {
                    Text(granted.formatted(date: .abbreviated, time: .omitted))
                        .font(.appCaption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            // ⚠️ **Its own line, never trailing the name.** Two words beside a name look tidy until
            // the column narrows or the text doubles, at which point they wrap and orphan
            // themselves under the app they describe. This is the one coloured word in the list and
            // it has to stay attached to the right app.
            if let note = standing {
                Text(note)
                    .font(.appCaption.weight(.semibold))
                    .foregroundStyle(palette.color(for: Severity.attention))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(subtitle)
                .font(.appCaption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appRow(index)
        .accessibilityElement(children: .combine)
    }

    /// The only two things in this list that ever take a colour.
    private var standing: String? {
        switch grant.concern {
        case .permissionHeldByMissingApp:    "No longer installed"
        case .signatureChangedSinceApproved: "Signature changed"
        default:                             nil
        }
    }

    /// The identity the permission was actually granted to — which is the thing that outlives the
    /// app — and, for Wellkept itself, the plain admission.
    private var subtitle: String {
        grant.isWellkept
            ? "\(grant.bundleID) — this is Wellkept. It holds Full Disk Access, which is how it "
              + "read this list."
            : grant.bundleID
    }
}

import SwiftUI
import WellkeptCore

//  HardwareView.swift
//  Wellkept — App/Sections
//
//  **"Is this machine healthy?"** — the drive, the battery, the memory, the restarts, the speed.
//
//  Read-only, except for one button. Nothing here changes anything about this Mac; the single
//  exception is the speed test, which writes a 256 MB file and deletes it in the same breath, only
//  on a press, and says so on the control that does it.
//
//  ## The shape, top to bottom
//
//  1. The heading, its status, and when it last ran.
//  2. **The failing-drive screen**, on the one Mac in a thousand that has one — above everything,
//     because it is the answer to the section's question and nobody should have to scroll past a
//     model number to reach it.
//  3. The sentence and the one button.
//  4. **What this Mac is** — inventory, on its own card, visibly separate, never a verdict.
//  5. **The five rows, in fixed order and never sorted**: Drive · Battery · Memory · Restarts ·
//     Speed. Every row every time, even when everything is fine.
//  6. **Options** — everything more exact, and the speed test.
//
//  ## ⚠️ Why every row is drawn even when nothing is wrong
//
//  Worst-first is right for a list of findings and wrong for a fixed panel. Somebody who learns
//  that Battery is the second row should still find it there next week, on a Mac where the drive
//  happens to have gone quiet — and **seeing that it looked is the point**, which is the same
//  argument for keeping the audit trail on a clean Overview. A panel that reshuffles
//  between runs is a panel you have to re-read every time you open it.
//
//  ## ⚠️ There is no daily check, and nothing on this screen may imply one
//
//  Wellkept quits when its window closes, and the one thing that can outlive it — the backup
//  background piece a person switches on themselves — does not read hardware and never will.
//  Hardware is read **on launch and when the button is pressed** — that is the whole list, and the
//  words below say exactly that.

struct HardwareView: View {
    @Environment(AppState.self) private var app

    private var model: HardwareModel { app.hardware }

    /// What is drawn. In demo mode this is an invented Mac and **nothing has been read from this
    /// one** — which is the promise the bar across the top of the window makes on every screen.
    private var report: HardwareReport? {
        app.demoMode ? DemoData.hardware(app.demoMachine) : model.report
    }

    private var alarm: DriveAlarm? {
        app.demoMode ? DemoData.driveAlarm(app.demoMachine) : model.alarm
    }

    /// The section's own line, taken from the report it describes so the chip and the rows cannot
    /// disagree.
    private var record: CheckRecord? { report?.record ?? app.records[.hardware] }

    /// Demo mode is a picture of a Mac, not this Mac, so nothing on it may start a real check.
    private var live: Bool { !app.demoMode }

    var body: some View {
        StableScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                SectionHeader(section: .hardware, record: record)

                // Nothing in Hardware needs Full Disk Access, so this draws nothing here. It is
                // present for the same reason it is on every face: a section that decides for
                // itself whether to mention a permission is a section that can forget to.
                PermissionNoticeLine(section: .hardware)

                if let alarm {
                    DriveAlarmView(alarm: alarm) { app.selection = $0 }
                }

                checkControl

                if let report {
                    MachineBlock(facts: report.facts) { showRepairCopy(report) }
                    rows(report)
                    options(report)
                } else {
                    notReadYet
                }
            }
            .padding(Space.page)
            .readableColumn()
        }
        .fillsPane()
    }

    // MARK: The sentence and the button

    private var checkControl: some View {
        VStack(alignment: .leading, spacing: Space.block) {
            Text(SectionID.hardware.sentence)
                .font(.appBody)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.gutter) {
                Button(SectionID.hardware.verb) {
                    Task { await app.runHardwareCheck() }
                }
                .buttonStyle(.appProminent)
                .controlSize(.large)
                .disabled(!live || model.isChecking)

                if model.isChecking {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                    Text("Reading this Mac…")
                        .font(.appCallout)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }

            // Said once, on the screen it is true of. Hardware is on no schedule at all — the one
            // part of Wellkept that runs on a clock is the backup background piece, and it never
            // touches this. So this is the whole of when Hardware runs.
            Text("Wellkept reads this when the app opens and whenever you press the button — never "
                 + "on its own, and nothing here changes your Mac.")
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: The five rows

    private func rows(_ report: HardwareReport) -> some View {
        // ⚠️ `report.readings` is already in `HardwareTopic` order, put there by
        // `HardwareReport.init`. It is never sorted here, and it is never filtered.
        VStack(spacing: 0) {
            ForEach(Array(report.readings.enumerated()), id: \.element.id) { index, reading in
                ReadingRow(reading: reading, index: index)
            }
        }
    }

    // MARK: Options

    /// **One disclosure on this screen, and it says what is behind it.**
    ///
    /// Its open state lives in `AppState` rather than in a `@State` here, so a ⌘+ press does not
    /// collapse a panel somebody had just opened — which reads as the app undoing their click.
    ///
    /// It sits **after** the rows rather than above them: everything in it is a more exact version
    /// of something in the panel above, and a disclosure that opens above the thing it details
    /// makes the reader scroll back up to use it.
    private func options(_ report: HardwareReport) -> some View {
        LabelledDisclosure("Options", isExpanded: app.optionsOpen(.hardware)) {
            VStack(alignment: .leading, spacing: Space.section) {
                ForEach(report.readings) { reading in
                    VStack(alignment: .leading, spacing: Space.block) {
                        ReadingDetails(reading: reading)
                        if reading.topic == .speed { speedControl }
                    }
                }
                whatWasRead(report)
            }
            .padding(.top, Space.row)
        }
    }

    /// **The one button in this app that writes anything.**
    ///
    /// `SpeedTest.writeNotice` is the sentence beside it, taken from the file that does the
    /// writing rather than retyped here. A consequence sentence written twice is a consequence
    /// sentence that starts being true in only one of the two places the first time one is edited.
    private var speedControl: some View {
        VStack(alignment: .leading, spacing: Space.row) {
            HStack(spacing: Space.gutter) {
                Button("Measure this drive") {
                    Task { await app.runSpeedTest() }
                }
                .buttonStyle(.app)
                .disabled(!live || model.isMeasuringSpeed || model.isChecking)

                if model.isMeasuringSpeed {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                    Text("Measuring…")
                        .font(.appCallout)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }

            Text(SpeedTest.writeNotice)
                .font(.appCallout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The section's own audit trail: when it ran, whether it saw everything, and what it did not.
    ///
    /// The developer asked for this on a clean Overview — that a check saying "nothing is wrong" is
    /// only worth as much as the list of what it actually looked at. The same argument holds one
    /// level down, and this is where it costs nothing.
    private func whatWasRead(_ report: HardwareReport) -> some View {
        VStack(alignment: .leading, spacing: Space.row) {
            Text("This check")
                .font(.appHeadline)

            DetailPairGrid(pairs: auditPairs(report))

            ForEach(report.unreadableTopics, id: \.topic) { item in
                Text(item.why.sentence(about: item.topic.label))
                    .font(.appCallout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func auditPairs(_ report: HardwareReport) -> [DetailPair] {
        [
            DetailPair("Ran at", ShortDate.stamp(report.ranAt)),
            DetailPair("Rows read", "\(report.readings.count) of \(HardwareTopic.allCases.count)"),
            DetailPair("Saw everything it looked for",
                       report.complete
                           ? "Yes"
                           : "No — something on this Mac refused to be read, and the rows below say which."),
            // Worth stating out loud: this is the section that works completely for somebody who
            // pressed "Finish later" during setup, and a person who refused a permission is exactly
            // the person wondering what it cost them.
            DetailPair("Permissions used", "None. Nothing in Hardware needs Full Disk Access."),
        ]
    }

    // MARK: Nothing read yet

    /// ⚠️ **A real state, and a common one.** Setup ends on Overview, so somebody can arrive here
    /// before anything has run — and it is what this screen looks like for the second or two the
    /// first check takes.
    private var notReadYet: some View {
        VStack(alignment: .leading, spacing: Space.block) {
            EmptyStateView(
                symbol: "stethoscope",
                title: "Nothing has been read yet",
                message: "Wellkept has not looked at this Mac's hardware. Press \(SectionID.hardware.verb) "
                       + "and it will read what the drive, the battery and the memory say about "
                       + "themselves, and what macOS recorded the last time the machine restarted "
                       + "on its own. It takes about a second and it changes nothing.",
                greedy: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Copy for a repair shop

    /// ⚠️ Raised through the window's **one** sheet slot. Two `.sheet` modifiers on a view make
    /// SwiftUI silently drop one, so every caller in the app goes through `AppState`.
    @MainActor private func showRepairCopy(_ report: HardwareReport) {
        app.sheet = SheetRoute(id: "hardware.repairShopCopy") {
            RepairShopSheet(report: report)
        }
    }
}

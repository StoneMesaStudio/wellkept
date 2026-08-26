import SwiftUI
import WellkeptCore

//  BackupView.swift
//  Wellkept — App/Sections
//
//  "Is my stuff safe?" — whether the files are backed up, and what is not covered.
//
//  ⚠️ **Never a bootable backup.** Apple removed the ability years ago and the ones still sold do
//  not survive a macOS update; proposing one would be advice that fails at the moment it is needed.
//  Backup is also the single exception to "nothing that changes the Mac happens on a schedule" —
//  and only because what it writes to is the backup disk, never this one.

struct BackupView: View {
    var body: some View { SectionFace(.backup) }
}

import SwiftUI
import WellkeptCore

//  SecurityView.swift
//  Wellkept — App/Sections
//
//  "Am I safe?" — this Mac's protections, what can watch you, and what macOS has already found.
//
//  Reporting, not fixing. Where something is off, the row's verb opens the System Settings pane
//  that owns it; the app does not reach in and flip it. A utility that silently changes security
//  settings is the category this one exists to not be.

struct SecurityView: View {
    var body: some View { SectionFace(.security) }
}

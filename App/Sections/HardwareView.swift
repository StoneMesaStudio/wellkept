import SwiftUI
import WellkeptCore

//  HardwareView.swift
//  Wellkept — App/Sections
//
//  "Is this machine healthy?" — the drive, the battery, the memory and the temperature.
//
//  Read-only for ever. Nothing in this section can change anything about the Mac, which is why it
//  is the first section being built: it proves the face, the palette and the plumbing with nothing
//  at risk.

struct HardwareView: View {
    var body: some View { SectionFace(.hardware) }
}

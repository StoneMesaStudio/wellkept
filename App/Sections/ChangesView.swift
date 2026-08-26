import SwiftUI
import WellkeptCore

//  ChangesView.swift
//  Wellkept — App/Sections
//
//  "What changed, and who changed it?" — this Mac's settings against the last time Wellkept looked.
//
//  It reports that something moved and when. It does not know who moved it, and it says so on the
//  row rather than implying an author it cannot name.

struct ChangesView: View {
    var body: some View { SectionFace(.changes) }
}

import SwiftUI
import WellkeptCore

//  AppsView.swift
//  Wellkept — App/Sections
//
//  "What's installed, and is it current?" — every app, where it came from, and whether a newer
//  version exists.
//
//  This is the one section that necessarily talks to the outside world: checking a version means
//  asking the vendor, which tells the vendor a copy exists on this Mac. Unavoidable, so the app
//  says so on the welcome page rather than leaving it to be discovered.

struct AppsView: View {
    var body: some View { SectionFace(.apps) }
}

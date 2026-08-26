import SwiftUI
import WellkeptCore

//  StorageView.swift
//  Wellkept — App/Sections
//
//  "What's eating my space?" — what is using the disk, largest first.
//
//  ⚠️ The distinction this section is built on: **machine junk regenerates and may be pre-selected;
//  the user's own files are revealed, sized and sorted, and are never pre-selected or swept.**
//  Nothing is deleted either way — anything removed is quarantined with a 30-day undo. A large
//  folder is not a problem, it is large.

struct StorageView: View {
    var body: some View { SectionFace(.storage) }
}

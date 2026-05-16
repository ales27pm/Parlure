//
//  RootTabView.swift
//  Parlure
//

import SwiftUI

struct RootTabView: View {
    @State private var selection: Tab = .record

    enum Tab: Hashable { case record, archive, settings }

    var body: some View {
        TabView(selection: $selection) {
            ConversationView()
                .tabItem { Label("Parler", systemImage: "mic.fill") }
                .tag(Tab.record)

            ArchiveView()
                .tabItem { Label("Archive", systemImage: "books.vertical.fill") }
                .tag(Tab.archive)

            SettingsView()
                .tabItem { Label("Réglages", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .tint(Theme.mapleRed)
    }
}

#Preview {
    RootTabView()
}

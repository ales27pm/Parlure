//
//  ContentView.swift
//  Parlure
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View { RootTabView() }
}

#Preview {
    RootTabView()
        .modelContainer(for: [DialogueTurn.self, GlossaryEntry.self], inMemory: true)
}

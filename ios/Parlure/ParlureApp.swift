//
//  ParlureApp.swift
//  Parlure
//

import SwiftUI
import SwiftData

@main
struct ParlureApp: App {
    let container: ModelContainer = {
        let schema = Schema([DialogueTurn.self, GlossaryEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }
}

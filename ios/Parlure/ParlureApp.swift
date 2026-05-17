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
        let diskConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [diskConfig])
        } catch {
            assertionFailure("Could not create on-disk ModelContainer: \(error). Falling back to in-memory container.")

            let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [memoryConfig])
            } catch {
                fatalError("Could not create fallback in-memory ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }
}

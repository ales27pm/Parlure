//
//  ParlureApp.swift
//  Parlure
//

import SwiftUI
import SwiftData
import OSLog

@main
struct ParlureApp: App {
    private static let logger = Logger(subsystem: "com.27pm.parlure", category: "Persistence")

    let container: ModelContainer = makeModelContainer()

    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([DialogueTurn.self, GlossaryEntry.self])
        let diskConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [diskConfig])
        } catch {
            logger.fault("Failed to initialize on-disk ModelContainer: \(error.localizedDescription, privacy: .public). Falling back to in-memory container; data will not persist.")
            assertionFailure("Could not create on-disk ModelContainer: \(error). Falling back to in-memory container.")

            let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [memoryConfig])
            } catch {
                logger.critical("Failed to initialize in-memory fallback ModelContainer: \(error.localizedDescription, privacy: .public)")
                fatalError("Could not create fallback in-memory ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }
}

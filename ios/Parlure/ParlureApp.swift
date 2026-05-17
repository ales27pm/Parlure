//
//  ParlureApp.swift
//  Parlure
//

import SwiftUI
import SwiftData
import OSLog

@main
struct ParlureApp: App {
    enum StorageMode {
        case persistent
        case inMemoryFallback
    }

    struct ContainerInitializationResult {
        let container: ModelContainer
        let storageMode: StorageMode
    }

    private static let logger = Logger(subsystem: "com.27pm.parlure", category: "Persistence")
    private static let fallbackTimestampKey = "PersistenceFallbackTimestamp"

    let container: ModelContainer
    @State private var storageMode: StorageMode
    @State private var showInMemoryFallbackAlert: Bool

    init() {
        let result = Self.makeModelContainer()
        container = result.container
        _storageMode = State(initialValue: result.storageMode)
        _showInMemoryFallbackAlert = State(initialValue: result.storageMode == .inMemoryFallback)
    }

    private static func makeModelContainer() -> ContainerInitializationResult {
        let schema = Schema([DialogueTurn.self, GlossaryEntry.self])
        let diskConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return ContainerInitializationResult(
                container: try ModelContainer(for: schema, configurations: [diskConfig]),
                storageMode: .persistent
            )
        } catch {
            logger.error("ModelContainer on-disk initialization failed: \(String(describing: error), privacy: .public). Falling back to in-memory container; data will not persist.")
#if DEBUG
            assertionFailure("Could not create on-disk ModelContainer: \(error). Falling back to in-memory container.")
#endif
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: fallbackTimestampKey)

            let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return ContainerInitializationResult(
                    container: try ModelContainer(for: schema, configurations: [memoryConfig]),
                    storageMode: .inMemoryFallback
                )
            } catch {
                logger.critical("Failed to initialize in-memory fallback ModelContainer: \(error.localizedDescription, privacy: .public)")
                fatalError("Could not create fallback in-memory ModelContainer: \(error)")
            }
        }
    }

    private static func retryDiskInitializationDiagnostic() {
        let schema = Schema([DialogueTurn.self, GlossaryEntry.self])
        let diskConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            _ = try ModelContainer(for: schema, configurations: [diskConfig])
            logger.notice("ModelContainer disk initialization retry succeeded. Persistence should work on next launch.")
        } catch {
            logger.error("ModelContainer disk initialization retry failed: \(String(describing: error), privacy: .public)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .alert("Storage fallback enabled", isPresented: $showInMemoryFallbackAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Parlure could not access persistent storage and is running in temporary in-memory mode. Your data may not persist after closing the app.")
                }
                .task(id: storageMode) {
                    guard storageMode == .inMemoryFallback else { return }
                    try? await Task.sleep(for: .seconds(5))
                    Self.retryDiskInitializationDiagnostic()
                }
        }
        .modelContainer(container)
    }
}

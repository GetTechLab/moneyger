import SwiftData
import Foundation

@MainActor
final class SwiftDataStack {
    static let shared = SwiftDataStack()

    let container: ModelContainer

    private init() {
        let schema = Schema([
            Transaction.self,
            Account.self,
            ProcessedEmail.self
        ])
        // Pinned to the app's own container: with the default `.automatic`, adding the App Group
        // (used only for the Share Extension inbox) silently moves the store and starts empty
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, groupContainer: .none)
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }
}

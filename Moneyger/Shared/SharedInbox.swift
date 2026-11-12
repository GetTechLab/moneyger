import Foundation

/// Hand-off folder between the Share Extension and the app, inside the shared App Group container.
/// The extension only copies files here (it has tight memory/time limits and no API keys);
/// the app picks them up the next time it becomes active and runs the normal import.
///
/// Layout: `Inbox/<share id>/<files>`; one folder per share, so several screenshots
/// shared together are imported as one document.
enum SharedInbox {
    static let appGroup = "group.com.moneyger.app"

    static var inboxURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("Inbox", isDirectory: true)
    }

    /// Creates a new folder for one share and returns it.
    static func makeShareFolder() throws -> URL {
        guard let inboxURL else { throw CocoaError(.fileNoSuchFile) }
        // Timestamp prefix keeps folders in share order
        let name = "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString)"
        let folder = inboxURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Pending share folders, oldest first.
    static func pendingShares() -> [URL] {
        guard let inboxURL,
              let folders = try? FileManager.default.contentsOfDirectory(
                at: inboxURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
              ) else { return [] }
        return folders.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func files(in share: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: share, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func remove(_ share: URL) {
        try? FileManager.default.removeItem(at: share)
    }
}

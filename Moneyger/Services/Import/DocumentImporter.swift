import Foundation
import SwiftData
import CryptoKit

/// A file or set of screenshots the user wants to import.
struct ImportRequest: Identifiable {
    enum Source {
        case file(URL)
        case images([Data])
    }

    let id = UUID()
    let source: Source
}

/// Receives import requests from anywhere in the app (Files "Open in", the share sheet,
/// or the dashboard menu) and hands them to the sheet presented by `MainTabView`.
@MainActor
final class DocumentImportCenter: ObservableObject {
    @Published var request: ImportRequest? {
        didSet {
            // Sheet closed: show the next queued import once the dismissal animation is done
            if request == nil, !queue.isEmpty {
                Task {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    presentNext()
                }
            }
        }
    }

    /// Imports waiting for the current sheet to close (e.g. several files shared at once).
    private var queue: [ImportRequest] = []

    func open(_ url: URL) {
        enqueue(ImportRequest(source: .file(url)))
    }

    func importImages(_ images: [Data]) {
        guard !images.isEmpty else { return }
        enqueue(ImportRequest(source: .images(images)))
    }

    /// Picks up everything the Share Extension dropped into the App Group inbox.
    /// Each PDF becomes its own import; images from one share are imported together.
    func checkSharedInbox() {
        for share in SharedInbox.pendingShares() {
            let files = SharedInbox.files(in: share)
            for pdf in files where pdf.pathExtension.lowercased() == "pdf" {
                // Moved out of the inbox first so a crash mid-import can't re-import it forever
                let copy = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("pdf")
                if (try? FileManager.default.copyItem(at: pdf, to: copy)) != nil {
                    queue.append(ImportRequest(source: .file(copy)))
                }
            }
            let images = files
                .filter { $0.pathExtension.lowercased() != "pdf" }
                .compactMap { try? Data(contentsOf: $0) }
            if !images.isEmpty {
                queue.append(ImportRequest(source: .images(images)))
            }
            SharedInbox.remove(share)
        }
        if request == nil { presentNext() }
    }

    private func enqueue(_ newRequest: ImportRequest) {
        queue.append(newRequest)
        if request == nil { presentNext() }
    }

    private func presentNext() {
        guard request == nil, !queue.isEmpty else { return }
        request = queue.removeFirst()
    }
}

/// Runs one import: on-device text extraction → AI analysis → save.
@MainActor
final class DocumentImporter: ObservableObject {
    enum Phase: Equatable {
        case reading
        case analyzing(part: Int, of: Int)
        case finished(Outcome)
        case failed(String)
    }

    enum Outcome: Equatable {
        case imported(bank: String, last4: String?, saved: Int, duplicates: Int, hasStatement: Bool)
        case notFinancial
        case alreadyImported
    }

    @Published private(set) var phase: Phase = .reading
    /// Exactly what was read from the document, page by page; shown in the sheet to diagnose bad extractions.
    @Published private(set) var extractedText: String?

    func run(_ request: ImportRequest, context: ModelContext, provider: any AIProvider) async {
        phase = .reading
        do {
            let (pages, kind, title) = try await readPages(from: request.source)
            extractedText = pages.enumerated()
                .map { "— Page \($0.offset + 1) —\n\($0.element)" }
                .joined(separator: "\n\n")
            guard pages.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw DocumentTextExtractor.ExtractionError.noText
            }

            // Same content imported twice (e.g. shared again) is recognized by hash and skipped
            let sourceId = "doc-" + Self.fingerprint(of: pages)
            let emailRepo = EmailRepository(context: context)
            if try emailRepo.isProcessed(sourceId) {
                phase = .finished(.alreadyImported)
                return
            }

            let importedAt = Date()
            let analyzed = try await provider.analyzeDocument(
                pages: pages,
                kind: kind,
                title: title,
                importedAt: importedAt
            ) { [weak self] part, total in
                self?.phase = .analyzing(part: part, of: total)
            }

            guard var extraction = analyzed else {
                phase = .finished(.notFinancial)
                return
            }
            // Consecutive screenshots of a scrolling list overlap; drop the repeated rows
            if kind == .screenshot, pages.count > 1 {
                extraction = extraction.removingRepeatedRows()
            }

            let result = try ExtractionStore(context: context).save(
                extraction,
                sourceId: sourceId,
                receivedDate: importedAt,
                forceStatement: true
            )
            try emailRepo.markProcessed(sourceId, wasFinancial: true, transactionCount: result.savedCount)

            phase = .finished(.imported(
                bank: result.account.bankName,
                last4: result.account.last4,
                saved: result.savedCount,
                duplicates: result.duplicateCount,
                hasStatement: extraction.statementBalance != nil
            ))
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func readPages(from source: ImportRequest.Source) async throws -> ([String], AIPrompts.DocumentKind, String) {
        switch source {
        case .file(let url):
            // Files from the share sheet / Files app are security scoped
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            if url.pathExtension.lowercased() == "pdf" {
                return (try await DocumentTextExtractor.pages(fromPDF: url), .pdf, url.lastPathComponent)
            }
            let data = try Data(contentsOf: url)
            return ([try await DocumentTextExtractor.text(fromImage: data)], .screenshot, url.lastPathComponent)

        case .images(let images):
            var pages: [String] = []
            for data in images {
                pages.append(try await DocumentTextExtractor.text(fromImage: data))
            }
            let title = images.count == 1 ? "Screenshot" : "\(images.count) screenshots"
            return (pages, .screenshot, title)
        }
    }

    private static func fingerprint(of pages: [String]) -> String {
        let digest = SHA256.hash(data: Data(pages.joined(separator: "\u{1E}").utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

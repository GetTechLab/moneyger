import Foundation
import SwiftData

@MainActor
final class EmailProcessingPipeline: ObservableObject {
    @Published var isProcessing = false
    @Published var progress: ProcessingProgress = .idle
    @Published var lastSyncDate: Date? {
        didSet { UserDefaults.standard.set(lastSyncDate, forKey: "lastSyncDate") }
    }

    private var gmailAPI: GmailAPIService?
    private var emailRepo: EmailRepository?
    private var transactionRepo: TransactionRepository?
    private var context: ModelContext?
    var provider: (any AIProvider)?

    /// How far back the very first sync looks.
    static let initialSyncDays = 30

    // Lazy placeholder — sçetup() must be called before sync()
    static var placeholder: EmailProcessingPipeline { EmailProcessingPipeline() }

    private init() {
        self.lastSyncDate = UserDefaults.standard.object(forKey: "lastSyncDate") as? Date
    }

    func setup(context: ModelContext, provider: any AIProvider, authService: GmailAuthService) {
        self.context = context
        self.provider = provider
        self.gmailAPI = GmailAPIService(authService: authService)
        self.emailRepo = EmailRepository(context: context)
        self.transactionRepo = TransactionRepository(context: context)
    }

    func sync() async {
        guard !isProcessing else { return }
        guard let gmailAPI, let emailRepo, let transactionRepo, let provider else {
            progress = .failed("Pipeline not configured")
            isProcessing = false
            return
        }

        isProcessing = true
        progress = .fetchingEmails

        do {
            // 1. Fetch message IDs from Gmail: since the last sync, or the last 30 days on first sync.
            // The window end is captured before fetching so emails arriving mid-sync are caught next time
            // (any overlap is harmless thanks to the processed-ID dedup).
            let syncStartedAt = Date()
            let since = lastSyncDate ?? Calendar.current.date(
                byAdding: .day, value: -Self.initialSyncDays, to: syncStartedAt
            ) ?? syncStartedAt
            let allIds = try await gmailAPI.fetchMessageIds(after: since)

            // 2. Dedup: skip already processed
            let newIds = try emailRepo.unprocessedIds(from: allIds)
            guard !newIds.isEmpty else {
                progress = .completed(newTransactions: 0)
                isProcessing = false
                return
            }

            // Progress is reported against the full list, so a resumed sync continues
            // from where the previous one stopped (e.g. 40/97) instead of looking like a restart.
            let total = allIds.count
            let alreadyDone = total - newIds.count
            progress = .classifying(total: total, done: alreadyDone)

            var totalNewTransactions = 0
            var skippedCount = 0

            // 3. Fetch and process each email
            for (index, messageId) in newIds.enumerated() {
                let done = alreadyDone + index
                progress = .classifying(total: total, done: done)

                do {
                    totalNewTransactions += try await processEmail(
                        messageId,
                        done: done,
                        total: total,
                        gmailAPI: gmailAPI,
                        emailRepo: emailRepo,
                        transactionRepo: transactionRepo,
                        provider: provider
                    )
                } catch let error as AIError {
                    // Permanent API errors (no credits, invalid key) affect every email: stop.
                    if case .httpError = error, !error.isTransient { throw error }
                    // Still overloaded after retries, or empty response:
                    // leave unprocessed so the next sync tries this email again.
                    skippedCount += 1
                } catch is DecodingError {
                    // Malformed AI output for this email only.
                    skippedCount += 1
                }
            }

            // Only advance the sync window when everything was handled,
            // otherwise skipped emails would fall outside the next fetch.
            if skippedCount == 0 {
                lastSyncDate = syncStartedAt
            }
            progress = .completed(newTransactions: totalNewTransactions, skipped: skippedCount)

        } catch {
            progress = .failed(error.localizedDescription)
        }

        isProcessing = false
    }

    /// Analyzes one email with a single AI request and saves the results.
    /// The email is only marked processed after the AI call succeeded and everything is saved,
    /// so a failure never leaves half the transactions saved (which would duplicate on retry).
    private func processEmail(
        _ messageId: String,
        done: Int,
        total: Int,
        gmailAPI: GmailAPIService,
        emailRepo: EmailRepository,
        transactionRepo: TransactionRepository,
        provider: any AIProvider
    ) async throws -> Int {
        let email = try await gmailAPI.fetchMessage(id: messageId)

        // Quick pre-filter: obviously non-financial emails never reach the AI
        guard gmailAPI.isLikelyFinancial(domain: email.senderDomain, subject: email.subject) else {
            try emailRepo.markProcessed(messageId, wasFinancial: false)
            return 0
        }

        // Single AI call: classification, extraction and categorization together
        progress = .extracting(total: total, done: done)
        guard let extraction = try await withRetry({ try await provider.analyzeEmail(email) }) else {
            try emailRepo.markProcessed(messageId, wasFinancial: false)
            return 0
        }

        guard let context else { throw PipelineError.notConfigured }
        let result = try ExtractionStore(context: context)
            .save(extraction, sourceId: messageId, receivedDate: email.receivedDate)

        try emailRepo.markProcessed(messageId, wasFinancial: true, transactionCount: result.savedCount)
        return result.savedCount
    }

    private func withRetry<T>(_ operation: () async throws -> T) async throws -> T {
        try await withAIRetry(operation)
    }
}

/// Retries transient AI errors (e.g. 503 "high demand", 429 rate limit) with exponential backoff.
func withAIRetry<T>(maxAttempts: Int = 4, _ operation: () async throws -> T) async throws -> T {
    var attempt = 1
    var delay: UInt64 = 2
    while true {
        do {
            return try await operation()
        } catch let error as AIError where error.isTransient && attempt < maxAttempts {
            try await Task.sleep(nanoseconds: delay * 1_000_000_000)
            attempt += 1
            delay *= 2
        }
    }
}

enum PipelineError: Error {
    case notConfigured
}

enum ProcessingProgress: Equatable {
    case idle
    case fetchingEmails
    case classifying(total: Int, done: Int)
    case extracting(total: Int, done: Int)
    case completed(newTransactions: Int, skipped: Int = 0)
    case failed(String)

    var statusMessage: String {
        switch self {
        case .idle: return "Ready to sync"
        case .fetchingEmails: return "Fetching emails..."
        case .classifying(let total, let done): return "Analyzing \(done)/\(total) emails..."
        case .extracting(let total, let done): return "Extracting from \(done)/\(total) emails..."
        case .completed(let count, let skipped):
            let result = count > 0 ? "Found \(count) new transactions" : "Up to date"
            return skipped > 0 ? "\(result) · \(skipped) emails skipped (AI busy), sync again to retry" : result
        case .failed(let msg): return "Error: \(msg)"
        }
    }
}

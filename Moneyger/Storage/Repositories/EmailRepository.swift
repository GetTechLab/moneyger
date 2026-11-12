import SwiftData
import Foundation

@MainActor
final class EmailRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func isProcessed(_ messageId: String) throws -> Bool {
        let descriptor = FetchDescriptor<ProcessedEmail>(
            predicate: #Predicate { $0.gmailMessageId == messageId }
        )
        return try !context.fetch(descriptor).isEmpty
    }

    func markProcessed(_ messageId: String, wasFinancial: Bool, transactionCount: Int = 0) throws {
        let entry = ProcessedEmail(
            gmailMessageId: messageId,
            wasFinancial: wasFinancial,
            extractedTransactionCount: transactionCount
        )
        context.insert(entry)
        try context.save()
    }

    func unprocessedIds(from ids: [String]) throws -> [String] {
        // One query for all candidates instead of one query per id
        let descriptor = FetchDescriptor<ProcessedEmail>(
            predicate: #Predicate { ids.contains($0.gmailMessageId) }
        )
        let processed = Set(try context.fetch(descriptor).map(\.gmailMessageId))
        return ids.filter { !processed.contains($0) }
    }

    func processedCount() throws -> Int {
        let descriptor = FetchDescriptor<ProcessedEmail>()
        return try context.fetchCount(descriptor)
    }
}

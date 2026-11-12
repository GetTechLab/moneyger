import SwiftData
import Foundation

@MainActor
final class TransactionRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func save(_ transaction: Transaction) throws {
        context.insert(transaction)
        try context.save()
    }

    func saveAll(_ transactions: [Transaction]) throws {
        transactions.forEach { context.insert($0) }
        try context.save()
    }

    func fetchAll() throws -> [Transaction] {
        let descriptor = FetchDescriptor<Transaction>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetch(for currency: String) throws -> [Transaction] {
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.currency == currency },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetch(from startDate: Date, to endDate: Date) throws -> [Transaction] {
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.date >= startDate && $0.date <= endDate },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func delete(_ transaction: Transaction) throws {
        context.delete(transaction)
        try context.save()
    }
}

import Foundation
import SwiftData

@MainActor
final class TransactionsViewModel: ObservableObject {
    @Published var transactions: [Transaction] = []
    @Published var searchText = ""
    @Published var selectedCategory: TransactionCategory?
    @Published var selectedCurrency: String?

    private var repo: TransactionRepository?

    func setup(context: ModelContext) {
        repo = TransactionRepository(context: context)
    }

    func load() async {
        guard let repo else { return }
        do {
            transactions = try repo.fetchAll()
        } catch {
            print("TransactionsViewModel load error: \(error)")
        }
    }

    var filtered: [Transaction] {
        transactions.filter { transaction in
            let matchesSearch = searchText.isEmpty ||
                transaction.transactionDescription.localizedCaseInsensitiveContains(searchText) ||
                (transaction.account?.bankName.localizedCaseInsensitiveContains(searchText) ?? false)
            let matchesCategory = selectedCategory == nil ||
                transaction.category == selectedCategory!.rawValue
            let matchesCurrency = selectedCurrency == nil ||
                transaction.currency == selectedCurrency!
            return matchesSearch && matchesCategory && matchesCurrency
        }
    }

    /// Filtered transactions grouped by calendar day, newest day first.
    var groupedByDay: [(day: Date, transactions: [Transaction])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.date) }
        return groups
            .map { (day: $0.key, transactions: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    var availableCurrencies: [String] {
        Array(Set(transactions.map(\.currency))).sorted()
    }

    func updateCategory(_ transaction: Transaction, category: TransactionCategory) throws {
        transaction.category = category.rawValue
        transaction.isManuallyEdited = true
        try repo?.saveAll([])
    }

    func delete(_ transaction: Transaction) throws {
        try repo?.delete(transaction)
        Task { await load() }
    }
}

import Foundation
import SwiftData

/// Spending of one account in a calendar month, used for the wallet detail chart.
struct MonthlySpending: Identifiable {
    let month: Date
    let amount: Double

    var id: Date { month }
}

@MainActor
final class AccountsViewModel: ObservableObject {
    @Published var accounts: [Account] = []
    @Published private(set) var rates: ExchangeRates?

    private var context: ModelContext?
    private let rateService = ExchangeRateService.shared

    /// Shares the dashboard's choice so both screens total in the same currency.
    var displayCurrency: String {
        UserDefaults.standard.string(forKey: "dashboard.displayCurrency") ?? "TRY"
    }

    init() {
        rates = rateService.cachedRates
    }

    func setup(context: ModelContext) {
        self.context = context
    }

    func load() async {
        guard let context else { return }
        do {
            let descriptor = FetchDescriptor<Account>(
                sortBy: [SortDescriptor(\.bankName)]
            )
            accounts = try context.fetch(descriptor)
        } catch {
            print("AccountsViewModel load error: \(error)")
        }
        rates = await rateService.latestRates()
    }

    // MARK: - Per-account figures (in the account's own currency)

    func totalSpent(for account: Account, currency: String) -> Double {
        account.transactions.filter { $0.isExpense && $0.currency == currency }
            .reduce(0) { $0 + $1.absoluteAmount }
    }

    func spentThisMonth(for account: Account) -> Double {
        let start = Period.thisMonth.dateRange.0
        return account.transactions
            .filter { $0.isExpense && $0.currency == account.currency && $0.date >= start }
            .reduce(0) { $0 + $1.absoluteAmount }
    }

    func transactionCount(for account: Account) -> Int {
        account.transactions.count
    }

    func recentTransactions(for account: Account, limit: Int = 8) -> [Transaction] {
        Array(account.transactions.sorted { $0.date > $1.date }.prefix(limit))
    }

    /// Spending for each of the last `months` calendar months, oldest first, including empty months.
    func monthlySpending(for account: Account, months: Int = 6) -> [MonthlySpending] {
        let calendar = Calendar.current
        guard let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) else {
            return []
        }

        var totals: [Date: Double] = [:]
        for transaction in account.transactions where transaction.isExpense && transaction.currency == account.currency {
            if let month = calendar.date(from: calendar.dateComponents([.year, .month], from: transaction.date)) {
                totals[month, default: 0] += transaction.absoluteAmount
            }
        }

        return (0..<months).reversed().compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: currentMonth)
                .map { MonthlySpending(month: $0, amount: totals[$0] ?? 0) }
        }
    }

    // MARK: - Wallet totals (converted to the display currency)

    func convert(_ amount: Double, from currency: String) -> Double? {
        if currency == displayCurrency { return amount }
        return rates?.convert(amount, from: currency, to: displayCurrency)
    }

    /// This month's spending across every account, converted; accounts without a rate are skipped.
    var walletSpentThisMonth: Double {
        accounts.reduce(0) { $0 + (convert(spentThisMonth(for: $1), from: $1.currency) ?? 0) }
    }

    // MARK: - Actions

    /// Deletes the account and, via the cascade rule, all of its transactions.
    /// The source emails stay marked as processed, so the next sync won't re-import them.
    func delete(_ account: Account) {
        guard let context else { return }
        context.delete(account)
        do {
            try context.save()
        } catch {
            print("AccountsViewModel delete error: \(error)")
        }
        accounts.removeAll { $0.id == account.id }
    }
}

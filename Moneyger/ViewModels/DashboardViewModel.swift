import Foundation
import SwiftData
import Combine

/// Per-currency totals for the selected period, with their value in the display currency.
struct CurrencySummary: Identifiable {
    let currency: String
    let income: Double
    let expenses: Double
    let transactionCount: Int
    /// Net amount converted to the display currency; nil when no rate is available.
    let convertedNet: Double?
    /// Value of 1 unit of `currency` in the display currency.
    let unitRate: Double?

    var id: String { currency }
    var net: Double { income - expenses }
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var transactions: [Transaction] = []
    @Published var selectedPeriod: Period = .thisMonth
    /// Every amount on the dashboard is converted into this currency.
    @Published var displayCurrency: String = UserDefaults.standard.string(forKey: "dashboard.displayCurrency") ?? "TRY" {
        didSet { UserDefaults.standard.set(displayCurrency, forKey: "dashboard.displayCurrency") }
    }
    @Published private(set) var rates: ExchangeRates?
    @Published private(set) var isRefreshingRates = false

    private var transactionRepo: TransactionRepository?
    private let rateService = ExchangeRateService.shared

    /// Currencies always offered in the picker, even without matching transactions.
    private static let commonCurrencies = ["TRY", "USD", "EUR", "GBP"]

    init() {
        rates = rateService.cachedRates
    }

    func setup(context: ModelContext) {
        transactionRepo = TransactionRepository(context: context)
    }

    func load() async {
        guard let repo = transactionRepo else { return }
        do {
            transactions = try repo.fetchAll()
        } catch {
            print("DashboardViewModel load error: \(error)")
        }
        await refreshRates()
    }

    func refreshRates(force: Bool = false) async {
        isRefreshingRates = true
        rates = await rateService.latestRates(force: force)
        isRefreshingRates = false
    }

    var availableCurrencies: [String] {
        Set(transactions.map(\.currency) + Self.commonCurrencies).sorted()
    }

    // MARK: - Conversion

    func convert(_ amount: Double, from currency: String) -> Double? {
        if currency == displayCurrency { return amount }
        return rates?.convert(amount, from: currency, to: displayCurrency)
    }

    /// Converted amount of a transaction, only when it's in a foreign currency.
    func convertedAmount(of transaction: Transaction) -> Double? {
        transaction.currency == displayCurrency ? nil : convert(transaction.amount, from: transaction.currency)
    }

    // MARK: - Period data

    /// All transactions in the selected period, regardless of currency.
    var periodTransactions: [Transaction] {
        let (start, end) = selectedPeriod.dateRange
        return transactions.filter { $0.date >= start && $0.date <= end }
    }

    /// Period transactions that can be expressed in the display currency.
    var filteredTransactions: [Transaction] {
        periodTransactions.filter { convert($0.amount, from: $0.currency) != nil }
    }

    /// Transactions that count as real income/spending. Transfers between the user's own
    /// accounts (e.g. paying the credit card) would otherwise be counted twice.
    private var flowTransactions: [Transaction] {
        filteredTransactions.filter { $0.transactionCategory != .transfer }
    }

    /// Currencies in the period that couldn't be converted (no rate yet) and are left out of totals.
    var unconvertedCurrencies: [String] {
        Set(periodTransactions.map(\.currency))
            .filter { convert(1, from: $0) == nil }
            .sorted()
    }

    /// True when any total on screen is derived from a currency conversion.
    var usesConversion: Bool {
        filteredTransactions.contains { $0.currency != displayCurrency }
    }

    var totalExpenses: Double {
        flowTransactions.filter(\.isExpense).reduce(0) { $0 + abs(convert($1.amount, from: $1.currency) ?? 0) }
    }

    var totalIncome: Double {
        filteredTransactions.filter(\.isIncome).reduce(0) { $0 + (convert($1.amount, from: $1.currency) ?? 0) }
    }

    var netBalance: Double { totalIncome - totalExpenses }

    var currencyBreakdown: [CurrencySummary] {
        Dictionary(grouping: periodTransactions, by: \.currency)
            .map { currency, items in
                let income = items.filter(\.isIncome).reduce(0) { $0 + $1.amount }
                let expenses = items.filter(\.isExpense).reduce(0) { $0 + $1.absoluteAmount }
                return CurrencySummary(
                    currency: currency,
                    income: income,
                    expenses: expenses,
                    transactionCount: items.count,
                    convertedNet: convert(income - expenses, from: currency),
                    unitRate: convert(1, from: currency)
                )
            }
            // Display currency first, then by converted size
            .sorted { lhs, rhs in
                if lhs.currency == displayCurrency { return true }
                if rhs.currency == displayCurrency { return false }
                return abs(lhs.convertedNet ?? 0) > abs(rhs.convertedNet ?? 0)
            }
    }

    var spendingByCategory: [(category: String, amount: Double)] {
        let expenses = flowTransactions.filter(\.isExpense)
        var grouped: [String: Double] = [:]
        for t in expenses {
            grouped[t.category, default: 0] += abs(convert(t.amount, from: t.currency) ?? 0)
        }
        return grouped.map { ($0.key, $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    var recentTransactions: [Transaction] {
        Array(periodTransactions.prefix(10))
    }

    // MARK: - Spending history

    @Published var historyGranularity: HistoryGranularity = .monthly

    static let unassignedBank = "No Account"
    static let otherBanks = "Other"

    private func bankName(of transaction: Transaction) -> String {
        transaction.account?.bankName ?? Self.unassignedBank
    }

    /// Banks shown as their own series, in a fixed name order so a bank keeps its color.
    /// Beyond the palette size, the smallest spenders fold into "Other".
    var historyBanks: [String] {
        var totals: [String: Double] = [:]
        for t in transactions where t.isExpense && t.transactionCategory != .transfer {
            totals[bankName(of: t), default: 0] += abs(convert(t.amount, from: t.currency) ?? 0)
        }
        let maxSeries = AppTheme.seriesColors.count
        let ranked = totals.sorted { $0.value > $1.value }.map(\.key)
        guard ranked.count > maxSeries else { return ranked.sorted() }
        return ranked.prefix(maxSeries - 1).sorted() + [Self.otherBanks]
    }

    /// Start dates of the visible buckets, oldest first, ending with the current one.
    var historyBuckets: [Date] {
        let calendar = Calendar.current
        guard let current = calendar.dateInterval(of: historyGranularity.component, for: Date())?.start else {
            return []
        }
        return (0..<historyGranularity.bucketCount).reversed().compactMap {
            calendar.date(byAdding: historyGranularity.component, value: -$0, to: current)
        }
    }

    /// Expenses per bank per bucket, converted to the display currency.
    var bankSpendingHistory: [BankSpending] {
        let calendar = Calendar.current
        let buckets = Set(historyBuckets)
        let banks = historyBanks
        let namedBanks = Set(banks)

        var totals: [Date: [String: Double]] = [:]
        for t in transactions where t.isExpense && t.transactionCategory != .transfer {
            guard let bucket = calendar.dateInterval(of: historyGranularity.component, for: t.date)?.start,
                  buckets.contains(bucket),
                  let amount = convert(t.amount, from: t.currency) else { continue }
            let bank = namedBanks.contains(bankName(of: t)) ? bankName(of: t) : Self.otherBanks
            totals[bucket, default: [:]][bank, default: 0] += abs(amount)
        }

        return historyBuckets.flatMap { bucket in
            banks.compactMap { bank in
                totals[bucket]?[bank].map { BankSpending(bucket: bucket, bank: bank, amount: $0) }
            }
        }
    }

    /// Per-bank spending for one bucket, largest first.
    func bankBreakdown(for bucket: Date) -> [BankSpending] {
        bankSpendingHistory.filter { $0.bucket == bucket }.sorted { $0.amount > $1.amount }
    }

    /// Number of cards/accounts behind a bank name, for the breakdown subtitle.
    func accountCount(forBank bank: String) -> Int {
        Set(transactions.compactMap { $0.account }.filter { $0.bankName == bank }.map(\.id)).count
    }
}

enum HistoryGranularity: String, CaseIterable, Identifiable {
    case weekly = "Weekly"
    case monthly = "Monthly"

    var id: String { rawValue }

    var component: Calendar.Component {
        self == .weekly ? .weekOfYear : .month
    }

    var bucketCount: Int {
        self == .weekly ? 8 : 6
    }
}

struct BankSpending: Identifiable {
    let bucket: Date
    let bank: String
    let amount: Double

    var id: String { "\(bucket.timeIntervalSince1970)-\(bank)" }
}

enum Period: String, CaseIterable, Identifiable {
    case thisWeek = "This Week"
    case thisMonth = "This Month"
    case last3Months = "Last 3 Months"
    case thisYear = "This Year"
    case allTime = "All Time"

    var id: String { rawValue }

    var dateRange: (Date, Date) {
        let now = Date()
        let calendar = Calendar.current
        switch self {
        case .thisWeek:
            let start = calendar.date(byAdding: .day, value: -7, to: now)!
            return (start, now)
        case .thisMonth:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            return (start, now)
        case .last3Months:
            let start = calendar.date(byAdding: .month, value: -3, to: now)!
            return (start, now)
        case .thisYear:
            let start = calendar.date(from: calendar.dateComponents([.year], from: now))!
            return (start, now)
        case .allTime:
            return (Date.distantPast, now)
        }
    }
}

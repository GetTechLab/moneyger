import SwiftUI
import SwiftData

struct TransactionsListView: View {
    @Environment(\.modelContext) private var context
    @StateObject private var viewModel = TransactionsViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    filterBar
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                ForEach(viewModel.groupedByDay, id: \.day) { group in
                    Section {
                        ForEach(group.transactions) { transaction in
                            NavigationLink {
                                TransactionDetailView(transaction: transaction, viewModel: viewModel)
                            } label: {
                                TransactionRow(transaction: transaction, showsDate: false)
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                try? viewModel.delete(group.transactions[index])
                            }
                        }
                    } header: {
                        DaySectionHeader(day: group.day, transactions: group.transactions)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if viewModel.filtered.isEmpty {
                    ContentUnavailableView(
                        viewModel.transactions.isEmpty ? "No Transactions Yet" : "No Matches",
                        systemImage: viewModel.transactions.isEmpty ? "tray" : "magnifyingglass",
                        description: Text(viewModel.transactions.isEmpty
                            ? "Sync your Gmail from the Dashboard to import transactions."
                            : "Try a different search or filter.")
                    )
                }
            }
            .navigationTitle("Transactions")
            .searchable(text: $viewModel.searchText, prompt: "Search transactions")
            .task {
                viewModel.setup(context: context)
                await viewModel.load()
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("All Categories") { viewModel.selectedCategory = nil }
                    ForEach(TransactionCategory.allCases, id: \.self) { cat in
                        Button {
                            viewModel.selectedCategory = cat
                        } label: {
                            Label(cat.rawValue, systemImage: cat.icon)
                        }
                    }
                } label: {
                    FilterChip(
                        label: viewModel.selectedCategory?.rawValue ?? "All Categories",
                        systemImage: viewModel.selectedCategory?.icon ?? "square.grid.2x2",
                        tint: viewModel.selectedCategory?.color ?? AppTheme.accent,
                        isActive: viewModel.selectedCategory != nil
                    )
                }

                if viewModel.availableCurrencies.count > 1 {
                    Menu {
                        Button("All Currencies") { viewModel.selectedCurrency = nil }
                        ForEach(viewModel.availableCurrencies, id: \.self) { currency in
                            Button(currency) { viewModel.selectedCurrency = currency }
                        }
                    } label: {
                        FilterChip(
                            label: viewModel.selectedCurrency ?? "All Currencies",
                            systemImage: "dollarsign.circle",
                            tint: AppTheme.accent,
                            isActive: viewModel.selectedCurrency != nil
                        )
                    }
                }

                if viewModel.selectedCategory != nil || viewModel.selectedCurrency != nil {
                    Button {
                        viewModel.selectedCategory = nil
                        viewModel.selectedCurrency = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Color(.secondarySystemGroupedBackground), in: Circle())
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct DaySectionHeader: View {
    let day: Date
    let transactions: [Transaction]

    private var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    /// Daily spending, shown only when every transaction of the day uses the same currency.
    private var dailySpending: (amount: Double, currency: String)? {
        let currencies = Set(transactions.map(\.currency))
        guard currencies.count == 1, let currency = currencies.first else { return nil }
        let spent = transactions.filter(\.isExpense).reduce(0) { $0 + $1.absoluteAmount }
        return spent > 0 ? (spent, currency) : nil
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if let dailySpending {
                Text(dailySpending.amount, format: .currency(code: dailySpending.currency))
                    .monospacedDigit()
            }
        }
        .font(.footnote.weight(.semibold))
        .textCase(nil)
    }
}

struct TransactionRow: View {
    let transaction: Transaction
    var showsDate: Bool = true
    /// Equivalent in the user's display currency, shown for foreign-currency transactions.
    var converted: (amount: Double, currency: String)? = nil

    private var subtitle: String {
        if showsDate {
            return transaction.date.formatted(date: .abbreviated, time: .omitted)
        }
        return transaction.account?.bankName ?? transaction.category
    }

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: transaction.transactionCategory)

            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.transactionDescription)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                // Expenses in the primary color, income highlighted in green, with explicit sign
                Text(verbatim: (transaction.isExpense ? "−" : "+")
                     + transaction.absoluteAmount.formatted(.currency(code: transaction.currency)))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(transaction.isExpense ? Color.primary : AppTheme.income)
                if let converted {
                    Text(verbatim: "≈ " + abs(converted.amount).formatted(.currency(code: converted.currency)))
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(transaction.category)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(transaction.transactionCategory.color)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct FilterChip: View {
    let label: String
    let systemImage: String
    let tint: Color
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(label)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .foregroundStyle(isActive ? .white : .primary)
        .background(
            isActive ? AnyShapeStyle(tint) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
            in: Capsule()
        )
    }
}

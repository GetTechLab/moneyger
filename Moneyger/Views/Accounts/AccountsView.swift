import SwiftUI
import SwiftData
import Charts

struct AccountsView: View {
    @Environment(\.modelContext) var context
    @StateObject private var viewModel = AccountsViewModel()
    @EnvironmentObject private var importCenter: DocumentImportCenter
    /// Backs category edits made from the transaction detail screen.
    @StateObject private var transactionsViewModel = TransactionsViewModel()
    @State private var selectedAccountID: UUID?
    @State private var accountToDelete: Account?
    /// Live vertical drag on the selected card; pulling down far enough closes it.
    @State private var dragOffset: CGFloat = 0

    /// Height of the strip of each stacked card left visible, like in Wallet.
    private let peekHeight: CGFloat = 64
    private let cardHeight: CGFloat = 212

    private var selectedAccount: Account? {
        viewModel.accounts.first { $0.id == selectedAccountID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.accounts.isEmpty {
                    ContentUnavailableView(
                        "No Accounts Yet",
                        systemImage: "creditcard",
                        description: Text("Sync your Gmail to automatically detect bank accounts and credit cards.")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if selectedAccount == nil {
                                WalletSummaryHeader(viewModel: viewModel)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }

                            cardStack

                            if let account = selectedAccount {
                                AccountDetailPanel(
                                    account: account,
                                    viewModel: viewModel,
                                    transactionsViewModel: transactionsViewModel
                                ) {
                                    accountToDelete = account
                                }
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        .padding()
                    }
                    .scrollDisabled(selectedAccount == nil && viewModel.accounts.count < 4)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(selectedAccount == nil ? "Wallet" : "")
            .navigationBarTitleDisplayMode(selectedAccount == nil ? .large : .inline)
            .toolbar {
                if selectedAccount != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { select(nil) }
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: selectedAccountID)
            .confirmationDialog(
                "Delete \(accountToDelete?.bankName ?? "account")?",
                isPresented: Binding(
                    get: { accountToDelete != nil },
                    set: { if !$0 { accountToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Account and Transactions", role: .destructive) {
                    if let accountToDelete {
                        withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
                            selectedAccountID = nil
                            viewModel.delete(accountToDelete)
                        }
                    }
                    accountToDelete = nil
                }
            } message: {
                Text("All \(accountToDelete.map { viewModel.transactionCount(for: $0) } ?? 0) transactions of this account will be removed. The emails won't be imported again.")
            }
            .task {
                viewModel.setup(context: context)
                transactionsViewModel.setup(context: context)
                await viewModel.load()
            }
            // Accounts created by an import show up as soon as its sheet closes, even if this tab is open
            .onChange(of: importCenter.request == nil) { _, closed in
                if closed { Task { await viewModel.load() } }
            }
        }
    }

    // MARK: - Card stack

    /// All cards live in one ZStack so selecting one animates it in place
    /// while the others slide away, rather than swapping views.
    private var cardStack: some View {
        let accounts = viewModel.accounts
        let stackHeight = selectedAccount == nil
            ? cardHeight + CGFloat(max(accounts.count - 1, 0)) * peekHeight
            : cardHeight

        return ZStack(alignment: .top) {
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                let isSelected = account.id == selectedAccountID

                WalletCard(account: account, viewModel: viewModel)
                    .frame(height: cardHeight)
                    .offset(y: offset(for: index, isSelected: isSelected))
                    .scaleEffect(selectedAccountID == nil || isSelected ? 1 : 0.92, anchor: .top)
                    .opacity(selectedAccountID == nil || isSelected ? 1 : 0)
                    .zIndex(isSelected ? 100 : Double(index))
                    .onTapGesture { select(isSelected ? nil : account.id) }
                    .gesture(isSelected ? dismissDrag : nil)
                    .contextMenu {
                        Button("Delete Account", systemImage: "trash", role: .destructive) {
                            accountToDelete = account
                        }
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(isSelected ? "Closes account details" : "Shows account details")
            }
        }
        .frame(height: stackHeight, alignment: .top)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity)
    }

    private func offset(for index: Int, isSelected: Bool) -> CGFloat {
        guard selectedAccountID != nil else { return CGFloat(index) * peekHeight }
        // Selected card stays on top and follows the finger; the rest drop below the fold
        return isSelected ? max(dragOffset, 0) : cardHeight + 220
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in dragOffset = value.translation.height * 0.6 }
            .onEnded { value in
                if value.translation.height > 120 {
                    select(nil)
                } else {
                    withAnimation(.spring(duration: 0.35, bounce: 0.3)) { dragOffset = 0 }
                }
            }
    }

    private func select(_ id: UUID?) {
        withAnimation(.spring(duration: 0.5, bounce: 0.22)) {
            selectedAccountID = id
            dragOffset = 0
        }
    }
}

// MARK: - Wallet summary

private struct WalletSummaryHeader: View {
    @ObservedObject var viewModel: AccountsViewModel

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Spent this month")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(viewModel.walletSpentThisMonth, format: .currency(code: viewModel.displayCurrency))
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer()
            Text("^[\(viewModel.accounts.count) card](inflect: true)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Card

/// Payment-card style tile. Key info sits in the top strip so it stays readable when stacked.
struct WalletCard: View {
    let account: Account
    let viewModel: AccountsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top strip: visible while the card is tucked under the next one
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.bankName)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(account.type.displayName)
                        .font(.caption.weight(.medium))
                        .opacity(0.8)
                }
                Spacer()
                Text(verbatim: [AppTheme.currencyFlag(for: account.currency), account.currency]
                    .compactMap { $0 }
                    .joined(separator: " "))
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .heroGlass(in: Capsule())
            }

            Spacer(minLength: 12)

            HStack(spacing: 12) {
                if account.type == .creditCard {
                    CardChip()
                    Image(systemName: "wave.3.right")
                        .font(.title3.weight(.semibold))
                        .opacity(0.8)
                } else {
                    Image(systemName: account.type.icon)
                        .font(.title2)
                        .opacity(0.85)
                }
            }
            .accessibilityHidden(true)

            Spacer(minLength: 12)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("This month")
                        .font(.caption)
                        .opacity(0.8)
                    Text(viewModel.spentThisMonth(for: account), format: .currency(code: account.currency))
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer()
                if let last4 = account.last4 {
                    Text(verbatim: "•••• \(last4)")
                        .font(.system(.callout, design: .monospaced, weight: .semibold))
                        .opacity(0.9)
                        .accessibilityLabel("Ending in \(last4)")
                }
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            ZStack {
                AppTheme.cardGradient(for: account.bankName)
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 220)
                    .offset(x: 140, y: -90)
                Circle()
                    .fill(.white.opacity(0.07))
                    .frame(width: 160)
                    .offset(x: 170, y: 80)
                // Diagonal sheen so the card reads as a glossy physical object
                LinearGradient(
                    colors: [.white.opacity(0.18), .clear, .clear],
                    startPoint: .topLeading,
                    endPoint: .center
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.25), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Stylized EMV chip.
private struct CardChip: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.95, green: 0.84, blue: 0.55), Color(red: 0.78, green: 0.62, blue: 0.32)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 42, height: 32)
            .overlay {
                // Contact pad lines
                VStack(spacing: 7) {
                    ForEach(0..<3) { _ in
                        Rectangle().fill(.black.opacity(0.18)).frame(height: 1)
                    }
                }
                .padding(.horizontal, 6)
            }
            .overlay {
                Rectangle().fill(.black.opacity(0.18)).frame(width: 1).padding(.vertical, 6)
            }
    }
}

// MARK: - Detail panel

private struct AccountDetailPanel: View {
    let account: Account
    @ObservedObject var viewModel: AccountsViewModel
    let transactionsViewModel: TransactionsViewModel
    let onDelete: () -> Void

    var body: some View {
        let recent = viewModel.recentTransactions(for: account)

        VStack(alignment: .leading, spacing: 20) {
            if let balance = account.statementBalance {
                statementBanner(balance: balance)
            }

            statsRow

            monthlyChart

            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Latest Transactions")
                        .font(.headline)
                    VStack(spacing: 0) {
                        ForEach(Array(recent.enumerated()), id: \.element.id) { index, transaction in
                            NavigationLink {
                                TransactionDetailView(transaction: transaction, viewModel: transactionsViewModel)
                            } label: {
                                TransactionRow(transaction: transaction)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if index < recent.count - 1 {
                                Divider().padding(.leading, 54)
                            }
                        }
                    }
                }
                .cardStyle()
            }

            Button(role: .destructive, action: onDelete) {
                Label("Remove Card", systemImage: "trash")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.expense)
        }
    }

    /// Amount owed on the latest statement, with the due date flagged as it approaches.
    private func statementBanner(balance: Double) -> some View {
        let daysLeft = account.dueDate.map {
            Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: $0).day ?? 0
        }
        let isUrgent = (daysLeft ?? .max) <= 3

        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: isUrgent ? "exclamationmark.circle.fill" : "doc.text.fill")
                .font(.title3)
                .foregroundStyle(isUrgent ? AppTheme.expense : AppTheme.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Statement balance")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(balance, format: .currency(code: account.currency))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                if let minimum = account.minimumPayment {
                    Text("Minimum \(minimum.formatted(.currency(code: account.currency)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let dueDate = account.dueDate, let daysLeft {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Due")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(dueDate, format: .dateTime.day().month(.abbreviated))
                        .font(.subheadline.weight(.bold))
                    Text(daysLeft < 0 ? "Overdue" : daysLeft == 0 ? "Today" : "in \(daysLeft) days")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isUrgent ? AppTheme.expense : .secondary)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var statsRow: some View {
        let spent = viewModel.spentThisMonth(for: account)
        let converted = account.currency == viewModel.displayCurrency
            ? nil
            : viewModel.convert(spent, from: account.currency)

        return HStack(spacing: 12) {
            StatTile(title: "This month", systemImage: "calendar", tint: AppTheme.accent) {
                Text(spent, format: .currency(code: account.currency))
                if let converted {
                    Text(verbatim: "≈ " + converted.formatted(.currency(code: viewModel.displayCurrency)))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            StatTile(title: "All time", systemImage: "sum", tint: AppTheme.expense) {
                Text(viewModel.totalSpent(for: account, currency: account.currency),
                     format: .currency(code: account.currency))
            }
            StatTile(title: "Activity", systemImage: "list.bullet", tint: AppTheme.income) {
                Text(viewModel.transactionCount(for: account).formatted())
            }
        }
    }

    private var monthlyChart: some View {
        let data = viewModel.monthlySpending(for: account)
        let currentMonth = data.last?.month

        return VStack(alignment: .leading, spacing: 12) {
            Text("Last 6 Months")
                .font(.headline)
            Chart(data) { item in
                BarMark(
                    x: .value("Month", item.month, unit: .month),
                    y: .value("Spent", item.amount)
                )
                .cornerRadius(6)
                // Current month highlighted, history muted
                .foregroundStyle(
                    item.month == currentMonth
                        ? AnyShapeStyle(AppTheme.cardGradient(for: account.bankName))
                        : AnyShapeStyle(Color.secondary.opacity(0.25))
                )
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(amount, format: .number.notation(.compactName))
                        }
                    }
                }
            }
            .frame(height: 160)
        }
        .cardStyle()
    }
}

private struct StatTile<Value: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color
    @ViewBuilder let value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                value
            }
            .font(.subheadline.weight(.bold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

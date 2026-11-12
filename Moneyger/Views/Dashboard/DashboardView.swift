import SwiftUI
import SwiftData
import Charts
import PhotosUI

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var authService: GmailAuthService
    @StateObject private var viewModel = DashboardViewModel()
    @StateObject private var pipeline = EmailProcessingPipeline.placeholder
    @EnvironmentObject private var importCenter: DocumentImportCenter
    @State private var isPickingFile = false
    @State private var pickedPhotos: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    BalanceHeroCard(viewModel: viewModel)

                    // "Ready to sync" adds no information, so only show the banner once a sync has started
                    if pipeline.progress != .idle {
                        SyncStatusView(pipeline: pipeline)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if viewModel.filteredTransactions.isEmpty {
                        EmptyDashboardCard()
                    }

                    if !viewModel.transactions.isEmpty {
                        SpendingHistoryCard(viewModel: viewModel)
                    }

                    // Only worth showing once money is held in more than the display currency
                    if viewModel.currencyBreakdown.contains(where: { $0.currency != viewModel.displayCurrency }) {
                        CurrencyBreakdownCard(viewModel: viewModel)
                    }

                    if !viewModel.spendingByCategory.isEmpty {
                        SpendingChartView(data: viewModel.spendingByCategory, currency: viewModel.displayCurrency)
                    }

                    if !viewModel.recentTransactions.isEmpty {
                        RecentTransactionsCard(viewModel: viewModel)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
                .animation(.snappy, value: pipeline.progress)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button("Statement PDF or File", systemImage: "doc.richtext") {
                            isPickingFile = true
                        }
                        PhotosPicker(selection: $pickedPhotos, maxSelectionCount: 10, matching: .screenshots) {
                            Label("Screenshots", systemImage: "camera.viewfinder")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Import statement")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await pipeline.sync() }
                    } label: {
                        if pipeline.isProcessing {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(pipeline.isProcessing)
                }
            }
            .task {
                viewModel.setup(context: context)
                pipeline.setup(context: context, provider: settingsViewModel.activeProvider, authService: authService)
                await viewModel.load()
            }
            .onChange(of: pipeline.progress) { _, _ in
                Task { await viewModel.load() }
            }
            .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.pdf, .image]) { result in
                if case .success(let url) = result {
                    importCenter.open(url)
                }
            }
            .onChange(of: pickedPhotos) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    var images: [Data] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            images.append(data)
                        }
                    }
                    pickedPhotos = []
                    importCenter.importImages(images)
                }
            }
            // Refresh once an import sheet closes so new transactions show up
            .onChange(of: importCenter.request == nil) { _, closed in
                if closed { Task { await viewModel.load() } }
            }
        }
    }
}

// MARK: - Hero balance card

struct BalanceHeroCard: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Menu {
                    Picker("Period", selection: $viewModel.selectedPeriod) {
                        ForEach(Period.allCases) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                } label: {
                    HeroChip(text: viewModel.selectedPeriod.rawValue, systemImage: "calendar")
                }

                Spacer()

                Menu {
                    Picker("Show amounts in", selection: $viewModel.displayCurrency) {
                        ForEach(viewModel.availableCurrencies, id: \.self) { currency in
                            Text(verbatim: [AppTheme.currencyFlag(for: currency), currency]
                                .compactMap { $0 }
                                .joined(separator: " "))
                                .tag(currency)
                        }
                    }
                } label: {
                    HeroChip(
                        text: [AppTheme.currencyFlag(for: viewModel.displayCurrency), viewModel.displayCurrency]
                            .compactMap { $0 }
                            .joined(separator: " "),
                        systemImage: nil
                    )
                }
                .accessibilityLabel("Display currency, \(viewModel.displayCurrency)")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Net Balance")
                    .font(.subheadline.weight(.medium))
                    .opacity(0.8)
                Text(viewModel.netBalance, format: .currency(code: viewModel.displayCurrency))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())

                if viewModel.usesConversion {
                    let count = Set(viewModel.filteredTransactions.map(\.currency)).count
                    Label("Combined from \(count) currencies at live rates", systemImage: "arrow.triangle.swap")
                        .font(.caption.weight(.medium))
                        .opacity(0.75)
                }
            }

            HStack(spacing: 12) {
                HeroStat(
                    title: "Income",
                    amount: viewModel.totalIncome,
                    currency: viewModel.displayCurrency,
                    systemImage: "arrow.down.left"
                )
                HeroStat(
                    title: "Expenses",
                    amount: viewModel.totalExpenses,
                    currency: viewModel.displayCurrency,
                    systemImage: "arrow.up.right"
                )
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                AppTheme.heroGradient
                // Soft decorative circles for depth
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 220)
                    .offset(x: 140, y: -90)
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 160)
                    .offset(x: -130, y: 110)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: AppTheme.accent.opacity(0.35), radius: 20, y: 10)
        .animation(.snappy, value: viewModel.netBalance)
    }
}

struct HeroChip: View {
    let text: String
    let systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(verbatim: text)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .heroGlass(in: Capsule(), interactive: true)
    }
}

struct HeroStat: View {
    let title: String
    let amount: Double
    let currency: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.2), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .opacity(0.8)
                Text(amount, format: .currency(code: currency))
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .heroGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Recent transactions

struct RecentTransactionsCard: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        let transactions = viewModel.recentTransactions
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Transactions")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(Array(transactions.enumerated()), id: \.element.id) { index, transaction in
                    TransactionRow(
                        transaction: transaction,
                        converted: viewModel.convertedAmount(of: transaction).map { ($0, viewModel.displayCurrency) }
                    )
                    .padding(.vertical, 8)
                    if index < transactions.count - 1 {
                        Divider().padding(.leading, 54)
                    }
                }
            }
        }
        .cardStyle()
    }
}

struct EmptyDashboardCard: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.largeTitle)
                .foregroundStyle(AppTheme.heroGradient)
            Text("No transactions in this period")
                .font(.headline)
            Text("Tap the refresh button to scan your Gmail for bank statements and card transactions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .cardStyle()
    }
}

// MARK: - Sync status

struct SyncStatusView: View {
    @ObservedObject var pipeline: EmailProcessingPipeline

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: statusIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .rotatingSymbol(isActive: pipeline.isProcessing)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 28, height: 28)
                    .background(statusColor.opacity(0.15), in: Circle())
                Text(pipeline.progress.statusMessage)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }

            if let fraction = progressFraction {
                ProgressView(value: fraction)
                    .tint(AppTheme.accent)
                    .animation(.easeOut, value: fraction)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var progressFraction: Double? {
        switch pipeline.progress {
        case .classifying(let total, let done), .extracting(let total, let done):
            return total > 0 ? Double(done) / Double(total) : nil
        default:
            return nil
        }
    }

    var statusIcon: String {
        switch pipeline.progress {
        case .idle: return "checkmark"
        case .fetchingEmails, .classifying, .extracting: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark"
        case .failed: return "exclamationmark"
        }
    }

    var statusColor: Color {
        switch pipeline.progress {
        case .failed: return AppTheme.expense
        case .completed: return AppTheme.income
        default: return AppTheme.accent
        }
    }
}

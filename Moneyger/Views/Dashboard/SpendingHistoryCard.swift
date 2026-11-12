import SwiftUI
import Charts

/// Weekly/monthly spending stacked by bank. Tapping a bar pins that period
/// and lists how much went to each bank.
struct SpendingHistoryCard: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var selectedBucket: Date?

    var body: some View {
        // Computed once per render; these walk every transaction
        let history = viewModel.bankSpendingHistory
        let banks = viewModel.historyBanks
        let buckets = viewModel.historyBuckets
        let activeBucket = selectedBucket ?? buckets.last
        let currency = viewModel.displayCurrency
        let component = viewModel.historyGranularity.component

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Spending History")
                    .font(.headline)
                Spacer()
                Picker("Granularity", selection: $viewModel.historyGranularity) {
                    ForEach(HistoryGranularity.allCases) { granularity in
                        Text(granularity.rawValue).tag(granularity)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            if history.isEmpty {
                Text("No spending in this range yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                selectionHeader(bucket: activeBucket, history: history, currency: currency)

                Chart(history) { item in
                    BarMark(
                        x: .value("Period", item.bucket, unit: component),
                        y: .value("Spent", item.amount),
                        width: .ratio(0.6)
                    )
                    .foregroundStyle(by: .value("Bank", item.bank))
                    .cornerRadius(4)
                    // Keep the pinned period vivid and recede the rest
                    .opacity(activeBucket == nil || item.bucket == activeBucket ? 1 : 0.35)
                }
                .chartForegroundStyleScale(domain: banks, range: Array(AppTheme.seriesColors.prefix(banks.count)))
                .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
                .chartXAxis {
                    AxisMarks(values: buckets) { _ in
                        AxisValueLabel(
                            format: viewModel.historyGranularity == .monthly
                                ? .dateTime.month(.abbreviated)
                                : .dateTime.day().month(.abbreviated),
                            centered: true
                        )
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(amount, format: .number.notation(.compactName))
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            // A tap (not a drag) so vertical scrolling over the chart still works
                            .onTapGesture { location in
                                select(at: location, proxy: proxy, geometry: geometry, component: component)
                            }
                    }
                }
                .frame(height: 200)
                .sensoryFeedback(.selection, trigger: selectedBucket)

                if let activeBucket {
                    bankBreakdown(for: activeBucket, banks: banks, currency: currency)
                }
            }
        }
        .cardStyle()
        .onChange(of: viewModel.historyGranularity) { _, _ in
            selectedBucket = nil
        }
    }

    // MARK: - Pieces

    private func selectionHeader(bucket: Date?, history: [BankSpending], currency: String) -> some View {
        let total = history.filter { $0.bucket == bucket }.reduce(0) { $0 + $1.amount }
        let average = history.reduce(0) { $0 + $1.amount } / Double(max(viewModel.historyBuckets.count, 1))

        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(bucket.map(periodLabel) ?? "")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(total, format: .currency(code: currency))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(viewModel.historyGranularity == .monthly ? "Monthly avg" : "Weekly avg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(average, format: .currency(code: currency).precision(.fractionLength(0)))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .animation(.snappy, value: total)
        .accessibilityElement(children: .combine)
    }

    private func bankBreakdown(for bucket: Date, banks: [String], currency: String) -> some View {
        let rows = viewModel.bankBreakdown(for: bucket)
        let total = rows.reduce(0) { $0 + $1.amount }

        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 12) {
                    // Line key in the series color; text stays in text colors
                    Capsule()
                        .fill(color(for: row.bank, in: banks))
                        .frame(width: 4, height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.amount, format: .currency(code: currency))
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                        Text(subtitle(for: row.bank))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(total > 0 ? row.amount / total : 0, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)

                if index < rows.count - 1 {
                    Divider().padding(.leading, 16)
                }
            }

            if rows.isEmpty {
                Text("No spending in this period.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.snappy, value: bucket)
    }

    // MARK: - Helpers

    private func select(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy, component: Calendar.Component) {
        guard let plotFrame = proxy.plotFrame else { return }
        let x = location.x - geometry[plotFrame].origin.x
        guard let date: Date = proxy.value(atX: x),
              let bucket = Calendar.current.dateInterval(of: component, for: date)?.start,
              viewModel.historyBuckets.contains(bucket),
              bucket != selectedBucket else { return }
        selectedBucket = bucket
    }

    private func color(for bank: String, in banks: [String]) -> Color {
        guard let index = banks.firstIndex(of: bank) else { return .secondary }
        return AppTheme.seriesColors[index % AppTheme.seriesColors.count]
    }

    private func subtitle(for bank: String) -> String {
        let cards = viewModel.accountCount(forBank: bank)
        guard cards > 1 else { return bank }
        return "\(bank) · \(cards) cards"
    }

    private func periodLabel(_ bucket: Date) -> String {
        switch viewModel.historyGranularity {
        case .monthly:
            return bucket.formatted(.dateTime.month(.wide).year())
        case .weekly:
            let end = Calendar.current.date(byAdding: .day, value: 6, to: bucket) ?? bucket
            return "\(bucket.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
        }
    }
}

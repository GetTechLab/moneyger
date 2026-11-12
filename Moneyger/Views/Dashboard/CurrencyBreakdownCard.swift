import SwiftUI

/// Shows how the period's money splits across currencies, each with its
/// equivalent in the display currency and the rate used.
struct CurrencyBreakdownCard: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        let breakdown = viewModel.currencyBreakdown

        VStack(alignment: .leading, spacing: 16) {
            header

            CurrencyShareBar(breakdown: breakdown, viewModel: viewModel)

            VStack(spacing: 0) {
                ForEach(Array(breakdown.enumerated()), id: \.element.id) { index, summary in
                    CurrencyRow(summary: summary, displayCurrency: viewModel.displayCurrency)
                        .padding(.vertical, 10)
                    if index < breakdown.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }

            if !viewModel.unconvertedCurrencies.isEmpty {
                Label(
                    "No rate for \(viewModel.unconvertedCurrencies.joined(separator: ", ")), not included in totals",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .cardStyle()
        .animation(.snappy, value: viewModel.displayCurrency)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Currencies")
                    .font(.headline)
                if let rates = viewModel.rates {
                    Text("Rates updated \(rates.updatedAt, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                Task { await viewModel.refreshRates(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .rotatingSymbol(isActive: viewModel.isRefreshingRates)
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isRefreshingRates)
            .accessibilityLabel("Refresh exchange rates")
        }
    }
}

/// Segmented capsule showing each currency's share of total volume in the display currency.
private struct CurrencyShareBar: View {
    let breakdown: [CurrencySummary]
    let viewModel: DashboardViewModel

    /// Income + expenses converted, so a currency with zero net still shows its activity.
    private var volumes: [(currency: String, volume: Double)] {
        breakdown.compactMap { summary in
            guard let volume = viewModel.convert(summary.income + summary.expenses, from: summary.currency),
                  volume > 0 else { return nil }
            return (summary.currency, volume)
        }
    }

    var body: some View {
        let items = volumes
        let total = items.reduce(0) { $0 + $1.volume }

        if total > 0 {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geometry in
                    HStack(spacing: 3) {
                        ForEach(items, id: \.currency) { item in
                            Capsule()
                                .fill(AppTheme.currencyColor(for: item.currency).gradient)
                                .frame(width: max(6, (geometry.size.width - CGFloat(items.count - 1) * 3) * item.volume / total))
                        }
                    }
                }
                .frame(height: 10)

                HStack(spacing: 14) {
                    ForEach(items, id: \.currency) { item in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(AppTheme.currencyColor(for: item.currency))
                                .frame(width: 8, height: 8)
                            Text(verbatim: item.currency)
                                .font(.caption.weight(.semibold))
                            Text(item.volume / total, format: .percent.precision(.fractionLength(0)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

private struct CurrencyRow: View {
    let summary: CurrencySummary
    let displayCurrency: String

    private var isForeign: Bool { summary.currency != displayCurrency }

    var body: some View {
        HStack(spacing: 12) {
            CurrencyBadge(code: summary.currency, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: summary.currency)
                    .font(.subheadline.weight(.semibold))
                Group {
                    if isForeign, let rate = summary.unitRate {
                        Text(verbatim: "1 \(summary.currency) = "
                             + rate.formatted(.currency(code: displayCurrency).precision(.fractionLength(2...4))))
                    } else {
                        Text("^[\(summary.transactionCount) transaction](inflect: true)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(verbatim: (summary.net < 0 ? "−" : "+")
                     + abs(summary.net).formatted(.currency(code: summary.currency)))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(summary.net < 0 ? Color.primary : AppTheme.income)

                if isForeign {
                    if let converted = summary.convertedNet {
                        Text(verbatim: "≈ " + abs(converted).formatted(.currency(code: displayCurrency)))
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    } else {
                        Text("Rate unavailable")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }
}

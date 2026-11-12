import SwiftUI
import Charts

struct SpendingChartView: View {
    let data: [(category: String, amount: Double)]
    let currency: String

    private var total: Double {
        data.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Spending by Category")
                .font(.headline)

            Chart(data, id: \.category) { item in
                SectorMark(
                    angle: .value("Amount", item.amount),
                    innerRadius: .ratio(0.65),
                    angularInset: 2
                )
                .cornerRadius(6)
                .foregroundStyle(TransactionCategory.from(string: item.category).color)
            }
            .chartBackground { proxy in
                // Total spending shown in the middle of the donut
                GeometryReader { geometry in
                    if let plotFrame = proxy.plotFrame {
                        let frame = geometry[plotFrame]
                        VStack(spacing: 2) {
                            Text("Total Spent")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(total, format: .currency(code: currency))
                                .font(.system(.title3, design: .rounded).weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                        .frame(width: frame.width * 0.55)
                        .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            .frame(height: 220)

            VStack(spacing: 14) {
                ForEach(data.prefix(6), id: \.category) { item in
                    CategoryBreakdownRow(
                        category: TransactionCategory.from(string: item.category),
                        amount: item.amount,
                        share: total > 0 ? item.amount / total : 0,
                        currency: currency
                    )
                }
            }
        }
        .cardStyle()
    }
}

struct CategoryBreakdownRow: View {
    let category: TransactionCategory
    let amount: Double
    let share: Double
    let currency: String

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: category, size: 34)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(category.rawValue)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Text(amount, format: .currency(code: currency))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(category.color.opacity(0.15))
                            Capsule()
                                .fill(category.color)
                                .frame(width: geometry.size.width * share)
                        }
                    }
                    .frame(height: 6)

                    Text(share, format: .percent.precision(.fractionLength(0)))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
    }
}

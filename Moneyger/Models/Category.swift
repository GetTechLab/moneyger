import Foundation

enum TransactionCategory: String, CaseIterable, Codable {
    case food = "Food & Dining"
    case transport = "Transport"
    case health = "Health"
    case shopping = "Shopping"
    case entertainment = "Entertainment"
    case bills = "Bills & Utilities"
    case investment = "Investment"
    case income = "Income"
    case transfer = "Transfer"
    case other = "Other"

    var icon: String {
        switch self {
        case .food: return "fork.knife"
        case .transport: return "car.fill"
        case .health: return "heart.fill"
        case .shopping: return "bag.fill"
        case .entertainment: return "tv.fill"
        case .bills: return "bolt.fill"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .income: return "arrow.down.circle.fill"
        case .transfer: return "arrow.left.arrow.right"
        case .other: return "ellipsis.circle.fill"
        }
    }

    static func from(string: String) -> TransactionCategory {
        return allCases.first { $0.rawValue.lowercased() == string.lowercased() }
            ?? allCases.first { $0.rawValue.lowercased().contains(string.lowercased()) }
            ?? .other
    }
}

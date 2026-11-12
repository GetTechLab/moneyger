import Foundation
import SwiftData

enum AccountType: String, Codable, CaseIterable {
    case creditCard = "credit_card"
    case bankAccount = "bank_account"
    case investment = "investment"

    var displayName: String {
        switch self {
        case .creditCard: return "Credit Card"
        case .bankAccount: return "Bank Account"
        case .investment: return "Investment"
        }
    }

    var icon: String {
        switch self {
        case .creditCard: return "creditcard.fill"
        case .bankAccount: return "building.columns.fill"
        case .investment: return "chart.bar.fill"
        }
    }
}

@Model
final class Account {
    var id: UUID
    var bankName: String
    var last4: String?
    var accountType: String
    var currency: String
    var createdAt: Date
    /// Latest credit card statement figures, taken from statement emails.
    /// Optional with nil defaults so existing stores migrate automatically.
    var statementBalance: Double? = nil
    var minimumPayment: Double? = nil
    var dueDate: Date? = nil
    /// Closing date of the statement the figures above came from; older statements never overwrite newer ones.
    var statementDate: Date? = nil

    @Relationship(deleteRule: .cascade, inverse: \Transaction.account)
    var transactions: [Transaction]

    init(bankName: String, last4: String? = nil, accountType: AccountType, currency: String) {
        self.id = UUID()
        self.bankName = bankName
        self.last4 = last4
        self.accountType = accountType.rawValue
        self.currency = currency
        self.createdAt = Date()
        self.transactions = []
    }

    var displayName: String {
        if let last4 = last4 {
            return "\(bankName) •••• \(last4)"
        }
        return bankName
    }

    var type: AccountType {
        AccountType(rawValue: accountType) ?? .bankAccount
    }
}

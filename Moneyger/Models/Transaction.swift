import Foundation
import SwiftData

@Model
final class Transaction {
    var id: UUID
    var gmailMessageId: String
    var date: Date
    var transactionDescription: String
    var amount: Double
    var currency: String
    var category: String
    var isManuallyEdited: Bool
    var createdAt: Date
    /// True when imported from a statement rather than a per-transaction notification;
    /// used to avoid counting the same purchase from both sources.
    var fromStatement: Bool = false

    @Relationship(deleteRule: .nullify)
    var account: Account?

    init(
        gmailMessageId: String,
        date: Date,
        description: String,
        amount: Double,
        currency: String,
        category: String = TransactionCategory.other.rawValue,
        account: Account? = nil
    ) {
        self.id = UUID()
        self.gmailMessageId = gmailMessageId
        self.date = date
        self.transactionDescription = description
        self.amount = amount
        self.currency = currency
        self.category = category
        self.isManuallyEdited = false
        self.createdAt = Date()
        self.account = account
    }

    var isExpense: Bool { amount < 0 }
    var isIncome: Bool { amount > 0 }
    var absoluteAmount: Double { abs(amount) }

    var transactionCategory: TransactionCategory {
        get { TransactionCategory.from(string: category) }
        set { category = newValue.rawValue }
    }
}

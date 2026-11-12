import Foundation

struct EmailContent {
    let messageId: String
    let subject: String
    let sender: String
    let senderDomain: String
    let body: String
    let receivedDate: Date

    /// "Garanti BBVA <bilgi@garantibbva.com.tr>" → "Garanti BBVA"; nil when the sender has no display name.
    var senderDisplayName: String? {
        guard let bracket = sender.firstIndex(of: "<") else { return nil }
        let name = sender[..<bracket]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return name.isEmpty ? nil : name
    }

    var shortPreview: String {
        let stripped = body.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return String(stripped.prefix(500))
    }
}

struct EmailClassification {
    let isFinancial: Bool
    let type: FinancialEmailType
}

enum FinancialEmailType: String, Codable {
    case creditCardStatement = "credit_card_statement"
    case accountStatement = "account_statement"
    case transaction = "transaction"
    case investmentReport = "investment_report"
    case unknown = "unknown"
    case notFinancial = "not_financial"
}

struct ExtractionResult {
    let bankName: String
    let accountLast4: String?
    let currency: String
    let transactions: [ExtractedTransaction]
    let statementPeriod: DateInterval?
    /// Credit card statements only: total amount due, minimum payment and due date.
    let statementBalance: Double?
    let minimumPayment: Double?
    let dueDate: Date?
    let accountType: AccountType
}

struct ExtractedTransaction {
    let date: Date
    let description: String
    let amount: Double
    let currency: String
    let category: TransactionCategory
    /// Set when a statement covers several cards (main, supplementary, virtual) and this row belongs to one of them.
    var cardLast4: String? = nil
}

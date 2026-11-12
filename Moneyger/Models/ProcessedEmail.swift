import Foundation
import SwiftData

@Model
final class ProcessedEmail {
    @Attribute(.unique)
    var gmailMessageId: String
    var processedAt: Date
    var wasFinancial: Bool
    var extractedTransactionCount: Int

    init(gmailMessageId: String, wasFinancial: Bool, extractedTransactionCount: Int = 0) {
        self.gmailMessageId = gmailMessageId
        self.processedAt = Date()
        self.wasFinancial = wasFinancial
        self.extractedTransactionCount = extractedTransactionCount
    }
}

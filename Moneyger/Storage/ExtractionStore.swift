import Foundation
import SwiftData

/// Saves AI extraction results: resolves the account, keeps statement figures current
/// and skips transactions already imported from another source. Shared by the Gmail
/// sync and the PDF/screenshot importer so both apply identical rules.
@MainActor
final class ExtractionStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    struct SaveResult {
        let account: Account
        let savedCount: Int
        let duplicateCount: Int
    }

    /// - Parameters:
    ///   - sourceId: Gmail message id or imported document id; stored on each transaction.
    ///   - forceStatement: imported documents always count as statements for duplicate detection.
    func save(
        _ extraction: ExtractionResult,
        sourceId: String,
        receivedDate: Date,
        forceStatement: Bool = false
    ) throws -> SaveResult {
        let account = try findOrCreateAccount(
            bankName: extraction.bankName,
            last4: extraction.accountLast4,
            type: extraction.accountType,
            currency: extraction.currency
        )
        let isStatement = forceStatement || extraction.statementPeriod != nil || extraction.statementBalance != nil
        try updateStatement(of: account, with: extraction, receivedDate: receivedDate)

        // An itemized statement replaces any earlier single "total" entry for the same debt
        if isStatement, !extraction.transactions.isEmpty {
            try removeSupersededTotals(on: account, extraction: extraction, sourceId: sourceId)
        }

        // Statements covering several cards (main, supplementary, virtual) get one account per card
        var cardAccounts: [String: Account] = account.last4.map { [$0: account] } ?? [:]
        func resolveAccount(for extracted: ExtractedTransaction) throws -> Account {
            guard let last4 = extracted.cardLast4 else { return account }
            if let known = cardAccounts[last4] { return known }
            let cardAccount = try findOrCreateAccount(
                bankName: extraction.bankName,
                last4: last4,
                type: extraction.accountType,
                currency: extraction.currency,
                adoptUnnumbered: false
            )
            cardAccounts[last4] = cardAccount
            return cardAccount
        }

        var saved = 0
        var duplicates = 0
        for extracted in extraction.transactions {
            let cardAccount = try resolveAccount(for: extracted)
            // The same purchase usually arrives twice: as an instant notification and again on the statement
            if try isDuplicate(extracted, account: cardAccount, sourceId: sourceId, isStatement: isStatement) {
                duplicates += 1
                continue
            }
            let transaction = Transaction(
                gmailMessageId: sourceId,
                date: extracted.date,
                description: extracted.description,
                amount: extracted.amount,
                currency: extracted.currency,
                category: extracted.category.rawValue,
                account: cardAccount
            )
            transaction.fromStatement = isStatement
            context.insert(transaction)
            saved += 1
        }
        try context.save()
        return SaveResult(account: account, savedCount: saved, duplicateCount: duplicates)
    }

    /// Deletes entries on this account that stood in for a whole statement: an email summary saved
    /// as one "statement debt" transaction, or summary/payment rows. Manually edited ones are kept.
    private func removeSupersededTotals(on account: Account, extraction: ExtractionResult, sourceId: String) throws {
        let totals = [extraction.statementBalance, account.statementBalance].compactMap { $0 }.map(abs)

        // How many transactions each source produced; a summary email yields exactly one
        let counts = Dictionary(grouping: account.transactions, by: \.gmailMessageId).mapValues(\.count)

        for transaction in account.transactions where transaction.gmailMessageId != sourceId && !transaction.isManuallyEdited {
            let isSummaryRow = StatementLineFilter.isSummaryLine(transaction.transactionDescription)
                || StatementLineFilter.isCardPayment(transaction.transactionDescription, amount: transaction.amount, accountType: account.type)
            let isLoneTotal = counts[transaction.gmailMessageId] == 1
                && totals.contains { abs($0 - transaction.absoluteAmount) < 0.01 }
            if isSummaryRow || isLoneTotal {
                context.delete(transaction)
            }
        }
    }

    /// One-time cleanup of rows imported before the summary filter existed.
    /// Returns how many transactions were removed.
    @discardableResult
    func removeLegacySummaryRows() throws -> Int {
        var removed = 0
        for transaction in try context.fetch(FetchDescriptor<Transaction>()) where !transaction.isManuallyEdited {
            let type = transaction.account?.type ?? .bankAccount
            if StatementLineFilter.isSummaryLine(transaction.transactionDescription)
                || StatementLineFilter.isCardPayment(transaction.transactionDescription, amount: transaction.amount, accountType: type) {
                context.delete(transaction)
                removed += 1
            }
        }
        try context.save()
        return removed
    }

    /// Matches by bank (case/diacritic-insensitive) and type, then by card number so two cards
    /// from the same bank stay separate. An account first seen without a number adopts it later.
    /// - Parameter adoptUnnumbered: lets an account created without a card number take this one.
    ///   Off for supplementary cards, which must not claim the main card's account.
    private func findOrCreateAccount(
        bankName: String,
        last4: String?,
        type: AccountType,
        currency: String,
        adoptUnnumbered: Bool = true
    ) throws -> Account {
        let typeRaw = type.rawValue
        let candidates = try context.fetch(FetchDescriptor<Account>(
            predicate: #Predicate { $0.accountType == typeRaw }
        ))
        .filter { $0.bankName.compare(bankName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }

        if let last4 {
            if let exact = candidates.first(where: { $0.last4 == last4 }) {
                return exact
            }
            if adoptUnnumbered, let unnumbered = candidates.first(where: { $0.last4 == nil }) {
                unnumbered.last4 = last4
                return unnumbered
            }
        } else if let existing = candidates.first(where: { $0.currency == currency }) ?? candidates.first {
            return existing
        }

        let account = Account(bankName: bankName, last4: last4, accountType: type, currency: currency)
        context.insert(account)
        return account
    }

    /// Keeps the newest statement's balance, minimum payment and due date on the account.
    private func updateStatement(of account: Account, with extraction: ExtractionResult, receivedDate: Date) throws {
        guard let balance = extraction.statementBalance else { return }
        let closingDate = extraction.statementPeriod?.end ?? receivedDate
        if let current = account.statementDate, current > closingDate { return }
        account.statementBalance = balance
        account.minimumPayment = extraction.minimumPayment
        account.dueDate = extraction.dueDate
        account.statementDate = closingDate
    }

    /// A transaction is a duplicate when another source already produced one on the same account
    /// with the same amount and currency within two days, and one of the two came from a statement.
    /// Two notifications are never merged, so genuinely repeated purchases (two coffees) are kept.
    private func isDuplicate(
        _ extracted: ExtractedTransaction,
        account: Account,
        sourceId: String,
        isStatement: Bool
    ) throws -> Bool {
        let amount = extracted.amount
        let currency = extracted.currency
        let windowStart = extracted.date.addingTimeInterval(-2 * 86_400)
        let windowEnd = extracted.date.addingTimeInterval(2 * 86_400)

        let matches = try context.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate {
                $0.amount == amount && $0.currency == currency &&
                $0.date >= windowStart && $0.date <= windowEnd &&
                $0.gmailMessageId != sourceId
            }
        ))
        return matches.contains { $0.account?.id == account.id && (isStatement || $0.fromStatement) }
    }
}

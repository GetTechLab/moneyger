import SwiftUI

struct TransactionDetailView: View {
    let transaction: Transaction
    let viewModel: TransactionsViewModel
    @State private var selectedCategory: TransactionCategory
    @Environment(\.dismiss) private var dismiss

    init(transaction: Transaction, viewModel: TransactionsViewModel) {
        self.transaction = transaction
        self.viewModel = viewModel
        _selectedCategory = State(initialValue: transaction.transactionCategory)
    }

    var body: some View {
        List {
            Section("Amount") {
                HStack {
                    Text(transaction.absoluteAmount, format: .currency(code: transaction.currency))
                        .font(.title.bold())
                        .foregroundStyle(transaction.isExpense ? .red : .green)
                    Spacer()
                    Text(transaction.isExpense ? "Expense" : "Income")
                        .font(.caption)
                        .padding(6)
                        .background(transaction.isExpense ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                        .foregroundStyle(transaction.isExpense ? .red : .green)
                        .clipShape(Capsule())
                }
            }

            Section("Details") {
                LabeledContent("Description", value: transaction.transactionDescription)
                LabeledContent("Date", value: transaction.date.formatted(date: .long, time: .omitted))
                LabeledContent("Currency", value: transaction.currency)
                if let bankName = transaction.account?.bankName {
                    LabeledContent("Account", value: transaction.account?.displayName ?? bankName)
                }
            }

            Section("Category") {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(TransactionCategory.allCases, id: \.self) { cat in
                        Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                    }
                }
                .pickerStyle(.inline)
            }
        }
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    try? viewModel.updateCategory(transaction, category: selectedCategory)
                    dismiss()
                }
            }
        }
    }
}

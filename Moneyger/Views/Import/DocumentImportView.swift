import SwiftUI
import SwiftData

/// Sheet that runs an import and reports what was added.
struct DocumentImportView: View {
    let request: ImportRequest

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsViewModel: SettingsViewModel
    @StateObject private var importer = DocumentImporter()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                icon
                    .font(.system(size: 56))
                    .frame(height: 72)
                    .contentTransition(.symbolEffect(.replace))

                VStack(spacing: 8) {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                if case .analyzing(let part, let total) = importer.phase, total > 1 {
                    ProgressView(value: Double(part - 1), total: Double(total))
                        .tint(AppTheme.accent)
                        .padding(.horizontal, 40)
                }
                Spacer()

                if isFinished, let extractedText = importer.extractedText {
                    NavigationLink {
                        ExtractedTextView(text: extractedText)
                    } label: {
                        Label("Show extracted text", systemImage: "text.viewfinder")
                            .font(.subheadline.weight(.medium))
                    }
                }

                if isFinished {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .padding(.horizontal)
                }
            }
            .padding(.bottom)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isFinished {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .interactiveDismissDisabled(!isFinished)
            .animation(.snappy, value: importer.phase)
            .task {
                await importer.run(request, context: context, provider: settingsViewModel.activeProvider)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var isFinished: Bool {
        switch importer.phase {
        case .finished, .failed: return true
        default: return false
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch importer.phase {
        case .reading:
            Image(systemName: "doc.text.viewfinder")
                .foregroundStyle(AppTheme.accent)
                .symbolEffect(.pulse)
        case .analyzing:
            Image(systemName: "sparkles")
                .foregroundStyle(AppTheme.accent)
                .symbolEffect(.pulse)
        case .finished(.imported):
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.income)
        case .finished(.alreadyImported):
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
        case .finished(.notFinancial):
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.orange)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.expense)
        }
    }

    private var title: String {
        switch importer.phase {
        case .reading: return "Reading document…"
        case .analyzing(let part, let total):
            return total > 1 ? "Analyzing part \(part) of \(total)…" : "Analyzing…"
        case .finished(.imported(let bank, let last4, let saved, _, _)):
            let card = last4.map { " •••• \($0)" } ?? ""
            return saved == 1 ? "1 transaction added to \(bank)\(card)" : "\(saved) transactions added to \(bank)\(card)"
        case .finished(.alreadyImported): return "Already imported"
        case .finished(.notFinancial): return "Not a statement"
        case .failed: return "Import failed"
        }
    }

    private var message: String {
        switch importer.phase {
        case .reading: return "Text is read on your device."
        case .analyzing: return "Only the extracted text is sent to \(settingsViewModel.activeProvider.name)."
        case .finished(.imported(_, _, _, let duplicates, let hasStatement)):
            var parts: [String] = []
            if duplicates > 0 { parts.append("\(duplicates) already known, skipped.") }
            if hasStatement { parts.append("Statement balance and due date updated.") }
            return parts.isEmpty ? "You'll see them on the dashboard." : parts.joined(separator: " ")
        case .finished(.alreadyImported): return "This document was imported before."
        case .finished(.notFinancial):
            return "This doesn't look like a bank or card statement, so nothing was added."
        case .failed(let error): return error
        }
    }
}

/// The raw text read on device and sent to the AI, for checking why a statement imported wrongly.
private struct ExtractedTextView: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(verbatim: text)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Extracted Text")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ShareLink(item: text)
        }
    }
}

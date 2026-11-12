import SwiftUI

struct AIProviderSettingsView: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @State private var showGeminiKey = false
    @State private var showClaudeKey = false
    @State private var showOpenAIKey = false

    var body: some View {
        List {
            Section("Active Provider") {
                ForEach(AIProviderType.allCases) { provider in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.displayName)
                                .font(.subheadline.bold())
                            if provider == .gemini {
                                Text("Recommended — fast & cost-effective")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if settingsViewModel.selectedProvider == provider {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        settingsViewModel.selectedProvider = provider
                    }
                }
            }

            Section {
                APIKeyField(
                    label: "Gemini API Key",
                    placeholder: "AIza...",
                    value: $settingsViewModel.geminiKey,
                    isVisible: $showGeminiKey
                )
            } header: {
                Text("Gemini (Google AI Studio)")
            } footer: {
                Text("Get your key at aistudio.google.com")
            }

            Section {
                APIKeyField(
                    label: "Claude API Key",
                    placeholder: "sk-ant-...",
                    value: $settingsViewModel.claudeKey,
                    isVisible: $showClaudeKey
                )
            } header: {
                Text("Claude (Anthropic)")
            } footer: {
                Text("Get your key at console.anthropic.com")
            }

            Section {
                APIKeyField(
                    label: "OpenAI API Key",
                    placeholder: "sk-...",
                    value: $settingsViewModel.openAIKey,
                    isVisible: $showOpenAIKey
                )
            } header: {
                Text("OpenAI")
            } footer: {
                Text("Get your key at platform.openai.com")
            }
        }
        .navigationTitle("AI Provider")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct APIKeyField: View {
    let label: String
    let placeholder: String
    @Binding var value: String
    @Binding var isVisible: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.subheadline)
                if isVisible {
                    TextField(placeholder, text: $value)
                        .font(.caption.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    Text(value.isEmpty ? "Not configured" : String(repeating: "•", count: min(value.count, 20)))
                        .font(.caption.monospaced())
                        .foregroundStyle(value.isEmpty ? .red : .secondary)
                }
            }
            Spacer()
            Button {
                isVisible.toggle()
            } label: {
                Image(systemName: isVisible ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

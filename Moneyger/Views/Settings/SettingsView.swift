import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var authService: GmailAuthService

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    HStack {
                        Image(systemName: "envelope.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Gmail")
                                .font(.subheadline.bold())
                            Text(authService.userEmail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Sign Out", role: .destructive) {
                            authService.signOut()
                        }
                        .font(.caption)
                    }
                }

                Section {
                    NavigationLink {
                        AIProviderSettingsView()
                    } label: {
                        HStack {
                            Image(systemName: "brain.fill")
                                .foregroundStyle(.purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI Provider")
                                    .font(.subheadline)
                                Text(settingsViewModel.selectedProvider.displayName)
                                    .font(.caption)
                                    .foregroundStyle(settingsViewModel.isActiveProviderConfigured ? Color.secondary : Color.red)
                            }
                        }
                    }
                } header: {
                    Text("AI Configuration")
                } footer: {
                    if !settingsViewModel.isActiveProviderConfigured {
                        Text("API key required — tap to configure")
                            .foregroundStyle(.red)
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    LabeledContent("Data Storage", value: "On-device only")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

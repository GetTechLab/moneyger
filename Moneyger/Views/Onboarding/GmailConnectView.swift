import SwiftUI
import GoogleSignIn

struct GmailConnectView: View {
    @EnvironmentObject var authService: GmailAuthService
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @State private var showAPIKeySetup = false
    @State private var isConnecting = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "envelope.badge.shield.half.filled.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                Text("Connect Gmail")
                    .font(.title2.bold())

                Text("Moneyger needs read-only access to your Gmail to find bank statements. No emails are stored on external servers.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 12) {
                PrivacyNote(icon: "lock.fill", text: "Read-only access — Moneyger cannot send or delete emails")
                PrivacyNote(icon: "iphone", text: "All data stays on your device — no backend server")
                PrivacyNote(icon: "key.fill", text: "AI API keys stored securely in Keychain")
            }
            .padding(.horizontal)

            Spacer()

            Button {
                Task { await connectGmail() }
            } label: {
                HStack {
                    if isConnecting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "envelope.fill")
                    }
                    Text(isConnecting ? "Connecting..." : "Connect with Gmail")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)
            }
            .disabled(isConnecting)

            if let error = authService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            Spacer().frame(height: 20)
        }
        .navigationTitle("Connect Gmail")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func connectGmail() async {
        isConnecting = true
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let vc = scene.windows.first?.rootViewController else {
            isConnecting = false
            return
        }
        do {
            try await authService.signIn(presenting: vc)
        } catch {
            authService.errorMessage = error.localizedDescription
        }
        isConnecting = false
    }
}

struct PrivacyNote: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

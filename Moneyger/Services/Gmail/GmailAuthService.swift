import Foundation
import GoogleSignIn
import SwiftUI

@MainActor
final class GmailAuthService: ObservableObject {
    @Published var isSignedIn: Bool = false
    @Published var userEmail: String = ""
    @Published var errorMessage: String?

    private let gmailScope = "https://www.googleapis.com/auth/gmail.readonly"

    init() {
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            isSignedIn = true
            userEmail = "demo@example.com"
            return
        }
        restoreSession()
    }

    private func restoreSession() {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: GoogleClientConfig.clientID)
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            guard let self else { return }
            if let user, error == nil {
                Task { @MainActor in
                    self.isSignedIn = true
                    self.userEmail = user.profile?.email ?? ""
                }
            }
        }
    }

    func signIn(presenting viewController: UIViewController) async throws {
        let config = GIDConfiguration(clientID: GoogleClientConfig.clientID)
        GIDSignIn.sharedInstance.configuration = config

        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: viewController,
            hint: nil,
            additionalScopes: [gmailScope]
        )

        isSignedIn = true
        userEmail = result.user.profile?.email ?? ""
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        isSignedIn = false
        userEmail = ""
    }

    func currentAccessToken() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw GmailError.notSignedIn
        }
        try await user.refreshTokensIfNeeded()
        guard let token = user.accessToken.tokenString as String? else {
            throw GmailError.tokenExpired
        }
        return token
    }
}

enum GmailError: LocalizedError {
    case notSignedIn
    case tokenExpired
    case fetchFailed(String)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Not signed in to Gmail"
        case .tokenExpired: return "Gmail session expired, please sign in again"
        case .fetchFailed(let msg): return "Gmail fetch failed: \(msg)"
        case .decodingFailed: return "Failed to decode Gmail response"
        }
    }
}

enum GoogleClientConfig {
    static var clientID: String {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientID = plist["CLIENT_ID"] as? String else {
            return ""
        }
        return clientID
    }
}

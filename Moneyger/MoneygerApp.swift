import SwiftUI
import SwiftData
import GoogleSignIn

@main
struct MoneygerApp: App {
    @StateObject private var authService = GmailAuthService()
    @StateObject private var settingsViewModel = SettingsViewModel()
    @StateObject private var importCenter = DocumentImportCenter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
                .environmentObject(settingsViewModel)
                .environmentObject(importCenter)
                .modelContainer(SwiftDataStack.shared.container)
                .onOpenURL { url in
                    // PDFs/images arrive as file URLs via "Open in Moneyger"; everything else is the Google sign-in callback
                    if url.isFileURL {
                        importCenter.open(url)
                    } else {
                        GIDSignIn.sharedInstance.handle(url)
                    }
                }
        }
    }
}

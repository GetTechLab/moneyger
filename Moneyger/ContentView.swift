import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authService: GmailAuthService

    var body: some View {
        Group {
            if authService.isSignedIn {
                MainTabView()
            } else {
                WelcomeView()
            }
        }
        .animation(.easeInOut, value: authService.isSignedIn)
    }
}

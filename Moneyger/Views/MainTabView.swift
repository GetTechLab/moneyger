import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var authService: GmailAuthService
    @EnvironmentObject var importCenter: DocumentImportCenter
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.pie.fill") }

            TransactionsListView()
                .tabItem { Label("Transactions", systemImage: "list.bullet") }

            AccountsView()
                .tabItem { Label("Accounts", systemImage: "creditcard.fill") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(AppTheme.accent)
        // Presented at the tab level so shared files are handled whichever tab is open
        .sheet(item: $importCenter.request) { request in
            DocumentImportView(request: request)
        }
        // Files shared from other apps via the Share Extension wait in the App Group inbox
        .task {
            removeLegacySummaryRowsOnce()
            importCenter.checkSharedInbox()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { importCenter.checkSharedInbox() }
        }
    }

    /// Statement totals, carried-over balances and card payments imported by older versions
    /// were counted as spending; remove them once.
    private func removeLegacySummaryRowsOnce() {
        let key = "cleanup.statementSummaryRows.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        do {
            let removed = try ExtractionStore(context: context).removeLegacySummaryRows()
            print("Removed \(removed) legacy statement summary rows")
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            print("Legacy cleanup error: \(error)")
        }
    }
}

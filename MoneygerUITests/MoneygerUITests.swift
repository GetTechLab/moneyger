import XCTest

final class MoneygerUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        sleep(2)
    }

    func testAllScreens() throws {
        // 1. Dashboard tab (default)
        snapshot("01_Dashboard")

        // 2. Transactions tab
        app.tabBars.buttons["Transactions"].tap()
        sleep(1)
        snapshot("02_Transactions")

        // 3. Accounts tab
        app.tabBars.buttons["Accounts"].tap()
        sleep(1)
        snapshot("03_Accounts")

        // 4. Settings tab
        app.tabBars.buttons["Settings"].tap()
        sleep(1)
        snapshot("04_Settings")

        // 5. AI Provider settings
        app.staticTexts["AI Provider"].tap()
        sleep(1)
        snapshot("05_AIProvider")
    }

    private func snapshot(_ name: String) {
        let s = app.screenshot()
        let a = XCTAttachment(screenshot: s)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}

import XCTest

/// End-to-end UI flows (tester role). XCTest is used here because XCUITest has no Swift Testing
/// equivalent. Run: xcodebuild test -scheme ScanLab -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
final class ScanLabUITests: XCTestCase {
    /// Finds a control by label whatever its element type (toggles styled as buttons report as switches).
    @MainActor
    private func control(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any)[label].firstMatch
    }

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(onboarded: Bool = true, seedDemo: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += onboarded ? ["-hasCompletedOnboarding", "YES"] : ["-ScanLabResetOnboarding", "YES"]
        app.launchArguments += [
                                "-ScanLabSeedDemo", seedDemo ? "YES" : "NO",
                                "-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR"]
        app.launch()
        return app
    }

    @MainActor
    func testOnboardingLeadsToLibrary() {
        let app = launch(onboarded: false)
        XCTAssertTrue(app.buttons["İleri"].waitForExistence(timeout: 5), "onboarding not shown")
        for _ in 0..<4 where !app.buttons["Başla"].exists {
            app.buttons["İleri"].tap()
            _ = app.buttons["Başla"].waitForExistence(timeout: 1.5)
        }
        XCTAssertTrue(app.buttons["Başla"].waitForExistence(timeout: 5))
        app.buttons["Başla"].tap()
        XCTAssertTrue(app.buttons["Yeni tarama"].waitForExistence(timeout: 5), "library not shown after onboarding")
    }

    @MainActor
    func testModePickerListsEveryMode() {
        let app = launch()
        app.buttons["Yeni tarama"].tap()
        for title in ["Oda / Ortam", "Yüz / Yakın nesne", "Nesne", "Oda planı", "Nokta bulutu", "Foto / Video"] {
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5), "missing mode \(title)")
        }
        app.buttons["Vazgeç"].tap()
    }

    @MainActor
    func testSettingsShowsDeviceCapabilities() {
        let app = launch()
        app.buttons["Ayarlar"].tap()
        XCTAssertTrue(app.staticTexts["LiDAR sahne yeniden yapılandırma"].waitForExistence(timeout: 5))
        app.buttons["Bitti"].tap()
    }

    @MainActor
    func testProjectShowsModelAndViewerTools() {
        let app = launch(seedDemo: true)
        let demo = app.staticTexts["Demo parça"].firstMatch
        XCTAssertTrue(demo.waitForExistence(timeout: 10))
        demo.tap()
        XCTAssertTrue(app.buttons["Tam ekran"].waitForExistence(timeout: 10), "embedded 3D viewer missing on project screen")
        app.buttons["Tam ekran"].tap()
        XCTAssertTrue(app.buttons["Kapat"].waitForExistence(timeout: 10), "full-screen viewer did not open from the embedded preview")
        XCTAssertTrue(app.staticTexts["12 üçgen · 0,120 × 0,060 × 0,080 m"].waitForExistence(timeout: 10)
                      || app.staticTexts.containing(NSPredicate(format: "label CONTAINS '12 üçgen'")).firstMatch.waitForExistence(timeout: 5),
                      "viewer stats missing")
        for mode in ["Gölgeli", "Sınıflar", "Tel kafes", "Noktalar"] {
            XCTAssertTrue(app.buttons[mode].exists, "display mode \(mode) missing")
        }
        app.buttons["Tel kafes"].tap()
        control(app, "Sınır kutusu").tap()
        control(app, "Kırp").tap()
        XCTAssertTrue(app.buttons["Kırpılmışı kaydet"].waitForExistence(timeout: 5))
        app.buttons["Kırpılmışı kaydet"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Kaydedildi'")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["Kapat"].tap()
    }

    @MainActor
    func testExportMeshAsGLBVerifies() {
        let app = launch(seedDemo: true)
        XCTAssertTrue(app.staticTexts["Demo parça"].firstMatch.waitForExistence(timeout: 10))
        app.staticTexts["Demo parça"].firstMatch.tap()
        let export = app.buttons["scan.export"]
        XCTAssertTrue(export.waitForExistence(timeout: 10))
        export.tap()
        // A Form picker's button label is "<title>, <value>".
        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Format'")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.tap()
        app.buttons["GLB (glTF 2.0)"].firstMatch.tap()
        app.buttons["export.run"].tap()
        XCTAssertTrue(app.staticTexts["Doğrulandı (yeniden okundu)"].waitForExistence(timeout: 15))
    }

    @MainActor
    func testPointCloudOutputOpensInViewer() {
        let app = launch(seedDemo: true)
        XCTAssertTrue(app.staticTexts["Demo parça"].firstMatch.waitForExistence(timeout: 10))
        app.staticTexts["Demo parça"].firstMatch.tap()
        let view = app.buttons["Görüntüle"].firstMatch
        XCTAssertTrue(view.waitForExistence(timeout: 10))
        view.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'nokta'")).firstMatch.waitForExistence(timeout: 10))
    }
}

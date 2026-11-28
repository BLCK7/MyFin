import XCTest

/// Walks every screen, sheet and main button of MyFin on the simulator and saves a screenshot of each step to
/// `$SIMULATOR_HOST_HOME/uishots` (collected by CI). Failures are recorded but the walk continues, so one run shows
/// everything that is wrong.
final class MyFinUITests: XCTestCase {
    private var app: XCUIApplication!
    private var shotIndex = 0
    private var prefix = "x"

    private static let shotsDir: URL = {
        let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: home).appendingPathComponent("uishots")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
    }

    // MARK: Helpers

    private func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        shotIndex += 1
        let file = Self.shotsDir.appendingPathComponent(String(format: "%@-%02d-%@.png", prefix, shotIndex, name))
        try? s.pngRepresentation.write(to: file)
        let a = XCTAttachment(screenshot: s)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    @discardableResult
    private func tap(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 6,
                     file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard element.waitForExistence(timeout: timeout) else {
            XCTFail("Topilmadi: \(what)", file: file, line: line)
            shot("MISSING-\(what.replacingOccurrences(of: " ", with: "_"))")
            return false
        }
        if !element.isHittable {
            app.swipeUp()
        }
        element.tap()
        return true
    }

    private func button(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", label)).firstMatch
    }

    private func anyText(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", label)).firstMatch
    }

    private func tab(_ name: String) {
        tap(app.tabBars.buttons[name].exists ? app.tabBars.buttons[name] : button(name), "tab \(name)")
        sleep(1)
    }

    private func back() {
        let b = app.navigationBars.buttons.element(boundBy: 0)
        if b.waitForExistence(timeout: 3) { b.tap() } else { app.swipeRight() }
        sleep(1)
    }

    private func closeSheet(_ label: String = "Bekor") {
        let b = button(label)
        if b.waitForExistence(timeout: 3) {
            b.tap()
        } else {
            app.swipeDown(velocity: .fast)
        }
        sleep(1)
    }

    private func typePIN(_ pin: String) {
        for d in pin {
            let key = app.buttons[String(d)].firstMatch
            if key.waitForExistence(timeout: 3) { key.tap() } else { XCTFail("PIN tugmasi yo'q: \(d)") }
        }
    }

    private func launchDemo() {
        app.launchArguments = ["-uitest", "-uitest-demo"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15), "Asosiy ekran ochilmadi")
        sleep(2)
    }

    // MARK: Flows

    func test01Onboarding() {
        prefix = "a-onboarding"
        app.launchArguments = ["-uitest"]
        app.launch()
        sleep(2)
        shot("welcome")
        tap(button("Boshlash"), "Boshlash")
        sleep(1)
        let name = app.textFields.firstMatch
        if name.waitForExistence(timeout: 4) {
            name.tap()
            name.typeText("Saminov")
        }
        shot("profile")
        tap(button("Davom etish"), "Davom etish 1")
        sleep(1)
        let cash = app.textFields.firstMatch
        if cash.waitForExistence(timeout: 4) {
            cash.tap()
            cash.typeText("250000")
        }
        shot("cash")
        tap(button("Davom etish"), "Davom etish 2")
        sleep(1)
        shot("cards")
        if button("Karta qo'shish").waitForExistence(timeout: 3) {
            button("Karta qo'shish").tap()
            sleep(1)
            shot("card-form")
            let fields = app.textFields
            if fields.count > 0 { fields.element(boundBy: 0).tap(); fields.element(boundBy: 0).typeText("TBC Visa") }
            shot("card-form-filled")
            if button("Qo'shish").exists { button("Qo'shish").tap() } else { closeSheet() }
            sleep(1)
            shot("cards-added")
        }
        tap(button("Davom etish"), "Davom etish 3")
        sleep(1)
        shot("debts")
        tap(button("Davom etish"), "Davom etish 4")
        sleep(1)
        shot("security")
        tap(button("PIN-kod o'rnatish"), "PIN o'rnatish")
        sleep(1)
        shot("pin-new")
        typePIN("135790")
        sleep(1)
        shot("pin-confirm")
        typePIN("135790")
        sleep(2)
        shot("pin-done")
        let notif = app.switches.matching(NSPredicate(format: "label CONTAINS[c] %@", "Eslatmalar")).firstMatch
        if notif.exists, (notif.value as? String) == "1" { notif.tap() }
        tap(button("Tayyor"), "Tayyor")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10), "Onboarding'dan keyin asosiy ekran chiqmadi")
        sleep(2)
        shot("home-after-onboarding")
    }

    func test02MainScreens() {
        prefix = "b-main"
        launchDemo()
        shot("dashboard")
        app.swipeUp()
        sleep(1)
        shot("dashboard-scrolled")
        app.swipeUp()
        sleep(1)
        shot("dashboard-bottom")

        tab("Operatsiyalar")
        shot("transactions")
        tap(anyText("Korzinka"), "Korzinka operatsiyasi")
        sleep(1)
        shot("tx-editor")
        closeSheet()

        tab("Hisoblar")
        shot("accounts")
        tap(anyText("•••• 7758"), "Visa kartasi")
        sleep(1)
        shot("account-detail")
        tap(button("Tahrirlash"), "Hisobni tahrirlash")
        sleep(1)
        shot("account-editor")
        closeSheet()
        tap(button("To'g'rilash"), "Balansni to'g'rilash")
        sleep(1)
        shot("account-adjust-alert")
        closeSheet("Bekor")
        back()

        tab("Qarzlar")
        shot("debts")
        tap(anyText("Ali"), "Ali qarzi")
        sleep(1)
        shot("debt-detail")
        back()
    }

    func test03AddOperationAndCapture() {
        prefix = "c-add"
        launchDemo()
        tap(button("Operatsiya qo'shish"), "Operatsiya qo'shish")
        sleep(1)
        shot("new-tx")
        let amount = app.textFields.firstMatch
        if amount.waitForExistence(timeout: 4) {
            amount.tap()
            amount.typeText("12500")
        }
        tap(anyText("Kafe va restoran"), "Kafe kategoriyasi")
        shot("new-tx-filled")
        tap(button("Saqlash"), "Saqlash")
        sleep(2)
        tab("Operatsiyalar")
        XCTAssertTrue(anyText("Kafe va restoran").waitForExistence(timeout: 5), "Yangi operatsiya ro'yxatda yo'q")
        shot("tx-list-after-add")

        tap(app.buttons["Chekni skanerlash"], "QR tugmasi")
        sleep(2)
        shot("qr-sheet")
        closeSheet("Yopish")

        tap(app.buttons["Skrinshotdan qo'shish"], "Skrinshot tugmasi")
        sleep(3)
        shot("photo-picker")
        let cancel = app.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 3) { cancel.tap() }
        sleep(1)
        shot("photo-sheet-idle")
        closeSheet("Yopish")
    }

    func test04MoreSections() {
        prefix = "d-more"
        launchDemo()
        tab("Ko'proq")
        shot("more")
        for title in ["Tahlil", "Limitlar", "Maqsadlar", "Doimiy to'lovlar", "Kategoriyalar", "Valyuta kurslari"] {
            if tap(anyText(title), title) {
                sleep(1)
                shot(title.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "'", with: ""))
                back()
            }
        }
        tap(anyText("Kartalarni avtomatik kuzatish"), "Avtomatizatsiya")
        sleep(1)
        shot("automation")
        app.swipeUp()
        shot("automation-2")
        let run = button("Sinash")
        for _ in 0..<6 where !run.isHittable { app.swipeUp() }
        tap(run, "Sinash")
        sleep(1)
        app.swipeUp()
        shot("sandbox-result")
        app.swipeUp()
        shot("sandbox-result-2")
        back()

        tap(anyText("Sozlamalar"), "Sozlamalar")
        sleep(1)
        shot("settings")
        app.swipeUp()
        shot("settings-2")
        back()
    }

    func test05VaultAndLock() {
        prefix = "e-security"
        launchDemo()
        tab("Ko'proq")
        tap(anyText("Shaxsiy seyf"), "Seyf")
        sleep(1)
        shot("vault-gate")
        tap(button("PIN-kod bilan ochish"), "PIN bilan ochish")
        sleep(1)
        typePIN("135790")
        sleep(2)
        shot("vault-list")
        tap(anyText("Pasport (demo)"), "Pasport yozuvi")
        sleep(2)
        shot("vault-detail")
        back()
        back()

        tap(anyText("Sozlamalar"), "Sozlamalar")
        sleep(1)
        tap(button("Hozir qulflash"), "Hozir qulflash")
        sleep(2)
        shot("lock-screen")
        typePIN("000000")
        sleep(1)
        shot("lock-wrong-pin")
        typePIN("135790")
        sleep(2)
        shot("unlocked")
        XCTAssertTrue(app.tabBars.firstMatch.isHittable, "PIN kiritilgandan keyin ilova ochilmadi")
    }

    func test06ReviewInboxAndDelete() {
        prefix = "f-review"
        launchDemo()
        XCTAssertTrue(anyText("Izoh kutmoqda").waitForExistence(timeout: 5), "Izoh kutayotganlar kartasi yo'q")
        shot("inbox")
        tap(app.buttons["reviewClearAll"], "Hammasi ko'rildi")
        sleep(1)
        XCTAssertFalse(anyText("Izoh kutmoqda").exists, "Izoh kartasi yopilmadi")
        shot("inbox-cleared")

        tab("Operatsiyalar")
        tap(anyText("Korzinka"), "Korzinka")
        sleep(1)
        app.swipeUp()
        tap(button("Operatsiyani o'chirish"), "O'chirish")
        sleep(1)
        shot("delete-confirm")
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@", "O'chirish")).firstMatch
        tap(confirm, "O'chirishni tasdiqlash")
        sleep(2)
        XCTAssertFalse(anyText("Korzinka").exists, "Operatsiya o'chmadi")
        shot("after-delete")

        tab("Hisoblar")
        tap(anyText("•••• 7675"), "Uzum kartasi")
        sleep(1)
        tap(button("Tahrirlash"), "Tahrirlash")
        sleep(1)
        app.swipeUp()
        app.swipeUp()
        tap(button("Hisobni o'chirish"), "Hisobni o'chirish")
        sleep(1)
        let confirmAcc = app.buttons.matching(NSPredicate(format: "label == %@", "O'chirish")).firstMatch
        tap(confirmAcc, "Hisob o'chirishni tasdiqlash")
        sleep(3)
        shot("after-account-delete")
        XCTAssertFalse(anyText("•••• 7675").exists, "Hisob o'chmadi")
        XCTAssertTrue(app.tabBars.firstMatch.exists, "Hisob o'chirilgandan keyin ilova yopildi")
    }
}

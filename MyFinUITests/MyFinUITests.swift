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

    /// First element of the query that can actually be tapped (other tabs keep their views alive but hidden).
    private func hittable(_ query: XCUIElementQuery, timeout: TimeInterval) -> XCUIElement? {
        let end = Date().addingTimeInterval(timeout)
        var scrolls = 0
        repeat {
            let n = min(query.count, 25)
            // The tab bar and the "Operatsiya qo'shish" bar float over the bottom of every screen; an element
            // under them is "hittable" for XCTest but a tap lands on the bar.
            let screenHeight = app.windows.firstMatch.frame.height
            let safeBottom = screenHeight > 0 ? screenHeight - 165 : 640
            for i in 0..<n {
                let e = query.element(boundBy: i)
                if e.exists && e.isHittable && e.frame.midY < safeBottom && e.frame.midY > 90 { return e }
            }
            if n > 0 && scrolls < 4 {
                app.swipeUp()
                scrolls += 1
            } else {
                usleep(400_000)
            }
        } while Date() < end
        return nil
    }

    @discardableResult
    private func tap(_ query: XCUIElementQuery, _ what: String, timeout: TimeInterval = 6,
                     file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard let e = hittable(query, timeout: timeout) else {
            XCTFail("Topilmadi: \(what)", file: file, line: line)
            shot("MISSING-\(what.replacingOccurrences(of: " ", with: "_"))")
            return false
        }
        e.tap()
        return true
    }

    @discardableResult
    private func tap(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 6,
                     file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard element.waitForExistence(timeout: timeout), element.isHittable else {
            XCTFail("Topilmadi: \(what)", file: file, line: line)
            shot("MISSING-\(what.replacingOccurrences(of: " ", with: "_"))")
            return false
        }
        element.tap()
        return true
    }

    private func buttons(_ label: String) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", label))
    }

    private func button(_ label: String) -> XCUIElement { buttons(label).firstMatch }

    private func exactButtons(_ label: String) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label == %@", label))
    }

    private func texts(_ label: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", label))
    }

    private func visible(_ label: String) -> Bool {
        let q = texts(label)
        for i in 0..<min(q.count, 25) where q.element(boundBy: i).isHittable { return true }
        return false
    }

    private func tab(_ name: String) {
        // A scrolled screen collapses the tab bar to the current tab's icon; tapping it brings all tabs back.
        for _ in 0..<4 {
            let b = app.tabBars.buttons[name]
            if b.exists && b.isHittable { b.tap(); sleep(1); return }
            let all = app.tabBars.buttons
            var tapped = false
            for i in 0..<min(all.count, 6) where all.element(boundBy: i).isHittable {
                all.element(boundBy: i).tap()
                tapped = true
                break
            }
            if !tapped { app.swipeDown() }
            sleep(1)
        }
        tap(app.tabBars.buttons[name], "tab \(name)")
        sleep(1)
    }

    private func back() {
        let b = app.navigationBars.buttons.element(boundBy: 0)
        if b.waitForExistence(timeout: 3) { b.tap() } else { app.swipeRight() }
        sleep(1)
    }

    private func closeSheet(_ label: String = "Bekor") {
        let q = exactButtons(label)
        var done = false
        for i in 0..<min(q.count, 10) where q.element(boundBy: i).isHittable {
            q.element(boundBy: i).tap()
            done = true
            break
        }
        if !done { app.swipeDown(velocity: .fast) }
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
        if button("Karta qo'shish").waitForExistence(timeout: 3) && button("Karta qo'shish").isHittable {
            button("Karta qo'shish").tap()
            sleep(1)
            shot("card-form")
            let fields = app.textFields
            if fields.count > 2 {
                fields.element(boundBy: 1).tap(); fields.element(boundBy: 1).typeText("TBC")
                fields.element(boundBy: 2).tap(); fields.element(boundBy: 2).typeText("7758")
            }
            shot("card-form-filled")
            if exactButtons("Qo'shish").firstMatch.exists { exactButtons("Qo'shish").firstMatch.tap() } else { closeSheet() }
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
        tap(texts("Korzinka"), "Korzinka operatsiyasi")
        sleep(1)
        shot("tx-editor")
        closeSheet()

        tab("Hisoblar")
        shot("accounts")
        tap(texts("•••• 7758"), "Visa kartasi")
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
        tap(buttons("Menga qarzdor"), "Menga qarzdor segmenti")
        sleep(1)
        shot("debts-owed-to-me")
        tap(texts("Ali"), "Ali qarzi")
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
        tap(texts("Kafe va restoran"), "Kafe kategoriyasi")
        shot("new-tx-filled")
        tap(button("Saqlash"), "Saqlash")
        sleep(2)
        tab("Operatsiyalar")
        XCTAssertNotNil(hittable(texts("Kafe va restoran"), timeout: 5), "Yangi operatsiya ro'yxatda yo'q")
        shot("tx-list-after-add")

        tap(app.buttons["Chekni skanerlash"], "QR tugmasi")
        sleep(2)
        shot("qr-sheet")
        closeSheet("Yopish")

        tap(app.buttons["Skrinshotdan qo'shish"], "Skrinshot tugmasi")
        sleep(3)
        shot("photo-picker")
        let cancel = app.buttons["Cancel"].exists ? app.buttons["Cancel"] : app.buttons["Close"]
        if cancel.waitForExistence(timeout: 3) { cancel.tap() } else { app.swipeDown(velocity: .fast) }
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
            if tap(texts(title), title) {
                sleep(1)
                shot(title.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "'", with: ""))
                back()
            }
        }
        tap(texts("Kartalarni avtomatik kuzatish"), "Avtomatizatsiya")
        sleep(1)
        shot("automation")
        app.swipeUp()
        shot("automation-2")
        tap(buttons("Sinash"), "Sinash", timeout: 10)
        sleep(1)
        app.swipeUp()
        shot("sandbox-result")
        app.swipeUp()
        shot("sandbox-result-2")
        back()

        tap(texts("Sozlamalar"), "Sozlamalar")
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
        tap(texts("Shaxsiy seyf"), "Seyf")
        sleep(1)
        shot("vault-gate")
        tap(button("PIN-kod bilan ochish"), "PIN bilan ochish")
        sleep(1)
        typePIN("135790")
        sleep(2)
        shot("vault-list")
        tap(texts("Pasport (demo)"), "Pasport yozuvi")
        sleep(2)
        shot("vault-detail")
        back()
        back()

        tap(texts("Sozlamalar"), "Sozlamalar")
        sleep(1)
        tap(buttons("Hozir qulflash"), "Hozir qulflash")
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
        XCTAssertTrue(texts("Izoh kutmoqda").firstMatch.waitForExistence(timeout: 5), "Izoh kutayotganlar kartasi yo'q")
        shot("inbox")
        tap(app.buttons["reviewClearAll"], "Hammasi ko'rildi")
        sleep(1)
        XCTAssertFalse(visible("Izoh kutmoqda"), "Izoh kartasi yopilmadi")
        shot("inbox-cleared")

        tab("Operatsiyalar")
        tap(texts("Korzinka"), "Korzinka")
        sleep(1)
        tap(buttons("Operatsiyani o'chirish"), "O'chirish", timeout: 8)
        sleep(1)
        shot("delete-confirm")
        tap(exactButtons("O'chirish"), "O'chirishni tasdiqlash")
        sleep(2)
        XCTAssertFalse(visible("Korzinka"), "Operatsiya o'chmadi")
        shot("after-delete")

        tab("Hisoblar")
        tap(texts("•••• 7675"), "Uzum kartasi")
        sleep(1)
        tap(buttons("Tahrirlash"), "Tahrirlash")
        sleep(1)
        tap(buttons("Hisobni o'chirish"), "Hisobni o'chirish", timeout: 8)
        sleep(1)
        tap(exactButtons("O'chirish"), "Hisob o'chirishni tasdiqlash")
        sleep(3)
        shot("after-account-delete")
        XCTAssertFalse(visible("•••• 7675"), "Hisob o'chmadi")
        XCTAssertTrue(app.tabBars.firstMatch.exists, "Hisob o'chirilgandan keyin ilova yopildi")
    }
}

import Foundation
import UserNotifications
import LocalAuthentication

enum Notifier {
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func cancel(_ ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    static func scheduleDebt(id: UUID, person: String, amountText: String, direction: DebtDirection, due: Date?, enabled: Bool) {
        let ids = ["debt-\(id.uuidString)-before", "debt-\(id.uuidString)-day"]
        cancel(ids)
        guard enabled, let due else { return }
        let cal = Calendar.current
        let title = direction == .iOwe ? "Qarz to'lash muddati" : "Qarz qaytarish muddati"
        let bodyDay = direction == .iOwe
            ? "Bugun \(person)ga \(amountText) qaytarishingiz kerak."
            : "Bugun \(person) sizga \(amountText) qaytarishi kerak."
        let bodyBefore = direction == .iOwe
            ? "Ertaga \(person)ga \(amountText) qaytarish muddati."
            : "Ertaga \(person) sizga \(amountText) qaytarishi kerak."
        var dayComps = cal.dateComponents([.year, .month, .day], from: due)
        dayComps.hour = 10
        add(id: ids[1], title: title, body: bodyDay, comps: dayComps, repeats: false)
        if let before = cal.date(byAdding: .day, value: -1, to: due) {
            var bc = cal.dateComponents([.year, .month, .day], from: before)
            bc.hour = 19
            add(id: ids[0], title: title, body: bodyBefore, comps: bc, repeats: false)
        }
    }

    static func scheduleRecurring(id: UUID, name: String, amountText: String, day: Int, enabled: Bool) {
        let rid = "recurring-\(id.uuidString)"
        cancel([rid])
        guard enabled else { return }
        var comps = DateComponents()
        comps.day = max(1, min(28, day))
        comps.hour = 10
        add(id: rid, title: "Doimiy to'lov: \(name)", body: "Bugun \(amountText) to'lash kuni.", comps: comps, repeats: true)
    }

    static func notifyNow(title: String, body: String, id: String = UUID().uuidString) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private static func add(id: String, title: String, body: String, comps: DateComponents, repeats: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: repeats)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}

enum Biometrics {
    static var available: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    static var name: String {
        let ctx = LAContext()
        var error: NSError?
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Parol"
        }
    }

    static func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }
        do {
            return try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}

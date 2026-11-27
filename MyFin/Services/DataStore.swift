import Foundation
import SwiftData

@MainActor
enum DataStore {
    static let schema = Schema([
        Account.self, FinTransaction.self, FinCategory.self, Debt.self,
        DebtPayment.self, Budget.self, Goal.self, RecurringPayment.self
    ])

    static let container: ModelContainer = {
        let config = ModelConfiguration("MyFin", schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("MyFin ma'lumotlar bazasini ochib bo'lmadi: \(error)")
        }
    }()

    static var context: ModelContext { container.mainContext }
}

@MainActor
enum SeedData {
    struct CategorySeed {
        let name: String
        let icon: String
        let color: String
        let kind: TxKind
        let keywords: String
    }

    static let debtPaymentCategory = "Qarz to'lovi"
    static let debtReturnCategory = "Qarz qaytdi"
    static let goalCategory = "Jamg'arma"

    static let categories: [CategorySeed] = [
        CategorySeed(name: "Oziq-ovqat", icon: "cart.fill", color: "#22C55E", kind: .expense,
                     keywords: "korzinka,makro,havas,baraka,magnum,market,supermarket,produkt,oziq,bozor,carrefour,mini market,non"),
        CategorySeed(name: "Kafe va restoran", icon: "fork.knife", color: "#F97316", kind: .expense,
                     keywords: "cafe,kafe,restoran,restaurant,evos,kfc,oqtepa,lavash,burger,pizza,coffee,kofe,choyxona,wolt,yandex eda,express24"),
        CategorySeed(name: "Transport", icon: "car.fill", color: "#3B82F6", kind: .expense,
                     keywords: "yandex go,taxi,taksi,metro,avtobus,mytaxi,uklon,transport,parking,parkovka"),
        CategorySeed(name: "Yoqilg'i", icon: "fuelpump.fill", color: "#0EA5E9", kind: .expense,
                     keywords: "azs,benzin,metan,propan,neft,fuel,zapravka,ai-92,ai-95"),
        CategorySeed(name: "Kommunal", icon: "house.fill", color: "#EAB308", kind: .expense,
                     keywords: "kommunal,elektr,hududgaz,suv,issiqlik,tozamakon,energosbyt,svet,gaz"),
        CategorySeed(name: "Aloqa va internet", icon: "wifi", color: "#06B6D4", kind: .expense,
                     keywords: "uzmobile,beeline,ucell,mobiuz,uztelecom,internet,sarkor,comnet,turon,tps"),
        CategorySeed(name: "Obunalar", icon: "repeat", color: "#A855F7", kind: .expense,
                     keywords: "apple.com,icloud,google,netflix,spotify,youtube,subscription,obuna,openai,chatgpt,claude,anthropic,github"),
        CategorySeed(name: "Kiyim-kechak", icon: "tshirt.fill", color: "#EC4899", kind: .expense,
                     keywords: "zara,lc waikiki,defacto,kiyim,poyabzal,shoes,mango,koton"),
        CategorySeed(name: "Sog'liq", icon: "cross.case.fill", color: "#EF4444", kind: .expense,
                     keywords: "apteka,dorixona,klinika,med,shifo,pharm,stomatolog,hospital"),
        CategorySeed(name: "Ta'lim", icon: "book.fill", color: "#8B5CF6", kind: .expense,
                     keywords: "kurs,talim,universitet,maktab,kitob,udemy,coursera,school"),
        CategorySeed(name: "Ko'ngilochar", icon: "gamecontroller.fill", color: "#F43F5E", kind: .expense,
                     keywords: "kino,cinema,steam,playstation,game,o'yin,bowling,park"),
        CategorySeed(name: "Uy-ro'zg'or", icon: "sofa.fill", color: "#14B8A6", kind: .expense,
                     keywords: "mebel,texnika,mediapark,texnomart,idea,uy"),
        CategorySeed(name: "O'tkazmalar", icon: "arrow.left.arrow.right", color: "#64748B", kind: .expense,
                     keywords: "perevod,p2p,o'tkazma,otkazma,payme,click,uzum,paynet"),
        CategorySeed(name: debtPaymentCategory, icon: "arrow.uturn.left.circle.fill", color: "#FB7185", kind: .expense, keywords: ""),
        CategorySeed(name: goalCategory, icon: "target", color: "#7C3AED", kind: .expense, keywords: ""),
        CategorySeed(name: "Boshqa xarajat", icon: "ellipsis.circle.fill", color: "#94A3B8", kind: .expense, keywords: ""),
        CategorySeed(name: "Maosh", icon: "briefcase.fill", color: "#10B981", kind: .income,
                     keywords: "zarplata,maosh,oylik,salary,ish haqi,avans"),
        CategorySeed(name: "Qo'shimcha daromad", icon: "star.fill", color: "#F59E0B", kind: .income,
                     keywords: "bonus,freelance,premiya,mukofot,bug bounty,hackerone"),
        CategorySeed(name: "Kirim o'tkazma", icon: "arrow.down.circle.fill", color: "#22D3EE", kind: .income,
                     keywords: "perevod,p2p,popolnenie,o'tkazma,kartaga"),
        CategorySeed(name: debtReturnCategory, icon: "arrow.uturn.right.circle.fill", color: "#34D399", kind: .income, keywords: ""),
        CategorySeed(name: "Sovg'a", icon: "gift.fill", color: "#E879F9", kind: .income, keywords: "sovg'a,gift,podarok"),
        CategorySeed(name: "Boshqa kirim", icon: "plus.circle.fill", color: "#94A3B8", kind: .income, keywords: "")
    ]

    static func seedIfNeeded(_ ctx: ModelContext) {
        let count = (try? ctx.fetchCount(FetchDescriptor<FinCategory>())) ?? 0
        guard count == 0 else { return }
        for (i, c) in categories.enumerated() {
            ctx.insert(FinCategory(name: c.name, icon: c.icon, colorHex: c.color, kind: c.kind,
                                   keywords: c.keywords, sortOrder: i, isSystem: true))
        }
        try? ctx.save()
    }
}

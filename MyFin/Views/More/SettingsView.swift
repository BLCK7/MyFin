import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @AppStorage("userName") private var userName = ""
    @AppStorage("baseCurrency") private var base = "UZS"
    @AppStorage("appearance") private var appearance = "dark"
    @AppStorage("faceIDEnabled") private var faceIDEnabled = false
    @AppStorage("hideAmounts") private var hideAmounts = false
    @AppStorage("defaultSMSAccountID") private var defaultAccount = ""
    @AppStorage("onboarded") private var onboarded = true
    @AppStorage("autoLockSeconds") private var autoLock = 0
    @Environment(AppLock.self) private var lock
    @State private var changePin = false
    @State private var exportURL: URL?
    @State private var csvURL: URL?
    @State private var importing = false
    @State private var message: String?
    @State private var confirmReset = false
    @State private var confirmImport: URL?

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        Form {
            Section("Profil") {
                TextField("Ismingiz", text: $userName)
                Picker("Asosiy valyuta", selection: $base) {
                    ForEach(Currencies.all, id: \.self) { c in
                        Text("\(Currencies.flag(c)) \(c) — \(Currencies.name(c))").tag(c)
                    }
                }
                Picker("Ko'rinish", selection: $appearance) {
                    Text("Qorong'i").tag("dark")
                    Text("Yorug'").tag("light")
                    Text("Tizim").tag("system")
                }
            }

            Section {
                Button {
                    changePin = true
                } label: {
                    Label("PIN-kodni o'zgartirish", systemImage: "lock.rotation")
                }
                Toggle(isOn: Binding(get: { faceIDEnabled }, set: { newValue in toggleBiometric(newValue) })) {
                    Label("\(Biometrics.name) bilan ochish", systemImage: Biometrics.icon)
                }
                .disabled(!Biometrics.available)
                Picker(selection: $autoLock) {
                    Text("Darhol").tag(0)
                    Text("30 soniya").tag(30)
                    Text("1 daqiqa").tag(60)
                    Text("5 daqiqa").tag(300)
                } label: {
                    Label("Avtomatik qulflash", systemImage: "timer")
                }
                Toggle(isOn: $hideAmounts) {
                    Label("Summalarni yashirish", systemImage: "eye.slash")
                }
                Button {
                    lock.lock()
                } label: {
                    Label("Hozir qulflash", systemImage: "lock.fill")
                }
            } header: {
                Text("Xavfsizlik va maxfiylik")
            } footer: {
                Text("PIN-kod PBKDF2 (SHA-256, 120 000 iteratsiya) bilan xeshlanib Keychain'da saqlanadi. 5 ta xato urinishdan keyin kirish vaqtincha bloklanadi. Ma'lumotlar faqat shu iPhone'da.")
            }

            Section {
                Picker("SMS uchun asosiy hisob", selection: $defaultAccount) {
                    Text("Avtomatik").tag("")
                    ForEach(accounts.filter { !$0.isArchived }) { a in
                        Text(a.displayName).tag(a.id.uuidString)
                    }
                }
                NavigationLink {
                    AutomationView()
                } label: {
                    Label("SMS / Apple Pay avtomatizatsiyasi", systemImage: "bolt.badge.automatic.fill")
                }
                Toggle(isOn: Binding(get: { UserDefaults.standard.object(forKey: "reviewNotifications") as? Bool ?? true },
                                     set: { UserDefaults.standard.set($0, forKey: "reviewNotifications") })) {
                    Label("Har operatsiyadan keyin izoh so'rash", systemImage: "text.bubble")
                }
                Toggle(isOn: Binding(get: { UserDefaults.standard.object(forKey: "learnCategories") as? Bool ?? true },
                                     set: { UserDefaults.standard.set($0, forKey: "learnCategories") })) {
                    Label("Tanlovlarimdan o'rganish", systemImage: "brain")
                }
                Toggle(isOn: Binding(get: { UserDefaults.standard.object(forKey: "balanceCheck") as? Bool ?? true },
                                     set: { UserDefaults.standard.set($0, forKey: "balanceCheck") })) {
                    Label("Qoldiqni bank bilan solishtirish", systemImage: "checkmark.shield")
                }
            } header: {
                Text("Avtomatizatsiya")
            } footer: {
                Text("SMS'da karta raqami bo'lmasa yoki mos karta topilmasa, shu hisob ishlatiladi. Xabardagi qoldiq MyFin'dagidan farq qilsa, bildirishnoma keladi.")
            }

            Section {
                Button {
                    Task {
                        let ok = await Notifier.requestAuthorization()
                        message = ok ? "Bildirishnomalar yoqildi." : "Ruxsat berilmadi. Sozlamalar → MyFin → Bildirishnomalar."
                    }
                } label: {
                    Label("Bildirishnomalarga ruxsat", systemImage: "bell.badge")
                }
            } header: {
                Text("Eslatmalar")
            } footer: {
                Text("Qarz muddati, doimiy to'lovlar va byudjet limitlari haqida ogohlantiradi.")
            }

            Section {
                Button {
                    do { exportURL = try BackupManager.exportJSON(context) } catch { message = "Xatolik: \(error.localizedDescription)" }
                } label: {
                    Label("Zaxira nusxa yaratish (JSON)", systemImage: "externaldrive.badge.plus")
                }
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Zaxirani saqlash / yuborish", systemImage: "square.and.arrow.up")
                    }
                }
                Button {
                    importing = true
                } label: {
                    Label("Zaxiradan tiklash", systemImage: "externaldrive.badge.timemachine")
                }
                Button {
                    do { csvURL = try BackupManager.exportCSV(context) } catch { message = "Xatolik: \(error.localizedDescription)" }
                } label: {
                    Label("Operatsiyalarni CSV'ga eksport", systemImage: "tablecells")
                }
                if let csvURL {
                    ShareLink(item: csvURL) {
                        Label("CSV faylni ulashish", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text("Ma'lumotlar")
            } footer: {
                Text("Ilovani o'chirib qayta o'rnatsangiz, ma'lumotlar yo'qoladi. Muntazam zaxira nusxa olib, Fayllar ilovasiga saqlang. Shaxsiy seyf zaxiraga kirmaydi: uning kaliti faqat shu iPhone'da.")
            }

            Section {
                Button("Barcha ma'lumotlarni o'chirish", role: .destructive) { confirmReset = true }
            }

            Section {
                LabeledContent("Versiya", value: version)
                LabeledContent("Muallif", value: "Saminov")
            }
        }
        .screenBackground()
        .navigationTitle("Sozlamalar")
        .fullScreenCover(isPresented: $changePin) {
            PasscodeSetupView(mode: .change, onComplete: {
                changePin = false
                message = "PIN-kod yangilandi."
            }, onCancel: {
                changePin = false
            })
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { confirmImport = url }
        }
        .confirmationDialog("Joriy ma'lumotlar zaxiradagilar bilan almashtirilsinmi?",
                            isPresented: Binding(get: { confirmImport != nil }, set: { if !$0 { confirmImport = nil } }),
                            titleVisibility: .visible) {
            Button("Tiklash", role: .destructive) {
                guard let url = confirmImport else { return }
                do {
                    let n = try BackupManager.importJSON(from: url, ctx: context)
                    message = "Tiklandi: \(n) ta operatsiya."
                } catch {
                    message = "Faylni o'qib bo'lmadi: \(error.localizedDescription)"
                }
                confirmImport = nil
            }
        }
        .confirmationDialog("Hamma narsa o'chirilsinmi?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Ha, o'chirish", role: .destructive) {
                BackupManager.wipe(context)
                VaultCrypto.destroyKey()
                UserDefaults.standard.removeObject(forKey: "seedVersion")
                SeedData.seedIfNeeded(context)
                PasscodeStore.clear()
                faceIDEnabled = false
                onboarded = false
            }
        } message: {
            Text("Hisoblar, operatsiyalar, qarzlar va boshqa barcha ma'lumotlar qaytarib bo'lmas darajada o'chiriladi.")
        }
        .alert("MyFin", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func toggleBiometric(_ enable: Bool) {
        Task {
            let ok = await Biometrics.authenticateBiometric(reason: enable ? "\(Biometrics.name) bilan kirishni yoqish" : "\(Biometrics.name) bilan kirishni o'chirish")
            if ok { faceIDEnabled = enable }
        }
    }
}

struct AutomationView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Environment(\.openURL) private var openURL
    @State private var script = Self.sampleScript
    @State private var report: Sandbox.Report?

    static let sampleScript = """
    # Har qatorda bitta xabar: [Ilova] matn. SMS uchun [SMS], Apple Pay uchun [Apple Pay] summa | do'kon | karta
    [TBC UZ] Siz "UzMobile" uchun 1000.00 UZS muvaffaqiyatli to‘lov qildingiz
    [TBC UZ] Pul yechish, karta: *7758. 1,000.00 UZS. Balans: 1,530.34 UZS.
    [Uzum Bank | Payment completed] 5 000 UZS, card *7675, UB P2P VISAUZUM2HUMO FEE. Available: 734,60 UZS
    [SMS] HUMOCARD *9300: oplata 2000.00 UZS; Humo to Visa>Tashken; 26-11-27 18:57;  Dostupno: 62.22 UZS
    [SMS] Kartaga o'tkazma: TBC VISA SALOM2UZCARD, UZ,27.11.26 19:01,karta ***7169. Miqdor:3000.00 UZS Qoldiq:28431.50 UZS
    """
    @State private var log: [AutomationEvent] = []
    @State private var expandedBank: String?

    private struct BankGuide: Identifiable {
        let id: String
        let icon: String
        let color: String
        let steps: [(String, String)]
    }

    private static func notificationSteps(app: String, field: String) -> [(String, String)] {
        [("Bildirishnoma triggeri",
          "Shortcuts → Avtomatizatsiya → “+” → “Bildirishnoma” (Notification) → Ilova: \(app). Matn shartini qo'ymang (yoki “so'm / UZS / сум” bo'lsa). “Darhol ishga tushirish”ni yoqing, “Ishga tushganda xabar bering”ni o'chiring."),
         ("MyFin amali",
          "“+ Amal” → MyFin → “Bank bildirishnomasini yozish”. Matn = Bildirishnoma → Body (Matn), Sarlavha = Title. “Ilova” maydoniga \(field) deb yozing — MyFin shu nom bo'yicha kartangizni topadi."),
         ("Ilova bildirishnomalari yoqilgan bo'lsin",
          "Sozlamalar → Bildirishnomalar → \(app) → ruxsat berilgan, “Ko'rinishlar”da matn ko'rinadigan bo'lsin. Telefon qulflangan holatda ham ishlashi uchun “Previews: Always”.")]
    }

    private var guides: [BankGuide] {
        [
            BankGuide(id: "TBC Bank", icon: "building.columns.fill", color: "#00A3E0",
                      steps: Self.notificationSteps(app: "TBC UZ", field: "TBC") + [
                        ("Visa karta Wallet'da bo'lsa", "Apple Pay bilan to'lansa, “Wallet (Apple Pay)” bo'limidagi Tranzaksiya triggerini ham qo'shing. Ikkalasi ishlasa ham operatsiya bir marta yoziladi.")
                      ]),
            BankGuide(id: "Wallet (Apple Pay)", icon: "wallet.pass.fill", color: "#111827",
                      steps: [
                        ("Tranzaksiya triggeri", "Shortcuts → Avtomatizatsiya → “+” → “Tranzaksiya” (Transaction) → Karta: TBC Visa (va boshqa Wallet kartalari) → “Darhol ishga tushirish”."),
                        ("MyFin amali", "MyFin → “Apple Pay xaridini yozish”: Summa = Qisqa buyruq kiritmasi → Amount, Do'kon = Merchant, Karta = Card or Pass (Name)."),
                        ("Karta nomi", "Hisoblar bo'limida kartaning Bank maydoniga “TBC” yozing yoki oxirgi 4 raqamni kiriting — MyFin xaridni to'g'ri kartaga yozadi.")
                      ]),
            BankGuide(id: "Uzum Bank", icon: "u.circle.fill", color: "#7000FF",
                      steps: Self.notificationSteps(app: "Uzum Bank", field: "Uzum")),
            BankGuide(id: "Anorbank", icon: "a.circle.fill", color: "#E11D48",
                      steps: Self.notificationSteps(app: "Anorbank", field: "Anor")),
            BankGuide(id: "Payme", icon: "p.circle.fill", color: "#00C2C2",
                      steps: Self.notificationSteps(app: "Payme", field: "Payme") + [
                        ("Qaysi karta", "Payme bildirishnomasida karta raqamining oxirgi 4 raqami bo'lsa, MyFin o'sha kartaga yozadi. Bo'lmasa, standart kartaga yoziladi — keyin tahrirlash mumkin.")
                      ]),
            BankGuide(id: "Paynet", icon: "p.square.fill", color: "#16A34A",
                      steps: Self.notificationSteps(app: "Paynet", field: "Paynet"))
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GlassCard(tint: Palette.accent) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Qanday ishlaydi", systemImage: "bolt.fill").font(.headline)
                        Text("iOS hech bir ilovaga boshqa ilovalarning bildirishnomalarini o'qishga ruxsat bermaydi. Shuning uchun har bir bank uchun Shortcuts'da bir marta avtomatizatsiya yaratiladi: bildirishnoma, SMS yoki Apple Pay xaridi kelishi bilan Shortcuts matnni MyFin'ga uzatadi. Avtomatizatsiya yaratilmagan bo'lsa, MyFin hech narsani ko'rmaydi.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                logCard

                sourcesCard

                Text("Banklar bo'yicha sozlash").font(.headline).padding(.top, 4)
                ForEach(guides) { g in
                    GlassCard(padding: 14) {
                        DisclosureGroup(isExpanded: Binding(
                            get: { expandedBank == g.id },
                            set: { expandedBank = $0 ? g.id : nil }
                        )) {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(g.steps.enumerated()), id: \.offset) { i, st in
                                    stepRow(i + 1, st.0, st.1)
                                }
                            }
                            .padding(.top, 10)
                        } label: {
                            HStack(spacing: 12) {
                                IconBadge(icon: g.icon, color: Color(hex: g.color), size: 34)
                                Text(g.id).font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                            }
                        }
                        .tint(.primary)
                    }
                }

                Text("Har qanday bank uchun · Back Tap skrinshot").font(.headline).padding(.top, 4)
                step(1, "Qisqa buyruq yarating", "Shortcuts → “+” → amallar: “Skrinshot olish” (Take Screenshot) → MyFin “Skrinshotdan yozish” (Rasm = Skrinshot). Nomi: “MyFin skrinshot”.")
                step(2, "Orqa tomonga ikki marta urish", "Sozlamalar → Universal kirish → Teginish → Orqaga teginish (Back Tap) → Ikki marta → “MyFin skrinshot”.")
                step(3, "Ishlatish", "Bank yoki Wallet bildirishnomasi chiqqanda telefon orqasiga ikki marta tegining — MyFin ekrandagi summa, karta va do'konni o'qib, operatsiyani yozadi. Avtomatizatsiya ishlamay qolgan holatlar uchun zaxira usul.")

                Text("Bank SMS").font(.headline).padding(.top, 4)
                step(1, "Xabar triggeri", "Shortcuts → Avtomatizatsiya → “+” → “Message” (When I receive a message) → Sender: bank jo'natuvchisi (TBC, HUMO, UZCARD, 900…). Jo'natuvchi ro'yxatda chiqmasa, “Message Contains” filtri: “karta”.")
                step(2, "MyFin amali", "MyFin → “Bank SMS'ini yozish”. SMS matni = Message → Content (ko'k yorliq). Show When Run — o'chiq.")
                step(3, "Operator SMS'larini ulamang", "UZTELECOM, Beeline, Ucell, Mobiuz SMS'lari telefon balansi haqida — karta emas. Ularni ulasangiz, to'lov ikki marta yoziladi.")

                Text("Telegram: @HUMOcardbot va @CardXabarBot").font(.headline).padding(.top, 4)
                step(1, "Botni ulang", "Humo kartalar uchun @HUMOcardbot, Uzcard kartalar uchun @CardXabarBot. Ular to'lov tizimining o'zidan keladi — karta qaysi ilovada ishlatilmasin, har bir operatsiya va qoldiq keladi. Telefon balansiga bog'liq emas.")
                step(2, "Telegram'da matn ko'rinsin", "Telegram → Sozlamalar → Bildirishnomalar → “Xabar matnini ko'rsatish” yoqiq bo'lsin, aks holda Shortcuts'ga faqat “Yangi xabar” keladi.")
                step(3, "Bildirishnoma triggeri", "Ilova: Telegram. Add Filter → Title contains “HUMO” (yoki “CardXabar”). Amal: MyFin → “Bank bildirishnomasini yozish”: Matn = Body, Sarlavha = Title, Ilova = “HUMO bot” (yoki “CardXabar”).")

                Button {
                    if let url = URL(string: "shortcuts://") { openURL(url) }
                } label: {
                    Label("Shortcuts ilovasini ochish", systemImage: "arrow.up.forward.app.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                sandboxCard
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationTitle("Avtomatizatsiya")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { log = AutomationLog.all() }
        .refreshable { log = AutomationLog.all() }
    }

    private var sandboxCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Sinov stoli", systemImage: "testtube.2").font(.headline)
                Text("Xabarlarni ketma-ket yozing — MyFin ularni kartalaringizning nusxasida ishlatib, nima yozilishini ko'rsatadi. Haqiqiy ma'lumot, bildirishnoma va jurnal o'zgarmaydi.")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $script)
                    .font(.caption.monospaced())
                    .frame(minHeight: 140)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 14))
                HStack(spacing: 10) {
                    Button {
                        report = Sandbox.run(Sandbox.parse(script), copying: context)
                    } label: {
                        Label("Sinash", systemImage: "play.fill")
                    }
                    .buttonStyle(.glassProminent)
                    Button("Tozalash") {
                        script = ""
                        report = nil
                    }
                    .buttonStyle(.glass)
                    Spacer()
                    Button("Namuna") {
                        script = Self.sampleScript
                        report = nil
                    }
                    .font(.caption)
                }
                if let report {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(report.steps.enumerated()), id: \.offset) { i, step in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(i + 1). \(step.input)").font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                                Text(step.result).font(.caption)
                            }
                        }
                        Divider()
                        Text("Natija").font(.subheadline.weight(.semibold))
                        if report.transactions.isEmpty {
                            Text("Hech qanday operatsiya yozilmadi.").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(report.transactions, id: \.self) { Text("• " + $0).font(.caption) }
                        if !report.balances.isEmpty {
                            Text("Balanslar").font(.subheadline.weight(.semibold)).padding(.top, 4)
                            ForEach(report.balances, id: \.self) { Text("• " + $0).font(.caption) }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.accent.opacity(0.12), in: .rect(cornerRadius: 14))
                }
            }
        }
    }

    private var sourcesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Kartalar holati", systemImage: "creditcard.and.123").font(.headline)
                Text("Har bir karta uchun ishonchli manba — kartani chiqargan bankning ilovasi yoki SMS. Payme, Paynet, Click, Wallet va boshqa ilovalar xabari “tasdiqlanmagan” (⏱) bo'lib yoziladi; bank xabari kelganda ular bitta operatsiyaga birlashadi, summa bankniki bo'ladi.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(accounts.filter { $0.kind == .card && !$0.isArchived }) { a in
                    let src = SourceStatus.lastConfirmed(a.id)
                    let issuer = FinanceEngine.issuerKey(of: a)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(a.displayName).font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: src != nil ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(src != nil ? Palette.income : Palette.warning)
                        }
                        if issuer == nil || a.cardLast4.isEmpty {
                            Text("Hisoblar'da \(issuer == nil ? "Bank nomini" : "")\(issuer == nil && a.cardLast4.isEmpty ? " va " : "")\(a.cardLast4.isEmpty ? "oxirgi 4 raqamni" : "") kiriting.")
                                .font(.caption).foregroundStyle(Palette.warning)
                        }
                        if let src {
                            Text("Bank xabari: \(src.tag) · \(src.date.formatted(.relative(presentation: .named)))")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Bankdan karta raqamli xabar hali kelmagan — shu bank ilovasi uchun avtomatizatsiya sozlang.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let b = SourceStatus.lastBalance(a.id) {
                            Text("Qoldiq bank bilan solishtirildi: \(b.formatted(.relative(presentation: .named)))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12))
                }
            }
        }
    }

    private var logCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Jurnal", systemImage: "list.bullet.clipboard").font(.headline)
                    Spacer()
                    if !log.isEmpty {
                        Button("Tozalash") {
                            AutomationLog.clear()
                            log = []
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
                if log.isEmpty {
                    Text("Hali hech bir avtomatizatsiya MyFin'ni chaqirmagan. Bank bildirishnomasi kelgan bo'lsa-yu bu yer bo'sh bo'lsa, demak Shortcuts avtomatizatsiyasi yaratilmagan yoki ishga tushmagan — pastdagi ko'rsatmani bajaring.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Oxirgi \(log.count) ta chaqiruv. Operatsiya yozilmagan bo'lsa, shu matnni menga yuboring — parserni moslashtiraman.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(log.prefix(10)) { e in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(e.source + (e.app.isEmpty ? "" : " · \(e.app)"))
                                    .font(.caption.weight(.bold))
                                Spacer()
                                Text(e.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Text(e.input).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                                .textSelection(.enabled)
                            Text(e.result).font(.caption).lineLimit(3)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12))
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = e.input
                            } label: {
                                Label("Matnni nusxalash", systemImage: "doc.on.doc")
                            }
                            Button {
                                let line: String
                                if e.source == TxSource.applePay.title {
                                    line = "[Apple Pay] " + e.input.replacingOccurrences(of: " · ", with: " | ") + " | " + e.app
                                } else if e.source == TxSource.sms.title {
                                    line = "[SMS] " + e.input.replacingOccurrences(of: "\n", with: " ")
                                } else {
                                    let lines = e.input.components(separatedBy: .newlines)
                                    let body = lines.count > 1 ? lines.dropFirst().joined(separator: " ") : e.input
                                    let title = lines.count > 1 ? lines[0] : ""
                                    let app = e.app.isEmpty ? e.source : e.app
                                    line = title.isEmpty || title == app ? "[\(app)] \(body)" : "[\(app) | \(title)] \(body)"
                                }
                                script += (script.hasSuffix("\n") || script.isEmpty ? "" : "\n") + line + "\n"
                                report = nil
                            } label: {
                                Label("Sinov stoliga qo'shish", systemImage: "testtube.2")
                            }
                        }
                    }
                }
            }
        }
    }

    private func stepRow(_ n: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.caption.weight(.bold).monospacedDigit())
                .frame(width: 24, height: 24)
                .background(Palette.accent.gradient, in: .circle)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func step(_ n: Int, _ title: String, _ text: String) -> some View {
        GlassCard(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(n)")
                    .font(.headline.monospacedDigit())
                    .frame(width: 30, height: 30)
                    .background(Palette.accent.gradient, in: .circle)
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.bold))
                    Text(text).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func resultRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(.secondary)
            Spacer()
            Text(v).fontWeight(.semibold).multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }
}

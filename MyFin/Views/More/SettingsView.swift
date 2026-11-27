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
            } header: {
                Text("Avtomatizatsiya")
            } footer: {
                Text("SMS'da karta raqami bo'lmasa yoki mos karta topilmasa, shu hisob ishlatiladi.")
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
                Text("Ilovani o'chirib qayta o'rnatsangiz, ma'lumotlar yo'qoladi. Muntazam zaxira nusxa olib, Fayllar ilovasiga saqlang.")
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
    @Environment(\.openURL) private var openURL
    @State private var sample = "Pokupka: 50 000.00 UZS, KORZINKA SUPERMARKET, karta ***1234, 27.11.26 10:15, Balans: 1 234 567.00 UZS"
    @State private var parsed: ParsedSMS?
    @State private var tested = false
    @State private var result: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GlassCard(tint: Palette.accent) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Qanday ishlaydi", systemImage: "bolt.fill").font(.headline)
                        Text("Bankdan SMS yoki bank ilovasidan bildirishnoma kelishi bilan iOS “Shortcuts” uning matnini MyFin'ga uzatadi. MyFin summani, karta raqamining oxirgi 4 raqamini, do'konni va qoldiqni ajratib, operatsiyani yozadi va karta balansini yangilaydi. Ilovani ochish shart emas.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("1-usul · Bank SMS").font(.headline).padding(.top, 4)
                step(1, "Kartani qo'shing", "Hisoblar bo'limida kartani oxirgi 4 raqami bilan qo'shing. Notanish raqamli kartadan SMS kelsa, MyFin uni o'zi yaratadi.")
                step(2, "Shortcuts → Avtomatizatsiya → Xabar", "Shortcuts → “Avtomatizatsiya” → “+” → “Xabar” (Message). Jo'natuvchi: UZCARD, HUMO, 13131 yoki bankingiz raqami. “Darhol ishga tushirish”ni tanlang.")
                step(3, "MyFin amali", "Amal: MyFin → “Bank SMS'ini yozish”. “SMS matni” maydoniga “Qisqa buyruq kiritmasi → Kontent”ni bering.")

                Text("2-usul · Bank ilovasi bildirishnomasi (iOS 27+)").font(.headline).padding(.top, 4)
                step(1, "Bildirishnoma triggeri", "Shortcuts → “Avtomatizatsiya” → “+” → “Bildirishnoma” (When I get a notification) → ilovani tanlang: Uzum Bank, TBC, Kapitalbank, Anorbank, Click, Payme… Ixtiyoriy: matnda “so'm” yoki “UZS” bo'lsa.")
                step(2, "MyFin amali", "Amal: MyFin → “Bank bildirishnomasini yozish”. Matn = bildirishnoma matni (Body), Sarlavha = sarlavha (Title). “Darhol ishga tushirish”ni tanlang.")
                step(3, "Ikki marta yozilmaydi", "Bitta operatsiya SMS'dan ham, bildirishnomadan ham kelsa, MyFin 6 daqiqa ichidagi bir xil summani bitta deb hisoblaydi va faqat balansni yangilaydi.")

                Text("3-usul · Apple Pay").font(.headline).padding(.top, 4)
                step(1, "Tranzaksiya triggeri", "“Avtomatizatsiya” → “+” → “Tranzaksiya” (Transaction) → kartangiz → “Darhol”. Amal: MyFin → “Apple Pay xaridini yozish”; Summa, Do'kon, Karta maydonlariga kiritma qiymatlarini bering.")

                Button {
                    if let url = URL(string: "shortcuts://") { openURL(url) }
                } label: {
                    Label("Shortcuts ilovasini ochish", systemImage: "arrow.up.forward.app.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("SMS / bildirishnomani sinash").font(.headline)
                        Text("Bankdan kelgan haqiqiy SMS matnini shu yerga qo'ying va MyFin uni qanday tushunishini tekshiring.")
                            .font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $sample)
                            .frame(minHeight: 110)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 14))
                        HStack(spacing: 10) {
                            Button("Tekshirish") {
                                parsed = SMSParser.parse(sample)
                                tested = true
                                result = nil
                            }
                            .buttonStyle(.glass)
                            Button("MyFin'ga yozish") {
                                result = FinanceEngine.processSMS(sample, ctx: context)
                            }
                            .buttonStyle(.glassProminent)
                            .disabled(SMSParser.parse(sample) == nil)
                        }
                        if tested {
                            if let p = parsed {
                                VStack(alignment: .leading, spacing: 6) {
                                    resultRow("Turi", p.isIncome ? "Kirim" : "Chiqim")
                                    resultRow("Summa", p.amount.map { Money.format($0, p.currency) } ?? "—")
                                    resultRow("Karta", p.last4.map { "•\($0)" } ?? "topilmadi")
                                    resultRow("Qoldiq", p.balance.map { Money.format($0, p.balanceCurrency ?? p.currency) } ?? "—")
                                    resultRow("Joy", p.merchant.isEmpty ? "—" : p.merchant)
                                    resultRow("Kategoriya", FinanceEngine.guessCategory(text: p.merchant + " " + sample,
                                                                                         kind: p.isIncome ? .income : .expense, ctx: context))
                                }
                                .padding(12)
                                .background(Palette.income.opacity(0.12), in: .rect(cornerRadius: 14))
                            } else {
                                Text("Summa topilmadi. SMS formatini menga yuboring — parserni moslashtiraman.")
                                    .font(.caption).foregroundStyle(Palette.expense)
                            }
                        }
                        if let result {
                            Text(result)
                                .font(.callout)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Palette.accent.opacity(0.15), in: .rect(cornerRadius: 14))
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationTitle("Avtomatizatsiya")
        .navigationBarTitleDisplayMode(.inline)
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

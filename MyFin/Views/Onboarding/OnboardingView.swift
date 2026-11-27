import SwiftUI
import SwiftData

struct DraftCard: Identifiable {
    let id = UUID()
    var name: String
    var bank: String
    var last4: String
    var balance: Double
    var currency: String
    var color: String
}

struct DraftDebt: Identifiable {
    let id = UUID()
    var person: String
    var amount: Double
    var currency: String
    var direction: DebtDirection
    var due: Date?
}

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("userName") private var userName = ""
    @AppStorage("baseCurrency") private var base = "UZS"
    @AppStorage("faceIDEnabled") private var faceIDEnabled = false

    @State private var step = 0
    @State private var name = ""
    @State private var currency = "UZS"
    @State private var cashText = ""
    @State private var cashUSDText = ""
    @State private var cards: [DraftCard] = []
    @State private var debts: [DraftDebt] = []
    @State private var showCardForm = false
    @State private var showDebtForm = false
    @State private var lockEnabled = false
    @State private var notifications = true
    @State private var showPinSetup = false
    @AppStorage("pinSet") private var pinSet = false

    private let totalSteps = 6

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                if step > 0 {
                    progressBar
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                }
                Group {
                    switch step {
                    case 0: welcome
                    case 1: profile
                    case 2: cash
                    case 3: cardsStep
                    case 4: debtsStep
                    default: security
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                .id(step)
                footer
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $showCardForm) {
            DraftCardForm { cards.append($0) }
        }
        .sheet(isPresented: $showDebtForm) {
            DraftDebtForm(currency: currency) { debts.append($0) }
        }
        .fullScreenCover(isPresented: $showPinSetup) {
            PasscodeSetupView(mode: .create, onComplete: {
                pinSet = true
                showPinSetup = false
            }, onCancel: {
                showPinSetup = false
            })
        }
    }

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(1..<totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Palette.accent : Color.primary.opacity(0.15))
                    .frame(height: 5)
            }
        }
    }

    private var footer: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                if step > 0 {
                    Button {
                        withAnimation(.smooth) { step -= 1 }
                    } label: {
                        Image(systemName: "chevron.left").frame(width: 24, height: 24)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
                Button {
                    next()
                } label: {
                    Text(step == 0 ? "Boshlash" : (step == totalSteps - 1 ? "Tayyor" : "Davom etish"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(step == totalSteps - 1 && !pinSet)
            }
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 26) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Palette.accent.opacity(0.25))
                    .frame(width: 170, height: 170)
                    .blur(radius: 30)
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [Palette.accent, Color(hex: "#C084FC")],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(34)
                    .glassEffect(.regular, in: .circle)
            }
            VStack(spacing: 10) {
                Text("MyFin")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                Text("Pulingiz, kartalaringiz va qarzlaringiz — bitta joyda, real vaqtda.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 30)
            }
            VStack(alignment: .leading, spacing: 14) {
                feature("creditcard.and.123", "Karta balanslari bank SMS'idan avtomatik yangilanadi")
                feature("person.2.fill", "Qarzlar, muddatlar va eslatmalar")
                feature("chart.bar.xaxis", "Byudjet, maqsadlar va chuqur tahlil")
                feature("lock.shield.fill", "Ma'lumotlar faqat telefoningizda, Face ID himoyasida")
            }
            .padding(20)
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    private func feature(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(Palette.accent)
                .frame(width: 28)
            Text(text).font(.subheadline)
        }
    }

    private func stepHeader(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            IconBadge(icon: icon, color: Palette.accent, size: 52)
            Text(title).font(.largeTitle.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profile: some View {
        ScrollView {
            VStack(spacing: 22) {
                stepHeader("person.crop.circle.fill", "Tanishaylik", "Ismingiz va asosiy valyutangiz.")
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("Ismingiz", text: $name)
                            .font(.title3)
                            .textContentType(.givenName)
                        Divider()
                        Text("Asosiy valyuta").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Picker("Valyuta", selection: $currency) {
                            ForEach(Currencies.all, id: \.self) { c in
                                Text(c).tag(c)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text("Barcha jami summalar \(Currencies.name(currency).lowercased())da hisoblanadi. Boshqa valyutalar MB kursi bo'yicha o'giriladi.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
        }
    }

    private var cash: some View {
        ScrollView {
            VStack(spacing: 22) {
                stepHeader("banknote.fill", "Naqd pul", "Hozir qo'lingizda qancha naqd pul bor?")
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("So'mda").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        AmountField(title: "0", text: $cashText, currency: "UZS")
                        Divider()
                        Text("Dollarda (ixtiyoriy)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        AmountField(title: "0", text: $cashUSDText, currency: "USD")
                    }
                }
                Text("Keyinchalik “Hisoblar” bo'limida istalgan vaqtda o'zgartirish mumkin.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }

    private var cardsStep: some View {
        ScrollView {
            VStack(spacing: 18) {
                stepHeader("creditcard.fill", "Bank kartalari", "Kartalaringiz va ulardagi joriy balans. Oxirgi 4 raqam SMS'larni kartaga bog'laydi.")
                ForEach(cards) { c in
                    HStack {
                        let preview = Account(name: c.name, kind: .card, bank: c.bank, cardLast4: c.last4,
                                              currency: c.currency, balance: c.balance, colorHex: c.color)
                        AccountCardView(account: preview).frame(height: 140)
                        Button {
                            cards.removeAll { $0.id == c.id }
                        } label: {
                            Image(systemName: "trash").frame(width: 22, height: 22)
                        }
                        .buttonStyle(.glass)
                        .tint(Palette.expense)
                    }
                }
                Button {
                    showCardForm = true
                } label: {
                    Label(cards.isEmpty ? "Karta qo'shish" : "Yana karta qo'shish", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glass)
                if cards.isEmpty {
                    Text("Kartangiz bo'lmasa, bu qadamni o'tkazib yuborishingiz mumkin.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
    }

    private var debtsStep: some View {
        ScrollView {
            VStack(spacing: 18) {
                stepHeader("person.2.fill", "Qarzlar", "Kimdan qarzdorsiz va kim sizdan qarzdor?")
                ForEach(debts) { d in
                    GlassCard(padding: 14, tint: d.direction.color) {
                        HStack(spacing: 12) {
                            IconBadge(icon: d.direction.icon, color: d.direction.color, size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.person).font(.headline)
                                Text(d.direction.title + (d.due.map { " · \($0.uzDate)" } ?? ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            AmountText(value: d.amount, currency: d.currency, font: .subheadline.weight(.bold), color: d.direction.color)
                            Button {
                                debts.removeAll { $0.id == d.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button {
                    showDebtForm = true
                } label: {
                    Label("Qarz qo'shish", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glass)
                if debts.isEmpty {
                    Text("Qarzingiz bo'lmasa — ajoyib! Davom eting.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
    }

    private var security: some View {
        ScrollView {
            VStack(spacing: 22) {
                stepHeader("lock.shield.fill", "Himoya", "Ilovaga kirish uchun PIN-kod o'rnating. Face ID bilan ham ochish mumkin.")
                GlassCard(tint: pinSet ? Palette.income : Palette.accent) {
                    Button {
                        showPinSetup = true
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: pinSet ? "checkmark.shield.fill" : "lock.badge.plus")
                                .font(.title2)
                                .foregroundStyle(pinSet ? Palette.income : Palette.accent)
                                .contentTransition(.symbolEffect(.replace))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pinSet ? "PIN-kod o'rnatildi" : "PIN-kod o'rnatish")
                                    .font(.headline)
                                Text(pinSet ? "O'zgartirish uchun bosing" : "Majburiy · 4 yoki 6 raqam")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                GlassCard {
                    VStack(spacing: 16) {
                        Toggle(isOn: Binding(get: { lockEnabled }, set: { v in
                            if v {
                                Task { lockEnabled = await Biometrics.authenticateBiometric(reason: "Face ID bilan kirishni yoqish") }
                            } else {
                                lockEnabled = false
                            }
                        })) {
                            Label("\(Biometrics.name) bilan ochish", systemImage: Biometrics.icon)
                        }
                        .disabled(!Biometrics.available || !pinSet)
                        Divider()
                        Toggle(isOn: $notifications) {
                            Label("Eslatmalar (qarz, to'lov, byudjet)", systemImage: "bell.badge.fill")
                        }
                    }
                }
                GlassCard(tint: Palette.income) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Deyarli tayyor!").font(.headline)
                        summaryLine("Naqd pul", total: (parseAmount(cashText) ?? 0), currency: "UZS")
                        if (parseAmount(cashUSDText) ?? 0) > 0 {
                            summaryLine("Naqd dollar", total: parseAmount(cashUSDText) ?? 0, currency: "USD")
                        }
                        Text("\(cards.count) ta karta · \(debts.count) ta qarz yozuvi")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
        }
    }

    private func summaryLine(_ title: String, total: Double, currency: String) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            AmountText(value: total, currency: currency, font: .subheadline.weight(.semibold))
        }
    }

    // MARK: Actions

    private func next() {
        if step < totalSteps - 1 {
            withAnimation(.smooth) { step += 1 }
            return
        }
        finish()
    }

    private func finish() {
        SeedData.seedIfNeeded(context)
        var order = 0
        let cashUZS = parseAmount(cashText) ?? 0
        let cashUSD = parseAmount(cashUSDText) ?? 0
        context.insert(Account(name: "Naqd pul", kind: .cash, currency: "UZS", balance: cashUZS, colorHex: "#10B981", sortOrder: order))
        order += 1
        if cashUSD > 0 {
            context.insert(Account(name: "Naqd dollar", kind: .cash, currency: "USD", balance: cashUSD, colorHex: "#0EA5E9", sortOrder: order))
            order += 1
        }
        for c in cards {
            context.insert(Account(name: c.name, kind: .card, bank: c.bank, cardLast4: c.last4, currency: c.currency,
                                   balance: c.balance, colorHex: c.color, sortOrder: order))
            order += 1
        }
        try? context.save()
        for d in debts {
            _ = FinanceEngine.addDebt(person: d.person, direction: d.direction, amount: d.amount, currency: d.currency,
                                      dueDate: d.due, note: "", reminder: d.due != nil, moveMoney: false, accountID: nil,
                                      ctx: context)
        }
        userName = name.trimmingCharacters(in: .whitespaces)
        base = currency
        faceIDEnabled = lockEnabled && Biometrics.available
        AppLock.shared.unlock()
        Haptics.success()
        if notifications {
            Task { _ = await Notifier.requestAuthorization() }
        }
        withAnimation(.smooth) { onboarded = true }
    }
}

struct DraftCardForm: View {
    let onSave: (DraftCard) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Asosiy karta"
    @State private var bank = ""
    @State private var last4 = ""
    @State private var balanceText = ""
    @State private var currency = "UZS"
    @State private var color = Palette.swatches[0]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AccountCardView(account: Account(name: name, kind: .card, bank: bank, cardLast4: last4,
                                                     currency: currency, balance: parseAmount(balanceText) ?? 0, colorHex: color))
                        .frame(height: 150)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
                Section("Karta") {
                    TextField("Nomi", text: $name)
                    TextField("Bank (Kapitalbank, Anorbank, TBC…)", text: $bank)
                    TextField("Oxirgi 4 raqam", text: $last4)
                        .keyboardType(.numberPad)
                        .onChange(of: last4) { _, v in
                            let d = String(v.filter(\.isNumber).prefix(4))
                            if d != v { last4 = d }
                        }
                }
                Section("Joriy balans") {
                    AmountField(title: "0", text: $balanceText, currency: currency)
                    Picker("Valyuta", selection: $currency) {
                        ForEach(Currencies.all, id: \.self) { Text("\(Currencies.flag($0)) \($0)").tag($0) }
                    }
                }
                Section("Rang") {
                    ColorSwatchPicker(selection: $color)
                }
            }
            .navigationTitle("Karta qo'shish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Bekor") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Qo'shish") {
                        onSave(DraftCard(name: name.isEmpty ? "Karta" : name, bank: bank, last4: last4,
                                         balance: parseAmount(balanceText) ?? 0, currency: currency, color: color))
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DraftDebtForm: View {
    let currency: String
    let onSave: (DraftDebt) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var person = ""
    @State private var amountText = ""
    @State private var cur = "UZS"
    @State private var direction: DebtDirection = .iOwe
    @State private var hasDue = false
    @State private var due = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Yo'nalish", selection: $direction) {
                        ForEach(DebtDirection.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section("Kim") {
                    TextField("Ism", text: $person)
                }
                Section("Summa") {
                    AmountField(title: "0", text: $amountText, currency: cur)
                    Picker("Valyuta", selection: $cur) {
                        ForEach(Currencies.all, id: \.self) { Text("\(Currencies.flag($0)) \($0)").tag($0) }
                    }
                }
                Section {
                    Toggle("Qaytarish muddati", isOn: $hasDue.animation())
                    if hasDue { DatePicker("Sana", selection: $due, displayedComponents: .date) }
                }
            }
            .navigationTitle("Qarz qo'shish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Bekor") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Qo'shish") {
                        if let a = parseAmount(amountText), a > 0, !person.isEmpty {
                            onSave(DraftDebt(person: person, amount: a, currency: cur, direction: direction, due: hasDue ? due : nil))
                        }
                        dismiss()
                    }
                    .disabled(person.isEmpty || (parseAmount(amountText) ?? 0) <= 0)
                }
            }
            .onAppear {
                if !loaded { loaded = true; cur = currency }
            }
        }
    }
}

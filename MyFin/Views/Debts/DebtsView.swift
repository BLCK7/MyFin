import SwiftUI
import SwiftData

struct DebtsView: View {
    @Query(sort: \Debt.createdAt, order: .reverse) private var debts: [Debt]
    @Environment(RateStore.self) private var rates
    @AppStorage("baseCurrency") private var base = "UZS"
    @State private var direction: DebtDirection = .iOwe
    @State private var showEditor = false
    @State private var showClosed = false

    private var open: [Debt] {
        debts.filter { $0.direction == direction && !$0.isClosed }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }
    private var closed: [Debt] { debts.filter { $0.direction == direction && $0.isClosed } }

    private func total(_ d: DebtDirection) -> Double {
        debts.filter { $0.direction == d && !$0.isClosed }
            .reduce(0) { $0 + rates.convert($1.remaining, from: $1.currency, to: base) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    GlassCard(padding: 18) {
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Qarzlarim", systemImage: DebtDirection.iOwe.icon)
                                    .font(.caption.weight(.semibold)).foregroundStyle(Palette.expense)
                                AmountText(value: total(.iOwe), currency: base, font: .title3.weight(.bold))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Divider().frame(height: 44)
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Haqlarim", systemImage: DebtDirection.owedToMe.icon)
                                    .font(.caption.weight(.semibold)).foregroundStyle(Palette.income)
                                AmountText(value: total(.owedToMe), currency: base, font: .title3.weight(.bold))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    Picker("Yo'nalish", selection: $direction) {
                        ForEach(DebtDirection.allCases) { d in
                            Text(d.title).tag(d)
                        }
                    }
                    .pickerStyle(.segmented)

                    if open.isEmpty {
                        GlassCard {
                            ContentUnavailableView(direction == .iOwe ? "Qarzingiz yo'q" : "Sizga hech kim qarzdor emas",
                                                   systemImage: "checkmark.seal",
                                                   description: Text("Yangi yozuv uchun yuqoridagi + tugmasini bosing."))
                        }
                    }

                    ForEach(open) { d in
                        NavigationLink {
                            DebtDetailView(debt: d)
                        } label: {
                            DebtCard(debt: d)
                        }
                        .buttonStyle(.plain)
                    }

                    if !closed.isEmpty {
                        DisclosureGroup(isExpanded: $showClosed) {
                            VStack(spacing: 10) {
                                ForEach(closed) { d in
                                    NavigationLink {
                                        DebtDetailView(debt: d)
                                    } label: {
                                        DebtCard(debt: d).opacity(0.65)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 8)
                        } label: {
                            Text("Yopilganlar (\(closed.count))").font(.headline)
                        }
                        .padding(14)
                        .glassEffect(.regular, in: .rect(cornerRadius: 22))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .screenBackground()
            .navigationTitle("Qarzlar")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showEditor = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showEditor) { DebtEditor(presetDirection: direction) }
        }
    }
}

struct DebtCard: View {
    let debt: Debt

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(debt.direction.color.gradient)
                        Text(String(debt.person.prefix(1)).uppercased())
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                    }
                    .frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(debt.person).font(.headline).lineLimit(1)
                        dueLabel
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        AmountText(value: debt.remaining, currency: debt.currency, font: .headline, color: debt.direction.color)
                        if debt.remaining != debt.principal {
                            AmountText(value: debt.principal, currency: debt.currency, font: .caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if debt.principal > 0 && debt.paidFraction > 0 {
                    ProgressCapsule(progress: debt.paidFraction, color: debt.direction.color, height: 6)
                }
            }
        }
    }

    @ViewBuilder
    private var dueLabel: some View {
        if debt.isClosed {
            Label("Yopilgan", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Palette.income)
        } else if let due = debt.dueDate {
            Label(debt.isOverdue ? "Muddati o'tgan: \(due.uzDate)" : due.uzDate, systemImage: "calendar")
                .font(.caption)
                .foregroundStyle(debt.isOverdue ? Palette.expense : Color.secondary)
        } else {
            Text("Muddatsiz").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct DebtEditor: View {
    var existing: Debt? = nil
    var presetDirection: DebtDirection = .iOwe

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var person = ""
    @State private var phone = ""
    @State private var direction: DebtDirection = .iOwe
    @State private var amountText = ""
    @State private var currency = "UZS"
    @State private var hasDue = false
    @State private var due = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var note = ""
    @State private var reminder = true
    @State private var moveMoney = false
    @State private var accountID: UUID?
    @State private var loaded = false

    private var isValid: Bool {
        !person.trimmingCharacters(in: .whitespaces).isEmpty && (parseAmount(amountText) ?? 0) > 0
            && (!moveMoney || accountID != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Yo'nalish", selection: $direction) {
                        ForEach(DebtDirection.allCases) { d in Text(d.title).tag(d) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section(direction == .iOwe ? "Kimdan qarz oldingiz" : "Kimga qarz berdingiz") {
                    TextField("Ism", text: $person)
                    TextField("Telefon (ixtiyoriy)", text: $phone).keyboardType(.phonePad)
                }
                Section(existing == nil ? "Summa" : "Qolgan summa") {
                    AmountField(title: "0", text: $amountText, currency: currency)
                    Picker("Valyuta", selection: $currency) {
                        ForEach(Currencies.all, id: \.self) { c in Text("\(Currencies.flag(c)) \(c)").tag(c) }
                    }
                }
                Section("Muddat") {
                    Toggle("Qaytarish muddati bor", isOn: $hasDue.animation())
                    if hasDue {
                        DatePicker("Sana", selection: $due, displayedComponents: .date)
                        Toggle("Eslatma yuborilsin", isOn: $reminder)
                    }
                }
                if existing == nil {
                    Section {
                        Toggle(direction == .iOwe ? "Pul hisobimga tushdi" : "Pul hisobimdan chiqdi", isOn: $moveMoney.animation())
                        if moveMoney {
                            Picker("Hisob", selection: $accountID) {
                                Text("Tanlang").tag(UUID?.none)
                                ForEach(accounts.filter { !$0.isArchived }) { a in
                                    Text(a.displayName).tag(UUID?.some(a.id))
                                }
                            }
                        }
                    } footer: {
                        Text("Yoqilsa, tanlangan hisob balansi ham o'zgaradi. Avvaldan mavjud qarzlar uchun o'chiq qoldiring.")
                    }
                }
                Section("Izoh") {
                    TextField("Izoh", text: $note, axis: .vertical)
                }
            }
            .navigationTitle(existing == nil ? "Yangi qarz" : "Qarzni tahrirlash")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Bekor") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Saqlash") { save() }.disabled(!isValid)
                }
            }
            .onAppear(perform: load)
            .task { _ = await Notifier.requestAuthorization() }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        direction = presetDirection
        currency = UserDefaults.standard.string(forKey: "baseCurrency") ?? "UZS"
        guard let d = existing else { return }
        person = d.person
        phone = d.phone
        direction = d.direction
        amountText = Money.number(d.remaining, decimals: Money.decimals(d.currency)).replacingOccurrences(of: " ", with: "")
        currency = d.currency
        hasDue = d.dueDate != nil
        due = d.dueDate ?? due
        note = d.note
        reminder = d.reminder
    }

    private func save() {
        guard let amount = parseAmount(amountText), amount > 0 else { return }
        let name = person.trimmingCharacters(in: .whitespaces)
        if let d = existing {
            let paid = d.principal - d.remaining
            d.person = name
            d.phone = phone
            d.direction = direction
            d.remaining = amount
            d.principal = amount + max(0, paid)
            d.currency = currency
            d.dueDate = hasDue ? due : nil
            d.note = note
            d.reminder = reminder
            d.isClosed = amount <= 0
            try? context.save()
            Notifier.scheduleDebt(id: d.id, person: name, amountText: Money.format(amount, currency),
                                  direction: direction, due: d.dueDate, enabled: reminder)
        } else {
            let created = FinanceEngine.addDebt(person: name, direction: direction, amount: amount, currency: currency,
                                                dueDate: hasDue ? due : nil, note: note, reminder: reminder,
                                                moveMoney: moveMoney, accountID: accountID, ctx: context)
            created.phone = phone
            try? context.save()
        }
        Haptics.success()
        dismiss()
    }
}

struct DebtDetailView: View {
    @Bindable var debt: Debt
    @Query(sort: \DebtPayment.date, order: .reverse) private var allPayments: [DebtPayment]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showPay = false
    @State private var showEdit = false
    @State private var confirmDelete = false

    private var payments: [DebtPayment] { allPayments.filter { $0.debtID == debt.id } }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard(padding: 20, tint: debt.direction.color) {
                    HStack(spacing: 18) {
                        ZStack {
                            RingProgress(progress: debt.paidFraction, color: debt.direction.color, lineWidth: 10)
                            Text("\(Int((debt.paidFraction * 100).rounded()))%")
                                .font(.headline.monospacedDigit())
                        }
                        .frame(width: 92, height: 92)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(debt.direction.title).font(.caption.weight(.semibold)).foregroundStyle(debt.direction.color)
                            AmountText(value: debt.remaining, currency: debt.currency, font: .title.weight(.bold))
                            HStack(spacing: 4) {
                                Text("Jami:")
                                AmountText(value: debt.principal, currency: debt.currency, font: .caption)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        infoRow("Ism", debt.person, "person.fill")
                        if !debt.phone.isEmpty { infoRow("Telefon", debt.phone, "phone.fill") }
                        infoRow("Yozilgan", debt.createdAt.uzDate, "calendar.badge.plus")
                        if let due = debt.dueDate {
                            infoRow("Muddat", due.uzDate, debt.isOverdue ? "exclamationmark.triangle.fill" : "calendar")
                        }
                        if !debt.note.isEmpty { infoRow("Izoh", debt.note, "text.alignleft") }
                    }
                }

                if !debt.isClosed {
                    GlassEffectContainer(spacing: 10) {
                        HStack(spacing: 10) {
                            Button { showPay = true } label: {
                                Label(debt.direction == .iOwe ? "To'lov qilish" : "To'lov qabul qilish", systemImage: "plus.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glassProminent)
                            Button {
                                FinanceEngine.addDebtPayment(debt, amount: debt.remaining, accountID: nil, note: "To'liq yopildi", ctx: context)
                            } label: {
                                Label("Yopish", systemImage: "checkmark").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                        }
                        .controlSize(.large)
                    }
                }

                SectionHeader(title: "To'lovlar tarixi")
                GlassCard(padding: 10) {
                    if payments.isEmpty {
                        Text("Hali to'lov yo'q").foregroundStyle(.secondary).padding(6)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(payments) { p in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(p.date.uzDate).font(.subheadline.weight(.semibold))
                                        Text(p.note.isEmpty ? (accounts.first { $0.id == p.accountID }?.displayName ?? "Hisobsiz") : p.note)
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    AmountText(value: p.amount, currency: debt.currency, font: .subheadline.weight(.bold),
                                               color: debt.direction.color)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationTitle(debt.person)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showEdit = true } label: { Label("Tahrirlash", systemImage: "pencil") }
                    if !debt.phone.isEmpty, let url = URL(string: "tel:\(debt.phone.filter { $0.isNumber || $0 == "+" })") {
                        Link(destination: url) { Label("Qo'ng'iroq", systemImage: "phone") }
                    }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("O'chirish", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showPay) { DebtPaymentSheet(debt: debt) }
        .sheet(isPresented: $showEdit) { DebtEditor(existing: debt) }
        .confirmationDialog("Qarz yozuvi o'chirilsinmi?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("O'chirish", role: .destructive) {
                FinanceEngine.deleteDebt(debt, ctx: context)
                dismiss()
            }
        }
    }

    private func infoRow(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(alignment: .top) {
            Label(title, systemImage: icon).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

struct DebtPaymentSheet: View {
    let debt: Debt
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @State private var amountText = ""
    @State private var accountID: UUID?
    @State private var note = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AmountField(title: "0", text: $amountText, currency: debt.currency)
                    Button("Qolgan summani kiritish") {
                        amountText = Money.number(debt.remaining, decimals: Money.decimals(debt.currency)).replacingOccurrences(of: " ", with: "")
                    }
                } header: {
                    Text("Summa")
                } footer: {
                    HStack(spacing: 4) {
                        Text("Qolgan:")
                        AmountText(value: debt.remaining, currency: debt.currency, font: .footnote)
                    }
                }
                Section {
                    Picker("Hisob", selection: $accountID) {
                        Text("Hisobga ta'sir qilmasin").tag(UUID?.none)
                        ForEach(accounts.filter { !$0.isArchived }) { a in
                            Text(a.displayName).tag(UUID?.some(a.id))
                        }
                    }
                    DatePicker("Sana", selection: $date)
                    TextField("Izoh", text: $note)
                } footer: {
                    Text(debt.direction == .iOwe ? "Tanlangan hisobdan chiqim yoziladi." : "Tanlangan hisobga kirim yoziladi.")
                }
            }
            .navigationTitle(debt.direction == .iOwe ? "Qarz to'lash" : "Qarz qabul qilish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Bekor") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Saqlash") {
                        if let a = parseAmount(amountText), a > 0 {
                            FinanceEngine.addDebtPayment(debt, amount: min(a, debt.remaining), accountID: accountID,
                                                         note: note, date: date, ctx: context)
                        }
                        dismiss()
                    }
                    .disabled((parseAmount(amountText) ?? 0) <= 0)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

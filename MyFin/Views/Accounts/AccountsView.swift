import SwiftUI
import SwiftData

struct AccountCardView: View {
    let account: Account

    var body: some View {
        let base = Color(hex: account.colorHex)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [base, base.opacity(0.55), Color.black.opacity(0.35)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 170, height: 170)
                .offset(x: 130, y: -70)
                .blur(radius: 2)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: account.kind.icon)
                        .font(.headline)
                    Text(account.bank.isEmpty ? account.kind.title : account.bank)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    if !account.includeInTotal {
                        Image(systemName: "eye.slash").font(.caption)
                    }
                }
                .opacity(0.9)
                Spacer(minLength: 6)
                Text(account.name)
                    .font(.subheadline.weight(.medium))
                    .opacity(0.9)
                    .lineLimit(1)
                AmountText(value: account.balance, currency: account.currency,
                           font: .system(size: 24, weight: .bold, design: .rounded), color: .white)
                if !account.cardLast4.isEmpty {
                    Text("•••• \(account.cardLast4)")
                        .font(.caption.monospaced())
                        .opacity(0.8)
                        .padding(.top, 2)
                }
            }
            .padding(16)
        }
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: base.opacity(0.35), radius: 14, y: 8)
    }
}

struct AccountsView: View {
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Environment(RateStore.self) private var rates
    @AppStorage("baseCurrency") private var base = "UZS"
    @State private var showEditor = false
    @State private var showTransfer = false
    @State private var showArchived = false

    private var active: [Account] { accounts.filter { !$0.isArchived } }
    private var archived: [Account] { accounts.filter { $0.isArchived } }

    private var total: Double {
        active.filter(\.includeInTotal).reduce(0) { $0 + rates.convert($1.balance, from: $1.currency, to: base) }
    }

    private var byCurrency: [(String, Double)] {
        var d: [String: Double] = [:]
        for a in active where a.includeInTotal { d[a.currency, default: 0] += a.balance }
        return d.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    GlassCard(padding: 20, tint: Palette.accent) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Jami mablag'").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            AmountText(value: total, currency: base, font: .system(size: 34, weight: .bold, design: .rounded))
                            if byCurrency.count > 1 {
                                HStack(spacing: 14) {
                                    ForEach(byCurrency, id: \.0) { item in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(Currencies.flag(item.0)) \(item.0)").font(.caption2).foregroundStyle(.secondary)
                                            AmountText(value: item.1, currency: item.0, font: .caption.weight(.semibold))
                                        }
                                    }
                                }
                            }
                        }
                    }

                    GlassEffectContainer(spacing: 10) {
                        HStack(spacing: 10) {
                            Button { showEditor = true } label: {
                                Label("Hisob qo'shish", systemImage: "plus").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glassProminent)
                            Button { showTransfer = true } label: {
                                Label("O'tkazma", systemImage: "arrow.left.arrow.right").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                            .disabled(active.count < 2)
                        }
                        .controlSize(.large)
                    }

                    if active.isEmpty {
                        GlassCard {
                            ContentUnavailableView("Hisoblar yo'q", systemImage: "creditcard",
                                                   description: Text("Karta, naqd pul yoki jamg'arma hisobini qo'shing."))
                        }
                    }

                    ForEach(active) { a in
                        NavigationLink {
                            AccountDetailView(account: a)
                        } label: {
                            AccountCardView(account: a).frame(height: 160)
                        }
                        .buttonStyle(.plain)
                    }

                    if !archived.isEmpty {
                        DisclosureGroup(isExpanded: $showArchived) {
                            VStack(spacing: 12) {
                                ForEach(archived) { a in
                                    NavigationLink {
                                        AccountDetailView(account: a)
                                    } label: {
                                        AccountCardView(account: a).frame(height: 140).opacity(0.6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 8)
                        } label: {
                            Text("Arxiv (\(archived.count))").font(.headline)
                        }
                        .padding(14)
                        .glassEffect(.regular, in: .rect(cornerRadius: 22))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .screenBackground()
            .navigationTitle("Hisoblar")
            .sheet(isPresented: $showEditor) { AccountEditor() }
            .sheet(isPresented: $showTransfer) { TransactionEditor(presetKind: .transfer) }
        }
    }
}

struct AccountDetailView: View {
    @Bindable var account: Account
    @Query(sort: \FinTransaction.date, order: .reverse) private var transactions: [FinTransaction]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \FinCategory.sortOrder) private var categories: [FinCategory]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var showAdjust = false
    @State private var adjustText = ""
    @State private var addKind: TxKind? = nil
    @State private var editing: FinTransaction?
    @State private var pendingDelete = false

    private var mine: [FinTransaction] {
        transactions.filter { $0.accountID == account.id || $0.toAccountID == account.id }
    }

    private var monthIn: Double {
        let cal = Calendar.current
        let rates = RateStore.shared
        return mine.filter { cal.isDate($0.date, equalTo: Date(), toGranularity: .month) }.reduce(0) { sum, t in
            if t.kind == .income && t.accountID == account.id {
                return sum + rates.convert(t.amount, from: t.currency, to: account.currency)
            }
            if t.kind == .transfer && t.toAccountID == account.id {
                return sum + (t.toAmount > 0 ? t.toAmount : rates.convert(t.amount, from: t.currency, to: account.currency))
            }
            return sum
        }
    }

    private var monthOut: Double {
        let cal = Calendar.current
        let rates = RateStore.shared
        return mine.filter { cal.isDate($0.date, equalTo: Date(), toGranularity: .month) }.reduce(0) { sum, t in
            if (t.kind == .expense || t.kind == .transfer) && t.accountID == account.id {
                return sum + rates.convert(t.amount, from: t.currency, to: account.currency)
            }
            return sum
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                AccountCardView(account: account).frame(height: 180)

                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        actionButton("Chiqim", "minus", Palette.expense) { addKind = .expense }
                        actionButton("Kirim", "plus", Palette.income) { addKind = .income }
                        actionButton("O'tkazma", "arrow.left.arrow.right", Palette.transfer) { addKind = .transfer }
                        actionButton("To'g'rilash", "slider.horizontal.3", Palette.accent) {
                            adjustText = Money.editString(account.balance, account.currency)
                            showAdjust = true
                        }
                    }
                }

                GlassCard {
                    HStack {
                        StatPill(title: "Shu oy kirim", value: monthIn, currency: account.currency, color: Palette.income, icon: "arrow.down.left")
                        StatPill(title: "Shu oy chiqim", value: monthOut, currency: account.currency, color: Palette.expense, icon: "arrow.up.right")
                    }
                }

                SectionHeader(title: "Operatsiyalar (\(mine.count))")
                GlassCard(padding: 6) {
                    if mine.isEmpty {
                        Text("Bu hisobda hali operatsiya yo'q").foregroundStyle(.secondary).padding()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(mine.prefix(100)) { t in
                                Button { editing = t } label: {
                                    TransactionRow(transaction: t, accounts: accounts, categories: categories)
                                }
                                .buttonStyle(.plain)
                                if t.id != mine.prefix(100).last?.id {
                                    Divider().padding(.leading, 60).opacity(0.4)
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
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Tahrirlash") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit, onDismiss: {
            guard pendingDelete else { return }
            // Leave this screen first; the account is removed once nothing on screen shows it any more.
            let doomed = account
            let ctx = context
            dismiss()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                FinanceEngine.deleteAccount(doomed, ctx: ctx)
            }
        }) {
            AccountEditor(existing: account, onDelete: { pendingDelete = true })
        }
        .sheet(item: $editing) { TransactionEditor(existing: $0) }
        .sheet(item: $addKind) { k in
            TransactionEditor(presetKind: k, presetAccountID: account.id)
        }
        .alert("Balansni to'g'rilash", isPresented: $showAdjust) {
            TextField("Haqiqiy balans", text: $adjustText).keyboardType(.decimalPad)
            Button("Saqlash") {
                if let v = parseAmount(adjustText) { FinanceEngine.setBalance(account, to: v, ctx: context) }
            }
            Button("Bekor", role: .cancel) {}
        } message: {
            Text("Kartadagi haqiqiy qoldiqni kiriting. Statistika o'zgarmaydi.")
        }
    }

    private func actionButton(_ title: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.headline)
                Text(title).font(.caption2.weight(.semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.glass)
        .tint(color)
    }
}

struct AccountEditor: View {
    var existing: Account? = nil
    /// Set by a screen that shows this account: it removes the account after closing itself.
    var onDelete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var name = ""
    @State private var kind: AccountKind = .card
    @State private var bank = ""
    @State private var last4 = ""
    @State private var currency = "UZS"
    @State private var balanceText = ""
    @State private var color = Palette.swatches[0]
    @State private var includeInTotal = true
    @State private var archived = false
    @State private var loaded = false
    @State private var confirmDelete = false

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AccountCardView(account: preview)
                        .frame(height: 150)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
                Section("Asosiy") {
                    Picker("Turi", selection: $kind) {
                        ForEach(AccountKind.allCases) { k in
                            Label(k.title, systemImage: k.icon).tag(k)
                        }
                    }
                    TextField("Nomi (masalan, Asosiy karta)", text: $name)
                    if kind == .card || kind == .savings {
                        TextField("Bank (masalan, Kapitalbank)", text: $bank)
                    }
                    if kind == .card {
                        TextField("Karta raqamining oxirgi 4 raqami", text: $last4)
                            .keyboardType(.numberPad)
                            .onChange(of: last4) { _, v in
                                let digits = String(v.filter(\.isNumber).prefix(4))
                                if digits != v { last4 = digits }
                            }
                    }
                }
                Section {
                    Picker("Valyuta", selection: $currency) {
                        ForEach(Currencies.all, id: \.self) { c in
                            Text("\(Currencies.flag(c)) \(c) — \(Currencies.name(c))").tag(c)
                        }
                    }
                    AmountField(title: "Balans", text: $balanceText, currency: currency)
                } header: {
                    Text(existing == nil ? "Boshlang'ich balans" : "Joriy balans")
                } footer: {
                    if kind == .card {
                        Text("Bank nomi (TBC, Uzum, Anorbank…) va oxirgi 4 raqam bank xabarlarini shu kartaga bog'lash uchun kerak.")
                    }
                }
                Section("Ko'rinish") {
                    ColorSwatchPicker(selection: $color)
                    Toggle("Umumiy balansga qo'shilsin", isOn: $includeInTotal)
                    if existing != nil {
                        Toggle("Arxivlangan", isOn: $archived)
                    }
                }
                if existing != nil {
                    Section {
                        Button("Hisobni o'chirish", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Hisob bilan bog'liq barcha operatsiyalar ham o'chiriladi.")
                    }
                }
            }
            .navigationTitle(existing == nil ? "Yangi hisob" : "Hisobni tahrirlash")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Bekor") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Saqlash") { save() }.disabled(!isValid)
                }
            }
            .confirmationDialog("Hisob o'chirilsinmi?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("O'chirish", role: .destructive) {
                    guard let existing else { return dismiss() }
                    if let onDelete {
                        onDelete()
                        dismiss()
                    } else {
                        let ctx = context
                        dismiss()
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(450))
                            FinanceEngine.deleteAccount(existing, ctx: ctx)
                        }
                    }
                }
            }
            .onAppear(perform: load)
        }
    }

    private var preview: Account {
        let a = Account(name: name.isEmpty ? "Yangi hisob" : name, kind: kind, bank: bank, cardLast4: last4,
                        currency: currency, balance: parseAmount(balanceText) ?? 0, colorHex: color)
        a.includeInTotal = includeInTotal
        return a
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let a = existing else { return }
        name = a.name
        kind = a.kind
        bank = a.bank
        last4 = a.cardLast4
        currency = a.currency
        balanceText = Money.editString(a.balance, a.currency)
        color = a.colorHex
        includeInTotal = a.includeInTotal
        archived = a.isArchived
    }

    private func save() {
        let balance = parseAmount(balanceText) ?? 0
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let a = existing {
            a.name = trimmed
            a.kind = kind
            a.bank = bank
            a.cardLast4 = kind == .card ? last4 : ""
            a.currency = currency
            a.balance = balance
            a.colorHex = color
            a.includeInTotal = includeInTotal
            a.isArchived = archived
        } else {
            let a = Account(name: trimmed, kind: kind, bank: bank, cardLast4: kind == .card ? last4 : "",
                            currency: currency, balance: balance, colorHex: color, sortOrder: accounts.count)
            a.includeInTotal = includeInTotal
            context.insert(a)
        }
        try? context.save()
        Haptics.success()
        dismiss()
    }
}

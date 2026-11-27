import SwiftUI
import SwiftData

struct TransactionEditor: View {
    var existing: FinTransaction? = nil
    var presetKind: TxKind = .expense
    var presetAccountID: UUID? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \FinCategory.sortOrder) private var categories: [FinCategory]

    @State private var kind: TxKind = .expense
    @State private var amountText = ""
    @State private var toAmountText = ""
    @State private var accountID: UUID?
    @State private var toAccountID: UUID?
    @State private var category = ""
    @State private var merchant = ""
    @State private var note = ""
    @State private var date = Date()
    @State private var loaded = false
    @State private var confirmDelete = false

    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }
    private var fromAccount: Account? { accounts.first { $0.id == accountID } }
    private var toAccount: Account? { accounts.first { $0.id == toAccountID } }
    private var currency: String { fromAccount?.currency ?? "UZS" }
    private var needsToAmount: Bool {
        kind == .transfer && toAccount != nil && toAccount?.currency != fromAccount?.currency
    }
    private var kindCategories: [FinCategory] { categories.filter { $0.kind == kind } }

    private var isValid: Bool {
        guard let a = parseAmount(amountText), a > 0, accountID != nil else { return false }
        if kind == .transfer {
            guard let to = toAccountID, to != accountID else { return false }
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Turi", selection: $kind) {
                        ForEach(TxKind.allCases) { k in
                            Text(k.title).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section("Summa") {
                    AmountField(title: "0", text: $amountText, currency: currency)
                }

                Section(kind == .transfer ? "Qayerdan" : "Hisob") {
                    accountPicker(selection: $accountID, exclude: nil)
                }

                if kind == .transfer {
                    Section("Qayerga") {
                        accountPicker(selection: $toAccountID, exclude: accountID)
                    }
                    if needsToAmount, let to = toAccount {
                        Section {
                            AmountField(title: "Tushadigan summa", text: $toAmountText, currency: to.currency)
                        } header: {
                            Text("Tushadigan summa (\(to.currency))")
                        } footer: {
                            Text("Bo'sh qoldirilsa, MB kursi bo'yicha hisoblanadi.")
                        }
                    }
                } else {
                    Section("Kategoriya") {
                        CategoryGrid(categories: kindCategories, selection: $category)
                    }
                }

                Section("Tafsilotlar") {
                    if kind != .transfer {
                        TextField(kind == .income ? "Kimdan / manba" : "Do'kon yoki xizmat", text: $merchant)
                    }
                    TextField("Izoh", text: $note, axis: .vertical)
                    DatePicker("Sana", selection: $date)
                }

                if let existing, existing.source != .manual {
                    Section("Manba") {
                        Label(existing.source.title, systemImage: existing.source.icon)
                        if !existing.rawText.isEmpty {
                            Text(existing.rawText).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if existing != nil {
                    Section {
                        Button("Operatsiyani o'chirish", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Yangi operatsiya" : "Tahrirlash")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Bekor") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Saqlash") { save() }
                        .disabled(!isValid)
                }
            }
            .confirmationDialog("O'chirilsinmi?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("O'chirish", role: .destructive) {
                    if let existing { FinanceEngine.delete(existing, ctx: context) }
                    dismiss()
                }
            } message: {
                Text("Hisob balansi ham mos ravishda qaytariladi.")
            }
            .onAppear(perform: load)
            .onChange(of: kind) { _, newKind in
                if !kindCategories.contains(where: { $0.name == category }) {
                    category = newKind == .income ? "Boshqa kirim" : (newKind == .expense ? "Boshqa xarajat" : "")
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func accountPicker(selection: Binding<UUID?>, exclude: UUID?) -> some View {
        if activeAccounts.isEmpty {
            Text("Avval “Hisoblar” bo'limida hisob qo'shing").foregroundStyle(.secondary)
        } else {
            Picker("Hisob", selection: selection) {
                Text("Tanlang").tag(UUID?.none)
                ForEach(activeAccounts.filter { $0.id != exclude }) { a in
                    Label("\(a.displayName) · \(Money.format(a.balance, a.currency))", systemImage: a.kind.icon)
                        .tag(UUID?.some(a.id))
                }
            }
            .pickerStyle(.navigationLink)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let t = existing {
            kind = t.kind
            amountText = Money.number(t.amount, decimals: Money.decimals(t.currency)).replacingOccurrences(of: " ", with: "")
            toAmountText = t.toAmount > 0 ? String(t.toAmount) : ""
            accountID = t.accountID
            toAccountID = t.toAccountID
            category = t.categoryName
            merchant = t.merchant
            note = t.note
            date = t.date
        } else {
            kind = presetKind
            accountID = presetAccountID ?? FinanceEngine.defaultAutomationAccount(context)?.id
            category = presetKind == .income ? "Boshqa kirim" : "Boshqa xarajat"
        }
    }

    private func save() {
        guard let amount = parseAmount(amountText), amount > 0 else { return }
        let toAmount = parseAmount(toAmountText) ?? 0
        let cat = kind == .transfer ? "" : (category.isEmpty ? FinanceEngine.guessCategory(text: merchant, kind: kind, ctx: context) : category)
        if let t = existing {
            if t.balanceApplied { FinanceEngine.applyEffect(of: t, sign: -1, ctx: context) }
            t.kind = kind
            t.amount = amount
            t.currency = currency
            t.accountID = accountID
            t.toAccountID = kind == .transfer ? toAccountID : nil
            t.toAmount = kind == .transfer ? toAmount : 0
            t.categoryName = cat
            t.merchant = kind == .transfer ? "" : merchant
            t.note = note
            t.date = date
            t.balanceApplied = true
            FinanceEngine.applyEffect(of: t, sign: 1, ctx: context)
            try? context.save()
        } else {
            FinanceEngine.addTransaction(kind: kind, amount: amount, currency: currency, accountID: accountID,
                                         toAccountID: kind == .transfer ? toAccountID : nil, toAmount: toAmount,
                                         category: cat, merchant: kind == .transfer ? "" : merchant, note: note,
                                         date: date, ctx: context)
        }
        Haptics.success()
        dismiss()
    }
}

struct CategoryGrid: View {
    let categories: [FinCategory]
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 12) {
            ForEach(categories) { c in
                Button {
                    selection = c.name
                } label: {
                    VStack(spacing: 6) {
                        IconBadge(icon: c.icon, color: Color(hex: c.colorHex), size: 42)
                            .overlay {
                                if selection == c.name {
                                    RoundedRectangle(cornerRadius: 14).stroke(Color.primary, lineWidth: 2.5)
                                        .padding(-3)
                                }
                            }
                        Text(c.name)
                            .font(.caption2)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(selection == c.name ? Color.primary : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }
}

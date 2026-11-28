import SwiftUI
import SwiftData

struct RecurringView: View {
    @Query(sort: \RecurringPayment.dayOfMonth) private var items: [RecurringPayment]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \FinCategory.sortOrder) private var categories: [FinCategory]
    @Environment(\.modelContext) private var context
    @Environment(RateStore.self) private var rates
    @AppStorage("baseCurrency") private var base = "UZS"
    @State private var showAdd = false
    @State private var editing: RecurringPayment?

    private var monthlyTotal: Double {
        items.filter(\.isActive).reduce(0) { $0 + rates.convert($1.amount, from: $1.currency, to: base) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                GlassCard(padding: 18, tint: Color(hex: "#06B6D4")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Har oy majburiy to'lovlar").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        AmountText(value: monthlyTotal, currency: base, font: .title.weight(.bold))
                        Text("Kommunal, internet, obunalar, ijara, kredit — to'lov kuni eslatma keladi.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if items.isEmpty {
                    GlassCard {
                        ContentUnavailableView("Doimiy to'lov yo'q", systemImage: "repeat.circle",
                                               description: Text("Masalan: internet, telefon, Spotify, ijara."))
                    }
                }
                ForEach(items) { r in
                    let cat = categories.first { $0.name == r.categoryName }
                    GlassCard(padding: 14) {
                        HStack(spacing: 12) {
                            IconBadge(icon: cat?.icon ?? "repeat", color: Color(hex: cat?.colorHex ?? "#06B6D4"), size: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.name).font(.headline).lineLimit(1)
                                Text(r.isPaidThisMonth ? "Bu oy to'langan ✓"
                                     : (r.isOverdue ? "Muddati o'tdi · \(r.nextDate.uzDate)"
                                        : "Har oyning \(r.dayOfMonth)-kuni · \(r.nextDate.uzDate)"))
                                    .font(.caption)
                                    .foregroundStyle(r.isPaidThisMonth ? Palette.income : (r.isOverdue && r.isActive ? Palette.expense : Color.secondary))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                AmountText(value: r.amount, currency: r.currency, font: .subheadline.weight(.bold))
                                if !r.isPaidThisMonth && r.isActive {
                                    Button("To'landi") {
                                        withAnimation { FinanceEngine.markPaid(r, ctx: context) }
                                    }
                                    .buttonStyle(.glassProminent)
                                    .controlSize(.small)
                                    .disabled(r.accountID == nil)
                                }
                            }
                        }
                    }
                    .opacity(r.isActive ? 1 : 0.5)
                    .onTapGesture { editing = r }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationTitle("Doimiy to'lovlar")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { RecurringEditor(existing: nil) }
        .sheet(item: $editing) { RecurringEditor(existing: $0) }
    }
}

struct RecurringEditor: View {
    let existing: RecurringPayment?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \FinCategory.sortOrder) private var categories: [FinCategory]
    @State private var name = ""
    @State private var amountText = ""
    @State private var accountID: UUID?
    @State private var category = "Obunalar"
    @State private var day = 1
    @State private var active = true
    @State private var reminder = true
    @State private var loaded = false

    private var currency: String { accounts.first { $0.id == accountID }?.currency ?? "UZS" }

    var body: some View {
        NavigationStack {
            Form {
                Section("To'lov") {
                    TextField("Nomi (masalan, Internet)", text: $name)
                    AmountField(title: "Summa", text: $amountText, currency: currency)
                    Stepper("Har oyning \(day)-kuni", value: $day, in: 1...28)
                }
                Section("Hisob") {
                    Picker("Qaysi hisobdan", selection: $accountID) {
                        Text("Tanlang").tag(UUID?.none)
                        ForEach(accounts.filter { !$0.isArchived }) { a in
                            Text(a.displayName).tag(UUID?.some(a.id))
                        }
                    }
                }
                Section("Kategoriya") {
                    CategoryGrid(categories: categories.filter { $0.kind == .expense }, selection: $category)
                }
                Section {
                    Toggle("Faol", isOn: $active)
                    Toggle("To'lov kuni eslatma", isOn: $reminder)
                }
                if let existing {
                    Section {
                        Button("O'chirish", role: .destructive) {
                            Notifier.cancel(["recurring-\(existing.id.uuidString)"])
                            let ctx = context
                            dismiss()
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(450))
                                ctx.delete(existing)
                                try? ctx.save()
                            }
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Yangi doimiy to'lov" : "Doimiy to'lov")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Bekor") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Saqlash", action: save)
                        .disabled(name.isEmpty || (parseAmount(amountText) ?? 0) <= 0)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let r = existing {
                    name = r.name
                    amountText = String(Int(r.amount))
                    accountID = r.accountID
                    category = r.categoryName
                    day = r.dayOfMonth
                    active = r.isActive
                    reminder = r.reminder
                } else {
                    accountID = FinanceEngine.defaultAutomationAccount(context)?.id
                }
            }
            .task { _ = await Notifier.requestAuthorization() }
        }
    }

    private func save() {
        guard let amount = parseAmount(amountText), amount > 0 else { return }
        let r: RecurringPayment
        if let existing {
            r = existing
        } else {
            r = RecurringPayment(name: name, amount: amount)
            context.insert(r)
        }
        r.name = name
        r.amount = amount
        r.currency = currency
        r.accountID = accountID
        r.categoryName = category
        r.dayOfMonth = day
        r.isActive = active
        r.reminder = reminder
        try? context.save()
        Notifier.scheduleRecurring(id: r.id, name: name, amountText: Money.format(amount, currency), day: day,
                                   enabled: active && reminder)
        dismiss()
    }
}

struct CategoriesView: View {
    @Query(sort: \FinCategory.sortOrder) private var categories: [FinCategory]
    @State private var kind: TxKind = .expense
    @State private var editing: FinCategory?
    @State private var showAdd = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("Turi", selection: $kind) {
                    Text("Chiqim").tag(TxKind.expense)
                    Text("Kirim").tag(TxKind.income)
                }
                .pickerStyle(.segmented)
                GlassCard(padding: 8) {
                    VStack(spacing: 0) {
                        ForEach(categories.filter { $0.kind == kind }) { c in
                            Button { editing = c } label: {
                                HStack(spacing: 12) {
                                    IconBadge(icon: c.icon, color: Color(hex: c.colorHex), size: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.name).font(.subheadline.weight(.semibold))
                                        if !c.keywords.isEmpty {
                                            Text(c.keywords).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                                .padding(8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text("Kalit so'zlar SMS va Apple Pay operatsiyalarini avtomatik kategoriyalash uchun ishlatiladi.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationTitle("Kategoriyalar")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { CategoryEditor(existing: $0, kind: $0.kind) }
        .sheet(isPresented: $showAdd) { CategoryEditor(existing: nil, kind: kind) }
    }
}

struct CategoryEditor: View {
    let existing: FinCategory?
    let kind: TxKind
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var categories: [FinCategory]
    @State private var name = ""
    @State private var icon = "tag.fill"
    @State private var color = "#7C3AED"
    @State private var keywords = ""
    @State private var loaded = false

    private let icons = ["tag.fill", "cart.fill", "fork.knife", "car.fill", "bus.fill", "fuelpump.fill", "house.fill",
                         "wifi", "phone.fill", "tshirt.fill", "cross.case.fill", "pills.fill", "book.fill",
                         "gamecontroller.fill", "film.fill", "music.note", "airplane", "gift.fill", "pawprint.fill",
                         "figure.run", "dumbbell.fill", "sofa.fill", "hammer.fill", "briefcase.fill", "star.fill",
                         "creditcard.fill", "banknote.fill", "cup.and.saucer.fill", "bag.fill", "heart.fill"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        IconBadge(icon: icon, color: Color(hex: color), size: 64)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Nomi") {
                    TextField("Kategoriya nomi", text: $name)
                }
                Section("Belgi") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(icons, id: \.self) { i in
                            Image(systemName: i)
                                .font(.title3)
                                .frame(width: 40, height: 40)
                                .background(icon == i ? Color(hex: color).opacity(0.35) : Color.clear, in: .circle)
                                .onTapGesture { icon = i }
                        }
                    }
                    ColorSwatchPicker(selection: $color)
                }
                Section {
                    TextField("korzinka, makro, havas", text: $keywords, axis: .vertical)
                } header: {
                    Text("Kalit so'zlar")
                } footer: {
                    Text("Vergul bilan ajrating. Do'kon nomida shu so'z bo'lsa, operatsiya avtomatik shu kategoriyaga tushadi.")
                }
                if let existing, !existing.isSystem {
                    Section {
                        Button("Kategoriyani o'chirish", role: .destructive) {
                            let ctx = context
                            dismiss()
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(450))
                                ctx.delete(existing)
                                try? ctx.save()
                            }
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Yangi kategoriya" : "Kategoriya")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Bekor") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Saqlash", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let c = existing {
                    name = c.name
                    icon = c.icon
                    color = c.colorHex
                    keywords = c.keywords
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let c = existing {
            let old = c.name
            c.name = trimmed
            c.icon = icon
            c.colorHex = color
            c.keywords = keywords
            if old != trimmed {
                let txs = (try? context.fetch(FetchDescriptor<FinTransaction>())) ?? []
                for t in txs where t.categoryName == old { t.categoryName = trimmed }
                let budgets = (try? context.fetch(FetchDescriptor<Budget>())) ?? []
                for b in budgets where b.categoryName == old { b.categoryName = trimmed }
            }
        } else {
            context.insert(FinCategory(name: trimmed, icon: icon, colorHex: color, kind: kind,
                                       keywords: keywords, sortOrder: categories.count + 100))
        }
        try? context.save()
        dismiss()
    }
}

struct RatesView: View {
    @Environment(RateStore.self) private var rates
    @AppStorage("baseCurrency") private var base = "UZS"
    @State private var converterAmount = "100"
    @State private var from = "USD"

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("O'zbekiston Markaziy banki kursi").font(.headline)
                            Spacer()
                            if rates.isLoading { ProgressView() }
                        }
                        ForEach(Currencies.all.filter { $0 != "UZS" }, id: \.self) { c in
                            HStack {
                                Text("\(Currencies.flag(c))  1 \(c)").font(.title3.weight(.semibold))
                                Spacer()
                                Text(Money.format(rates.rate(c), "UZS")).font(.title3.monospacedDigit())
                            }
                        }
                        Text(rates.cbuDate.isEmpty ? "Standart qiymatlar — yangilang" : "Sana: \(rates.cbuDate)")
                            .font(.caption).foregroundStyle(.secondary)
                        if let e = rates.lastError {
                            Text(e).font(.caption).foregroundStyle(Palette.expense)
                        }
                    }
                }
                Button {
                    Task { await rates.refresh() }
                } label: {
                    Label("Kurslarni yangilash", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Konvertor").font(.headline)
                        HStack {
                            TextField("Summa", text: $converterAmount).keyboardType(.decimalPad).font(.title3)
                            Picker("", selection: $from) {
                                ForEach(Currencies.all, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                        }
                        ForEach(Currencies.all.filter { $0 != from }, id: \.self) { c in
                            HStack {
                                Text("\(Currencies.flag(c)) \(c)")
                                Spacer()
                                Text(Money.format(rates.convert(parseAmount(converterAmount) ?? 0, from: from, to: c), c))
                                    .monospacedDigit()
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationTitle("Valyuta kurslari")
        .task { await rates.refreshIfStale() }
    }
}

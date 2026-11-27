import SwiftUI
import SwiftData

struct BudgetRow: View {
    let budget: Budget
    let spent: Double
    let category: FinCategory?
    let base: String

    private var ratio: Double { budget.limit > 0 ? spent / budget.limit : 0 }
    private var color: Color { ratio >= 1 ? Palette.expense : (ratio >= 0.8 ? Palette.warning : Palette.income) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                IconBadge(icon: category?.icon ?? "tag.fill", color: Color(hex: category?.colorHex ?? "#94A3B8"), size: 32)
                Text(budget.categoryName).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                AmountText(value: spent, currency: base, font: .caption.weight(.bold), color: color)
                Text("/").font(.caption).foregroundStyle(.secondary)
                AmountText(value: budget.limit, currency: base, font: .caption)
            }
            ProgressCapsule(progress: ratio, color: color, height: 7)
            if ratio >= 1 {
                HStack(spacing: 4) {
                    Text("Limitdan oshdi:")
                    AmountText(value: spent - budget.limit, currency: base, font: .caption2.weight(.semibold), color: Palette.expense)
                }
                .font(.caption2)
                .foregroundStyle(Palette.expense)
            } else {
                HStack(spacing: 4) {
                    Text("Qoldi:")
                    AmountText(value: budget.limit - spent, currency: base, font: .caption2.weight(.semibold))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }
}

struct BudgetsView: View {
    @Query(sort: \Budget.createdAt) private var budgets: [Budget]
    @Query(sort: \FinTransaction.date, order: .reverse) private var transactions: [FinTransaction]
    @Query(sort: \FinCategory.sortOrder) private var categories: [FinCategory]
    @Environment(\.modelContext) private var context
    @Environment(RateStore.self) private var rates
    @AppStorage("baseCurrency") private var base = "UZS"
    @State private var showAdd = false
    @State private var editing: Budget?

    private var totalLimit: Double { budgets.reduce(0) { $0 + $1.limit } }
    private var totalSpent: Double {
        budgets.reduce(0) { $0 + FinanceEngine.spent(category: $1.categoryName, transactions: transactions, rates: rates, base: base) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard(padding: 18, tint: Palette.warning) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(Date().uzMonthYear) byudjeti").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            AmountText(value: totalSpent, currency: base, font: .title.weight(.bold))
                            Text("/").foregroundStyle(.secondary)
                            AmountText(value: totalLimit, currency: base, font: .headline)
                        }
                        ProgressCapsule(progress: totalLimit > 0 ? totalSpent / totalLimit : 0,
                                        color: totalSpent > totalLimit ? Palette.expense : Palette.warning)
                    }
                }
                if budgets.isEmpty {
                    GlassCard {
                        ContentUnavailableView("Byudjet yo'q", systemImage: "gauge.with.dots.needle.33percent",
                                               description: Text("Kategoriyalar uchun oylik limit belgilang. 80% va 100% ga yetganda bildirishnoma keladi."))
                    }
                } else {
                    GlassCard {
                        VStack(spacing: 18) {
                            ForEach(budgets) { b in
                                BudgetRow(budget: b,
                                          spent: FinanceEngine.spent(category: b.categoryName, transactions: transactions, rates: rates, base: base),
                                          category: categories.first { $0.name == b.categoryName }, base: base)
                                    .contentShape(Rectangle())
                                    .onTapGesture { editing = b }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            context.delete(b)
                                            try? context.save()
                                        } label: { Label("O'chirish", systemImage: "trash") }
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
        .navigationTitle("Byudjetlar")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { BudgetEditor(existing: nil) }
        .sheet(item: $editing) { BudgetEditor(existing: $0) }
        .task { _ = await Notifier.requestAuthorization() }
    }
}

struct BudgetEditor: View {
    let existing: Budget?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \FinCategory.sortOrder) private var categories: [FinCategory]
    @Query private var budgets: [Budget]
    @AppStorage("baseCurrency") private var base = "UZS"
    @State private var category = ""
    @State private var limitText = ""
    @State private var loaded = false

    private var available: [FinCategory] {
        categories.filter { c in
            c.kind == .expense && (c.name == existing?.categoryName || !budgets.contains { $0.categoryName == c.name })
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Oylik limit") {
                    AmountField(title: "0", text: $limitText, currency: base)
                }
                Section("Kategoriya") {
                    CategoryGrid(categories: available, selection: $category)
                }
                if let existing {
                    Section {
                        Button("Byudjetni o'chirish", role: .destructive) {
                            context.delete(existing)
                            try? context.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Yangi byudjet" : "Byudjet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Bekor") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Saqlash") {
                        guard let limit = parseAmount(limitText), limit > 0, !category.isEmpty else { return }
                        if let existing {
                            existing.categoryName = category
                            existing.limit = limit
                        } else {
                            context.insert(Budget(categoryName: category, limit: limit))
                        }
                        try? context.save()
                        dismiss()
                    }
                    .disabled(category.isEmpty || (parseAmount(limitText) ?? 0) <= 0)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let existing {
                    category = existing.categoryName
                    limitText = String(Int(existing.limit))
                }
            }
        }
    }
}

struct GoalsView: View {
    @Query(sort: \Goal.createdAt) private var goals: [Goal]
    @State private var showAdd = false
    @State private var contributing: Goal?
    @State private var editing: Goal?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if goals.isEmpty {
                    GlassCard {
                        ContentUnavailableView("Maqsad yo'q", systemImage: "target",
                                               description: Text("Masalan: yangi noutbuk, sayohat yoki zaxira jamg'arma."))
                    }
                }
                ForEach(goals) { g in
                    GoalCard(goal: g, onContribute: { contributing = g }, onEdit: { editing = g })
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationTitle("Maqsadlar")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { GoalEditor(existing: nil) }
        .sheet(item: $editing) { GoalEditor(existing: $0) }
        .sheet(item: $contributing) { GoalContributionSheet(goal: $0) }
    }
}

struct GoalCard: View {
    let goal: Goal
    let onContribute: () -> Void
    let onEdit: () -> Void

    private var monthlyNeed: Double? {
        guard let deadline = goal.deadline, !goal.isCompleted else { return nil }
        let months = max(1, Calendar.current.dateComponents([.month], from: Date(), to: deadline).month ?? 1)
        return max(0, goal.target - goal.saved) / Double(months)
    }

    var body: some View {
        let color = Color(hex: goal.colorHex)
        GlassCard(padding: 16, tint: color) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    ZStack {
                        RingProgress(progress: goal.progress, color: color, lineWidth: 7)
                        Image(systemName: goal.icon).font(.title3).foregroundStyle(color)
                    }
                    .frame(width: 58, height: 58)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(goal.name).font(.headline)
                        HStack(spacing: 4) {
                            AmountText(value: goal.saved, currency: goal.currency, font: .subheadline.weight(.bold))
                            Text("/").foregroundStyle(.secondary)
                            AmountText(value: goal.target, currency: goal.currency, font: .subheadline)
                        }
                        if let deadline = goal.deadline {
                            Text("Muddat: \(deadline.uzDate)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text("\(Int((goal.progress * 100).rounded()))%").font(.title3.bold().monospacedDigit())
                }
                if let need = monthlyNeed, need > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar.badge.clock")
                        Text("Oyiga kerak:")
                        AmountText(value: need, currency: goal.currency, font: .caption.weight(.semibold))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button(action: onContribute) {
                            Label(goal.isCompleted ? "Bajarildi" : "Pul qo'shish", systemImage: goal.isCompleted ? "checkmark.seal.fill" : "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(color)
                        .disabled(goal.isCompleted)
                        Button(action: onEdit) {
                            Image(systemName: "pencil").frame(width: 28)
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
        }
    }
}

struct GoalEditor: View {
    let existing: Goal?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var targetText = ""
    @State private var savedText = ""
    @State private var currency = "UZS"
    @State private var hasDeadline = false
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @State private var icon = "target"
    @State private var color = "#8B5CF6"
    @State private var loaded = false

    private let icons = ["target", "laptopcomputer", "airplane", "car.fill", "house.fill", "graduationcap.fill",
                         "iphone", "gift.fill", "heart.fill", "shield.fill", "bicycle", "camera.fill"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Maqsad") {
                    TextField("Nomi", text: $name)
                    AmountField(title: "Kerakli summa", text: $targetText, currency: currency)
                    AmountField(title: "Hozir yig'ilgan", text: $savedText, currency: currency)
                    Picker("Valyuta", selection: $currency) {
                        ForEach(Currencies.all, id: \.self) { Text("\(Currencies.flag($0)) \($0)").tag($0) }
                    }
                }
                Section("Muddat") {
                    Toggle("Muddat belgilash", isOn: $hasDeadline.animation())
                    if hasDeadline { DatePicker("Sana", selection: $deadline, displayedComponents: .date) }
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
                if let existing {
                    Section {
                        Button("Maqsadni o'chirish", role: .destructive) {
                            context.delete(existing)
                            try? context.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Yangi maqsad" : "Maqsad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Bekor") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Saqlash", action: save)
                        .disabled(name.isEmpty || (parseAmount(targetText) ?? 0) <= 0)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                currency = UserDefaults.standard.string(forKey: "baseCurrency") ?? "UZS"
                if let g = existing {
                    name = g.name
                    targetText = String(Int(g.target))
                    savedText = String(Int(g.saved))
                    currency = g.currency
                    hasDeadline = g.deadline != nil
                    deadline = g.deadline ?? deadline
                    icon = g.icon
                    color = g.colorHex
                }
            }
        }
    }

    private func save() {
        guard let target = parseAmount(targetText), target > 0 else { return }
        let saved = parseAmount(savedText) ?? 0
        if let g = existing {
            g.name = name
            g.target = target
            g.saved = saved
            g.currency = currency
            g.deadline = hasDeadline ? deadline : nil
            g.icon = icon
            g.colorHex = color
        } else {
            let g = Goal(name: name, icon: icon, colorHex: color, target: target, currency: currency,
                         deadline: hasDeadline ? deadline : nil)
            g.saved = saved
            context.insert(g)
        }
        try? context.save()
        dismiss()
    }
}

struct GoalContributionSheet: View {
    let goal: Goal
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @State private var amountText = ""
    @State private var accountID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section("Summa") {
                    AmountField(title: "0", text: $amountText, currency: goal.currency)
                }
                Section {
                    Picker("Hisobdan", selection: $accountID) {
                        Text("Hisobga ta'sir qilmasin").tag(UUID?.none)
                        ForEach(accounts.filter { !$0.isArchived }) { a in
                            Text(a.displayName).tag(UUID?.some(a.id))
                        }
                    }
                } footer: {
                    Text("Hisob tanlansa, undan “Jamg'arma” chiqimi yoziladi.")
                }
            }
            .navigationTitle(goal.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Bekor") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Qo'shish") {
                        if let a = parseAmount(amountText), a > 0 {
                            FinanceEngine.contribute(to: goal, amount: a, accountID: accountID, ctx: context)
                        }
                        dismiss()
                    }
                    .disabled((parseAmount(amountText) ?? 0) <= 0)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

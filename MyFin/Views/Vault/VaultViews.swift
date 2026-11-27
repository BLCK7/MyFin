import SwiftUI
import SwiftData
import PhotosUI

struct DecryptedVaultItem: Identifiable {
    let id: UUID
    let kind: VaultKind
    let payload: VaultPayload
    let updatedAt: Date
}

enum VaultCache {
    static func decrypt(_ inputs: [(UUID, String, Data, Date)]) async -> [DecryptedVaultItem] {
        await Task.detached(priority: .userInitiated) {
            inputs.compactMap { id, kind, data, updated in
                guard let p = try? VaultCrypto.open(data) else { return nil }
                return DecryptedVaultItem(id: id, kind: VaultKind(rawValue: kind) ?? .custom, payload: p, updatedAt: updated)
            }
        }.value
    }
}

enum VaultText {
    static func digits(_ s: String) -> String { s.filter(\.isNumber) }

    static func isCardNumber(_ f: VaultField) -> Bool { f.label.hasPrefix("Karta raqami") }

    static func grouped(_ v: String) -> String {
        let d = Array(digits(v))
        guard d.count >= 12 else { return v }
        return stride(from: 0, to: d.count, by: 4).map { String(d[$0..<min($0 + 4, d.count)]) }.joined(separator: " ")
    }

    /// Value that goes to the clipboard: card numbers without spaces, everything else as typed.
    static func copyValue(_ f: VaultField) -> String {
        isCardNumber(f) ? digits(f.value) : f.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func masked(_ f: VaultField) -> String {
        if isCardNumber(f) { return "•••• " + String(digits(f.value).suffix(4)) }
        let v = f.value
        if v.count <= 4 { return String(repeating: "•", count: max(v.count, 4)) }
        return String(repeating: "•", count: min(v.count - 2, 8)) + String(v.suffix(2))
    }

    static func allText(_ item: DecryptedVaultItem) -> String {
        var lines = [item.payload.title.isEmpty ? item.kind.title : item.payload.title]
        for f in item.payload.fields where !f.value.isEmpty {
            lines.append("\(f.label): \(isCardNumber(f) ? grouped(f.value) : f.value)")
        }
        if let e = item.payload.expiry { lines.append("Amal qilish muddati: \(e.uzDate)") }
        if !item.payload.notes.isEmpty { lines.append(item.payload.notes) }
        return lines.joined(separator: "\n")
    }

    /// The fields people copy most often, shown as one-tap chips in the list.
    static func quickFields(_ item: DecryptedVaultItem) -> [VaultField] {
        let filled = item.payload.fields.filter { !$0.value.isEmpty }
        let wanted: [String]
        switch item.kind {
        case .bankCard: wanted = ["Karta raqami", "Amal qilish muddati", "Hisob raqami"]
        case .passport, .idCard: wanted = ["Seriya va raqam", "JShShIR", "F.I.Sh."]
        case .license: wanted = ["Guvohnoma raqami", "Amal qilish muddati"]
        case .custom: return Array(filled.prefix(2))
        }
        let picked = wanted.compactMap { w in filled.first { $0.label.hasPrefix(w) } }
        return Array((picked.isEmpty ? filled : picked).prefix(3))
    }

    static func shortLabel(_ f: VaultField) -> String {
        if f.label.hasPrefix("Karta raqami") { return "Karta" }
        if f.label.hasPrefix("Amal qilish muddati") { return "Muddat" }
        if f.label.hasPrefix("Seriya va raqam") { return "Seriya" }
        if f.label.hasPrefix("JShShIR") { return "JShShIR" }
        if f.label.hasPrefix("Hisob raqami") { return "IBAN" }
        if f.label.hasPrefix("Guvohnoma raqami") { return "Raqam" }
        return f.label
    }
}

struct VaultView: View {
    @Query(sort: \VaultItem.sortOrder) private var items: [VaultItem]
    @Environment(VaultSession.self) private var session
    @AppStorage("faceIDEnabled") private var faceIDEnabled = false
    @AppStorage("vaultShowValues") private var showValues = false
    @AppStorage("clipboardSeconds") private var clipboardSeconds = 60
    @AppStorage("vaultTimeout") private var vaultTimeout = 180
    @State private var decrypted: [DecryptedVaultItem] = []
    @State private var loading = false
    @State private var showPin = false
    @State private var showEditor = false
    @State private var newKind: VaultKind = .passport
    @State private var search = ""
    @State private var copiedID: UUID?

    private var signature: String {
        items.map { "\($0.id.uuidString)\($0.updatedAt.timeIntervalSince1970)" }.joined()
    }

    private var filtered: [DecryptedVaultItem] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return decrypted }
        return decrypted.filter { d in
            d.payload.title.lowercased().contains(q) || d.kind.title.lowercased().contains(q)
                || d.payload.fields.contains { $0.value.lowercased().contains(q) || $0.label.lowercased().contains(q) }
        }
    }

    var body: some View {
        Group {
            if session.isUnlocked {
                unlockedList
            } else {
                gate
            }
        }
        .screenBackground()
        .navigationTitle("Shaxsiy seyf")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.isUnlocked {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(VaultKind.allCases) { k in
                            Button {
                                newKind = k
                                showEditor = true
                            } label: { Label(k.title, systemImage: k.icon) }
                        }
                    } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Qiymatlarni ochiq ko'rsatish", isOn: $showValues)
                        Picker("Nusxa buferda turadi", selection: $clipboardSeconds) {
                            Text("1 daqiqa").tag(60)
                            Text("5 daqiqa").tag(300)
                            Text("15 daqiqa").tag(900)
                            Text("O'chirilmasin").tag(0)
                        }
                        Picker("Seyf ochiq turadi", selection: $vaultTimeout) {
                            Text("1 daqiqa").tag(60)
                            Text("3 daqiqa").tag(180)
                            Text("10 daqiqa").tag(600)
                        }
                        Button { withAnimation { session.lock() } } label: { Label("Seyfni yopish", systemImage: "lock.fill") }
                    } label: { Image(systemName: "gearshape") }
                }
            }
        }
        .sheet(isPresented: $showEditor) { VaultEditor(kind: newKind, existing: nil) }
        .fullScreenCover(isPresented: $showPin) {
            PinVerifySheet(title: "Seyfni ochish") { ok in
                showPin = false
                if ok { withAnimation(.smooth) { session.unlock() } }
            }
        }
        .task {
            if !session.isUnlocked && faceIDEnabled { await unlockWithBiometrics() }
        }
        .task(id: "\(session.isUnlocked)\(signature)") {
            guard session.isUnlocked else { decrypted = []; return }
            loading = decrypted.isEmpty && !items.isEmpty
            let inputs = items.map { ($0.id, $0.kindRaw, $0.payload, $0.updatedAt) }
            let result = await VaultCache.decrypt(inputs)
            withAnimation(.smooth(duration: 0.25)) {
                decrypted = result
                loading = false
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if !session.isUnlocked && session.unlockedUntil != nil { session.lock() }
            }
        }
    }

    private var gate: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "lock.doc.fill")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 110, height: 110)
                .glassEffect(.regular, in: .circle)
            Text("Shaxsiy seyf").font(.title2.bold())
            Text("Pasport, ID karta, bank kartalari va boshqa hujjatlar AES-256 bilan shifrlangan holda faqat shu iPhone'da saqlanadi.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer()
            VStack(spacing: 12) {
                if faceIDEnabled && Biometrics.available {
                    Button {
                        Task { await unlockWithBiometrics() }
                    } label: {
                        Label("\(Biometrics.name) bilan ochish", systemImage: Biometrics.icon).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                }
                Button {
                    showPin = true
                } label: {
                    Label("PIN-kod bilan ochish", systemImage: "circle.grid.3x3.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
            .padding(.horizontal, 30)
            .padding(.bottom, 40)
        }
    }

    private var unlockedList: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if loading {
                    ProgressView("Ochilmoqda…").padding(.top, 40)
                } else if decrypted.isEmpty {
                    GlassCard {
                        ContentUnavailableView("Seyf bo'sh", systemImage: "tray",
                                               description: Text("Yuqoridagi + tugmasi orqali pasport, karta yoki boshqa hujjat qo'shing."))
                    }
                } else if filtered.isEmpty {
                    GlassCard { ContentUnavailableView.search(text: search) }
                }
                ForEach(filtered) { d in
                    VaultCardRow(item: d, showValues: showValues, copiedID: $copiedID) {
                        session.touch()
                    }
                }
                if !loading && items.count > decrypted.count {
                    Text("\(items.count - decrypted.count) ta yozuvni ochib bo'lmadi (kalit topilmadi).")
                        .font(.caption).foregroundStyle(Palette.expense)
                }
                Text("Nusxa olish uchun qiymatni bosing. Karta raqami bo'shliqsiz nusxalanadi.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .searchable(text: $search, prompt: "Hujjat yoki raqam bo'yicha qidirish")
        .simultaneousGesture(TapGesture().onEnded { session.touch() })
    }

    private func unlockWithBiometrics() async {
        if await Biometrics.authenticateBiometric(reason: "Shaxsiy seyfni ochish") {
            withAnimation(.smooth) { session.unlock() }
        }
    }
}

struct VaultCardRow: View {
    let item: DecryptedVaultItem
    let showValues: Bool
    @Binding var copiedID: UUID?
    let onInteract: () -> Void

    private var expired: Bool { (item.payload.expiry ?? .distantFuture) < Date() }

    var body: some View {
        GlassCard(padding: 14, tint: Color(hex: item.kind.colorHex)) {
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink {
                    VaultDetailView(item: item)
                } label: {
                    HStack(spacing: 14) {
                        IconBadge(icon: item.kind.icon, color: Color(hex: item.kind.colorHex), size: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.payload.title.isEmpty ? item.kind.title : item.payload.title)
                                .font(.headline)
                                .lineLimit(1)
                            Group {
                                if let exp = item.payload.expiry {
                                    Text(expired ? "Muddati o'tgan: \(exp.uzDate)" : "Amal qiladi: \(exp.uzDate)")
                                } else {
                                    Text(item.kind.title)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(expired ? Palette.expense : Color.secondary)
                        }
                        Spacer()
                        if !item.payload.images.isEmpty {
                            Label("\(item.payload.images.count)", systemImage: "photo")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                let quick = VaultText.quickFields(item)
                if !quick.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(quick) { f in
                            copyChip(f)
                        }
                    }
                }
            }
        }
    }

    private func copyChip(_ f: VaultField) -> some View {
        let copied = copiedID == f.id
        return Button {
            SecureClipboard.copy(VaultText.copyValue(f))
            onInteract()
            withAnimation(.snappy) { copiedID = f.id }
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                if copiedID == f.id { withAnimation(.snappy) { copiedID = nil } }
            }
        } label: {
            HStack(spacing: 10) {
                Text(VaultText.shortLabel(f))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .leading)
                Text(showValues || !f.secret
                     ? (VaultText.isCardNumber(f) ? VaultText.grouped(f.value) : f.value)
                     : VaultText.masked(f))
                    .font(.subheadline.monospaced().weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .foregroundStyle(copied ? Palette.income : Palette.accent)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.primary.opacity(0.07), in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

struct VaultDetailView: View {
    let item: DecryptedVaultItem
    @Query private var items: [VaultItem]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(VaultSession.self) private var session
    @AppStorage("vaultShowValues") private var showValues = false
    @State private var revealed: Set<UUID> = []
    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var zoom: ImageBox?
    @State private var copiedID: UUID?
    @State private var copiedAll = false
    @State private var current: DecryptedVaultItem?

    private var stored: VaultItem? { items.first { $0.id == item.id } }
    private var cur: DecryptedVaultItem { current ?? item }
    private var kind: VaultKind { cur.kind }
    private var p: VaultPayload { cur.payload }
    private var filled: [VaultField] { p.fields.filter { !$0.value.isEmpty } }

    var body: some View {
        Group {
            if !session.isUnlocked {
                ContentUnavailableView("Seyf yopildi", systemImage: "lock.fill",
                                       description: Text("Xavfsizlik uchun seyf avtomatik yopildi. Orqaga qayting va qayta oching."))
            } else {
                content
            }
        }
        .screenBackground()
        .navigationTitle(p.title.isEmpty ? kind.title : p.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showEdit = true } label: { Label("Tahrirlash", systemImage: "pencil") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("O'chirish", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let stored { VaultEditor(kind: kind, existing: stored) }
        }
        .task(id: stored?.updatedAt) {
            guard let s = stored, s.updatedAt != cur.updatedAt else { return }
            let fresh = await VaultCache.decrypt([(s.id, s.kindRaw, s.payload, s.updatedAt)])
            if let f = fresh.first { current = f }
        }
        .sheet(item: $zoom) { z in
            ZoomImageView(data: z.data)
        }
        .confirmationDialog("Yozuv butunlay o'chirilsinmi?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("O'chirish", role: .destructive) {
                if let stored {
                    Notifier.cancel(["vault-\(stored.id.uuidString)-30", "vault-\(stored.id.uuidString)-7"])
                    context.delete(stored)
                    try? context.save()
                }
                dismiss()
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 14) {
                GlassCard(padding: 18, tint: Color(hex: kind.colorHex)) {
                    HStack(spacing: 14) {
                        IconBadge(icon: kind.icon, color: Color(hex: kind.colorHex), size: 54)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.title.isEmpty ? kind.title : p.title).font(.title3.bold())
                            Text(kind.title).font(.caption).foregroundStyle(.secondary)
                            if let exp = p.expiry {
                                Label(exp < Date() ? "Muddati o'tgan: \(exp.uzDate)" : "Amal qiladi: \(exp.uzDate)",
                                      systemImage: "calendar")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(exp < Date() ? Palette.expense : Palette.income)
                            }
                        }
                    }
                }

                Button {
                    SecureClipboard.copy(VaultText.allText(cur))
                    session.touch()
                    withAnimation(.snappy) { copiedAll = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.6))
                        withAnimation(.snappy) { copiedAll = false }
                    }
                } label: {
                    Label(copiedAll ? "Nusxalandi" : "Hammasini nusxalash",
                          systemImage: copiedAll ? "checkmark.circle.fill" : "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                GlassCard(padding: 6) {
                    VStack(spacing: 0) {
                        ForEach(filled) { f in
                            fieldRow(f)
                            if f.id != filled.last?.id {
                                Divider().opacity(0.35).padding(.leading, 12)
                            }
                        }
                    }
                }

                if !p.images.isEmpty {
                    GlassCard(padding: 10) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(Array(p.images.enumerated()), id: \.offset) { _, data in
                                ThumbnailView(data: data)
                                    .frame(height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .onTapGesture { zoom = ImageBox(data: data) }
                            }
                        }
                    }
                }

                if !p.notes.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Izoh").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(p.notes).font(.subheadline)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .simultaneousGesture(TapGesture().onEnded { session.touch() })
    }

    private func display(_ f: VaultField) -> String {
        if showValues || !f.secret || revealed.contains(f.id) {
            return VaultText.isCardNumber(f) ? VaultText.grouped(f.value) : f.value
        }
        return VaultText.masked(f)
    }

    private func fieldRow(_ f: VaultField) -> some View {
        let copied = copiedID == f.id
        return HStack(spacing: 10) {
            Button {
                SecureClipboard.copy(VaultText.copyValue(f))
                session.touch()
                withAnimation(.snappy) { copiedID = f.id }
                Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    if copiedID == f.id { withAnimation(.snappy) { copiedID = nil } }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(f.label).font(.caption).foregroundStyle(.secondary)
                        Text(display(f))
                            .font(.body.monospaced().weight(.semibold))
                            .contentTransition(.interpolate)
                    }
                    Spacer()
                    Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                        .foregroundStyle(copied ? Palette.income : Palette.accent)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 30, height: 30)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if f.secret && !showValues {
                Button {
                    withAnimation(.snappy) {
                        if revealed.contains(f.id) { revealed.remove(f.id) } else { revealed.insert(f.id) }
                    }
                    session.touch()
                } label: {
                    Image(systemName: revealed.contains(f.id) ? "eye.slash" : "eye")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
    }
}

struct ThumbnailView: View {
    let data: Data
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.primary.opacity(0.08)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ProgressView()
            }
        }
        .task {
            let d = data
            image = await Task.detached(priority: .userInitiated) {
                UIImage(data: d)?.preparingThumbnail(of: CGSize(width: 400, height: 400))
            }.value
        }
    }
}

struct ImageBox: Identifiable {
    let id = UUID()
    let data: Data
}

struct ZoomImageView: View {
    let data: Data
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            if let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(MagnifyGesture().onChanged { scale = max(1, $0.magnification) }.onEnded { _ in
                        withAnimation(.spring) { scale = 1 }
                    })
                    .frame(maxHeight: .infinity)
                HStack {
                    ShareLink(item: Image(uiImage: ui), preview: SharePreview("Hujjat rasmi", image: Image(uiImage: ui))) {
                        Image(systemName: "square.and.arrow.up").font(.headline).frame(width: 36, height: 36)
                    }
                    .buttonStyle(.glass)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.headline).frame(width: 36, height: 36)
                    }
                    .buttonStyle(.glass)
                }
                .padding()
            }
        }
    }
}

struct VaultEditor: View {
    let kind: VaultKind
    let existing: VaultItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var items: [VaultItem]
    @State private var title = ""
    @State private var fields: [VaultField] = []
    @State private var notes = ""
    @State private var images: [Data] = []
    @State private var hasExpiry = false
    @State private var expiry = Calendar.current.date(byAdding: .year, value: 5, to: Date()) ?? Date()
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nomi (masalan, Mening pasportim)", text: $title)
                } header: {
                    Label(kind.title, systemImage: kind.icon)
                }
                Section("Ma'lumotlar") {
                    ForEach($fields) { $f in
                        VStack(alignment: .leading, spacing: 4) {
                            if kind == .custom {
                                TextField("Maydon nomi", text: $f.label).font(.caption)
                            } else {
                                Text(f.label).font(.caption).foregroundStyle(.secondary)
                            }
                            TextField(f.label, text: $f.value)
                                .keyboardType(f.keyboard == "number" ? .numberPad : .default)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                            Toggle("Yashirin ko'rsatish", isOn: $f.secret).font(.caption2)
                        }
                    }
                    .onDelete { fields.remove(atOffsets: $0) }
                    Button {
                        fields.append(VaultField(label: kind == .custom ? "Maydon" : "Qo'shimcha", value: ""))
                    } label: {
                        Label("Maydon qo'shish", systemImage: "plus")
                    }
                }
                if kind == .bankCard {
                    Section {
                        Label("CVV/CVC va karta PIN-kodi ataylab saqlanmaydi: telefon yoki zaxira nusxa qo'lga tushsa, ular bilan kartadan internetda to'lov qilish mumkin bo'ladi.",
                              systemImage: "exclamationmark.shield.fill")
                            .font(.caption)
                            .foregroundStyle(Palette.warning)
                    }
                }
                Section {
                    Toggle("Amal qilish muddati", isOn: $hasExpiry.animation())
                    if hasExpiry {
                        DatePicker("Tugash sanasi", selection: $expiry, displayedComponents: .date)
                    }
                } footer: {
                    Text("Muddat tugashidan 30 va 7 kun oldin eslatma keladi.")
                }
                Section("Rasmlar") {
                    if !images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(Array(images.enumerated()), id: \.offset) { idx, data in
                                    ThumbnailView(data: data)
                                        .frame(width: 90, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(alignment: .topTrailing) {
                                            Button { images.remove(at: idx) } label: {
                                                Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.6))
                                            }
                                            .buttonStyle(.plain)
                                            .padding(2)
                                        }
                                }
                            }
                        }
                    }
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                        Label("Galereyadan qo'shish", systemImage: "photo.on.rectangle")
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showCamera = true } label: { Label("Suratga olish", systemImage: "camera") }
                    }
                }
                Section("Izoh") {
                    TextField("Izoh", text: $notes, axis: .vertical)
                }
                if let error {
                    Text(error).foregroundStyle(Palette.expense)
                }
            }
            .navigationTitle(existing == nil ? "Yangi yozuv" : "Tahrirlash")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Bekor") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Saqlash", action: save) }
            }
            .onChange(of: pickerItems) { _, newItems in
                Task {
                    for it in newItems {
                        if let raw = try? await it.loadTransferable(type: Data.self), let jpg = ImageTools.compress(raw) {
                            images.append(jpg)
                        }
                    }
                    pickerItems = []
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { data in
                    if let data, let jpg = ImageTools.compress(data) { images.append(jpg) }
                    showCamera = false
                }
                .ignoresSafeArea()
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let existing, let p = try? VaultCrypto.open(existing.payload) {
            title = p.title
            fields = p.fields
            notes = p.notes
            images = p.images
            hasExpiry = p.expiry != nil
            expiry = p.expiry ?? expiry
        } else {
            fields = kind.template
        }
    }

    private func save() {
        let payload = VaultPayload(title: title.trimmingCharacters(in: .whitespaces), fields: fields, notes: notes,
                                   images: images, expiry: hasExpiry ? expiry : nil)
        do {
            let sealed = try VaultCrypto.seal(payload)
            let item: VaultItem
            if let existing {
                existing.payload = sealed
                existing.updatedAt = Date()
                item = existing
            } else {
                item = VaultItem(kind: kind.rawValue, payload: sealed, sortOrder: items.count)
                context.insert(item)
            }
            try context.save()
            Notifier.scheduleExpiry(id: item.id, title: payload.title.isEmpty ? kind.title : payload.title,
                                    date: payload.expiry)
            Haptics.success()
            dismiss()
        } catch {
            self.error = "Shifrlab saqlab bo'lmadi: \(error.localizedDescription)"
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (Data?) -> Void
        init(onFinish: @escaping (Data?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            onFinish(image?.jpegData(compressionQuality: 0.9))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}

struct PinVerifySheet: View {
    let title: String
    let onFinish: (Bool) -> Void
    @State private var entered = ""
    @State private var shakes: CGFloat = 0
    @State private var message = ""
    private let length = PasscodeStore.length

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 22) {
                HStack {
                    Button("Bekor") { onFinish(false) }.buttonStyle(.glass)
                    Spacer()
                }
                Spacer(minLength: 0)
                Image(systemName: "lock.doc.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 76, height: 76)
                    .glassEffect(.regular, in: .circle)
                Text(title).font(.title3.bold())
                PinDots(count: length, filled: entered.count, error: !message.isEmpty)
                    .modifier(ShakeEffect(animatableData: shakes))
                Text(message).font(.footnote).foregroundStyle(Palette.expense).frame(height: 20)
                Spacer(minLength: 0)
                PinKeypad(onDigit: append, onDelete: { if !entered.isEmpty { entered.removeLast() } })
                    .padding(.bottom, 30)
            }
            .padding(.horizontal, 24)
        }
    }

    private func append(_ d: String) {
        guard entered.count < length else { return }
        message = ""
        entered.append(d)
        guard entered.count == length else { return }
        switch PasscodeStore.verify(entered) {
        case .success:
            Haptics.success()
            onFinish(true)
        case .failure(let remaining):
            fail("Noto'g'ri PIN-kod. Yana \(remaining) ta urinish.")
        case .lockedOut:
            fail("Juda ko'p urinish. Keyinroq qayta urining.")
        }
    }

    private func fail(_ text: String) {
        Haptics.error()
        message = text
        withAnimation(.linear(duration: 0.4)) { shakes += 1 }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            entered = ""
        }
    }
}

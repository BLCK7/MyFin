import SwiftUI
import SwiftData
import PhotosUI

struct DecryptedVaultItem: Identifiable {
    let id: UUID
    let item: VaultItem
    let kind: VaultKind
    let payload: VaultPayload
}

struct VaultView: View {
    @Query(sort: \VaultItem.sortOrder) private var items: [VaultItem]
    @Environment(VaultSession.self) private var session
    @AppStorage("faceIDEnabled") private var faceIDEnabled = false
    @State private var showPin = false
    @State private var showEditor = false
    @State private var newKind: VaultKind = .passport
    @State private var error: String?

    private var decrypted: [DecryptedVaultItem] {
        items.compactMap { i in
            guard let p = try? VaultCrypto.open(i.payload) else { return nil }
            return DecryptedVaultItem(id: i.id, item: i, kind: VaultKind(rawValue: i.kindRaw) ?? .custom, payload: p)
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
                ToolbarItem(placement: .topBarLeading) {
                    Button { withAnimation { session.lock() } } label: { Image(systemName: "lock.fill") }
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
            VStack(spacing: 14) {
                GlassCard(padding: 12, tint: Palette.income) {
                    Label("Seyf ochiq · 3 daqiqa harakatsizlikdan keyin yoki ilova fonga o'tganda yopiladi",
                          systemImage: "lock.open.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if decrypted.isEmpty {
                    GlassCard {
                        ContentUnavailableView("Seyf bo'sh", systemImage: "tray",
                                               description: Text("Yuqoridagi + tugmasi orqali pasport, karta yoki boshqa hujjat qo'shing."))
                    }
                }
                ForEach(Array(decrypted.enumerated()), id: \.element.id) { idx, d in
                    NavigationLink {
                        VaultDetailView(itemID: d.id)
                    } label: {
                        VaultCardRow(item: d)
                    }
                    .buttonStyle(.plain)
                    .appearAnimation(idx)
                }
                if items.count > decrypted.count {
                    Text("\(items.count - decrypted.count) ta yozuvni ochib bo'lmadi (kalit topilmadi).")
                        .font(.caption).foregroundStyle(Palette.expense)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
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

    private var subtitle: String {
        if item.kind == .bankCard, let n = item.payload.fields.first(where: { $0.label.hasPrefix("Karta raqami") })?.value,
           n.count >= 4 {
            return "•••• \(n.filter(\.isNumber).suffix(4))"
        }
        if let exp = item.payload.expiry {
            return exp < Date() ? "Muddati o'tgan" : "Amal qiladi: \(exp.uzDate)"
        }
        return item.kind.title
    }

    var body: some View {
        GlassCard(padding: 14, tint: Color(hex: item.kind.colorHex)) {
            HStack(spacing: 14) {
                IconBadge(icon: item.kind.icon, color: Color(hex: item.kind.colorHex), size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.payload.title.isEmpty ? item.kind.title : item.payload.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle((item.payload.expiry ?? .distantFuture) < Date() ? Palette.expense : Color.secondary)
                }
                Spacer()
                if !item.payload.images.isEmpty {
                    Label("\(item.payload.images.count)", systemImage: "photo").font(.caption).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
        }
    }
}

struct VaultDetailView: View {
    let itemID: UUID
    @Query private var items: [VaultItem]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(VaultSession.self) private var session
    @State private var revealed: Set<UUID> = []
    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var zoom: ImageBox?

    private var item: VaultItem? { items.first { $0.id == itemID } }
    private var payload: VaultPayload? { item.flatMap { try? VaultCrypto.open($0.payload) } }
    private var kind: VaultKind { VaultKind(rawValue: item?.kindRaw ?? "") ?? .custom }

    var body: some View {
        Group {
            if !session.isUnlocked {
                ContentUnavailableView("Seyf yopildi", systemImage: "lock.fill",
                                       description: Text("Xavfsizlik uchun seyf avtomatik yopildi. Orqaga qayting va qayta oching."))
            } else if let payload {
                content(payload)
            } else {
                ContentUnavailableView("Yozuv topilmadi", systemImage: "questionmark.folder")
            }
        }
        .screenBackground()
        .navigationTitle(payload?.title ?? kind.title)
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
            if let item { VaultEditor(kind: kind, existing: item) }
        }
        .sheet(item: $zoom) { z in
            ZoomImageView(data: z.data)
        }
        .confirmationDialog("Yozuv butunlay o'chirilsinmi?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("O'chirish", role: .destructive) {
                if let item {
                    Notifier.cancel(["vault-\(item.id.uuidString)-30", "vault-\(item.id.uuidString)-7"])
                    context.delete(item)
                    try? context.save()
                }
                dismiss()
            }
        }
    }

    private func content(_ p: VaultPayload) -> some View {
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

                GlassCard(padding: 6) {
                    VStack(spacing: 0) {
                        ForEach(p.fields.filter { !$0.value.isEmpty }) { f in
                            fieldRow(f)
                            if f.id != p.fields.filter({ !$0.value.isEmpty }).last?.id {
                                Divider().opacity(0.35).padding(.leading, 12)
                            }
                        }
                    }
                }

                if !p.images.isEmpty {
                    GlassCard(padding: 10) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(Array(p.images.enumerated()), id: \.offset) { _, data in
                                if let ui = UIImage(data: data) {
                                    Image(uiImage: ui)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 120)
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                        .onTapGesture { zoom = ImageBox(data: data) }
                                }
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

                Text("Nusxa olingan qiymat 60 soniyadan keyin bufer xotiradan avtomatik o'chadi va boshqa qurilmalarga sinxronlanmaydi.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .simultaneousGesture(TapGesture().onEnded { session.touch() })
    }

    private func display(_ f: VaultField) -> String {
        if !f.secret || revealed.contains(f.id) {
            if f.label.hasPrefix("Karta raqami") { return grouped(f.value) }
            return f.value
        }
        if f.label.hasPrefix("Karta raqami") {
            return "•••• •••• •••• " + String(f.value.filter(\.isNumber).suffix(4))
        }
        return String(repeating: "•", count: min(max(f.value.count, 6), 14))
    }

    private func grouped(_ v: String) -> String {
        let digits = Array(v.filter(\.isNumber))
        guard digits.count >= 12 else { return v }
        return stride(from: 0, to: digits.count, by: 4).map { String(digits[$0..<min($0 + 4, digits.count)]) }.joined(separator: " ")
    }

    private func fieldRow(_ f: VaultField) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(f.label).font(.caption).foregroundStyle(.secondary)
                Text(display(f))
                    .font(.body.monospaced().weight(.semibold))
                    .contentTransition(.interpolate)
                    .textSelection(.disabled)
            }
            Spacer()
            if f.secret {
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
            Button {
                SecureClipboard.copy(f.value)
                session.touch()
            } label: {
                Image(systemName: "doc.on.doc").frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
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
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(MagnifyGesture().onChanged { scale = max(1, $0.magnification) }.onEnded { _ in
                        withAnimation(.spring) { scale = 1 }
                    })
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline).frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .padding()
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
                                    if let ui = UIImage(data: data) {
                                        Image(uiImage: ui)
                                            .resizable().scaledToFill()
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
                    }
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 4, matching: .images) {
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

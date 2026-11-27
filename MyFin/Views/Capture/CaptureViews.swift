import SwiftUI
import SwiftData
import VisionKit
import PhotosUI

enum CaptureMode: String, Identifiable {
    case scan, photo
    var id: String { rawValue }
}

struct CaptureSheet: View {
    let mode: CaptureMode
    var onPrefill: (TxPrefill) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    private enum Stage {
        case idle
        case working(String)
        case match(ReceiptInfo, FinTransaction)
        case failed(String, TxPrefill?)
    }

    @State private var stage: Stage = .idle
    @State private var showPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var handled = false

    private var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppBackground())
                .navigationTitle(mode == .scan ? "Chekni skanerlash" : "Rasmdan qo'shish")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Yopish") { dismiss() }
                    }
                }
        }
        .photosPicker(isPresented: $showPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task { await readPhoto(item) }
        }
        .onAppear {
            if mode == .photo { showPicker = true }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .idle:
            if mode == .scan && scannerAvailable {
                scanner
            } else {
                idlePanel
            }
        case .working(let text):
            VStack(spacing: 16) {
                ProgressView().controlSize(.large)
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
        case .match(let info, let tx):
            matchPanel(info, tx)
        case .failed(let message, let prefill):
            failedPanel(message, prefill)
        }
    }

    private var scanner: some View {
        ZStack(alignment: .bottom) {
            QRScannerView { code in handle(code: code) }
                .ignoresSafeArea(edges: .bottom)
            VStack(spacing: 12) {
                Label("Chekdagi QR kodni ramkaga keltiring", systemImage: "qrcode.viewfinder")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                Button {
                    showPicker = true
                } label: {
                    Label("Galereyadan tanlash", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.glass)
            }
            .padding(.bottom, 36)
        }
    }

    private var idlePanel: some View {
        VStack(spacing: 18) {
            Image(systemName: mode == .scan ? "qrcode.viewfinder" : "text.viewfinder")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Palette.accent)
            Text(mode == .scan
                 ? "Kamera skaneri bu qurilmada mavjud emas. Chek rasmini galereyadan tanlang."
                 : "Bank ilovasi yoki Wallet skrinshotini, yoki soliq cheki rasmini tanlang. Summa, karta va do'kon avtomatik o'qiladi.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 28)
            Button {
                showPicker = true
            } label: {
                Label("Rasm tanlash", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: 240)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first else { return }
                Task { @MainActor in handle(text: text) }
            }
            .labelStyle(.titleAndIcon)
        }
    }

    private func matchPanel(_ info: ReceiptInfo, _ tx: FinTransaction) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                receiptCard(info)
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Shu xarid allaqachon yozilgan bo'lishi mumkin", systemImage: "link")
                            .font(.subheadline.weight(.semibold))
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tx.merchant.isEmpty ? tx.categoryName : tx.merchant).font(.body.weight(.medium))
                                Text("\(tx.date.uzDay) · \(tx.source.title)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            AmountText(value: -tx.amount, currency: tx.currency, font: .body.weight(.semibold), signed: true)
                        }
                    }
                }
                Button {
                    FinanceEngine.enrich(tx, with: info, ctx: context)
                    Haptics.success()
                    dismiss()
                } label: {
                    Label("Shu operatsiyaga biriktirish", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                Button {
                    finish(FinanceEngine.prefill(from: info, ctx: context))
                } label: {
                    Label("Yangi operatsiya sifatida", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
            .padding()
        }
    }

    private func receiptCard(_ info: ReceiptInfo) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    IconBadge(icon: "qrcode", color: Palette.accent, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.store.isEmpty ? "Soliq cheki" : info.store).font(.headline).lineLimit(2)
                        if let d = info.date {
                            Text(d.uzDate + " " + d.formatted(date: .omitted, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let total = info.total {
                        AmountText(value: total, currency: "UZS", font: .title3.weight(.semibold))
                    }
                }
                if !info.items.isEmpty {
                    Text(info.items.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(4)
                }
            }
        }
    }

    private func failedPanel(_ message: String, _ prefill: TxPrefill?) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44)).foregroundStyle(Palette.warning)
            Text(message)
                .font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
                .padding(.horizontal, 28)
            if let prefill {
                Button {
                    finish(prefill)
                } label: {
                    Label("Qo'lda davom etish", systemImage: "square.and.pencil").frame(maxWidth: 240)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
            Button {
                handled = false
                stage = .idle
            } label: {
                Label("Qaytadan", systemImage: "arrow.counterclockwise").frame(maxWidth: 240)
            }
            .buttonStyle(.glass)
        }
    }

    // MARK: Logic

    private func finish(_ prefill: TxPrefill) {
        onPrefill(prefill)
        dismiss()
    }

    private func handle(code: String) {
        guard !handled else { return }
        handled = true
        Haptics.tap()
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ReceiptParser.isReceiptURL(trimmed), let url = URL(string: trimmed) else {
            stage = .failed("Bu soliq cheki QR kodi emas.\n\(String(trimmed.prefix(80)))", nil)
            return
        }
        if let old = FinanceEngine.receiptAlreadyScanned(trimmed, ctx: context) {
            stage = .failed("Bu chek allaqachon qo'shilgan: \(old.merchant.isEmpty ? old.categoryName : old.merchant), \(Money.format(old.amount, old.currency)).", nil)
            return
        }
        stage = .working("Chek ofd.soliq.uz dan yuklanmoqda…")
        Task { @MainActor in
            let fetcher = ReceiptFetcher()
            let text = await fetcher.fetchText(url)
            var info = ReceiptParser.parse(text: text ?? "", url: trimmed)
            if info.date == nil { info.date = Date() }
            guard text != nil, let total = info.total else {
                stage = .failed("Chek sahifasini o'qib bo'lmadi (internet yoki sayt javob bermadi). Summani qo'lda kiriting — chek havolasi saqlanadi.",
                                FinanceEngine.prefill(from: info, ctx: context))
                return
            }
            if let match = FinanceEngine.receiptMatch(amount: total, date: info.date ?? Date(), ctx: context) {
                stage = .match(info, match)
            } else {
                finish(FinanceEngine.prefill(from: info, ctx: context))
            }
        }
    }

    private func handle(text: String) {
        if ReceiptParser.isReceiptURL(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            handle(code: text)
            return
        }
        if let p = FinanceEngine.prefill(fromText: text, ctx: context) {
            finish(p)
        } else {
            stage = .failed("Matnda summa topilmadi.", nil)
        }
    }

    private func readPhoto(_ item: PhotosPickerItem) async {
        stage = .working("Rasm o'qilmoqda…")
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            stage = .failed("Rasmni ochib bo'lmadi.", nil)
            return
        }
        let result = await ImageReader.read(data)
        if let code = result.codes.first(where: ReceiptParser.isReceiptURL) {
            handled = false
            handle(code: code)
            return
        }
        if let p = FinanceEngine.prefill(fromText: result.text, ctx: context) {
            finish(p)
        } else {
            var p = TxPrefill()
            p.rawText = String(result.text.prefix(600))
            p.source = .screenshot
            stage = .failed("Rasmda summa topilmadi. Qo'lda kiritishingiz mumkin.", p)
        }
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                           qualityLevel: .balanced,
                                           recognizesMultipleItems: false,
                                           isHighFrameRateTrackingEnabled: false,
                                           isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if !context.coordinator.started {
            context.coordinator.started = true
            try? vc.startScanning()
        }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        var started = false
        var fired = false

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !fired else { return }
            for item in addedItems {
                if case .barcode(let b) = item, let payload = b.payloadStringValue {
                    fired = true
                    dataScanner.stopScanning()
                    onCode(payload)
                    return
                }
            }
        }
    }
}

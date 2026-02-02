import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Translation

enum TargetLanguage: String, CaseIterable {
    case english = "en"
    case chinese = "zh-Hans"

    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "Chinese"
        }
    }

    var localeLanguage: Locale.Language {
        Locale.Language(identifier: rawValue)
    }
}

struct ComicTranslationView: View {
    @StateObject private var manager = ComicTranslationManager.shared
    @State private var selectedImage: UIImage?
    @State private var pdfPages: [UIImage] = []
    @State private var currentPageIndex = 0
    @State private var showingImagePicker = false
    @State private var showingDocumentPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var targetLanguage: TargetLanguage = .english
    @State private var showOverlay = false

    private let speechManager = SpeechManager.shared

    var currentDisplayImage: UIImage? {
        if !pdfPages.isEmpty {
            return pdfPages[currentPageIndex]
        }
        return selectedImage
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if currentDisplayImage == nil {
                    emptyStateView
                } else {
                    contentView
                }
            }
            .navigationTitle("Comic Translation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if currentDisplayImage != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: clearSelection) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
        }
        .photosPicker(isPresented: $showingImagePicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, newValue in
            Task {
                await loadImage(from: newValue)
            }
        }
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPicker(onPick: handlePDFSelection)
        }
        .onChange(of: manager.shouldTriggerTranslation) { _, shouldTranslate in
            if shouldTranslate {
                triggerTranslation()
            }
        }
        .onChange(of: targetLanguage) { _, _ in
            // Re-translate when language changes
            if !manager.extractedTexts.isEmpty {
                retranslate()
            }
        }
        .translationTask(translationConfiguration) { session in
            await performTranslation(session: session)
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("Upload a Comic Page")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Select an image or PDF containing Japanese text to translate")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(spacing: 12) {
                Button(action: { showingImagePicker = true }) {
                    Label("Select Image", systemImage: "photo")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(12)
                }

                Button(action: { showingDocumentPicker = true }) {
                    Label("Select PDF", systemImage: "doc.fill")
                        .font(.headline)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.red, lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Content View

    private var contentView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Controls bar
                controlsBar

                // Image display with optional overlay
                if let image = currentDisplayImage {
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)

                        if showOverlay && !manager.extractedTexts.isEmpty && !manager.isProcessing {
                            GeometryReader { geometry in
                                translationOverlay(in: geometry.size)
                            }
                        }
                    }
                    .cornerRadius(12)
                    .shadow(radius: 4)
                    .padding(.horizontal)
                }

                if pdfPages.count > 1 {
                    pdfNavigationView
                }

                if manager.isProcessing {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Extracting and translating text...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }

                if let error = manager.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }

                if !manager.extractedTexts.isEmpty && !showOverlay {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Extracted Text (\(manager.extractedTexts.count))")
                            .font(.headline)
                            .padding(.horizontal)
                            .padding(.bottom, 8)

                        ForEach(manager.extractedTexts) { text in
                            ExtractedTextRow(text: text, speechManager: speechManager)
                            Divider()
                                .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
    }

    // MARK: - Controls Bar

    private var controlsBar: some View {
        VStack(spacing: 12) {
            // Language picker
            HStack {
                Text("Translate to:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("Language", selection: $targetLanguage) {
                    ForEach(TargetLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal)

            // Overlay toggle
            HStack {
                Text("Show overlay:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Toggle("", isOn: $showOverlay)
                    .labelsHidden()
                    .tint(.red)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Translation Overlay

    private func translationOverlay(in size: CGSize) -> some View {
        ZStack {
            ForEach(manager.extractedTexts) { text in
                if !text.translation.isEmpty {
                    Text(text.translation)
                        .font(.system(size: calculateFontSize(for: text.boundingBox, in: size)))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.black.opacity(0.85))
                        .cornerRadius(4)
                        .position(
                            x: text.boundingBox.midX * size.width,
                            y: text.boundingBox.midY * size.height
                        )
                }
            }
        }
    }

    private func calculateFontSize(for boundingBox: CGRect, in size: CGSize) -> CGFloat {
        let boxHeight = boundingBox.height * size.height
        // Scale font to fit roughly within the bounding box
        return max(8, min(boxHeight * 0.6, 16))
    }

    // MARK: - PDF Navigation

    private var pdfNavigationView: some View {
        HStack {
            Button(action: previousPage) {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
            }
            .disabled(currentPageIndex == 0)

            Text("Page \(currentPageIndex + 1) of \(pdfPages.count)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button(action: nextPage) {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
            }
            .disabled(currentPageIndex >= pdfPages.count - 1)
        }
        .foregroundColor(.red)
    }

    // MARK: - Translation

    private func triggerTranslation() {
        translationConfiguration = TranslationSession.Configuration(
            source: Locale.Language(identifier: "ja"),
            target: targetLanguage.localeLanguage
        )
    }

    private func retranslate() {
        // Clear existing translations and re-trigger
        for index in manager.extractedTexts.indices {
            manager.updateTranslation(at: index, with: "")
        }
        manager.shouldTriggerTranslation = true
        triggerTranslation()
    }

    private func performTranslation(session: TranslationSession) async {
        do {
            for (index, text) in manager.extractedTexts.enumerated() {
                let response = try await session.translate(text.japanese)
                await MainActor.run {
                    manager.updateTranslation(at: index, with: response.targetText)
                }
            }
        } catch {
            await MainActor.run {
                manager.errorMessage = "Translation error: \(error.localizedDescription)"
            }
        }

        await MainActor.run {
            manager.finishTranslation()
            translationConfiguration = nil
        }
    }

    // MARK: - Actions

    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item = item else { return }

        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            pdfPages = []
            currentPageIndex = 0
            selectedImage = image
            await manager.processImage(image)
        }
    }

    private func handlePDFSelection(_ url: URL) {
        selectedImage = nil
        pdfPages = manager.extractPDFPages(from: url)
        currentPageIndex = 0

        if let firstPage = pdfPages.first {
            Task {
                await manager.processImage(firstPage)
            }
        }
    }

    private func previousPage() {
        guard currentPageIndex > 0 else { return }
        currentPageIndex -= 1
        processCurrentPage()
    }

    private func nextPage() {
        guard currentPageIndex < pdfPages.count - 1 else { return }
        currentPageIndex += 1
        processCurrentPage()
    }

    private func processCurrentPage() {
        guard currentPageIndex < pdfPages.count else { return }
        Task {
            await manager.processImage(pdfPages[currentPageIndex])
        }
    }

    private func clearSelection() {
        selectedImage = nil
        pdfPages = []
        currentPageIndex = 0
        selectedPhotoItem = nil
        manager.extractedTexts = []
        manager.errorMessage = nil
        translationConfiguration = nil
        showOverlay = false
    }
}

// MARK: - Extracted Text Row

struct ExtractedTextRow: View {
    let text: ExtractedText
    let speechManager: SpeechManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(text.japanese)
                    .font(.title3)
                    .fontWeight(.medium)

                Spacer()

                Button(action: {
                    speechManager.speak(text.japanese)
                }) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.body)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color.red))
                }
                .buttonStyle(PlainButtonStyle())
            }

            if !text.translation.isEmpty {
                Text(text.translation)
                    .font(.body)
                    .foregroundColor(.blue)
            } else {
                Text("Translating...")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding()
    }
}

// MARK: - Document Picker

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.pdf])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }

            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            onPick(url)
        }
    }
}

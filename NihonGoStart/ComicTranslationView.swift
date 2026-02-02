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
    @State private var selectedImages: [UIImage] = []
    @State private var pdfPages: [UIImage] = []
    @State private var currentPageIndex = 0
    @State private var showingImagePicker = false
    @State private var showingDocumentPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var targetLanguage: TargetLanguage = .chinese
    @State private var showOverlay = false
    @State private var showingSaveAlert = false
    @State private var saveAlertMessage = ""

    private let speechManager = SpeechManager.shared
    private let maxImageSelection = 9

    var currentDisplayImage: UIImage? {
        if !pdfPages.isEmpty && currentPageIndex < pdfPages.count {
            return pdfPages[currentPageIndex]
        }
        if !selectedImages.isEmpty && currentPageIndex < selectedImages.count {
            return selectedImages[currentPageIndex]
        }
        return nil
    }

    var totalPages: Int {
        if !pdfPages.isEmpty {
            return pdfPages.count
        }
        return selectedImages.count
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
        .photosPicker(isPresented: $showingImagePicker, selection: $selectedPhotoItems, maxSelectionCount: maxImageSelection, matching: .images)
        .onChange(of: selectedPhotoItems) { _, newValue in
            Task {
                await loadImages(from: newValue)
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
        .alert("Save Image", isPresented: $showingSaveAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveAlertMessage)
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

                        if showOverlay && !manager.extractedTexts.isEmpty && !manager.isProcessing && !manager.isTranslating {
                            GeometryReader { geometry in
                                translationOverlay(in: geometry.size)
                            }
                        }
                    }
                    .cornerRadius(12)
                    .shadow(radius: 4)
                    .padding(.horizontal)
                }

                if totalPages > 1 {
                    pageNavigationView
                }

                if manager.isProcessing || manager.isTranslating {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(manager.isProcessing ? "Extracting text..." : "Translating...")
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

            // Overlay toggle and save button
            HStack {
                Text("Show overlay:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Toggle("", isOn: $showOverlay)
                    .labelsHidden()
                    .tint(.red)

                Spacer()

                if showOverlay && !manager.extractedTexts.isEmpty && !manager.isProcessing {
                    Button(action: saveOverlayImage) {
                        Label("Save", systemImage: "square.and.arrow.down")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.red)
                }
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
                    let isVertical = isVerticalText(text.boundingBox)
                    let boxRect = CGRect(
                        x: text.boundingBox.minX * size.width,
                        y: text.boundingBox.minY * size.height,
                        width: text.boundingBox.width * size.width,
                        height: text.boundingBox.height * size.height
                    )

                    TranslationOverlayText(
                        translation: text.translation,
                        isVertical: isVertical,
                        boxRect: boxRect
                    )
                    .position(
                        x: boxRect.midX,
                        y: boxRect.midY
                    )
                }
            }
        }
    }

    private func isVerticalText(_ boundingBox: CGRect) -> Bool {
        // If height > width * 1.5, likely vertical text
        return boundingBox.height > boundingBox.width * 1.5
    }

    // MARK: - Page Navigation

    private var pageNavigationView: some View {
        HStack {
            Button(action: previousPage) {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
            }
            .disabled(currentPageIndex == 0)

            Text("\(!pdfPages.isEmpty ? "Page" : "Image") \(currentPageIndex + 1) of \(totalPages)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button(action: nextPage) {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
            }
            .disabled(currentPageIndex >= totalPages - 1)
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
        // Start a translation session
        let sessionId = await MainActor.run {
            manager.startTranslationSession()
        }

        do {
            for (index, text) in manager.extractedTexts.enumerated() {
                // Check if session is still valid before each translation
                let isValid = await MainActor.run { manager.isSessionValid(sessionId) }
                guard isValid else {
                    // Session was cancelled, stop translating
                    return
                }

                let response = try await session.translate(text.japanese)

                // Check again before updating
                let stillValid = await MainActor.run { manager.isSessionValid(sessionId) }
                if stillValid {
                    await MainActor.run {
                        manager.updateTranslation(at: index, with: response.targetText)
                    }
                }
            }
        } catch {
            let isValid = await MainActor.run { manager.isSessionValid(sessionId) }
            if isValid {
                await MainActor.run {
                    manager.errorMessage = "Translation error: \(error.localizedDescription)"
                }
            }
        }

        // Only finish if session is still valid
        let isValid = await MainActor.run { manager.isSessionValid(sessionId) }
        if isValid {
            await MainActor.run {
                manager.finishTranslation()
                translationConfiguration = nil
            }
        }
    }

    // MARK: - Actions

    private func loadImages(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }

        var images: [UIImage] = []

        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }

        guard !images.isEmpty else { return }

        await MainActor.run {
            pdfPages = []
            selectedImages = images
            currentPageIndex = 0
        }

        // Process the first image
        await manager.processImage(images[0])
    }

    private func handlePDFSelection(_ url: URL) {
        selectedImages = []
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
        guard currentPageIndex < totalPages - 1 else { return }
        currentPageIndex += 1
        processCurrentPage()
    }

    private func processCurrentPage() {
        guard let image = currentDisplayImage else { return }
        Task {
            await manager.processImage(image)
        }
    }

    private func clearSelection() {
        // Cancel any ongoing translation session
        manager.cancelSession()

        selectedImages = []
        pdfPages = []
        currentPageIndex = 0
        selectedPhotoItems = []
        manager.extractedTexts = []
        manager.errorMessage = nil
        translationConfiguration = nil
        showOverlay = false
    }

    private func saveOverlayImage() {
        guard let originalImage = currentDisplayImage else { return }

        let imageSize = originalImage.size
        let renderer = UIGraphicsImageRenderer(size: imageSize)

        let overlayedImage = renderer.image { context in
            // Draw original image
            originalImage.draw(at: .zero)

            // Draw translation overlays
            for text in manager.extractedTexts where !text.translation.isEmpty {
                let isVertical = isVerticalText(text.boundingBox)
                let boxRect = CGRect(
                    x: text.boundingBox.minX * imageSize.width,
                    y: text.boundingBox.minY * imageSize.height,
                    width: text.boundingBox.width * imageSize.width,
                    height: text.boundingBox.height * imageSize.height
                )

                // Draw background
                context.cgContext.setFillColor(UIColor.black.withAlphaComponent(0.9).cgColor)
                let backgroundPath = UIBezierPath(roundedRect: boxRect, cornerRadius: 4)
                context.cgContext.addPath(backgroundPath.cgPath)
                context.cgContext.fillPath()

                // Calculate font size that fits the text in the box
                let textRect = boxRect.insetBy(dx: 4, dy: 4)
                let fontSize = calculateFittingFontSize(
                    for: text.translation,
                    in: textRect,
                    minSize: 8,
                    maxSize: 48
                )

                // Draw text
                let font = UIFont.boldSystemFont(ofSize: fontSize)
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .center
                paragraphStyle.lineBreakMode = .byWordWrapping

                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraphStyle
                ]

                let attributedString = NSAttributedString(string: text.translation, attributes: attributes)
                attributedString.draw(in: textRect)
            }
        }

        // Save to photo library
        UIImageWriteToSavedPhotosAlbum(overlayedImage, nil, nil, nil)
        saveAlertMessage = "Image saved to Photos"
        showingSaveAlert = true
    }

    /// Calculate the largest font size that fits the text within the given rect
    private func calculateFittingFontSize(for text: String, in rect: CGRect, minSize: CGFloat, maxSize: CGFloat) -> CGFloat {
        var fontSize = maxSize

        while fontSize >= minSize {
            let font = UIFont.boldSystemFont(ofSize: fontSize)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            paragraphStyle.lineBreakMode = .byWordWrapping

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .paragraphStyle: paragraphStyle
            ]

            let boundingRect = (text as NSString).boundingRect(
                with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            )

            if boundingRect.height <= rect.height {
                return fontSize
            }

            fontSize -= 1
        }

        return minSize
    }
}

// MARK: - Translation Overlay Text

struct TranslationOverlayText: View {
    let translation: String
    let isVertical: Bool
    let boxRect: CGRect

    var body: some View {
        Text(translation)
            .font(.system(size: calculateFontSize()))
            .fontWeight(.bold)
            .foregroundColor(.white)
            .lineLimit(nil)
            .minimumScaleFactor(0.1)
            .multilineTextAlignment(.center)
            .frame(width: boxRect.width - 4, height: boxRect.height - 4)
            .padding(2)
            .background(Color.black.opacity(0.9))
            .cornerRadius(4)
    }

    private func calculateFontSize() -> CGFloat {
        // Start with a reasonable base font size based on box dimensions
        // Let minimumScaleFactor handle shrinking to fit
        let area = boxRect.width * boxRect.height
        let charCount = max(1, CGFloat(translation.count))

        // Estimate font size based on available area per character
        // Assuming average character width/height ratio
        let areaPerChar = area / charCount
        let estimatedSize = sqrt(areaPerChar) * 0.8

        // Clamp to reasonable range, minimumScaleFactor will shrink if needed
        return max(8, min(estimatedSize, 24))
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
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Translating...")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .italic()
                }
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

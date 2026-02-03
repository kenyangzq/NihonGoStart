import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Translation
import Photos

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
    @State private var showingImagePicker = false
    @State private var showingDocumentPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var showingSaveAlert = false
    @State private var saveAlertMessage = ""
    @State private var isSaving = false

    private let speechManager = SpeechManager.shared
    private let maxImageSelection = 9

    // Bindings to manager's session state for persistence
    private var targetLanguageBinding: Binding<TargetLanguage> {
        Binding(
            get: { TargetLanguage(rawValue: manager.sessionTargetLanguage) ?? .chinese },
            set: { manager.sessionTargetLanguage = $0.rawValue }
        )
    }

    private var showOverlayBinding: Binding<Bool> {
        Binding(
            get: { manager.sessionShowOverlay },
            set: { manager.sessionShowOverlay = $0 }
        )
    }

    // Convenience getters for session state
    private var targetLanguage: TargetLanguage {
        TargetLanguage(rawValue: manager.sessionTargetLanguage) ?? .chinese
    }

    private var showOverlay: Bool {
        manager.sessionShowOverlay
    }

    var allImages: [UIImage] {
        if !manager.sessionPDFPages.isEmpty {
            return manager.sessionPDFPages
        }
        return manager.sessionImages
    }

    private var currentPageIndex: Int {
        manager.sessionCurrentPageIndex
    }

    var currentDisplayImage: UIImage? {
        let images = allImages
        guard !images.isEmpty && currentPageIndex < images.count else { return nil }
        return images[currentPageIndex]
    }

    var totalPages: Int {
        return allImages.count
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
                // Check if we have cached translation for this language
                if let image = currentDisplayImage,
                   manager.loadCachedTranslations(for: image, language: targetLanguage.rawValue) {
                    // Loaded from cache, no need to translate
                    manager.shouldTriggerTranslation = false
                    return
                }

                // Use Gemini API if available, then Azure, then Apple Translation
                Task {
                    await manager.translateWithGemini(to: targetLanguage.rawValue)
                    // Update cache after translation with language
                    if let image = currentDisplayImage {
                        manager.updateCache(for: image, language: targetLanguage.rawValue)
                    }
                }
            }
        }
        .onChange(of: manager.sessionTargetLanguage) { _, newLanguage in
            // When language changes, check cache first
            if let image = currentDisplayImage {
                if manager.loadCachedTranslations(for: image, language: newLanguage) {
                    // Loaded from cache
                    return
                }
                // Need to re-translate
                if !manager.extractedTexts.isEmpty {
                    retranslate()
                }
            }
        }
        .onChange(of: manager.sessionCurrentPageIndex) { _, _ in
            // When page changes, load the appropriate data
            switchToCurrentPage()
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

                // Image display with optional overlay and swipe gestures
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

                        // Progress overlay on top of image
                        if manager.isProcessing || manager.isTranslating {
                            // Dim the image
                            Color.black.opacity(0.5)

                            // Progress indicator
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.white)
                                Text(manager.translationProgress.isEmpty ?
                                     (manager.isProcessing ? "Processing..." : "Translating...") :
                                     manager.translationProgress)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 32)
                            .padding(.vertical, 20)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(16)
                        }
                    }
                    .cornerRadius(12)
                    .shadow(radius: 4)
                    .padding(.horizontal)
                    .gesture(
                        DragGesture(minimumDistance: 50)
                            .onEnded { value in
                                handleSwipe(value)
                            }
                    )
                }

                if totalPages > 1 {
                    pageNavigationView
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

                Picker("Language", selection: targetLanguageBinding) {
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

                Toggle("", isOn: showOverlayBinding)
                    .labelsHidden()
                    .tint(.red)

                Spacer()

                if showOverlay && !manager.extractedTexts.isEmpty && !manager.isProcessing {
                    Button(action: saveOverlayImage) {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Label("Save", systemImage: "square.and.arrow.down")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                    .foregroundColor(.red)
                    .disabled(isSaving)
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

            Text("\(!manager.sessionPDFPages.isEmpty ? "Page" : "Image") \(currentPageIndex + 1) of \(totalPages)")
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

    // MARK: - Swipe Handling

    private func handleSwipe(_ value: DragGesture.Value) {
        let horizontalAmount = value.translation.width
        let verticalAmount = value.translation.height

        // Only handle horizontal swipes
        guard abs(horizontalAmount) > abs(verticalAmount) else { return }

        if horizontalAmount < -50 {
            // Swipe left - next image
            nextPage()
        } else if horizontalAmount > 50 {
            // Swipe right - previous image
            previousPage()
        }
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

        // Use Gemini API (falls back to Azure, then Apple Translation)
        Task {
            await manager.translateWithGemini(to: targetLanguage.rawValue)
            if let image = currentDisplayImage {
                manager.updateCache(for: image, language: targetLanguage.rawValue)
            }
        }
    }

    private func performTranslation(session: TranslationSession) async {
        // Start a translation session
        let sessionId = await MainActor.run {
            manager.startTranslationSession()
        }

        // Capture current image for cache update
        let currentImage = currentDisplayImage

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

                // Update cache with translated results
                if let image = currentImage {
                    manager.cacheTranslations(for: image, language: targetLanguage.rawValue)
                }
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
            manager.sessionPDFPages = []
            manager.sessionImages = images
            manager.sessionCurrentPageIndex = 0
            manager.clearCache()
        }

        // Process the first image
        await manager.processImage(images[0])

        // Start background processing for remaining images
        if images.count > 1 {
            Task.detached {
                for i in 1..<images.count {
                    await manager.processImageInBackground(images[i])
                }
            }
        }
    }

    private func handlePDFSelection(_ url: URL) {
        manager.sessionImages = []
        manager.sessionPDFPages = manager.extractPDFPages(from: url)
        manager.sessionCurrentPageIndex = 0
        manager.clearCache()

        if let firstPage = manager.sessionPDFPages.first {
            Task {
                await manager.processImage(firstPage)

                // Start background processing for remaining pages
                if manager.sessionPDFPages.count > 1 {
                    let pages = manager.sessionPDFPages
                    Task.detached {
                        for i in 1..<pages.count {
                            await manager.processImageInBackground(pages[i])
                        }
                    }
                }
            }
        }
    }

    private func previousPage() {
        guard manager.sessionCurrentPageIndex > 0 else { return }
        manager.sessionCurrentPageIndex -= 1
    }

    private func nextPage() {
        guard manager.sessionCurrentPageIndex < totalPages - 1 else { return }
        manager.sessionCurrentPageIndex += 1
    }

    private func switchToCurrentPage() {
        guard let image = currentDisplayImage else { return }

        // Cancel any ongoing translation
        manager.cancelSession()
        translationConfiguration = nil

        Task {
            await manager.processImage(image)
        }
    }

    private func clearSelection() {
        // Cancel any ongoing translation session
        manager.cancelSession()

        manager.sessionImages = []
        manager.sessionPDFPages = []
        manager.sessionCurrentPageIndex = 0
        selectedPhotoItems = []
        manager.extractedTexts = []
        manager.errorMessage = nil
        manager.clearCache()
        translationConfiguration = nil
        manager.sessionShowOverlay = true  // Reset to default
    }

    private func saveOverlayImage() {
        guard let originalImage = currentDisplayImage else { return }

        isSaving = true

        // Request photo library permission
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                if status == .authorized || status == .limited {
                    self.performSave(originalImage: originalImage)
                } else {
                    self.isSaving = false
                    self.saveAlertMessage = "Please grant photo library access in Settings to save images."
                    self.showingSaveAlert = true
                }
            }
        }
    }

    private func performSave(originalImage: UIImage) {
        let imageSize = originalImage.size
        let renderer = UIGraphicsImageRenderer(size: imageSize)

        let overlayedImage = renderer.image { context in
            // Draw original image
            originalImage.draw(at: .zero)

            // Draw translation overlays
            for text in manager.extractedTexts where !text.translation.isEmpty {
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

        // Save to photo library using PHPhotoLibrary
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: overlayedImage)
        } completionHandler: { success, error in
            DispatchQueue.main.async {
                self.isSaving = false
                if success {
                    self.saveAlertMessage = "Image saved to Photos"
                } else {
                    self.saveAlertMessage = "Failed to save: \(error?.localizedDescription ?? "Unknown error")"
                }
                self.showingSaveAlert = true
            }
        }
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

    // Minimum font size to ensure readability
    private let minFontSize: CGFloat = 10
    private let maxFontSize: CGFloat = 24
    private let padding: CGFloat = 4

    var body: some View {
        let (fontSize, adjustedSize) = calculateFontAndBoxSize()

        Text(translation)
            .font(.system(size: fontSize))
            .fontWeight(.bold)
            .foregroundColor(.white)
            .lineLimit(nil)
            .multilineTextAlignment(.center)
            .frame(width: adjustedSize.width - padding * 2, height: adjustedSize.height - padding * 2)
            .padding(padding)
            .background(Color.black.opacity(0.9))
            .cornerRadius(4)
    }

    /// Calculate font size and potentially expanded box size to fit minimum readable text
    private func calculateFontAndBoxSize() -> (fontSize: CGFloat, boxSize: CGSize) {
        // Start with original box size
        var boxWidth = boxRect.width
        var boxHeight = boxRect.height

        // Calculate font size based on box dimensions
        let area = boxWidth * boxHeight
        let charCount = max(1, CGFloat(translation.count))
        let areaPerChar = area / charCount
        var fontSize = sqrt(areaPerChar) * 0.7

        // Enforce minimum font size
        if fontSize < minFontSize {
            fontSize = minFontSize

            // Need to expand the box to fit the text at minimum font size
            // Estimate required area based on minimum font
            let charWidth = fontSize * 0.6  // Approximate character width
            let charHeight = fontSize * 1.2  // Line height

            // Calculate how many characters fit per line
            let charsPerLine = max(1, Int(boxWidth / charWidth))
            let linesNeeded = Int(ceil(Double(translation.count) / Double(charsPerLine)))

            // Calculate required height
            let requiredHeight = CGFloat(linesNeeded) * charHeight + padding * 2

            // Expand box if needed (add minimum expansion factor)
            if requiredHeight > boxHeight {
                boxHeight = max(boxHeight * 1.2, requiredHeight)
            }

            // Also ensure minimum width for readability
            let minWidth: CGFloat = 40
            if boxWidth < minWidth {
                boxWidth = minWidth
            }
        }

        // Cap at maximum font size
        fontSize = min(fontSize, maxFontSize)

        return (fontSize, CGSize(width: boxWidth, height: boxHeight))
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

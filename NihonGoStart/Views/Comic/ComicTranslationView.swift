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

    // Dictionary lookup state
    @State private var showingDictionary = false
    @State private var dictionaryTerm = ""

    // Bookmarks state
    @State private var showingBookmarks = false

    // Zoom/pan state
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero

    // Full screen state
    @State private var showingFullScreen = false

    // Loading state for image upload
    @State private var isLoadingImages = false
    @State private var loadingProgress: String = ""

    // Session management state
    @State private var showingMergeSessions = false
    @State private var showingReorderImages = false
    @State private var selectedSessionsForMerge: Set<UUID> = []

    // Font size preference (persisted)
    @AppStorage("overlayFontSize") private var overlayFontSize: Double = 12.0

    private let speechManager = SpeechManager.shared
    private let maxImageSelection = 20

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
                if isLoadingImages {
                    loadingImagesView
                } else if currentDisplayImage == nil {
                    emptyStateView
                } else {
                    contentView
                }
            }
            .navigationTitle("Comic Translation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingBookmarks = true }) {
                        Image(systemName: "bookmark")
                            .foregroundColor(.yellow)
                    }
                }

                if currentDisplayImage != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: closeSession) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
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
        .sheet(isPresented: $showingDictionary) {
            DictionaryLookupSheet(term: dictionaryTerm)
        }
        .sheet(isPresented: $showingBookmarks) {
            BookmarksView()
        }
        .sheet(isPresented: $showingMergeSessions) {
            MergeSessionsView(onMerge: mergeSelectedSessions)
        }
        .sheet(isPresented: $showingReorderImages) {
            ReorderImagesView(
                images: allImages,
                isPDF: !manager.sessionPDFPages.isEmpty,
                onReorder: reorderImages
            )
        }
        .fullScreenCover(isPresented: $showingFullScreen) {
            FullScreenComicView(
                images: allImages,
                currentIndex: Binding(
                    get: { manager.sessionCurrentPageIndex },
                    set: { manager.sessionCurrentPageIndex = $0 }
                ),
                showOverlay: showOverlay,
                extractedTexts: manager.extractedTexts,
                isProcessing: manager.isProcessing,
                isTranslating: manager.isTranslating,
                translationProgress: manager.translationProgress,
                overlayFontSize: overlayFontSize
            )
        }
        .onDisappear {
            // Auto-save current session when navigating away
            if !allImages.isEmpty {
                // Update session language to current selection before saving
                manager.sessionTargetLanguage = targetLanguage.rawValue
                manager.saveCurrentSession()
            }
        }
    }

    // MARK: - Loading Images View

    private var loadingImagesView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text(loadingProgress.isEmpty ? "Loading images..." : loadingProgress)
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Please wait while your images are being prepared")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // New session section
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)

                    Text("New Translation")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Select an image or PDF containing Japanese text")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 12) {
                        Button(action: { showingImagePicker = true }) {
                            Label("Image", systemImage: "photo")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.red)
                                .cornerRadius(10)
                        }

                        Button(action: { showingDocumentPicker = true }) {
                            Label("PDF", systemImage: "doc.fill")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.red, lineWidth: 1)
                                )
                        }
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(16)
                .padding(.horizontal)

                // Saved sessions section
                if !manager.savedSessions.isEmpty {
                    savedSessionsSection
                }
            }
            .padding(.vertical)
        }
    }

    // MARK: - Saved Sessions Section

    private var savedSessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Sessions")
                    .font(.headline)
                Spacer()
                Text("\(manager.savedSessions.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Merge sessions button
                if manager.savedSessions.count > 1 {
                    Button(action: { showingMergeSessions = true }) {
                        Text("Merge")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal)

            LazyVStack(spacing: 8) {
                ForEach(manager.savedSessions) { session in
                    SavedSessionRow(session: session, onTap: {
                        loadSession(session)
                    }, onDelete: {
                        manager.deleteSavedSession(session)
                    }, onRename: { newName in
                        manager.renameSession(session, to: newName)
                    })
                }
            }
            .padding(.horizontal)
        }
    }

    private func loadSession(_ session: SavedComicSession) {
        manager.loadSavedSession(session)
        if let firstImage = manager.sessionImages.first {
            Task {
                // Pass the session's target language explicitly to ensure cache lookup works
                await manager.processImage(firstImage, language: session.targetLanguage)
            }
        }
    }

    // MARK: - Content View

    private var contentView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Controls bar
                controlsBar

                // Image display with optional overlay, zoom/pan, and swipe gestures
                if let image = currentDisplayImage {
                    ZoomableImageView(
                        image: image,
                        zoomScale: $zoomScale,
                        lastZoomScale: $lastZoomScale,
                        panOffset: $panOffset,
                        lastPanOffset: $lastPanOffset,
                        showOverlay: showOverlay,
                        extractedTexts: manager.extractedTexts,
                        isProcessing: manager.isProcessing,
                        isTranslating: manager.isTranslating,
                        translationProgress: manager.translationProgress,
                        overlayFontSize: overlayFontSize,
                        onSwipe: handleSwipe
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
                            ExtractedTextRow(
                                text: text,
                                speechManager: speechManager,
                                targetLanguage: targetLanguage.rawValue
                            ) { term in
                                dictionaryTerm = term
                                showingDictionary = true
                            }
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

            // Overlay toggle and font size
            HStack {
                Text("Show overlay:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Toggle("", isOn: showOverlayBinding)
                    .labelsHidden()
                    .tint(.red)

                Spacer()

                // Font size control (only shown when overlay is on)
                if showOverlay {
                    HStack(spacing: 4) {
                        Image(systemName: "textformat.size.smaller")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(value: $overlayFontSize, in: 8...24, step: 1)
                            .frame(width: 80)
                            .tint(.red)
                        Image(systemName: "textformat.size.larger")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)

            // Action buttons
            HStack {
                // Zoom indicator (only when zoomed)
                if zoomScale > 1.0 {
                    Button(action: resetZoom) {
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                                .font(.caption)
                            Text("\(Int(zoomScale * 100))%")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.8))
                        .cornerRadius(12)
                    }
                }

                // Full screen button
                Button(action: { showingFullScreen = true }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.gray.opacity(0.8))
                        .cornerRadius(8)
                }

                Spacer()

                // Retry button - re-run translation
                if !manager.extractedTexts.isEmpty && !manager.isProcessing && !manager.isTranslating {
                    Button(action: retryTranslation) {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.orange)
                }

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

                Button(action: startNewSession) {
                    Label("New", systemImage: "plus.circle")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundColor(.blue)

                // Reorder button
                if totalPages > 1 {
                    Button(action: { showingReorderImages = true }) {
                        Label("Reorder", systemImage: "arrow.up.arrow.down")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.purple)
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
                        boxRect: boxRect,
                        baseFontSize: CGFloat(overlayFontSize)
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
        VStack(spacing: 8) {
            // Thumbnail strip
            PageThumbnailStrip(
                images: allImages,
                currentIndex: currentPageIndex,
                onSelect: { index in
                    manager.sessionCurrentPageIndex = index
                }
            )

            // Navigation buttons
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

        // Show loading indicator
        await MainActor.run {
            isLoadingImages = true
            loadingProgress = "Loading \(items.count) image\(items.count > 1 ? "s" : "")..."
        }

        var images: [UIImage] = []

        for (index, item) in items.enumerated() {
            await MainActor.run {
                loadingProgress = "Loading image \(index + 1) of \(items.count)..."
            }

            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }

        guard !images.isEmpty else {
            await MainActor.run {
                isLoadingImages = false
                loadingProgress = ""
            }
            return
        }

        await MainActor.run {
            loadingProgress = "Preparing..."

            // Auto-save current session before loading new images
            if !allImages.isEmpty {
                // Update session language to current selection before saving
                manager.sessionTargetLanguage = targetLanguage.rawValue
                manager.saveCurrentSession()
                manager.resetSavedSessionId()  // New images will be a new session
            }

            manager.sessionPDFPages = []
            manager.sessionImages = images
            manager.sessionCurrentPageIndex = 0
            manager.clearCache()

            // Hide loading indicator - image is now ready to display
            isLoadingImages = false
            loadingProgress = ""
        }

        // Process the first image
        await manager.processImage(images[0])

        // Prefetch next images (up to 2)
        prefetchNextImages()
    }

    /// Prefetch next images when current page changes
    private func prefetchNextImages() {
        let images = allImages
        let currentIndex = manager.sessionCurrentPageIndex
        let currentLanguage = targetLanguage.rawValue

        // Prefetch up to 2 next images (total 3 including current)
        let prefetchCount = 2
        let startIndex = currentIndex + 1
        let endIndex = min(startIndex + prefetchCount, images.count)

        guard startIndex < endIndex else { return }

        let imagesToPrefetch = Array(images[startIndex..<endIndex])

        Task.detached {
            for image in imagesToPrefetch {
                await manager.processAndTranslateInBackground(image, language: currentLanguage)
            }
        }
    }

    private func handlePDFSelection(_ url: URL) {
        // Show loading indicator
        isLoadingImages = true
        loadingProgress = "Extracting PDF pages..."

        // Auto-save current session before loading new PDF
        if !allImages.isEmpty {
            // Update session language to current selection before saving
            manager.sessionTargetLanguage = targetLanguage.rawValue
            manager.saveCurrentSession()
            manager.resetSavedSessionId()  // New PDF will be a new session
        }

        manager.sessionImages = []
        manager.sessionPDFPages = manager.extractPDFPages(from: url)
        manager.sessionCurrentPageIndex = 0
        manager.clearCache()

        let pages = manager.sessionPDFPages

        // Hide loading indicator
        isLoadingImages = false
        loadingProgress = ""

        guard let firstPage = pages.first else { return }

        // Process the first page
        Task {
            await manager.processImage(firstPage)
            // Prefetch next pages (up to 2)
            prefetchNextImages()
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

        // Reset zoom when switching pages
        resetZoom()

        // Check if we have cached results for this image first
        // Only cancel if we actually need to process
        let hasCache = manager.hasCachedResults(for: image)

        if !hasCache {
            // Cancel any ongoing translation only if we need to reprocess
            manager.cancelSession()
            translationConfiguration = nil
        }

        Task {
            await manager.processImage(image)
            // Prefetch next images after current page is loaded
            prefetchNextImages()
        }
    }

    private func resetZoom() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = 1.0
            lastZoomScale = 1.0
            panOffset = .zero
            lastPanOffset = .zero
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
        manager.resetSavedSessionId()  // Important: reset so next save creates new session
        translationConfiguration = nil
        manager.sessionShowOverlay = true  // Reset to default

        // Reset zoom state
        zoomScale = 1.0
        lastZoomScale = 1.0
        panOffset = .zero
        lastPanOffset = .zero
    }

    private func startNewSession() {
        // Save current session before starting new one
        if !allImages.isEmpty {
            // Update session language to current selection before saving
            manager.sessionTargetLanguage = targetLanguage.rawValue
            manager.saveCurrentSession()
        }

        // Clear for new session
        clearSelection()
    }

    private func closeSession() {
        // Save current session before closing (X button)
        if !allImages.isEmpty {
            // Update session language to current selection before saving
            manager.sessionTargetLanguage = targetLanguage.rawValue
            manager.saveCurrentSession()
        }

        // Clear the view
        clearSelection()
    }

    private func retryTranslation() {
        // Force re-run entire flow (OCR + translation) for current image
        guard let image = currentDisplayImage else { return }

        // Clear entire cache for this image to force full reprocessing
        manager.clearCacheForImage(image)
        manager.extractedTexts = []
        manager.errorMessage = nil

        // Reprocess the image from scratch
        Task {
            await manager.processImage(image, language: targetLanguage.rawValue)
        }
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
                let textRect = boxRect.insetBy(dx: 3, dy: 3)
                let fontSize = calculateFittingFontSize(
                    for: text.translation,
                    in: textRect,
                    minSize: 6,
                    maxSize: 36
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

    // MARK: - Merge Sessions

    private func mergeSelectedSessions(_ sessionIds: Set<UUID>) {
        guard sessionIds.count > 1 else { return }

        // Save current session if there is one
        if !allImages.isEmpty {
            manager.sessionTargetLanguage = targetLanguage.rawValue
            manager.saveCurrentSession()
        }

        // Load images from all selected sessions
        var mergedImages: [UIImage] = []
        var targetLanguage = "zh-Hans"  // Default

        for sessionId in sessionIds.sorted(by: { $0.uuidString < $1.uuidString }) {
            if let session = manager.savedSessions.first(where: { $0.id == sessionId }) {
                let sessionDir = manager.sessionsDirectory.appendingPathComponent(session.id.uuidString)

                for fileName in session.imageFileNames {
                    let fileURL = sessionDir.appendingPathComponent(fileName)
                    if let data = try? Data(contentsOf: fileURL),
                       let image = UIImage(data: data) {
                        mergedImages.append(image)
                    }
                }

                targetLanguage = session.targetLanguage
            }
        }

        guard !mergedImages.isEmpty else { return }

        // Clear and setup new merged session
        manager.clearSession()
        manager.sessionImages = mergedImages
        manager.sessionPDFPages = []
        manager.sessionTargetLanguage = targetLanguage
        manager.sessionCurrentPageIndex = 0

        // Process first image
        if let firstImage = mergedImages.first {
            Task {
                await manager.processImage(firstImage, language: targetLanguage)
                prefetchNextImages()
            }
        }
    }

    // MARK: - Reorder Images

    private func reorderImages(to newOrder: [UIImage]) {
        if !manager.sessionPDFPages.isEmpty {
            // PDF pages
            manager.sessionPDFPages = newOrder
        } else {
            // Regular images
            manager.sessionImages = newOrder
        }

        // Update current page index to stay within bounds
        if manager.sessionCurrentPageIndex >= newOrder.count {
            manager.sessionCurrentPageIndex = max(0, newOrder.count - 1)
        }

        // Clear cache since image order has changed
        manager.clearCache()

        // Reload current page
        if let image = currentDisplayImage {
            Task {
                await manager.processImage(image, language: targetLanguage.rawValue)
            }
        }
    }
}

// MARK: - Translation Overlay Text

struct TranslationOverlayText: View {
    let translation: String
    let isVertical: Bool
    let boxRect: CGRect
    var baseFontSize: CGFloat = 12  // User-adjustable base size

    // Font size bounds relative to base size
    private var minFontSize: CGFloat { max(6, baseFontSize - 6) }
    private var maxFontSize: CGFloat { baseFontSize + 6 }
    private let padding: CGFloat = 3

    var body: some View {
        let (fontSize, adjustedSize) = calculateFontAndBoxSize()

        Text(translation)
            .font(.system(size: fontSize))
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .lineLimit(nil)
            .minimumScaleFactor(0.5)  // Allow text to shrink to fit
            .multilineTextAlignment(.center)
            .frame(width: adjustedSize.width - padding * 2, height: adjustedSize.height - padding * 2)
            .padding(padding)
            .background(Color.black.opacity(0.9))
            .cornerRadius(3)
    }

    /// Calculate font size and box size - prioritize fitting text within original box
    private func calculateFontAndBoxSize() -> (fontSize: CGFloat, boxSize: CGSize) {
        let boxWidth = boxRect.width
        let boxHeight = boxRect.height

        // Calculate font size based on box dimensions and text length
        let area = boxWidth * boxHeight
        let charCount = max(1, CGFloat(translation.count))
        let areaPerChar = area / charCount
        var fontSize = sqrt(areaPerChar) * 0.65  // Slightly smaller multiplier

        // Adjust based on user preference
        fontSize = fontSize * (baseFontSize / 12.0)

        // Clamp font size to bounds
        fontSize = max(minFontSize, min(fontSize, maxFontSize))

        // Calculate if text fits at this font size
        let charWidth = fontSize * 0.55  // Approximate character width
        let lineHeight = fontSize * 1.15  // Line height

        let charsPerLine = max(1, Int((boxWidth - padding * 2) / charWidth))
        let linesNeeded = Int(ceil(Double(translation.count) / Double(charsPerLine)))
        let requiredHeight = CGFloat(linesNeeded) * lineHeight + padding * 2

        // Only expand height slightly if absolutely necessary, cap at 1.3x original
        var finalHeight = boxHeight
        if requiredHeight > boxHeight {
            // Try shrinking font first before expanding box
            let shrinkFactor = boxHeight / requiredHeight
            if shrinkFactor >= 0.7 {
                // Text will fit with minimumScaleFactor, keep original box
                finalHeight = boxHeight
            } else {
                // Need some expansion, but cap it
                finalHeight = min(requiredHeight, boxHeight * 1.3)
            }
        }

        // Ensure minimum width for readability
        let finalWidth = max(boxWidth, 30)

        return (fontSize, CGSize(width: finalWidth, height: finalHeight))
    }
}

// MARK: - Zoomable Image View

struct ZoomableImageView: View {
    let image: UIImage
    @Binding var zoomScale: CGFloat
    @Binding var lastZoomScale: CGFloat
    @Binding var panOffset: CGSize
    @Binding var lastPanOffset: CGSize
    let showOverlay: Bool
    let extractedTexts: [ExtractedText]
    let isProcessing: Bool
    let isTranslating: Bool
    let translationProgress: String
    let overlayFontSize: Double
    let onSwipe: (DragGesture.Value) -> Void

    // Track if we're currently panning to prevent scroll interference
    @State private var isPanning = false

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 5.0

    var body: some View {
        GeometryReader { geometry in
            let imageAspect = image.size.width / image.size.height
            let containerAspect = geometry.size.width / geometry.size.height
            let imageSize: CGSize = {
                if imageAspect > containerAspect {
                    // Image is wider - fit to width
                    let width = geometry.size.width
                    let height = width / imageAspect
                    return CGSize(width: width, height: height)
                } else {
                    // Image is taller - fit to height
                    let height = geometry.size.height
                    let width = height * imageAspect
                    return CGSize(width: width, height: height)
                }
            }()

            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)

                // Translation overlay
                if showOverlay && !extractedTexts.isEmpty && !isProcessing && !isTranslating {
                    translationOverlay(in: imageSize)
                }

                // Progress overlay on top of image
                if isProcessing || isTranslating {
                    Color.black.opacity(0.5)

                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text(translationProgress.isEmpty ?
                             (isProcessing ? "Processing..." : "Translating...") :
                             translationProgress)
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
            .frame(width: imageSize.width, height: imageSize.height)
            .scaleEffect(zoomScale)
            .offset(panOffset)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 4)
            // Double-tap has highest priority so it always works for zoom reset
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if zoomScale > 1.0 {
                        zoomScale = 1.0
                        panOffset = .zero
                        lastPanOffset = .zero
                        lastZoomScale = 1.0
                    } else {
                        zoomScale = 2.5
                    }
                }
            }
            // Use highPriorityGesture for pan when zoomed to take priority over scroll view
            .highPriorityGesture(zoomScale > 1.0 ? panGesture : nil)
            .simultaneousGesture(zoomGesture)
            .simultaneousGesture(zoomScale <= 1.0 ? swipeGesture : nil)
        }
        .aspectRatio(CGSize(width: image.size.width, height: image.size.height), contentMode: .fit)
        .padding(.horizontal)
    }

    private func translationOverlay(in size: CGSize) -> some View {
        ZStack {
            ForEach(extractedTexts) { text in
                if !text.translation.isEmpty {
                    let isVertical = text.boundingBox.height > text.boundingBox.width * 1.5
                    let boxRect = CGRect(
                        x: text.boundingBox.minX * size.width,
                        y: text.boundingBox.minY * size.height,
                        width: text.boundingBox.width * size.width,
                        height: text.boundingBox.height * size.height
                    )

                    TranslationOverlayText(
                        translation: text.translation,
                        isVertical: isVertical,
                        boxRect: boxRect,
                        baseFontSize: CGFloat(overlayFontSize)
                    )
                    .position(
                        x: boxRect.midX,
                        y: boxRect.midY
                    )
                }
            }
        }
    }

    // Pinch to zoom gesture
    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastZoomScale
                lastZoomScale = value
                let newScale = zoomScale * delta
                zoomScale = min(max(newScale, minZoom), maxZoom)
            }
            .onEnded { _ in
                lastZoomScale = 1.0
                // Snap back if zoomed out too far
                if zoomScale < minZoom {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        zoomScale = minZoom
                        panOffset = .zero
                    }
                }
                // Reset pan offset when zooming back to 1x
                if zoomScale <= 1.0 {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        panOffset = .zero
                        lastPanOffset = .zero
                    }
                }
            }
    }

    // Pan/drag gesture - smoother with minimumDistance of 0
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                isPanning = true
                // Direct 1:1 mapping for responsive feel
                panOffset = CGSize(
                    width: lastPanOffset.width + value.translation.width,
                    height: lastPanOffset.height + value.translation.height
                )
            }
            .onEnded { value in
                isPanning = false
                // Add momentum for smoother feel
                let velocity = CGSize(
                    width: value.predictedEndTranslation.width - value.translation.width,
                    height: value.predictedEndTranslation.height - value.translation.height
                )

                // Apply momentum with animation
                withAnimation(.easeOut(duration: 0.3)) {
                    panOffset = CGSize(
                        width: lastPanOffset.width + value.translation.width + velocity.width * 0.3,
                        height: lastPanOffset.height + value.translation.height + velocity.height * 0.3
                    )
                }
                lastPanOffset = panOffset
            }
    }

    // Swipe gesture for page navigation (only when not zoomed)
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 50)
            .onEnded { value in
                onSwipe(value)
            }
    }

}

// MARK: - Extracted Text Row

struct ExtractedTextRow: View {
    let text: ExtractedText
    let speechManager: SpeechManager
    let targetLanguage: String
    let onLookup: (String) -> Void

    @StateObject private var bookmarksManager = BookmarksManager.shared
    @State private var showCopiedToast = false
    @State private var toastMessage = "Copied!"

    private var isBookmarked: Bool {
        bookmarksManager.isBookmarked(japanese: text.japanese)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(text.japanese)
                    .font(.title3)
                    .fontWeight(.medium)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = text.japanese
                            toastMessage = "Copied!"
                            showCopiedToast = true
                        } label: {
                            Label("Copy Japanese", systemImage: "doc.on.doc")
                        }

                        if !text.translation.isEmpty {
                            Button {
                                UIPasteboard.general.string = text.translation
                                toastMessage = "Copied!"
                                showCopiedToast = true
                            } label: {
                                Label("Copy Translation", systemImage: "doc.on.doc")
                            }

                            Button {
                                UIPasteboard.general.string = "\(text.japanese)\n\(text.translation)"
                                toastMessage = "Copied!"
                                showCopiedToast = true
                            } label: {
                                Label("Copy Both", systemImage: "doc.on.doc.fill")
                            }
                        }

                        Divider()

                        Button {
                            onLookup(text.japanese)
                        } label: {
                            Label("Look Up", systemImage: "book")
                        }

                        Divider()

                        Button {
                            bookmarksManager.toggleBookmark(
                                japanese: text.japanese,
                                translation: text.translation,
                                targetLanguage: targetLanguage
                            )
                            toastMessage = isBookmarked ? "Removed from bookmarks" : "Bookmarked!"
                            showCopiedToast = true
                        } label: {
                            Label(
                                isBookmarked ? "Remove Bookmark" : "Add Bookmark",
                                systemImage: isBookmarked ? "bookmark.slash" : "bookmark"
                            )
                        }
                    }
                    .onTapGesture {
                        onLookup(text.japanese)
                    }

                Spacer()

                // Bookmark button
                if !text.translation.isEmpty {
                    Button(action: {
                        bookmarksManager.toggleBookmark(
                            japanese: text.japanese,
                            translation: text.translation,
                            targetLanguage: targetLanguage
                        )
                        toastMessage = isBookmarked ? "Removed" : "Bookmarked!"
                        showCopiedToast = true
                    }) {
                        Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                            .font(.body)
                            .foregroundColor(isBookmarked ? .yellow : .gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

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
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = text.translation
                            toastMessage = "Copied!"
                            showCopiedToast = true
                        } label: {
                            Label("Copy Translation", systemImage: "doc.on.doc")
                        }
                    }
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
        .overlay(alignment: .top) {
            if showCopiedToast {
                Text(toastMessage)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { showCopiedToast = false }
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showCopiedToast)
    }
}

// MARK: - Saved Session Row

struct SavedSessionRow: View {
    let session: SavedComicSession
    let onTap: () -> Void
    let onDelete: () -> Void
    let onRename: (String) -> Void

    @StateObject private var manager = ComicTranslationManager.shared
    @State private var showingRenameAlert = false
    @State private var newName = ""

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail with page count badge
            ZStack(alignment: .bottomTrailing) {
                if let thumbnail = manager.getThumbnail(for: session) {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 70)
                        .cornerRadius(6)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 50, height: 70)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        )
                }

                // Page count badge
                Text("\(session.imageCount)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(4)
                    .offset(x: 2, y: 2)
            }

            // Session info
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(session.displayDate)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(session.targetLanguage == "en" ? "English" : "Chinese")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.8))
                    .cornerRadius(4)
            }

            Spacer()

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.body)
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture {
            newName = session.name ?? ""
            showingRenameAlert = true
        }
        .alert("Rename Session", isPresented: $showingRenameAlert) {
            TextField("Session name", text: $newName)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                onRename(newName)
            }
        } message: {
            Text("Enter a new name for this session")
        }
    }
}

// MARK: - Page Thumbnail Strip

struct PageThumbnailStrip: View {
    let images: [UIImage]
    let currentIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(images.indices, id: \.self) { index in
                        PageThumbnail(
                            image: images[index],
                            index: index,
                            isSelected: index == currentIndex
                        )
                        .onTapGesture { onSelect(index) }
                        .id(index)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .onChange(of: currentIndex) { _, newIndex in
                withAnimation {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .frame(height: 85)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct PageThumbnail: View {
    let image: UIImage
    let index: Int
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 45, height: 65)
                .cornerRadius(6)
                .clipped()
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.red : Color.clear, lineWidth: 3)
                )
                .shadow(color: isSelected ? Color.red.opacity(0.3) : Color.clear, radius: 4)

            // Page number badge
            Text("\(index + 1)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.7))
                .cornerRadius(3)
                .offset(x: 2, y: 2)
        }
        .opacity(isSelected ? 1.0 : 0.7)
    }
}

// MARK: - Dictionary Lookup Sheet

struct DictionaryLookupSheet: View {
    let term: String
    @Environment(\.dismiss) var dismiss
    @State private var jishoResults: [JishoWord] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Looking up...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else if jishoResults.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No definitions found for")
                            .foregroundColor(.secondary)
                        Text(term)
                            .font(.title2)
                            .fontWeight(.medium)
                    }
                    .padding()
                } else {
                    List(jishoResults) { word in
                        JishoWordRow(word: word)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(term)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            await lookupWord()
        }
    }

    private func lookupWord() async {
        // First try Apple's built-in dictionary
        if UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: term) {
            // Apple dictionary has a definition - we could show it, but for now use Jisho for consistency
        }

        // Use Jisho API
        guard let encodedTerm = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://jisho.org/api/v1/search/words?keyword=\(encodedTerm)") else {
            errorMessage = "Invalid search term"
            isLoading = false
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(JishoResponse.self, from: data)
            jishoResults = Array(response.data.prefix(10))  // Limit to 10 results
            isLoading = false
        } catch {
            errorMessage = "Could not fetch definitions"
            isLoading = false
        }
    }
}

struct JishoWordRow: View {
    let word: JishoWord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Word and reading
            HStack(alignment: .bottom, spacing: 8) {
                if let japanese = word.japanese.first {
                    if let wordText = japanese.word {
                        Text(wordText)
                            .font(.title2)
                            .fontWeight(.medium)
                    }
                    if let reading = japanese.reading {
                        Text(reading)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Definitions
            ForEach(Array(word.senses.prefix(3).enumerated()), id: \.offset) { index, sense in
                VStack(alignment: .leading, spacing: 2) {
                    // Parts of speech
                    if !sense.parts_of_speech.isEmpty {
                        Text(sense.parts_of_speech.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.blue)
                            .italic()
                    }
                    // Definitions
                    Text("\(index + 1). \(sense.english_definitions.joined(separator: "; "))")
                        .font(.body)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Full Screen Comic View

struct FullScreenComicView: View {
    let images: [UIImage]
    @Binding var currentIndex: Int
    let showOverlay: Bool
    let extractedTexts: [ExtractedText]
    let isProcessing: Bool
    let isTranslating: Bool
    let translationProgress: String
    let overlayFontSize: Double

    @Environment(\.dismiss) var dismiss
    @State private var fsZoomScale: CGFloat = 1.0
    @State private var fsLastZoomScale: CGFloat = 1.0
    @State private var fsPanOffset: CGSize = .zero
    @State private var fsLastPanOffset: CGSize = .zero
    @State private var showControls = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if !images.isEmpty && currentIndex < images.count {
                GeometryReader { geometry in
                    let image = images[currentIndex]
                    let imageAspect = image.size.width / image.size.height
                    let containerAspect = geometry.size.width / geometry.size.height
                    let imageSize: CGSize = {
                        if imageAspect > containerAspect {
                            let width = geometry.size.width
                            let height = width / imageAspect
                            return CGSize(width: width, height: height)
                        } else {
                            let height = geometry.size.height
                            let width = height * imageAspect
                            return CGSize(width: width, height: height)
                        }
                    }()

                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)

                        // Translation overlay
                        if showOverlay && !extractedTexts.isEmpty && !isProcessing && !isTranslating {
                            ZStack {
                                ForEach(extractedTexts) { text in
                                    if !text.translation.isEmpty {
                                        let isVertical = text.boundingBox.height > text.boundingBox.width * 1.5
                                        let boxRect = CGRect(
                                            x: text.boundingBox.minX * imageSize.width,
                                            y: text.boundingBox.minY * imageSize.height,
                                            width: text.boundingBox.width * imageSize.width,
                                            height: text.boundingBox.height * imageSize.height
                                        )

                                        TranslationOverlayText(
                                            translation: text.translation,
                                            isVertical: isVertical,
                                            boxRect: boxRect,
                                            baseFontSize: CGFloat(overlayFontSize)
                                        )
                                        .position(x: boxRect.midX, y: boxRect.midY)
                                    }
                                }
                            }
                        }

                        // Progress overlay
                        if isProcessing || isTranslating {
                            Color.black.opacity(0.5)
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.white)
                                Text(translationProgress.isEmpty ?
                                     (isProcessing ? "Processing..." : "Translating...") :
                                     translationProgress)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                            }
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(16)
                        }
                    }
                    .frame(width: imageSize.width, height: imageSize.height)
                    .scaleEffect(fsZoomScale)
                    .offset(fsPanOffset)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .onTapGesture(count: 2) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if fsZoomScale > 1.0 {
                                fsZoomScale = 1.0
                                fsPanOffset = .zero
                                fsLastPanOffset = .zero
                                fsLastZoomScale = 1.0
                            } else {
                                fsZoomScale = 2.5
                            }
                        }
                    }
                    .onTapGesture(count: 1) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showControls.toggle()
                        }
                    }
                    .highPriorityGesture(fsZoomScale > 1.0 ? fsPanGesture : nil)
                    .simultaneousGesture(fsZoomGesture)
                    .simultaneousGesture(fsZoomScale <= 1.0 ? fsSwipeGesture : nil)
                }
                .ignoresSafeArea()
            }

            // Controls overlay
            if showControls {
                VStack {
                    // Top bar
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .shadow(radius: 4)
                        }

                        Spacer()

                        if images.count > 1 {
                            Text("\(currentIndex + 1) / \(images.count)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(12)
                        }

                        Spacer()

                        // Zoom indicator
                        if fsZoomScale > 1.0 {
                            Button(action: resetFullScreenZoom) {
                                Text("\(Int(fsZoomScale * 100))%")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.6))
                                    .cornerRadius(8)
                            }
                        } else {
                            Color.clear.frame(width: 30)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    Spacer()

                    // Bottom navigation (only when not zoomed)
                    if images.count > 1 && fsZoomScale <= 1.0 {
                        HStack(spacing: 40) {
                            Button(action: previousFullScreenPage) {
                                Image(systemName: "chevron.left.circle.fill")
                                    .font(.title)
                                    .foregroundColor(currentIndex > 0 ? .white : .gray)
                                    .shadow(radius: 4)
                            }
                            .disabled(currentIndex == 0)

                            Button(action: nextFullScreenPage) {
                                Image(systemName: "chevron.right.circle.fill")
                                    .font(.title)
                                    .foregroundColor(currentIndex < images.count - 1 ? .white : .gray)
                                    .shadow(radius: 4)
                            }
                            .disabled(currentIndex >= images.count - 1)
                        }
                        .padding(.bottom, 30)
                    }
                }
            }
        }
        .statusBarHidden(true)
    }

    // MARK: - Full Screen Gestures

    private var fsZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / fsLastZoomScale
                fsLastZoomScale = value
                let newScale = fsZoomScale * delta
                fsZoomScale = min(max(newScale, 1.0), 5.0)
            }
            .onEnded { _ in
                fsLastZoomScale = 1.0
                if fsZoomScale < 1.0 {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        fsZoomScale = 1.0
                        fsPanOffset = .zero
                    }
                }
                if fsZoomScale <= 1.0 {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        fsPanOffset = .zero
                        fsLastPanOffset = .zero
                    }
                }
            }
    }

    private var fsPanGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                fsPanOffset = CGSize(
                    width: fsLastPanOffset.width + value.translation.width,
                    height: fsLastPanOffset.height + value.translation.height
                )
            }
            .onEnded { value in
                let velocity = CGSize(
                    width: value.predictedEndTranslation.width - value.translation.width,
                    height: value.predictedEndTranslation.height - value.translation.height
                )
                withAnimation(.easeOut(duration: 0.3)) {
                    fsPanOffset = CGSize(
                        width: fsLastPanOffset.width + value.translation.width + velocity.width * 0.3,
                        height: fsLastPanOffset.height + value.translation.height + velocity.height * 0.3
                    )
                }
                fsLastPanOffset = fsPanOffset
            }
    }

    private var fsSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 50)
            .onEnded { value in
                let horizontalAmount = value.translation.width
                let verticalAmount = value.translation.height
                guard abs(horizontalAmount) > abs(verticalAmount) else { return }

                if horizontalAmount < -50 {
                    nextFullScreenPage()
                } else if horizontalAmount > 50 {
                    previousFullScreenPage()
                }
            }
    }

    // MARK: - Full Screen Actions

    private func resetFullScreenZoom() {
        withAnimation(.easeInOut(duration: 0.2)) {
            fsZoomScale = 1.0
            fsLastZoomScale = 1.0
            fsPanOffset = .zero
            fsLastPanOffset = .zero
        }
    }

    private func previousFullScreenPage() {
        guard currentIndex > 0 else { return }
        resetFullScreenZoom()
        currentIndex -= 1
    }

    private func nextFullScreenPage() {
        guard currentIndex < images.count - 1 else { return }
        resetFullScreenZoom()
        currentIndex += 1
    }
}

// MARK: - Merge Sessions View

struct MergeSessionsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var manager = ComicTranslationManager.shared
    @State private var selectedSessionIds: Set<UUID> = []

    let onMerge: (Set<UUID>) -> Void

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Select sessions to merge")
                        .font(.headline)
                        .padding(.top)

                    Text("Selected sessions will be combined into one. The order will be based on the session creation date.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)

                    ForEach(manager.savedSessions) { session in
                        MergeSessionRow(
                            session: session,
                            isSelected: selectedSessionIds.contains(session.id),
                            onTap: {
                                if selectedSessionIds.contains(session.id) {
                                    selectedSessionIds.remove(session.id)
                                } else {
                                    selectedSessionIds.insert(session.id)
                                }
                            }
                        )
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Merge Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Merge") {
                        onMerge(selectedSessionIds)
                        dismiss()
                    }
                    .disabled(selectedSessionIds.count < 2)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

struct MergeSessionRow: View {
    let session: SavedComicSession
    let isSelected: Bool
    let onTap: () -> Void

    @StateObject private var manager = ComicTranslationManager.shared

    var body: some View {
        HStack(spacing: 12) {
            // Selection indicator
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundColor(isSelected ? .blue : .gray)

            // Thumbnail with page count badge
            ZStack(alignment: .bottomTrailing) {
                if let thumbnail = manager.getThumbnail(for: session) {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 70)
                        .cornerRadius(6)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 50, height: 70)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        )
                }

                Text("\(session.imageCount)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(4)
                    .offset(x: 2, y: 2)
            }

            // Session info
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(session.displayDate)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(session.targetLanguage == "en" ? "English" : "Chinese")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.8))
                    .cornerRadius(4)
            }

            Spacer()
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Reorder Images View

struct ReorderImagesView: View {
    @Environment(\.dismiss) var dismiss
    let images: [UIImage]
    let isPDF: Bool
    let onReorder: ([UIImage]) -> Void

    @State private var reorderedImages: [UIImage]

    init(images: [UIImage], isPDF: Bool, onReorder: @escaping ([UIImage]) -> Void) {
        self.images = images
        self.isPDF = isPDF
        self.onReorder = onReorder
        self._reorderedImages = State(initialValue: images)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Drag to reorder \(isPDF ? "pages" : "images")")
                        .font(.headline)
                        .padding(.top)

                    LazyVStack(spacing: 8) {
                        ForEach(reorderedImages.indices, id: \.self) { index in
                            ReorderableImageRow(
                                image: reorderedImages[index],
                                index: index,
                                totalCount: reorderedImages.count,
                                onMove: { from, to in
                                    withAnimation {
                                        reorderedImages.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                                    }
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Reorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onReorder(reorderedImages)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

struct ReorderableImageRow: View {
    let image: UIImage
    let index: Int
    let totalCount: Int
    let onMove: (Int, Int) -> Void

    @State private var offset = CGSize.zero

    var body: some View {
        HStack(spacing: 12) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.gray)
                .frame(width: 20)

            // Page number
            Text("\(index + 1)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 30)
                .background(Color.gray)
                .cornerRadius(8)

            // Thumbnail
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 60, height: 85)
                .cornerRadius(6)
                .clipped()

            Spacer()

            // Move buttons
            HStack(spacing: 8) {
                Button(action: { onMove(index, index - 1) }) {
                    Image(systemName: "chevron.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(index > 0 ? .blue : .gray)
                }
                .disabled(index == 0)

                Button(action: { onMove(index, index + 1) }) {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.title2)
                        .foregroundColor(index < totalCount - 1 ? .blue : .gray)
                }
                .disabled(index >= totalCount - 1)
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
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

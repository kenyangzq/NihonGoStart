import Foundation
import Vision
import UIKit
import PDFKit

// Cache entry for storing translation results per image
struct ImageTranslationCache {
    let imageHash: Int
    var extractedTexts: [ExtractedText]
    var isProcessed: Bool
    var translatedLanguages: Set<String>  // Track which languages have been translated

    // Store translations per language
    var translationsByLanguage: [String: [String]]  // language code -> translations array
}

// Response from manga-ocr server
struct MangaOCRResponse: Codable {
    let text: String
}

// MARK: - Saved Session Model

/// Represents a saved comic translation session
struct SavedComicSession: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    var lastAccessedAt: Date
    let imageCount: Int
    let targetLanguage: String
    var thumbnailData: Data?  // First image thumbnail for preview

    // File paths for images (stored separately due to size)
    var imageFileNames: [String]

    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: lastAccessedAt)
    }
}

/// Codable version of ExtractedText for persistence
struct SavedExtractedText: Codable {
    let japanese: String
    let translation: String
    let boundingBox: CGRect
}

/// Codable cache entry for persistence
struct SavedImageCache: Codable {
    let imageIndex: Int
    var extractedTexts: [SavedExtractedText]
    var translationsByLanguage: [String: [String]]
}

@MainActor
class ComicTranslationManager: ObservableObject {
    static let shared = ComicTranslationManager()

    @Published var isProcessing = false
    @Published var isTranslating = false
    @Published var extractedTexts: [ExtractedText] = []
    @Published var errorMessage: String?
    @Published var shouldTriggerTranslation = false
    @Published var translationProgress: String = ""

    // Cache for storing results per image (keyed by image hash)
    private var translationCache: [Int: ImageTranslationCache] = [:]

    // Session ID to track current translation session
    private var currentSessionId: UUID?

    // Session persistence - stores state when switching views
    @Published var sessionImages: [UIImage] = []
    @Published var sessionPDFPages: [UIImage] = []
    @Published var sessionCurrentPageIndex: Int = 0
    @Published var sessionTargetLanguage: String = "zh-Hans"
    @Published var sessionShowOverlay: Bool = true

    // Saved sessions list
    @Published var savedSessions: [SavedComicSession] = []
    private var currentSavedSessionId: UUID?  // Track if we're viewing a saved session

    // Azure AI Vision credentials from Secrets.swift
    private let azureAPIKey = Secrets.azureAPIKey
    private let azureEndpoint = Secrets.azureEndpoint

    // File paths for session storage
    private var sessionsDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let sessionsDir = paths[0].appendingPathComponent("ComicSessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        return sessionsDir
    }

    private var sessionsIndexURL: URL {
        sessionsDirectory.appendingPathComponent("sessions_index.json")
    }

    private init() {
        loadSavedSessionsList()
    }

    // MARK: - Session Persistence

    /// Load the list of saved sessions from disk
    func loadSavedSessionsList() {
        guard FileManager.default.fileExists(atPath: sessionsIndexURL.path) else {
            savedSessions = []
            return
        }

        do {
            let data = try Data(contentsOf: sessionsIndexURL)
            savedSessions = try JSONDecoder().decode([SavedComicSession].self, from: data)
            // Sort by last accessed, most recent first
            savedSessions.sort { $0.lastAccessedAt > $1.lastAccessedAt }
        } catch {
            print("Failed to load sessions index: \(error)")
            savedSessions = []
        }
    }

    /// Save the sessions index to disk
    private func saveSessionsIndex() {
        do {
            let data = try JSONEncoder().encode(savedSessions)
            try data.write(to: sessionsIndexURL)
        } catch {
            print("Failed to save sessions index: \(error)")
        }
    }

    /// Save the current session to disk
    func saveCurrentSession() {
        let images = !sessionPDFPages.isEmpty ? sessionPDFPages : sessionImages
        guard !images.isEmpty else { return }

        // Always create a new session ID for new sessions
        let sessionId = currentSavedSessionId ?? UUID()
        let sessionDir = sessionsDirectory.appendingPathComponent(sessionId.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        // Save images
        var imageFileNames: [String] = []
        for (index, image) in images.enumerated() {
            let fileName = "image_\(index).jpg"
            let fileURL = sessionDir.appendingPathComponent(fileName)
            if let data = image.jpegData(compressionQuality: 0.8) {
                try? data.write(to: fileURL)
                imageFileNames.append(fileName)
            }
        }

        // Save translation cache for each image
        var savedCaches: [SavedImageCache] = []
        for (index, image) in images.enumerated() {
            let hash = hashForImage(image)
            if let cache = translationCache[hash] {
                let savedTexts = cache.extractedTexts.map { text in
                    SavedExtractedText(
                        japanese: text.japanese,
                        translation: text.translation,
                        boundingBox: text.boundingBox
                    )
                }
                let savedCache = SavedImageCache(
                    imageIndex: index,
                    extractedTexts: savedTexts,
                    translationsByLanguage: cache.translationsByLanguage
                )
                savedCaches.append(savedCache)
            }
        }

        // Write cache to file
        let cacheURL = sessionDir.appendingPathComponent("translation_cache.json")
        if let cacheData = try? JSONEncoder().encode(savedCaches) {
            try? cacheData.write(to: cacheURL)
        }

        // Create thumbnail from first image
        var thumbnailData: Data?
        if let firstImage = images.first {
            let thumbnailSize = CGSize(width: 100, height: 150)
            let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
            let thumbnail = renderer.image { _ in
                firstImage.draw(in: CGRect(origin: .zero, size: thumbnailSize))
            }
            thumbnailData = thumbnail.jpegData(compressionQuality: 0.6)
        }

        // Update or create session entry
        if let existingIndex = savedSessions.firstIndex(where: { $0.id == sessionId }) {
            savedSessions[existingIndex].lastAccessedAt = Date()
            savedSessions[existingIndex].imageFileNames = imageFileNames
            savedSessions[existingIndex].thumbnailData = thumbnailData
        } else {
            let newSession = SavedComicSession(
                id: sessionId,
                createdAt: Date(),
                lastAccessedAt: Date(),
                imageCount: images.count,
                targetLanguage: sessionTargetLanguage,
                thumbnailData: thumbnailData,
                imageFileNames: imageFileNames
            )
            savedSessions.insert(newSession, at: 0)
        }

        currentSavedSessionId = sessionId
        saveSessionsIndex()
    }

    /// Load a saved session
    func loadSavedSession(_ session: SavedComicSession) {
        let sessionDir = sessionsDirectory.appendingPathComponent(session.id.uuidString, isDirectory: true)

        var loadedImages: [UIImage] = []
        for fileName in session.imageFileNames {
            let fileURL = sessionDir.appendingPathComponent(fileName)
            if let data = try? Data(contentsOf: fileURL),
               let image = UIImage(data: data) {
                loadedImages.append(image)
            }
        }

        guard !loadedImages.isEmpty else {
            errorMessage = "Failed to load session images"
            return
        }

        // Update last accessed
        if let index = savedSessions.firstIndex(where: { $0.id == session.id }) {
            savedSessions[index].lastAccessedAt = Date()
            saveSessionsIndex()
        }

        // Set session state
        currentSavedSessionId = session.id
        sessionImages = loadedImages
        sessionPDFPages = []
        sessionCurrentPageIndex = 0
        sessionTargetLanguage = session.targetLanguage
        sessionShowOverlay = true

        // Clear existing cache before loading saved cache
        translationCache.removeAll()

        // Load translation cache from disk
        let cacheURL = sessionDir.appendingPathComponent("translation_cache.json")
        if let cacheData = try? Data(contentsOf: cacheURL),
           let savedCaches = try? JSONDecoder().decode([SavedImageCache].self, from: cacheData) {

            for savedCache in savedCaches {
                guard savedCache.imageIndex < loadedImages.count else { continue }
                let image = loadedImages[savedCache.imageIndex]
                // Compute hash from the LOADED image (this is what will be used for cache lookup)
                let hash = hashForImage(image)

                // Build extractedTexts - apply translations from the saved language if available
                var extractedTexts = savedCache.extractedTexts.map { saved in
                    ExtractedText(
                        japanese: saved.japanese,
                        translation: saved.translation,
                        boundingBox: saved.boundingBox
                    )
                }

                // If we have translations stored, apply them to extractedTexts for the session's language
                if let translations = savedCache.translationsByLanguage[session.targetLanguage] {
                    for (index, translation) in translations.enumerated() where index < extractedTexts.count {
                        extractedTexts[index] = ExtractedText(
                            japanese: extractedTexts[index].japanese,
                            translation: translation,
                            boundingBox: extractedTexts[index].boundingBox
                        )
                    }
                }

                translationCache[hash] = ImageTranslationCache(
                    imageHash: hash,
                    extractedTexts: extractedTexts,
                    isProcessed: true,
                    translatedLanguages: Set(savedCache.translationsByLanguage.keys),
                    translationsByLanguage: savedCache.translationsByLanguage
                )
            }
        }
    }

    /// Delete a saved session
    func deleteSavedSession(_ session: SavedComicSession) {
        let sessionDir = sessionsDirectory.appendingPathComponent(session.id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: sessionDir)

        savedSessions.removeAll { $0.id == session.id }
        saveSessionsIndex()

        // If we deleted the current session, clear it
        if currentSavedSessionId == session.id {
            currentSavedSessionId = nil
        }
    }

    /// Get thumbnail image for a session
    func getThumbnail(for session: SavedComicSession) -> UIImage? {
        guard let data = session.thumbnailData else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Cache Management

    /// Get a hash for the image to use as cache key
    private func hashForImage(_ image: UIImage) -> Int {
        // Use image data hash for reliable identification
        if let data = image.jpegData(compressionQuality: 0.5) {
            return data.hashValue
        }
        // Fallback to size-based hash
        return Int(image.size.width * 1000 + image.size.height)
    }

    /// Check if image has cached results
    func hasCachedResults(for image: UIImage) -> Bool {
        let hash = hashForImage(image)
        return translationCache[hash]?.isProcessed == true
    }

    /// Get cached results for image
    func getCachedResults(for image: UIImage) -> [ExtractedText]? {
        let hash = hashForImage(image)
        return translationCache[hash]?.extractedTexts
    }

    /// Check if translation is complete for image in specific language
    func isTranslationComplete(for image: UIImage, language: String) -> Bool {
        let hash = hashForImage(image)
        return translationCache[hash]?.translatedLanguages.contains(language) == true
    }

    /// Get cached translations for a specific language
    func getCachedTranslations(for image: UIImage, language: String) -> [String]? {
        let hash = hashForImage(image)
        return translationCache[hash]?.translationsByLanguage[language]
    }

    /// Load cached translations for a language into extractedTexts
    func loadCachedTranslations(for image: UIImage, language: String) -> Bool {
        let hash = hashForImage(image)
        guard let cache = translationCache[hash],
              let translations = cache.translationsByLanguage[language],
              translations.count == cache.extractedTexts.count else {
            return false
        }

        // Apply cached translations
        extractedTexts = cache.extractedTexts.enumerated().map { index, text in
            ExtractedText(
                japanese: text.japanese,
                translation: translations[index],
                boundingBox: text.boundingBox
            )
        }
        return true
    }

    /// Save translations to cache for a specific language
    func cacheTranslations(for image: UIImage, language: String) {
        let hash = hashForImage(image)
        guard var cache = translationCache[hash] else { return }

        let translations = extractedTexts.map { $0.translation }
        cache.translationsByLanguage[language] = translations
        cache.translatedLanguages.insert(language)

        // Also update extractedTexts in the cache so translations persist when saved to disk
        cache.extractedTexts = extractedTexts
        translationCache[hash] = cache
    }

    /// Clear translation for a specific language (for retry functionality)
    func clearTranslationForCurrentLanguage(for image: UIImage, language: String) {
        let hash = hashForImage(image)
        guard var cache = translationCache[hash] else { return }

        cache.translationsByLanguage.removeValue(forKey: language)
        cache.translatedLanguages.remove(language)

        // Clear translations from extractedTexts
        cache.extractedTexts = cache.extractedTexts.map { text in
            ExtractedText(
                japanese: text.japanese,
                translation: "",
                boundingBox: text.boundingBox
            )
        }

        translationCache[hash] = cache

        // Also clear current extractedTexts translations
        extractedTexts = extractedTexts.map { text in
            ExtractedText(
                japanese: text.japanese,
                translation: "",
                boundingBox: text.boundingBox
            )
        }
    }

    /// Clear all cached results
    func clearCache() {
        translationCache.removeAll()
    }

    /// Reset the saved session ID (call when starting a fresh session)
    func resetSavedSessionId() {
        currentSavedSessionId = nil
    }

    /// Clear all session data (for full reset)
    func clearSession() {
        sessionImages = []
        sessionPDFPages = []
        sessionCurrentPageIndex = 0
        sessionTargetLanguage = "zh-Hans"
        sessionShowOverlay = true
        extractedTexts = []
        errorMessage = nil
        translationCache.removeAll()
        currentSavedSessionId = nil
    }

    // MARK: - Azure AI Vision OCR

    func performAzureOCR(on image: UIImage) async -> [ExtractedText] {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            errorMessage = "Failed to process image"
            return []
        }

        // Azure Computer Vision Read API endpoint
        let urlString = "\(azureEndpoint)vision/v3.2/read/analyze?language=ja"
        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid API URL"
            return []
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(azureAPIKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = imageData

        do {
            // Step 1: Submit image for analysis
            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "Invalid response"
                return []
            }

            if httpResponse.statusCode != 202 {
                errorMessage = "API Error: Status \(httpResponse.statusCode)"
                return []
            }

            // Get the operation location to poll for results
            guard let operationLocation = httpResponse.value(forHTTPHeaderField: "Operation-Location") else {
                errorMessage = "No operation location returned"
                return []
            }

            // Step 2: Poll for results
            return await pollForResults(operationLocation: operationLocation, imageSize: image.size)

        } catch {
            errorMessage = "Network error: \(error.localizedDescription)"
            return []
        }
    }

    private func pollForResults(operationLocation: String, imageSize: CGSize) async -> [ExtractedText] {
        guard let url = URL(string: operationLocation) else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(azureAPIKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")

        // Poll until results are ready (max 30 attempts)
        for _ in 0..<30 {
            do {
                let (data, _) = try await URLSession.shared.data(for: request)

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let status = json["status"] as? String else {
                    continue
                }

                if status == "succeeded" {
                    return parseAzureResponse(json, imageSize: imageSize)
                } else if status == "failed" {
                    errorMessage = "OCR analysis failed"
                    return []
                }

                // Wait before polling again
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            } catch {
                continue
            }
        }

        errorMessage = "OCR timeout - please try again"
        return []
    }

    private func parseAzureResponse(_ json: [String: Any], imageSize: CGSize) -> [ExtractedText] {
        guard let analyzeResult = json["analyzeResult"] as? [String: Any],
              let readResults = analyzeResult["readResults"] as? [[String: Any]] else {
            return []
        }

        var results: [ExtractedText] = []

        for readResult in readResults {
            guard let lines = readResult["lines"] as? [[String: Any]],
                  let pageWidth = readResult["width"] as? Double,
                  let pageHeight = readResult["height"] as? Double else {
                continue
            }

            for line in lines {
                guard let text = line["text"] as? String else { continue }

                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedText.isEmpty, containsJapanese(trimmedText) else { continue }

                // Parse bounding box
                var boundingBox = CGRect.zero
                if let boundingBoxArray = line["boundingBox"] as? [Double], boundingBoxArray.count >= 8 {
                    // Azure returns 4 corner points: [x1,y1,x2,y2,x3,y3,x4,y4]
                    let minX = min(boundingBoxArray[0], boundingBoxArray[6])
                    let maxX = max(boundingBoxArray[2], boundingBoxArray[4])
                    let minY = min(boundingBoxArray[1], boundingBoxArray[3])
                    let maxY = max(boundingBoxArray[5], boundingBoxArray[7])

                    // Normalize to 0-1 range
                    boundingBox = CGRect(
                        x: minX / pageWidth,
                        y: minY / pageHeight,
                        width: (maxX - minX) / pageWidth,
                        height: (maxY - minY) / pageHeight
                    )
                }

                let extracted = ExtractedText(
                    japanese: trimmedText,
                    translation: "",
                    boundingBox: boundingBox
                )
                results.append(extracted)
            }
        }

        // Merge nearby text blocks that likely belong to the same speech bubble
        let mergedResults = mergeNearbyTextBlocks(results)

        // Sort by position (top to bottom, right to left for manga reading order)
        let sortedResults = mergedResults.sorted { a, b in
            if abs(a.boundingBox.midY - b.boundingBox.midY) < 0.05 {
                return a.boundingBox.midX > b.boundingBox.midX
            }
            return a.boundingBox.minY < b.boundingBox.minY
        }

        return sortedResults
    }

    // MARK: - Merge Nearby Text Blocks

    /// Merges text blocks that are close together (likely from the same speech bubble)
    /// Handles both vertical and horizontal text arrangements in manga
    private func mergeNearbyTextBlocks(_ texts: [ExtractedText]) -> [ExtractedText] {
        guard !texts.isEmpty else { return [] }

        // Threshold for considering texts as part of the same bubble
        // Lower = less aggressive merging, keeps bubbles more separate
        let proximityThreshold: CGFloat = 0.04  // 4% of image dimension

        var remaining = texts
        var merged: [ExtractedText] = []

        while !remaining.isEmpty {
            var currentGroup = [remaining.removeFirst()]

            // Find all texts that should be merged with this group
            var foundMore = true
            while foundMore {
                foundMore = false
                var i = 0
                while i < remaining.count {
                    let candidate = remaining[i]

                    // Check if candidate should be merged with any text in current group
                    let shouldMerge = currentGroup.contains { groupText in
                        isNearby(groupText.boundingBox, candidate.boundingBox,
                                proximityThreshold: proximityThreshold)
                    }

                    if shouldMerge {
                        currentGroup.append(remaining.remove(at: i))
                        foundMore = true
                    } else {
                        i += 1
                    }
                }
            }

            // Merge the group into a single ExtractedText
            if currentGroup.count == 1 {
                merged.append(currentGroup[0])
            } else {
                let combinedBox = calculateCombinedBox(for: currentGroup)

                // Determine text orientation by checking individual text blocks
                // If most blocks are taller than wide, it's vertical text
                let verticalBlockCount = currentGroup.filter {
                    $0.boundingBox.height > $0.boundingBox.width * 0.8
                }.count
                let isVerticalText = verticalBlockCount > currentGroup.count / 2

                // Also check if combined box suggests vertical layout
                let isVerticalLayout = combinedBox.height > combinedBox.width * 1.2

                // Sort group based on layout direction
                let sortedGroup: [ExtractedText]
                if isVerticalText || isVerticalLayout {
                    // Vertical Japanese text: read columns RIGHT to LEFT, each column TOP to BOTTOM
                    // Group by X position first (columns), then sort within each column by Y
                    let columnThreshold = proximityThreshold * 1.5

                    sortedGroup = currentGroup.sorted { a, b in
                        // If X positions are significantly different, sort right to left (higher X first)
                        let xDiff = abs(a.boundingBox.midX - b.boundingBox.midX)
                        if xDiff > columnThreshold {
                            return a.boundingBox.midX > b.boundingBox.midX  // Right to left
                        }
                        // Same column: sort top to bottom
                        return a.boundingBox.midY < b.boundingBox.midY
                    }
                } else {
                    // Horizontal layout: sort top to bottom, then left to right
                    sortedGroup = currentGroup.sorted { a, b in
                        let yDiff = abs(a.boundingBox.midY - b.boundingBox.midY)
                        if yDiff > proximityThreshold {
                            return a.boundingBox.midY < b.boundingBox.midY
                        }
                        return a.boundingBox.midX < b.boundingBox.midX
                    }
                }

                // Concatenate text with proper handling for Japanese
                // Don't add spaces - Japanese doesn't use spaces between words
                let combinedText = sortedGroup.map { $0.japanese }.joined()

                merged.append(ExtractedText(
                    japanese: combinedText,
                    translation: "",
                    boundingBox: combinedBox
                ))
            }
        }

        return merged
    }

    /// Calculate combined bounding box for a group of texts
    private func calculateCombinedBox(for texts: [ExtractedText]) -> CGRect {
        let minX = texts.map { $0.boundingBox.minX }.min() ?? 0
        let minY = texts.map { $0.boundingBox.minY }.min() ?? 0
        let maxX = texts.map { $0.boundingBox.maxX }.max() ?? 0
        let maxY = texts.map { $0.boundingBox.maxY }.max() ?? 0

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    /// Check if two bounding boxes are nearby in any direction (vertical or horizontal)
    private func isNearby(_ box1: CGRect, _ box2: CGRect, proximityThreshold: CGFloat) -> Bool {
        // Check horizontal proximity (boxes are side by side)
        let horizontallyClose = areHorizontallyAdjacent(box1, box2, threshold: proximityThreshold)

        // Check vertical proximity (boxes are stacked)
        let verticallyClose = areVerticallyAdjacent(box1, box2, threshold: proximityThreshold)

        return horizontallyClose || verticallyClose
    }

    /// Check if boxes are horizontally adjacent with vertical overlap
    private func areHorizontallyAdjacent(_ box1: CGRect, _ box2: CGRect, threshold: CGFloat) -> Bool {
        // Calculate horizontal gap
        let horizontalGap: CGFloat
        if box1.maxX < box2.minX {
            horizontalGap = box2.minX - box1.maxX
        } else if box2.maxX < box1.minX {
            horizontalGap = box1.minX - box2.maxX
        } else {
            horizontalGap = 0  // Overlapping horizontally
        }

        guard horizontalGap < threshold else { return false }

        // Check for vertical overlap (at least 15% - reduced for better merging)
        let overlapTop = max(box1.minY, box2.minY)
        let overlapBottom = min(box1.maxY, box2.maxY)
        let overlapHeight = max(0, overlapBottom - overlapTop)
        let minHeight = min(box1.height, box2.height)

        guard minHeight > 0 else { return false }
        return overlapHeight / minHeight >= 0.15
    }

    /// Check if boxes are vertically adjacent with horizontal overlap
    private func areVerticallyAdjacent(_ box1: CGRect, _ box2: CGRect, threshold: CGFloat) -> Bool {
        // Calculate vertical gap
        let verticalGap: CGFloat
        if box1.maxY < box2.minY {
            verticalGap = box2.minY - box1.maxY
        } else if box2.maxY < box1.minY {
            verticalGap = box1.minY - box2.maxY
        } else {
            verticalGap = 0  // Overlapping vertically
        }

        guard verticalGap < threshold else { return false }

        // Check for horizontal overlap (at least 15% - reduced for better merging)
        let overlapLeft = max(box1.minX, box2.minX)
        let overlapRight = min(box1.maxX, box2.maxX)
        let overlapWidth = max(0, overlapRight - overlapLeft)
        let minWidth = min(box1.width, box2.width)

        guard minWidth > 0 else { return false }
        return overlapWidth / minWidth >= 0.15
    }

    // MARK: - Manga OCR Recognition

    /// Crop image to a normalized rect
    private func cropImage(_ image: UIImage, to normalizedRect: CGRect) -> UIImage {
        let imageSize = image.size
        let cropRect = CGRect(
            x: normalizedRect.minX * imageSize.width,
            y: normalizedRect.minY * imageSize.height,
            width: normalizedRect.width * imageSize.width,
            height: normalizedRect.height * imageSize.height
        )

        guard let cgImage = image.cgImage?.cropping(to: cropRect) else {
            return image
        }
        return UIImage(cgImage: cgImage)
    }

    /// Perform OCR on a cropped image using manga-ocr backend
    private func performMangaOCRRecognition(croppedImage: UIImage) async -> String? {
        // Check if manga-ocr endpoint is configured
        guard !Secrets.mangaOCREndpoint.isEmpty else { return nil }

        guard let imageData = croppedImage.jpegData(compressionQuality: 0.9) else { return nil }

        guard let url = URL(string: "\(Secrets.mangaOCREndpoint)/ocr") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            let ocrResponse = try JSONDecoder().decode(MangaOCRResponse.self, from: data)
            return ocrResponse.text.isEmpty ? nil : ocrResponse.text
        } catch {
            // Silently fail - will fall back to Azure text
            return nil
        }
    }

    /// Batch response from manga-ocr server
    private struct MangaOCRBatchResponse: Codable {
        let results: [MangaOCRResponse]
    }

    /// Perform batch OCR on multiple cropped images using manga-ocr backend
    private func performMangaOCRBatchRecognition(croppedImages: [UIImage]) async -> [String?] {
        // Check if manga-ocr endpoint is configured
        guard !Secrets.mangaOCREndpoint.isEmpty else {
            return Array(repeating: nil, count: croppedImages.count)
        }

        guard let url = URL(string: "\(Secrets.mangaOCREndpoint)/ocr/batch") else {
            return Array(repeating: nil, count: croppedImages.count)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60  // Longer timeout for batch

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        for (index, image) in croppedImages.enumerated() {
            guard let imageData = image.jpegData(compressionQuality: 0.9) else { continue }

            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"images\"; filename=\"image\(index).jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(imageData)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return Array(repeating: nil, count: croppedImages.count)
            }

            let batchResponse = try JSONDecoder().decode(MangaOCRBatchResponse.self, from: data)
            return batchResponse.results.map { $0.text.isEmpty ? nil : $0.text }
        } catch {
            // Silently fail - will fall back to Azure text
            return Array(repeating: nil, count: croppedImages.count)
        }
    }

    // MARK: - AI Translation (Azure OpenAI preferred, Gemini fallback)

    /// Translate all texts using AI - tries Azure OpenAI first, then Gemini, then Azure Translator
    func translateWithGemini(to targetLanguage: String) async {
        guard !extractedTexts.isEmpty else { return }

        // Try Azure OpenAI first (preferred)
        if !Secrets.azureOpenAIEndpoint.isEmpty && !Secrets.azureOpenAIKey.isEmpty {
            let success = await translateWithAzureOpenAI(to: targetLanguage)
            if success { return }
        }

        // Fall back to Gemini if configured
        if !Secrets.geminiAPIKey.isEmpty {
            let success = await translateWithGeminiAPI(to: targetLanguage)
            if success { return }
        }

        // Final fallback to Azure Translator
        await translateWithAzure(to: targetLanguage)
    }

    // MARK: - Azure OpenAI Translation

    /// Translate using Azure OpenAI (GPT-4o-mini or similar)
    private func translateWithAzureOpenAI(to targetLanguage: String) async -> Bool {
        isTranslating = true
        translationProgress = "Translating (Azure OpenAI)..."

        let sessionId = UUID()
        currentSessionId = sessionId

        // Build the endpoint URL
        let urlString = "\(Secrets.azureOpenAIEndpoint)openai/deployments/\(Secrets.azureOpenAIDeployment)/chat/completions?api-version=2025-01-01-preview"
        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid Azure OpenAI endpoint"
            return false
        }

        // Build compact prompt
        let textsForTranslation = extractedTexts.enumerated().map { index, text in
            "\(index + 1).\(text.japanese)"
        }.joined(separator: "\n")

        let lang = targetLanguage == "en" ? "English" : "Chinese"

        let systemPrompt = "You are a manga translator. Translate Japanese to \(lang). Be natural and concise. Reply with numbered translations only, matching the input format."
        let userPrompt = textsForTranslation

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Secrets.azureOpenAIKey, forHTTPHeaderField: "api-key")

        let requestBody: [String: Any] = [
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.3,
            "max_tokens": min(2048, max(256, extractedTexts.count * 50))
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard isSessionValid(sessionId) else { return false }

            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "Invalid response"
                return false
            }

            if httpResponse.statusCode != 200 {
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorJson["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    print("Azure OpenAI error: \(message)")
                }
                return false
            }

            // Parse Azure OpenAI response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let translatedText = message["content"] as? String else {
                return false
            }

            // Parse the numbered translations
            let translations = parseNumberedTranslations(translatedText)

            for (index, translation) in translations.enumerated() {
                guard index < extractedTexts.count else { break }
                guard isSessionValid(sessionId) else { return false }

                extractedTexts[index] = ExtractedText(
                    japanese: extractedTexts[index].japanese,
                    translation: translation,
                    boundingBox: extractedTexts[index].boundingBox
                )
            }

            translationProgress = "Translated \(extractedTexts.count)/\(extractedTexts.count)"
            finishTranslation()
            return true

        } catch {
            guard isSessionValid(sessionId) else { return false }
            print("Azure OpenAI error: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Gemini API Translation (Fallback)

    /// Translate using Gemini API
    private func translateWithGeminiAPI(to targetLanguage: String) async -> Bool {
        isTranslating = true
        translationProgress = "Translating (Gemini)..."

        let sessionId = UUID()
        currentSessionId = sessionId

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(Secrets.geminiAPIKey)")!

        // Build compact prompt
        let textsForTranslation = extractedTexts.enumerated().map { index, text in
            "\(index + 1).\(text.japanese)"
        }.joined(separator: "\n")

        let lang = targetLanguage == "en" ? "EN" : "ZH"
        let prompt = "Manga JP→\(lang). Natural, concise. Reply numbered only:\n\(textsForTranslation)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.3,
                "maxOutputTokens": min(2048, max(256, extractedTexts.count * 50))
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard isSessionValid(sessionId) else { return false }

            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }

            if httpResponse.statusCode != 200 {
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorJson["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    print("Gemini error: \(message)")
                }
                return false
            }

            // Parse Gemini response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let firstCandidate = candidates.first,
                  let content = firstCandidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let firstPart = parts.first,
                  let translatedText = firstPart["text"] as? String else {
                return false
            }

            // Parse the numbered translations
            let translations = parseNumberedTranslations(translatedText)

            for (index, translation) in translations.enumerated() {
                guard index < extractedTexts.count else { break }
                guard isSessionValid(sessionId) else { return false }

                extractedTexts[index] = ExtractedText(
                    japanese: extractedTexts[index].japanese,
                    translation: translation,
                    boundingBox: extractedTexts[index].boundingBox
                )
            }

            translationProgress = "Translated \(extractedTexts.count)/\(extractedTexts.count)"
            finishTranslation()
            return true

        } catch {
            guard isSessionValid(sessionId) else { return false }
            print("Gemini error: \(error.localizedDescription)")
            return false
        }
    }

    /// Parse numbered translation response (works for both Claude and Gemini)
    private func parseNumberedTranslations(_ response: String) -> [String] {
        var translations: [String] = []
        let lines = response.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match patterns like "[1] translation" or "1. translation" or "1) translation"
            if let match = trimmed.range(of: #"^\[?\d+[\]\.\)]\s*"#, options: .regularExpression) {
                let translation = String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !translation.isEmpty {
                    translations.append(translation)
                }
            }
        }

        return translations
    }

    // MARK: - Azure Translator API

    /// Translate all texts using Azure Translator API (batch for speed)
    func translateWithAzure(to targetLanguage: String) async {
        guard !extractedTexts.isEmpty else { return }

        // Check if Azure Translator is configured
        guard !Secrets.azureTranslatorKey.isEmpty else {
            // Fall back to Apple Translation
            shouldTriggerTranslation = true
            return
        }

        isTranslating = true
        translationProgress = "Translating (Azure)..."

        let sessionId = UUID()
        currentSessionId = sessionId

        // Azure Translator endpoint
        let urlString = "https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&from=ja&to=\(targetLanguage)"
        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid translator URL"
            finishTranslation()
            return
        }

        // Prepare batch request body - Azure supports up to 100 texts per request
        let textsToTranslate = extractedTexts.map { ["Text": $0.japanese] }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: textsToTranslate)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(Secrets.azureTranslatorKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
            request.setValue(Secrets.azureTranslatorRegion, forHTTPHeaderField: "Ocp-Apim-Subscription-Region")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonData

            let (data, response) = try await URLSession.shared.data(for: request)

            // Check if session was cancelled
            guard isSessionValid(sessionId) else { return }

            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "Invalid response"
                finishTranslation()
                return
            }

            if httpResponse.statusCode != 200 {
                // Try to parse error message
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorJson["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    errorMessage = "Translation error: \(message)"
                } else {
                    errorMessage = "Translation API error: \(httpResponse.statusCode)"
                }
                finishTranslation()
                return
            }

            // Parse response - array of translations
            guard let translations = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                errorMessage = "Failed to parse translation response"
                finishTranslation()
                return
            }

            // Update all translations at once
            for (index, translation) in translations.enumerated() {
                guard index < extractedTexts.count else { break }
                guard isSessionValid(sessionId) else { return }

                if let translationArray = translation["translations"] as? [[String: Any]],
                   let firstTranslation = translationArray.first,
                   let translatedText = firstTranslation["text"] as? String {
                    extractedTexts[index] = ExtractedText(
                        japanese: extractedTexts[index].japanese,
                        translation: translatedText,
                        boundingBox: extractedTexts[index].boundingBox
                    )
                }
            }

            translationProgress = "Translated \(extractedTexts.count)/\(extractedTexts.count)"

        } catch {
            guard isSessionValid(sessionId) else { return }
            errorMessage = "Translation error: \(error.localizedDescription)"
        }

        finishTranslation()
    }

    // MARK: - Translation (called from view with TranslationSession - fallback)

    /// Start a new translation session
    func startTranslationSession() -> UUID {
        let sessionId = UUID()
        currentSessionId = sessionId
        isTranslating = true
        translationProgress = "Starting..."
        return sessionId
    }

    /// Check if session is still valid (not cancelled)
    func isSessionValid(_ sessionId: UUID) -> Bool {
        return currentSessionId == sessionId
    }

    func updateTranslation(at index: Int, with translation: String) {
        guard index < extractedTexts.count else { return }
        extractedTexts[index] = ExtractedText(
            japanese: extractedTexts[index].japanese,
            translation: translation,
            boundingBox: extractedTexts[index].boundingBox
        )
        translationProgress = "Translated \(index + 1)/\(extractedTexts.count)"
    }

    func finishTranslation() {
        isProcessing = false
        isTranslating = false
        shouldTriggerTranslation = false
        translationProgress = ""
    }

    /// Cancel current session (called when user clears selection)
    func cancelSession() {
        currentSessionId = nil
        isTranslating = false
        translationProgress = ""
    }

    /// Update cache with current results for an image
    func updateCache(for image: UIImage, language: String? = nil) {
        let hash = hashForImage(image)

        // Get existing cache or create new one
        var cache = translationCache[hash] ?? ImageTranslationCache(
            imageHash: hash,
            extractedTexts: extractedTexts,
            isProcessed: true,
            translatedLanguages: [],
            translationsByLanguage: [:]
        )

        // Update extracted texts (OCR results)
        cache.extractedTexts = extractedTexts.map { text in
            // Store without translations for base cache
            ExtractedText(japanese: text.japanese, translation: "", boundingBox: text.boundingBox)
        }
        cache.isProcessed = true

        // If language provided, cache the translations
        if let lang = language {
            let translations = extractedTexts.map { $0.translation }
            cache.translationsByLanguage[lang] = translations
            cache.translatedLanguages.insert(lang)
        }

        translationCache[hash] = cache
    }

    /// Load cached results into current state
    func loadFromCache(for image: UIImage, language: String? = nil) -> Bool {
        let hash = hashForImage(image)
        guard let cached = translationCache[hash], cached.isProcessed else { return false }

        // Load base extracted texts
        extractedTexts = cached.extractedTexts

        // If language specified and we have cached translations, apply them
        if let lang = language, let translations = cached.translationsByLanguage[lang] {
            for (index, translation) in translations.enumerated() where index < extractedTexts.count {
                extractedTexts[index] = ExtractedText(
                    japanese: extractedTexts[index].japanese,
                    translation: translation,
                    boundingBox: extractedTexts[index].boundingBox
                )
            }
            shouldTriggerTranslation = false
        } else {
            // Need to translate
            shouldTriggerTranslation = !cached.extractedTexts.isEmpty
        }

        isProcessing = false
        isTranslating = false
        translationProgress = ""  // Clear progress when loading from cache
        return true
    }

    // MARK: - PDF Extraction

    func extractPDFPages(from url: URL) -> [UIImage] {
        guard let pdfDocument = PDFDocument(url: url) else {
            errorMessage = "Failed to load PDF"
            return []
        }

        var images: [UIImage] = []

        for pageIndex in 0..<pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }

            let pageRect = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0

            let renderer = UIGraphicsImageRenderer(size: CGSize(
                width: pageRect.width * scale,
                height: pageRect.height * scale
            ))

            let image = renderer.image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: renderer.format.bounds.size))

                context.cgContext.translateBy(x: 0, y: pageRect.height * scale)
                context.cgContext.scaleBy(x: scale, y: -scale)

                page.draw(with: .mediaBox, to: context.cgContext)
            }

            images.append(image)
        }

        return images
    }

    // MARK: - Process Image

    func processImage(_ image: UIImage, language: String? = nil) async {
        // Check cache first - pass language to load translations if available
        let lang = language ?? sessionTargetLanguage
        if loadFromCache(for: image, language: lang) {
            return
        }

        isProcessing = true
        errorMessage = nil
        extractedTexts = []
        shouldTriggerTranslation = false
        translationProgress = "Detecting text regions (Azure)..."

        // Step 1: Use Azure AI Vision OCR to get bounding boxes
        let texts = await performAzureOCR(on: image)

        if texts.isEmpty {
            isProcessing = false
            translationProgress = ""
            if errorMessage == nil {
                errorMessage = "No Japanese text detected in the image"
            }
            return
        }

        // Step 2: Enhance text with manga-ocr (if available)
        let enhancedTexts = await enhanceWithMangaOCR(texts, originalImage: image)

        extractedTexts = enhancedTexts
        shouldTriggerTranslation = true

        // Cache the OCR results (not yet translated)
        updateCache(for: image)
    }

    /// Enhance Azure OCR results with manga-ocr for better text recognition
    private func enhanceWithMangaOCR(_ texts: [ExtractedText], originalImage: UIImage) async -> [ExtractedText] {
        // Skip if manga-ocr endpoint is not configured
        guard !Secrets.mangaOCREndpoint.isEmpty else { return texts }

        translationProgress = "Recognizing text (Manga-OCR)..."

        // Crop images for each text region
        var croppedImages: [UIImage] = []
        for text in texts {
            // Add padding to the bounding box for better recognition
            let paddedBox = CGRect(
                x: max(0, text.boundingBox.minX - 0.01),
                y: max(0, text.boundingBox.minY - 0.01),
                width: min(1 - text.boundingBox.minX, text.boundingBox.width + 0.02),
                height: min(1 - text.boundingBox.minY, text.boundingBox.height + 0.02)
            )
            let cropped = cropImage(originalImage, to: paddedBox)
            croppedImages.append(cropped)
        }

        // Try batch recognition first (more efficient)
        let mangaOCRResults = await performMangaOCRBatchRecognition(croppedImages: croppedImages)

        // Merge results: use manga-ocr text if available, otherwise keep Azure text
        var enhancedTexts: [ExtractedText] = []
        for (index, text) in texts.enumerated() {
            if index < mangaOCRResults.count, let mangaText = mangaOCRResults[index], !mangaText.isEmpty {
                // Use manga-ocr result
                enhancedTexts.append(ExtractedText(
                    japanese: mangaText,
                    translation: "",
                    boundingBox: text.boundingBox
                ))
            } else {
                // Fall back to Azure text
                enhancedTexts.append(text)
            }
        }

        translationProgress = "Found \(enhancedTexts.count) text regions"
        return enhancedTexts
    }

    /// Process image in background without updating UI state (for pre-loading)
    func processImageInBackground(_ image: UIImage) async {
        // Check if already cached
        if hasCachedResults(for: image) {
            return
        }

        // Step 1: Azure OCR for bounding boxes
        let texts = await performAzureOCR(on: image)

        if !texts.isEmpty {
            // Step 2: Enhance with manga-ocr (background, no UI updates)
            let enhancedTexts = await enhanceWithMangaOCRBackground(texts, originalImage: image)

            let hash = hashForImage(image)
            await MainActor.run {
                translationCache[hash] = ImageTranslationCache(
                    imageHash: hash,
                    extractedTexts: enhancedTexts,
                    isProcessed: true,
                    translatedLanguages: [],
                    translationsByLanguage: [:]
                )
            }
        }
    }

    /// Process image AND translate in background (full pre-loading)
    func processAndTranslateInBackground(_ image: UIImage, language: String) async {
        let hash = hashForImage(image)

        // Check if already fully cached with translation
        if let cache = translationCache[hash],
           cache.isProcessed,
           cache.translatedLanguages.contains(language) {
            return
        }

        // Step 1: OCR if needed
        if !hasCachedResults(for: image) {
            let texts = await performAzureOCR(on: image)
            if !texts.isEmpty {
                let enhancedTexts = await enhanceWithMangaOCRBackground(texts, originalImage: image)
                await MainActor.run {
                    translationCache[hash] = ImageTranslationCache(
                        imageHash: hash,
                        extractedTexts: enhancedTexts,
                        isProcessed: true,
                        translatedLanguages: [],
                        translationsByLanguage: [:]
                    )
                }
            }
        }

        // Step 2: Translate in background
        guard let cache = translationCache[hash], !cache.extractedTexts.isEmpty else { return }

        // Skip if already translated for this language
        if cache.translatedLanguages.contains(language) { return }

        let translations = await translateTextsInBackground(cache.extractedTexts, to: language)

        // Cache the translations
        await MainActor.run {
            if var updatedCache = translationCache[hash] {
                updatedCache.translationsByLanguage[language] = translations
                updatedCache.translatedLanguages.insert(language)

                // Also update extractedTexts with translations so they persist when saved
                var updatedTexts = updatedCache.extractedTexts
                for (index, translation) in translations.enumerated() where index < updatedTexts.count {
                    updatedTexts[index] = ExtractedText(
                        japanese: updatedTexts[index].japanese,
                        translation: translation,
                        boundingBox: updatedTexts[index].boundingBox
                    )
                }
                updatedCache.extractedTexts = updatedTexts

                translationCache[hash] = updatedCache
            }
        }
    }

    /// Translate texts in background without updating UI
    private func translateTextsInBackground(_ texts: [ExtractedText], to targetLanguage: String) async -> [String] {
        // Try Azure OpenAI first
        if !Secrets.azureOpenAIEndpoint.isEmpty && !Secrets.azureOpenAIKey.isEmpty {
            if let translations = await translateTextsWithAzureOpenAI(texts, to: targetLanguage) {
                return translations
            }
        }

        // Fall back to Gemini
        if !Secrets.geminiAPIKey.isEmpty {
            if let translations = await translateTextsWithGemini(texts, to: targetLanguage) {
                return translations
            }
        }

        // Fall back to Azure Translator
        if let translations = await translateTextsWithAzureTranslator(texts, to: targetLanguage) {
            return translations
        }

        return Array(repeating: "", count: texts.count)
    }

    /// Background translation using Azure OpenAI (no UI updates)
    private func translateTextsWithAzureOpenAI(_ texts: [ExtractedText], to targetLanguage: String) async -> [String]? {
        let urlString = "\(Secrets.azureOpenAIEndpoint)openai/deployments/\(Secrets.azureOpenAIDeployment)/chat/completions?api-version=2025-01-01-preview"
        guard let url = URL(string: urlString) else { return nil }

        let textsForTranslation = texts.enumerated().map { "\($0.offset + 1).\($0.element.japanese)" }.joined(separator: "\n")
        let lang = targetLanguage == "en" ? "English" : "Chinese"

        let systemPrompt = "You are a manga translator. Translate Japanese to \(lang). Be natural and concise. Reply with numbered translations only, matching the input format."

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Secrets.azureOpenAIKey, forHTTPHeaderField: "api-key")

        let requestBody: [String: Any] = [
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": textsForTranslation]
            ],
            "temperature": 0.3,
            "max_tokens": min(2048, max(256, texts.count * 50))
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let translatedText = message["content"] as? String else { return nil }

            return parseNumberedTranslations(translatedText)
        } catch {
            return nil
        }
    }

    /// Background translation using Gemini (no UI updates)
    private func translateTextsWithGemini(_ texts: [ExtractedText], to targetLanguage: String) async -> [String]? {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(Secrets.geminiAPIKey)")!

        let textsForTranslation = texts.enumerated().map { "\($0.offset + 1).\($0.element.japanese)" }.joined(separator: "\n")
        let lang = targetLanguage == "en" ? "EN" : "ZH"
        let prompt = "Manga JP→\(lang). Natural, concise. Reply numbered only:\n\(textsForTranslation)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": ["temperature": 0.3, "maxOutputTokens": min(2048, max(256, texts.count * 50))]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let firstCandidate = candidates.first,
                  let content = firstCandidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let firstPart = parts.first,
                  let translatedText = firstPart["text"] as? String else { return nil }

            return parseNumberedTranslations(translatedText)
        } catch {
            return nil
        }
    }

    /// Background translation using Azure Translator (no UI updates)
    private func translateTextsWithAzureTranslator(_ texts: [ExtractedText], to targetLanguage: String) async -> [String]? {
        guard !Secrets.azureTranslatorKey.isEmpty else { return nil }

        let urlString = "https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&from=ja&to=\(targetLanguage)"
        guard let url = URL(string: urlString) else { return nil }

        let textsToTranslate = texts.map { ["Text": $0.japanese] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Secrets.azureTranslatorKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue(Secrets.azureTranslatorRegion, forHTTPHeaderField: "Ocp-Apim-Subscription-Region")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: textsToTranslate)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }

            guard let translations = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }

            return translations.compactMap { translation -> String? in
                guard let translationArray = translation["translations"] as? [[String: Any]],
                      let firstTranslation = translationArray.first,
                      let text = firstTranslation["text"] as? String else { return nil }
                return text
            }
        } catch {
            return nil
        }
    }

    /// Enhance Azure OCR results with manga-ocr (background version, no UI updates)
    private func enhanceWithMangaOCRBackground(_ texts: [ExtractedText], originalImage: UIImage) async -> [ExtractedText] {
        // Skip if manga-ocr endpoint is not configured
        guard !Secrets.mangaOCREndpoint.isEmpty else { return texts }

        // Crop images for each text region
        var croppedImages: [UIImage] = []
        for text in texts {
            let paddedBox = CGRect(
                x: max(0, text.boundingBox.minX - 0.01),
                y: max(0, text.boundingBox.minY - 0.01),
                width: min(1 - text.boundingBox.minX, text.boundingBox.width + 0.02),
                height: min(1 - text.boundingBox.minY, text.boundingBox.height + 0.02)
            )
            let cropped = cropImage(originalImage, to: paddedBox)
            croppedImages.append(cropped)
        }

        // Try batch recognition
        let mangaOCRResults = await performMangaOCRBatchRecognition(croppedImages: croppedImages)

        // Merge results
        var enhancedTexts: [ExtractedText] = []
        for (index, text) in texts.enumerated() {
            if index < mangaOCRResults.count, let mangaText = mangaOCRResults[index], !mangaText.isEmpty {
                enhancedTexts.append(ExtractedText(
                    japanese: mangaText,
                    translation: "",
                    boundingBox: text.boundingBox
                ))
            } else {
                enhancedTexts.append(text)
            }
        }

        return enhancedTexts
    }

    // MARK: - Helpers

    private func containsJapanese(_ text: String) -> Bool {
        let hiraganaRange = "\u{3040}"..."\u{309F}"
        let katakanaRange = "\u{30A0}"..."\u{30FF}"
        let kanjiRange = "\u{4E00}"..."\u{9FFF}"

        for char in text.unicodeScalars {
            let charString = String(char)
            if hiraganaRange.contains(charString) ||
               katakanaRange.contains(charString) ||
               kanjiRange.contains(charString) {
                return true
            }
        }
        return false
    }
}

import Foundation
import Vision
import UIKit
import PDFKit

// Cache entry for storing translation results per image
struct ImageTranslationCache {
    let imageHash: Int
    var extractedTexts: [ExtractedText]
    var isProcessed: Bool
    var isTranslated: Bool
}

// Response from manga-ocr server
struct MangaOCRResponse: Codable {
    let text: String
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

    // Azure AI Vision credentials from Secrets.swift
    private let azureAPIKey = Secrets.azureAPIKey
    private let azureEndpoint = Secrets.azureEndpoint

    private init() {}

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

    /// Check if translation is complete for image
    func isTranslationComplete(for image: UIImage) -> Bool {
        let hash = hashForImage(image)
        return translationCache[hash]?.isTranslated == true
    }

    /// Clear all cached results
    func clearCache() {
        translationCache.removeAll()
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

    // MARK: - Claude API Translation (Best Quality)

    /// Translate all texts using Claude API (best quality for manga)
    func translateWithClaude(to targetLanguage: String) async {
        guard !extractedTexts.isEmpty else { return }

        // Check if Claude API is configured
        guard !Secrets.claudeAPIKey.isEmpty else {
            // Fall back to Azure Translator
            await translateWithAzure(to: targetLanguage)
            return
        }

        isTranslating = true
        translationProgress = "Translating (Claude)..."

        let sessionId = UUID()
        currentSessionId = sessionId

        let url = URL(string: "https://api.anthropic.com/v1/messages")!

        // Build compact prompt - just numbered texts, minimal instructions
        let textsForTranslation = extractedTexts.enumerated().map { index, text in
            "\(index + 1).\(text.japanese)"
        }.joined(separator: "\n")

        let lang = targetLanguage == "en" ? "EN" : "ZH"

        // Minimal prompt to reduce token cost
        let prompt = "Manga JP→\(lang). Natural, concise. Reply numbered only:\n\(textsForTranslation)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Secrets.claudeAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Estimate max tokens needed (roughly 2x input for safety)
        let estimatedTokens = min(2048, max(256, extractedTexts.count * 50))

        let requestBody: [String: Any] = [
            "model": "claude-3-5-haiku-20241022",
            "max_tokens": estimatedTokens,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard isSessionValid(sessionId) else { return }

            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "Invalid response"
                finishTranslation()
                return
            }

            if httpResponse.statusCode != 200 {
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorJson["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    errorMessage = "Claude error: \(message)"
                } else {
                    errorMessage = "Claude API error: \(httpResponse.statusCode)"
                }
                // Fall back to Azure
                await translateWithAzure(to: targetLanguage)
                return
            }

            // Parse Claude response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]],
                  let firstContent = content.first,
                  let translatedText = firstContent["text"] as? String else {
                errorMessage = "Failed to parse Claude response"
                await translateWithAzure(to: targetLanguage)
                return
            }

            // Parse the numbered translations
            let translations = parseClaudeTranslations(translatedText)

            for (index, translation) in translations.enumerated() {
                guard index < extractedTexts.count else { break }
                guard isSessionValid(sessionId) else { return }

                extractedTexts[index] = ExtractedText(
                    japanese: extractedTexts[index].japanese,
                    translation: translation,
                    boundingBox: extractedTexts[index].boundingBox
                )
            }

            translationProgress = "Translated \(extractedTexts.count)/\(extractedTexts.count)"

        } catch {
            guard isSessionValid(sessionId) else { return }
            errorMessage = "Claude error: \(error.localizedDescription)"
            // Fall back to Azure
            await translateWithAzure(to: targetLanguage)
            return
        }

        finishTranslation()
    }

    /// Parse Claude's numbered translation response
    private func parseClaudeTranslations(_ response: String) -> [String] {
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
    func updateCache(for image: UIImage, isTranslated: Bool) {
        let hash = hashForImage(image)
        translationCache[hash] = ImageTranslationCache(
            imageHash: hash,
            extractedTexts: extractedTexts,
            isProcessed: true,
            isTranslated: isTranslated
        )
    }

    /// Load cached results into current state
    func loadFromCache(for image: UIImage) -> Bool {
        let hash = hashForImage(image)
        guard let cached = translationCache[hash] else { return false }

        extractedTexts = cached.extractedTexts
        isProcessing = false
        isTranslating = false
        shouldTriggerTranslation = !cached.isTranslated && !cached.extractedTexts.isEmpty
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

    func processImage(_ image: UIImage) async {
        // Check cache first
        if loadFromCache(for: image) {
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
        updateCache(for: image, isTranslated: false)
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
                    isTranslated: false
                )
            }
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

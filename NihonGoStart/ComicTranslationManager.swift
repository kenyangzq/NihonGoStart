import Foundation
import Vision
import UIKit
import PDFKit

@MainActor
class ComicTranslationManager: ObservableObject {
    static let shared = ComicTranslationManager()

    @Published var isProcessing = false
    @Published var isTranslating = false
    @Published var extractedTexts: [ExtractedText] = []
    @Published var errorMessage: String?
    @Published var shouldTriggerTranslation = false

    // Session ID to track current translation session
    private var currentSessionId: UUID?

    // Azure AI Vision credentials from Secrets.swift
    private let azureAPIKey = Secrets.azureAPIKey
    private let azureEndpoint = Secrets.azureEndpoint

    private init() {}

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
        let proximityThreshold: CGFloat = 0.06  // 6% of image dimension

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
                // Determine if the group is primarily vertical or horizontal
                let combinedBox = calculateCombinedBox(for: currentGroup)
                let isVerticalLayout = combinedBox.height > combinedBox.width

                // Sort group based on layout direction
                let sortedGroup: [ExtractedText]
                if isVerticalLayout {
                    // Vertical layout: sort right to left (Japanese reading order), then top to bottom
                    sortedGroup = currentGroup.sorted { a, b in
                        if abs(a.boundingBox.midX - b.boundingBox.midX) < proximityThreshold {
                            return a.boundingBox.midY < b.boundingBox.midY
                        }
                        return a.boundingBox.midX > b.boundingBox.midX
                    }
                } else {
                    // Horizontal layout: sort top to bottom, then left to right
                    sortedGroup = currentGroup.sorted { a, b in
                        if abs(a.boundingBox.midY - b.boundingBox.midY) < proximityThreshold {
                            return a.boundingBox.midX < b.boundingBox.midX
                        }
                        return a.boundingBox.midY < b.boundingBox.midY
                    }
                }

                // Concatenate text
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

        // Check for vertical overlap (at least 20%)
        let overlapTop = max(box1.minY, box2.minY)
        let overlapBottom = min(box1.maxY, box2.maxY)
        let overlapHeight = max(0, overlapBottom - overlapTop)
        let minHeight = min(box1.height, box2.height)

        guard minHeight > 0 else { return false }
        return overlapHeight / minHeight >= 0.2
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

        // Check for horizontal overlap (at least 20%)
        let overlapLeft = max(box1.minX, box2.minX)
        let overlapRight = min(box1.maxX, box2.maxX)
        let overlapWidth = max(0, overlapRight - overlapLeft)
        let minWidth = min(box1.width, box2.width)

        guard minWidth > 0 else { return false }
        return overlapWidth / minWidth >= 0.2
    }

    // MARK: - Translation (called from view with TranslationSession)

    /// Start a new translation session
    func startTranslationSession() -> UUID {
        let sessionId = UUID()
        currentSessionId = sessionId
        isTranslating = true
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
    }

    func finishTranslation() {
        isProcessing = false
        isTranslating = false
        shouldTriggerTranslation = false
    }

    /// Cancel current session (called when user clears selection)
    func cancelSession() {
        currentSessionId = nil
        isTranslating = false
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
        isProcessing = true
        errorMessage = nil
        extractedTexts = []
        shouldTriggerTranslation = false

        // Use Azure AI Vision OCR
        let texts = await performAzureOCR(on: image)

        if texts.isEmpty {
            isProcessing = false
            if errorMessage == nil {
                errorMessage = "No Japanese text detected in the image"
            }
            return
        }

        extractedTexts = texts
        shouldTriggerTranslation = true
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

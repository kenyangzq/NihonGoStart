import Foundation
import Vision
import UIKit
import PDFKit

@MainActor
class ComicTranslationManager: ObservableObject {
    static let shared = ComicTranslationManager()

    @Published var isProcessing = false
    @Published var extractedTexts: [ExtractedText] = []
    @Published var errorMessage: String?
    @Published var shouldTriggerTranslation = false

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

        // Sort by position (top to bottom, right to left for manga reading order)
        let sortedResults = results.sorted { a, b in
            if abs(a.boundingBox.midY - b.boundingBox.midY) < 0.05 {
                return a.boundingBox.midX > b.boundingBox.midX
            }
            return a.boundingBox.minY < b.boundingBox.minY
        }

        return sortedResults
    }

    // MARK: - Translation (called from view with TranslationSession)

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
        shouldTriggerTranslation = false
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

# Manga OCR Integration Plan

**Date:** 2026-02-02
**Status:** Planned (not yet implemented)

## Overview

Integrate manga-ocr for better Japanese text recognition in manga/comic images. Uses a hybrid approach: Azure Computer Vision for text detection (bounding boxes) + Python backend with manga-ocr for text recognition.

## Architecture

```
iOS App → Azure Computer Vision (bounding boxes) → manga-ocr backend (text recognition) → Translation
```

**Why hybrid:**
- Azure OCR is good at detecting text regions but struggles with manga fonts and vertical text ordering
- manga-ocr is specialized for manga text but needs cropped regions (can't detect on its own)
- Combining both gives best results

## Part 1: Python Backend

### Files to Create

Create a new repo `manga-ocr-server` with these files:

**app.py**
```python
from fastapi import FastAPI, File, UploadFile
from manga_ocr import MangaOcr
from PIL import Image
import io

app = FastAPI()
mocr = MangaOcr()

@app.post("/ocr")
async def recognize_text(image: UploadFile = File(...)):
    contents = await image.read()
    img = Image.open(io.BytesIO(contents))
    text = mocr(img)
    return {"text": text}

@app.post("/ocr/batch")
async def recognize_batch(images: list[UploadFile] = File(...)):
    results = []
    for image in images:
        contents = await image.read()
        img = Image.open(io.BytesIO(contents))
        text = mocr(img)
        results.append({"text": text})
    return {"results": results}
```

**requirements.txt**
```
fastapi
uvicorn
manga-ocr
pillow
python-multipart
```

**Dockerfile**
```dockerfile
FROM python:3.10-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 8000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
```

### Deploy to Azure Container Apps

```bash
# 1. Create Container Registry
az acr create --resource-group NihonGoStart --name nihongostartacr --sku Basic
az acr login --name nihongostartacr

# 2. Build and push
docker build -t nihongostartacr.azurecr.io/manga-ocr-server:latest .
docker push nihongostartacr.azurecr.io/manga-ocr-server:latest

# 3. Create Container App
az containerapp create \
  --name manga-ocr-server \
  --resource-group NihonGoStart \
  --environment NihonGoStartEnv \
  --image nihongostartacr.azurecr.io/manga-ocr-server:latest \
  --target-port 8000 \
  --ingress external \
  --cpu 1 --memory 2Gi \
  --min-replicas 0 --max-replicas 1
```

**Cost:** ~$5-15/month with scale-to-zero

## Part 2: iOS App Changes

### Secrets.swift
Add:
```swift
static let mangaOCREndpoint = "https://manga-ocr-server.azurecontainerapps.io"
```

### ComicTranslationManager.swift

1. Add response struct:
```swift
struct MangaOCRResponse: Codable {
    let text: String
}
```

2. Add manga-ocr API call:
```swift
private func performMangaOCRRecognition(croppedImage: UIImage) async -> String? {
    guard let imageData = croppedImage.jpegData(compressionQuality: 0.9) else { return nil }

    let url = URL(string: "\(Secrets.mangaOCREndpoint)/ocr")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"

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
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(MangaOCRResponse.self, from: data)
        return response.text
    } catch {
        return nil // Fall back to Azure text
    }
}
```

3. Add image cropping helper:
```swift
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
```

4. Modify `parseAzureResponse` to use manga-ocr for each detected region (keep Azure text as fallback)

## Implementation Order

1. **Backend first:** Create repo, deploy to Azure, test with curl
2. **iOS integration:** Add endpoint, API call, modify parsing
3. **Testing:** Compare results with Azure-only approach

## Fallback Strategy

If manga-ocr backend is unavailable:
- Fall back to Azure's text (existing behavior)
- Cache results to avoid repeated failures

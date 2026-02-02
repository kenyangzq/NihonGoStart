# NihonGoStart

A Japanese language learning iOS app built with SwiftUI.

## Features

### Kana
- View hiragana and katakana character charts
- Organized by groups: basic, dakuon, handakuon, and combo characters

### Kana Practice
- Flashcard-style practice for hiragana and katakana
- Swipe to navigate between cards
- Tap to flip and reveal the romaji

### Vocabulary
- Flashcard practice for Japanese vocabulary
- Includes kanji, kana, romaji, and English translations
- Organized by JLPT levels (N5-N1)

### Phrases
- Common Japanese phrases with translations
- Categorized by situation (greetings, shopping, etc.)
- Audio pronunciation via text-to-speech

### Sentences
- Example sentences for learning grammar in context
- Organized by topic

### Grammar
- Grammar guide with explanations and examples
- Covers particles, verb forms, adjectives, and more
- Organized by JLPT level and category

### Songs
- Spotify integration for Japanese music
- Search and play Japanese songs for listening practice

### Comic Translation
- Upload manga/comic pages (images or PDFs)
- OCR extracts Japanese text using Azure AI Vision
- On-device translation to English or Chinese
- Overlay mode shows translations directly on the image
- Audio pronunciation for extracted text

## Setup

### Requirements
- iOS 17.4+ (for Translation framework)
- Xcode 15+

### API Keys

The Comic Translation feature requires an Azure AI Vision API key.

1. Create an Azure account at [portal.azure.com](https://portal.azure.com)
2. Create a "Computer Vision" resource
3. Get your API key and endpoint from "Keys and Endpoint"
4. Create `NihonGoStart/Secrets.swift` with:

```swift
import Foundation

enum Secrets {
    static let azureAPIKey = "YOUR_AZURE_API_KEY"
    static let azureEndpoint = "https://YOUR_RESOURCE.cognitiveservices.azure.com/"
}
```

**Note:** `Secrets.swift` is git-ignored to protect your API keys.

### Spotify Integration (Optional)

For the Songs feature, configure Spotify credentials in `SpotifyManager.swift`:
- Client ID
- Client Secret

## Project Structure

```
NihonGoStart/
├── NihonGoStartApp.swift      # App entry point
├── ContentView.swift          # Main tab container
├── DataModels.swift           # All data models
├── DataLoader.swift           # JSON data loading
├── SeedData.swift             # Data access layer
├── Secrets.swift              # API keys (git-ignored)
│
├── Views/
│   ├── KanaView.swift         # Kana charts
│   ├── KanaFlashcardView.swift
│   ├── FlashcardView.swift    # Vocabulary flashcards
│   ├── PhrasesView.swift
│   ├── SentencesView.swift
│   ├── GrammarView.swift
│   └── SongsView.swift
│
├── ComicTranslationView.swift     # Comic OCR & translation UI
├── ComicTranslationManager.swift  # Azure Vision & translation logic
├── SpeechManager.swift            # Text-to-speech
└── SpotifyManager.swift           # Spotify API integration
```

## Data Files

JSON data files in the project:
- `kana.json` - Hiragana & katakana characters
- `vocabulary.json` - Vocabulary words
- `phrases.json` - Common phrases
- `sentences.json` - Example sentences
- `grammar.json` - Grammar points

## License

Private project.

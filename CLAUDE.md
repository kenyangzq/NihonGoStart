# CLAUDE.md - NihonGoStart

## Project Overview

NihonGoStart is an iOS Japanese language learning app built with SwiftUI. It provides tools for learning kana, vocabulary, grammar, phrases, and sentences, plus advanced features for translating manga/comics and integrating with Spotify for Japanese music.

## Tech Stack

- **Platform:** iOS 17.4+
- **Language:** Swift 5 (Swift 6 concurrency compliant)
- **UI Framework:** SwiftUI
- **Build System:** Xcode 15+
- **Testing:** Swift Testing framework (`import Testing`)
- **Backend (optional):** Python FastAPI server for manga-ocr

## Project Structure

```
NihonGoStart/
├── NihonGoStart/                    # Main iOS app source
│   ├── App/                         # App entry points
│   │   ├── NihonGoStartApp.swift    # App entry point (@main), widget data sync
│   │   └── ContentView.swift        # Main tab container (Learn/Songs/Comic tabs)
│   │
│   ├── Models/                      # Data models
│   │   └── DataModels.swift         # All data models (VocabularyWord, GrammarPoint, etc.)
│   │
│   ├── Views/                       # UI views organized by feature
│   │   ├── Learning/                # Learning-related views
│   │   │   ├── KanaView.swift       # Hiragana/Katakana charts
│   │   │   ├── KanaFlashcardView.swift  # Kana practice flashcards
│   │   │   ├── FlashcardView.swift  # Vocabulary flashcards
│   │   │   ├── PhrasesView.swift    # Common phrases
│   │   │   ├── SentencesView.swift  # Example sentences
│   │   │   └── GrammarView.swift    # Grammar guide
│   │   ├── Comic/                   # Comic translation views
│   │   │   ├── ComicTranslationView.swift  # Manga OCR & translation UI + full screen mode
│   │   │   └── BookmarksView.swift  # Saved translations UI
│   │   ├── Songs/                   # Music/Apple Music views
│   │   │   └── SongsView.swift      # Apple Music integration UI (user auth, search, playback, lyrics)
│   │   └── SettingsView.swift       # Settings sheet (dev mode toggle)
│   │
│   ├── Managers/                    # Business logic & API clients
│   │   ├── AppSettings.swift        # App settings (dev mode toggle, persisted via UserDefaults)
│   │   ├── ComicTranslationManager.swift  # Azure Vision, OCR, translation logic
│   │   ├── BookmarksManager.swift   # Bookmarks persistence
│   │   ├── MusicManager.swift       # Apple Music integration with MusicKit (user auth, playback, library)
│   │   └── SpeechManager.swift      # Text-to-speech (Japanese)
│   │
│   ├── Shared/                      # Shared code between app and widget
│   │   └── WidgetDataProvider.swift  # Widget data sync, card generation, App Group storage
│   │
│   ├── Data/                        # Data loading utilities
│   │   ├── DataLoader.swift         # JSON data loading utilities
│   │   └── SeedData.swift           # Data access layer
│   │
│   ├── Resources/                   # Static data files
│   │   ├── kana.json                # Hiragana & katakana characters
│   │   ├── vocabulary.json          # Vocabulary words by JLPT level
│   │   ├── phrases.json             # Common phrases by category
│   │   ├── sentences.json           # Example sentences by topic
│   │   └── grammar.json             # Grammar points by level/category
│   │
│   ├── Secrets.swift                # API keys (git-ignored, must be created)
│   └── Assets.xcassets/             # App icons and colors
│
├── NihonGoStartWidget/              # Widget extension (WidgetKit)
│   ├── NihonGoStartWidget.swift     # Widget entry & views (FlashcardWidgetView)
│   ├── NihonGoStartWidgetBundle.swift # Widget bundle entry point (@main)
│   ├── AppIntent.swift              # AppIntents: config, timeline provider, interactive intents
│   └── Info.plist                   # Widget extension config
│
├── NihonGoStart.xcodeproj/          # Xcode project configuration
├── NihonGoStartTests/               # Unit tests
├── NihonGoStartUITests/             # UI tests
├── manga-ocr-server/                # Python backend for manga-ocr
│   ├── app.py                       # FastAPI server
│   ├── requirements.txt             # Python dependencies
│   └── Dockerfile                   # Container deployment
└── docs/                            # Documentation
```

## Build & Run

### Prerequisites
1. macOS with Xcode 15+
2. iOS 17.4+ device or simulator (required for Translation framework)

### Setup Steps
1. Open `NihonGoStart.xcodeproj` in Xcode
2. Create `NihonGoStart/Secrets.swift` (see API Keys section below)
3. Select target device/simulator
4. Build and run (Cmd+R)

### API Keys Setup

Create `NihonGoStart/Secrets.swift` with:

```swift
import Foundation

enum Secrets {
    // Required: Azure AI Vision (for Comic Translation OCR)
    static let azureAPIKey = "YOUR_AZURE_VISION_API_KEY"
    static let azureEndpoint = "https://YOUR_RESOURCE.cognitiveservices.azure.com/"

    // Optional: Azure Translator (fallback translation)
    static let azureTranslatorKey = ""
    static let azureTranslatorRegion = ""

    // Optional: Azure OpenAI (preferred translation)
    static let azureOpenAIEndpoint = ""
    static let azureOpenAIKey = ""
    static let azureOpenAIDeployment = "gpt-4o-mini"

    // Optional: Gemini API (fallback translation)
    static let geminiAPIKey = ""

    // Optional: manga-ocr backend URL
    static let mangaOCREndpoint = ""

    // Apple Music Kit (for Japanese music integration)
    // To enable Apple Music integration:
    // 1. Enroll in Apple Developer Program (https://developer.apple.com/programs/)
    // 2. Go to https://appstoreconnect.apple.com and create an app
    // 3. Go to https://developer.apple.com/account/resources/identifiers/list
    // 4. Create a MusicKit Key (Team ID, Key ID, and download .p8 private key)
    // 5. Copy the private key content (excluding header/footer) and base64 encode it
    //    Use: cat MusicKit.p8 | base64 | tr -d '\n'
    // 6. Fill in the values below:
    static let appleMusicTeamId = ""  // Your Apple Developer Team ID (10-character string)
    static let appleMusicKeyId = ""   // Your MusicKit Key ID (10-character string)
    static let appleMusicPrivateKey = "" // Base64-encoded content of your .p8 private key file
}
```

For Apple Music integration, credentials are stored in `Secrets.swift`.

## Architecture Patterns

### Singleton Managers
The app uses shared singleton managers for state management:
- `AppSettings.shared` - App settings (dev mode toggle, persisted via UserDefaults)
- `ComicTranslationManager.shared` - Comic translation state & API calls
- `BookmarksManager.shared` - Bookmarked translations persistence
- `MusicManager.shared` - Apple Music integration with MusicKit (search, playback)
- `SpeechManager.shared` - Text-to-speech (marked `@unchecked Sendable` for Swift 6)
- `WidgetDataProvider.shared` - Widget flashcard data sync via App Groups

All managers inherit from `ObservableObject` and use `@Published` properties for SwiftUI binding. Most use `@MainActor` for UI thread safety.

### Data Flow
```
JSON Files → DataLoader → SeedData → Views
JSON Files → WidgetDataProvider → App Group UserDefaults → Widget
```

### View Structure
- `ContentView` manages main tabs (Learn/Songs/Comic)
- Learn tab has sub-tabs managed by `LearnSubTab` enum
- Each view is self-contained with its own state

### Async/Await
Network calls use Swift async/await with `@MainActor` for UI updates.

## Key Features Implementation

### Comic Translation Pipeline
1. User uploads image/PDF (up to 20 images at once)
2. Azure AI Vision detects text regions (bounding boxes)
3. (Optional) manga-ocr backend enhances text recognition
4. Text merging algorithm groups nearby text blocks
5. Translation via Azure OpenAI → Gemini → Azure Translator (fallback chain)
6. Results cached per image hash for performance
7. **Smart prefetching**: Only processes up to 3 images at a time (current + next 2)
8. **No-text caching**: Images with no detected Japanese text are cached to avoid re-processing

### Comic Full Screen Mode
- Enter via expand button in comic controls bar
- Full-screen immersive view with black background
- Swipe left/right to navigate between images (when not zoomed)
- Pinch to zoom (1x-5x) and pan when zoomed
- Double-tap to toggle between 1x and 2.5x zoom
- Single tap to show/hide navigation controls
- Translation overlay supported in full screen
- Implemented in `FullScreenComicView` within `ComicTranslationView.swift`

### Comic Session Management
- **Merge Sessions**: Combine multiple saved sessions into one larger session
  - Access via "Merge" button in saved sessions section (when 2+ sessions exist)
  - Select multiple sessions to merge, combined in chronological order
  - Useful for combining chapters or volumes
- **Reorder Images**: Rearrange images/pages within a session
  - Access via "Reorder" button in controls bar (when 2+ images exist)
  - Use up/down arrows to move individual images
  - Clears translation cache after reordering to ensure correct indexing
- **Image Upload Limit**: Up to 20 images per session (increased from 9)
- **Smart Background Processing**: Only prefetches up to 3 images total (current + next 2) to save resources
- **No-Text Detection**: Images without Japanese text are cached and skipped on subsequent views

### Widget (WidgetKit)
- Home screen widget showing Japanese flashcards
- User configurable card type: Kana, Vocabulary, or Phrase
- Auto-updates every hour with a new random card
- Interactive buttons: Reveal/Hide meaning toggle and Next card swap (via `AppIntent`)
- Small widget: shows card front with icon-only Reveal and Next buttons (no text labels)
- Medium widget: shows card front on left, meaning (or `?` placeholder) on right, with labeled Reveal/Hide and Next buttons
- Uses `AppIntentConfiguration` for user card type selection
- `WidgetDataProvider.updateCardTypeIfNeeded(_:)` prevents card regeneration on every timeline reload (only regenerates when card type actually changes, directly updates UserDefaults to avoid triggering unwanted card swaps via setter)
- Data shared via App Groups (`group.ziqiyang.NihonGoStart`)
- `WidgetDataProvider` syncs JSON data from main app to widget storage
- App syncs data on launch via `NihonGoStartApp.onAppear`
- **Bug fix:** Reveal/Hide button now only toggles meaning visibility without advancing to next card (fixed by avoiding `selectedCardType` setter in `updateCardTypeIfNeeded`)

### Apple Music Integration with MusicKit
The Songs feature integrates with Apple Music using the native MusicKit framework:

#### MusicKit Features
- **Search**: Catalog search via MusicKit API or REST API fallback
- **Developer Token**: JWT generated from MusicKit credentials for catalog operations
- **Playback**:
  - Preview playback (30-second clips) via AVPlayer - works for all users
  - Full track playback via ApplicationMusicPlayer - requires Apple Music subscription
- **Lyrics**: API fetch via REST endpoint with TTML parsing for synchronized lyrics
- **Add to Library**: Opens in Apple Music app for manual library addition

#### Key Implementation Details
- `MusicManager` is `@MainActor` for UI thread safety
- Developer token valid for 6 months (auto-generated on app launch from credentials)
- Catalog search works for all users (no subscription or login required)
- Preview playback (30-second clips) available for all tracks
- Full playback requires Apple Music subscription and user authorization
- Simplified authorization flow - uses MusicKit's built-in authorization when needed

### Dev Mode
- Settings accessible via gear icon (top-right corner of main view)
- Toggle enables/disables Songs and Comic tabs (dev features)
- Default: off (only Learn tab visible, main tab bar hidden)
- Preference persisted via UserDefaults (`devModeEnabled` key)
- Auto-resets to Learn tab when dev mode is turned off while on a dev-only tab
- `AppSettings.shared` provides `visibleTabs` computed property used by `MainTabBar`
- In user mode, `LearnSubTabBar` handles bottom safe area padding (since main tab bar is hidden)

### Session Persistence
- Comic sessions saved to Documents/ComicSessions/
- Translation cache persisted across app restarts
- Cache includes `hasNoText` flag to skip re-processing images without Japanese text
- Bookmarks stored in UserDefaults
- Widget card data stored in App Group UserDefaults

## Testing

### Running Tests
```bash
# Open Xcode and run tests with Cmd+U
# Or via command line:
xcodebuild test -scheme NihonGoStart -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Test Files
- `NihonGoStartTests/` - Unit tests using Swift Testing
- `NihonGoStartUITests/` - UI automation tests

## External Dependencies

### Required APIs
- **Azure AI Vision** - OCR for comic text detection

### Optional APIs (enhance functionality)
- **Azure OpenAI** - Best translation quality
- **Google Gemini** - Translation fallback
- **Azure Translator** - Translation fallback
- **Apple MusicKit** - Music search, playback, and library (requires Apple Developer account)
- **Jisho API** - Dictionary lookups

### Python Backend (Optional)
The `manga-ocr-server/` provides specialized manga text recognition:
```bash
# Run locally
cd manga-ocr-server
pip install -r requirements.txt
uvicorn app:app --host 0.0.0.0 --port 8000

# Or with Docker
docker build -t manga-ocr-server .
docker run -p 8000:8000 manga-ocr-server
```

## Code Conventions

### Swift Style
- Use Swift's native async/await for asynchronous code
- Prefer `@MainActor` classes for UI-bound managers
- Use `guard` for early returns
- Enums with associated values for type-safe state
- **Swift 6 Concurrency**: Mark classes as `@unchecked Sendable` when using non-Sendable types that are safe (e.g., `SpeechManager` uses `AVSpeechSynthesizer` which isn't Sendable but is safe to use from main actor)
- Use `nonisolated` + `Task { @MainActor in }` pattern for delegate methods that update `@Published` properties

### SwiftUI Patterns
- `@Published` properties in ObservableObject for reactive state
- `@State` for view-local state
- `@Binding` for child view state propagation
- Use `.task {}` modifier for async work on view appear

### File Naming & Organization
- Views: `*View.swift` in `Views/` subfolders (e.g., `Views/Learning/KanaView.swift`)
- Managers: `*Manager.swift` in `Managers/` (e.g., `Managers/BookmarksManager.swift`)
- Data models: `Models/DataModels.swift` (centralized)
- JSON data: `Resources/*.json`
- App entry: `App/` folder for app-level files

### JSON Data Format
All JSON files use arrays of objects with string keys matching Codable struct properties. UUIDs are auto-generated on decode (not stored in JSON).

### Documentation
- **Always update CLAUDE.md** after making any code changes that affect:
  - Architecture or file structure
  - New features or functionality
  - API changes or new dependencies
  - Bug fixes or behavior changes
  - Configuration or setup instructions
- Keep CLAUDE.md as the single source of truth for project understanding
- Update relevant sections immediately when implementing features

## Common Tasks

### Adding a New Learning Category
1. Add data model to `Models/DataModels.swift`
2. Create JSON file in `Resources/` folder
3. Add loader function to `Data/DataLoader.swift`
4. Create new View file in `Views/Learning/`
5. Add to `LearnSubTab` enum in `App/ContentView.swift`

### Adding a New Translation Provider
1. Add API key to `Secrets.swift`
2. Add translation method to `Managers/ComicTranslationManager.swift`
3. Update `translateWithGemini()` fallback chain

### Modifying OCR Behavior
Key functions in `Managers/ComicTranslationManager.swift`:
- `performAzureOCR()` - Azure Vision API call
- `mergeNearbyTextBlocks()` - Text grouping algorithm
- `enhanceWithMangaOCR()` - manga-ocr integration

### Modifying Widget
- Widget views: `NihonGoStartWidget/NihonGoStartWidget.swift`
- Widget bundle: `NihonGoStartWidget/NihonGoStartWidgetBundle.swift`
- Intents & timeline provider: `NihonGoStartWidget/AppIntent.swift` (includes `FlashcardConfigurationIntent`, `ConfigurableFlashcardProvider`, `SwapCardIntent`, `RevealMeaningIntent`)
- Data provider (shared): `NihonGoStart/Shared/WidgetDataProvider.swift`
- To add new card types: update `WidgetCardType` enum and add generator in `WidgetDataProvider`
- To add new interactive buttons: create a new `AppIntent` struct in `AppIntent.swift` and add a `Button(intent:)` in the widget view

### Setting Up Apple Music Integration
1. **Enroll in Apple Developer Program**: https://developer.apple.com/programs/
2. **Create an App in App Store Connect**: https://appstoreconnect.apple.com
3. **Create MusicKit Key**:
   - Go to https://developer.apple.com/account/resources/identifiers/list
   - Create a MusicKit Key (Team ID, Key ID, and download .p8 private key)
   - **Important**: Save the .p8 file - you can only download it once!
4. **Encode Private Key**:
   ```bash
   cat MusicKit.p8 | base64 | tr -d '\n'
   ```
5. **Add Credentials to Secrets.swift**:
   ```swift
   static let appleMusicTeamId = "YOUR_TEAM_ID"  // 10-character string
   static let appleMusicKeyId = "YOUR_KEY_ID"   // 10-character string
   static let appleMusicPrivateKey = "BASE64_ENCODED_PRIVATE_KEY"
   ```
6. **Enable MusicKit Capability in Xcode**:
   - Select your app target
   - Signing & Capabilities → + Capability → MusicKit

#### Testing Apple Music Integration
- **Without credentials**: Shows setup message, no functionality
- **With credentials**: Catalog search and preview playback work
- **With subscription**: Full track playback available
- Test with free Apple ID: Preview playback only
- Test with subscription: Full playback

### Widget Setup (Xcode)
The widget extension target must be added in Xcode:
1. File → New → Target → Widget Extension
2. Name: `NihonGoStartWidget`, bundle ID: `ziqiyang.NihonGoStart.Widget`
3. Enable App Groups capability on both main app and widget targets
4. App Group ID: `group.ziqiyang.NihonGoStart`
5. Add `Shared/WidgetDataProvider.swift` to both targets
6. Add JSON resource files (`kana.json`, `vocabulary.json`, `phrases.json`) to widget target

## Git Workflow

### Ignored Files
- `Secrets.swift` - Contains API keys
- `xcuserdata/` - Xcode user settings
- `DerivedData/` - Build artifacts
- `.claude/` - Claude memory files

### Branch Strategy
Work on feature branches, merge to main via PR.

## Troubleshooting

### "No Japanese text detected"
- Ensure image has clear, readable text
- Azure Vision works best with high-contrast images
- manga-ocr backend improves recognition for manga fonts
- **Note**: Images with no detected text are cached. To re-process, use the "Retry" button which clears the cache for that image

### Translation Not Working
1. Check Secrets.swift has valid API keys
2. Verify network connectivity
3. Check console for API error messages
4. Fallback chain: Azure OpenAI → Gemini → Azure Translator → Apple Translation

### Build Errors
- Ensure iOS 17.4+ deployment target (required for Translation framework)
- Clean build folder (Cmd+Shift+K) if experiencing stale cache issues

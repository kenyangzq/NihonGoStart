//
//  AppIntent.swift
//  NihonGoStartWidget
//
//  Created by Ken Yang on 2/7/26.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Widget Card Type for AppIntents

enum WidgetCardTypeIntent: String, AppEnum {
    case kana = "kana"
    case word = "word"
    case phrase = "phrase"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Card Type"
    static var caseDisplayRepresentations: [WidgetCardTypeIntent: DisplayRepresentation] = [
        .kana: "Kana",
        .word: "Vocabulary",
        .phrase: "Phrase"
    ]
}

// MARK: - Configuration Intent

struct FlashcardConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Flashcard Settings"
    static var description: IntentDescription = "Choose what type of flashcard to display"

    @Parameter(title: "Card Type", default: .kana)
    var cardType: WidgetCardTypeIntent
}

// MARK: - Configurable Timeline Provider

struct ConfigurableFlashcardProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FlashcardEntry {
        FlashcardEntry(
            date: Date(),
            card: WidgetFlashcard(
                front: "あ",
                subtitle: "",
                back: "a",
                category: "Hiragana - Basic",
                cardType: .kana
            ),
            cardType: .kana,
            showMeaning: false
        )
    }

    func snapshot(for configuration: FlashcardConfigurationIntent, in context: Context) async -> FlashcardEntry {
        let widgetType = mapIntentType(configuration.cardType)
        let provider = WidgetDataProvider.shared
        provider.updateCardTypeIfNeeded(widgetType)
        let card = provider.getCurrentCard()
        let showMeaning = provider.showMeaning
        return FlashcardEntry(date: Date(), card: card, cardType: widgetType, showMeaning: showMeaning)
    }

    func timeline(for configuration: FlashcardConfigurationIntent, in context: Context) async -> Timeline<FlashcardEntry> {
        let widgetType = mapIntentType(configuration.cardType)
        let provider = WidgetDataProvider.shared
        provider.updateCardTypeIfNeeded(widgetType)

        let now = Date()
        let showMeaning = provider.showMeaning
        let currentCard = provider.getCurrentCard()

        // Only show the current card for now; future hourly entries will
        // be generated when the timeline refreshes (avoiding double-swap).
        let entry = FlashcardEntry(
            date: now,
            card: currentCard,
            cardType: widgetType,
            showMeaning: showMeaning
        )

        let refreshDate = Calendar.current.date(byAdding: .hour, value: 1, to: now)!
        return Timeline(entries: [entry], policy: .after(refreshDate))
    }

    private func mapIntentType(_ intentType: WidgetCardTypeIntent) -> WidgetCardType {
        switch intentType {
        case .kana: return .kana
        case .word: return .word
        case .phrase: return .phrase
        }
    }
}

// MARK: - Swap Card Intent (Interactive Button)

struct SwapCardIntent: AppIntent {
    static var title: LocalizedStringResource = "Swap Flashcard"
    static var description: IntentDescription = "Show a different flashcard"

    func perform() async throws -> some IntentResult {
        let provider = WidgetDataProvider.shared
        provider.showMeaning = false  // Reset reveal state when swapping
        _ = provider.swapToNextCard()
        provider.synchronize()
        WidgetCenter.shared.reloadTimelines(ofKind: "NihonGoStartConfigurableWidget")
        return .result()
    }
}

// MARK: - Reveal Meaning Intent (Interactive Button)

struct RevealMeaningIntent: AppIntent {
    static var title: LocalizedStringResource = "Reveal Meaning"
    static var description: IntentDescription = "Toggle showing the meaning of the flashcard"

    func perform() async throws -> some IntentResult {
        let provider = WidgetDataProvider.shared
        _ = provider.toggleShowMeaning()
        provider.synchronize()
        WidgetCenter.shared.reloadTimelines(ofKind: "NihonGoStartConfigurableWidget")
        return .result()
    }
}

// MARK: - Configurable Widget

struct NihonGoStartConfigurableWidget: Widget {
    let kind: String = "NihonGoStartConfigurableWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: FlashcardConfigurationIntent.self,
            provider: ConfigurableFlashcardProvider()
        ) { entry in
            FlashcardWidgetView(entry: entry)
        }
        .configurationDisplayName("Japanese Flashcard")
        .description("Learn Japanese with hourly flashcards. Choose Kana, Vocabulary, or Phrases.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

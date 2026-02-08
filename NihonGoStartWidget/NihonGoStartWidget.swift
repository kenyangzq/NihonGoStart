//
//  NihonGoStartWidget.swift
//  NihonGoStartWidget
//
//  Created by Ken Yang on 2/7/26.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Widget Entry

struct FlashcardEntry: TimelineEntry {
    let date: Date
    let card: WidgetFlashcard
    let cardType: WidgetCardType
    let showMeaning: Bool
}

// MARK: - Widget View

struct FlashcardWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: FlashcardEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallWidget
        case .systemMedium:
            mediumWidget
        default:
            smallWidget
        }
    }

    // MARK: - Small Widget

    private var smallWidget: some View {
        VStack(spacing: 4) {
            Spacer()

            if entry.showMeaning {
                // Revealed state: show meaning
                Text(entry.card.front)
                    .font(frontFontSmall)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                if !entry.card.subtitle.isEmpty {
                    Text(entry.card.subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Text(entry.card.back)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                    .minimumScaleFactor(0.5)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
            } else {
                // Front state: show card
                Text(entry.card.front)
                    .font(frontFont)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if !entry.card.subtitle.isEmpty {
                    Text(entry.card.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Category label
            Text(entry.card.category)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)

            // Single interactive button (small widgets support one tap zone)
            // Unrevealed → tap to reveal; Revealed → tap to go to next card
            if entry.showMeaning {
                Button(intent: SwapCardIntent()) {
                    HStack(spacing: 4) {
                        Text("Next")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Button(intent: RevealMeaningIntent()) {
                    HStack(spacing: 4) {
                        Image(systemName: "eye")
                            .font(.system(size: 12))
                        Text("Reveal")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: - Medium Widget

    private var mediumWidget: some View {
        HStack(spacing: 12) {
            // Left: Card content
            VStack(spacing: 4) {
                Spacer()

                Text(entry.card.front)
                    .font(frontFont)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if !entry.card.subtitle.isEmpty {
                    Text(entry.card.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(entry.card.category)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            // Divider
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 1)

            // Right: Meaning or tap to reveal
            VStack(spacing: 8) {
                Spacer()

                if entry.showMeaning {
                    Text(entry.card.back)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                        .minimumScaleFactor(0.5)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                } else {
                    Image(systemName: "questionmark.circle")
                        .font(.title)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Buttons
                HStack(spacing: 8) {
                    Button(intent: RevealMeaningIntent()) {
                        HStack(spacing: 4) {
                            Image(systemName: entry.showMeaning ? "eye.slash" : "eye")
                                .font(.system(size: 13))
                            Text(entry.showMeaning ? "Hide" : "Reveal")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button(intent: SwapCardIntent()) {
                        HStack(spacing: 4) {
                            Text("Next")
                                .font(.system(size: 13, weight: .medium))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13))
                        }
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: - Helpers

    private var frontFont: Font {
        switch entry.cardType {
        case .kana:
            return .system(size: 48)
        case .word:
            return .system(size: 32)
        case .phrase:
            return .system(size: 18)
        }
    }

    private var frontFontSmall: Font {
        switch entry.cardType {
        case .kana:
            return .system(size: 28)
        case .word:
            return .system(size: 22)
        case .phrase:
            return .system(size: 14)
        }
    }
}

// MARK: - Preview

struct NihonGoStartWidget_Previews: PreviewProvider {
    static var previews: some View {
        FlashcardWidgetView(entry: FlashcardEntry(
            date: .now,
            card: WidgetFlashcard(
                front: "あ",
                subtitle: "",
                back: "a",
                category: "Hiragana - Basic",
                cardType: .kana
            ),
            cardType: .kana,
            showMeaning: false
        ))
        .previewContext(WidgetPreviewContext(family: .systemSmall))

        FlashcardWidgetView(entry: FlashcardEntry(
            date: .now,
            card: WidgetFlashcard(
                front: "食べる",
                subtitle: "たべる",
                back: "to eat",
                category: "N5 - Verb",
                cardType: .word
            ),
            cardType: .word,
            showMeaning: true
        ))
        .previewContext(WidgetPreviewContext(family: .systemMedium))
    }
}

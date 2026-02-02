import SwiftUI
import AVFoundation

struct KanaView: View {
    @State private var selectedType: KanaType = .hiragana
    @State private var allKana = SeedData.kana

    private let vowels = ["a", "i", "u", "e", "o"]

    // Basic rows
    private let basicRows = ["vowel", "k", "s", "t", "n", "h", "m", "y", "r", "w", "special"]
    private let basicRowLabels = ["", "K", "S", "T", "N", "H", "M", "Y", "R", "W", ""]

    // Dakuon rows
    private let dakuonRows = ["g", "z", "d", "b"]
    private let dakuonRowLabels = ["G", "Z", "D", "B"]

    // Handakuon rows
    private let handakuonRows = ["p"]
    private let handakuonRowLabels = ["P"]

    // Combo rows
    private let comboRows = ["ky", "sh", "ch", "ny", "hy", "my", "ry", "gy", "j", "by", "py"]
    private let comboRowLabels = ["KY", "SH", "CH", "NY", "HY", "MY", "RY", "GY", "J", "BY", "PY"]
    private let comboVowels = ["a", "u", "o"]

    var filteredKana: [KanaCharacter] {
        allKana.filter { $0.type == selectedType }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Type", selection: $selectedType) {
                    ForEach(KanaType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                ScrollView {
                    VStack(spacing: 20) {
                        // Basic Section
                        KanaSectionView(
                            title: "Basic",
                            subtitle: "Gojuon (五十音)",
                            rows: basicRows,
                            rowLabels: basicRowLabels,
                            vowels: vowels,
                            characters: filteredKana.filter { $0.group == .basic },
                            color: .red
                        )

                        // Dakuon Section
                        KanaSectionView(
                            title: "Dakuon",
                            subtitle: "濁音 (Voiced)",
                            rows: dakuonRows,
                            rowLabels: dakuonRowLabels,
                            vowels: vowels,
                            characters: filteredKana.filter { $0.group == .dakuon },
                            color: .blue
                        )

                        // Handakuon Section
                        KanaSectionView(
                            title: "Handakuon",
                            subtitle: "半濁音 (Semi-voiced)",
                            rows: handakuonRows,
                            rowLabels: handakuonRowLabels,
                            vowels: vowels,
                            characters: filteredKana.filter { $0.group == .handakuon },
                            color: .purple
                        )

                        // Combo Section
                        KanaSectionView(
                            title: "Combo",
                            subtitle: "拗音 (Contracted)",
                            rows: comboRows,
                            rowLabels: comboRowLabels,
                            vowels: comboVowels,
                            characters: filteredKana.filter { $0.group == .combo },
                            color: .orange
                        )
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle(selectedType.displayName)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct KanaSectionView: View {
    let title: String
    let subtitle: String
    let rows: [String]
    let rowLabels: [String]
    let vowels: [String]
    let characters: [KanaCharacter]
    let color: Color

    var body: some View {
        VStack(spacing: 12) {
            // Section Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(color)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("\(characters.count)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(color))
            }
            .padding(.horizontal)

            // Header row with vowels
            HStack(spacing: 8) {
                Text("")
                    .frame(width: 30)
                ForEach(vowels, id: \.self) { vowel in
                    Text(vowel.uppercased())
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .frame(width: 55)
                }
            }
            .padding(.horizontal)

            // Character rows
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                KanaRowView(
                    rowLabel: rowLabels[index],
                    characters: characters.filter { $0.row == row },
                    vowels: vowels,
                    accentColor: color
                )
            }
        }
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemBackground).opacity(0.5))
        )
        .padding(.horizontal, 8)
    }
}

struct KanaRowView: View {
    let rowLabel: String
    let characters: [KanaCharacter]
    let vowels: [String]
    var accentColor: Color = .red
    private let speechManager = SpeechManager.shared

    var body: some View {
        HStack(spacing: 8) {
            Text(rowLabel)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(width: 30)

            ForEach(vowels, id: \.self) { vowel in
                if let kana = findKana(forVowel: vowel) {
                    KanaCell(character: kana, speechManager: speechManager, accentColor: accentColor)
                } else {
                    Text("")
                        .frame(width: 55, height: 55)
                }
            }
        }
        .padding(.horizontal)
    }

    func findKana(forVowel vowel: String) -> KanaCharacter? {
        characters.first { char in
            char.romaji.hasSuffix(vowel) || char.romaji == vowel || char.romaji == "n"
        }
    }
}

struct KanaCell: View {
    let character: KanaCharacter
    let speechManager: SpeechManager
    var accentColor: Color = .red
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
            speechManager.speak(character.character, rate: 0.7)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = false
                }
            }
        }) {
            VStack(spacing: 2) {
                Text(character.character)
                    .font(.system(size: 24))
                    .fontWeight(.medium)
                Text(character.romaji)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .frame(width: 55, height: 55)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isPressed ? accentColor.opacity(0.2) : Color(UIColor.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(accentColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

import SwiftUI
import AVFoundation

struct KanaFlashcardView: View {
    @State private var selectedType: KanaType = .hiragana
    @State private var selectedGroup: KanaGroup = .basic
    @State private var allKana = SeedData.kana
    @State private var filteredKana: [KanaCharacter] = []

    @State private var currentIndex = 0
    @State private var isFlipped = false
    @State private var dragOffset = CGSize.zero

    var body: some View {
        VStack {
            // Type picker (Hiragana/Katakana)
            Picker("Type", selection: $selectedType) {
                ForEach(KanaType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top)
            .onChange(of: selectedType) {
                resetDeck()
            }

            // Group picker (Basic/Dakuon/Handakuon/Combo)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(KanaGroup.allCases) { group in
                        GroupChip(
                            title: group.displayName,
                            isSelected: selectedGroup == group,
                            action: {
                                selectedGroup = group
                                resetDeck()
                            }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            Spacer()

            if !filteredKana.isEmpty && currentIndex < filteredKana.count {
                ZStack {
                    // Background cards
                    ForEach(0..<2) { i in
                        if currentIndex + i + 1 < filteredKana.count {
                            KanaCardView(kana: filteredKana[currentIndex + i + 1], isFlipped: false)
                                .offset(y: CGFloat(i * 10))
                                .scaleEffect(1 - CGFloat(i) * 0.05)
                                .opacity(0.5)
                        }
                    }

                    // Active Card
                    KanaCardView(kana: filteredKana[currentIndex], isFlipped: isFlipped)
                        .offset(x: dragOffset.width, y: dragOffset.height * 0.2)
                        .rotationEffect(.degrees(Double(dragOffset.width / 20)))
                        .gesture(
                            DragGesture()
                                .onChanged { gesture in
                                    dragOffset = gesture.translation
                                }
                                .onEnded { gesture in
                                    if abs(gesture.translation.width) > 100 {
                                        dismissCard(direction: gesture.translation.width > 0 ? 1 : -1)
                                    } else {
                                        withAnimation(.spring()) {
                                            dragOffset = .zero
                                        }
                                    }
                                }
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isFlipped.toggle()
                            }
                        }
                }

                // Navigation buttons
                HStack(spacing: 40) {
                    Button(action: {
                        dismissCard(direction: -1)
                    }) {
                        Image(systemName: "arrow.left.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.red.opacity(0.8))
                    }

                    Button(action: {
                        dismissCard(direction: 1)
                    }) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.red.opacity(0.8))
                    }
                }
                .padding(.top, 20)
            } else {
                VStack(spacing: 20) {
                    Text(filteredKana.isEmpty ? "No characters found" : "🎉")
                        .font(.system(size: 80))

                    Text(filteredKana.isEmpty ? "Try another type" : "Practice Complete!")
                        .font(.title)

                    Button("Restart Practice") {
                        resetDeck()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }

            Spacer()

            HStack {
                Text("\(currentIndex) / \(filteredKana.count)")
                    .font(.caption)
                    .bold()
                    .foregroundColor(.secondary)
            }
            .padding(.bottom)
        }
        .onAppear {
            resetDeck()
        }
    }

    func dismissCard(direction: CGFloat) {
        withAnimation(.easeOut(duration: 0.2)) {
            dragOffset.width = direction > 0 ? 500 : -500
        }
        // Immediately update the index without delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            currentIndex += 1
            dragOffset = .zero
            isFlipped = false
        }
    }

    func resetDeck() {
        filteredKana = allKana.filter { $0.type == selectedType && $0.group == selectedGroup }.shuffled()
        currentIndex = 0
        isFlipped = false
        dragOffset = .zero
    }
}

struct GroupChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.red : Color(UIColor.secondarySystemBackground))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.red.opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct KanaCardView: View {
    let kana: KanaCharacter
    let isFlipped: Bool
    private let speechManager = SpeechManager.shared

    var groupColor: Color {
        switch kana.group {
        case .basic: return .red
        case .dakuon: return .blue
        case .handakuon: return .purple
        case .combo: return .orange
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: .gray.opacity(0.4), radius: 10, x: 0, y: 5)

            VStack(spacing: 20) {
                if !isFlipped {
                    // Front - show character
                    Text(kana.character)
                        .font(.system(size: 120))
                        .fontWeight(.medium)

                    HStack(spacing: 8) {
                        Text(kana.type == .hiragana ? "Hiragana" : "Katakana")
                            .font(.caption)
                            .fontWeight(.black)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.red))

                        Text(kana.group.displayName)
                            .font(.caption)
                            .fontWeight(.black)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(groupColor))
                    }
                    .padding(.top, 10)

                    Button(action: {
                        speechManager.speak(kana.character, rate: 0.7)
                    }) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Circle().fill(Color.red))
                    }
                    .padding(.top, 20)
                } else {
                    // Back - show romaji
                    Text(kana.romaji.uppercased())
                        .font(.system(size: 80))
                        .fontWeight(.bold)
                        .foregroundColor(groupColor)

                    Text(kana.character)
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)

                    Button(action: {
                        speechManager.speak(kana.character, rate: 0.7)
                    }) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Circle().fill(Color.red))
                    }
                    .padding(.top, 20)
                }
            }
            .padding()
        }
        .frame(width: 320, height: 480)
    }
}

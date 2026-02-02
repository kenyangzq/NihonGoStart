import SwiftUI
import AVFoundation

struct FlashcardView: View {
    // Start with N5
    @State private var selectedLevel: DifficultyLevel = .n5
    @State private var allWords = SeedData.vocabulary
    @State private var filteredWords: [VocabularyWord] = []

    @State private var currentIndex = 0
    @State private var isFlipped = false
    @State private var dragOffset = CGSize.zero

    var body: some View {
        VStack {
            // Level Selector
            Picker("Level", selection: $selectedLevel) {
                ForEach(DifficultyLevel.allCases) { level in
                    Text(level.label).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            .onChange(of: selectedLevel) { _ in
                resetDeck()
            }

            Spacer()

            if !filteredWords.isEmpty && currentIndex < filteredWords.count {
                ZStack {
                    // Background cards
                    ForEach(0..<2) { i in
                        if currentIndex + i + 1 < filteredWords.count {
                            CardView(word: filteredWords[currentIndex + i + 1], isFlipped: false)
                                .offset(y: CGFloat(i * 10))
                                .scaleEffect(1 - CGFloat(i) * 0.05)
                                .opacity(0.5)
                        }
                    }

                    // Active Card
                    CardView(word: filteredWords[currentIndex], isFlipped: isFlipped)
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
                                        // Snap back
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
                    Text(filteredWords.isEmpty ? "No words found" : "🎉")
                        .font(.system(size: 80))

                    Text(filteredWords.isEmpty ? "Try another level" : "Level Complete!")
                        .font(.title)

                    Button("Restart Level") {
                        resetDeck()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }

            Spacer()

            HStack {
                Text("\(currentIndex) / \(filteredWords.count)")
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
        // Reduced delay for faster card transitions
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            currentIndex += 1
            dragOffset = .zero
            isFlipped = false
        }
    }

    func resetDeck() {
        // Filter words by the selected level
        filteredWords = allWords.filter { $0.level == selectedLevel }.shuffled()
        currentIndex = 0
        isFlipped = false
        dragOffset = .zero
    }
}

struct CardView: View {
    let word: VocabularyWord
    let isFlipped: Bool
    private let speechManager = SpeechManager.shared

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: .gray.opacity(0.4), radius: 10, x: 0, y: 5)

            VStack(spacing: 15) {
                // Front (Japanese)
                if !isFlipped {
                    Text(word.kanji)
                        .font(.system(size: 60))
                        .bold()
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal)

                    if word.kanji != word.kana {
                        Text(word.kana)
                            .font(.title)
                            .foregroundColor(.gray)
                    }

                    Text(word.category.uppercased())
                        .font(.caption)
                        .fontWeight(.black)
                        .foregroundColor(.blue.opacity(0.7))
                        .padding(.top, 20)

                    // Speaker button
                    Button(action: {
                        speechManager.speak(word.kana)
                    }) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Circle().fill(Color.red))
                    }
                    .padding(.top, 20)
                }
                // Back (English)
                else {
                    Text(word.english)
                        .font(.largeTitle)
                        .bold()
                        .foregroundColor(.blue)
                        .multilineTextAlignment(.center)
                        .padding()

                    Text(word.romaji)
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .italic()

                    // Speaker button on back side too
                    Button(action: {
                        speechManager.speak(word.kana)
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

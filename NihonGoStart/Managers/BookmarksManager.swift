import Foundation
import SwiftUI

@MainActor
class BookmarksManager: ObservableObject {
    static let shared = BookmarksManager()

    @Published var bookmarks: [BookmarkedText] = []

    private let bookmarksKey = "savedBookmarks"

    private init() {
        loadBookmarks()
    }

    // MARK: - Public Methods

    func addBookmark(japanese: String, translation: String, targetLanguage: String, note: String? = nil) {
        // Check if already bookmarked (same Japanese text)
        guard !isBookmarked(japanese: japanese) else { return }

        let bookmark = BookmarkedText(
            japanese: japanese,
            translation: translation,
            targetLanguage: targetLanguage,
            note: note
        )
        bookmarks.insert(bookmark, at: 0)  // Add to beginning
        saveBookmarks()
    }

    func removeBookmark(_ bookmark: BookmarkedText) {
        bookmarks.removeAll { $0.id == bookmark.id }
        saveBookmarks()
    }

    func removeBookmark(japanese: String) {
        bookmarks.removeAll { $0.japanese == japanese }
        saveBookmarks()
    }

    func isBookmarked(japanese: String) -> Bool {
        bookmarks.contains { $0.japanese == japanese }
    }

    func toggleBookmark(japanese: String, translation: String, targetLanguage: String) {
        if isBookmarked(japanese: japanese) {
            removeBookmark(japanese: japanese)
        } else {
            addBookmark(japanese: japanese, translation: translation, targetLanguage: targetLanguage)
        }
    }

    func updateNote(for bookmark: BookmarkedText, note: String?) {
        if let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks[index].note = note
            saveBookmarks()
        }
    }

    func clearAllBookmarks() {
        bookmarks.removeAll()
        saveBookmarks()
    }

    // MARK: - Persistence

    private func saveBookmarks() {
        do {
            let data = try JSONEncoder().encode(bookmarks)
            UserDefaults.standard.set(data, forKey: bookmarksKey)
        } catch {
            print("Failed to save bookmarks: \(error)")
        }
    }

    private func loadBookmarks() {
        guard let data = UserDefaults.standard.data(forKey: bookmarksKey) else { return }
        do {
            bookmarks = try JSONDecoder().decode([BookmarkedText].self, from: data)
        } catch {
            print("Failed to load bookmarks: \(error)")
        }
    }
}

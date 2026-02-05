import SwiftUI

struct BookmarksView: View {
    @StateObject private var bookmarksManager = BookmarksManager.shared
    @StateObject private var speechManager = SpeechManager.shared
    @Environment(\.dismiss) var dismiss

    @State private var searchText = ""
    @State private var showingClearConfirmation = false
    @State private var editingBookmark: BookmarkedText?
    @State private var editNoteText = ""

    private var filteredBookmarks: [BookmarkedText] {
        if searchText.isEmpty {
            return bookmarksManager.bookmarks
        }
        return bookmarksManager.bookmarks.filter {
            $0.japanese.localizedCaseInsensitiveContains(searchText) ||
            $0.translation.localizedCaseInsensitiveContains(searchText) ||
            ($0.note?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        NavigationView {
            Group {
                if bookmarksManager.bookmarks.isEmpty {
                    emptyStateView
                } else {
                    bookmarksList
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }

                if !bookmarksManager.bookmarks.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button(role: .destructive) {
                                showingClearConfirmation = true
                            } label: {
                                Label("Clear All", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search bookmarks")
            .confirmationDialog(
                "Clear All Bookmarks?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear All", role: .destructive) {
                    bookmarksManager.clearAllBookmarks()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete all \(bookmarksManager.bookmarks.count) bookmarks.")
            }
            .sheet(item: $editingBookmark) { bookmark in
                EditNoteSheet(bookmark: bookmark, noteText: $editNoteText) {
                    bookmarksManager.updateNote(for: bookmark, note: editNoteText.isEmpty ? nil : editNoteText)
                    editingBookmark = nil
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bookmark")
                .font(.system(size: 50))
                .foregroundColor(.gray)

            Text("No Bookmarks Yet")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Tap the bookmark icon on any translated text to save it here for later review.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Bookmarks List

    private var bookmarksList: some View {
        List {
            ForEach(filteredBookmarks) { bookmark in
                BookmarkRow(
                    bookmark: bookmark,
                    speechManager: speechManager,
                    onEdit: {
                        editNoteText = bookmark.note ?? ""
                        editingBookmark = bookmark
                    }
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        bookmarksManager.removeBookmark(bookmark)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        editNoteText = bookmark.note ?? ""
                        editingBookmark = bookmark
                    } label: {
                        Label("Note", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Bookmark Row

struct BookmarkRow: View {
    let bookmark: BookmarkedText
    let speechManager: SpeechManager
    let onEdit: () -> Void

    @State private var showCopiedToast = false

    private var languageLabel: String {
        bookmark.targetLanguage == "en" ? "EN" : "CN"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Japanese text with actions
            HStack {
                Text(bookmark.japanese)
                    .font(.title3)
                    .fontWeight(.medium)

                Spacer()

                // Language badge
                Text(languageLabel)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.8))
                    .cornerRadius(4)

                Button(action: {
                    speechManager.speak(bookmark.japanese)
                }) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Circle().fill(Color.red))
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Translation
            Text(bookmark.translation)
                .font(.body)
                .foregroundColor(.blue)

            // Note (if exists)
            if let note = bookmark.note, !note.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "note.text")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text(note)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
                .padding(.top, 2)
            }

            // Date
            Text(bookmark.dateAdded.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                UIPasteboard.general.string = bookmark.japanese
            } label: {
                Label("Copy Japanese", systemImage: "doc.on.doc")
            }

            Button {
                UIPasteboard.general.string = bookmark.translation
            } label: {
                Label("Copy Translation", systemImage: "doc.on.doc")
            }

            Button {
                UIPasteboard.general.string = "\(bookmark.japanese)\n\(bookmark.translation)"
            } label: {
                Label("Copy Both", systemImage: "doc.on.doc.fill")
            }

            Divider()

            Button {
                onEdit()
            } label: {
                Label("Edit Note", systemImage: "pencil")
            }
        }
    }
}

// MARK: - Edit Note Sheet

struct EditNoteSheet: View {
    let bookmark: BookmarkedText
    @Binding var noteText: String
    let onSave: () -> Void

    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text(bookmark.japanese)
                        .font(.title3)
                        .fontWeight(.medium)
                    Text(bookmark.translation)
                        .font(.body)
                        .foregroundColor(.blue)
                }

                Section("Note") {
                    TextField("Add a note...", text: $noteText, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    BookmarksView()
}

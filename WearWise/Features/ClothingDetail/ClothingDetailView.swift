import SwiftUI

struct ClothingDetailView: View {
    let itemID: UUID

    @Environment(WardrobeStore.self) private var wardrobe
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var errorMessage: String?

    var body: some View {
        if let item = wardrobe.item(id: itemID) {
            List {
                Section {
                    StoredImage(path: item.imagePath, contentMode: .fit)
                        .frame(maxHeight: 420)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                        .listRowInsets(EdgeInsets())
                        .accessibilityLabel("Photo of \(item.name)")
                }

                if item.category == .tops {
                    Section {
                        NavigationLink {
                            MatchResultsView(topID: item.id)
                        } label: {
                            Label("Find pants and shoes that match", systemImage: "sparkles")
                                .fontWeight(.medium)
                        }
                    }
                }

                Section("Details") {
                    LabeledContent("Category", value: item.category.displayName)
                    LabeledContent("Casual or formal", value: item.formality.displayName)
                    LabeledContent("Colours") {
                        HStack(spacing: 6) {
                            ForEach([item.primaryColor] + item.secondaryColors, id: \.self) { ColorSwatch(color: $0) }
                            Text(item.colorDescription)
                        }
                    }
                    LabeledContent("Pattern", value: item.pattern.displayName)
                }

                Section {
                    LabeledContent("Added", value: item.dateAdded.formatted(date: .abbreviated, time: .omitted))
                    if let note = Self.statusNote(item.aiStatus) {
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Delete item", role: .destructive) { confirmingDelete = true }
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        perform { try wardrobe.toggleFavorite(item) }
                    } label: {
                        Label(item.isFavorite ? "Remove from favourites" : "Add to favourites",
                              systemImage: item.isFavorite ? "heart.fill" : "heart")
                    }
                    Button("Edit") { editing = true }
                }
            }
            .sheet(isPresented: $editing) {
                EditClothingView(item: item)
            }
            .confirmationDialog("Delete \(item.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    perform {
                        try wardrobe.delete(item)
                        dismiss()
                    }
                }
            } message: {
                Text("The item and its photo will be removed from this iPhone.")
            }
            .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        } else {
            ContentUnavailableView("Item not found", systemImage: "questionmark.square.dashed")
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }

    static func statusNote(_ status: AIAnalysisStatus) -> String? {
        switch status {
        case .manual: nil
        case .suggestedAccepted: "Details were suggested on device and confirmed by you."
        case .suggestedEdited: "Details were suggested on device and corrected by you."
        case .analysisUnavailable, .analysisFailed: "Details were entered by you."
        }
    }
}

private struct EditClothingView: View {
    let item: ClothingItem

    @Environment(WardrobeStore.self) private var wardrobe
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ClothingDraft
    @State private var errorMessage: String?

    init(item: ClothingItem) {
        self.item = item
        _draft = State(initialValue: ClothingDraft(item: item))
    }

    var body: some View {
        NavigationStack {
            Form {
                ClothingFormFields(draft: $draft)
            }
            .navigationTitle("Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try wardrobe.update(item, with: draft)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(!draft.isComplete)
                }
            }
            .alert("Couldn't save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
}

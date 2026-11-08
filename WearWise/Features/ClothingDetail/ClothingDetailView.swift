import SwiftUI

struct ClothingDetailView: View {
    let itemID: UUID

    @Environment(WardrobeStore.self) private var wardrobe
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @State private var photoModel: ItemPhotoModel?
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var errorMessage: String?
    @State private var showOriginal = false

    var body: some View {
        if let item = wardrobe.item(id: itemID) {
            List {
                Section {
                    let showingCutout = item.cutoutPath != nil && !showOriginal
                    StoredImage(
                        path: showingCutout ? item.displayImagePath : item.imagePath,
                        contentMode: .fit,
                        background: showingCutout ? Theme.cutoutBackground : Theme.cardBackground
                    )
                    .padding(showingCutout ? 20 : 0)
                    .frame(maxHeight: 420)
                    .background(showingCutout ? Theme.cutoutBackground : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    .listRowInsets(EdgeInsets())
                    .accessibilityLabel(showingCutout ? "\(item.name), background removed" : "Photo of \(item.name)")
                    if item.cutoutPath != nil {
                        Picker("Image", selection: $showOriginal) {
                            Text("Cut-out").tag(false)
                            Text("Original photo").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    photoAction(for: item)
                }

                if OutfitMatcher.startingCategories.contains(item.category) {
                    Section {
                        NavigationLink {
                            MatchResultsView(topID: item.id)
                        } label: {
                            Label(item.category == .dresses ? "Find shoes that match" : "Find pants and shoes that match", systemImage: "sparkles")
                                .fontWeight(.medium)
                        }
                    }
                }

                Section("Details") {
                    LabeledContent("Category", value: item.category.displayName)
                    if let kind = item.resolvedAccessoryKind {
                        LabeledContent("Type", value: kind.displayName)
                    }
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
            .task {
                if photoModel == nil {
                    photoModel = ItemPhotoModel(processor: dependencies.imageProcessor, segmenter: dependencies.segmenter)
                }
            }
            .alert(
                "Update the main colour?",
                isPresented: Binding(
                    get: { photoModel?.colorSuggestion != nil },
                    set: { if !$0 { photoModel?.colorSuggestion = nil } }
                ),
                presenting: photoModel?.colorSuggestion
            ) { suggestion in
                Button("Change to \(suggestion.suggested.displayName)") { photoModel?.acceptColorSuggestion(in: wardrobe) }
                Button("Keep \(suggestion.current.displayName)", role: .cancel) {}
            } message: { suggestion in
                Text("Without the background, this item looks mostly \(suggestion.suggested.displayName.lowercased()), not \(suggestion.current.displayName.lowercased()). Matching uses the main colour.")
            }
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

    @ViewBuilder
    private func photoAction(for item: ClothingItem) -> some View {
        if let model = photoModel {
            if model.isWorking {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(item.cutoutPath == nil ? "Removing background…" : "Restoring original photo…")
                        .foregroundStyle(.secondary)
                }
            } else if item.cutoutPath == nil {
                Button {
                    Task { await model.removeBackground(of: item, in: wardrobe) }
                } label: {
                    Label("Remove background", systemImage: "scissors")
                }
            } else {
                Button {
                    showOriginal = false
                    Task { await model.restoreOriginal(of: item, in: wardrobe) }
                } label: {
                    Label("Use original photo instead", systemImage: "photo")
                }
            }
            if case .failed(let message) = model.state {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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

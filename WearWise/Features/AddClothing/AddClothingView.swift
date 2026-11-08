import PhotosUI
import SwiftUI
import UIKit

/// Add an item: take or choose a photo, review suggestions, correct anything, save.
struct AddClothingView: View {
    var onSaved: (ClothingItem) -> Void = { _ in }

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @State private var model: AddClothingModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    AddClothingForm(model: model, onSaved: { item in
                        onSaved(item)
                        dismiss()
                    })
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Add clothing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model?.cancel()
                        dismiss()
                    }
                }
            }
        }
        .task {
            if model == nil {
                model = AddClothingModel(processor: dependencies.imageProcessor, analysisService: dependencies.analysisService)
            }
        }
    }
}

private struct AddClothingForm: View {
    @Bindable var model: AddClothingModel
    let onSaved: (ClothingItem) -> Void

    @Environment(WardrobeStore.self) private var wardrobe
    @State private var pickerItem: PhotosPickerItem?
    @State private var showingCamera = false

    var body: some View {
        Form {
            photoSection
            if model.preparedPhoto != nil {
                analysisSection
                ClothingFormFields(draft: $model.draft, suggestion: model.suggestion)
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if let item = model.save(to: wardrobe) { onSaved(item) }
                }
                .disabled(!model.canSave)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.preparedPhoto != nil, !model.draft.isComplete, !model.isAnalyzing {
                Text("Still needed: \(model.draft.missingFields.joined(separator: ", "))")
                    .font(.footnote)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
        .alert("Couldn't save", isPresented: Binding(get: { model.saveError != nil }, set: { if !$0 { model.saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.saveError ?? "")
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    model.load(imageData: data)
                } else {
                    model.photoLoadFailed()
                }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { data in
                if let data { model.load(imageData: data) }
            }
            .ignoresSafeArea()
        }
        .onDisappear { model.cancel() }
    }

    @ViewBuilder
    private var photoSection: some View {
        Section {
            switch model.photo {
            case .none:
                ContentUnavailableView(
                    "Add a photo",
                    systemImage: "camera",
                    description: Text("Lay the item flat or hang it against a plain background.")
                )
            case .preparing:
                ProgressView("Preparing photo…").frame(maxWidth: .infinity)
            case .ready(_, let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    .accessibilityLabel("Photo of the item")
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }

            if CameraPicker.isAvailable {
                Button {
                    showingCamera = true
                } label: {
                    Label(model.preparedPhoto == nil ? "Take photo" : "Retake photo", systemImage: "camera")
                }
            }
            let libraryTitle = model.preparedPhoto == nil ? "Choose from library" : "Choose a different photo"
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(libraryTitle, systemImage: "photo.on.rectangle")
            }
        }
    }

    @ViewBuilder
    private var analysisSection: some View {
        Section {
            switch model.analysis {
            case .idle:
                Button {
                    model.reanalyze()
                } label: {
                    Label("Suggest details", systemImage: "wand.and.stars")
                }
            case .analyzing:
                HStack {
                    ProgressView()
                    Text("Looking at your photo on device…")
                    Spacer()
                    Button("Skip") { model.cancel() }
                }
            case .suggested(.onDeviceModel):
                Label("Suggested by on-device AI. Check each value before saving.", systemImage: "sparkles")
                    .font(.footnote)
            case .suggested(.visionOnly):
                Label("Basic suggestions from image recognition. \(model.aiAvailability.isAvailable ? "" : model.aiAvailability.message)", systemImage: "eye")
                    .font(.footnote)
            case .failed(let message):
                VStack(alignment: .leading, spacing: 6) {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                    Text("Fill in the details below yourself.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Wraps UIImagePickerController for taking a photo with the camera.
struct CameraPicker: UIViewControllerRepresentable {
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    let onFinish: (Data?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator { data in
            onFinish(data)
            dismiss()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let finish: (Data?) -> Void

        init(finish: @escaping (Data?) -> Void) {
            self.finish = finish
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            finish(image?.jpegData(compressionQuality: 0.9))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            finish(nil)
        }
    }
}

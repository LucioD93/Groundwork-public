import SwiftUI
import PhotosUI
import AVFoundation
import Vision
import GroundsCore

struct CameraCapture: UIViewControllerRepresentable {
 let onCapture: (UIImage) -> Void
 @Environment(\.dismiss) private var dismiss
 func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
 func makeUIViewController(context: Context) -> UIImagePickerController {
 let picker = UIImagePickerController()
 picker.sourceType = .camera
 picker.cameraCaptureMode = .photo
 picker.delegate = context.coordinator
 return picker
 }
 func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
 final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
 let parent: CameraCapture
 init(parent: CameraCapture) { self.parent = parent }
 func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
 func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
 if let image = info[.originalImage] as? UIImage { parent.onCapture(image) }
 parent.dismiss()
 }
 }
}

struct TitledTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    init(_ title: String, placeholder: String, text: Binding<String>) {
        self.title = title; self.placeholder = placeholder; self._text = text
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(JournalTheme.secondaryText)
            TextField(placeholder, text: $text, prompt: Text(placeholder).foregroundStyle(JournalTheme.secondaryText))
                .accessibilityLabel(title)
        }.padding(.vertical, 4)
    }
}

struct CoffeeEditor: View {
    @AppStorage("useOnDeviceAI") private var useOnDeviceAI = true
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var coffee: Coffee
    @State private var hasRoastDate: Bool
    @State private var roastDate: Date
    private let original: Coffee
    private let isNew: Bool
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var loading = false
    @State private var showingCamera = false
    @State private var cameraPermissionDenied = false
    @State private var confirmingDiscard = false
    @State private var autofillTask: Task<Void, Never>?
    @State private var autofillMessage: String?
    @State private var error: String?
    @FocusState private var focusedName: Bool

    init(coffee: Coffee) {
        _coffee = State(initialValue: coffee); original = coffee; isNew = coffee.name.isEmpty
        _hasRoastDate = State(initialValue: coffee.roastDate != nil)
        _roastDate = State(initialValue: coffee.roastDate ?? Date())
    }
    private var previewImage: UIImage? {
        if let photoData { return UIImage(data: photoData) }
        if let photo = coffee.photo, let directory = store.journal?.photosDirectory {
            return UIImage(contentsOfFile: directory.appendingPathComponent(photo).path)
        }
        return nil
    }
    private var hasChanges: Bool {
        coffee != original || photoData != nil || hasRoastDate != (original.roastDate != nil) || (hasRoastDate && roastDate != (original.roastDate ?? roastDate))
    }
    var body: some View {
        NavigationStack {
            JournalForm {
                Section {
                    if isNew { Text("Scan your bag or enter the details below.").font(.subheadline).foregroundStyle(JournalTheme.secondaryText) }
                    Button("Scan bag with camera", systemImage: "camera") { openCamera() }.disabled(loading).journalAction()
                    PhotosPicker(selection: $selectedPhoto, matching: .images) { Label("Choose a label photo", systemImage: "photo") }.disabled(loading).journalAction()
                    if let image = previewImage {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 190)
                            .clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityLabel("Selected coffee label")
                        Button("Fill details from this label", systemImage: "sparkles") { autofill() }
                            .disabled(autofillTask != nil || loading).journalPrimary()
                        Text(useOnDeviceAI ? "Reads this label on your iPhone." : "Sends this label to OpenAI using your API balance.").font(.footnote).foregroundStyle(JournalTheme.secondaryText)
                        Button("Remove photo", role: .destructive) { coffee.photo = nil; photoData = nil; selectedPhoto = nil }.journalAction(destructive: true)
                    }
                    if loading { ProgressView("Loading photo…") }
                    if autofillTask != nil { ProgressView("Reading the label…") }
                    if let autofillMessage { Text(autofillMessage).font(.footnote).foregroundStyle(JournalTheme.secondaryText) }
                    if isNew && previewImage == nil { Button("Enter details manually") { focusedName = true }.journalAction() }
                } header: { Text("Coffee label · optional") }
                Section("Coffee details") {
                    TitledTextField("Coffee name · required", placeholder: "House Blend", text: $coffee.name).focused($focusedName)
                    TitledTextField("Roaster · optional", placeholder: "Puerto Blest", text: $coffee.roaster)
                    TitledTextField("Origin · optional", placeholder: "Brazil", text: $coffee.origin)
                    Toggle("Add roast date", isOn: $hasRoastDate).tint(JournalTheme.accent)
                    if hasRoastDate { DatePicker("Roasted", selection: $roastDate, in: ...Date(), displayedComponents: .date) }
                }
                if let error { Section { InlineError(message: error) } }
            }
            .disabled(autofillTask != nil)
            .journalTitle(isNew ? "Add coffee" : "Edit coffee")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if hasChanges { confirmingDiscard = true } else { dismiss() } }.journalAction(fixedLabel: true) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(loading || autofillTask != nil || coffee.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).journalAction(fixedLabel: true)
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focusedName = false }.journalAction() }
            }
            .interactiveDismissDisabled(hasChanges)
            .confirmationDialog("Discard your changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraCapture { image in
                    guard let jpeg = image.jpegData(compressionQuality: 0.85) else { error = "This photo could not be read. Please take another."; return }
                    selectedPhoto = nil; photoData = jpeg
                }.ignoresSafeArea()
            }
            .alert("Allow camera access", isPresented: $cameraPermissionDenied) {
                Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Allow Groundwork to use the camera in Settings to scan a coffee bag.") }
            .task(id: selectedPhoto) {
                guard let selectedPhoto else { return }
                loading = true
                defer { loading = false }
                do {
                    guard let data = try await selectedPhoto.loadTransferable(type: Data.self), let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.85) else { throw JournalError.invalid("This photo could not be read.") }
                    try Task.checkCancellation(); photoData = jpeg; error = nil
                } catch is CancellationError {} catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
            .onDisappear { autofillTask?.cancel(); autofillTask = nil }
        }
    }
    private func save() {
        do {
            guard let journal = store.journal else { throw JournalError.invalid("Journal unavailable. Your draft is still here.") }
            var saved = coffee; saved.roastDate = hasRoastDate ? roastDate : nil
            try saved.validate()
            if let photoData { saved.photo = try journal.storePhoto(photoData) }
            try journal.save(saved); try store.refresh(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { error = "A camera is unavailable. Choose a label photo from your library instead."; return }
        Task { @MainActor in
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: showingCamera = true
            case .notDetermined:
                if await AVCaptureDevice.requestAccess(for: .video) { showingCamera = true } else { cameraPermissionDenied = true }
            default: cameraPermissionDenied = true
            }
        }
    }
    private func autofill() {
        autofillMessage = nil; error = nil
        autofillTask = Task { @MainActor in
            defer { autofillTask = nil }
            do {
                guard let image = previewImage else { throw JournalError.invalid("Choose a readable label photo first.") }
                let jpeg = try preparedCoffeePhoto(image)
                let key = try aiKey(onDevice: useOnDeviceAI)
                let details: CoffeePhotoDetails
                if useOnDeviceAI { details = try await OnDeviceAI.extract(label: try await readCoffeeLabel(jpeg)) }
                else { details = try await RecipeGenerator().extractCoffee(jpeg: jpeg, apiKey: key) }
                try Task.checkCancellation(); coffee = details.applying(to: coffee)
                if let date = details.parsedRoastDate { roastDate = date; hasRoastDate = true }
                autofillMessage = "Details filled. Review the fields below before saving; unreadable details stayed unchanged."
            } catch is CancellationError {} catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}

func aiKey(onDevice: Bool) throws -> String {
    if onDevice {
        if let reason = OnDeviceAI.unavailableReason { throw JournalError.invalid(reason) }
        return ""
    }
    guard let key = try OpenAIKeyStore().load(), !key.isEmpty else { throw JournalError.invalid("Add your OpenAI key in Settings first.") }
    return key
}

@MainActor func preparedCoffeePhoto(_ image: UIImage) throws -> Data {
    let scale = min(1, 1600 / max(image.size.width, image.size.height))
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { throw JournalError.invalid("This photo could not be prepared. Choose another label photo.") }
    return jpeg
}

func readCoffeeLabel(_ jpeg: Data) async throws -> String {
    try await Task.detached(priority: .userInitiated) {
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
        try VNImageRequestHandler(data: jpeg).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }.value
}

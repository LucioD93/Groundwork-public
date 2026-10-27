import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import GroundsCore
import Security
import Vision

/// Device-only credential storage, independent of the journal and its exports.
struct OpenAIKeyStore {
 private var query: [String: Any] {
 [kSecClass as String: kSecClassGenericPassword,
  kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "com.dailygrounds.journal") + ".openai",
  kSecAttrAccount as String: "api-key",
  kSecAttrSynchronizable as String: false]
 }
 func load() throws -> String? {
 var request = query
 request[kSecReturnData as String] = true
 request[kSecMatchLimit as String] = kSecMatchLimitOne
 var result: CFTypeRef?
 let status = SecItemCopyMatching(request as CFDictionary, &result)
 if status == errSecItemNotFound { return nil }
 try check(status)
 guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
 throw JournalError.invalid("The saved key could not be read. Replace it with a new key.")
 }
 return key
 }
 func save(_ key: String) throws {
 let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8),
  kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
 let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
 if status == errSecItemNotFound {
 try check(SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil))
 } else { try check(status) }
 }
 func remove() throws {
 let status = SecItemDelete(query as CFDictionary)
 if status != errSecItemNotFound { try check(status) }
 }
 private func check(_ status: OSStatus) throws {
 guard status == errSecSuccess else {
 throw JournalError.invalid("Could not access the device Keychain (error \(status)). Please try again.")
 }
 }
}

@MainActor final class Store: ObservableObject {
    @Published var coffees: [Coffee] = []
    @Published var brews: [Brew] = []
    @Published var recipes: [Brew] = []
    @Published var error: String?
    @Published var deletedBrew: Brew?
    let journal: Journal?

    init() {
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let legacy = support.appendingPathComponent("DailyGrounds")
            let root = support.appendingPathComponent("Groundwork")
            if FileManager.default.fileExists(atPath: legacy.path), !FileManager.default.fileExists(atPath: root.path) {
                try FileManager.default.moveItem(at: legacy, to: root)
            }
            journal = try Journal(directory: root)
        } catch { journal = nil; self.error = error.localizedDescription }
        reload()
    }

    func refresh() throws {
        guard let journal else { throw JournalError.invalid("Your journal is unavailable. Please reopen Groundwork.") }
        coffees = try journal.coffees()
        brews = try journal.brews()
        recipes = try journal.recipes()
    }
    func reload() { perform { try refresh() } }
    func perform(_ action: () throws -> Void) { do { try action() } catch { self.error = error.localizedDescription } }
    func removeBrew(_ brew: Brew) {
        perform { try journal?.deleteBrew(brew.id); deletedBrew = brew; try refresh() }
    }
    func undoDelete() {
        perform { if let deletedBrew { try journal?.save(deletedBrew); self.deletedBrew = nil; try refresh() } }
    }
    func archive(_ coffee: Coffee) {
        perform { var updated = coffee; updated.archived = coffee.archived == true ? nil : true; try journal?.save(updated); try refresh() }
    }
}

@main struct GroundworkApp: App {
    @StateObject private var store = Store()
    @AppStorage("appearance") private var appearance = JournalAppearance.system
    init() { JournalTheme.configureNavigation() }
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).tint(JournalTheme.accent).preferredColorScheme(appearance.colorScheme)
                .alert("Something needs attention", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                    Button("OK") { store.error = nil }
                } message: { Text(store.error ?? "") }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        TabView {
            NavigationStack { CoffeeShelf() }.tabItem { Label("Coffees", systemImage: "cup.and.saucer") }
            NavigationStack { BrewList(brews: store.brews).journalTitle("Brew history") }.tabItem { Label("History", systemImage: "clock") }
            NavigationStack { AISettingsView() }.tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .safeAreaInset(edge: .bottom) {
            if store.deletedBrew != nil {
                HStack {
                    Text("Brew deleted").font(.subheadline)
                    Spacer()
                    Button("Undo") { store.undoDelete() }.journalAction()
                    Button { store.deletedBrew = nil } label: { Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Dismiss undo").journalAction()
                }
                .padding(.horizontal).background(JournalTheme.surface)
            }
        }
    }
}

struct CoffeeShelf: View {
    @EnvironmentObject private var store: Store
    @AppStorage("lastBrewMethod") private var lastMethod = BrewMethod.espresso.rawValue
    @State private var adding = false
    @State private var query = ""
    @State private var archived = false
    @State private var draft: Brew?
    private var coffees: [Coffee] {
        store.coffees.filter { ($0.archived == true) == archived && (query.isEmpty || [$0.name, $0.roaster, $0.origin].joined(separator: " ").localizedCaseInsensitiveContains(query)) }
    }
    var body: some View {
        JournalList {
            if store.coffees.isEmpty {
                ContentUnavailableView {
                    Label("Your coffee shelf", systemImage: "cup.and.saucer")
                } description: { Text("Start with a bag you love. Remember the recipe and make the next cup even better.") }
                actions: { Button("Add your first coffee") { adding = true }.journalPrimary() }
            } else {
                Picker("Shelf", selection: $archived) { Text("Active").tag(false); Text("Finished").tag(true) }.pickerStyle(.segmented)
                if coffees.isEmpty {
                    Text(query.isEmpty ? (archived ? "Finished bags will stay here with their brew history." : "Add a coffee or bring a finished bag back to your shelf.") : "No coffees match your search.")
                        .foregroundStyle(JournalTheme.secondaryText)
                }
                ForEach(coffees) { coffee in
                    Section {
                        NavigationLink { CoffeeDetail(coffeeID: coffee.id) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                CoffeePhoto(coffee: coffee).frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(coffee.name).font(.headline)
                                    Text([coffee.roaster, coffee.origin].filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline).foregroundStyle(JournalTheme.secondaryText)
                                    if let age = coffee.roastAge { Text(age).font(.caption).foregroundStyle(JournalTheme.secondaryText) }
                                }
                            }.padding(.vertical, 4)
                        }
                        if let last = store.brews.first(where: { $0.coffeeID == coffee.id }) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("Last cup · \(last.method.rawValue)").font(.caption).foregroundStyle(JournalTheme.secondaryText)
                                Text(last.recipeSummary).font(.subheadline)
                                Button("Brew again", systemImage: "arrow.clockwise") { draft = last.repeated() }.journalAction()
                            }.padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .journalTitle("Groundwork").searchable(text: $query, prompt: "Coffee, roaster or origin")
        .toolbar { Button("Add coffee", systemImage: "plus") { adding = true }.journalAction() }
        .sheet(isPresented: $adding) { CoffeeEditor(coffee: Coffee(name: "")) }
        .sheet(item: $draft) { BrewEditor(brew: $0) }
    }
}

extension Coffee {
    var roastAge: String? {
        guard let roastDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: roastDate), to: Calendar.current.startOfDay(for: Date())).day ?? 0
        if days < 0 { return "Roast date is in the future" }
        return days == 0 ? "Roasted today" : "\(days) \(days == 1 ? "day" : "days") since roast"
    }
}

struct CoffeePhoto: View {
    @EnvironmentObject private var store: Store
    let coffee: Coffee
    var body: some View {
        Group {
            if let name = coffee.photo, let root = store.journal?.photosDirectory,
               let image = UIImage(contentsOfFile: root.appendingPathComponent(name).path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "cup.and.saucer.fill").resizable().scaledToFit().padding(14)
                    .foregroundStyle(JournalTheme.secondaryText).background(JournalTheme.photoBackground)
            }
        }.clipped().accessibilityHidden(true)
    }
}

struct CoffeeDetail: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lastBrewMethod") private var lastMethod = BrewMethod.espresso.rawValue
    let coffeeID: UUID
    @State private var editing = false
    @State private var deleting = false
    @State private var photoRecipe = false
    @State private var suggestion = false
    @State private var draft: Brew?
    private var coffee: Coffee? { store.coffees.first { $0.id == coffeeID } }
    private var brews: [Brew] { store.brews.filter { $0.coffeeID == coffeeID } }
    private var best: Brew? { brews.filter { $0.score != nil }.sorted { $0.score == $1.score ? $0.date > $1.date : ($0.score ?? 0) > ($1.score ?? 0) }.first }

    var body: some View {
        Group {
            if let coffee {
                JournalList {
                    Section {
                        HStack(alignment: .top, spacing: 14) {
                            CoffeePhoto(coffee: coffee).frame(width: 80, height: 80).clipShape(RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 6) {
                                if !coffee.roaster.isEmpty { Text(coffee.roaster).font(.headline) }
                                if !coffee.origin.isEmpty { Text(coffee.origin).font(.subheadline).foregroundStyle(JournalTheme.secondaryText) }
                                if let age = coffee.roastAge { Text(age).font(.caption).foregroundStyle(JournalTheme.secondaryText) }
                                if coffee.archived == true { Text("Finished bag").font(.caption).foregroundStyle(JournalTheme.secondaryText) }
                            }
                        }.padding(.vertical, 6)
                        Button("Brew this coffee", systemImage: "cup.and.saucer.fill") {
                            let method = brews.first?.method ?? BrewMethod(rawValue: lastMethod) ?? .espresso
                            draft = Brew.starting(coffeeID: coffeeID, method: method, history: store.brews)
                        }.journalPrimary()
                    }
                    if let last = brews.first {
                        Section("Last recipe") { recipeCard(last, title: last.method.rawValue) }
                    }
                    if let best, best.id != brews.first?.id {
                        Section("Best-rated recipe") { recipeCard(best, title: "\(best.method.rawValue) · \(best.score ?? 0)/5 taste") }
                    }
                    let saved = store.recipes.filter { $0.coffeeID == coffeeID }
                    if !saved.isEmpty {
                        Section("Saved recipes") {
                            ForEach(saved) { recipe in
                                recipeCard(recipe, title: recipe.method.rawValue)
                                    .swipeActions { Button("Delete recipe", role: .destructive) { store.perform { try store.journal?.deleteRecipe(recipe.id); try store.refresh() } } }
                            }
                        }
                    }
                    Section("Recent brews") {
                        if brews.isEmpty { Text("Start with your usual recipe. You can add tasting notes after the first sip.").foregroundStyle(JournalTheme.secondaryText) }
                        ForEach(brews.prefix(5)) { BrewRow(brew: $0, previous: previous(to: $0)) }
                        if brews.count > 5 { NavigationLink("All \(brews.count) brews") { BrewList(brews: brews).journalTitle("Coffee history") } }
                    }
                    Section("Recipe ideas") {
                        if best != nil { Button("Find a recipe from my ratings", systemImage: "star.bubble") { suggestion = true }.journalAction() }
                        if coffee.photo != nil { Button("Starting recipe from label", systemImage: "sparkles") { photoRecipe = true }.journalAction() }
                        if best == nil && coffee.photo == nil {
                            Text("Rate a cup to find your favorite recipe, or add a label photo for a starting point.").font(.subheadline).foregroundStyle(JournalTheme.secondaryText)
                        }
                    }
                }
                .journalTitle(coffee.name)
                .toolbar {
                    Button("Edit") { editing = true }.journalAction(fixedLabel: true)
                    Menu {
                        Button(coffee.archived == true ? "Return to active shelf" : "Mark bag as finished", systemImage: "archivebox") { store.archive(coffee) }
                        Button("Delete coffee and its brews", systemImage: "trash", role: .destructive) { deleting = true }
                    } label: { Label("Coffee actions", systemImage: "ellipsis") }.journalAction()
                }
                .sheet(isPresented: $editing) { CoffeeEditor(coffee: coffee) }
                .sheet(item: $draft) { BrewEditor(brew: $0, previousFeedback: brews.first(where: { $0.method == draft?.method })?.notes) }
                .sheet(isPresented: $photoRecipe) { RecipeView(coffee: coffee) }
                .sheet(isPresented: $suggestion) { RecipeView(coffee: coffee, fromScores: true) }
                .confirmationDialog("Delete this coffee and all its brews?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete coffee", role: .destructive) {
                        store.perform { try store.journal?.deleteCoffee(coffeeID); try store.refresh(); dismiss() }
                    }
                } message: { Text("This permanently removes the coffee, its saved recipes and its brew history. Mark the bag as finished to keep them.") }
            } else { Text("Coffee removed") }
        }
    }
    private func previous(to brew: Brew) -> Brew? { brews.first { $0.method == brew.method && $0.date < brew.date } }
    private func recipeCard(_ brew: Brew, title: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.headline)
            Text(brew.recipeSummary).font(.subheadline)
            if let ratio = brew.waterRatio { Text("Coffee to water · \(ratio)").font(.caption).foregroundStyle(JournalTheme.secondaryText) }
            Button("Brew again", systemImage: "arrow.clockwise") { draft = brew.repeated() }.journalAction()
        }.padding(.vertical, 5)
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct BackupView: View {
    @EnvironmentObject private var store: Store
    @State private var exporting = false
    @State private var importing = false
    @State private var imported = false
    @State private var error: String?
    @State private var document = BackupDocument()
    var body: some View {
        JournalForm {
            Section("Keep your journal") {
                Button("Export backup", systemImage: "square.and.arrow.up") {
                    do {
                        guard let journal = store.journal else { throw JournalError.invalid("Journal unavailable.") }
                        document = BackupDocument(data: try journal.exportBackup()); exporting = true
                    } catch { self.error = error.localizedDescription }
                }.journalAction()
                Button("Import backup", systemImage: "square.and.arrow.down") { importing = true }.journalAction()
                Text("Backups include coffees, saved recipes, brews and photos. Import adds missing records and keeps your current journal.").font(.footnote).foregroundStyle(JournalTheme.secondaryText)
                Text("If the same record has been edited in both places, nothing is imported. Keep both backups and use the most recent one.").font(.footnote).foregroundStyle(JournalTheme.secondaryText)
                if let error { InlineError(message: error) }
            }
        }.journalTitle("Backup")
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Groundwork-backup") { result in
            if case .failure(let error) = result { self.error = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let journal = store.journal else { throw JournalError.invalid("Journal unavailable.") }
                try journal.importBackup(Data(contentsOf: url)); try store.refresh(); imported = true
            } catch { if (error as NSError).code != NSUserCancelledError { self.error = error.localizedDescription } }
        }
        .alert("Backup imported", isPresented: $imported) { Button("OK", role: .cancel) {} } message: { Text("Your shelf, recipes and history are ready.") }
    }
}

struct AISettingsView: View {
    @AppStorage("appearance") private var appearance = JournalAppearance.system
    @AppStorage("useOnDeviceAI") private var useOnDeviceAI = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var key = ""
    @State private var hasSavedKey = false
    @State private var checking = false
    @State private var message: String?
    @State private var error: String?
    @State private var confirmingRemoval = false
    @FocusState private var editingKey: Bool
    private let credentials = OpenAIKeyStore()
    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        JournalForm {
            Section("Appearance") { Picker("Theme", selection: $appearance) { ForEach(JournalAppearance.allCases) { Text($0.title).tag($0) } } }
            Section("Photo recipes and label scanning") {
                Picker("Processing", selection: $useOnDeviceAI) { Text("On this iPhone").tag(true); Text("OpenAI").tag(false) }
                if useOnDeviceAI { Text(OnDeviceAI.unavailableReason ?? "Apple Intelligence is ready. Your photos stay on this iPhone.").font(.footnote).foregroundStyle(JournalTheme.secondaryText) }
                else { Text("Uses your OpenAI API key and balance.").font(.footnote).foregroundStyle(JournalTheme.secondaryText) }
                DisclosureGroup("How processing works") {
                    Text(useOnDeviceAI ? "Apple Vision reads label text and Apple Intelligence proposes a starting recipe locally. There is no cloud fallback." : "Only the selected label photo and coffee details are sent to OpenAI when you request a scan or photo recipe. API charges may apply.")
                        .font(.footnote).foregroundStyle(JournalTheme.secondaryText)
                }
            }
            if !useOnDeviceAI {
                Section {
                    LabeledContent("OpenAI key", value: checking ? "Checking…" : (hasSavedKey ? "Saved on this device" : "Not configured"))
                    SecureField(hasSavedKey ? "Paste a replacement key" : "Paste your API key", text: $key)
                        .textContentType(.password).textInputAutocapitalization(.never).autocorrectionDisabled().focused($editingKey)
                    Button(hasSavedKey ? "Replace key" : "Save key") { saveKey() }.disabled(checking || trimmedKey.isEmpty).journalAction()
                    if hasSavedKey { Button("Remove key", role: .destructive) { confirmingRemoval = true }.journalAction(destructive: true) }
                    if let error { InlineError(message: error); Button("Try again") { refreshStatus() }.journalAction() }
                    if let message { Text(message).font(.footnote).foregroundStyle(JournalTheme.secondaryText) }
                } header: { Text("OpenAI key") } footer: { Text("Stored only in this device’s Keychain, outside journal backups. Saving does not validate the key or contact OpenAI.") }
            }
            Section { Text("Suggestions from your ratings use saved brew records on this device. They do not upload your history or invent missing observations.").font(.footnote).foregroundStyle(JournalTheme.secondaryText) }
            Section("Your journal") { NavigationLink { BackupView() } label: { Label("Backup", systemImage: "externaldrive") } }
        }.journalTitle("Settings")
        .onAppear { if !useOnDeviceAI { refreshStatus() } }
        .onDisappear { clearKey() }
        .onChange(of: useOnDeviceAI) { _, local in clearKey(); error = nil; if !local { refreshStatus() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { clearKey() } else if !useOnDeviceAI { refreshStatus() } }
        .confirmationDialog("Remove the OpenAI key from this device?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove key", role: .destructive) {
                do { try credentials.remove(); clearKey(); hasSavedKey = false; error = nil; message = "Key removed." }
                catch { self.error = error.localizedDescription }
            }
        }
    }
    private func clearKey() { key = ""; editingKey = false }
    private func refreshStatus() {
        checking = true
        defer { checking = false }
        do { hasSavedKey = try credentials.load() != nil; error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func saveKey() {
        do {
            guard !trimmedKey.isEmpty, !trimmedKey.contains(where: { $0.isWhitespace }) else { throw JournalError.invalid("Paste a key without spaces or line breaks.") }
            try credentials.save(trimmedKey); clearKey(); hasSavedKey = true; error = nil; message = "Key saved on this device."
        } catch { self.error = error.localizedDescription }
    }
}

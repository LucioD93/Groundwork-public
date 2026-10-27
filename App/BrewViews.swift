import SwiftUI
import GroundsCore

func flowTitle(_ rating: Int?) -> String {
    switch rating { case 1: return "Choked"; case 2: return "Slow"; case 3: return "Steady"; case 4: return "Fast"; case 5: return "Gushing"; default: return "Not observed" }
}

struct BrewList: View {
    @EnvironmentObject private var store: Store
    let brews: [Brew]
    @State private var method = "All methods"
    @State private var query = ""
    @State private var comparing = false
    @State private var selected: [UUID] = []
    @State private var showComparison = false
    private var filtered: [Brew] {
        brews.filter { brew in
            let coffee = store.coffees.first { $0.id == brew.coffeeID }
            return (method == "All methods" || brew.method.rawValue == method) &&
                (query.isEmpty || [coffee?.name ?? "", brew.grinder, brew.notes].joined(separator: " ").localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        JournalList {
            if brews.isEmpty {
                ContentUnavailableView("Your first cup awaits", systemImage: "clock", description: Text("Choose a coffee from your shelf and tap Brew this coffee. You can rate it after tasting."))
            } else {
                Picker("Method", selection: $method) {
                    Text("All methods").tag("All methods")
                    ForEach(BrewMethod.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
                }
                if comparing {
                    Section {
                        Text("Choose two cups of the same coffee and method.").font(.subheadline).foregroundStyle(JournalTheme.secondaryText)
                        Button("Compare selected cups") { showComparison = true }.disabled(selected.count != 2).journalPrimary()
                    }
                }
                if filtered.isEmpty { Text("No brews match your filters.").foregroundStyle(JournalTheme.secondaryText) }
                ForEach(filtered) { brew in
                    Section {
                        if comparing {
                            Button {
                                if selected.contains(brew.id) { selected.removeAll { $0 == brew.id } }
                                else if selected.count < 2 { selected.append(brew.id) }
                            } label: {
                                Label(selected.contains(brew.id) ? "Selected" : "Compare this cup", systemImage: selected.contains(brew.id) ? "checkmark.circle.fill" : "circle")
                            }.journalAction()
                            .disabled(!canCompare(brew))
                        }
                        BrewRow(brew: brew, previous: brews.first { $0.coffeeID == brew.coffeeID && $0.method == brew.method && $0.date < brew.date })
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Coffee, grinder or tasting note")
        .toolbar { if brews.count > 1 { Button(comparing ? "Done" : "Compare") { comparing.toggle(); selected = [] }.journalAction() } }
        .sheet(isPresented: $showComparison) {
            BrewComparison(brews: selected.compactMap { id in brews.first { $0.id == id } })
        }
        .onChange(of: brews.map(\.id)) { _, ids in selected.removeAll { !ids.contains($0) } }
    }
    private func canCompare(_ brew: Brew) -> Bool {
        guard let firstID = selected.first, let first = brews.first(where: { $0.id == firstID }) else { return true }
        return selected.contains(brew.id) || (selected.count < 2 && first.coffeeID == brew.coffeeID && first.method == brew.method)
    }
}

struct BrewRow: View {
    @EnvironmentObject private var store: Store
    let brew: Brew
    var previous: Brew? = nil
    @State private var viewing = false
    @State private var draft: Brew?
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button { viewing = true } label: {
                VStack(alignment: .leading, spacing: 7) {
                    Text(store.coffees.first { $0.id == brew.coffeeID }?.name ?? "Coffee").font(.headline)
                    Text(brew.method.rawValue).font(.subheadline).foregroundStyle(JournalTheme.secondaryText)
                    Text(brew.recipeSummary).font(.subheadline)
                    if let score = brew.score { Label("Taste · \(score)/5", systemImage: "star.fill").font(.subheadline).foregroundStyle(JournalTheme.accent) }
                    else { Text("Not tasted yet").font(.caption).foregroundStyle(JournalTheme.secondaryText) }
                    if !brew.notes.isEmpty { Text(brew.notes).font(.subheadline).lineLimit(2) }
                    if let change = changeSummary { Text(change).font(.caption).foregroundStyle(JournalTheme.secondaryText) }
                    Text(brew.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(JournalTheme.secondaryText)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityHint("Opens recipe and tasting details")
            HStack {
                Button(brew.score == nil ? "Add tasting notes" : "View details") { viewing = true }.journalAction()
                Spacer()
                Button("Brew again", systemImage: "arrow.clockwise") { draft = brew.repeated() }.journalAction()
            }.buttonStyle(.borderless)
        }.padding(.vertical, 6)
        .swipeActions { Button("Delete", role: .destructive) { store.removeBrew(brew) }.tint(JournalTheme.danger) }
        .sheet(isPresented: $viewing) { BrewDetailView(brewID: brew.id) }
        .sheet(item: $draft) { BrewEditor(brew: $0, previousFeedback: brew.notes) }
    }
    private var changeSummary: String? {
        guard let previous else { return nil }
        var changes: [String] = []
        if brew.dose != previous.dose { changes.append("dose \(previous.dose.formatted()) → \(brew.dose.formatted()) g") }
        if brew.grinder == previous.grinder && brew.grindSetting != previous.grindSetting { changes.append("grind \(previous.grindSetting) → \(brew.grindSetting)") }
        if brew.grinder != previous.grinder { changes.append("different grinder") }
        if brew.method == .aeroPress, brew.seconds != previous.seconds { changes.append("brew time changed") }
        return changes.isEmpty ? "Same recorded recipe as the previous cup" : "Since previous cup: " + changes.joined(separator: " · ")
    }
}

struct BrewDetailView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let brewID: UUID
    @State private var draft: Brew?
    @State private var savingRecipe = false
    private var brew: Brew? { store.brews.first { $0.id == brewID } }
    var body: some View {
        NavigationStack {
            JournalList {
                if let brew {
                    Section("Recipe") {
                        Text(store.coffees.first { $0.id == brew.coffeeID }?.name ?? "Coffee").font(.headline)
                        Text(brew.method.rawValue)
                        Text(brew.recipeSummary)
                        if let ratio = brew.waterRatio { LabeledContent("Coffee to water", value: ratio) }
                        if let notes = brew.recipeNotes, !notes.isEmpty { Text(notes).textSelection(.enabled) }
                        Text(brew.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(JournalTheme.secondaryText)
                    }
                    Section("This cup") {
                        LabeledContent("Taste", value: brew.score.map { "\($0)/5" } ?? "Not rated")
                        if brew.method == .espresso { LabeledContent("Flow", value: flowTitle(brew.flowRating)) }
                        if let smell = brew.smellRating { LabeledContent("Smell", value: "\(smell)/5") }
                        if let color = brew.colorRating { LabeledContent("Color", value: "\(color)/5") }
                        if let texture = brew.textureRating { LabeledContent("Texture", value: "\(texture)/5") }
                        Text(brew.notes.isEmpty ? "No tasting notes yet." : brew.notes).foregroundStyle(brew.notes.isEmpty ? JournalTheme.secondaryText : JournalTheme.text)
                        Button("Edit brew and tasting notes") { draft = brew }.journalAction()
                    }
                    Section {
                        Button("Brew again", systemImage: "arrow.clockwise") { draft = brew.repeated() }.journalPrimary()
                        Button("Save as a recipe", systemImage: "bookmark") { savingRecipe = true }.journalAction()
                    }
                }
            }.journalTitle("Brew details")
            .toolbar { Button("Done") { dismiss() }.journalAction() }
        }
        .sheet(item: $draft) { BrewEditor(brew: $0, previousFeedback: $0.id == brewID ? nil : brew?.notes) }
        .sheet(isPresented: $savingRecipe) { if let brew { BrewEditor(brew: brew.repeated(), savingRecipe: true) } }
    }
}

struct BrewComparison: View {
    @Environment(\.dismiss) private var dismiss
    let brews: [Brew]
    var body: some View {
        NavigationStack {
            JournalList {
                ForEach(Array(brews.enumerated()), id: \.element.id) { index, brew in
                    Section("Cup \(index + 1) · \(brew.date.formatted(date: .abbreviated, time: .shortened))") {
                        Text(brew.recipeSummary).font(.headline)
                        LabeledContent("Taste", value: brew.score.map { "\($0)/5" } ?? "Not rated")
                        if brew.method == .espresso { LabeledContent("Flow", value: flowTitle(brew.flowRating)) }
                        if let ratio = brew.waterRatio { LabeledContent("Coffee to water", value: ratio) }
                        if !brew.notes.isEmpty { Text(brew.notes) }
                    }
                }
                if brews.count == 2, brews[0].grinder != brews[1].grinder {
                    Text("These cups use different grinders. Their setting numbers do not describe equivalent grind sizes.").font(.footnote).foregroundStyle(JournalTheme.secondaryText)
                }
            }.journalTitle("Compare cups").toolbar { Button("Done") { dismiss() }.journalAction() }
        }
    }
}

struct RecipeSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let decimals: Bool
    var unit = ""
    var showsTime = false
    private var formatted: String { format(value) }
    private func format(_ value: Double) -> String {
        if showsTime {
            guard value > 0 else { return "Not recorded" }
            return "\(Int(value) / 60):\(String(format: "%02d", Int(value) % 60))"
        }
        return value.formatted(.number.precision(.fractionLength(decimals ? 1 : 0))) + unit
    }
    private func adjust(by amount: Double) {
        value = min(range.upperBound, max(range.lowerBound, ((value + amount) / step).rounded() * step))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack { Text(title).font(.subheadline); Spacer(); Text(formatted).font(.title3.bold()).monospacedDigit() }
                VStack(alignment: .leading, spacing: 5) { Text(title).font(.subheadline); Text(formatted).font(.title3.bold()).monospacedDigit() }
            }
            HStack(spacing: 8) {
                Button { adjust(by: -step) } label: {
                    Image(systemName: "minus.circle").frame(width: 44, height: 44)
                }.buttonStyle(.plain).foregroundStyle(JournalTheme.accent)
                    .accessibilityLabel("Decrease " + title.lowercased()).disabled(value <= range.lowerBound)
                Slider(value: $value, in: range, step: step) { Text(title) }
                    .accessibilityValue(formatted)
                Button { adjust(by: step) } label: {
                    Image(systemName: "plus.circle").frame(width: 44, height: 44)
                }.buttonStyle(.plain).foregroundStyle(JournalTheme.accent)
                    .accessibilityLabel("Increase " + title.lowercased()).disabled(value >= range.upperBound)
            }
            HStack {
                Text(format(range.lowerBound))
                Spacer()
                Text(format(range.upperBound))
            }.font(.caption).foregroundStyle(JournalTheme.secondaryText).accessibilityHidden(true)
        }.padding(.vertical, 7)
    }
}

struct BrewStarRatingField: View {
    let title: String
    @Binding var rating: Int?
    @ScaledMetric(relativeTo: .body) private var starSize = 24.0
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Text(rating.map { "\($0)/5" } ?? "Not rated").font(.subheadline).foregroundStyle(JournalTheme.secondaryText)
            }
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { value in
                    Button { rating = value } label: {
                        Image(systemName: value <= (rating ?? 0) ? "star.fill" : "star")
                            .font(.system(size: min(starSize, 28)))
                            .foregroundStyle(value <= (rating ?? 0) ? JournalTheme.rating : JournalTheme.unselectedRating)
                            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("\(title): \(value) out of 5")
                }
            }
            .accessibilityElement(children: .ignore).accessibilityLabel(title)
            .accessibilityValue(rating.map { "\($0) out of 5" } ?? "Not rated")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: rating = min(5, (rating ?? 0) + 1)
                case .decrement: rating = (rating ?? 0) <= 1 ? nil : (rating ?? 1) - 1
                @unknown default: break
                }
            }
            if rating != nil { Button("Clear \(title.lowercased()) rating") { rating = nil }.font(.caption).journalAction() }
        }.padding(.vertical, 7)
    }
}

private struct MethodDraft {
    var brew: Brew
    var water: Double
    var seconds: Double
}

struct BrewEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lastBrewMethod") private var lastMethod = BrewMethod.espresso.rawValue
    @State private var brew: Brew
    let previousFeedback: String?
    let savingRecipe: Bool
    @State private var stage = 0
    @State private var output: Double
    @State private var seconds: Double
    @State private var methodDrafts: [BrewMethod: MethodDraft] = [:]
    @State private var error: String?
    @State private var initial: MethodDraft?
    @State private var confirmingDiscard = false
    @State private var initialized = false

    init(brew: Brew, previousFeedback: String? = nil, savingRecipe: Bool = false) {
        _brew = State(initialValue: brew)
        _output = State(initialValue: min(500, max(50, brew.output.rounded())))
        _seconds = State(initialValue: min(600, max(0, ((brew.seconds ?? 0) / 5).rounded() * 5)))
        self.previousFeedback = previousFeedback
        self.savingRecipe = savingRecipe
    }
    private var grindRange: ClosedRange<Double> {
        brew.method == .espresso ? 10...60 : 20...180
    }
    private func clampedGrind(_ setting: String) -> Double {
        min(grindRange.upperBound, max(grindRange.lowerBound, (Double(setting) ?? 20).rounded()))
    }
    private var grind: Binding<Double> {
        Binding(get: { clampedGrind(brew.grindSetting) }, set: { brew.grindSetting = String(Int(min(grindRange.upperBound, max(grindRange.lowerBound, $0.rounded())))) })
    }
    private var hasChanges: Bool {
        guard let initial else { return false }
        return initial.brew != brew || initial.water != output || initial.seconds != seconds
    }
    var body: some View {
        NavigationStack {
            JournalForm {
                if !savingRecipe {
                    Picker("Log a cup", selection: $stage) { Text("Recipe").tag(0); Text("Taste").tag(1) }.pickerStyle(.segmented)
                }
                if stage == 0 || savingRecipe { recipeFields }
                else { tastingFields }
                if let error { Section { InlineError(message: error) } }
            }
            .journalTitle(savingRecipe ? "Save recipe" : "Log a brew")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if hasChanges { confirmingDiscard = true } else { dismiss() } }.journalAction(fixedLabel: true).padding(.horizontal, 10).padding(.vertical, 8) }
                ToolbarItem(placement: .confirmationAction) { Button(savingRecipe ? "Save recipe" : "Save brew") { save() }.journalAction(fixedLabel: true).padding(.horizontal, 10).padding(.vertical, 8) }
            }
            .confirmationDialog("Discard your changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .interactiveDismissDisabled(hasChanges)
            .onAppear { initialize() }
        }
    }
    @ViewBuilder private var recipeFields: some View {
        Section("Recipe") {
            Picker("Coffee", selection: $brew.coffeeID) { ForEach(store.coffees) { Text($0.name).tag($0.id) } }
            Picker("Method", selection: Binding(get: { brew.method }, set: switchMethod)) {
                ForEach(BrewMethod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            RecipeSlider(title: "Coffee dose", value: $brew.dose, range: 10...25, step: 0.1, decimals: true, unit: " g")
            Picker("Grinder", selection: $brew.grinder) { Text("Blackdrop").tag("Blackdrop"); Text("Kingrinder").tag("Kingrinder") }
            RecipeSlider(title: "Grind setting", value: grind, range: grindRange, step: 1, decimals: false)
            if brew.method == .aeroPress {
                RecipeSlider(title: "AeroPress water", value: $output, range: 50...500, step: 1, decimals: false, unit: " g")
                RecipeSlider(title: "Total brew time", value: $seconds, range: 0...600, step: 5, decimals: false, showsTime: true)
                Text("Coffee to water · 1:\((output / brew.dose).formatted(.number.precision(.fractionLength(1))))").font(.footnote).foregroundStyle(JournalTheme.secondaryText)
            }
        }
        if let instructions = brew.recipeNotes, !instructions.isEmpty {
            Section("Recipe instructions") {
                Text(instructions)
            }
        }
        if !savingRecipe {
            Section {
                Button("Add tasting notes", systemImage: "star") { stage = 1 }.journalPrimary()
            }
        }
    }
    @ViewBuilder private var tastingFields: some View {
        Section {
            BrewStarRatingField(title: "How much did you enjoy it?", rating: $brew.score)
        } header: { Text("This cup") }
        if let previousFeedback, !previousFeedback.isEmpty {
            Section("Previous cup's feedback") {
                Text(previousFeedback).foregroundStyle(JournalTheme.secondaryText)
            }
        }
        Section("Observations") {
            if brew.method == .espresso {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Flow").font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(1...5, id: \.self) { value in
                                Button {
                                    brew.flowRating = brew.flowRating == value ? nil : value
                                } label: {
                                    Text(flowTitle(value))
                                        .font(.subheadline.weight(.medium))
                                        .fixedSize()
                                        .padding(.horizontal, 12)
                                        .frame(minHeight: 44)
                                        .foregroundStyle(brew.flowRating == value ? JournalTheme.surface : JournalTheme.text)
                                        .background(brew.flowRating == value ? JournalTheme.accent : JournalTheme.background, in: Capsule())
                                        .overlay(Capsule().strokeBorder(brew.flowRating == value ? JournalTheme.accent : JournalTheme.separator))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Flow: " + flowTitle(value))
                                .accessibilityAddTraits(brew.flowRating == value ? [.isSelected] : [])
                                .accessibilityHint("Tap again to clear")
                            }
                        }
                    }
                }.padding(.vertical, 7)
            }
            BrewStarRatingField(title: "Smell", rating: $brew.smellRating)
            BrewStarRatingField(title: "Color", rating: $brew.colorRating)
            BrewStarRatingField(title: "Texture", rating: $brew.textureRating)
        }
        Section("Tasting notes · optional") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 115))], alignment: .leading, spacing: 8) {
                ForEach(["Sharp / sour", "Sweet", "Bitter", "Dry / astringent", "Thin", "Heavy"], id: \.self) { note in
                    Button { toggleNote(note) } label: {
                        Label(note, systemImage: selectedNote(note) ? "checkmark.circle.fill" : "plus.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.font(.subheadline).buttonStyle(.bordered)
                        .accessibilityAddTraits(selectedNote(note) ? [.isSelected] : [])
                }
            }
            if !brew.notes.isEmpty {
                Text(brew.notes).accessibilityLabel("Tasting notes for this cup: " + brew.notes)
                Button("Clear tasting notes") { brew.notes = "" }.journalAction()
            }
        }
    }

    private func initialize() {
        guard !initialized else { return }
        if !["Blackdrop", "Kingrinder"].contains(brew.grinder) { brew.grinder = "Blackdrop" }
        brew.dose = min(25, max(10, (brew.dose * 10).rounded() / 10))
        brew.grindSetting = String(Int(clampedGrind(brew.grindSetting)))
        initial = MethodDraft(brew: brew, water: output, seconds: seconds)
        initialized = true
    }
    private func switchMethod(_ method: BrewMethod) {
        guard method != brew.method else { return }
        methodDrafts[brew.method] = MethodDraft(brew: brew, water: output, seconds: seconds)
        let identity = brew.id
        let date = brew.date
        if let cached = methodDrafts[method] {
            brew = cached.brew; output = cached.water; seconds = cached.seconds
        } else {
            brew = Brew.starting(coffeeID: brew.coffeeID, method: method, history: store.brews)
            if !["Blackdrop", "Kingrinder"].contains(brew.grinder) { brew.grinder = "Blackdrop" }
            brew.dose = min(25, max(10, (brew.dose * 10).rounded() / 10))
            brew.grindSetting = String(Int(clampedGrind(brew.grindSetting)))
            output = min(500, max(50, brew.output.rounded()))
            seconds = min(600, max(0, ((brew.seconds ?? 0) / 5).rounded() * 5))
        }
        brew.id = identity; brew.date = date
        error = nil
    }
    private var noteParts: [String] {
        brew.notes.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    private func selectedNote(_ note: String) -> Bool {
        noteParts.contains { $0.caseInsensitiveCompare(note) == .orderedSame }
    }
    private func toggleNote(_ note: String) {
        var parts = noteParts
        if selectedNote(note) { parts.removeAll { $0.caseInsensitiveCompare(note) == .orderedSame } }
        else { parts.append(note) }
        brew.notes = parts.joined(separator: ", ")
    }
    private func save() {
        error = nil
        do {
            guard let journal = store.journal else { throw JournalError.invalid("Journal unavailable. Your draft is still here.") }
            var saved = brew
            if saved.method == .aeroPress {
                saved.output = output
                saved.seconds = seconds > 0 ? seconds : nil
            } else { saved.seconds = nil }
            try saved.validate()
            saved.date = Date()
            if savingRecipe {
                var recipe = saved
                recipe.smellRating = nil; recipe.score = nil; recipe.flowRating = nil; recipe.colorRating = nil; recipe.textureRating = nil; recipe.notes = ""
                try journal.saveRecipe(recipe)
            } else { try journal.save(saved); lastMethod = saved.method.rawValue }
            try store.refresh()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

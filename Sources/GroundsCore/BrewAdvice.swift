import Foundation

public extension Brew {
    static func starting(coffeeID: UUID, method: BrewMethod, history: [Brew]) -> Brew {
        if let last = history.filter({ $0.coffeeID == coffeeID && $0.method == method }).max(by: { $0.date < $1.date }) {
            return last.repeated()
        }
        return Brew(coffeeID: coffeeID, method: method, dose: method == .espresso ? 18 : 15,
                    grindSetting: "20", output: method == .aeroPress ? 200 : 36)
    }

    var recipeSummary: String {
        var parts = ["\(dose.formatted(.number.precision(.fractionLength(0...1)))) g"]
        if method == .aeroPress {
            parts.append("\(output.formatted()) g water")
            if let seconds { parts.append("\(Int(seconds) / 60):\(String(format: "%02d", Int(seconds) % 60))") }
        }
        if !grinder.isEmpty { parts.append("\(grinder) · \(grindSetting)") }
        return parts.joined(separator: " · ")
    }

    var waterRatio: String? {
        guard method == .aeroPress, dose > 0 else { return nil }
        return "1:\((output / dose).formatted(.number.precision(.fractionLength(1))))"
    }
}

/// Observations shown as evidence always come from the journal, never a model.
public struct BrewSuggestion {
    public var recipe: Brew
    public var evidence: [Brew]
    public var summary: String
    public var assumptions: [String]

    public static func history(coffeeID: UUID, method: BrewMethod, brews: [Brew]) throws -> BrewSuggestion {
        let rated = RecipeGenerator.ratedBrews(brews, coffeeID: coffeeID, method: method)
        guard let best = rated.sorted(by: {
            $0.score == $1.score ? $0.date > $1.date : ($0.score ?? 0) > ($1.score ?? 0)
        }).first else { throw JournalError.invalid("Rate a \(method.rawValue) brew for this coffee first.") }
        return BrewSuggestion(recipe: best.repeated(), evidence: rated.sorted { $0.score == $1.score ? $0.date > $1.date : ($0.score ?? 0) > ($1.score ?? 0) },
            summary: rated.count == 1
                ? "Start from your one rated brew. This is a reference recipe, not a proven best result."
                : "Start from your highest-rated recorded brew (\(best.score ?? 0)/5). Equal scores favor the most recent brew.",
            assumptions: ["Keep the same coffee and equipment when comparing cups.",
                          "Unrecorded color, texture and flow remain unknown. Temperature was not recorded."])
    }

    public var text: String {
        var lines = [summary, "\(recipe.method.rawValue): \(recipe.recipeSummary)"]
        if let notes = recipe.recipeNotes, !notes.isEmpty { lines.append(notes) }
        if !evidence.isEmpty {
            lines.append("Based on \(evidence.count) rated \(recipe.method.rawValue) \(evidence.count == 1 ? "brew" : "brews").")
        }
        lines += assumptions
        return lines.joined(separator: "\n\n")
    }
}

/// Proposed recipe parameters only; measured observations never come from this payload.
public struct StartingRecipePlan: Codable {
    public var dose: Double
    public var seconds: Double?
    public var grindDescription: String
    public var steps: [String]
    public var assumptions: [String]

    public func validate() throws {
        guard dose.isFinite, (10...25).contains(dose),
              seconds == nil || (seconds!.isFinite && seconds! > 0 && seconds! <= 3600),
              !grindDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...12).contains(steps.count), steps.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              grindDescription.count <= 500, steps.joined().count <= 6000, assumptions.joined().count <= 3000
        else { throw JournalError.invalid("The suggested recipe could not be used. Please generate another starting recipe.") }
    }

    public func suggestion(coffeeID: UUID, method: BrewMethod, history: [Brew]) throws -> BrewSuggestion {
        try validate()
        var brew = Brew.starting(coffeeID: coffeeID, method: method, history: history)
        brew.dose = (dose * 10).rounded() / 10
        brew.seconds = method == .aeroPress ? seconds : nil
        brew.recipeNotes = (["Grind: \(grindDescription). Choose the setting that matches your grinder."] +
                            steps.enumerated().map { "\($0.offset + 1). \($0.element)" }).joined(separator: "\n")
        return BrewSuggestion(recipe: brew, evidence: [], summary: "A proposed starting recipe from the label. Review it before brewing.",
            assumptions: ["Grinder setting uses your previous recipe or a starting value; a photo cannot determine clicks.",
                          "No taste, color, texture or flow observations were inferred."] + assumptions)
    }
}

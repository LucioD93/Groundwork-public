import Foundation

public struct Coffee: Codable, Identifiable, Equatable {
 public var id: UUID
 public var name: String
 public var roaster: String
 public var origin: String
 public var roastDate: Date?
 public var photo: String?
 public var archived: Bool?
 public init(id: UUID = UUID(), name: String, roaster: String = "", origin: String = "", roastDate: Date? = nil, photo: String? = nil, archived: Bool? = nil) {
  self.id = id; self.name = name; self.roaster = roaster; self.origin = origin; self.roastDate = roastDate; self.photo = photo; self.archived = archived
 }
 public func validate() throws {
  guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw JournalError.invalid("Coffee name is required.") }
  if let roastDate { guard roastDate.timeIntervalSinceReferenceDate.isFinite else { throw JournalError.invalid("Invalid roast date.") } }
  if let photo { guard UUID(uuidString: photo) != nil else { throw JournalError.invalid("Invalid photo reference.") } }
 }
}
public enum BrewMethod: String, Codable, CaseIterable { case espresso = "Espresso", aeroPress = "AeroPress" }
public struct Brew: Codable, Identifiable, Equatable {
 public var id: UUID
 public var coffeeID: UUID
 public var method: BrewMethod
 public var dose: Double
 public var grinder: String
 public var grindSetting: String
 public var seconds: Double?
 public var output: Double
 public var smellRating: Int?
 public var colorRating: Int?
 public var textureRating: Int?
 public var flowRating: Int?
 public var score: Int?
 public var recipeNotes: String?
 public var notes: String
 public var date: Date
 public init(id: UUID = UUID(), coffeeID: UUID, method: BrewMethod = .espresso, dose: Double = 18, grinder: String = "", grindSetting: String = "", seconds: Double? = nil, output: Double = 36, notes: String = "", score: Int? = nil, flowRating: Int? = nil, colorRating: Int? = nil, textureRating: Int? = nil, smellRating: Int? = nil, date: Date = Date(), recipeNotes: String? = nil) {
 self.id = id; self.coffeeID = coffeeID; self.method = method; self.dose = dose; self.grinder = grinder; self.grindSetting = grindSetting; self.seconds = seconds; self.output = output; self.notes = notes; self.recipeNotes = recipeNotes; self.score = score; self.flowRating = flowRating; self.colorRating = colorRating; self.textureRating = textureRating; self.smellRating = smellRating; self.date = date
 }
 public func validate() throws {
 for (name, rating) in [("Smell", smellRating), ("Color", colorRating), ("Texture", textureRating)] {
 if let rating { guard (1...5).contains(rating) else { throw JournalError.invalid("\(name) rating must be between 1 and 5.") } }
 }
 if let flowRating { guard (1...5).contains(flowRating) else { throw JournalError.invalid("Flow rating must be between 1 and 5.") } }
 if let score { guard (1...5).contains(score) else { throw JournalError.invalid("Score must be between 1 and 5.") } }
 guard dose.isFinite, dose > 0 else { throw JournalError.invalid("Dose must be a positive number.") }
 if method == .aeroPress { guard output.isFinite, output > 0 else { throw JournalError.invalid("Water must be a positive number.") } }
 if let seconds { guard seconds.isFinite, seconds > 0 else { throw JournalError.invalid("Brew time must be positive or empty.") } }
 guard !grinder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !grindSetting.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw JournalError.invalid("Grinder and grind setting are required.") }
 guard date.timeIntervalSince1970.isFinite else { throw JournalError.invalid("Invalid brew date.") }
 }
 public func repeated(at date: Date = Date()) -> Brew { var copy = self; copy.id = UUID(); copy.date = date; copy.smellRating = nil; copy.score = nil; copy.flowRating = nil; copy.colorRating = nil; copy.textureRating = nil; copy.notes = ""; return copy }
}
public enum JournalError: Error, LocalizedError {
 case invalid(String), database(String)
 public var errorDescription: String? { switch self { case .invalid(let s), .database(let s): return s } }
}
public struct Backup: Codable {
 public var schemaVersion: Int
 public var coffees: [Coffee]
 public var brews: [Brew]
 public var photos: [String: Data]
 public var recipes: [Brew]?
 public init(schemaVersion: Int = 1, coffees: [Coffee], brews: [Brew], photos: [String: Data], recipes: [Brew]? = nil) { self.schemaVersion = schemaVersion; self.coffees = coffees; self.brews = brews; self.photos = photos; self.recipes = recipes }
}

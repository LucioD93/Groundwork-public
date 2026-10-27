import Foundation

public struct CoffeePhotoDetails: Decodable {
 public let name: String?
 public let roaster: String?
 public let origin: String?
 public let roastDate: String?
 public var parsedRoastDate: Date? {
  guard let roastDate else { return nil }
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.calendar = Calendar(identifier: .gregorian)
  formatter.timeZone = .current
  formatter.dateFormat = "yyyy-MM-dd"
  formatter.isLenient = false
  guard roastDate.count == 10, let date = formatter.date(from: roastDate), formatter.string(from: date) == roastDate else { return nil }
  return date
 }
 public static func parse(_ data: Data) throws -> Self {
  let result = try JSONDecoder().decode(Self.self, from: data)
  guard [result.name, result.roaster, result.origin].contains(where: { !($0?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }) || result.parsedRoastDate != nil else {
   throw JournalError.invalid("No readable coffee details were found. Try a clearer photo of the label or enter them manually.")
  }
  return result
 }
 /// Only extracted, nonempty values replace fields; unknown fields preserve manual input.
 public func applying(to coffee: Coffee) -> Coffee {
  var copy = coffee
  if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines) }
  if let roaster, !roaster.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { copy.roaster = roaster.trimmingCharacters(in: .whitespacesAndNewlines) }
  if let origin, !origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { copy.origin = origin.trimmingCharacters(in: .whitespacesAndNewlines) }
  if let date = parsedRoastDate { copy.roastDate = date }
  return copy
 }
}

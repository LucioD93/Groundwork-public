import Foundation
import GroundsCore
func XCTAssertTrue(_ value: @autoclosure () throws -> Bool) { do { let result = try value(); precondition(result) } catch { fatalError("Unexpected error: \(error)") } }
func XCTAssertEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T) { do { let a = try lhs(); let b = try rhs(); precondition(a == b, "Equality failed") } catch { fatalError("Unexpected error: \(error)") } }
func XCTAssertNotEqual<T: Equatable>(_ lhs: T, _ rhs: T) { precondition(lhs != rhs) }
func XCTAssertThrowsError<T>(_ body: @autoclosure () throws -> T) { do { _ = try body(); fatalError("Expected error") } catch {} }

final class JournalTests {
 var roots: [URL] = []
 func make() throws -> Journal { let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); roots.append(url); return try Journal(directory: url) }
 func tearDown() { for root in roots { try? FileManager.default.removeItem(at: root) } }
 func testPersistenceAndRelationships() throws {
 let j = try make(); let c = Coffee(name: "Coffee"); try j.save(c)
 let b = Brew(coffeeID: c.id, grinder: "Hand grinder", grindSetting: "12 clicks"); try j.save(b)
 let reopened = try Journal(directory: j.directory)
 XCTAssertEqual(try reopened.coffees(), [c]); XCTAssertEqual(try reopened.brews(coffeeID: c.id), [b])
 try j.deleteCoffee(c.id); XCTAssertTrue(try j.brews().isEmpty)
 XCTAssertThrowsError(try j.save(b))
 }
 func testValidationAndRepeat() throws {
 XCTAssertThrowsError(try Coffee(name: "  ").validate())
 let b = Brew(coffeeID: UUID(), grinder: "K", grindSetting: "1.4", seconds: 30, notes: "Sweet")
 let date = Date(timeIntervalSince1970: 123); let copy = b.repeated(at: date)
 XCTAssertNotEqual(copy.id, b.id); XCTAssertEqual(copy.date, date)
 var expected = b; expected.id = copy.id; expected.date = date; XCTAssertEqual(copy, expected)
 var bad = b; bad.dose = .nan; XCTAssertThrowsError(try bad.validate()); bad = b; bad.seconds = -1; XCTAssertThrowsError(try bad.validate())
 }
 func testBackupRoundTripPhotosAndIdempotency() throws {
 let source = try make(); let bytes = Data([0,1,2,3,255]); let photo = try source.storePhoto(bytes)
 let c = Coffee(name: "Test", photo: photo); try source.save(c)
 let b = Brew(coffeeID: c.id, method: .aeroPress, grinder: "K", grindSetting: "25", output: 240); try source.save(b)
 let data = try source.exportBackup(); let target = try make(); try target.importBackup(data); try target.importBackup(data)
 XCTAssertEqual(try target.coffees(), [c]); XCTAssertEqual(try target.brews(), [b]); XCTAssertEqual(try Data(contentsOf: target.photosDirectory.appendingPathComponent(photo)), bytes)
 }
 func testInvalidImportIsAtomicAndNonDestructive() throws {
 let j = try make(); let c = Coffee(name: "Existing"); try j.save(c)
 let new = Coffee(name: "New"); let orphan = Brew(coffeeID: UUID(), grinder: "K", grindSetting: "1")
 XCTAssertThrowsError(try j.importBackup(JSONEncoder().encode(Backup(coffees: [new], brews: [orphan], photos: [:]))))
 var changed = c; changed.name = "Changed"
 XCTAssertThrowsError(try j.importBackup(JSONEncoder().encode(Backup(coffees: [new, changed], brews: [], photos: [:]))))
 let photoID = try j.storePhoto(Data([1]))
 let photoCoffee = Coffee(name: "Conflict photo", photo: photoID)
 XCTAssertThrowsError(try j.importBackup(JSONEncoder().encode(Backup(coffees: [photoCoffee], brews: [], photos: [photoID: Data([2])]))))
 XCTAssertEqual(try Data(contentsOf: j.photosDirectory.appendingPathComponent(photoID)), Data([1]))
 XCTAssertEqual(try j.coffees(), [c])
 XCTAssertThrowsError(try j.importBackup(JSONEncoder().encode(Backup(schemaVersion: 2, coffees: [], brews: [], photos: [:]))))
 let missing = Coffee(name: "Photo", photo: UUID().uuidString)
 XCTAssertThrowsError(try j.importBackup(JSONEncoder().encode(Backup(coffees: [missing], brews: [], photos: [:]))))
 }
}

let suite = JournalTests()
defer { suite.tearDown() }
try suite.testPersistenceAndRelationships()
try suite.testValidationAndRepeat()
try suite.testBackupRoundTripPhotosAndIdempotency()
try suite.testInvalidImportIsAtomicAndNonDestructive()
print("PASS: 4 verification suites (persistence, relationships, validation, repeat, photo backup, atomic import)")

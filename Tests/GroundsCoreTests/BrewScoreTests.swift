import XCTest
import CSQLite
@testable import GroundsCore

final class BrewScoreTests: XCTestCase {
 func testScorePersistenceBackupAndLegacyDecoding() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let other = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: other) }
  let journal = try Journal(directory: root)
  let coffee = Coffee(name: "Rated coffee"); try journal.save(coffee)
  let brew = Brew(coffeeID: coffee.id, grinder: "Hand", grindSetting: "12", score: 5)
  try journal.save(brew)
  XCTAssertEqual(try Journal(directory: root).brews().first?.score, 5)
  let restored = try Journal(directory: other); try restored.importBackup(journal.exportBackup())
  XCTAssertEqual(try restored.brews(), [brew])
  var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(brew)) as? [String: Any])
  json.removeValue(forKey: "score")
  XCTAssertNil(try JSONDecoder().decode(Brew.self, from: JSONSerialization.data(withJSONObject: json)).score)
  XCTAssertNil(brew.repeated().score)
  for score in [0, 6] { var invalid = brew; invalid.score = score; XCTAssertThrowsError(try journal.save(invalid)) }
 }
 func testMigratesExistingDatabase() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  var db: OpaquePointer?
  XCTAssertEqual(sqlite3_open(root.appendingPathComponent("journal.sqlite").path, &db), SQLITE_OK)
  let coffee = UUID(), brew = UUID()
  let sql = """
  CREATE TABLE coffee(id TEXT PRIMARY KEY,name TEXT,roaster TEXT,origin TEXT,roast_date REAL,photo TEXT);
  CREATE TABLE brew(id TEXT PRIMARY KEY,coffee_id TEXT,method TEXT,dose REAL,grinder TEXT,grind_setting TEXT,seconds REAL,output REAL,notes TEXT,date REAL);
  INSERT INTO coffee VALUES('\(coffee)','Legacy','','',NULL,NULL);
  INSERT INTO brew VALUES('\(brew)','\(coffee)','Espresso',18,'Hand','12',30,36,'Sweet',0);
  PRAGMA user_version=1;
  """
  XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK); sqlite3_close(db)
  let journal = try Journal(directory: root)
  var migrated = try XCTUnwrap(journal.brews().first)
  XCTAssertEqual(migrated.id, brew); XCTAssertNil(migrated.score)
  migrated.score = 4; try journal.save(migrated)
  XCTAssertEqual(try Journal(directory: root).brews().first?.score, 4)
 }
 func testHistorySelectionSeparatesCoffeeMethodAndUnratedBrews() {
  let coffee = UUID()
  let rated = Brew(coffeeID: coffee, score: 4)
  XCTAssertEqual(RecipeGenerator.ratedBrews([rated, Brew(coffeeID: coffee), Brew(coffeeID: UUID(), score: 5), Brew(coffeeID: coffee, method: .aeroPress, score: 5)], coffeeID: coffee, method: .espresso), [rated])
  let many = (0..<40).map { Brew(coffeeID: coffee, score: 3, date: Date(timeIntervalSince1970: Double($0))) }
  let selected = RecipeGenerator.ratedBrews(many, coffeeID: coffee, method: .espresso)
  XCTAssertEqual(selected.count, 30); XCTAssertEqual(selected.first, many.last)
 }
 func testSuggestionRequiresRatedHistory() async {
  do {
   _ = try await RecipeGenerator().suggest(coffee: Coffee(name: "Coffee"), method: .espresso, brews: [], apiKey: "unused")
   XCTFail("Expected missing history error")
  } catch { XCTAssertTrue(error.localizedDescription.contains("Rate at least one")) }
 }
}

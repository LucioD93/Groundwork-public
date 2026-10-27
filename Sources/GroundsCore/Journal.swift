import Foundation
import CSQLite

public final class Journal {
 private var db: OpaquePointer?
 public let directory: URL
 public var photosDirectory: URL { directory.appendingPathComponent("Photos", isDirectory: true) }
 public init(directory: URL) throws {
 self.directory = directory
 try FileManager.default.createDirectory(at: directory.appendingPathComponent("Photos"), withIntermediateDirectories: true)
 guard sqlite3_open(directory.appendingPathComponent("journal.sqlite").path, &db) == SQLITE_OK else { throw JournalError.database("Cannot open journal.") }
 do { try execute("PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL; CREATE TABLE IF NOT EXISTS coffee(id TEXT PRIMARY KEY, name TEXT NOT NULL, roaster TEXT NOT NULL, origin TEXT NOT NULL, roast_date REAL, photo TEXT); CREATE TABLE IF NOT EXISTS brew(id TEXT PRIMARY KEY, coffee_id TEXT NOT NULL REFERENCES coffee(id) ON DELETE CASCADE, method TEXT NOT NULL, dose REAL NOT NULL, grinder TEXT NOT NULL, grind_setting TEXT NOT NULL, seconds REAL, output REAL NOT NULL, notes TEXT NOT NULL, date REAL NOT NULL);")
 // A nullable column preserves all existing brews and version-1 backups.
 let columns = try statement("PRAGMA table_info(brew)")
 var hasScore = false
 var hasFlowRating = false
 var ratingColumns = Set<String>()
 while sqlite3_step(columns) == SQLITE_ROW { ratingColumns.insert(string(columns, 1)); if string(columns, 1) == "score" { hasScore = true }; if string(columns, 1) == "flow_rating" { hasFlowRating = true } }
 sqlite3_finalize(columns)
 if !hasScore { try execute("ALTER TABLE brew ADD COLUMN score INTEGER") }
 if !hasFlowRating { try execute("ALTER TABLE brew ADD COLUMN flow_rating INTEGER") }
 for column in ["color_rating", "texture_rating", "smell_rating"] where !ratingColumns.contains(column) { try execute("ALTER TABLE brew ADD COLUMN \(column) INTEGER") }
 if !ratingColumns.contains("recipe_notes") { try execute("ALTER TABLE brew ADD COLUMN recipe_notes TEXT") }
 let coffeeColumns = try statement("PRAGMA table_info(coffee)")
 var hasArchived = false
 while sqlite3_step(coffeeColumns) == SQLITE_ROW { if string(coffeeColumns, 1) == "archived" { hasArchived = true } }
 sqlite3_finalize(coffeeColumns)
 if !hasArchived { try execute("ALTER TABLE coffee ADD COLUMN archived INTEGER NOT NULL DEFAULT 0") }
 try execute("CREATE TABLE IF NOT EXISTS recipe(id TEXT PRIMARY KEY, coffee_id TEXT NOT NULL REFERENCES coffee(id) ON DELETE CASCADE, data TEXT NOT NULL); PRAGMA user_version=6")
 } catch { sqlite3_close(db); db = nil; throw error }
 }
 deinit { sqlite3_close(db) }
 private func execute(_ sql: String) throws { guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw JournalError.database(String(cString: sqlite3_errmsg(db))) } }
 private func statement(_ sql: String, _ values: [Any?] = []) throws -> OpaquePointer {
 var p: OpaquePointer?
 guard sqlite3_prepare_v2(db, sql, -1, &p, nil) == SQLITE_OK, let p else { throw JournalError.database(String(cString: sqlite3_errmsg(db))) }
 for (i, v) in values.enumerated() { let index = Int32(i + 1)
 if let s = v as? String { sqlite3_bind_text(p, index, s, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
 else if let d = v as? Double { sqlite3_bind_double(p, index, d) }
 else { sqlite3_bind_null(p, index) }
 }
 return p
 }
 private func write(_ sql: String, _ values: [Any?]) throws { let p = try statement(sql, values); defer { sqlite3_finalize(p) }; guard sqlite3_step(p) == SQLITE_DONE else { throw JournalError.database(String(cString: sqlite3_errmsg(db))) } }
 private func string(_ p: OpaquePointer, _ i: Int32) -> String { String(cString: sqlite3_column_text(p, i)) }
 private func optionalDouble(_ p: OpaquePointer, _ i: Int32) -> Double? { sqlite3_column_type(p, i) == SQLITE_NULL ? nil : sqlite3_column_double(p, i) }
 public func coffees() throws -> [Coffee] {
 let p = try statement("SELECT id,name,roaster,origin,roast_date,photo,archived FROM coffee ORDER BY name COLLATE NOCASE"); defer { sqlite3_finalize(p) }; var result: [Coffee] = []
 while sqlite3_step(p) == SQLITE_ROW { result.append(Coffee(id: UUID(uuidString: string(p,0))!, name: string(p,1), roaster: string(p,2), origin: string(p,3), roastDate: optionalDouble(p,4).map(Date.init(timeIntervalSinceReferenceDate:)), photo: sqlite3_column_type(p,5) == SQLITE_NULL ? nil : string(p,5), archived: sqlite3_column_int(p,6) == 0 ? nil : true)) }; return result
 }
 public func brews(coffeeID: UUID? = nil) throws -> [Brew] {
 let p = try statement("SELECT id,coffee_id,method,dose,grinder,grind_setting,seconds,output,notes,date,score,flow_rating,color_rating,texture_rating,recipe_notes,smell_rating FROM brew" + (coffeeID == nil ? "" : " WHERE coffee_id=?") + " ORDER BY date DESC", coffeeID.map { [$0.uuidString] } ?? []); defer { sqlite3_finalize(p) }; var result: [Brew] = []
 while sqlite3_step(p) == SQLITE_ROW { result.append(Brew(id: UUID(uuidString: string(p,0))!, coffeeID: UUID(uuidString: string(p,1))!, method: BrewMethod(rawValue: string(p,2))!, dose: sqlite3_column_double(p,3), grinder: string(p,4), grindSetting: string(p,5), seconds: optionalDouble(p,6), output: sqlite3_column_double(p,7), notes: string(p,8), score: optionalDouble(p,10).map { Int($0) }, flowRating: optionalDouble(p,11).map { Int($0) }, colorRating: optionalDouble(p,12).map { Int($0) }, textureRating: optionalDouble(p,13).map { Int($0) }, smellRating: optionalDouble(p,15).map { Int($0) }, date: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(p,9)), recipeNotes: sqlite3_column_type(p,14) == SQLITE_NULL ? nil : string(p,14))) }; return result
 }
 public func save(_ c: Coffee) throws { try c.validate(); if let photo = c.photo { guard FileManager.default.fileExists(atPath: photosDirectory.appendingPathComponent(photo).path) else { throw JournalError.invalid("Photo file is missing.") } }; try write("INSERT INTO coffee(id,name,roaster,origin,roast_date,photo,archived) VALUES(?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,roaster=excluded.roaster,origin=excluded.origin,roast_date=excluded.roast_date,photo=excluded.photo,archived=excluded.archived", [c.id.uuidString,c.name,c.roaster,c.origin,c.roastDate?.timeIntervalSinceReferenceDate,c.photo,c.archived == true ? 1.0 : 0.0]) }
 public func save(_ b: Brew) throws { try b.validate(); try write("INSERT INTO brew(id,coffee_id,method,dose,grinder,grind_setting,seconds,output,notes,date,score,flow_rating,color_rating,texture_rating,recipe_notes,smell_rating) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET coffee_id=excluded.coffee_id,method=excluded.method,dose=excluded.dose,grinder=excluded.grinder,grind_setting=excluded.grind_setting,seconds=excluded.seconds,output=excluded.output,notes=excluded.notes,date=excluded.date,score=excluded.score,flow_rating=excluded.flow_rating,color_rating=excluded.color_rating,texture_rating=excluded.texture_rating,recipe_notes=excluded.recipe_notes,smell_rating=excluded.smell_rating", [b.id.uuidString,b.coffeeID.uuidString,b.method.rawValue,b.dose,b.grinder,b.grindSetting,b.seconds,b.output,b.notes,b.date.timeIntervalSinceReferenceDate,b.score.map(Double.init),b.flowRating.map(Double.init),b.colorRating.map(Double.init),b.textureRating.map(Double.init),b.recipeNotes,b.smellRating.map(Double.init)]) }
 public func recipes() throws -> [Brew] {
 let p = try statement("SELECT data FROM recipe ORDER BY rowid DESC"); defer { sqlite3_finalize(p) }
 var result: [Brew] = []
 while sqlite3_step(p) == SQLITE_ROW { result.append(try JSONDecoder().decode(Brew.self, from: Data(string(p,0).utf8))) }
 return result
 }
 public func saveRecipe(_ brew: Brew) throws {
 try brew.validate()
 let data = String(decoding: try JSONEncoder().encode(brew), as: UTF8.self)
 try write("INSERT INTO recipe(id,coffee_id,data) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET coffee_id=excluded.coffee_id,data=excluded.data", [brew.id.uuidString,brew.coffeeID.uuidString,data])
 }
 public func deleteRecipe(_ id: UUID) throws { try write("DELETE FROM recipe WHERE id=?", [id.uuidString]) }
 public func deleteCoffee(_ id: UUID) throws { try write("DELETE FROM coffee WHERE id=?", [id.uuidString]) }
 public func deleteBrew(_ id: UUID) throws { try write("DELETE FROM brew WHERE id=?", [id.uuidString]) }
 public func storePhoto(_ data: Data) throws -> String { guard !data.isEmpty else { throw JournalError.invalid("Empty photo.") }; let name = UUID().uuidString; try data.write(to: photosDirectory.appendingPathComponent(name), options: .atomic); return name }
 public func exportBackup() throws -> Data {
 let coffees = try coffees(); var photos: [String: Data] = [:]
 for c in coffees { if let name = c.photo { photos[name] = try Data(contentsOf: photosDirectory.appendingPathComponent(name)) } }
 return try JSONEncoder().encode(Backup(coffees: coffees, brews: brews(), photos: photos, recipes: recipes()))
 }
 /// Additive import: colliding IDs must be identical; otherwise the entire import fails.
 public func importBackup(_ data: Data) throws {
 let backup = try JSONDecoder().decode(Backup.self, from: data)
 guard backup.schemaVersion == 1 else { throw JournalError.invalid("Unsupported backup version.") }
 let ids = Set(backup.coffees.map(\.id))
 guard ids.count == backup.coffees.count, Set(backup.brews.map(\.id)).count == backup.brews.count else { throw JournalError.invalid("Duplicate IDs in backup.") }
 for c in backup.coffees { try c.validate(); if let p = c.photo { guard let bytes = backup.photos[p], !bytes.isEmpty else { throw JournalError.invalid("Missing photo data.") } } }
 for (name, bytes) in backup.photos { guard UUID(uuidString: name) != nil, !bytes.isEmpty else { throw JournalError.invalid("Invalid photo data.") } }
 let importedRecipes = backup.recipes ?? []
 guard Set(importedRecipes.map(\.id)).count == importedRecipes.count else { throw JournalError.invalid("Duplicate saved recipes in backup.") }
 for b in backup.brews + importedRecipes { try b.validate(); guard ids.contains(b.coffeeID) else { throw JournalError.invalid("Brew references missing coffee.") } }
 let existingC = Dictionary(uniqueKeysWithValues: try coffees().map { ($0.id, $0) }); let existingB = Dictionary(uniqueKeysWithValues: try brews().map { ($0.id, $0) })
 for c in backup.coffees { if let old = existingC[c.id], old != c { throw JournalError.invalid("A coffee ID conflicts. No records were imported.") } }
 for b in backup.brews { if let old = existingB[b.id], old != b { throw JournalError.invalid("A brew ID conflicts. No records were imported.") } }
 let existingRecipes = Dictionary(uniqueKeysWithValues: try recipes().map { ($0.id, $0) })
 for recipe in importedRecipes { if let old = existingRecipes[recipe.id], old != recipe { throw JournalError.invalid("A saved recipe has changed since this backup. Nothing was imported.") } }
 var created: [URL] = []
 try execute("BEGIN IMMEDIATE")
 do {
 for (name, bytes) in backup.photos { let url = photosDirectory.appendingPathComponent(name); if FileManager.default.fileExists(atPath: url.path) { guard try Data(contentsOf: url) == bytes else { throw JournalError.invalid("Photo conflict.") } } else { try bytes.write(to: url, options: .atomic); created.append(url) } }
 for c in backup.coffees { try save(c) }; for b in backup.brews { try save(b) }; for recipe in importedRecipes { try saveRecipe(recipe) }
 try execute("COMMIT")
 } catch { try? execute("ROLLBACK"); for url in created { try? FileManager.default.removeItem(at: url) }; throw error }
 }
}

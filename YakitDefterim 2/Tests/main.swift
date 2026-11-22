import Foundation
let vehicle = Vehicle(name: "Test")
func fill(_ km: Double, _ liters: Double, full: Bool = true, missed: Bool = false) -> Entry { Entry(vehicleID: vehicle.id, odometer: km, amount: liters * 50, liters: liters, fullTank: full, missedFill: missed) }
func check(_ condition: Bool, _ name: String) { if !condition { fatalError(name) }; print("PASS: \(name)") }
check(Metrics.average([]) == nil, "empty history")
check(Metrics.average([fill(100, 40)]) == nil, "single full tank is baseline")
check(abs(Metrics.average([fill(100, 40), fill(600, 30)])! - 6) < 0.0001, "full to full")
check(abs(Metrics.average([fill(100, 40), fill(350, 15, full: false), fill(600, 20)])! - 7) < 0.0001, "partial fills accumulated")
check(Metrics.average([fill(100, 40), fill(600, 30, missed: true)]) == nil, "missed fill resets baseline")
check(Metrics.average([fill(100, 40), fill(600, 30, full: false)]) == nil, "unfinished interval excluded")
check(abs(Metrics.average([fill(100, 40), fill(600, 30), fill(1600, 80)])! - 110.0/1500*100) < 0.0001, "distance weighted average")
var entry = fill(1200, 40); entry.note = "Virgül, çift \"tırnak\"\nve yeni satır"; entry.station = "İstanbul"
let csv = CSV.export([entry]); let restored = try CSV.parse(csv, vehicleID: vehicle.id)
check(restored.count == 1 && restored[0].note == entry.note && restored[0].station == entry.station, "CSV unicode quote newline round trip")
var db = Database(); db.vehicles = [vehicle]; db.entries = [entry]; db.selectedID = vehicle.id
try DataValidation.validate(db)
let copy = try JSONDecoder().decode(Database.self, from: JSONEncoder().encode(db)); try DataValidation.validate(copy)
check(copy.entries == db.entries, "JSON round trip")
var invalid = db; invalid.entries[0].liters = -5
var rejected = false; do { try DataValidation.validate(invalid) } catch { rejected = true }
check(rejected, "invalid amounts rejected")
invalid = db; invalid.entries[0].vehicleID = UUID(); rejected = false
 do { try DataValidation.validate(invalid) } catch { rejected = true }; check(rejected, "orphan vehicle rejected")
invalid = db; invalid.entries.append(entry); rejected = false
 do { try DataValidation.validate(invalid) } catch { rejected = true }; check(rejected, "duplicate IDs rejected")
let legacyData = Data("{\"version\":1,\"vehicles\":[],\"entries\":[],\"reminders\":[],\"trips\":[]}".utf8)
let legacy = try JSONDecoder().decode(Database.self, from: legacyData)
check(legacy.autoRecordCarPlay == nil, "legacy backup keeps automatic recording off")
var enabled = legacy; enabled.autoRecordCarPlay = true
let enabledCopy = try JSONDecoder().decode(Database.self, from: JSONEncoder().encode(enabled))
check(enabledCopy.autoRecordCarPlay == true, "automatic recording preference round trip")
var custom = db
custom.calculatorDrafts = [vehicle.id.uuidString: CalculatorDraft(distance: "246,5", consumption: "9,2", price: "49,90", fuel: "25")]
custom.stationFilters = StationFilters(radiusKM: 25, brand: "Opet")
custom.stationPrices = ["test-station": StationPriceNote(petrol: 50, lpg: 25)]
let customCopy = try JSONDecoder().decode(Database.self, from: JSONEncoder().encode(custom))
try DataValidation.validate(customCopy)
check(customCopy.calculatorDrafts?[vehicle.id.uuidString]?.consumption == "9,2", "custom calculator comma values survive backup")
check(customCopy.stationFilters?.radiusKM == 25 && customCopy.stationFilters?.brand == "Opet", "search preferences survive backup")
check(customCopy.stationPrices?["test-station"]?.lpg == 25, "station price note survives backup")
check(legacy.calculatorDrafts == nil && legacy.stationFilters == nil && legacy.stationPrices == nil, "old database supports new optional settings")
check(StationFilters(radiusKM: 10, brand: "Opet").matches("OPET Akaryakıt") && !StationFilters(radiusKM: 10, brand: "Opet").matches("Shell"), "brand filtering")
check(!StationFilters(radiusKM: 10, brand: "BP").matches("Bpet") && StationFilters(radiusKM: 10, brand: "BP").matches("BP İstasyon"), "short brand avoids substring match")
let reportNow = Date(timeIntervalSince1970: 1_800_000_000)
var firstFill = fill(1000, 50); firstFill.date = reportNow.addingTimeInterval(-40*86400)
var partialFill = fill(1250, 15, full: false); partialFill.date = reportNow.addingTimeInterval(-20*86400)
var finalFill = fill(1500, 20); finalFill.date = reportNow.addingTimeInterval(-10*86400)
let completed = Trip(vehicleID: vehicle.id, start: reportNow.addingTimeInterval(-7200), end: reportNow.addingTimeInterval(-3600), distance: 60)
let unfinished = Trip(vehicleID: vehicle.id, start: reportNow.addingTimeInterval(-600), distance: 8)
let snapshot = ReportSnapshot.make(entries: [firstFill, partialFill, finalFill], trips: [completed, unfinished], since: reportNow.addingTimeInterval(-30*86400), now: reportNow)
check(abs(snapshot.averageConsumption! - 7) < 0.0001, "period report keeps baseline outside date window")
check(snapshot.entries.count == 2 && snapshot.totalCost == 1750, "report expenses respect date window")
check(snapshot.trips.count == 1 && snapshot.averageSpeed == 60, "average trip speed excludes active trips")
let emptyReport = ReportSnapshot.make(entries: [], trips: [], since: nil, now: reportNow)
check(emptyReport.costPerKM == nil && emptyReport.averagePrice == nil && emptyReport.averageSpeed == nil, "missing report data stays unavailable")
let opetFilter = StationFilters(radiusKM: 5, brand: "Opet")
check(opetFilter.includes(name: "OPET", distanceMeters: 4999), "selected brand inside radius is included")
check(!opetFilter.includes(name: "OPET", distanceMeters: 5001), "selected brand outside radius is excluded")
check(!opetFilter.includes(name: "Shell", distanceMeters: 100), "other brand is excluded even when nearby")
check(!opetFilter.includes(name: "OPET", distanceMeters: .nan), "invalid station distance is excluded")
check(StationFilters(radiusKM: 25, brand: "Tümü").includes(name: "Shell", distanceMeters: 20000), "larger radius and all brands work together")
var englishDB = db; englishDB.language = "en"
let englishCopy = try JSONDecoder().decode(Database.self, from: JSONEncoder().encode(englishDB))
try DataValidation.validate(englishCopy)
check(englishCopy.language == "en" && englishCopy.entries == db.entries, "language preference persists without translating stored records")
check(legacy.language == nil, "legacy backups retain default Turkish")
var invalidLanguage = db; invalidLanguage.language = "invalid"; rejected = false
do { try DataValidation.validate(invalidLanguage) } catch { rejected = true }
check(rejected, "unsupported language is rejected")

let recoveryFile = URL(fileURLWithPath: "/unused-database-test.json")
let originalBytes = try JSONEncoder().encode(db)
var accessDenied = true
var writtenBytes: Data?
let recoveringDisk = DatabaseDisk(file: recoveryFile, read: { _ in
    if accessDenied { throw CocoaError(.fileReadNoPermission) }
    return originalBytes
}, write: { data, _ in writtenBytes = data })
rejected = false
do { _ = try recoveringDisk.load(allowMissing: true) } catch { rejected = true }
check(rejected && !recoveringDisk.writable, "permission denial never becomes an empty database")
rejected = false
do { try recoveringDisk.save(Database()) } catch { rejected = true }
check(rejected && writtenBytes == nil, "writes blocked after failed read preserve existing bytes")
accessDenied = false
let recoveredDB = try recoveringDisk.load(allowMissing: true)
check(recoveredDB.vehicles == db.vehicles && recoveredDB.entries == db.entries, "unlock retry restores original vehicle and records")
try recoveringDisk.save(recoveredDB)
check(try JSONDecoder().decode(Database.self, from: writtenBytes!).entries == db.entries, "writes resume only after successful recovery")
let missingDisk = DatabaseDisk(file: recoveryFile, read: { _ in throw CocoaError(.fileReadNoSuchFile) }, write: { _, _ in fatalError("unexpected write") })
rejected = false
do { _ = try missingDisk.load(allowMissing: false) } catch { rejected = true }
check(rejected && !missingDisk.writable, "unavailable protected data cannot initialize a missing database")
let fresh = try missingDisk.load(allowMissing: true)
check(fresh.vehicles.isEmpty && missingDisk.writable, "confirmed missing file initializes only when allowed")
var corruptWrites = 0
let corruptDisk = DatabaseDisk(file: recoveryFile, read: { _ in Data("broken-json".utf8) }, write: { _, _ in corruptWrites += 1 })
rejected = false
do { _ = try corruptDisk.load(allowMissing: true) } catch { rejected = true }
check(rejected && !corruptDisk.writable && corruptWrites == 0, "corrupt database is never overwritten during recovery")
// Real disk round-trip also exercises the atomic writer used by the repository.
let testFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: testFolder, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: testFolder) }
let actualDisk = DatabaseDisk(file: testFolder.appendingPathComponent("database.json"))
_ = try actualDisk.load(allowMissing: true)
try actualDisk.save(db)
let actualReload = try DatabaseDisk(file: actualDisk.file).load(allowMissing: false)
check(actualReload.vehicles == db.vehicles && actualReload.entries == db.entries, "atomic disk save and reload retain records")

var measured = CalculatorDraft()
measured.measuredLiters = "40"
measured.measuredDistance = "500"
check(measured.measuredConsumption == 8, "liters and distance produce L per 100 km")
measured.measuredLiters = "40,5"
check(measured.measuredConsumption == 8.1, "manual consumption accepts decimal comma")
for invalid in ["0", "-1", "nan", "inf", ""] {
    measured.measuredDistance = invalid
    check(measured.measuredConsumption == nil, "invalid manual distance rejected: " + invalid)
}
let oldDraft = try JSONDecoder().decode(CalculatorDraft.self, from: Data(#"{"distance":"100","consumption":"8","price":"45","fuel":"20"}"#.utf8))
check(oldDraft.measuredConsumption == nil && oldDraft.consumption == "8", "legacy calculator keeps chosen consumption")
measured.measuredDistance = "500"
let measuredReload = try JSONDecoder().decode(CalculatorDraft.self, from: JSONEncoder().encode(measured))
check(measuredReload == measured && measuredReload.measuredConsumption == 8.1, "manual inputs survive backup round trip")

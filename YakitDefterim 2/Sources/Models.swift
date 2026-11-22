import Foundation

struct Vehicle: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var plate: String = ""
    var fuel: String = "Benzin"
    var currency: String = "TRY"
}
struct Entry: Codable, Identifiable, Hashable {
    var id = UUID()
    var vehicleID: UUID
    var date = Date()
    var kind = "Yakıt"
    var odometer: Double
    var amount: Double
    var liters: Double = 0
    var fullTank = true
    var missedFill = false
    var station = ""
    var note = ""
}
struct Reminder: Codable, Identifiable, Hashable {
    var id = UUID()
    var vehicleID: UUID
    var title: String
    var date: Date?
    var odometer: Double?
    var done = false
}
struct RoutePoint: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var date: Date
}
struct Trip: Codable, Identifiable, Hashable {
    var id = UUID()
    var vehicleID: UUID
    var start = Date()
    var end: Date?
    var distance: Double = 0
    var purpose = "Kişisel"
    var points: [RoutePoint] = []
}
struct Database: Codable {
    var version = 1
    var vehicles: [Vehicle] = []
    var entries: [Entry] = []
    var reminders: [Reminder] = []
    var trips: [Trip] = []
    var selectedID: UUID?
    // Optional for compatibility with backups created before this setting existed.
    var autoRecordCarPlay: Bool?
    var calculatorDrafts: [String: CalculatorDraft]?
    var stationFilters: StationFilters?
    var language: String?
    var stationPrices: [String: StationPriceNote]?
}
struct Consumption: Identifiable {
    var id: UUID
    var date: Date
    var distance: Double
    var liters: Double
    var rate: Double { liters / distance * 100 }
}
enum Metrics {
    // Full-to-full intervals include intervening partial fills. Unknown fills reset the baseline.
    static func consumption(_ entries: [Entry]) -> [Consumption] {
        let fills = entries.filter { $0.kind == "Yakıt" }.sorted { $0.odometer < $1.odometer }
        var baseline: Double?
        var liters = 0.0
        var result: [Consumption] = []
        for fill in fills {
            if fill.missedFill { baseline = nil; liters = 0 }
            if let start = baseline {
                liters += fill.liters
                if fill.fullTank, fill.odometer > start {
                    result.append(Consumption(id: fill.id, date: fill.date, distance: fill.odometer - start, liters: liters))
                    baseline = fill.odometer; liters = 0
                }
            } else if fill.fullTank { baseline = fill.odometer; liters = 0 }
        }
        return result
    }
    static func average(_ entries: [Entry]) -> Double? {
        let samples = consumption(entries)
        let distance = samples.reduce(0) { $0 + $1.distance }
        return distance > 0 ? samples.reduce(0) { $0 + $1.liters } / distance * 100 : nil
    }
}
enum DataValidation {
    static func validate(_ db: Database) throws {
        func require(_ valid: Bool) throws { if !valid { throw CocoaError(.fileReadCorruptFile) } }
        try require(db.version == 1)
        let ids = Set(db.vehicles.map(\.id))
        try require(ids.count == db.vehicles.count)
        try require(Set(db.entries.map(\.id)).count == db.entries.count)
        try require(Set(db.reminders.map(\.id)).count == db.reminders.count)
        try require(Set(db.trips.map(\.id)).count == db.trips.count)
        try require(db.selectedID == nil || ids.contains(db.selectedID!))
        try require(db.language == nil || ["tr", "en"].contains(db.language!))
        if let filters = db.stationFilters {
            try require(StationFilters.radii.contains(filters.radiusKM) && StationFilters.brands.contains(filters.brand))
        }
        for (key, draft) in db.calculatorDrafts ?? [:] {
            try require(UUID(uuidString: key).map { ids.contains($0) } ?? false)
            try require([draft.distance, draft.consumption, draft.price, draft.fuel, draft.measuredLiters ?? "", draft.measuredDistance ?? ""].allSatisfy { $0.count <= 100 })
        }
        for (_, quote) in db.stationPrices ?? [:] {
            for value in [quote.petrol, quote.lpg].compactMap({ $0 }) { try require(value.isFinite && value > 0) }
            try require(quote.petrol != nil || quote.lpg != nil)
        }
        for v in db.vehicles { try require(!v.name.trimmingCharacters(in: .whitespaces).isEmpty && ["TRY", "EUR", "USD"].contains(v.currency)) }
        for e in db.entries {
            try require(ids.contains(e.vehicleID) && e.odometer.isFinite && e.odometer >= 0 && e.amount.isFinite && e.amount >= 0 && e.liters.isFinite && e.liters >= 0)
            try require(e.kind != "Yakıt" || e.liters > 0)
        }
        for r in db.reminders { try require(ids.contains(r.vehicleID) && !r.title.isEmpty && (r.date != nil || r.odometer != nil)); if let km = r.odometer { try require(km.isFinite && km >= 0) } }
        for t in db.trips {
            try require(ids.contains(t.vehicleID) && t.distance.isFinite && t.distance >= 0)
            for p in t.points { try require((-90...90).contains(p.latitude) && (-180...180).contains(p.longitude)) }
        }
    }
}
enum CSV {
    static let header = "id,vehicle_id,date,category,odometer_km,amount,liters,full_tank,missed_fill,station,note"
    static func escape(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
    static func export(_ entries: [Entry]) -> String {
        ([header] + entries.map { e in
            [e.id.uuidString, e.vehicleID.uuidString, ISO8601DateFormatter().string(from: e.date), e.kind, String(e.odometer), String(e.amount), String(e.liters), e.fullTank ? "1" : "0", e.missedFill ? "1" : "0", e.station, e.note].map(escape).joined(separator: ",")
        }).joined(separator: "\r\n")
    }
    static func rows(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []; var row: [String] = []; var field = ""; var quoted = false
        let chars = Array(text); var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if quoted && i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                else { quoted.toggle() }
            } else if c == "," && !quoted { row.append(field); field = "" }
            else if (c == "\n" || c == "\r\n" || c == "\r") && !quoted {
                row.append(field); if row != [""] { rows.append(row) }; row = []; field = ""
            } else { field.append(c) }
            i += 1
        }
        if quoted { throw CocoaError(.fileReadCorruptFile) }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
    static func parse(_ text: String, vehicleID: UUID) throws -> [Entry] {
        let rows = try rows(text)
        guard rows.first?.joined(separator: ",") == header else { throw CocoaError(.fileReadCorruptFile) }
        return try rows.dropFirst().map { r in
            guard r.count == 11, let id = UUID(uuidString: r[0]), let date = ISO8601DateFormatter().date(from: r[2]), let km = Double(r[4]), let amount = Double(r[5]), let liters = Double(r[6]), ["0", "1"].contains(r[7]), ["0", "1"].contains(r[8]) else { throw CocoaError(.fileReadCorruptFile) }
            return Entry(id: id, vehicleID: vehicleID, date: date, kind: r[3], odometer: km, amount: amount, liters: liters, fullTank: r[7] == "1", missedFill: r[8] == "1", station: r[9], note: r[10])
        }
    }
}


struct CalculatorDraft: Codable, Equatable {
    var distance = "100"
    var consumption = ""
    var price = ""
    var fuel = ""
    // Optional for compatibility with existing backups.
    var measuredLiters: String?
    var measuredDistance: String?
    var measuredConsumption: Double? {
        func parse(_ text: String?) -> Double? {
            guard let value = Double((text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")), value.isFinite, value > 0 else { return nil }
            return value
        }
        guard let liters = parse(measuredLiters), let distance = parse(measuredDistance) else { return nil }
        let result = liters / distance * 100
        return result.isFinite && result > 0 ? result : nil
    }
}
struct StationFilters: Codable, Equatable {
    var radiusKM = 10
    var brand = "Tümü"
    static let radii = [2, 5, 10, 25, 50]
    static let brands = ["Tümü", "Opet", "Shell", "Petrol Ofisi", "BP", "TotalEnergies", "TP", "Aytemiz", "Alpet"]
    func includes(name: String, distanceMeters: Double) -> Bool {
        distanceMeters.isFinite && distanceMeters >= 0 && distanceMeters <= Double(radiusKM) * 1000 && matches(name)
    }
    func matches(_ name: String) -> Bool {
        if brand == "Tümü" { return true }
        let normalized = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
        switch brand {
        case "Petrol Ofisi": return normalized.contains("petrol ofisi") || normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains("po")
        case "TotalEnergies": return normalized.contains("total")
        case "TP": return normalized.contains("turkiye petrolleri") || normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains("tp")
        case "BP": return normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains("bp")
        default: return normalized.contains(brand.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR")))
        }
    }
}
struct StationPriceNote: Codable, Equatable {
    var petrol: Double?
    var lpg: Double?
    var observedAt = Date()
}
struct ReportSnapshot {
    let entries: [Entry]
    let trips: [Trip]
    let samples: [Consumption]
    var totalCost: Double { entries.reduce(0) { $0 + $1.amount } }
    var fuelCost: Double { entries.filter { $0.kind == "Yakıt" }.reduce(0) { $0 + $1.amount } }
    var fuelLiters: Double { entries.filter { $0.kind == "Yakıt" }.reduce(0) { $0 + $1.liters } }
    var averageConsumption: Double? {
        let distance = samples.reduce(0) { $0 + $1.distance }
        return distance > 0 ? samples.reduce(0) { $0 + $1.liters } / distance * 100 : nil
    }
    var averagePrice: Double? { fuelLiters > 0 ? fuelCost / fuelLiters : nil }
    var loggedDistance: Double? {
        let kms = entries.map(\.odometer)
        guard let low = kms.min(), let high = kms.max(), high > low else { return nil }
        return high - low
    }
    var costPerKM: Double? { loggedDistance.map { totalCost / $0 } }
    var tripDistance: Double { trips.reduce(0) { $0 + $1.distance } }
    var tripSeconds: Double { trips.reduce(0) { $0 + max(0, ($1.end ?? $1.start).timeIntervalSince($1.start)) } }
    var averageSpeed: Double? { tripSeconds > 0 ? tripDistance / (tripSeconds / 3600) : nil }
    static func make(entries: [Entry], trips: [Trip], since: Date?, now: Date) -> ReportSnapshot {
        func included(_ date: Date) -> Bool { date <= now && (since == nil || date >= since!) }
        return ReportSnapshot(entries: entries.filter { included($0.date) }, trips: trips.filter { $0.end != nil && included($0.start) && $0.end! <= now }, samples: Metrics.consumption(entries.filter { $0.date <= now }).filter { included($0.date) })
    }
}

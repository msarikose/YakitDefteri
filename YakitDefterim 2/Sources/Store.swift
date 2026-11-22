import SwiftUI
import UserNotifications
import CoreLocation
import Combine
import UIKit

@MainActor final class Store: ObservableObject {
    static let shared = Store()
    @Published private(set) var db = Database()
    @Published var error: String?
    @Published var notificationsEnabled = false
    @Published private(set) var readOnly = true
    @Published private(set) var dataIssue: String?
    let file: URL
    private let disk: DatabaseDisk
    private var lifecycle = Set<AnyCancellable>()
    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("YakitDefterim", isDirectory: true)
        file = directory.appendingPathComponent("database.json")
        disk = DatabaseDisk(file: file)
        NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.retryLoad() }
            .store(in: &lifecycle)
        retryLoad()
    }
    func retryLoad() {
        guard readOnly else { return }
        do {
            let directory = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var excluded = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
            try excluded.setResourceValues(values)
            let loaded = try disk.load(allowMissing: UIApplication.shared.isProtectedDataAvailable)
            // Migrate protection metadata only after reading and validating the original.
            // No records are rewritten or replaced during recovery.
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
            }
            db = loaded
            dataIssue = nil
            readOnly = false
        } catch {
            // Permission errors (including locked-device starts) are not an empty database.
            readOnly = true
            dataIssue = "Verilere erişilemiyor. iPhone’un kilidini açıp yeniden dene. Mevcut kayıtlar korunuyor."
        }
    }
    var vehicle: Vehicle? { db.vehicles.first { $0.id == db.selectedID } ?? db.vehicles.first }
    var entries: [Entry] { db.entries.filter { $0.vehicleID == vehicle?.id }.sorted { $0.date > $1.date } }
    var reminders: [Reminder] { db.reminders.filter { $0.vehicleID == vehicle?.id && !$0.done } }
    var odometer: Double { entries.map(\.odometer).max() ?? 0 }
    @discardableResult func commit(_ edit: (inout Database) -> Void) -> Bool {
        guard !readOnly else { error = "Veri dosyası okunamadığı için değişiklik kaydedilemiyor."; return false }
        var next = db; edit(&next)
        do {
            try disk.save(next)
            let remindersChanged = db.reminders != next.reminders
            db = next
            if remindersChanged { Task { await scheduleReminders() } }
            return true
        } catch { self.error = "Kaydedilemedi: \(error.localizedDescription)"; return false }
    }
    func exportJSON() throws -> Data {
        guard !readOnly else { throw CocoaError(.fileReadNoPermission) }
        return try JSONEncoder().encode(db)
    }
    func importJSON(_ data: Data) throws {
        let next = try JSONDecoder().decode(Database.self, from: data)
        try DataValidation.validate(next)
        commit { $0 = next }
    }
    func requestNotifications() async {
        do { notificationsEnabled = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]); await scheduleReminders() }
        catch { self.error = error.localizedDescription }
    }
    func scheduleReminders() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        center.removeAllPendingNotificationRequests()
        let pending = db.reminders.filter { !$0.done }.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        for reminder in pending.prefix(60) {
            let content = UNMutableNotificationContent(); content.title = reminder.title
            content.body = db.vehicles.first { $0.id == reminder.vehicleID }?.name ?? localized("Araç bakımı"); content.sound = .default
            if let date = reminder.date, date > Date() {
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                do { try await center.add(UNNotificationRequest(identifier: reminder.id.uuidString, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))) }
                catch { self.error = "Hatırlatma planlanamadı: \(error.localizedDescription)" }
            }
        }
    }
}

@MainActor final class TripRecorder: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = TripRecorder()
    @Published var active: Trip?
    @Published var status = "Yolculuk başlatılmadı"
    private let manager = CLLocationManager()
    private var last: CLLocation?
    private var pendingVehicle: UUID?
    private var automaticTripID: UUID?
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBest; manager.distanceFilter = 10; manager.activityType = .automotiveNavigation; manager.pausesLocationUpdatesAutomatically = false }
    func start(vehicleID: UUID) {
        guard active == nil else { return }
        Store.shared.retryLoad()
        guard !Store.shared.readOnly else { status = "Veriler hazır değil. iPhone’un kilidini aç."; return }
        pendingVehicle = vehicleID
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: begin()
        default: status = "Konum izni kapalı. Ayarlar’dan izin verebilirsin."
        }
    }
    func startAutomatic() -> String {
        Store.shared.retryLoad()
        guard !Store.shared.readOnly else { return "Veriler hazır değil. iPhone’un kilidini aç." }
        guard Store.shared.db.autoRecordCarPlay == true else { return "Önce Diğer → CarPlay bölümünden otomatik kaydı aç." }
        guard active == nil else { return "Yolculuk kaydı zaten açık." }
        guard let vehicle = Store.shared.vehicle else { return "Önce iPhone uygulamasında araç ekle." }
        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else {
            status = "Önce iPhone’da elle yolculuk başlatarak konum izni ver."
            return status
        }
        start(vehicleID: vehicle.id)
        automaticTripID = active?.id
        return active == nil ? status : "Yolculuk kaydı başlatıldı."
    }
    func stopAutomatic() -> String {
        // A manual trip must never be stopped by an unrelated disconnect event.
        guard let id = automaticTripID, active?.id == id else { return "Otomatik başlayan etkin yolculuk yok." }
        stop()
        return status
    }
    private func begin() {
        guard active == nil, let id = pendingVehicle else { return }
        let trip = Trip(vehicleID: id)
        guard Store.shared.commit({ $0.trips.append(trip) }) else {
            status = "Kayıt yazılamadı. Yeniden kaydetmeyi dene."; pendingVehicle = nil; return
        }
        active = trip; last = nil
        manager.allowsBackgroundLocationUpdates = true; manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation(); status = "GPS bekleniyor"
    }
    func stop() {
        manager.stopUpdatingLocation()
        pendingVehicle = nil
        guard var trip = active else { return }; trip.end = Date()
        guard Store.shared.commit({ db in db.trips.removeAll { $0.id == trip.id }; db.trips.append(trip) }) else { status = "Kayıt yazılamadı. Yeniden kaydetmeyi dene."; return }
        active = nil; automaticTripID = nil; last = nil; pendingVehicle = nil; status = "Yolculuk kaydedildi"
    }
    private func persist() {
        guard let trip = active else { return }
        Store.shared.commit { db in db.trips.removeAll { $0.id == trip.id }; db.trips.append(trip) }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse { begin() }
        else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { status = "Konum izni verilmedi"; if active != nil { stop() } }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard active != nil else { return }
        for location in locations where location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 50 && abs(location.timestamp.timeIntervalSinceNow) < 30 {
            if let previous = last {
                let dt = location.timestamp.timeIntervalSince(previous.timestamp)
                guard dt > 0 else { continue }
                let distance = location.distance(from: previous)
                if dt > 120 { last = location; continue }
                guard distance / dt < 90 else { continue }
                active?.distance += distance / 1000
            }
            last = location
            active?.points.append(RoutePoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, date: location.timestamp))
        }
        status = "Yolculuk kaydediliyor"; persist()
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { status = "GPS: \(error.localizedDescription)" }
}

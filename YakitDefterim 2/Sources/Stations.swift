import SwiftUI
import MapKit
import CoreLocation

struct NearbyStation: Identifiable {
    let id = UUID()
    let item: MKMapItem
    let distance: CLLocationDistance
    var name: String { item.name ?? "Yakıt istasyonu" }
    var address: String { item.placemark.title ?? "Adres bilgisi yok" }

}

@MainActor final class StationSearch: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var stations: [NearbyStation] = []
    @Published var busy = false
    @Published var message = "Yakınındaki istasyonları bulmak için aramayı başlat."
    @Published var denied = false
    private let locationManager = CLLocationManager()
    private var search: MKLocalSearch?
    private var task: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var waitingForLocation = false
    private var generation = UUID()
    private var filters = StationFilters()
    private var origin: CLLocation?
    private(set) var hasSearched = false
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    func start(filters: StationFilters) {
        cancel()
        self.filters = filters
        hasSearched = true
        if let origin, abs(origin.timestamp.timeIntervalSinceNow) < 120 {
            busy = true; stations = []; denied = false
            performSearch(origin: origin)
            return
        }
        stations = []; busy = true; denied = false; waitingForLocation = true
        message = "Konumun alınıyor…"
        switch locationManager.authorizationStatus {
        case .notDetermined: locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: requestLocation()
        default: failPermission()
        }
    }
    private func requestLocation() {
        locationManager.requestLocation()
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            guard let self, self.waitingForLocation else { return }
            self.cancel(); self.message = "Konum alınamadı. Açık bir alanda tekrar dene."
        }
    }
    private func failPermission() {
        cancel(); denied = true
        message = "Konum izni kapalı. Ayarlar’dan izin vererek tekrar deneyebilirsin."
    }
    func cancel() {
        generation = UUID(); waitingForLocation = false; busy = false
        locationManager.stopUpdatingLocation(); search?.cancel(); search = nil
        task?.cancel(); task = nil; timeout?.cancel(); timeout = nil
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard waitingForLocation else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: requestLocation()
        case .denied, .restricted: failPermission()
        default: break
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard waitingForLocation else { return }
        guard let origin = locations.last(where: { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 3000 && abs($0.timestamp.timeIntervalSinceNow) < 60 }) else {
            cancel(); message = "Yeterince güncel konum bulunamadı. Tekrar dene."; return
        }
        self.origin = origin
        performSearch(origin: origin)
    }
    private func performSearch(origin: CLLocation) {
        waitingForLocation = false; timeout?.cancel()
        message = "Apple Haritalar’da istasyonlar aranıyor…"
        let token = generation
        task = Task { [weak self] in
            guard let self else { return }
            let filters = self.filters
            let radius = Double(filters.radiusKM) * 1000
            // Region-based text search avoids the POI request's small hard radius cap.
            // Results are still filtered to an exact circle below; MapKit may return an incomplete list.
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = filters.brand == "Tümü" ? "gas station" : filters.brand
            request.region = MKCoordinateRegion(center: origin.coordinate, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
            request.resultTypes = .pointOfInterest
            if filters.brand == "Tümü" {
                request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.gasStation])
            }
            let search = MKLocalSearch(request: request)
            self.search = search
            do {
                let response = try await search.start()
                guard !Task.isCancelled, self.generation == token else { return }
                self.stations = response.mapItems.compactMap { item in
                    guard let location = item.placemark.location else { return nil }
                    let distance = origin.distance(from: location)
                    guard filters.includes(name: item.name ?? "", distanceMeters: distance) else { return nil }
                    return NearbyStation(item: item, distance: distance)
                }.sorted { $0.distance < $1.distance }
                self.message = self.stations.isEmpty ? "Seçilen filtrelerde istasyon bulunamadı." : ""
            } catch {
                guard !Task.isCancelled, self.generation == token else { return }
                self.message = "İstasyonlar alınamadı. İnternet bağlantını kontrol edip tekrar dene."
            }
            guard self.generation == token else { return }
            self.busy = false; self.search = nil
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard waitingForLocation else { return }
        cancel(); message = "Konum alınamadı. Konum servislerini kontrol edip tekrar dene."
    }
}

struct NearbyStationsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: Store
    @StateObject private var search = StationSearch()
    @LocalState private var chosen: NearbyStation?
    @LocalState private var directionsError = false
    private var filters: StationFilters { store.db.stationFilters ?? StationFilters() }
    private func setFilters(_ edit: (inout StationFilters) -> Void) {
        var next = filters; edit(&next)
        if store.commit({ $0.stationFilters = next }) {
            if search.hasSearched { search.start(filters: next) }
            else { search.message = "Yakınındaki istasyonları bulmak için aramayı başlat." }
        }
    }
    var onSelect: ((String) -> Void)? = nil
    var body: some View {
        NavigationStack {
            List {
                Section("Arama tercihleri") {
                    Picker("Mesafe", selection: Binding(get: { filters.radiusKM }, set: { value in setFilters { $0.radiusKM = value } })) {
                        ForEach(StationFilters.radii, id: \.self) { Text("\($0) km").tag($0) }
                    }
                    Picker("Marka", selection: Binding(get: { filters.brand }, set: { value in setFilters { $0.brand = value } })) {
                        ForEach(StationFilters.brands, id: \.self) { Text(LocalizedStringKey($0)).tag($0) }
                    }
                    Button { search.start(filters: filters) } label: {
                        Label(LocalizedStringKey(search.busy ? "Aranıyor…" : "Yakınımdaki istasyonları bul"), systemImage: "location.magnifyingglass")
                    }.disabled(search.busy)
                    if search.busy { ProgressView() }
                    if !search.message.isEmpty { Text(LocalizedStringKey(search.message)).font(.footnote).foregroundStyle(.secondary) }
                    Text("Konum çevren Apple Haritalar’a gönderilir. Mesafeler kuş uçuşudur.").font(.caption2).foregroundStyle(.secondary)
                    if search.denied {
                        Button("Konum ayarlarını aç") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                }
                ForEach(search.stations) { station in
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(station.name).font(.headline)
                            Text(station.address).font(.caption).foregroundStyle(.secondary)
                            Label(station.distance < 1000 ? "\(Int(station.distance)) m" : "\(number(station.distance/1000)) km", systemImage: "location")
                                .font(.subheadline).foregroundStyle(.teal)
                        }
                        if let url = officialPriceURL(station.name) {
                            Link("Fiyat listesi", destination: url).font(.subheadline)
                        }
                        Button(LocalizedStringKey(onSelect == nil ? "Yakıt kaydı ekle" : "Seç"), systemImage: "plus.circle") {
                            if let onSelect { onSelect(station.name); dismiss() } else { chosen = station }
                        }.disabled(onSelect == nil && store.vehicle == nil)
                        Button("Yol tarifi", systemImage: "arrow.triangle.turn.up.right.diamond") {
                            directionsError = !station.item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                        }
                    }
                }
                if onSelect == nil && store.vehicle == nil {
                    Text("Yakıt kaydı eklemek için önce Diğer → Araçlar bölümünden araç ekle.").font(.footnote)
                }
            }
            .navigationTitle("Yakındaki istasyonlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
            .sheet(item: $chosen) { station in EntryForm(initialStation: station.name) }
            .alert("Apple Haritalar açılamadı", isPresented: $directionsError) { Button("Tamam", role: .cancel) {} }
            .onDisappear { search.cancel() }
        }
    }
}


private func officialPriceURL(_ name: String) -> URL? {
    if name.localizedCaseInsensitiveContains("opet") { return URL(string: "https://www.opet.com.tr/akaryakit-fiyatlari") }
    if name.localizedCaseInsensitiveContains("petrol ofisi") { return URL(string: "https://www.petrolofisi.com.tr/akaryakit-fiyatlari") }
    return nil
}

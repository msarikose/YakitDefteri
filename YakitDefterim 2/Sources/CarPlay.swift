import CarPlay
import Combine
import MapKit

@MainActor final class CarPlayDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var controller: CPInterfaceController?
    private var subscriptions = Set<AnyCancellable>()
    private var template: CPGridTemplate?
    private var gridSignature = ""
    private var pendingAutomaticStart = false
    private weak var scene: CPTemplateApplicationScene?
    private var detail: CPListTemplate?
    private var information: CPInformationTemplate?
    private var detailKind: String?
    private let stationSearch = StationSearch()
    private var searchedFilters: StationFilters?
    private var filterPicker: String?
    private var deferredSearch: Task<Void, Never>?
    private var lastStationSearch: Date?

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        controller = interfaceController
        self.scene = scene
        let list = CPGridTemplate(title: localized("Yakıt Defterim"), gridButtons: [])
        template = list
        interfaceController.setRootTemplate(list, animated: false, completion: nil)
        pendingAutomaticStart = true
        Store.shared.retryLoad()
        tryAutomaticStart()
        refresh()
        Store.shared.$readOnly.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.tryAutomaticStart()
            self?.refresh()
        }.store(in: &subscriptions)
        // Location persistence can publish every few seconds; CarPlay summaries update at most every 10s.
        Publishers.Merge3(Store.shared.$db.map { _ in () }, TripRecorder.shared.$active.map { _ in () }, TripRecorder.shared.$status.map { _ in () })
            .throttle(for: .seconds(10), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        stationSearch.$busy.receive(on: RunLoop.main).sink { [weak self] _ in
            guard self?.detailKind == "Yakın istasyonlar" else { return }
            self?.refreshDetail()
        }.store(in: &subscriptions)
    }
    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        pendingAutomaticStart = false
        deferredSearch?.cancel(); deferredSearch = nil; filterPicker = nil
        stationSearch.cancel()
        subscriptions.removeAll(); controller = nil; template = nil
        self.scene = nil; gridSignature = ""; detail = nil; information = nil; detailKind = nil; lastStationSearch = nil
    }
    private func tryAutomaticStart() {
        guard pendingAutomaticStart, !Store.shared.readOnly else { return }
        pendingAutomaticStart = false
        _ = TripRecorder.shared.startAutomatic()
    }
    private func refresh() {
        let store = Store.shared
        if detailKind == "Yakın istasyonlar", !store.readOnly {
            if searchedFilters != (store.db.stationFilters ?? StationFilters()) { searchStations() }
            refreshDetail()
        } else { refreshDetail() }
        guard let template else { return }
        guard !store.readOnly else {
            gridSignature = ""
            template.updateTitle(localized("Veriler hazır değil"))
            template.updateGridButtons([gridButton("Yeniden dene", symbol: "lock.open.fill", color: .systemTeal) { [weak self] in
                store.retryLoad(); self?.tryAutomaticStart(); self?.refresh()
            }])
            return
        }
        guard let vehicle = store.vehicle else {
            gridSignature = ""
            template.updateTitle(localized("Önce iPhone’da araç ekle"))
            let help = gridButton("Kurulumu park halindeyken tamamla", symbol: "iphone", color: .systemTeal) {}
            help.isEnabled = false
            template.updateGridButtons([help])
            return
        }
        let recorder = TripRecorder.shared
        let active = recorder.active != nil
        let tripTitle = localized(active ? "Yolculuğu bitir" : "Yolculuğu başlat")
        let distance = recorder.active.map { number($0.distance, digits: 1) + " km" }
        let signature = [vehicle.id.uuidString, vehicle.name, store.db.language ?? "tr", tripTitle, distance ?? ""].joined(separator: "|")
        // Preserve focus and avoid rebuilding a stationary menu on every database publication.
        guard gridSignature != signature else { return }
        gridSignature = signature
        template.updateTitle(vehicle.name)
        let trip = CPGridButton(titleVariants: [distance.map { tripTitle + " • " + $0 } ?? tripTitle, tripTitle],
                                image: gridIcon(active ? "stop.fill" : "location.fill", color: active ? .systemOrange : .systemTeal)) { [weak self] _ in
            guard !store.readOnly else { self?.refresh(); return }
            if recorder.active == nil {
                if let selected = store.vehicle { recorder.start(vehicleID: selected.id) }
            } else { recorder.stop() }
            self?.refresh()
        }
        let menus: [(String, String, UIColor)] = [
            ("Yakın istasyonlar", "fuelpump.fill", .systemCyan),
            ("Tüketim özeti", "gauge.with.dots.needle.50percent", .systemGreen),
            ("Hesaplayıcı", "function", .systemIndigo),
            ("Bakım planı", "wrench.and.screwdriver.fill", .systemOrange),
            ("Araç seç", "car.fill", .systemBlue)
        ]
        template.updateGridButtons([trip] + menus.map { title, symbol, color in
            gridButton(title, symbol: symbol, color: color) { [weak self] in self?.show(title) }
        })
    }

    private func gridButton(_ title: String, symbol: String, color: UIColor, action: @escaping () -> Void) -> CPGridButton {
        CPGridButton(titleVariants: [localized(title)], image: gridIcon(symbol, color: color)) { _ in action() }
    }

    // Only the icon is custom drawn; CarPlay owns the layout, focus, labels and background.
    private func gridIcon(_ symbol: String, color: UIColor) -> UIImage {
        let size: CGSize
        if #available(iOS 26.0, *) { size = CPGridTemplate.maximumGridButtonImageSize }
        else { size = CGSize(width: 40, height: 40) }
        let side = min(size.width, size.height, 64)
        let format = UIGraphicsImageRendererFormat()
        format.scale = controller?.carTraitCollection.displayScale ?? 2
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let rect = CGRect(x: 1, y: 1, width: side - 2, height: side - 2)
            color.withAlphaComponent(0.20).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: side * 0.28).fill()
            color.withAlphaComponent(0.65).setStroke()
            let border = UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: side * 0.28)
            border.lineWidth = 1; border.stroke()
            let configuration = UIImage.SymbolConfiguration(pointSize: side * 0.48, weight: .semibold)
            if let image = UIImage(systemName: symbol, withConfiguration: configuration)?.withTintColor(color, renderingMode: .alwaysOriginal) {
                let scale = min(side * 0.56 / image.size.width, side * 0.56 / image.size.height)
                let width = image.size.width * scale, height = image.size.height * scale
                image.draw(in: CGRect(x: (side - width) / 2, y: (side - height) / 2, width: width, height: height))
            }
        }.withRenderingMode(.alwaysOriginal)
    }

    private func row(_ title: String, _ value: String? = nil) -> CPListItem {
        let item = CPListItem(text: localized(title), detailText: value)
        item.isEnabled = false
        return item
    }
    private func show(_ kind: String) {
        guard !Store.shared.readOnly else { refresh(); return }
        detailKind = kind
        filterPicker = nil
        let screen: CPTemplate
        if kind == "Tüketim özeti" || kind == "Hesaplayıcı" {
            let panel = CPInformationTemplate(title: localized(kind), layout: .twoColumn, items: [], actions: [])
            information = panel; detail = nil; screen = panel
        } else {
            let list = CPListTemplate(title: localized(kind), sections: [])
            detail = list; information = nil; screen = list
        }
        refreshDetail()
        controller?.pushTemplate(screen, animated: true, completion: nil)
        if kind == "Yakın istasyonlar" { searchStations() }
    }
    private func searchStations() {
        guard !Store.shared.readOnly else { return }
        let filters = Store.shared.db.stationFilters ?? StationFilters()
        if searchedFilters != filters {
            stationSearch.cancel()
            stationSearch.stations = []
            searchedFilters = filters
        }
        guard !stationSearch.busy else { return }
        // Keep POI refreshes at least 60 seconds apart, including filter changes.
        if let lastStationSearch {
            let remaining = 60 - Date().timeIntervalSince(lastStationSearch)
            if remaining > 0 {
                if deferredSearch == nil {
                    stationSearch.message = "Yeni arama kısa süre içinde başlayacak"
                    deferredSearch = Task { [weak self] in
                        do { try await Task.sleep(for: .seconds(remaining + 0.1)) } catch { return }
                        guard let self else { return }
                        self.deferredSearch = nil
                        self.searchStations()
                    }
                }
                refreshDetail()
                return
            }
        }
        // Permission setup belongs on the phone, not in a driving interaction.
        let authorization = CLLocationManager().authorizationStatus
        guard authorization == .authorizedAlways || authorization == .authorizedWhenInUse else {
            stationSearch.message = "Konum iznini iPhone’da aç"; refreshDetail(); return
        }
        lastStationSearch = Date()
        searchedFilters = filters
        stationSearch.start(filters: filters)
        refreshDetail()
    }
    private func refreshDetail() {
        guard let kind = detailKind, detail != nil || information != nil else { return }
        let store = Store.shared
        guard !store.readOnly else {
            renderDetail([row("Veriler hazır değil", localized("iPhone’un kilidini açıp yeniden dene"))]); return
        }
        guard let vehicle = store.vehicle else {
            renderDetail([row("Önce iPhone’da araç ekle")]); return
        }
        var items: [CPListItem] = []
        switch kind {
        case "Araç seç":
            items = store.db.vehicles.prefix(CPListTemplate.maximumItemCount).map { vehicle in
                let item = CPListItem(text: vehicle.name, detailText: vehicle.id == store.vehicle?.id ? localized("Seçili araç") : vehicle.plate)
                item.setImage(gridIcon(vehicle.id == store.vehicle?.id ? "checkmark.circle.fill" : "car.fill", color: .systemBlue))
                item.isEnabled = TripRecorder.shared.active == nil
                item.handler = { [weak self] _, done in
                    guard TripRecorder.shared.active == nil else { done(); return }
                    if store.commit({ $0.selectedID = vehicle.id }) { self?.refresh() }
                    else { item.setDetailText(localized("Kaydedilemedi")) }
                    done()
                }
                return item
            }
            if TripRecorder.shared.active != nil { items.insert(row("Araç değiştirmek için yolculuğu bitir"), at: 0) }
        case "Bakım planı":
            items = store.reminders.prefix(10).map { reminder in
                let item = row(reminder.title, [reminder.odometer.map { number($0, digits: 0) + " km" }, reminder.date?.formatted(date: .abbreviated, time: .omitted)].compactMap { $0 }.joined(separator: " • "))
                item.setImage(gridIcon("wrench.and.screwdriver.fill", color: .systemOrange))
                return item
            }
            if items.isEmpty { items = [row("Bekleyen bakım yok")]
                items[0].setImage(gridIcon("checkmark.circle.fill", color: .systemGreen)) }
        case "Tüketim özeti":
            items = [row("Seçili araç", vehicle.name), row("Ortalama tüketim", Metrics.average(store.entries).map { number($0) + " L/100 km" } ?? localized("İki tam depo kaydı gerekiyor"))]
            if let last = store.entries.first(where: { $0.kind == "Yakıt" }) {
                items.append(row("Son yakıt kaydı", number(last.liters) + " L • " + last.date.formatted(date: .abbreviated, time: .omitted)))
            }

        case "Hesaplayıcı":
            if let draft = store.db.calculatorDrafts?[vehicle.id.uuidString] {
                func value(_ text: String) -> Double? {
                    guard let n = Double(text.replacingOccurrences(of: ",", with: ".")), n.isFinite, n >= 0 else { return nil }; return n
                }
                if let consumption = value(draft.consumption), consumption > 0 {
                    if let fuel = value(draft.fuel), (fuel / consumption * 100).isFinite { items.append(row("Tahmini menzil", number(fuel / consumption * 100, digits: 0) + " km")) }
                    if let distance = value(draft.distance) {
                        let liters = distance * consumption / 100
                        if liters.isFinite {
                            items.append(row("Tahmini yakıt", number(liters) + " L • " + number(distance, digits: 0) + " km"))
                            if let price = value(draft.price), (liters * price).isFinite { items.append(row("Tahmini maliyet", number(liters * price) + " " + vehicle.currency)) }
                        }
                    }
                }
            }
            if items.isEmpty { items.append(row("Hesaplayıcı", localized("iPhone’da kaydettiğin değerlerle hesaplanır"))) }
        case "Yakın istasyonlar":
            let filters = store.db.stationFilters ?? StationFilters()
            if let picker = filterPicker {
                let back = CPListItem(text: localized("Sonuçlara dön"), detailText: nil)
                back.setImage(gridIcon("arrow.left", color: .systemCyan))
                back.handler = { [weak self] _, done in self?.filterPicker = nil; self?.refreshDetail(); done() }
                let options = picker == "Marka" ? StationFilters.brands : StationFilters.radii.map { String($0) }
                items = [back] + options.map { option in
                    let selected = picker == "Marka" ? filters.brand == option : String(filters.radiusKM) == option
                    let item = CPListItem(text: picker == "Marka" ? localized(option) : option + " km", detailText: nil)
                    item.setImage(gridIcon(selected ? "checkmark.circle.fill" : "circle", color: .systemCyan))
                    item.handler = { [weak self] _, done in
                        let saved = store.commit { db in
                            var next = db.stationFilters ?? StationFilters()
                            if picker == "Marka" { next.brand = option }
                            else if let radius = Int(option) { next.radiusKM = radius }
                            db.stationFilters = next
                        }
                        if saved { self?.filterPicker = nil; self?.searchStations(); self?.refreshDetail() }
                        else { item.setDetailText(localized("Kaydedilemedi")) }
                        done()
                    }
                    return item
                }
                break
            }
            let brand = CPListItem(text: localized("Marka"), detailText: localized(filters.brand))
            let radius = CPListItem(text: localized("Arama mesafesi"), detailText: "\(filters.radiusKM) km")
            for (item, picker) in [(brand, "Marka"), (radius, "Arama mesafesi")] {
                item.setImage(gridIcon("line.3.horizontal.decrease.circle", color: .systemCyan))
                item.accessoryType = .disclosureIndicator
                item.handler = { [weak self] _, done in self?.filterPicker = picker; self?.refreshDetail(); done() }
            }
            let search = CPListItem(text: localized("Yeniden ara"), detailText: localized(filters.brand) + " • \(filters.radiusKM) km")
            search.setImage(gridIcon("arrow.clockwise", color: .systemCyan))
            search.handler = { [weak self] _, done in self?.searchStations(); done() }
            items = [brand, radius, search]
            if deferredSearch != nil { items.append(row("Yeni arama kısa süre içinde başlayacak")) }
            if stationSearch.busy { items.append(row("İstasyonlar aranıyor…")) }
            else if stationSearch.stations.isEmpty {
                if deferredSearch == nil { items.append(row(stationSearch.message)) }
            }
            else {
                items += stationSearch.stations.prefix(8).map { station in
                    let item = CPListItem(text: station.name, detailText: number(station.distance / 1000, digits: 1) + " km • " + localized("Yol tarifi"))
                    item.setImage(gridIcon("fuelpump.fill", color: .systemCyan))
                    item.setAccessoryImage(UIImage(systemName: "arrow.up.right"))
                    item.handler = { [weak self] _, done in
                        let coordinate = station.item.placemark.coordinate
                        var components = URLComponents(string: "https://maps.apple.com/")!
                        components.queryItems = [URLQueryItem(name: "daddr", value: "\(coordinate.latitude),\(coordinate.longitude)"), URLQueryItem(name: "dirflg", value: "d")]
                        guard let url = components.url, let scene = self?.scene else { done(); return }
                        scene.open(url, options: nil) { success in
                            if !success { item.setDetailText(localized("Haritalar açılamadı")) }
                            done()
                        }
                    }
                    return item
                }
            }
        default: break
        }
        renderDetail(items)
    }

    private func renderDetail(_ items: [CPListItem]) {
        if let information {
            information.items = items.prefix(4).map {
                CPInformationItem(title: $0.text, detail: $0.detailText)
            }
        } else {
            let header = Store.shared.readOnly ? nil : Store.shared.vehicle?.name
            detail?.updateSections([CPListSection(items: Array(items.prefix(CPListTemplate.maximumItemCount)), header: header, sectionIndexTitle: nil)])
        }
    }
}

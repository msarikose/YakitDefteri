import SwiftUI
import UniformTypeIdentifiers

struct ReminderRow: View {
    @EnvironmentObject var store: Store
    let reminder: Reminder
    var due: Bool { (reminder.date.map { $0 <= Date() } ?? false) || (reminder.odometer.map { $0 <= store.odometer } ?? false) }
    var body: some View {
        HStack { Image(systemName: due ? "exclamationmark.circle.fill" : "wrench").foregroundStyle(due ? .orange : .teal)
            VStack(alignment: .leading) {
                Text(reminder.title)
                if let date = reminder.date { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                if let km = reminder.odometer { Text(number(km, digits: 0) + " km").font(.caption).foregroundStyle(.secondary) }
            }; Spacer(); if due { Text("Zamanı geldi").font(.caption).foregroundStyle(.orange) }
        }
    }
}
struct RemindersView: View {
    @EnvironmentObject var store: Store
    @LocalState var adding = false
    var body: some View {
        NavigationStack { List {
            Section { ForEach(store.reminders) { r in ReminderRow(reminder: r).swipeActions { Button("Tamamlandı") { store.commit { db in if let i = db.reminders.firstIndex(where: { $0.id == r.id }) { db.reminders[i].done = true } } }.tint(.teal) } } }
            Section { Text("Tarih bildirimleri izin verdiğinde çalışır. Kilometre uyarıları, girdiğin son kilometreye göre uygulamada görünür; araçtan kilometre okunmaz.").font(.caption).foregroundStyle(.secondary)
                Button("Bildirimlere izin ver") { Task { await store.requestNotifications() } }
            }
            Section("Tamamlananlar") { ForEach(store.db.reminders.filter { $0.vehicleID == store.vehicle?.id && $0.done }) { r in Label(r.title, systemImage: "checkmark.circle").foregroundStyle(.secondary) } }
        }.navigationTitle("Bakım planı").toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Bakım hatırlatması ekle").disabled(store.vehicle == nil) } } }.sheet(isPresented: $adding) { ReminderForm() }
    }
}
struct ReminderForm: View {
    @EnvironmentObject var store: Store; @Environment(\.dismiss) var dismiss
    @LocalState var title = ""; @LocalState var date = Date().addingTimeInterval(86400); @LocalState var withDate = true; @LocalState var withKm = false; @LocalState var km = ""
    var valid: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty && (withDate || withKm) && (!withKm || (decimal(km).map { $0.isFinite && $0 >= 0 } ?? false)) }
    var body: some View {
        NavigationStack { Form {
            TextField("Bakım / hatırlatma adı", text: $title)
            Toggle("Tarihe göre", isOn: $withDate)
            if withDate { DatePicker("Hatırlatma zamanı", selection: $date, in: Date()...) }
            Toggle("Kilometreye göre", isOn: $withKm)
            if withKm { TextField("Hedef kilometre", text: $km).keyboardType(.decimalPad) }
        }.navigationTitle("Hatırlatma ekle").toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("İptal") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Kaydet") { guard let id = store.vehicle?.id else { return }; let r = Reminder(vehicleID: id, title: title, date: withDate ? date : nil, odometer: withKm ? decimal(km) : nil); store.commit { $0.reminders.append(r) }; if store.error == nil { dismiss() } }.disabled(!valid) }
        } }
    }
}
struct TripsView: View {
    @EnvironmentObject var store: Store
    @ObservedObject var recorder = TripRecorder.shared
    @LocalState var manual = false; @LocalState var deleting: Trip?
    var body: some View {
        NavigationStack { List {
            Section("Canlı kayıt") {
                Text(LocalizedStringKey(recorder.status)).foregroundStyle(.secondary)
                if let active = recorder.active {
                    Text(number(active.distance, digits: 2) + " km").font(.largeTitle.bold())
                    Button("Yolculuğu bitir ve kaydet", role: .destructive) { recorder.stop() }
                } else {
                    Button("GPS yolculuğu başlat", systemImage: "location.fill") { if let id = store.vehicle?.id { recorder.start(vehicleID: id) } }.disabled(store.vehicle == nil)
                }
                Text("Başlattığın yolculuk sırasında GPS kullanılır. Rota noktaları yalnızca bu cihazda tutulur. Uygulama zorla kapatılırsa kayıt durur; kaydedilmiş bölüm korunur.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Yolculuklar") {
                ForEach(store.db.trips.filter { $0.vehicleID == store.vehicle?.id }.sorted { $0.start > $1.start }) { trip in
                    NavigationLink { TripDetail(trip: trip) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text(LocalizedStringKey(trip.purpose)); Spacer(); Text(number(trip.distance, digits: 2) + " km").bold() }
                            Text(trip.start.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            if trip.end == nil { Text(LocalizedStringKey(recorder.active?.id == trip.id ? "Kayıt sürüyor" : "Tamamlanmamış kayıt — saklanan bölüm")).font(.caption).foregroundStyle(.orange) }
                        }
                    }.swipeActions { if recorder.active?.id != trip.id { Button("Sil", role: .destructive) { deleting = trip } } }
                }
            }
        }.navigationTitle("Yolculuklar").toolbar { ToolbarItem(placement: .topBarTrailing) { Button { manual = true } label: { Image(systemName: "plus").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Yolculuk ekle").disabled(store.vehicle == nil) } } }
        .sheet(isPresented: $manual) { ManualTripForm() }
        .confirmationDialog("Yolculuk silinsin mi?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) { Button("Sil", role: .destructive) { if let t = deleting { store.commit { $0.trips.removeAll { $0.id == t.id } } }; deleting = nil } }
    }
}
struct TripDetail: View {
    let trip: Trip
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 20) {
            Text(number(trip.distance, digits: 2) + " km").font(.largeTitle.bold())
            Text(trip.start.formatted(date: .long, time: .shortened))
            if let end = trip.end { Text("Süre: \(number(max(0, end.timeIntervalSince(trip.start))/60, digits: 0)) dk") }
            if trip.points.count > 1 {
                Text("Rotan").font(.headline)
                Canvas { context, size in
                    let points = trip.points
                    let minLon = points.map(\.longitude).min()!; let maxLon = points.map(\.longitude).max()!
                    let minLat = points.map(\.latitude).min()!; let maxLat = points.map(\.latitude).max()!
                    let cosLat = cos((minLat + maxLat) / 2 * .pi / 180)
                    let width = max(0.00001, (maxLon-minLon)*cosLat); let height = max(0.00001, maxLat-minLat)
                    let scale = min((size.width-24)/width, (size.height-24)/height)
                    var path = Path()
                    for (i, p) in points.enumerated() {
                        let point = CGPoint(x: (p.longitude-minLon)*cosLat*scale + (size.width-width*scale)/2, y: size.height-((p.latitude-minLat)*scale + (size.height-height*scale)/2))
                        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    context.stroke(path, with: .color(.teal), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }.frame(height: 260).background(.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
                Text("Çevrimdışı rota çizimi. Harita servisine konum gönderilmez.").font(.caption).foregroundStyle(.secondary)
            } else { Text("Bu yolculuk için çizilebilecek rota yok.").foregroundStyle(.secondary) }
        }.padding() }.navigationTitle(LocalizedStringKey(trip.purpose))
    }
}
struct ManualTripForm: View {
    @EnvironmentObject var store: Store; @Environment(\.dismiss) var dismiss
    @LocalState var distance = ""; @LocalState var purpose = "Kişisel"; @LocalState var start = Date(); @LocalState var end = Date()
    var body: some View {
        NavigationStack { Form {
            Picker("Tür", selection: $purpose) { Text("Kişisel").tag("Kişisel"); Text("İş").tag("İş") }
            TextField("Mesafe (km)", text: $distance).keyboardType(.decimalPad)
            DatePicker("Başlangıç", selection: $start, in: ...Date()); DatePicker("Bitiş", selection: $end, in: start...max(start, Date()))
        }.navigationTitle("Yolculuk ekle").toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("İptal") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Kaydet") { guard let id = store.vehicle?.id, let d = decimal(distance) else { return }; store.commit { $0.trips.append(Trip(vehicleID: id, start: start, end: end, distance: d, purpose: purpose)) }; if store.error == nil { dismiss() } }.disabled(!(decimal(distance).map { $0.isFinite && $0 > 0 } ?? false) || end < start) }
        } }
    }
}
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct SettingsView: View {
    @EnvironmentObject var store: Store
    @LocalState private var addVehicle = false
    @LocalState var exporting = false; @LocalState var importing = false; @LocalState var document = BackupDocument(); @LocalState var type: UTType = .json
    @LocalState var pending: Data?; @LocalState var restore = false; @LocalState var importCSV = false
    var body: some View {
        NavigationStack { List {
            Section("Dil / Language") {
                Picker("Dil / Language", selection: Binding(
                    get: { store.db.language ?? "tr" },
                    set: { value in store.commit { $0.language = value } }
                )) {
                    Text("Türkçe").tag("tr")
                    Text("English").tag("en")
                }
            }
            Section("Araçlar") {
                ForEach(store.db.vehicles) { vehicle in
                    Button {
                        store.commit { $0.selectedID = vehicle.id }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(vehicle.name).foregroundStyle(.primary)
                                Text(vehicle.plate + " · " + localized(vehicle.fuel) + " · " + vehicle.currency)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if vehicle.id == store.vehicle?.id {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.teal)
                            }
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .accessibilityValue(vehicle.id == store.vehicle?.id ? "Seçili araç" : "")
                }
                Button("Araç ekle", systemImage: "plus.circle") { addVehicle = true }
            }
            Section("Hesaplama ve rapor") {
                NavigationLink("Yakıt ve yolculuk hesaplayıcı") { CalculatorView() }
                NavigationLink("Yol bilgisayarı ve raporlar") { ReportsView() }
            }
            Section("Yedekleme") {
                Button("Tüm verileri JSON olarak dışa aktar") { do { document = BackupDocument(data: try store.exportJSON()); type = .json; exporting = true } catch { store.error = error.localizedDescription } }
                Button("Seçili aracın kayıtlarını CSV olarak dışa aktar") { document = BackupDocument(data: Data(CSV.export(store.entries).utf8)); type = .commaSeparatedText; exporting = true }.disabled(store.vehicle == nil)
                Button("JSON yedeğini geri yükle") { importCSV = false; importing = true }.disabled(TripRecorder.shared.active != nil)
                Button("CSV kayıtlarını seçili araca ekle") { importCSV = true; importing = true }.disabled(store.vehicle == nil)
                Text("JSON tüm verileri ve rotaları içerir. CSV bu uygulamanın kayıt şemasını kullanır; Fuelio dosyaları doğrudan desteklenmez. Dosyalar şifrelenmez. Yalnızca cihazda tutmak için Dosyalar’da ‘iPhone’umda’ konumunu seç.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Gizlilik") {
                Label("Hesap, reklam veya analiz SDK’sı yok", systemImage: "lock.shield")
                Text("Kayıtlar uygulamanın korumalı alanında saklanır. Otomatik bulut eşitleme ve uygulama veri klasörünün sistem yedeğine dahil edilmesi kapalıdır. Dışa aktardığın dosyanın konumunu sen seçersin.").font(.caption)
                Text("Konum, elle veya otomatik başlattığın yolculuklarda ve yakındaki istasyonları aradığında kullanılır. İstasyon araması konum çevreni Apple Haritalar’a gönderir; yakıt ve gider kayıtlarını göndermez. Seçtiğin fiş fotoğrafındaki metin Apple Vision ile cihazda okunur; iCloud’daki bir fotoğrafın indirilmesi Apple’ın fotoğraf hizmetini kullanabilir.").font(.caption)
            }
            Section("CarPlay") {
                Toggle("Otomatik yolculuk kaydı", isOn: Binding(
                    get: { store.db.autoRecordCarPlay ?? false },
                    set: { enabled in
                        if store.commit({ $0.autoRecordCarPlay = enabled }), !enabled {
                            _ = TripRecorder.shared.stopAutomatic()
                        }
                    }
                ))
                Text("Açıksa uygulamanın CarPlay ekranı açıldığında seçili araç için kayıt başlar. Her araç bağlantısında başlatmak için aşağıdaki Kestirmeler otomasyonlarını kur. Önce telefonda bir kez elle yolculuk başlatıp konum izni ver.").font(.caption)
                NavigationLink("Otomatik kayıt kurulumu") { AutoRecordingHelp() }

                Text("Araç özeti ve yolculuk başlat / bitir ekranı kaynak kodda mevcut. Araç ekranında kullanılabilmesi Apple’ın CarPlay Driving Task yetkisini onaylamasına ve uygun imzalamaya bağlıdır.").font(.caption)
            }
        }.navigationTitle("Araç kutusu") }
        .sheet(isPresented: $addVehicle) { VehicleForm() }
        .fileExporter(isPresented: $exporting, document: document, contentType: type, defaultFilename: "YakitDefterim-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { if case .failure(let error) = $0 { store.error = error.localizedDescription } }
        .fileImporter(isPresented: $importing, allowedContentTypes: importCSV ? [.commaSeparatedText, .plainText] : [.json]) { result in
            do {
                let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let values = try url.resourceValues(forKeys: [.fileSizeKey]); guard (values.fileSize ?? 0) <= 50_000_000 else { throw CocoaError(.fileReadTooLarge) }
                let data = try Data(contentsOf: url)
                if importCSV {
                    guard let id = store.vehicle?.id, let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
                    let entries = try CSV.parse(text, vehicleID: id)
                    var candidate = store.db; let ids = Set(candidate.entries.map(\.id)); candidate.entries += entries.filter { !ids.contains($0.id) }; try DataValidation.validate(candidate)
                    store.commit { $0 = candidate }
                } else { let db = try JSONDecoder().decode(Database.self, from: data); try DataValidation.validate(db); pending = data; restore = true }
            } catch { store.error = "Dosya içe aktarılamadı. Mevcut kayıtlar korunuyor. \(error.localizedDescription)" }
        }
        .confirmationDialog("Mevcut tüm veriler bu yedekle değiştirilecek. Önce dışa aktararak yedek aldığından emin ol.", isPresented: $restore, titleVisibility: .visible) {
            Button("Yedekle değiştir", role: .destructive) { if let pending { do { try store.importJSON(pending) } catch { store.error = error.localizedDescription } }; pending = nil }
            Button("İptal", role: .cancel) { pending = nil }
        }
    }
}
struct CalculatorView: View {
    @EnvironmentObject var store: Store
    @LocalState private var draft = CalculatorDraft()
    @LocalState private var loadedID: UUID?
    @LocalState private var saveStatus = ""
    private func positive(_ text: String, allowZero: Bool = false) -> Double? {
        guard let value = decimal(text), value.isFinite, allowZero ? value >= 0 : value > 0 else { return nil }
        return value
    }
    var body: some View {
        Form {
            Section("Yakıt kayıtlarından tüketim") {
                if let average = Metrics.average(store.entries) {
                    LabeledContent("Ortalama tüketim", value: number(average, digits: 2) + " L/100 km")
                    Button("Tüketimi kayıtlarımdan al") { draft.consumption = String(format: "%.2f", average) }
                } else {
                    Text("Tüketim için en az iki tam depo kaydı gerekir. Aradaki eksiksiz ara dolumlar da hesaba katılır.").font(.callout).foregroundStyle(.secondary)
                }
            }
            Section("Litre ve kilometreden hesapla") {
                field("Tüketilen yakıt (L)", text: Binding(get: { draft.measuredLiters ?? "" }, set: { draft.measuredLiters = $0 }))
                field("Gidilen mesafe (km)", text: Binding(get: { draft.measuredDistance ?? "" }, set: { draft.measuredDistance = $0 }))
                if let result = draft.measuredConsumption {
                    LabeledContent("Hesaplanan tüketim", value: number(result, digits: 2) + " L/100 km")
                }
                Button("Bu tüketimi kullan") {
                    if let result = draft.measuredConsumption { draft.consumption = String(format: "%.2f", result) }
                }.disabled(draft.measuredConsumption == nil)
                Text("Depoyu tam doldur. Sonraki tam dolumda alınan litreyi ve iki dolum arasında gidilen kilometreyi gir. Arada yakıt aldıysan o litreleri de ekle.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Yolculuk maliyeti") {
                field("Mesafe (km)", text: $draft.distance)
                field("Tüketim (L/100 km)", text: $draft.consumption)
                field(localized("Litre fiyatı") + " (" + (store.vehicle?.currency ?? "TRY") + ")", text: $draft.price)
                if let d = positive(draft.distance, allowZero: true), let c = positive(draft.consumption) {
                    LabeledContent("Gereken yakıt", value: number(d*c/100, digits: 2) + " L")
                    if let p = positive(draft.price, allowZero: true) {
                        LabeledContent("Tahmini maliyet", value: (d*c/100*p).formatted(.currency(code: store.vehicle?.currency ?? "TRY")))
                    }
                }
            }
            Section("Menzil") {
                field("Depodaki yakıt (L)", text: $draft.fuel)
                if let f = positive(draft.fuel, allowZero: true), let c = positive(draft.consumption) {
                    LabeledContent("Tahmini menzil", value: number(f/c*100, digits: 0) + " km")
                }
                Text("Girilen değerlere göre tahmindir; araçtan depo seviyesi okunmaz.").font(.caption)
            }
            Section {
                Label(LocalizedStringKey(saveStatus), systemImage: "internaldrive").font(.caption).foregroundStyle(.secondary)
                Text("Değişikliklerin bu araç için otomatik saklanır. Yeniden açıldığında kendi değerlerin korunur.").font(.caption)
            }
        }.navigationTitle("Hesaplayıcı")
        .disabled(store.vehicle == nil)
        .onAppear { load() }
        .onChange(of: store.vehicle?.id) { _, _ in load() }
        .onChange(of: draft) { _, value in
            guard let id = loadedID else { return }
            let saved = store.commit { db in
                var values = db.calculatorDrafts ?? [:]; values[id.uuidString] = value; db.calculatorDrafts = values
            }
            saveStatus = saved ? "Bu araç için kaydedildi" : "Kaydedilemedi; tekrar dene"
        }
    }
    private func load() {
        guard let vehicle = store.vehicle, loadedID != vehicle.id else { return }
        var initial = store.db.calculatorDrafts?[vehicle.id.uuidString] ?? CalculatorDraft()
        if store.db.calculatorDrafts?[vehicle.id.uuidString] == nil, let average = Metrics.average(store.entries) {
            initial.consumption = String(format: "%.2f", average)
        }
        draft = initial; loadedID = vehicle.id
        saveStatus = "Değerler cihazında saklanır"
    }
    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(title)).font(.caption).foregroundStyle(.secondary)
            TextField(LocalizedStringKey(title), text: text).keyboardType(.decimalPad).monospacedDigit()
        }
    }
}

struct AutoRecordingHelp: View {
    var body: some View {
        List {
            Section("1 · Ön hazırlık") {
                Text("Araç ekle, elle yolculuk başlatıp konum izni ver ve deneme kaydını bitir. Diğer → CarPlay → Otomatik yolculuk kaydı ayarını aç.")
            }
            Section("2 · Bağlanınca başlat") {
                Text("iPhone’da Kestirmeler → Otomasyon → + → CarPlay → Bağlandığında → Hemen Çalıştır seç. Uygulamalar altında Yakıt Defterim’in ‘Otomatik yolculuğu başlat’ eylemini ekle.")
            }
            Section("3 · Ayrılınca bitir") {
                Text("İkinci bir CarPlay otomasyonu oluştur: Bağlantı kesildiğinde → Hemen Çalıştır → Yakıt Defterim → ‘Otomatik yolculuğu bitir’.")
            }
            Section("Bilmen gerekenler") {
                Text("Başlatma eylemi GPS kaydını başlatmak için uygulamayı öne getirir; kilitli telefonda kilidi açman istenebilir. Her bağlantıda sessiz başlangıç garanti edilmez. Araçla gerçek cihaz testi yap.")
                Text("Yalnızca otomatik başlayan yolculuklar otomasyonla bitirilir. Elle başladığın kayıt devam eder. Zorla kapatılan uygulama kayıt yapmaz; kaydedilmiş bölüm korunur. Kısa bağlantı kopmaları yolculuğu bölebilir.")
                Text("CarPlay ekranının kapanması fiziksel bağlantının koptuğu anlamına gelmediği için otomatik bitirme, Kestirmeler’deki bağlantı kesilme tetikleyicisini kullanır.")
                Text("Veriler cihazda kalır. Bu otomasyonları iPhone’da sen oluşturmalısın; uygulama kendiliğinden oluşturamaz.")
            }
        }.navigationTitle("Otomatik kayıt")
    }
}

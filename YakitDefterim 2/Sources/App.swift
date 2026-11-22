import SwiftUI
import Charts
import UniformTypeIdentifiers
import PhotosUI
import Vision
import MapKit

// Use the property-wrapper form for compatibility with iOS 17 and macro-restricted build hosts.
typealias LocalState<Value> = SwiftUI.State<Value>

@main struct YakitDefterimApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var store = Store.shared
    var body: some Scene { WindowGroup { RootView().environmentObject(store).environment(\.locale, Locale(identifier: store.db.language ?? "tr")).tint(.teal).preferredColorScheme(.dark) } }
}
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: session.role)
        if session.role.rawValue == "CPTemplateApplicationSceneSessionRoleApplication" { config.delegateClass = CarPlayDelegate.self }
        return config
    }
}
func number(_ n: Double, digits: Int = 1) -> String { n.formatted(.number.precision(.fractionLength(digits))) }
func decimal(_ text: String) -> Double? { Double(text.replacingOccurrences(of: ",", with: ".")) }
struct RootView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Group {
            if store.readOnly {
                VStack(spacing: 20) {
                    Image(systemName: "lock.doc").font(.system(size: 44)).foregroundStyle(.teal)
                    Text("Kayıtların bekliyor").font(.title2.bold())
                    Text(LocalizedStringKey(store.dataIssue ?? "Veriler hazır değil. iPhone’un kilidini aç."))
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button("Yeniden dene") { store.retryLoad() }.buttonStyle(.borderedProminent)
                    Text("Uygulamayı silme veya aracı yeniden ekleme.").font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            } else {
        TabView {
            Dashboard().tabItem { Label("Özet", systemImage: "gauge.with.dots.needle.67percent") }
            EntriesView().tabItem { Label("Kayıtlar", systemImage: "fuelpump") }
            TripsView().tabItem { Label("Yolculuk", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
            RemindersView().tabItem { Label("Bakım", systemImage: "wrench.and.screwdriver") }
            SettingsView().tabItem { Label("Diğer", systemImage: "ellipsis.circle") }
        }
            }
        }
        .alert("Bilgi", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("Tamam") { store.error = nil } } message: { Text(store.error ?? "") }
    }
}

struct Dashboard: View {
    @EnvironmentObject var store: Store
    @LocalState private var showStations = false
    @LocalState var adding = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YOLUN HESABI SENDE").font(.caption).tracking(3).foregroundStyle(.teal)
                        HStack(spacing: 14) {
                            Image("BrandLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .accessibilityHidden(true)
                            Text("Yakıt Defterim")
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                        }
                        Text("Aracını tanı. Verin sende kalsın.").foregroundStyle(.secondary)
                    }
                    NavigationLink { ReportsView() } label: {
                        Label("Yol bilgisayarı", systemImage: "gauge.with.dots.needle.67percent")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent)
                    Button { showStations = true } label: {
                        Label("Yakındaki yakıt istasyonları", systemImage: "mappin.and.ellipse")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.bordered)
                    if store.vehicle == nil {
                        ContentUnavailableView("Aracınla başlayalım", systemImage: "car.side", description: Text("Diğer → Araçlar bölümünden araç ekle. Kayıtların bu iPhone’da saklanır."))
                    } else {
                        let average = Metrics.average(store.entries)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("ORTALAMA TÜKETİM").font(.caption).tracking(2)
                            HStack(alignment: .firstTextBaseline) { Text(average.map { number($0) } ?? "—").font(.system(size: 64, weight: .semibold, design: .rounded)); Text("L / 100 km").foregroundStyle(.secondary) }
                            Text(average == nil ? "En az iki tam depo kaydıyla hesaplanır." : "Tam depo aralıklarına göre ağırlıklı ortalama").font(.caption).foregroundStyle(.secondary)
                        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(.teal.opacity(0.14), in: RoundedRectangle(cornerRadius: 24))
                        HStack {
                            stat("Toplam gider", store.entries.reduce(0) { $0 + $1.amount }.formatted(.currency(code: store.vehicle?.currency ?? "TRY")), "turkishlirasign.circle")
                            stat("Son kilometre", number(store.odometer, digits: 0) + " km", "speedometer")
                        }
                        Button { adding = true } label: { Label("Yeni kayıt ekle", systemImage: "plus.circle.fill").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.borderedProminent)
                        let samples = Metrics.consumption(store.entries)
                        if !samples.isEmpty {
                            Text("Tüketim eğilimi").font(.title3.bold())
                            Chart(samples) { sample in
                                LineMark(x: .value("Tarih", sample.date), y: .value("L/100 km", sample.rate)).foregroundStyle(.teal)
                                PointMark(x: .value("Tarih", sample.date), y: .value("L/100 km", sample.rate)).foregroundStyle(.teal)
                            }.frame(height: 180).accessibilityLabel("Yakıt tüketimi grafiği")
                        }
                        let categories = Dictionary(grouping: store.entries, by: \.kind)
                        if !categories.isEmpty {
                            Text("Gider dağılımı").font(.title3.bold())
                            ForEach(categories.keys.sorted(), id: \.self) { key in
                                HStack { Text(LocalizedStringKey(key)); Spacer(); Text((categories[key] ?? []).reduce(0) { $0 + $1.amount }.formatted(.currency(code: store.vehicle?.currency ?? "TRY"))).bold() }
                            }
                        }
                        Text("Yaklaşan bakımlar").font(.title3.bold())
                        if store.reminders.isEmpty { Text("Bekleyen bakım yok.").foregroundStyle(.secondary) }
                        ForEach(store.reminders.prefix(3)) { ReminderRow(reminder: $0) }
                    }
                }.padding(20)
            }.navigationTitle("Özet").navigationBarTitleDisplayMode(.inline)
                
        }.sheet(isPresented: $adding) { EntryForm() }
        .sheet(isPresented: $showStations) { NearbyStationsView() }
    }
    func stat(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) { Label(LocalizedStringKey(title), systemImage: icon).font(.caption).foregroundStyle(.secondary); Text(value).font(.headline).minimumScaleFactor(0.6).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18))
    }
}
struct VehicleForm: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @LocalState var name = ""; @LocalState var plate = ""; @LocalState var fuel = "Benzin"; @LocalState var currency = "TRY"
    var body: some View {
        NavigationStack { Form {
            TextField("Araç adı", text: $name); TextField("Plaka (isteğe bağlı)", text: $plate)
            Picker("Yakıt türü", selection: $fuel) { ForEach(["Benzin", "Dizel", "LPG", "Hibrit"], id: \.self) { Text(LocalizedStringKey($0)) } }
            Picker("Para birimi", selection: $currency) { ForEach(["TRY", "EUR", "USD"], id: \.self) { Text(LocalizedStringKey($0)) } }
            Text("Her aracın tüketimi ayrı hesaplanır. LPG ve benzin kayıtlarını ayrı araç profillerinde tut.").font(.caption)
        }.navigationTitle("Araç ekle").toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("İptal") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Kaydet") { let v = Vehicle(name: name.trimmingCharacters(in: .whitespaces), plate: plate, fuel: fuel, currency: currency); store.commit { $0.vehicles.append(v); $0.selectedID = v.id }; if store.error == nil { dismiss() } }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
        } }
    }
}
struct EntriesView: View {
    @EnvironmentObject var store: Store
    @LocalState var adding = false; @LocalState var editing: Entry?; @LocalState var search = ""; @LocalState var deleting: Entry?
    var body: some View {
        NavigationStack {
            List {
                ForEach(store.entries.filter { search.isEmpty || "\($0.kind) \($0.station) \($0.note)".localizedCaseInsensitiveContains(search) }) { entry in
                    Button { editing = entry } label: {
                        HStack {
                            Image(systemName: entry.kind == "Yakıt" ? "fuelpump.fill" : "creditcard.fill").foregroundStyle(.teal).frame(width: 30)
                            VStack(alignment: .leading, spacing: 5) { Text(LocalizedStringKey(entry.kind)).foregroundStyle(.primary); Text(entry.date.formatted(date: .abbreviated, time: .omitted) + " · " + number(entry.odometer, digits: 0) + " km").font(.caption).foregroundStyle(.secondary) }
                            Spacer(); Text(entry.amount.formatted(.currency(code: store.vehicle?.currency ?? "TRY"))).foregroundStyle(.primary)
                        }
                    }.swipeActions { Button("Sil", role: .destructive) { deleting = entry } }
                }
            }.overlay { if store.entries.isEmpty { ContentUnavailableView("Henüz kayıt yok", systemImage: "fuelpump", description: Text("Yakıt ve diğer araç giderlerini + ile ekle.")) } }
            .navigationTitle("Kayıtlar").searchable(text: $search, prompt: "Kategori, istasyon veya not")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Kayıt ekle").disabled(store.vehicle == nil) } }
        }.sheet(isPresented: $adding) { EntryForm() }.sheet(item: $editing) { EntryForm(entry: $0) }
        .confirmationDialog("Bu kayıt silinsin mi?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) { Button("Kaydı sil", role: .destructive) { if let entry = deleting { store.commit { $0.entries.removeAll { $0.id == entry.id } } }; deleting = nil } }
    }
}
struct EntryForm: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    var entry: Entry?
    var initialStation = ""
    @LocalState private var showStations = false
    @LocalState private var initialized = false
    @LocalState var kind = "Yakıt"; @LocalState var date = Date(); @LocalState var km = ""; @LocalState var amount = ""; @LocalState var liters = ""; @LocalState var full = true; @LocalState var missed = false; @LocalState var station = ""; @LocalState var note = ""
    @LocalState var photo: PhotosPickerItem?; @LocalState var scanning = false; @LocalState var scanError: String?
    let categories = ["Yakıt", "Bakım", "Sigorta", "Vergi", "Muayene", "Tamir", "Otopark", "Geçiş", "Yıkama", "Diğer"]
    var valid: Bool { guard let k = decimal(km), k.isFinite, k >= 0, let a = decimal(amount), a.isFinite, a >= 0 else { return false }; return kind != "Yakıt" || (decimal(liters).map { $0.isFinite && $0 > 0 } ?? false) }
    var body: some View {
        NavigationStack { Form {
            Section("Kayıt") {
                Picker("Kategori", selection: $kind) { ForEach(categories, id: \.self) { Text(LocalizedStringKey($0)) } }
                DatePicker("Tarih", selection: $date, in: ...Date(), displayedComponents: .date)
                TextField("Kilometre sayacı (km)", text: $km).keyboardType(.decimalPad)
                TextField("Toplam tutar (\(store.vehicle?.currency ?? "TRY"))", text: $amount).keyboardType(.decimalPad)
            }
            if kind == "Yakıt" {
                Section("Dolum") {
                    TextField("Litre", text: $liters).keyboardType(.decimalPad)
                    if let a = decimal(amount), let l = decimal(liters), l > 0 { LabeledContent("Litre fiyatı", value: number(a/l, digits: 2)) }
                    Toggle("Depo tam doldu", isOn: $full); Toggle("Önceki dolumlardan biri eksik", isOn: $missed)
                    TextField("İstasyon", text: $station)
                    Button("Yakındaki istasyonlardan seç", systemImage: "mappin.and.ellipse") { showStations = true }
                }
            }
            Section("Not ve fiş") {
                TextField("Not", text: $note, axis: .vertical).lineLimit(3...8)
                PhotosPicker(selection: $photo, matching: .images) { Label(LocalizedStringKey(scanning ? "Fiş okunuyor…" : "Fiş fotoğrafından metin oku"), systemImage: "doc.text.viewfinder") }.disabled(scanning)
                Text("Metin cihaz üzerinde okunur ve nota eklenir. Tutarı ve litreyi kontrol ederek kendin gir. Fotoğraf uygulamaya kaydedilmez.").font(.caption).foregroundStyle(.secondary)
                if let scanError { Text(LocalizedStringKey(scanError)).foregroundStyle(.red) }
            }
        }.navigationTitle(LocalizedStringKey(entry == nil ? "Yeni kayıt" : "Kaydı düzenle")).toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("İptal") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Kaydet") { save() }.disabled(!valid) }
        }.onAppear { guard !initialized else { return }; initialized = true; station = initialStation; if let e = entry { kind = e.kind; date = e.date; km = String(e.odometer); amount = String(e.amount); liters = String(e.liters); full = e.fullTank; missed = e.missedFill; station = e.station; note = e.note } }
        .sheet(isPresented: $showStations) { NearbyStationsView { station = $0 } }
        .onChange(of: photo) { _, item in Task { await scan(item) } }
        }
    }
    func save() {
        guard valid, let vehicleID = entry?.vehicleID ?? store.vehicle?.id else { return }
        let result = Entry(id: entry?.id ?? UUID(), vehicleID: vehicleID, date: date, kind: kind, odometer: decimal(km)!, amount: decimal(amount)!, liters: kind == "Yakıt" ? decimal(liters)! : 0, fullTank: full, missedFill: missed, station: station, note: note)
        store.commit { db in db.entries.removeAll { $0.id == result.id }; db.entries.append(result) }
        if store.error == nil { dismiss() }
    }
    func scan(_ item: PhotosPickerItem?) async {
        guard let item else { return }; scanning = true; defer { scanning = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let result = try await Task.detached(priority: .userInitiated) {
                let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.automaticallyDetectsLanguage = true
                try VNImageRequestHandler(data: data).perform([request])
                return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            }.value
            note += (note.isEmpty ? "" : "\n") + result
            scanError = result.isEmpty ? "Okunabilir metin bulunamadı." : nil
        } catch { scanError = "Fiş okunamadı: \(error.localizedDescription)" }
    }
}

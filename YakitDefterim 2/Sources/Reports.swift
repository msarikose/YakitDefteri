import SwiftUI
import Charts

struct ReportsView: View {
    @EnvironmentObject private var store: Store
    @LocalState private var days = 30
    private let accent = Color(red: 0.25, green: 0.93, blue: 0.84)
    private var now: Date { Date() }
    private var since: Date? { days == 0 ? nil : Calendar.current.date(byAdding: .day, value: -days, to: now) }
    private var report: ReportSnapshot {
        ReportSnapshot.make(entries: store.entries, trips: store.db.trips.filter { $0.vehicleID == store.vehicle?.id }, since: since, now: now)
    }
    private var currency: String { store.vehicle?.currency ?? "TRY" }
    private var monthly: [(date: Date, amount: Double)] {
        Dictionary(grouping: report.entries) { Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: $0.date))! }
            .map { (date: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }.sorted { $0.date < $1.date }
    }
    private var categories: [(name: String, amount: Double)] {
        Dictionary(grouping: report.entries, by: \.kind).map { (name: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }.sorted { $0.amount > $1.amount }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SÜRÜŞ ANALİZİ").font(.caption2.weight(.bold)).tracking(3).foregroundStyle(accent)
                        Text(store.vehicle?.name ?? "Aracını ekle").font(.title2.bold())
                    }
                    Spacer()
                    Image(systemName: "car.side.fill").font(.title).foregroundStyle(accent)
                }
                Picker("Rapor dönemi", selection: $days) {
                    Text("30 gün").tag(30); Text("90 gün").tag(90); Text("1 yıl").tag(365); Text("Tümü").tag(0)
                }.pickerStyle(.segmented)
                if store.vehicle == nil {
                    ContentUnavailableView("Önce araç ekle", systemImage: "car", description: Text("Diğer → Araçlar bölümünden başlayabilirsin."))
                } else {
                    consumptionPanel
                    metricsGrid
                    tripPanel
                    consumptionChart
                    spendingPanel
                    maintenancePanel
                    Text("Kayıtlarından hesaplanır; canlı OBD verisi değildir. Tüketim, seçilen dönemde biten tam depo aralıklarını içerir; aralığın başlangıcı dönemden önce olabilir. Km başına gider, dönem giderinin kayıtlardaki kilometre farkına bölünmesidir. Hız, tamamlanan yolculukların mesafe/süre ortalamasıdır; duraklamaları içerir.")
                        .font(.caption2).foregroundStyle(.secondary).padding(.bottom, 16)
                }
            }.padding(20)
        }
        .background(Color(red: 0.025, green: 0.045, blue: 0.065))
        .navigationTitle("Yol bilgisayarı")
        .navigationBarTitleDisplayMode(.inline)
    }
    private var consumptionPanel: some View {
        VStack(spacing: 14) {
            Text("ORTALAMA TÜKETİM").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
            ZStack {
                Circle().trim(from: 0.12, to: 0.88).stroke(.white.opacity(0.07), style: StrokeStyle(lineWidth: 13, lineCap: .round)).rotationEffect(.degrees(90))
                if let value = report.averageConsumption {
                    Circle().trim(from: 0.12, to: 0.12 + 0.76 * min(max(value / 20, 0), 1))
                        .stroke(AngularGradient(colors: [.teal, accent, .cyan], center: .center), style: StrokeStyle(lineWidth: 13, lineCap: .round)).rotationEffect(.degrees(90))
                }
                VStack(spacing: 6) {
                    Text(report.averageConsumption.map { number($0) } ?? "—")
                        .font(.system(size: 62, weight: .light, design: .rounded)).monospacedDigit()
                    Text("L / 100 km").font(.caption).foregroundStyle(accent)
                }
            }.frame(height: 220).padding(.horizontal, 24)
            HStack {
                smallValue("Son dolum aralığı", report.samples.last.map { number($0.rate) + " L/100" } ?? "—")
                Spacer()
                smallValue("En düşük aralık", report.samples.map(\.rate).min().map { number($0) + " L/100" } ?? "—")
            }
            Text(report.samples.isEmpty ? LocalizedStringKey("Tüketim için en az iki tam depo kaydı gerekir.") : LocalizedStringKey("\(report.samples.count) tam depo aralığı • Gösterge ölçeği 0–20 L/100 km"))
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(22).frame(maxWidth: .infinity).background(panelBackground)
    }
    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            tile("TOPLAM GİDER", report.totalCost.formatted(.currency(code: currency)), "creditcard")
            tile("KM BAŞINA GİDER", report.costPerKM.map { number($0, digits: 2) + " " + currency } ?? "—", "road.lanes")
            tile("ALINAN YAKIT", number(report.fuelLiters) + " L", "fuelpump.fill")
            tile("ORT. LİTRE FİYATI", report.averagePrice.map { $0.formatted(.currency(code: currency)) } ?? "—", "tag")
            tile("KAYIT KM FARKI", report.loggedDistance.map { number($0, digits: 0) + " km" } ?? "—", "speedometer")
            tile("YAKIT DIŞI GİDER", (report.totalCost - report.fuelCost).formatted(.currency(code: currency)), "wrench.and.screwdriver")
        }
    }
    private var tripPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Yolculuk özeti", "point.topleft.down.to.point.bottomright.curvepath")
            HStack {
                smallValue("Mesafe", number(report.tripDistance, digits: 1) + " km")
                Spacer()
                smallValue("Toplam süre", String(format: localized("%@ saat"), number(report.tripSeconds / 3600, digits: 1)))
            }
            HStack {
                smallValue("Ortalama hız", report.averageSpeed.map { String(format: localized("%@ km/sa"), number($0, digits: 0)) } ?? "—")
                Spacer()
                smallValue("Tamamlanan", String(report.trips.count))
            }
            Divider()
            HStack {
                Text("İş / kişisel mesafe").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(number(report.trips.filter { $0.purpose == "İş" }.reduce(0) { $0 + $1.distance }, digits: 0) + " / " + number(report.trips.filter { $0.purpose != "İş" }.reduce(0) { $0 + $1.distance }, digits: 0) + " km").font(.caption.monospacedDigit())
            }
        }.padding(20).background(panelBackground)
    }
    private var consumptionChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Tüketim eğrisi", "chart.xyaxis.line")
            if report.samples.isEmpty {
                Text("Bu dönem için tamamlanmış dolum aralığı yok.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Chart(report.samples) { sample in
                    LineMark(x: .value("Tarih", sample.date), y: .value("L/100 km", sample.rate)).foregroundStyle(accent)
                    PointMark(x: .value("Tarih", sample.date), y: .value("L/100 km", sample.rate)).foregroundStyle(accent)
                }.frame(height: 170)
                ForEach(report.samples.suffix(3).reversed()) { sample in
                    HStack { Text(sample.date.formatted(date: .abbreviated, time: .omitted)); Spacer(); Text(number(sample.rate) + " L/100 km").monospacedDigit() }.font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(20).background(panelBackground)
    }
    private var spendingPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Gider analizi", "chart.bar.fill")
            if monthly.isEmpty {
                Text("Bu dönemde gider kaydı yok.").foregroundStyle(.secondary)
            } else {
                Chart(monthly, id: \.date) { month in
                    BarMark(x: .value("Ay", month.date, unit: .month), y: .value(currency, month.amount)).foregroundStyle(accent.gradient).cornerRadius(5)
                }.frame(height: 160)
                ForEach(categories, id: \.name) { category in
                    VStack(spacing: 6) {
                        HStack { Text(LocalizedStringKey(category.name)); Spacer(); Text(category.amount.formatted(.currency(code: currency))).monospacedDigit() }.font(.subheadline)
                        ProgressView(value: report.totalCost > 0 ? category.amount / report.totalCost : 0).tint(accent)
                    }
                }
                Divider()
                ForEach(monthly.reversed(), id: \.date) { month in
                    HStack { Text(month.date.formatted(.dateTime.month(.wide).year())); Spacer(); Text(month.amount.formatted(.currency(code: currency))) }.font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(20).background(panelBackground)
    }
    private var maintenancePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Bakım radarı", "wrench.adjustable")
            if store.reminders.isEmpty { Text("Bekleyen bakım yok.").foregroundStyle(.secondary) }
            ForEach(store.reminders.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }.prefix(4)) { reminder in
                ReminderRow(reminder: reminder)
                if let target = reminder.odometer {
                    Text(target > store.odometer ? String(format: localized("%@ km kaldı"), number(target - store.odometer, digits: 0)) : localized("Kilometre sınırı geldi"))
                        .font(.caption).foregroundStyle(target > store.odometer ? accent : .orange)
                }
            }
        }.padding(20).background(panelBackground)
    }
    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 24).fill(LinearGradient(colors: [Color.white.opacity(0.07), Color.white.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay { RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.07), lineWidth: 1) }
    }
    private func heading(_ title: String, _ icon: String) -> some View {
        Label(LocalizedStringKey(title), systemImage: icon).font(.headline).foregroundStyle(accent)
    }
    private func smallValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(title)).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit()).minimumScaleFactor(0.65).lineLimit(1)
        }
    }
    private func tile(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon).foregroundStyle(accent)
            Text(value).font(.title3.bold().monospacedDigit()).minimumScaleFactor(0.6).lineLimit(1)
            Text(LocalizedStringKey(title)).font(.system(size: 10, weight: .semibold)).tracking(0.7).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, minHeight: 104, alignment: .leading).padding(16).background(panelBackground)
    }
}

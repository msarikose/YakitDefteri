import AppIntents

struct StartAutomaticTripIntent: AppIntent {
    static var title: LocalizedStringResource = "Otomatik yolculuğu başlat"
    static var description = IntentDescription("Seçili araç için yerel GPS kaydı başlatır. Uygulamadaki otomatik kayıt ayarının açık olması gerekir.")
    // A foreground launch lets Core Location start a user-initiated session reliably;
    // this deliberately does not claim silent, locked-device background activation.
    static var openAppWhenRun: Bool = true
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = TripRecorder.shared.startAutomatic()
        return .result(dialog: IntentDialog(stringLiteral: localized(message)))
    }
}
struct StopAutomaticTripIntent: AppIntent {
    static var title: LocalizedStringResource = "Otomatik yolculuğu bitir"
    static var description = IntentDescription("Otomatik başlayan etkin yolculuğu kaydeder. Elle başlayan yolculuğu durdurmaz.")
    static var openAppWhenRun: Bool = false
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = TripRecorder.shared.stopAutomatic()
        return .result(dialog: IntentDialog(stringLiteral: localized(message)))
    }
}

# CarPlay kurulumu ve başvuru taslağı

Ücretli Apple Developer üyeliği, CarPlay yetkisini otomatik olarak vermez. Aşağıdaki başvuru henüz gönderilmedi.

## Başvuru

[Apple CarPlay başvuru sayfası](https://developer.apple.com/contact/carplay/) üzerinden **Driving Task** kategorisi için başvur. Bu kategori seçimi bir geliştirme önerisidir; uygunluğa Apple karar verir. Uygulama yakındaki yakıt istasyonlarını göstermediği için Fueling kategorisine hazır olduğu iddia edilmiyor.

İngilizce açıklama taslağı:

> Yakıt Defterim is a privacy-focused vehicle expense and trip log for iPhone. The proposed CarPlay experience is a minimal driving-task interface: a glanceable summary for the selected vehicle and a single action to start or stop a locally recorded trip. Maintenance items are read-only. Fuel entry, receipt reading, expense editing and data export remain on iPhone. The app does not include ads, analytics, user accounts or a server backend. Location is used only for a user-started trip and stored on the device. We request the CarPlay Driving Task entitlement to evaluate and test this limited interface on supported vehicles.

Bu taslağı kendi gerçek geliştirici bilgilerin, uygulama durumu ve test planınla gözden geçirerek gönder. Henüz cihaz testi yapılmadığından yayınlanmış/araçta doğrulanmış bir ürün olarak sunma.

## Yetki onaylandıktan sonra

1. Developer hesabında uygulamanın App ID’sini oluştur veya seç.
2. App ID’de **CarPlay Driving Task** yetkisini etkinleştir.
3. Cihazını içeren ve bu yetkiyi destekleyen geliştirme provisioning profile’ını oluştur, indir ve Xcode’a yükle.
4. Xcode’da **YakitDefterim-CarPlay** şemasını seç. Bu şema `CarPlay` yapılandırmasını kullanır; `CarPlay.entitlements` ona bağlıdır.
5. Bundle Identifier, Development Team ve manuel provisioning profile ayarlarını kendi App ID’nle eşleştir.
6. Gerçek iPhone’a derle ve kur. Önce telefonda araç ekle ve yolculuk için konum izni ver.
7. CarPlay simülatöründe ve park halindeki araçta dene.

Normal **YakitDefterim** şeması CarPlay entitlement’ını istemez; CarPlay onayı gelmeden telefon tarafını denemeye yarar. CarPlay şeması tek başına onay yerine geçmez.

Kaynak: [Apple — Preparing your iOS app for CarPlay development](https://developer.apple.com/documentation/carplay/preparing-your-ios-app-for-carplay-development).

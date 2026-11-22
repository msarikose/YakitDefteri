# Yakıt Defterim

Türkçe, yerel veri kullanan bağımsız bir iPhone uygulaması. Fuelio ile bağlantısı yoktur. **Bu teslim 0.1 geliştirme sürümüdür; Fuelio Premium’un tüm özelliklerinin tamamlanmış karşılığı değildir.**

## Çalıştırma

1. `YakitDefterim.xcodeproj` dosyasını Xcode ile aç.
2. Normal iPhone denemesi için **YakitDefterim** şemasını seç.
3. Target → Signing & Capabilities bölümünde kendi Apple Developer takımını seç. Bundle Identifier alanını hesabında benzersiz bir kimlikle değiştir.
4. iOS 17 veya üzeri bir iPhone bağla. Gerekirse telefonda Geliştirici Modu’nu aç, cihazı hedef olarak seç ve Run düğmesine bas.
5. Uygulamanın üst menüsünden araç ekle. GPS iznini ilk yolculuğu başlatırken, bildirim iznini Bakım ekranından ver.

CarPlay şeması Apple tarafından onaylanmış profil gerektirir. Ayrıntılar `CARPLAY-KURULUM.md` içinde. İmzalı IPA veya telefona kurulum bu teslimde yapılmadı.

## Kaynak kodda bulunan özellikler

- Birden fazla araç; her araç için TRY, EUR veya USD.
- Yakıt, bakım, sigorta, vergi, muayene, tamir, otopark, geçiş, yıkama ve diğer giderler.
- Kayıt ekleme, düzenleme, silme ve arama.
- Tam depo aralıklarına dayanan tüketim hesabı; kısmi dolumları dahil etme, eksik dolumdan sonraki aralığı sıfırlama.
- Tüketim grafiği, kategori toplamları ve aylık gider raporu.
- Tarihe göre yerel bildirim; girilen kilometreye göre uygulama içi bakım uyarısı; bakım tamamlama geçmişi.
- Kullanıcının başlatıp bitirdiği GPS yolculuğu; arka planda konum kaydı, yerel rota çizimi ve elle iş/kişisel yolculuk ekleme.
- Apple Vision ile cihazda fiş metni okuma. Sonuç nota eklenir; parasal alanlar otomatik doldurulmaz.
- Yakıt ihtiyacı, yolculuk maliyeti ve menzil hesaplayıcı.
- Tüm veriler için JSON yedeği ve geri yükleme; seçili aracın kayıtları için uygulamaya özel CSV içe/dışa aktarma.
- CarPlay liste şablonuyla seçili araç özeti, bakım listesi ve yolculuk başlatma/bitirme.
- İsteğe bağlı CarPlay ekranı açılışında otomatik kayıt ve Kestirmeler için otomatik yolculuk başlat/bitir App Intent eylemleri. Kurulum uygulamada Diğer → CarPlay → Otomatik kayıt kurulumu bölümünde.

## Henüz bulunmayan veya doğrulanmayan özellikler

- Canlı yakıt fiyatları ve fiyat karşılaştırması. İstasyon arama ve Apple Haritalar’a yol tarifi aktarma iPhone sürümüne eklendi; CarPlay içinde kayıtlı marka/mesafe tercihleriyle kısa bir istasyon listesi ve Apple Haritalar’a yol tarifi aktarımı da vardır.
- Fuelio’nun gerçek CSV dışa aktarma formatından doğrudan göç. Dahili CSV şeması Fuelio formatı değildir. Bir örnek dışa aktarım yapısı olmadan veri taşınmış sayılmamalı.
- Bluetooth ile otomatik sürüş algılama, tamamen sessiz/kilitli telefonda garanti edilen otomatik başlangıç ve ana ekran widget’ları.
- Fiş tutarını alanlara otomatik yerleştirme, fiş görseli arşivi, PDF raporları, özel gider kategorileri ve tekrar eden bakım planları.
- Elektrikli araç kWh hesabı, aynı araçta çok yakıtlı depo modeli, mil/galon dönüşümleri.
- Araç profilini düzenleme/silme, uygulamaya özel Face ID kilidi, şifreli dışa aktarma ve bulut senkronizasyonu.
- Gerçek cihazda arka plan GPS, bildirim teslimi, OCR ve CarPlay doğrulaması. Apple’ın CarPlay uygunluk/onay kararı garanti değildir.

## Gizlilik

Uygulamaya ait sunucu, hesap, reklam/analiz SDK’sı veya bulut senkronizasyonu yoktur. Kullanıcı istasyon aramasını başlattığında MapKit aracılığıyla konum çevresi Apple Haritalar hizmetine gönderilir. Yol tarifi düğmesi Apple Haritalar uygulamasını açar. Yakıt ve gider kayıtları arama isteğine dahil edilmez. Veri `Application Support/YakitDefterim/database.json` içinde atomik yazılır; iOS dosya koruması kullanılır. Uygulama veri klasörü sistem yedeğinden hariç tutulur. Bu nedenle uygulamayı silmeden veya telefon değişiminden önce elle yedek almalısın.

JSON yedeği plakaları, notları, konumları ve yolculukları içerebilir. JSON ve CSV şifrelenmez. Dosyalar uygulamasında iCloud veya başka sağlayıcı seçersen o dışa aktarılan kopya seçtiğin hizmete gider. Yalnızca cihazda tutmak için “iPhone’umda” seç. Fotoğraf seçicisinde iCloud’daki bir fotoğrafın indirilmesi Apple’ın hizmetini kullanabilir; OCR sonrasında cihazda yapılır.

GPS kaydı kullanıcı elle başlatınca veya otomatik kayda izin verip ilgili tetikleyiciyi çalıştırınca başlar; zorla kapatılınca devam etmez. Her konum güncellemesinde kaydedilmiş bölüm saklanır. Kilometre sayacı araçtan okunmaz; kullanıcı kayıtlarından hesaplanır. Rota çiziminde harita altlığı kullanılmaz.

## Doğrulama

19 Kasım 2026 tarihinde Xcode 27 ile fiziksel iPhone SDK’sına karşı **imzasız Debug derlemesi başarılı**. Çekirdek modeller için 12 otomatik kontrol geçti. Testler:

```sh
./Tests/run.sh
```

Kontroller boş/tek dolum, tam depo, kısmi dolum, eksik dolum, tamamlanmamış aralık, ağırlıklı ortalama, Unicode/tırnak/satır sonlu CSV, JSON dönüşümü ve geçersiz/tekrarlı kayıtları kapsar.

Bu ortamda CoreSimulator servisine erişilemedi. Ekranların görsel testi ve uçtan uca gerçek cihaz testleri yapılmadı. Derleme başarısı bunların yerine geçmez.

## İlk cihaz testi

- Araç oluştur; 1.000 km’de tam depo, 1.250 km’de 15 L kısmi, 1.500 km’de 20 L tam depo kaydet. Son tüketim 7 L/100 km olmalı.
- Kaydı düzenle, uygulamayı kapat/aç; veri korunmalı.
- JSON dışa aktar, geri yükle; kayıt ve yolculuk sayısını karşılaştır.
- Bildirim izni verip gelecekteki bir tarih için hatırlatma oluştur.
- Açık havada kısa GPS yolculuğu başlat; ekran kilitliyken kaydı ve bitirdikten sonra rota çizimini kontrol et.
- Uçak modunda cihazdaki bir fişi seç ve metin okuma sonucunu kontrol et.
- CarPlay yetkisiyle imzalandıktan sonra bağlantı, başlangıç, bitiş, yeniden bağlanma ve konum izni reddi senaryolarını dene.

Kaynaklar: [Fuelio özellikleri](https://www.fuel.io/en-US/features/), [Apple CarPlay hazırlığı](https://developer.apple.com/documentation/carplay/preparing-your-ios-app-for-carplay-development).

## CarPlay otomatik kayıt güncellemesi

Ayar varsayılan olarak kapalıdır. Eski yedekler ayar olmadan açılır ve otomatik kayıt kapalı kalır. Kullanıcı ayarı açınca CarPlay uygulama sahnesinin bağlantısı otomatik kaydı başlatabilir; bu olay her fiziksel CarPlay bağlantısını temsil etmez.

Her fiziksel bağlantı için iPhone Kestirmeler uygulamasında iki kişisel otomasyon gerekir:

1. CarPlay → Bağlandığında → Hemen Çalıştır → Yakıt Defterim → Otomatik yolculuğu başlat.
2. CarPlay → Bağlantı kesildiğinde → Hemen Çalıştır → Yakıt Defterim → Otomatik yolculuğu bitir.

Önce iPhone’da araç ve konum izni hazırlanmalıdır. Başlangıç eylemi uygulamayı öne getirir (`openAppWhenRun = true`); kilit açma gerekebilir. Kilitli/kapalı uygulamanın her bağlantıda sessizce kayda başlaması garanti edilmez. Kullanıcının elle başlattığı kayıt otomatik bitirme tarafından durdurulmaz. Otomatik kayıt ayarını kapatmak otomatik başlayan etkin kaydı bitirir. Kopup yeniden bağlanmak yeni yolculuk oluşturabilir. Uygulama süreci sonlandırılırsa kaydedilmiş bölüm tamamlanmamış kayıt olarak korunur; otomasyon kayıt sürecini geri getirdiğini iddia etmez.

Güncelleme doğrulaması: iPhone için imzasız derleme ve 14 çekirdek kontrolü. Ek iki kontrol eski yedek uyumluluğu ve ayar serileştirmesidir. CarPlay olayları, Kestirmeler, telefon kilidi ve arka plan GPS davranışı gerçek cihazda henüz doğrulanmadı.

Kaynaklar: [Apple CarPlay sahne yaşam döngüsü](https://developer.apple.com/documentation/carplay/displaying-content-in-carplay), [Kestirmeler seyahat tetikleyicileri](https://support.apple.com/guide/shortcuts/apd8ebfc4e8e/ios).

## Yakındaki istasyonlar

Özet → Yakındaki yakıt istasyonları veya yeni/düzenlenen yakıt kaydında Dolum → Yakındaki istasyonlardan seç. Arama düğmesi konum izni ister; seçilen 2/5/10/25/50 km yarıçapı ve marka filtresiyle bölge tabanlı MapKit araması yapar. Dönen sonuçlar mesafeye göre ayrıca süzülür. Apple’ın sonuç kapsamı eksik olabilir. Liste kuş uçuşu mesafeye göre sıralıdır; sürüş mesafesi değildir ve tüm istasyonları kapsadığı garanti edilmez. Seçim istasyon adını forma aktarır; kayıt kullanıcı Kaydet’e basınca oluşur. Canlı fiyat veya otomatik dolum kaydı yoktur. Benzin/LPG için tarihli yerel fiyat notları eklenebilir; bunlar kullanıcı notu olarak açıkça etiketlenir.

Konum izni reddi, konum zaman aşımı, ağ hatası ve boş sonuç durumları ele alınır. Sayfa kapanırken arama iptal edilir. GPS yolculuk kaydından ayrı bir konum yöneticisi kullanılır. İstasyon araması ve yol tarifi için internet/Apple hizmetleri gerekir. Gerçek cihazda canlı arama, izin reddi, form alanlarının seçim sonrası korunması ve Haritalar’a geçiş test edilmelidir.

## 20 Kasım 2026 güncellemesi

- İstasyon araması: 2, 5, 10, 25, 50 km ve marka filtresi. Seçimler yerel veritabanına/yedeğe kaydedilir. Marka, MapKit sonuç adından tanınır; adı farklı kayıtlı bayiler listelenmeyebilir. İlk arama düğmeyle başlar. Sonrasında filtre değişince sonuçlar temizlenir ve yeni filtreyle otomatik arama yapılır.
- Hesaplayıcı: mesafe, tüketim, litre fiyatı ve depodaki yakıt her araç için otomatik kaydedilir. Kullanıcı değeri sonraki açılışta hesaplanan ortalamayla değiştirilmez. “Tüketimi kayıtlarımdan al” isteğe bağlıdır.
- Yol bilgisayarı: Özet ekranından ve Diğer bölümünden açılır. 30/90/365 gün veya tüm geçmiş; tüketim göstergesi ve grafiği, gider/km, litre fiyatı, yakıt/gider toplamları, tamamlanan yolculuk mesafe/süre/hız özeti, kategori dağılımı, aylık gider ve yaklaşan bakım bilgileri. Eksik ölçümler sıfır tüketim/hız diye sunulmaz. Canlı OBD bağlantısı yoktur.
- Fiyatlar: canlı istasyon fiyatı entegrasyonu **tamamlanmadı**. Benzin/LPG fiyat alanları ve fiyat notu ekranı kullanıcı isteğiyle kaldırıldı. Opet/Petrol Ofisi için resmî fiyat sayfası bağlantıları vardır. İl/ilçe tarifesi istasyonun gerçek pompa fiyatı olarak kullanılmaz. Fiyat notları TRY/L cinsindedir.
- İmzasız iPhone derlemesi başarılı; 24 çekirdek kontrolü geçti. Yeni ekranın cihaz görüntüsü, canlı arama, kullanıcı düzenlemelerinin yeniden açılışta görünmesi ve dinamik yazı boyutları gerçek cihazda henüz doğrulanmadı.

Aktif Xcode kopyası: `YakitDefterim 2/YakitDefterim.xcodeproj`. Ana dağıtım klasörünün kaynakları da eşitlendi; takım/imzalama ayarları ayrı korundu.

## İstasyon listesi ve İngilizce güncellemesi

- Fiyat alanları/not ekleme ekranı kaldırıldı; uygun markalarda resmî fiyat sayfası bağlantısı kaldı. Eski fiyat notları veri kaybını önlemek için yalnızca yedek modelinde korunur.
- Sonuç kartları sadeleştirildi. Tek bir kısa konum paylaşımı açıklaması gösterilir.
- İlk aramadan sonra mesafe/marka değişimi otomatik yeniden arama başlatır. Güncel konum kısa süreli yeniden kullanılır. Marka araması yalnızca marka adıyla yapılır; Apple’ın kategori etiketlemesine bağlı gereksiz elemeyi önlemek için gaz istasyonu kategori filtresi sadece Tümü seçiminde kullanılır. Marka ve dairesel mesafe kontrolü sonuçlara ayrıca uygulanır. MapKit tüm istasyonları döndürmeyi garanti etmez.
- Diğer → Dil / Language altında Türkçe/English seçimi vardır. Seçim veritabanına kaydedilir; 244 çeviri girdisi eklendi. Kullanıcı notları, araç isimleri ve saklanan kategori anahtarları değiştirilmez. Apple’ın sistem izin ekranları telefonun dil tercihlerini kullanabilir.
- İmzasız iPhone derlemesi ve 32 çekirdek kontrolü geçti. Çeviri dosyalarının uygulama paketine dahil edildiği kontrol edildi. Canlı istasyon araması, dil değişimindeki tüm ekran yerleşimleri ve CarPlay görünümü gerçek cihazda henüz doğrulanmadı.

## CarPlay kilitli cihazda veri erişimi düzeltmesi

Önceki `completeFileProtectionUnlessOpen` dosya koruması, dosya kapandıktan sonra kilitli telefonda yeniden okumayı engelleyebiliyordu. Başlangıç okuma hatası da uygulama süreci boyunca kalıcı salt-okunur duruma yol açıyordu. Artık veritabanı `completeFileProtectionUntilFirstUserAuthentication` ile yazılır: dosya şifreli kalır, yeniden başlatma sonrası ilk kilit açılışına kadar okunamaz; sonrasında telefon tekrar kilitlense de uygulama erişebilir. Mevcut dosya başarıyla okunup doğrulandıktan sonra yalnızca koruma özniteliği güncellenir.

Kilit açılışı ve uygulamanın yeniden etkinleşmesi başarısız okumayı yeniden dener. Kullanıcı da Yeniden dene düğmesini kullanabilir. CarPlay erişim hatasını araç yok olarak sunmaz. Okuma hatası/bozuk dosya hiçbir zaman boş veritabanı olarak kaydedilmez. Veri açılmadan dışa aktarma, değişiklik ve yolculuk başlatma engellenir.

Kurulum: uygulamayı silmeden aynı uygulama kimliğiyle güncelle, iPhone’un kilidini açıp uygulamayı bir kez aç. Araçların görünmesini doğrula, ardından park halindeyken CarPlay’i dene. Eski dosya ilk kez açılmadan koruma geçişi tamamlanamaz. Telefonda verinin geri geldiği henüz doğrulanmadı.

Doğrulama: CarPlay şemasıyla imzasız iPhone derlemesi başarılı; 40 kontrol geçti. İzin reddi, yazmanın engellenmesi, erişimin geri gelmesiyle kayıtların korunması, kilitliyken eksik dosyanın oluşturulmaması, bozuk dosya ve gerçek dosyada atomik kaydet/oku senaryoları test edildi. Gerçek cihaz kilit durumları otomatik test ortamında çalıştırılmadı.

## CarPlay menüleri

Ana listeden yolculuk başlat/bitir, yakın istasyonlar, tüketim özeti, hesaplayıcı, bakım planı ve araç seçimine erişilir. Alt ekranlar tek seviyelidir; Driving Task için liste şablonları kullanılır. Ayrıntılı kayıt formları, grafikler ve ayarlar iPhone’da kalır. Hesaplayıcı iPhone’da kaydedilmiş araç bazlı değerleri gösterir; canlı depo/OBD verisi değildir. Aktif kayıt sırasında araç değiştirilemez.

İstasyon araması iPhone’daki marka/mesafe tercihlerini kullanır, ilk konum izni iPhone’dan verilmelidir. Aynı bağlantıda aramalar arasında en az 60 saniye vardır; sonuçlar en fazla sekiz istasyondur. Seçim Apple Haritalar’da araçla yol tarifini açar. Periyodik yolculuk/tüketim güncellemeleri en fazla 10 saniyede birdir.

Doğrulama: CarPlay şeması imzasız iPhone derlemesi ve mevcut 40 çekirdek kontrolü. Gerçek CarPlay’de menüler, kilitli telefon, dil değişimi, istasyon araması ve Haritalar’a geçiş ayrıca denenmelidir.

## CarPlay simgeli ana ekran

Ana ekran CPGridTemplate ile altı renkli simgeye dönüştürüldü: yolculuk, istasyonlar, tüketim, hesaplayıcı, bakım ve araç seçimi. Başlık seçili araçtır; aktif yolculuk düğmesi turuncu durdurma simgesi ve alana sığarsa mesafe gösterir. Alt ekranlar okunabilir sistem listeleridir. Simge ölçeği CarPlay ekranından alınır; renkler, yuvarlatılmış simge zeminleri ve çizgiler uygulamada çizilir. Ekranın arka planı, yazı tipi ve son yerleşimi CarPlay yönetir.

CarPlay şemasıyla imzasız iPhone derlemesi başarılı. Gerçek araçta simge boyutları, açık/koyu görünüm ve dokunma hedefleri henüz doğrulanmadı.

## İki yöntemle tüketim hesaplama

Hesaplayıcı yakıt kayıtlarının tam depo ortalamasını gösterir; “Tüketimi kayıtlarımdan al” seçilen değeri maliyet/menzil için kaydeder. Alternatif olarak tüketilen litre ve gidilen kilometre girilir, L/100 km sonucu hesaplanır ve “Bu tüketimi kullan” ile uygulanır. Yeni taslaklar yeterli kayıt yoksa tüketimi boş bırakır; önceden kaydedilmiş kullanıcı değerleri korunur. Ölçüm girişleri araç bazında saklanır ve eski yedeklerle uyumludur. İngilizce metinler eklendi. CarPlay hesaplayıcısı aynı kaydedilen tüketim değerini kullanır.

Doğrulama: 49 çekirdek kontrolü ve CarPlay şemasıyla imzasız iPhone derlemesi başarılı; cihazda ekran testi yapılmadı.

## CarPlay iç ekranları

Tüketim ve hesaplayıcı CPInformationTemplate iki sütunlu bilgi panelleri kullanır. İstasyon listesinde turkuaz yakıt simgeleri ve yön oku, bakımda turuncu servis simgeleri, araç seçiminde mavi araç/seçim simgeleri vardır. Liste başlığında seçili araç gösterilir. Sistem geri düğmesi ve iki seviyeli gezinme korunur. İmzasız CarPlay derlemesi başarılı; gerçek araçta panel yerleşimi henüz test edilmedi.

## CarPlay istasyon filtreleri

Yakın istasyonlar içinde Marka ve Arama mesafesi satırları açılır; telefonla aynı marka listesi ve 2/5/10/25/50 km seçenekleri kullanılır. Seçimler ortak yerel veritabanına kaydedilir. Seçim ekranı aynı listeyi değiştirir ve Sonuçlara dön satırı sağlar; ek gezinme derinliği oluşturmaz. Filtre değişince eski sonuçlar temizlenir. POI aramaları arasındaki 60 saniyelik sınır dolmadıysa yeni arama otomatik ertelenir ve bekleme mesajı gösterilir. Bağlantı kesilince bekleyen arama iptal edilir.

Doğrulama: 49 mevcut kontrol ve imzasız CarPlay derlemesi başarılı. Gerçek CarPlay’de filtre seçimleri ve canlı istasyon sonuçları henüz test edilmedi.

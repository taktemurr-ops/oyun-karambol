# Karambol (oyun-karambol)

Masa Oyunları merkez uygulamasındaki carrom tipi parmakla vuruşlu tahta oyunu. Vurucuyu taban çizginde kaydırıp geri çekerek fiskelersin; kendi taşlarını köşe ceplerine sokar, kırmızı kraliçeyi kendi taşınla örtersin. Vurucuyu cebe sokmak fauldür.

- 33 dil; seviyeler (100.000) bilgisayara karşı iki kişilik maç, günlük/haftalık/meydan okuma/zen/sonsuz/zamana karşı tek kişilik tahta temizleme
- Çevrimiçi masa: sırayla vuruş; vuruşu yapan cihaz sonucu ve son dizilimi gönderir, iki tahta her vuruştan sonra birebir aynıdır; kopan rakibin yerine bot geçer
- Fizik saf Dart ve deterministik; her seviye bot tarafından bitirilerek doğrulanır
- Testler: `flutter test`

Kullanım: `import 'package:oyun_karambol/oyun_karambol.dart';` ve `karambolConfig`.

import 'package:flutter_test/flutter_test.dart';
import 'package:oyun_karambol/oyun_karambol.dart';

void main() {
  test('33 dilde ad, slogan, anlatım ve eğitim var', () {
    expect(karambolConfig.gameId, 'oyun-karambol');
    expect(karambolConfig.title.length, 33);
    expect(karambolConfig.tagline.length, 33);
    for (final s in karambolConfig.tutorial) {
      expect(s.text.length, 33);
      expect(s.text.every((t) => t.trim().isNotEmpty), isTrue);
    }
  });
}

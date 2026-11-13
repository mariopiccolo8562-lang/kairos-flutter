import 'package:flutter_test/flutter_test.dart';
import 'package:kairos_plus/data/models.dart';

void main() {
  test('separatori del fornitore nascosti, titoli veri no', () {
    for (final n in ['----NOME----', '##### SPORT #####', '==== FILM 2024 ====', '★★★ CINEMA ★★★', '—— PRIME VIDEO ——', '*** NOVITÀ ***', '']) {
      expect(isSepName(n), isTrue, reason: n);
    }
    for (final n in ['...E giustizia per tutti', 'Rocky ★★★', 'X-Men: Giorni di un futuro passato', '|IT| RAI 1', 'M*A*S*H', 'Spider-Man – No Way Home']) {
      expect(isSepName(n), isFalse, reason: n);
    }
  });
}

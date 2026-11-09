import 'package:flutter_test/flutter_test.dart';
import 'package:kairos_plus/data/quality_box.dart';

/// Riquadro della qualità nel lettore dal pannello (voce rc «qbox», contratto comune di tutte le app Kairos):
/// che cosa riceve il lettore nativo (`resInd` = può comparire, `resTag` = con la sigla di qualità).
void main() {
  // tutto quello che il pannello può mandare (o non mandare) e che deve valere come oggi
  const likeToday = <Object?>['full', '', null, 'null', 'OFF', ' off', 'noq ', 'qualsiasi', 1, true];

  test('solo «off» e «noq» cambiano qualcosa', () {
    expect(QualityBox.of('off'), QualityBox.off);
    expect(QualityBox.of('noq'), QualityBox.noq);
    for (final v in likeToday) {
      expect(QualityBox.of(v), QualityBox.full, reason: '«$v»');
    }
  });

  test('come oggi: riquadro con la sigla, se il permesso «resInd» lo consente', () {
    for (final v in likeToday) {
      expect(qualityBoxArgs(true, v), {'resInd': true, 'resTag': true}, reason: '«$v»');
      expect(qualityBoxArgs(false, v), {'resInd': false, 'resTag': true}, reason: '«$v»');
    }
  });

  test('con «off» il riquadro non compare mai', () {
    expect(qualityBoxArgs(true, 'off')['resInd'], isFalse);
    expect(qualityBoxArgs(false, 'off')['resInd'], isFalse);
  });

  test('con «noq» il riquadro resta, senza la sigla di qualità', () {
    expect(qualityBoxArgs(true, 'noq'), {'resInd': true, 'resTag': false});
  });

  test('il permesso «resInd» bloccato nasconde sempre il riquadro', () {
    for (final v in [...likeToday, 'noq', 'off']) {
      expect(qualityBoxArgs(false, v)['resInd'], isFalse, reason: '«$v»');
    }
  });
}

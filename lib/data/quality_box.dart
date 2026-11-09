// Riquadro della qualità nel lettore («FHD · 1080p · 50 fps» in alto a destra sui canali in diretta): come lo vedono i
// clienti lo decide il pannello, per tutte le app Kairos insieme, con la voce rc «qbox» del controllo remoto.
// - «off»: il riquadro non compare mai (né all'apertura del canale, né al cambio di risoluzione, né con la barra
//   informazioni), come con il permesso «resInd» bloccato.
// - «noq»: il riquadro resta, senza la sigla di qualità (4K, UHD, FHD, HD, SD): «1080p · 50 fps».
// - «full», vuota, assente o qualsiasi altro valore: come sempre.
// Il permesso «resInd» bloccato lo nasconde comunque. Il riquadro lo disegna il lettore nativo (PlayerActivity.kt):
// qui si decide che cosa mostra. Logica pura, provata in test/quality_box_test.dart.

/// Come i clienti vedono il riquadro della qualità (voce rc «qbox» del pannello).
enum QualityBox {
  /// come sempre: «FHD · 1080p · 50 fps»
  full,

  /// senza la sigla di qualità: «1080p · 50 fps»
  noq,

  /// mai, come con il permesso «resInd» bloccato
  off;

  /// La voce così come arriva dal pannello: cambiano qualcosa solo «off» e «noq», il resto (null e vuoto compresi) è [full].
  static QualityBox of(Object? rcValue) => switch (rcValue?.toString()) {
        'off' => off,
        'noq' => noq,
        _ => full,
      };
}

/// Dati del riquadro per il lettore nativo, dal permesso «resInd» del cliente e dalla voce rc «qbox»:
/// `resInd` = il riquadro può comparire (permesso non bloccato e voce diversa da «off»),
/// `resTag` = con la sigla di qualità (voce diversa da «noq»).
Map<String, bool> qualityBoxArgs(bool resIndPerm, Object? rcValue) {
  final mode = QualityBox.of(rcValue);
  return {'resInd': resIndPerm && mode != QualityBox.off, 'resTag': mode != QualityBox.noq};
}

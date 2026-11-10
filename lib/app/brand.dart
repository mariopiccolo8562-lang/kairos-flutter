import 'package:flutter/painting.dart';

/// Identità del marchio Kairos Plus. Per una versione "white label" basta cambiare questo file
/// (e le icone in android/app/src/main/res e assets/brand).
abstract final class Brand {
  static const String appName = 'Kairos Plus';
  static const String shortName = 'Kairos';

  /// Indirizzo dei download (feed degli aggiornamenti e APK), il dominio dedicato ai download: l'unico da cambiare.
  /// L'app chiede `<dlBase>/get/plus.json` e, solo se non risponde bene, lo stesso file sulle riserve ([dlBase2] e i
  /// domini annunciati dal feed in «mirrors»); niente pannello né GitHub. L'APK si scarica dal campo `url` del feed che
  /// ha risposto e, se non riesce, dalle basi successive (vedi updateFeeds e apkUrls in app_updater.dart).
  static const String dlBase = 'https://store-k.download';

  /// Secondo dominio dei download, di riserva, con gli stessi percorsi: vuoto finché non se ne compra uno. Si imposta
  /// senza toccare il codice con la variabile KAIROS_DL_BASE2 del repository (il workflow la passa con --dart-define).
  /// Anche senza, le app già installate imparano le riserve dal feed («mirrors», dalla lista DL_HOSTS del pannello).
  static const String dlBase2 = String.fromEnvironment('KAIROS_DL_BASE2');

  /// Viola Kairos Plus (le altre app Kairos usano rosso, blu, arancio e ambra).
  static const Color accent = Color(0xFFA855F7);
  static const Color accentDeep = Color(0xFF7C3AED);
  static const Color background = Color(0xFF0B0812);
  static const Color surface = Color(0xFF16121F);
  static const Color card = Color(0xFF1D1828);
}

import 'package:flutter/painting.dart';

/// Identità del marchio Kairos Plus. Per una versione "white label" basta cambiare questo file
/// (e le icone in android/app/src/main/res e assets/brand).
abstract final class Brand {
  static const String appName = 'Kairos Plus';
  static const String shortName = 'Kairos';

  /// Indirizzo dei download (feed degli aggiornamenti e APK), il dominio dedicato ai download: l'unico da cambiare.
  /// L'app chiede `<dlBase>/get/plus.json`, poi panel-kairos.com, poi [updateFeedFallback]; l'APK si scarica dal campo
  /// `url` del feed che ha risposto e, se non riesce, dalle basi successive e da [apkFallback] (vedi updateFeeds e
  /// apkUrls in app_updater.dart).
  static const String dlBase = 'https://store-k.download';

  /// Riserva degli aggiornamenti, solo se dominio dei download e pannello non rispondono: feed della release più
  /// recente su GitHub (versione, numero e link dell'APK). Quando il repository diventerà privato fallirà senza danni.
  static const String updateFeedFallback =
      'https://github.com/mariopiccolo8562-lang/kairos-flutter/releases/latest/download/kairos-plus.json';

  /// Ultima riserva dell'APK, dopo le basi dei download: l'APK della release più recente su GitHub.
  static const String apkFallback =
      'https://github.com/mariopiccolo8562-lang/kairos-flutter/releases/latest/download/kairos-plus.apk';

  /// Viola Kairos Plus (le altre app Kairos usano rosso, blu, arancio e ambra).
  static const Color accent = Color(0xFFA855F7);
  static const Color accentDeep = Color(0xFF7C3AED);
  static const Color background = Color(0xFF0B0812);
  static const Color surface = Color(0xFF16121F);
  static const Color card = Color(0xFF1D1828);
}

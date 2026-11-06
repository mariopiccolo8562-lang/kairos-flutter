import 'package:flutter/painting.dart';

/// Identità del marchio Kairos Plus. Per una versione "white label" basta cambiare questo file
/// (e le icone in android/app/src/main/res e assets/brand).
abstract final class Brand {
  static const String appName = 'Kairos Plus';
  static const String shortName = 'Kairos';

  /// Feed della release più recente (versione, numero e link dell'APK): lo legge l'app per aggiornarsi
  /// e lo legge il pannello Kairos per sapere qual è l'ultima versione.
  static const String updateFeed = 'https://github.com/mariopiccolo8562-lang/kairos-flutter/releases/latest/download/kairos-plus.json';

  /// Viola Kairos Plus (le altre app Kairos usano rosso, blu, arancio e ambra).
  static const Color accent = Color(0xFFA855F7);
  static const Color accentDeep = Color(0xFF7C3AED);
  static const Color background = Color(0xFF0B0812);
  static const Color surface = Color(0xFF16121F);
  static const Color card = Color(0xFF1D1828);
}

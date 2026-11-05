import 'package:flutter/painting.dart';

/// Identità del marchio. Per una versione "white label" basta cambiare questo file.
abstract final class Brand {
  static const String appName = 'Kairos';
  static const String version = 'Anteprima 0.1';

  static const Color accent = Color(0xFF00B4FF);
  static const Color background = Color(0xFF0A0A0F);
  static const Color surface = Color(0xFF15151D);
  static const Color card = Color(0xFF1B1B24);
}

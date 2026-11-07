/// Scelte di grafica per le prestazioni, decise all'avvio in base alla memoria
/// del dispositivo e all'impostazione «Grafica leggera».
abstract final class Perf {
  /// Grafica leggera: niente sfondi grandi, sfumature, dissolvenze e animazioni
  /// di ingrandimento. Le chiavette con poca memoria la usano da sole.
  static bool lite = false;

  /// Dispositivo debole (classe D di Kairos Adaptive: ≤ 1,2 GB di RAM o Android < 7): immagini più
  /// piccole (sfondi al massimo 1280 px, locandine TMDB w185) e meno memoria per le immagini.
  static bool weak = false;

  /// Durata delle animazioni brevi (focus, scorrimento delle file).
  static Duration get quick => lite ? Duration.zero : const Duration(milliseconds: 140);

  /// Scorrimento delle file e della pagina.
  static Duration get scroll => Duration(milliseconds: lite ? 160 : 220);
}

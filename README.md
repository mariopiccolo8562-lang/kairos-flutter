# Kairos (Flutter) — anteprima

App streaming per **Fire TV con Fire OS** e **Android TV**, scritta in Flutter.

## Cosa c'è

- Accesso con **Xtream Codes**, **link M3U** oppure **demo** (contenuti di prova pubblici).
- Interfaccia per telecomando in stile Netflix: barra laterale, intestazione con
  immagine e trama, file di locandine che scorrono in modo morbido.
- **TV in diretta** con categorie, canali e guida TV (programma attuale e successivo).
- **Film e Serie TV** con schede, stagioni ed episodi, "Continua a guardare" e "La mia lista".
- **Player**: zapping con ▲▼, avanti/indietro con ◀▶, ripresa dal punto lasciato,
  episodio successivo automatico, riconnessione automatica se il flusso cade.

## Struttura

```
lib/
  app/      tema, marchio (brand.dart), avvio
  core/     rete, JSON, formattazione
  data/     modelli, sorgenti (Xtream, M3U, demo), cache del catalogo
  state/    AppController: stato dell'app
  ui/       schermate, player e componenti TV
```

## Compilare

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Ogni push su `main` compila l'APK con GitHub Actions: lo trovi nella scheda
**Actions**, nell'esecuzione più recente, alla voce *Artifacts*.

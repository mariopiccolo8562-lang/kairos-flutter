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

## Pubblicazione nel Kairos Store

Ogni push su `main` compila l'APK con GitHub Actions e lo pubblica nelle
release del repository pubblico **kairos-store** (il codice resta privato qui),
con un link fisso usato dallo store:

```
https://github.com/mariopiccolo8562-lang/kairos-store/releases/download/kairos-flutter/kairos-flutter.apk
```

- La release è una *pre-release* e non diventa mai "l'ultima" di kairos-store,
  perché l'app Kairos Store usa l'ultima release per aggiornare sé stessa.
- Serve il segreto **`STORE_TOKEN`** in questo repository: un token GitHub
  *fine-grained* con accesso **solo a kairos-store**, permesso *Contents: Read and write*.
- La versione è `0.1.N`, con N che cresce a ogni compilazione.

## Firma

L'APK è firmato con la chiave di **anteprima** `android/keys/preview.jks`, sempre la
stessa, così gli aggiornamenti si installano sopra la versione precedente.
Prima della distribuzione ai clienti va sostituita con una chiave definitiva
custodita nei segreti di GitHub (non nel repository).

# Kairos Plus

App streaming stile Netflix per **Fire TV (Fire OS)**, Android TV e telefoni Android, collegata al **pannello Kairos** come le altre app Kairos (Kairos Pro, Kairos TV, Kairos Lite, Kairos XC). Si installa accanto a loro (pacchetto `com.kairos.plus`).

## Attivazione (come le altre app Kairos)

1. Al primo avvio la TV mostra il suo **codice di attivazione** (`KX12-AB34`).
2. Il fornitore lo attiva dal pannello e assegna le playlist (Xtream o M3U): l'app si sblocca da sola (controlla ogni 12 secondi).
3. In alternativa: **Collega con codice a 6 cifre**, generato da un'altra TV già attiva (Impostazioni → «Collega un'altra TV»).

Dal pannello funzionano: attivazione e scadenza, playlist (anche più di una, con scelta in Impostazioni), cambio DNS, manutenzione, **Disconnetti**, limite di visioni contemporanee, permessi (anche «modalità leggera» e «risoluzione e FPS» nel lettore), messaggi, collegamento di altre TV, Home configurabile (categorie in primo piano e nascoste). In *Utenti online* la versione compare come `plus 0.1.N`; quando l'app va in sfondo o si chiude il pannello la vede subito non in linea.

## Adulti fuori dalla Home

Regola comune a tutte le app Kairos (Controllo remoto, chiave `adult`):

- `adult` diverso da `"on"` (anche assente o vuoto, quindi di base): nella Home **nessuna riga e nessun elemento per adulti**: categorie in primo piano e solite righe, titolo in evidenza (se i recenti erano tutti per adulti si prende il primo titolo delle righe della Home), Continua a guardare, La mia lista, I tuoi canali, aggiunti di recente. Una riga che resta vuota non si mostra.
- Un elemento è per adulti se la sua categoria è per adulti o è nascosta da `home.hide`, oppure se il nome è un titolo per adulti (solo parole forti: «Sex Education» resta). Il riconoscimento (`adultCat`, `adultTitle` in `lib/data/home_rules.dart`) è quello del contratto comune, provato con i suoi 94 esempi (`test/adult_vectors.json`).
- Negli elenchi (Film, Serie TV, TV in diretta) le categorie per adulti vanno in fondo, come quelle di `home.hide`, e restano raggiungibili; ricerca, guida, zapping e PIN del controllo genitori non cambiano.
- `adult` = `"on"`: tutto come prima, vale solo `home.hide`.

## Cosa c'è

- Home stile Netflix: «Continua a guardare», La mia lista, novità, categorie.
- TV in diretta a tre colonne (categorie · canali · scheda con guida adesso/dopo).
- Film e serie con stagioni ed episodi, posizione di visione salvata, episodio successivo automatico.
- Ricerca istantanea, preferiti.
- **Lettore nativo** (Media3/ExoPlayer su SurfaceView, stessa configurazione di Kairos Lite e Kairos TV): video fluido anche sulle Fire TV Stick, riconnessione automatica, cambio canale con ▲▼ e con i numeri, guida in sovrimpressione.
- **Modalità leggera** automatica sulle chiavette con meno di ~1,8 GB di RAM (niente sfondi grandi, meno memoria per le immagini).

## Struttura

```
lib/app/            avvio, tema, marchio (nome, colori)
lib/panel/          pannello Kairos: codice TV, attivazione, battito, collegamento
lib/state/          stato dell'app (attivazione, catalogo, preferiti, progressi, battito)
lib/data/           modelli, sorgenti Xtream/M3U, cache del catalogo
lib/ui/             schermate e componenti per il telecomando
android/app/src/main/kotlin/com/kairos/plus/   lettore nativo (PlayerActivity) e ponte con Flutter
.github/workflows/android.yml                  compilazione e pubblicazione dell'APK
```

## Pubblicazione

Ogni modifica su `main` compila l'APK e pubblica la release `v0.1.N` con:

- `kairos-plus.apk` — link fisso per il Kairos Store:
  `https://github.com/mariopiccolo8562-lang/kairos-flutter/releases/latest/download/kairos-plus.apk`
- `kairos-plus.json` — versione per il pannello.

L'app chiede gli aggiornamenti al pannello, `https://panel-kairos.com/get/plus.json` (indirizzo dei download `Brand.dlBase` in `lib/app/brand.dart`), e scarica l'APK dal link che c'è dentro; solo se il pannello non risponde legge `kairos-plus.json` dell'ultima release (riserva finché il repository è pubblico).

### Firma

Senza segreti l'APK è firmato con la chiave **di anteprima** del repository (pubblica). Per la distribuzione ai clienti crea in *Settings → Secrets and variables → Actions* i segreti `ANDROID_KEYSTORE_B64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` (anche gli stessi di Kairos Lite / Kairos TV). Cambiare chiave richiede di disinstallare e reinstallare l'app una volta: va fatto prima di darla ai clienti.

L'app è solo un lettore e non contiene canali: i contenuti arrivano dalle playlist assegnate dal pannello.

# Diario Sonoro (iOS)

Tieni premuto un pulsante e registri 10 secondi del suono intorno a te. Ogni
sera le clip della giornata diventano una **colonna sonora**. Dopo un anno puoi
riascoltare com'era un giorno qualsiasi: il bosco, la strada, la cucina.

App iOS nativa (Swift + SwiftUI, grafica Material 3 sobria con un solo colore
d'accento, tema chiaro e scuro). Tutto resta sul telefono: nessun server,
nessun account.

Sviluppata senza Mac: compilata e firmata da GitHub Actions, arriva sull'iPhone
con **TestFlight**.

## Cosa c'è

- **Registra**: grande pulsante centrale, tieni premuto e registra N secondi
  (5–30, default 10) con anello di progresso, conto alla rovescia e vibrazione
  a inizio e fine. Se rilasci prima salva quello che c'è (minimo 2 secondi).
  Audio AAC mono, qualità Compatta / Standard / Alta (~40 / 80 / 160 KB per
  10 s).
- **Ogni clip** salva data e ora, posizione (una sola richiesta "Durante
  l'uso" al momento della registrazione, nessun tracciamento), nome del luogo,
  meteo facoltativo, nota ed emoji, preferito, forma d'onda.
- **Calendario** mensile: ogni giorno è colorato in base a quante clip ha,
  il puntino indica la colonna sonora. Tocca un giorno: timeline delle clip con
  ora e luogo, riascolto una per una o tutte di fila.
- **Colonna sonora del giorno**: all'orario scelto (default 21:30) le clip
  vengono unite in ordine cronologico con dissolvenze incrociate. Un tocco per
  ascoltarla, condividerla o esportarla. Notifica facoltativa "La colonna
  sonora di oggi è pronta". Nei giorni senza clip non succede nulla.
- **Promemoria** facoltativo: ogni giorno, in un momento a caso della fascia
  oraria che scegli (es. 10:00–20:00), la notifica "È ora della tua
  registrazione audio" apre l'app pronta a registrare. Si può saltare nei
  giorni in cui hai già registrato.
- **Un anno fa oggi** (e 2, 3… anni fa): schermata e notifica facoltativa.
- **Mappa**: tutti i luoghi in cui hai registrato, pin raggruppati per zona;
  tocca un pin per ascoltare le clip di quel posto. Filtri per anno, stagione,
  momento della giornata e preferiti.
- **Cerca**: per nota, luogo, emoji, mese; periodo, luogo, preferiti.
- **Player**: mini player con forma d'onda, velocità 0,75×–2×, riproduzione in
  background e controlli dalla schermata di blocco.
- **Statistiche**: giorni registrati, clip, minuti, serie di giorni
  consecutivi, luoghi più registrati, orari tipici, giorni della settimana,
  ultimi 12 mesi, spazio occupato.
- **Avvio rapido**: widget per schermata di blocco e Home, controllo per
  Centro di Controllo e tasto Azione, comando Siri "Registra con Diario
  Sonoro". Aprono l'app già pronta a registrare (opzione "Avvio rapido
  registra subito": parte da sola, tocchi per fermare).
- **Impostazioni**: durata, qualità, luogo e meteo, orario della colonna
  sonora e dissolvenza, notifiche, tema, Face ID per aprire l'app, backup
  iCloud, export ZIP (audio e dati) e CSV, eliminazione delle clip.
- **Backup iCloud** automatico: in File, *iCloud Drive › Backup ›
  DiarioSonoro*, un JSON al giorno (ultimi 30) con clip, giornate, note e
  impostazioni. Parte dopo ogni modifica, quando chiudi l'app e in
  background. L'audio delle clip entra nel backup solo se lo attivi
  (Impostazioni › Backup iCloud, spento di default: sono registrazioni
  personali e pesano). Ripristino da Impostazioni, e proposto da solo al
  primo avvio se l'app è vuota e su iCloud c'è un backup.

### Limiti da sapere

- **Meteo**: per ora spento. Per attivarlo basta spuntare WeatherKit sull'App
  ID (incluso nell'account sviluppatore, 500.000 richieste al mese gratis)
  e aggiungere l'entitlement: senza, la clip si salva senza meteo.
- **Colonna sonora "ogni sera"**: iOS non permette di eseguire codice a
  un'ora precisa. L'app la crea appena la apri dopo l'orario scelto, quando
  tocchi la notifica, quando registri dopo l'orario e, quando iOS lo concede,
  in background. La notifica è programmata solo nei giorni con clip.
- **Cosa esce dal telefono**: il nome del luogo (Apple Mappe, solo con la
  posizione della clip) e il backup nel *tuo* iCloud Drive. Nessun server,
  nessun account, nessun token.

## Installare l'app sull'iPhone

L'app arriva con **TestFlight**: apri l'app TestFlight sull'iPhone e installa
**Diario Sonoro**. Ogni push con modifiche all'app carica una nuova build
(workflow **testflight**); le build TestFlight scadono dopo 90 giorni e la CI
ne carica una nuova da sola ogni ~60 giorni.

Al primo avvio tieni premuto il pulsante: iOS chiede il microfono. Dopo la
prima clip chiede la posizione "Durante l'uso". Se l'app è vuota e su iCloud
c'è un backup, propone di ripristinarlo.

Ripiego senza TestFlight: workflow **build-ipa** › artifact
`DiarioSonoro-unsigned-ipa`, da firmare con Sideloadly (in questo caso niente
backup iCloud, che richiede l'account sviluppatore).

### Configurazione una tantum (già fatta)

- developer.apple.com: App Group `group.com.garoth93.diariosonoro`; App ID
  `com.garoth93.diariosonoro` con App Groups + iCloud (container
  `iCloud.com.garoth93.backup`); App ID `com.garoth93.diariosonoro.widgets`
  solo con App Groups.
- App Store Connect: scheda app con ID pacchetto `com.garoth93.diariosonoro`,
  gruppi TestFlight interni ed esterni.
- Secrets della repo: `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`,
  `ASC_KEY_P8`.

## Screenshot

Il workflow **build-simulator** avvia l'app sul simulatore con un diario
sintetico (3 anni di clip inventate) e salva uno screenshot di ogni schermata,
chiaro e scuro, nell'artifact `screenshots-DiarioSonoro` e sul branch
`ci-screenshots` (aprilo su GitHub per vederli tutti nel README).

## Struttura

```
apps/DiarioSonoro/       app SwiftUI (project.yml per XcodeGen)
  Sources/               schermate, modello, servizi audio/posizione/meteo
  Shared/                codice comune app + widget (tema, intent, viste widget)
  Widgets/               estensione WidgetKit (widget e controllo)
  screenshots.txt        schermate fotografate in CI
packages/SonoroCore/     logica non grafica, testata con `swift test` anche su Linux
.github/workflows/       testflight, build-simulator (+ screenshot), build-ipa (ripiego), test-linux
scripts/                 asc_*.py: diagnostica App ID e revoca certificati (usati da testflight)
CLAUDE.md                convenzioni e regole di lavoro per Claude Code
```

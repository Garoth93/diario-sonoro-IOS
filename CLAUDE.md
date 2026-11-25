# CLAUDE.md — regole di lavoro per questa repo

Repo di app iOS **native (Swift + SwiftUI)** personali, sviluppate senza Mac:
il codice viene scritto su Linux (Claude Code) e compilato **solo** su GitHub
Actions con runner macOS. Non va su App Store: l'app arriva sull'iPhone con
**TestFlight** (account Apple a pagamento, firma automatica in CI,
`testflight.yml`); il `.ipa` non firmato per Sideloadly (`build-ipa.yml`)
resta come ripiego.

Stessa impostazione delle repo `Garoth93/tessere-IOS` e `Garoth93/montagna-360`
(TestFlight e backup iCloud: procedure riusabili descritte nel CLAUDE.md di
tessere), `Garoth93/home-alarm-IOS`, `Garoth93/LTIDI-Last-Time-I-Did-It-IOS`,
`Garoth93/ritorni-IOS` (mappa).

## Vincoli fissi

- Nativo vero: Swift/SwiftUI. Niente WebView, niente framework cross-platform,
  salvo richiesta esplicita dell'utente.
- Nessun `.xcodeproj` committato: il progetto è generato in CI da
  `apps/<app>/project.yml` con XcodeGen. `.gitignore` lo esclude.
- Mai committare segreti, chiavi API, certificati, profili di provisioning,
  Team ID reali, **audio o dati reali** (`.gitignore` esclude `*.m4a`, `*.zip`,
  `diary.json`). Test e screenshot usano solo dati sintetici (`DemoData`).
- Firma solo in `testflight.yml` (automatica, chiave API App Store Connect).
  Mai certificati, profili o `.p8` nella repo; Team ID solo nei secrets.
  `build-ipa.yml` e `build-simulator.yml` compilano senza firma.
- Dati locali; iCloud solo come **backup in iCloud Drive** (niente CloudKit),
  vedi sotto. Nell'app non esistono token né dati sensibili da salvare.
- Non modificare impostazioni della repo o secrets: spiegare all'utente cosa
  configurare.

## Struttura repo

```
apps/<NomeApp>/            un'app per cartella
  project.yml              spec XcodeGen (target, bundle id, deployment target)
  Sources/                 codice SwiftUI dell'app (solo strato UI + glue)
  Resources/               Assets.xcassets e altre risorse
  Shared/                  codice comune app + widget (se c'è un'estensione)
  Widgets/                 estensione WidgetKit (se presente)
  *.entitlements           entitlements (App Group) usati per la firma ad-hoc in CI
  Info.plist               GENERATO da XcodeGen (git-ignored)
packages/<NomePackage>/    Swift Package con la logica NON grafica
  Package.swift            tools-version 5.9, nessuna dipendenza da UIKit/SwiftUI
  Sources/<NomePackage>/   modelli, regole, persistenza (Foundation only)
  Tests/<NomePackage>Tests/ XCTest, eseguiti anche su Linux
.github/workflows/         CI (vedi sotto)
.github/actions/setup-xcode/ composite action: seleziona Xcode, installa XcodeGen, genera il progetto
```

App presenti:

| App          | Package logica | Bundle ID                                    | Deployment target |
|--------------|----------------|----------------------------------------------|-------------------|
| DiarioSonoro | SonoroCore     | `com.garoth93.diariosonoro` (+ `.widgets`)   | iOS 26.0 |

App Group `group.com.garoth93.diariosonoro` (app + widget), container iCloud
`iCloud.com.garoth93.backup` (solo app). Entrambi creati e spuntati a mano su
developer.apple.com (App ID app: App Groups + iCloud; App ID widget: solo App
Groups; WeatherKit **spento**).

### Diario Sonoro

Tieni premuto il grande pulsante: registra N secondi (default 10, 5–30) di
suono ambiente, AAC mono. Ogni sera le clip del giorno diventano una
"colonna sonora" con dissolvenze incrociate. Calendario, "un anno fa oggi",
mappa, ricerca, statistiche. Tutto locale: nessun server né account.

Logica nel package `SonoroCore` (Foundation only, testata su Linux con dati
sintetici, `Tests/SonoroCoreTests`):

- `Models`: `Clip` (giorno locale `DayDate` e minuto salvati alla
  registrazione, file relativo, posizione, luogo, meteo, nota, emoji,
  preferito, waveform 48 byte), `DailySoundtrack` (clipIDs usati: se
  cambiano si ricrea), `DiarySettings` (decodifica tollerante), `DiaryData`.
- `FileNaming`: `clips/AAAA/MM/AAAAMMGG-hhmmss-<id8>.m4a`,
  `soundtracks/AAAA/AAAA-MM-GG.m4a`, nomi di export, controllo path sicuri.
- `Calendar`: `DayGrouping`/`DaySummary`, `MonthGrid` (lunedì primo,
  `IntensityScale` 0…4 configurabile), `MonthRange`.
- `Soundtrack`: `SoundtrackPlan` (timeline con crossfade ≤ metà della clip
  più corta, due tracce alternate, fade ai bordi), `SoundtrackScheduler`
  (giorni da creare/ricreare, orfani, prossima esecuzione),
  `SoundtrackBuilder` + protocollo `AudioMerging`.
- `Capture`: `RecordingRules` (minimo 2 s, autostop), protocolli
  `AudioRecording`, `LocationProviding`, `WeatherProviding`;
  `CaptureController` (begin → finish → enrich: una sola richiesta di
  posizione, permesso chiesto dopo la prima registrazione).
- `Anniversary` (1…10 anni, 29 febbraio), `DiaryStats` (serie, luoghi,
  orari, mesi, spazio), `ClipFilter`/`SearchText` (senza accenti),
  `MapFilter`/`Season`/`TimeOfDay`, `PlaceSpots` (clip entro 150 m) e
  `MapClusterer` (cluster in base allo zoom), `Waveform`, `ItalianFormat`.
- `MiniZip` (ZIP STORE + CRC32, niente ZIP64) e `BackupArchive`
  (`diario.json` + audio, ripristino via cartella di staging), `CSVExport`.
- `DeepLink` (`diariosonoro://record?source=…`, `day/…`, `soundtrack/…`,
  `anniversary`), `WidgetSnapshot`, `NotificationPlanner` (colonna sonora,
  un anno fa, promemoria "È ora della tua registrazione audio" in un minuto
  pseudo-casuale ma stabile per giorno dentro la fascia scelta, anche oltre la
  mezzanotte, saltato se oggi c'è già una clip), `CloudBackup`
  (`CloudBackupFile` JSON versionato + `CloudBackupPlan`, vedi sotto), `DemoData`
  (diario sintetico deterministico di 3 anni).

App (`apps/DiarioSonoro`):

- Implementazioni reali dei protocolli: `AVRecorderService` (AVAudioRecorder
  con metering), `AVMergeService` (AVMutableComposition + volume ramp,
  export M4A), `LocationService` (CLLocationManager `requestLocation`,
  CLGeocoder: deprecato in iOS 26, solo warning), `WeatherKitProvider`
  (richiede la capability WeatherKit sull'App ID + entitlement
  `com.apple.developer.weatherkit`: oggi spenti per scelta dell'utente, la
  richiesta fallisce e la clip si salva senza meteo).
- `AppModel` (@Observable, @MainActor): dati in
  `Application Support/DiarioSonoro/diary.json` + audio, salvataggio
  differito; widget, notifiche e task in background aggiornati a ogni modifica.
- Colonna sonora: creata quando l'app si apre dopo l'orario scelto, quando si
  registra dopo l'orario, dal tocco sulla notifica e (best effort) da un
  `BGAppRefreshTask`. Notifica serale programmata solo se oggi ci sono clip.
- `PlayerModel`: AVAudioPlayer, coda, velocità, background audio,
  `MPNowPlayingInfoCenter` + comandi remoti.
- Widget (target `DiarioSonoroWidgets`): `TodayWidget` (Home small/medium,
  schermata di blocco circolare/rettangolare/inline) con `widgetURL`
  `diariosonoro://record`, controllo `RecordControl` (Centro di Controllo e
  tasto Azione). App Shortcuts Siri in `DiarioShortcuts`. Gli intent in
  `Shared/Intents.swift` (compilati in entrambi i target, `WIDGET_EXTENSION`
  nel widget) lasciano un link "pendente" nell'App Group
  `group.com.garoth93.diariosonoro`, letto quando l'app torna attiva.
- Modalità demo per gli screenshot: argomenti `-demo -screen <nome>` (vedi
  `apps/DiarioSonoro/screenshots.txt`). Usa `DemoData` in una cartella
  separata, non tocca dati reali, non chiede permessi, playback simulato.

### Backup iCloud Drive

Stessa procedura di `Garoth93/tessere-IOS`: container **condiviso**
`iCloud.com.garoth93.backup`, sottocartella `DiarioSonoro` (in File: *iCloud
Drive › Backup › DiarioSonoro*).

- `DiarioSonoro.entitlements` (App Group + container + `CloudDocuments`), usato
  da `testflight.yml`; `DiarioSonoro.sideload.entitlements` solo App Group,
  preferito da `build-ipa.yml` (l'account gratuito non ha iCloud);
  `Widgets.entitlements` solo App Group (mai iCloud nel widget). `project.yml`:
  `SystemCapabilities` `com.apple.iCloud`, `NSUbiquitousContainers` con
  `NSUbiquitousContainerName: Backup`.
- File: `DiarioSonoro-backup-yyyy-MM-dd.json` (uno al giorno, ultimi 30) +
  `DiarioSonoro-backup-latest.json`: `CloudBackupFile` con `version`, `app`,
  `includesAudio`, `days` (riepilogo leggibile delle giornate) e `data`
  (clip + impostazioni; colonne sonore escluse, si ricreano). Audio delle clip
  in `audio/<nome file>.m4a` **solo** con `settings.cloudBackupAudio` (default
  spento), caricato una volta sola. Logica pura in `CloudBackup.swift`
  (package, testata), I/O in `CloudBackupService.swift` (`NSFileCoordinator`,
  container risolto fuori dal main thread, segnaposto `.<nome>.icloud`).
- Quando: dopo le modifiche (8 s), all'uscita in background, nel
  `BGAppRefreshTask` (`com.garoth93.diariosonoro.soundtrack`, ogni ~6 h e la
  sera). Impronta del contenuto: nessuna riscrittura se nulla è cambiato. Un
  diario vuoto non sovrascrive mai i backup. Mai in modalità demo.
- Ripristino: Impostazioni › Ripristina da iCloud (anteprima + conferma) e
  guidato al primo avvio se il diario è vuoto (chiesto una volta). I file audio
  non presenti nel backup vengono rimossi; le giornate senza audio sul
  telefono non provano a ricreare la colonna sonora.

Per aggiungere un'app: creare `apps/<Nome>/project.yml` + `Sources/` +
`Resources/`; i workflow scoprono automaticamente le cartelle in `apps/`
e i `Package.swift` in `packages/`. Il nome della cartella deve coincidere
con `name`, target e scheme nel `project.yml`.

## Convenzioni di codice

- Swift 5 language mode (`SWIFT_VERSION: 5.0` nel project.yml), tools-version
  5.9 nei package, in modo che Linux (`swift:6.0`) e Xcode 26 compilino lo
  stesso codice. Il package dichiara `.iOS(.v17)` come minimo: è solo il suo
  minimo, l'app può avere un target più alto.
- Logica, modelli e persistenza nel package: tipi `struct` value-type,
  `Codable`, `Equatable`, `Sendable`, senza `import SwiftUI`/`UIKit`.
  Tutto ciò che è testabile va lì e ha un test.
- Nell'app: `@Observable` (framework Observation) + `@MainActor`, iniettato
  con `.environment(...)` e letto con `@Environment(Tipo.self)`; viste piccole,
  una per file; stringhe UI in italiano. Target iOS 26.0: si possono usare
  SwiftData, Liquid Glass e le API SwiftUI di iOS 26 senza `#available`.
- Persistenza: JSON in Application Support tramite `JSONFileStore` (o
  SwiftData/UserDefaults quando serve, decidere caso per caso e documentarlo).
- Nessuna dipendenza esterna salvo necessità motivata; se serve, dichiararla
  nel `Package.swift` o in `project.yml > packages`, mai vendorizzare binari.
- Commit piccoli e descrittivi, in italiano o inglese ma coerenti; un commit
  per argomento. Niente identificatori di modello AI nei commit.

## Xcode e runner

- Runner: `macos-26`. Xcode fissato con `XCODE_VERSION: "26.6"` (SDK iOS 26.5) (env in ogni
  workflow) e selezionato con `xcode-select`. Se GitHub ritira la versione,
  la composite action fallisce elencando le Xcode disponibili: aggiornare il
  valore in tutti i workflow e qui.
- Toolchain Linux per i test: immagine Docker `swift:6.0-noble`.
- XcodeGen e xcbeautify installati con Homebrew a ogni run.

## CI (GitHub Actions)

| Workflow | Trigger | Cosa fa |
|----------|---------|---------|
| `build-simulator.yml` | push su ogni branch, PR, manuale | `xcodebuild build` per iOS Simulator, senza firma; poi avvia l'app su un simulatore con dati sintetici e salva uno screenshot di ogni schermata (chiaro e scuro) nell'artifact `screenshots-<App>`. Le schermate sono elencate in `apps/<App>/screenshots.txt` (`nome attesa_secondi`). Sui push le stesse immagini (ridotte) vengono anche pubblicate con force-push sul branch `ci-screenshots`: per guardarle `git fetch origin ci-screenshots && git archive FETCH_HEAD \| tar -x -C <cartella>`. |
| `build-ipa.yml` | push su `main` e `claude/**`, manuale | ripiego Sideloadly: build Release per dispositivo con `CODE_SIGNING_ALLOWED=NO`, firma ad-hoc con `<App>.sideload.entitlements` (senza iCloud) e gli `.entitlements` del widget, impacchetta `Payload/<App>.app` in `<App>-unsigned.ipa` e lo carica come artifact (30 giorni). |
| `testflight.yml` | manuale, push su `main`/`claude/**` (solo `apps/`, `packages/`, il workflow), ogni ~60 giorni (1° dei mesi dispari, sul branch di default) | archive firmato + export App Store + upload su TestFlight (vedi sotto). |
| `test-linux.yml` | push su ogni branch, PR, manuale | `swift test` su ogni package in `packages/`. |

Nota: nei repo pubblici i workflow con `schedule` vengono disattivati dopo 60
giorni senza commit: se succede, riattivare `testflight` dalla pagina Actions o
lanciarlo a mano (`workflow_dispatch`). La schedulazione gira sul branch di
default della repo.

### TestFlight

Procedura identica a `Garoth93/tessere-IOS` (vedi il suo CLAUDE.md):

- secrets della repo: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (chiave API
  App Store Connect, ruolo Admin), `APPLE_TEAM_ID`;
- App ID `com.garoth93.diariosonoro` (+ `.widgets`) e scheda App Store Connect
  creati a mano; i profili li crea `xcodebuild -allowProvisioningUpdates`.
  App Group e container iCloud vanno spuntati a mano sull'App ID (l'API non può);
- `project.yml` con firma vuota (la imposta il workflow da riga di comando),
  `SystemCapabilities` sul target, `UIRequiresFullScreen: true` (solo
  verticale, errore 90474), icona 1024 senza trasparenza,
  `ITSAppUsesNonExemptEncryption: false`;
- build number = `github.run_number`; `MARKETING_VERSION` si alza a mano;
- step "App ID capabilities" (`scripts/asc_bundle_ids.py --delete-stale
  --group group.com.garoth93.diariosonoro`) stampa capability e profili di app
  e widget ed elimina i profili senza l'App Group (Xcode li ricrea); il
  certificato di sviluppo creato sul runner viene revocato
  (`scripts/asc_revoke_certs.py`). Log nell'artifact `testflight-logs`;
- le build TestFlight scadono dopo 90 giorni: la schedulazione le rinnova.

### Come leggere i log di CI

Con `gh` (se il token è valido):

```bash
gh run list --limit 10
gh run view <run-id> --log-failed
gh run watch <run-id>
gh run download <run-id> -n testflight-logs
gh run download <run-id> -n DiarioSonoro-unsigned-ipa
gh run download <run-id> -n screenshots-DiarioSonoro
```

Con gli strumenti GitHub MCP disponibili a Claude Code (quando `gh` non è
autenticato): `actions_list` con `list_workflow_runs` per trovare il run,
`list_workflow_jobs` per i job, `get_job_logs` con `failed_only=true` e
`return_content=true` per i log dei job falliti. I log raw di `xcodebuild`
sono anche caricati come artifact `xcodebuild-*-log-<App>`.

Gli errori Swift compaiono come annotazioni `::error file=...` grazie a
`xcbeautify --renderer github-actions`.

## Regole di lavoro (per Claude)

1. Dopo **ogni push** controllare l'esito della CI e correggere da soli gli
   errori di compilazione fino a build verde. Mai dichiarare "funziona" se la
   CI non è verde: riportare l'esito reale con il link al run.
2. L'interfaccia si vede solo dagli screenshot della CI (artifact
   `screenshots-DiarioSonoro`): dopo modifiche grafiche guardarli e
   rifinire prima di consegnare; dire all'utente cosa verificare sul telefono.
3. Commit piccoli e descrittivi. Mai segreti. Mai toccare impostazioni repo o
   secrets: indicare all'utente cosa configurare.
4. I test del package si possono eseguire in locale con Docker:
   `docker run --rm -v "$PWD":/src -w /src swift:6.0-noble swift test --package-path packages/SonoroCore`
   (se Docker Hub risponde 429, `docker pull mirror.gcr.io/library/swift:6.0-noble`
   e `docker tag` come `swift:6.0-noble`)
   (avviare `dockerd` se non è attivo). L'app SwiftUI si compila solo in CI.

# vodovod_bd_flutter

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Android updates

The user menu beside the collector's name opens the update screen. Startup
also checks `AppConfig.versionUrl`. The existing JSON format is supported;
`versionName` is optional. Example for a future release:

```json
{
  "versionCode": 101,
  "versionName": "1.9.11",
  "apkUrl": "https://your-server.example/releases/vob-101.apk"
}
```

Publish the signed APK first, then update the JSON. `versionCode` must match
the APK and be greater than the installed build number. Keep the same
application ID and signing key. The project currently uses the debug keystore
for release signing; a different keystore will not update existing installations.

Android downloads into the private update cache, validates package/version/signer,
and opens the system installer. Android may first request permission to install
from this app. Installation still requires user confirmation. Cancelling the
installer keeps the completed APK for another attempt. Incomplete downloads are
discarded and retried from the beginning. No reading database is cleared.
This feature takes effect after users install the first APK containing it.

## Local diagnostics

The user menu and login screen open the diagnostics viewer. Errors include
timestamp, app version, collector ID when logged in, and stack trace. It also
records sync and save events. Records stay in application support storage across
restarts and upgrades, with two rotating files of approximately 512 KiB each.
Known credential fields are redacted; no credentials are deliberately logged.
Flutter framework and uncaught Dart errors, handled login/sync/save/photo/update
failures, location failures and failed note/image retrieval are captured. Repeated
image rebuilds report a failed image once per session; an offline spell records
the first failed connectivity check, not a new error every polling tick. Routine
`info` events remain local; `error` and native `fatal` reports are uploaded.

## Online diagnostics

This feature requires the updated backend and `app_errors` from SQL block 001.
See `../backend/VodovodbBDBackAndroid/DIJAGNOSTIKA.md` for server setup and SQL
queries. No extra database migration is required. Configure the same random key
(at least 32 characters) in the server's `AppDiagnostics__IngestKey` environment
variable and the APK's `DIAGNOSTICS_UPLOAD_KEY` build define. Do not commit keys.

Android builds now load `android/diagnostics.properties` automatically (ignored
by Git). Set `uploadKey` to the server's key and optionally `baseUrl` to its
diagnostics HTTPS URL. The key is also accepted through `VOB_DIAGNOSTICS_KEY` or
an explicit dart-define. Every Android build requires a key of at least 32
characters, so a release cannot silently disable online logging. Keep this file
for subsequent releases and provision the same key on any new build machine.

```sh
flutter build apk --release \
  --dart-define=DIAGNOSTICS_UPLOAD_KEY="$VOB_DIAGNOSTICS_KEY" \
  --dart-define=DIAGNOSTICS_BASE_URL=https://your-api.example
```

The diagnostics base URL defaults to `API_BASE_URL`. Use HTTPS in production:
the existing HTTP base URL does not encrypt errors or the ingestion key. This
shared APK key grants write-only ingestion, not read access or strong per-user
authentication; it can be extracted from an APK. Without a configured key, errors
still persist locally and the diagnostics screen shows that upload is disabled.

Each error is first flushed to a separate durable outbox in app support storage.
Only explicit server acknowledgements remove it from that outbox; the local
viewer retains its copy until rotation. Stable UUID event IDs make a retry after
a lost response idempotent. Old errors still present in the rotating log are
imported once. Neither logout nor the monthly reading import clears this queue.
The queue is not a temp/cache folder, and pending errors are not rotated away.

Delivery runs independently from readings: shortly after an error, on startup,
resume, Android network availability (API 24+), and every 30 seconds while the
process runs. Failures use backoff from 1 to 20 minutes; resume/network/manual
retry can bypass it. Each run sends at most 3 batches of up to 20 events, with
bounded payloads and a 12-second request timeout. The UI never waits for delivery
to save a reading or photo. The diagnostics screen shows pending count, last
successful delivery, failures, and a manual retry button. Delivery failures do
not recursively add more delivery errors. There is no OS background worker:
after process termination delivery resumes on the next launch.

Android Java/Kotlin uncaught exceptions are flushed by a native crash handler;
the OS's original crash handler is still invoked. At next launch, Android 11+
also supplies available ANR/native-crash exit reports (up to its retained history).
System reports may have no trace or trustworthy past user/version, so these are
marked unknown rather than attributed to whoever logs in next. A Java crash can
have both a detailed app report and a separate OS exit report. This is not a
guarantee of every crash: power loss, full storage, uninstall/clear data, unavailable
OS history, ANRs on older Android, and native iOS crashes are not fully covered.
No photos, request bodies or credentials are intentionally sent; known secret
fields and JSON payloads are scrubbed and messages/stacks are bounded. Keep access
to the server log table restricted and define operational retention/backups.

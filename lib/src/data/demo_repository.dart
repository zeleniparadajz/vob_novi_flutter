import 'dart:convert';
import 'dart:io';
import 'dart:async';

import '../core/app_config.dart';
import '../core/app_logger.dart';
import 'local_store.dart';
import '../models/vodovod_models.dart';

class SavedLoginCredentials {
  const SavedLoginCredentials({required this.username, required this.password});

  final String username;
  final String password;
}

class SyncRunResult {
  const SyncRunResult({
    required this.readings,
    required this.notes,
    required this.hadNetwork,
  });

  final int readings;
  final int notes;
  final bool hadNetwork;
}

class DemoVodovodRepository {
  DemoVodovodRepository({HttpClient? httpClient, LocalVodovodStore? store})
    : _httpClient = httpClient ?? HttpClient(),
      _store = store ?? LocalVodovodStore();

  static const _connectTimeout = Duration(seconds: 8);
  static const _readTimeout = Duration(seconds: 20);
  static const _uploadTimeout = Duration(seconds: 45);
  static const _serverRefreshInterval = Duration(minutes: 20);

  final HttpClient _httpClient;
  final LocalVodovodStore _store;
  Timer? _syncTimer;
  Future<SyncRunResult>? _activeSyncRun;
  Future<int>? _activeReadingsSync;
  Future<int>? _activeNotesSync;
  List<InkasantiModel> _inkasanti = [];
  List<OcitavanjeModel> _ocitavanja = [];
  List<StanjeBrojilaModel> _stanjaBrojila = [];
  final List<NapomenaDraft> _napomene = [];
  OcitavanjeGlavnoModel? _aktivnoOcitavanje;
  InkasantiModel? _currentUser;
  DateTime? _lastSuccessfulSyncAt;
  DateTime? _lastNetworkFailureAt;
  DateTime? _lastServerRefreshAt;
  int _lastReadingsSyncCandidates = 0;
  String? _lastReadingsSyncError;
  int _lastNotesSyncCandidates = 0;
  String? _lastNotesSyncError;

  OcitavanjeGlavnoModel? get aktivnoOcitavanje => _aktivnoOcitavanje;
  DateTime? get lastSuccessfulSyncAt => _lastSuccessfulSyncAt;
  int get lastReadingsSyncCandidates => _lastReadingsSyncCandidates;
  String? get lastReadingsSyncError => _lastReadingsSyncError;
  int get lastNotesSyncCandidates => _lastNotesSyncCandidates;
  String? get lastNotesSyncError => _lastNotesSyncError;
  InkasantiModel get currentUser {
    final user = _currentUser;
    if (user == null) {
      throw const AuthException('Korisnik nije prijavljen.');
    }
    return user;
  }

  List<StanjeBrojilaModel> get stanjaBrojila =>
      List.unmodifiable(_stanjaBrojila);

  Future<SavedLoginCredentials?> loadSavedLogin() async {
    final username = await _store.loadMetaValue('session_username');
    final password = await _store.loadMetaValue('session_password');
    if (username == null ||
        username.trim().isEmpty ||
        password == null ||
        password.isEmpty) {
      return null;
    }
    return SavedLoginCredentials(username: username, password: password);
  }

  Future<void> rememberLogin(String username, String password) async {
    await _store.saveMetaValue('session_username', username.trim());
    await _store.saveMetaValue('session_password', password);
  }

  Future<void> clearSavedLogin() async {
    await _store.deleteMetaValue('session_username');
    await _store.deleteMetaValue('session_password');
  }

  Future<InkasantiModel> login(String username, String password) async {
    unawaited(AppLogger.log('Pokrenuta prijava korisnika: $username'));
    try {
      _inkasanti = await _fetchInkasanti();
      await _store.saveInkasanti(_inkasanti);
    } catch (_) {
      _inkasanti = await _store.loadInkasanti();
    }

    final normalizedUser = username.trim().toLowerCase();
    final user = _inkasanti.firstWhere(
      (inkasant) =>
          inkasant.username.trim().toLowerCase() == normalizedUser &&
          inkasant.password == password,
      orElse: () =>
          throw const AuthException('Pogrešno korisničko ime ili lozinka.'),
    );
    _currentUser = user;

    await _loadWorkPackage(user);
    await _loadLastSuccessfulSyncAt();
    unawaited(
      AppLogger.log(
        'Uspjesna prijava: ${user.ime}, ID: ${user.idZaOcitavanja}',
      ),
    );
    startPeriodicSync();
    return user;
  }

  List<ReonSummary> reoni(InkasantiModel user) {
    final source = _ocitavanjaZaInkasanta(user, activeOnly: true);
    final groups = <String, List<OcitavanjeModel>>{};
    for (final item in source) {
      groups.putIfAbsent(item.idreon, () => []).add(item);
    }
    return groups.entries.map((entry) {
      final first = entry.value.first;
      return ReonSummary(
        id: first.idreon,
        naziv: first.nazivReona,
        ukupno: entry.value.length,
        ocitano: entry.value.where((item) => item.isOcitano).length,
      );
    }).toList();
  }

  List<RutaSummary> ruteZaReon(String reonId, InkasantiModel user) {
    final items = _ocitavanjaZaInkasanta(
      user,
      activeOnly: true,
    ).where((item) => item.idreon == reonId);
    final groups = <String, List<OcitavanjeModel>>{};
    for (final item in items) {
      groups.putIfAbsent(item.idrute, () => []).add(item);
    }
    return groups.entries.map((entry) {
      final first = entry.value.first;
      return RutaSummary(
        id: first.idrute,
        naziv: first.nazivRute,
        reonId: first.idreon,
        ukupno: entry.value.length,
        ocitano: entry.value.where((item) => item.isOcitano).length,
      );
    }).toList();
  }

  List<OcitavanjeModel> ocitavanjaZaRutu(
    String rutaId,
    InkasantiModel user, {
    required String reonId,
  }) {
    final items = _ocitavanjaZaInkasanta(
      user,
      activeOnly: true,
    ).where((item) => item.idreon == reonId && item.idrute == rutaId).toList();
    items.sort(_compareRbr);
    return items;
  }

  List<OcitavanjeModel> pretraga(String query) {
    final value = query.trim().toLowerCase();
    final activeId = _aktivnoOcitavanje?.id ?? 0;
    final source = activeId <= 0
        ? _ocitavanja
        : _ocitavanja
              .where((item) => item.ocitavanjeGlavnoId == activeId)
              .toList();
    if (value.isEmpty) return List.of(source);
    return source.where((item) {
      return item.idpot.toLowerCase().contains(value) ||
          item.potrosac.toLowerCase().contains(value) ||
          item.vodomjer.toLowerCase().contains(value);
    }).toList();
  }

  List<NapomenaDraft> nesinhronizovaneNapomene() =>
      List.unmodifiable(_napomene);

  int nesinhronizovanaOcitavanjaCount(InkasantiModel user) {
    return _ocitavanjaZaInkasanta(
      user,
      activeOnly: false,
    ).where(_isPendingOcitavanjeUpload).length;
  }

  List<OcitavanjeModel> nesinhronizovanaOcitavanja(InkasantiModel user) {
    final items = _ocitavanjaZaInkasanta(
      user,
      activeOnly: false,
    ).where(_isPendingOcitavanjeUpload).toList();
    items.sort(_compareRbr);
    return items;
  }

  Future<void> refreshLocalSyncState() async {
    _ocitavanja = await _store.loadOcitavanja();
    _napomene
      ..clear()
      ..addAll(await _store.loadUnsyncedNapomene());
    await _loadLastSuccessfulSyncAt();
  }

  Future<AppUpdateInfo?> requiredUpdate(int currentBuildNumber) async {
    final json = await _getJson(
      AppConfig.versionUrl,
    ).timeout(const Duration(seconds: 5));
    if (json is! Map<String, dynamic>) return null;
    final versionCode = _asInt(json['versionCode']);
    final apkUrl = json['apkUrl']?.toString().trim() ?? '';
    if (versionCode <= currentBuildNumber || apkUrl.isEmpty) return null;
    return AppUpdateInfo(versionCode: versionCode, apkUrl: apkUrl);
  }

  Future<bool> hasNetworkSignal() async {
    final lastFailure = _lastNetworkFailureAt;
    if (lastFailure != null &&
        DateTime.now().difference(lastFailure) < const Duration(seconds: 12)) {
      return false;
    }
    try {
      await _getJson(
        '${AppConfig.apiBaseUrl}${AppConfig.maxOcitavanjePath}',
      ).timeout(const Duration(seconds: 5));
      _lastNetworkFailureAt = null;
      return true;
    } catch (_) {
      _lastNetworkFailureAt = DateTime.now();
      return false;
    }
  }

  Future<Map<String, BackendNapomenaModel>> latestNapomeneForIdpots(
    Iterable<String> idpots,
  ) async {
    final uniqueIds = idpots
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (uniqueIds.isEmpty) return {};

    final json = await _postJson(
      '${AppConfig.uploadBaseUrl}${AppConfig.napomenaUploadPath.replaceAll('/upload2', '/latest')}',
      uniqueIds,
    );
    final notes = _asList(
      json,
    ).map((item) => BackendNapomenaModel.fromJson(item));
    return {for (final note in notes) note.idpot: note};
  }

  Future<List<BackendNapomenaModel>> napomeneZaPotrosaca(String idpot) async {
    final encoded = Uri.encodeComponent(idpot.trim());
    final json = await _getJson(
      '${AppConfig.uploadBaseUrl}${AppConfig.napomenaUploadPath.replaceAll('/upload2', '/potrosac/$encoded')}',
    );
    return _asList(
      json,
    ).map((item) => BackendNapomenaModel.fromJson(item)).toList();
  }

  Future<void> sacuvajOcitavanje(
    int id,
    int novoStanje,
    int idstanjebrojila,
    String latitude,
    String longitude,
  ) async {
    final index = _ocitavanja.indexWhere((item) => item.id == id);
    if (index == -1) return;
    _ocitavanja[index] = _ocitavanja[index].copyWith(
      novoStanje: novoStanje,
      idstanjebrojila: idstanjebrojila,
      latitude: latitude,
      longitude: longitude,
      ocitano: 'DA',
      isSynced: false,
    );
    await _store.updateOcitavanje(_ocitavanja[index]);
    unawaited(AppLogger.log('Lokalno sacuvano ocitavanje ID: $id'));
    unawaited(syncPendingNow(reason: 'save_reading'));
  }

  Future<void> sacuvajNapomenu(NapomenaDraft draft) async {
    _napomene.insert(0, draft);
    await _store.saveNapomena(draft);
    unawaited(
      AppLogger.log(
        'Lokalno sacuvana napomena: ${draft.idpot} / ${draft.vodomjer}',
      ),
    );
    unawaited(syncPendingNow(reason: 'save_note'));
  }

  StanjeBrojilaModel? stanjeBrojilaById(int id) {
    for (final stanje in _stanjaBrojila) {
      if (stanje.id == id) return stanje;
    }
    return null;
  }

  void startPeriodicSync() {
    _syncTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(syncPendingNow(reason: 'periodic'));
    });
    unawaited(syncPendingNow(reason: 'login'));
  }

  Future<SyncRunResult> syncPendingNow({String reason = 'manual'}) {
    final activeRun = _activeSyncRun;
    if (activeRun != null) return activeRun;

    final syncFuture = _syncPendingNowInternal(reason);
    _activeSyncRun = syncFuture;
    syncFuture.whenComplete(() => _activeSyncRun = null);
    return syncFuture;
  }

  Future<SyncRunResult> _syncPendingNowInternal(String reason) async {
    final pendingReadings = await _store.loadUnsyncedOcitavanja();
    final pendingNotes = await _store.loadUnsyncedNapomene();
    final shouldRefreshFromServer = _shouldRefreshFromServer(reason);
    if (pendingReadings.isEmpty &&
        pendingNotes.isEmpty &&
        !shouldRefreshFromServer) {
      return const SyncRunResult(readings: 0, notes: 0, hadNetwork: true);
    }

    final hasNetwork = await hasNetworkSignal();
    if (!hasNetwork) {
      unawaited(
        AppLogger.log(
          'Sync preskocen ($reason): nema veze, ocitavanja ${pendingReadings.length}, napomene ${pendingNotes.length}',
        ),
      );
      return const SyncRunResult(readings: 0, notes: 0, hadNetwork: false);
    }

    unawaited(
      AppLogger.log(
        'Sync start ($reason): ocitavanja ${pendingReadings.length}, napomene ${pendingNotes.length}',
      ),
    );
    final readings = pendingReadings.isEmpty
        ? 0
        : await syncUnsyncedOcitavanja();
    final notes = pendingNotes.isEmpty ? 0 : await syncUnsyncedNapomene();
    if (shouldRefreshFromServer) {
      await _refreshServerSnapshot(reason);
    }
    return SyncRunResult(readings: readings, notes: notes, hadNetwork: true);
  }

  Future<int> syncUnsyncedOcitavanja() async {
    final activeSync = _activeReadingsSync;
    if (activeSync != null) return activeSync;

    final syncFuture = _syncUnsyncedOcitavanjaInternal();
    _activeReadingsSync = syncFuture;
    syncFuture.whenComplete(() => _activeReadingsSync = null);
    return syncFuture;
  }

  Future<int> _syncUnsyncedOcitavanjaInternal() async {
    var syncedCount = 0;
    final unsynced = await _store.loadUnsyncedOcitavanja();
    _lastReadingsSyncCandidates = unsynced.length;
    _lastReadingsSyncError = null;
    unawaited(AppLogger.log('Sync ocitavanja kandidati: ${unsynced.length}'));
    for (final item in unsynced) {
      try {
        final synced = item.copyWith(isSynced: true);
        await _putOcitavanje(synced);
        final serverItem = await _fetchOcitavanjeById(item.id);
        if (!_serverConfirmsOcitavanje(item, serverItem)) {
          throw BackendException(
            'Server nije potvrdio upis za očitavanje ${item.id}.',
          );
        }
        await _store.updateOcitavanje(serverItem);
        final index = _ocitavanja.indexWhere((local) => local.id == item.id);
        if (index != -1) _ocitavanja[index] = serverItem;
        syncedCount++;
      } catch (error) {
        _lastReadingsSyncError ??= 'ID ${item.id}: $error';
        await _store.updateOcitavanje(item.copyWith(isSynced: false));
        unawaited(
          AppLogger.log('Greska sync ocitavanja ID ${item.id}: $error'),
        );
      }
    }
    if (syncedCount > 0) {
      await _recordSuccessfulSync('ocitavanja', syncedCount);
    }
    return syncedCount;
  }

  Future<int> syncUnsyncedNapomene() async {
    final activeSync = _activeNotesSync;
    if (activeSync != null) return activeSync;

    final syncFuture = _syncUnsyncedNapomeneInternal();
    _activeNotesSync = syncFuture;
    syncFuture.whenComplete(() => _activeNotesSync = null);
    return syncFuture;
  }

  Future<int> _syncUnsyncedNapomeneInternal() async {
    var syncedCount = 0;
    final notes = await _store.loadUnsyncedNapomene();
    _lastNotesSyncCandidates = notes.length;
    _lastNotesSyncError = null;
    for (final note in notes) {
      try {
        await _uploadNapomena(note);
        await _store.deleteNapomena(note.localId);
        _napomene.removeWhere((item) => item.localId == note.localId);
        final file = File(note.slikaPath);
        if (await file.exists()) await file.delete();
        syncedCount++;
      } catch (error) {
        _lastNotesSyncError ??= 'ID ${note.localId}: $error';
        unawaited(
          AppLogger.log(
            'Greska sync napomene ${note.localId} / ${note.idpot}: $error',
          ),
        );
        // Napomena ostaje lokalno za sljedeći pokušaj.
      }
    }
    if (syncedCount > 0) {
      await _recordSuccessfulSync('napomene', syncedCount);
    }
    return syncedCount;
  }

  Future<void> _loadWorkPackage(InkasantiModel user) async {
    try {
      _aktivnoOcitavanje = await _fetchAktivnoOcitavanje();
      await _store.saveAktivnoOcitavanje(_aktivnoOcitavanje!);
      _stanjaBrojila = await _fetchStanjaBrojila();
      await _store.saveStanjaBrojila(_stanjaBrojila);
      _ocitavanja = await _fetchOcitavanjaZaInkasanta(
        maxId: _aktivnoOcitavanje?.id ?? 0,
        idZaOcitavanja: user.idZaOcitavanja,
      );
      final localMaxId = await _store.maxLocalOcitavanjeGlavnoId();
      final onlineMaxId = _aktivnoOcitavanje?.id ?? 0;
      if (localMaxId < onlineMaxId) {
        await _store.replaceOcitavanja(_ocitavanja);
      } else {
        await _store.mergeOcitavanjaForActiveImport(_ocitavanja);
      }
      _ocitavanja = await _store.loadOcitavanja();
      _napomene
        ..clear()
        ..addAll(await _store.loadUnsyncedNapomene());
    } catch (_) {
      _aktivnoOcitavanje = await _store.loadAktivnoOcitavanje();
      _stanjaBrojila = await _store.loadStanjaBrojila();
      _ocitavanja = await _store.loadOcitavanja();
      _napomene
        ..clear()
        ..addAll(await _store.loadUnsyncedNapomene());
      if (_ocitavanja.isEmpty) {
        throw const BackendException(
          'Nema interneta i nema lokalno sačuvanih očitavanja.',
        );
      }
    }
  }

  bool _shouldRefreshFromServer(String reason) {
    if (_currentUser == null) return false;
    if (reason.startsWith('manual')) return false;
    if (reason == 'login' || reason == 'app_resumed') return true;
    final lastRefresh = _lastServerRefreshAt;
    return lastRefresh == null ||
        DateTime.now().difference(lastRefresh) >= _serverRefreshInterval;
  }

  Future<void> _refreshServerSnapshot(String reason) async {
    final current = _currentUser;
    if (current == null) return;
    try {
      final user = await _refreshCurrentUserFromServer(current);
      _aktivnoOcitavanje = await _fetchAktivnoOcitavanje();
      await _store.saveAktivnoOcitavanje(_aktivnoOcitavanje!);
      _stanjaBrojila = await _fetchStanjaBrojila();
      await _store.saveStanjaBrojila(_stanjaBrojila);

      final serverOcitavanja = await _fetchOcitavanjaZaInkasanta(
        maxId: _aktivnoOcitavanje?.id ?? 0,
        idZaOcitavanja: user.idZaOcitavanja,
      );
      final localMaxId = await _store.maxLocalOcitavanjeGlavnoId();
      final onlineMaxId = _aktivnoOcitavanje?.id ?? 0;
      if (localMaxId < onlineMaxId) {
        await _store.replaceOcitavanja(serverOcitavanja);
      } else {
        await _store.mergeOcitavanjaForActiveImport(serverOcitavanja);
      }
      _ocitavanja = await _store.loadOcitavanja();
      _napomene
        ..clear()
        ..addAll(await _store.loadUnsyncedNapomene());
      _lastServerRefreshAt = DateTime.now();
      unawaited(
        AppLogger.log(
          'Server refresh ($reason): ${serverOcitavanja.length} ocitavanja',
        ),
      );
    } catch (error) {
      unawaited(AppLogger.log('Server refresh greska ($reason): $error'));
    }
  }

  Future<InkasantiModel> _refreshCurrentUserFromServer(
    InkasantiModel fallback,
  ) async {
    _inkasanti = await _fetchInkasanti();
    await _store.saveInkasanti(_inkasanti);
    final updated = _inkasanti.firstWhere(
      (item) =>
          item.idink == fallback.idink ||
          item.username.trim().toLowerCase() ==
              fallback.username.trim().toLowerCase(),
      orElse: () => fallback,
    );
    _currentUser = updated;
    return updated;
  }

  Future<void> _loadLastSuccessfulSyncAt() async {
    final value = await _store.loadMetaValue('last_successful_sync_at');
    _lastSuccessfulSyncAt = value == null ? null : DateTime.tryParse(value);
  }

  Future<void> _recordSuccessfulSync(String type, int count) async {
    final now = DateTime.now();
    _lastSuccessfulSyncAt = now;
    await _store.saveMetaValue(
      'last_successful_sync_at',
      now.toIso8601String(),
    );
    unawaited(AppLogger.log('Sinhronizovano $type: $count'));
  }

  int _compareRbr(OcitavanjeModel a, OcitavanjeModel b) {
    final aIsEmpty = a.rbr <= 0;
    final bIsEmpty = b.rbr <= 0;
    if (aIsEmpty && !bIsEmpty) return 1;
    if (!aIsEmpty && bIsEmpty) return -1;
    final byRbr = a.rbr.compareTo(b.rbr);
    if (byRbr != 0) return byRbr;
    return a.potrosac.compareTo(b.potrosac);
  }

  bool _isPendingOcitavanjeUpload(OcitavanjeModel item) {
    return !item.isSynced && item.ocitano.trim().toLowerCase() == 'da';
  }

  List<OcitavanjeModel> _ocitavanjaZaInkasanta(
    InkasantiModel user, {
    required bool activeOnly,
  }) {
    final id = user.idZaOcitavanja.trim();
    final source = activeOnly ? _aktivnaOcitavanja() : _ocitavanja;
    if (id.isEmpty) return List.of(source);
    final filtered = _ocitavanja
        .where((item) => item.idink.trim() == id)
        .toList();
    if (!activeOnly) return filtered.isEmpty ? List.of(_ocitavanja) : filtered;
    final activeFiltered = filtered
        .where(
          (item) =>
              (_aktivnoOcitavanje?.id ?? 0) <= 0 ||
              item.ocitavanjeGlavnoId == _aktivnoOcitavanje?.id,
        )
        .toList();
    return activeFiltered.isEmpty ? List.of(source) : activeFiltered;
  }

  List<OcitavanjeModel> _aktivnaOcitavanja() {
    final activeId = _aktivnoOcitavanje?.id ?? 0;
    if (activeId <= 0) return List.of(_ocitavanja);
    return _ocitavanja
        .where((item) => item.ocitavanjeGlavnoId == activeId)
        .toList();
  }

  Future<List<InkasantiModel>> _fetchInkasanti() async {
    final json = await _getJson(
      '${AppConfig.apiBaseUrl}${AppConfig.inkasantiPath}',
    );
    return _asList(json).map((item) => InkasantiModel.fromJson(item)).toList();
  }

  Future<OcitavanjeGlavnoModel> _fetchAktivnoOcitavanje() async {
    final json = await _getJson(
      '${AppConfig.apiBaseUrl}${AppConfig.maxOcitavanjePath}',
    );
    if (json is! Map<String, dynamic>) {
      throw const BackendException('Backend nije vratio aktivno očitavanje.');
    }
    return OcitavanjeGlavnoModel.fromJson(json);
  }

  Future<List<OcitavanjeModel>> _fetchOcitavanjaZaInkasanta({
    required int maxId,
    required String idZaOcitavanja,
  }) async {
    final encodedId = Uri.encodeComponent(idZaOcitavanja);
    final json = await _getJson(
      '${AppConfig.apiBaseUrl}${AppConfig.ocitavanjaPath}/$maxId/$encodedId',
    );
    return _asList(json).map((item) => OcitavanjeModel.fromJson(item)).toList();
  }

  Future<OcitavanjeModel> _fetchOcitavanjeById(int id) async {
    final json = await _getJson(
      '${AppConfig.apiBaseUrl}${AppConfig.ocitavanjaPath}/$id',
    );
    if (json is! Map<String, dynamic>) {
      throw BackendException('Backend nije vratio očitavanje $id.');
    }
    return OcitavanjeModel.fromJson(json);
  }

  bool _serverConfirmsOcitavanje(
    OcitavanjeModel local,
    OcitavanjeModel server,
  ) {
    return server.id == local.id &&
        server.novoStanje == local.novoStanje &&
        server.idstanjebrojila == local.idstanjebrojila &&
        server.isSynced &&
        server.ocitano.trim().toLowerCase() == 'da';
  }

  Future<List<StanjeBrojilaModel>> _fetchStanjaBrojila() async {
    final json = await _getJson(
      '${AppConfig.apiBaseUrl}${AppConfig.stanjaBrojilaPath}',
    );
    return _asList(
      json,
    ).map((item) => StanjeBrojilaModel.fromJson(item)).toList();
  }

  Future<Object?> _getJson(String url) async {
    final request = await _httpClient
        .getUrl(Uri.parse(url))
        .timeout(_connectTimeout);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(_readTimeout);
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(_readTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BackendException('Backend greška ${response.statusCode}: $body');
    }
    if (body.trim().isEmpty) return null;
    return jsonDecode(body);
  }

  Future<Object?> _postJson(String url, Object payload) async {
    final request = await _httpClient
        .postUrl(Uri.parse(url))
        .timeout(_connectTimeout);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.contentType = ContentType(
      'application',
      'json',
      charset: 'utf-8',
    );
    request.add(utf8.encode(jsonEncode(payload)));
    final response = await request.close().timeout(_readTimeout);
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(_readTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BackendException('Backend greška ${response.statusCode}: $body');
    }
    if (body.trim().isEmpty) return null;
    return jsonDecode(body);
  }

  Future<void> _putOcitavanje(OcitavanjeModel item) async {
    final request = await _httpClient
        .putUrl(
          Uri.parse(
            '${AppConfig.apiBaseUrl}${AppConfig.ocitavanjaPath}/${item.id}',
          ),
        )
        .timeout(_connectTimeout);
    request.headers.contentType = ContentType(
      'application',
      'json',
      charset: 'utf-8',
    );
    request.add(utf8.encode(jsonEncode(item.toJson())));
    final response = await request.close().timeout(_readTimeout);
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(_readTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BackendException('Sync greška ${response.statusCode}: $body');
    }
  }

  Future<void> _uploadNapomena(NapomenaDraft note) async {
    final file = File(note.slikaPath);
    if (!await file.exists()) {
      throw const BackendException('Slika za napomenu ne postoji lokalno.');
    }

    final boundary =
        '----vodovod_flutter_${DateTime.now().microsecondsSinceEpoch}';
    final request = await _httpClient
        .postUrl(
          Uri.parse(
            '${AppConfig.uploadBaseUrl}${AppConfig.napomenaUploadPath}',
          ),
        )
        .timeout(_connectTimeout);
    request.headers.set(
      HttpHeaders.contentTypeHeader,
      'multipart/form-data; boundary=$boundary',
    );

    void addTextPart(String name, String value) {
      request.add(
        utf8.encode(
          '--$boundary\r\n'
          'Content-Disposition: form-data; name="$name"\r\n'
          'Content-Type: text/plain; charset=utf-8\r\n\r\n'
          '$value\r\n',
        ),
      );
    }

    addTextPart('vodomjer', _fallback(note.vodomjer, 'nema vodomjera'));
    addTextPart('link', 'link2');
    addTextPart('ink_id', note.inkId);
    addTextPart('imepot', _fallback(note.imepot, 'nema imena potrosaca'));
    addTextPart('idpot', _fallback(note.idpot, 'nema id potrosaca'));
    addTextPart('napomena', _fallback(note.napomena, 'nema napomene'));
    addTextPart('is_prijava', note.isPrijava.toString());
    addTextPart('profil', _fallback(note.profil, 'nema_profila'));

    request.add(
      utf8.encode(
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="file"; filename="${file.uri.pathSegments.last}"\r\n'
        'Content-Type: image/jpeg\r\n\r\n',
      ),
    );
    await request.addStream(file.openRead());
    request.add(utf8.encode('\r\n--$boundary--\r\n'));

    final response = await request.close().timeout(_uploadTimeout);
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(_readTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BackendException('Upload napomene ${response.statusCode}: $body');
    }
  }

  String _fallback(String value, String fallback) {
    return value.trim().isEmpty ? fallback : value.trim();
  }

  List<Map<String, dynamic>> _asList(Object? json) {
    if (json is List) {
      return json
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    throw const BackendException('Backend nije vratio listu podataka.');
  }

  int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class AppUpdateInfo {
  const AppUpdateInfo({required this.versionCode, required this.apkUrl});

  final int versionCode;
  final String apkUrl;
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BackendException implements Exception {
  const BackendException(this.message);

  final String message;

  @override
  String toString() => message;
}

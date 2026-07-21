import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import '../models/artwork_document.dart';
import '../models/artwork_index.dart';
import '../models/artwork_summary.dart';
import '../repositories/artwork_repository.dart';

/// Debounced auto-save (Phase Hγ: "自動保存＋復帰"). [scheduleSave] is meant
/// to be called once per relevant provider change (see
/// `providers/auto_save_provider.dart` for the `ref.listen` wiring that
/// does so in the real app, across `canvasProvider`, `underlayProvider`,
/// and `underlayLayoutProvider`); once [debounce] has passed with no
/// further call, the latest [ArtworkDocument] snapshot is saved through
/// [ArtworkRepository] in the background — the document itself, a freshly
/// captured thumbnail (if [captureThumbnail] is supplied), and an updated
/// 索引ファイル entry.
///
/// Deliberately knows nothing about Riverpod/`CanvasNotifier`/Flutter's
/// widget tree — it only ever sees the plain [ArtworkDocument] snapshots
/// handed to [scheduleSave]/[flush], plus the injected [captureThumbnail]
/// callback — so it's testable with nothing more than a fake/in-memory
/// [ArtworkRepository] and plain values, no `ProviderContainer` or
/// rendered widget required.
class AutoSaveService {
  AutoSaveService({
    // Named `repository` (not `_repository`) so callers outside this
    // library can pass it — an initializing formal (`this._repository`)
    // would force the external argument name to match the private field
    // name, which other libraries cannot reference at all.
    required ArtworkRepository repository,
    this.debounce = const Duration(seconds: 2),
    this.captureThumbnail,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) : _repository = repository, // ignore: prefer_initializing_formals
       _onError = onError ?? _defaultOnError;

  final ArtworkRepository _repository;

  /// Quiet period after the *last* [scheduleSave] call before the save
  /// actually runs — each call resets the timer, so a burst of edits (e.g.
  /// a なぞり stroke placing many vertices, or Phase G's bulk tessellation
  /// commit) triggers exactly one save, not one per individual edit.
  final Duration debounce;

  /// Captures a fresh gallery thumbnail at the moment a save actually
  /// runs, or `null` bytes/no callback at all if that's unavailable (e.g.
  /// the editor isn't currently mounted). A capture failure never blocks
  /// or fails the document save itself — see [_saveNow].
  final Future<Uint8List?> Function()? captureThumbnail;

  final void Function(Object error, StackTrace stackTrace) _onError;

  Timer? _timer;

  /// The most recently scheduled document snapshot — used by [flush] so it
  /// always saves the *latest* state even if called without its own
  /// [ArtworkDocument] in hand (e.g. from an app-lifecycle callback).
  ArtworkDocument? _pendingDocument;

  /// The most recent in-flight (or most recently completed) save, so
  /// [flush]/[dispose] callers can `await` it instead of racing a
  /// still-running background save.
  Future<void>? lastSave;

  /// Records [document] as the latest snapshot to save, (re)starting the
  /// debounce countdown. Cheap — just resets a [Timer] — until [debounce]
  /// elapses with no further call, so it's safe to call on every single
  /// relevant provider change.
  void scheduleSave(ArtworkDocument document) {
    _pendingDocument = document;
    _timer?.cancel();
    _timer = Timer(debounce, () => lastSave = _saveNow(document));
  }

  /// Cancels any pending debounced save and saves immediately — for
  /// app-pause/dispose call sites, so the last few seconds of edits before
  /// a kill are never silently lost waiting for [debounce] to elapse.
  /// [document] defaults to whatever [scheduleSave] most recently recorded;
  /// a no-op (no save) if nothing has ever been scheduled.
  Future<void> flush([ArtworkDocument? document]) async {
    _timer?.cancel();
    _timer = null;
    final toSave = document ?? _pendingDocument;
    if (toSave == null) return;
    await (lastSave = _saveNow(toSave));
  }

  /// Cancels any pending debounced save without running it — for ending a
  /// session without a final save (e.g. discarding a blank, never-edited
  /// artwork). Most call sites should prefer [flush].
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pendingDocument = null;
  }

  void dispose() => cancel();

  /// Persists [document] and upserts its 索引ファイル entry, capturing a
  /// fresh thumbnail first if [captureThumbnail] is set. Exceptions are
  /// caught and routed to [_onError] rather than left to propagate: in
  /// normal use ([scheduleSave]) this runs from inside a bare [Timer]
  /// callback, where an uncaught exception would become an unhandled async
  /// error instead of a recoverable failure — a save failure (disk full,
  /// permission denial, a thumbnail capture that throws, …) must never
  /// crash the app (Phase Hγ #19).
  Future<void> _saveNow(ArtworkDocument document) async {
    try {
      await _repository.saveArtwork(document);

      final thumbnailBytes = await _safeCaptureThumbnail();
      if (thumbnailBytes != null) {
        await _repository.saveThumbnail(document.artwork.id, thumbnailBytes);
      }

      final index = await _repository.readIndex();
      final summary = ArtworkSummary(
        id: document.artwork.id,
        title: document.artwork.title,
        updatedAt: DateTime.now(),
        thumbnailPath: _repository.thumbnailPathFor(document.artwork.id),
        documentPath: _repository.documentPathFor(document.artwork.id),
      );
      final artworks = [
        for (final existing in index.artworks)
          if (existing.id != document.artwork.id) existing,
        summary,
      ];
      await _repository.writeIndex(ArtworkIndex(artworks: artworks));
    } catch (error, stackTrace) {
      _onError(error, stackTrace);
    }
  }

  /// Runs [captureThumbnail], swallowing any exception it throws into
  /// `null` — a thumbnail is a nice-to-have for the gallery grid, never a
  /// reason to abandon (or fail) the document save itself.
  Future<Uint8List?> _safeCaptureThumbnail() async {
    final capture = captureThumbnail;
    if (capture == null) return null;
    try {
      return await capture();
    } catch (error, stackTrace) {
      _onError(error, stackTrace);
      return null;
    }
  }
}

void _defaultOnError(Object error, StackTrace stackTrace) {
  debugPrint('AutoSaveService: save failed: $error\n$stackTrace');
}

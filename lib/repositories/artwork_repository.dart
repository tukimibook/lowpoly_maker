import 'dart:convert';
import 'dart:typed_data';

import 'package:file/file.dart';
import 'package:flutter/foundation.dart' show compute;

import '../models/artwork_document.dart';
import '../models/artwork_index.dart';

/// File-based persistence for Phase Hγ ("1作品＝1 JSON + サムネPNG + 索引ファイル").
///
/// Layout under [documentsPath] (the app's own local documents directory —
/// see `providers/artwork_repository_provider.dart` for how that's resolved
/// via `path_provider` in the real app):
/// ```
/// <documentsPath>/
///   index.json                 — the single 索引ファイル (ArtworkIndex)
///   artworks/<id>.json         — one ArtworkDocument per artwork
///   thumbnails/<id>.png        — one gallery thumbnail per artwork
///   underlays/<id><ext>        — the artwork's underlay photo, copied in at
///                                 import time so deleting/moving the
///                                 original in the system gallery can never
///                                 break a saved artwork
/// ```
///
/// Takes a [FileSystem] (`package:file`) rather than talking to `dart:io`
/// directly, so tests can inject `MemoryFileSystem()` (real read/write
/// semantics, no real disk I/O, no platform channel) instead of either
/// touching the real filesystem or hand-mocking every `File`/`Directory`
/// method individually.
///
/// Every *write* here goes through [_writeAtomicBytes]: encode/serialize,
/// write to a sibling `<name>.temp` file, then rename it over the real
/// path — so a kill (or a crash) mid-write can never leave a half-written
/// `index.json`/artwork document/thumbnail in place (Phase Hγ requirement,
/// #19). Every *read* of a document/index that fails to parse — corrupted
/// JSON, or any other I/O error — is treated as absent (`null`/empty)
/// rather than thrown, so a single damaged file can never crash the app;
/// callers decide what "not found" should mean (e.g. the gallery skipping
/// that entry — see the 統合 smoke checklist's 破損JSON step).
class ArtworkRepository {
  ArtworkRepository({required FileSystem fileSystem, required String documentsPath})
    : _fs = fileSystem,
      _root = documentsPath;

  final FileSystem _fs;
  final String _root;

  /// App documents directory this repository is rooted at — used by callers
  /// composing `ArtworkDocument.fromSession` / resolving underlay relative
  /// paths back to absolute filesystem paths.
  String get documentsPath => _root;

  String get _indexPath => _fs.path.join(_root, 'index.json');
  String get _artworksDirPath => _fs.path.join(_root, 'artworks');
  String get _thumbnailsDirPath => _fs.path.join(_root, 'thumbnails');
  String get _underlaysDirPath => _fs.path.join(_root, 'underlays');

  /// Path [saveArtwork]/[readArtwork] use for artwork [id]. Exposed so
  /// callers (e.g. `AutoSaveService`) can populate `ArtworkSummary.documentPath`
  /// without duplicating this layout decision.
  String documentPathFor(String id) => _fs.path.join(_artworksDirPath, '$id.json');

  /// Path [saveThumbnail] writes artwork [id]'s thumbnail to. Exposed for
  /// the same reason as [documentPathFor].
  String thumbnailPathFor(String id) => _fs.path.join(_thumbnailsDirPath, '$id.png');

  /// Path [copyUnderlayImage] copies artwork [id]'s underlay photo to,
  /// preserving [sourcePath]'s original extension (so the copy stays a
  /// valid, correctly-typed image file the platform's decoder recognizes).
  String underlayPathFor(String id, String sourcePath) {
    final ext = _fs.path.extension(sourcePath);
    return _fs.path.join(_underlaysDirPath, '$id$ext');
  }

  // --- Index file --------------------------------------------------------

  /// Reads the 索引ファイル. Returns [ArtworkIndex.empty] if it doesn't exist
  /// yet (first launch) or fails to parse (corrupted — see class doc).
  Future<ArtworkIndex> readIndex() async {
    final file = _fs.file(_indexPath);
    if (!await file.exists()) return ArtworkIndex.empty();
    try {
      final raw = await file.readAsString();
      final json = await compute(_decodeJsonObject, raw);
      return ArtworkIndex.fromJson(json);
    } catch (_) {
      return ArtworkIndex.empty();
    }
  }

  /// Atomically overwrites the 索引ファイル with [index]. Propagates any
  /// underlying I/O failure (e.g. permission denial, disk full) — callers
  /// that must never crash on this (e.g. `AutoSaveService`, running
  /// detached from any UI await) are responsible for catching it.
  Future<void> writeIndex(ArtworkIndex index) async {
    final json = await compute(_encodeIndexJson, index);
    await _writeAtomicBytes(_fs.file(_indexPath), utf8.encode(json));
  }

  // --- ArtworkDocument (one per artwork) ---------------------------------

  /// Reads artwork [id]'s document. Returns `null` if it doesn't exist or
  /// fails to parse (see class doc) — never throws.
  Future<ArtworkDocument?> readArtwork(String id) async {
    final file = _fs.file(documentPathFor(id));
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      final json = await compute(_decodeJsonObject, raw);
      return ArtworkDocument.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Atomically writes [document]'s `ArtworkDocument` JSON (geometry, plus
  /// its underlay reference if any). Encoding runs on a background
  /// `Isolate` via `compute()` (Phase Hγ requirement — avoids blocking the
  /// UI thread on a large document's `jsonEncode`, the same reasoning as
  /// Phase G's `compute(triangulate, ...)`).
  Future<void> saveArtwork(ArtworkDocument document) async {
    final json = await compute(_encodeArtworkDocumentJson, document);
    await _writeAtomicBytes(_fs.file(documentPathFor(document.artwork.id)), utf8.encode(json));
  }

  /// Deletes artwork [id]'s document, if present. A missing file is a
  /// silent no-op (deleting an already-deleted artwork must not throw).
  /// Does **not** touch the index or the artwork's thumbnail/underlay —
  /// callers (the future gallery delete action) are responsible for
  /// removing/updating those too.
  Future<void> deleteArtworkDocument(String id) async {
    final file = _fs.file(documentPathFor(id));
    if (await file.exists()) await file.delete();
  }

  // --- Thumbnail -----------------------------------------------------------

  /// Atomically writes artwork [id]'s gallery thumbnail ([pngBytes] — a
  /// pre-encoded PNG; encoding the bitmap itself is a UI/rendering concern
  /// outside this repository).
  Future<void> saveThumbnail(String id, Uint8List pngBytes) async {
    await _writeAtomicBytes(_fs.file(thumbnailPathFor(id)), pngBytes);
  }

  /// Deletes artwork [id]'s thumbnail, if present. A missing file is a
  /// silent no-op, same as [deleteArtworkDocument].
  Future<void> deleteThumbnail(String id) async {
    final file = _fs.file(thumbnailPathFor(id));
    if (await file.exists()) await file.delete();
  }

  // --- Composite delete (gallery "削除") -------------------------------------

  /// Removes artwork [id] entirely: its `ArtworkDocument`, its thumbnail,
  /// and its 索引ファイル entry (read-modify-write, so a concurrent
  /// `writeIndex` from an in-flight auto-save can't be silently dropped by
  /// this call overwriting the index with a stale copy — see the class
  /// doc's atomic-write guarantee, which still applies to this final
  /// write). Deliberately leaves the artwork's underlay photo copy (if any)
  /// in place — Phase Hγ's delete action only removes "関連ファイル（JSON,
  /// PNG）"; an orphaned underlay copy is an acceptable, unlisted trade-off
  /// rather than scope creep here.
  Future<void> deleteArtwork(String id) async {
    await deleteArtworkDocument(id);
    await deleteThumbnail(id);

    final index = await readIndex();
    final remaining = index.artworks.where((summary) => summary.id != id).toList();
    if (remaining.length != index.artworks.length) {
      await writeIndex(ArtworkIndex(artworks: remaining));
    }
  }

  // --- Underlay photo copy -------------------------------------------------

  /// Copies the underlay photo at [sourcePath] into this repository's own
  /// `underlays/` directory, so a saved artwork keeps working even if the
  /// original photo is later deleted or moved out of the system gallery.
  /// Returns the new, in-app path (what should be stored as the artwork's
  /// underlay reference from then on — never [sourcePath] itself).
  ///
  /// Copies via a `.temp` sibling + rename, same as every other write here,
  /// so an interrupted copy can never leave a half-written image file at
  /// the real destination path.
  Future<String> copyUnderlayImage({required String artworkId, required String sourcePath}) async {
    final destinationPath = underlayPathFor(artworkId, sourcePath);
    final destination = _fs.file(destinationPath);
    await destination.parent.create(recursive: true);

    final tempFile = _fs.file('$destinationPath.temp');
    await _fs.file(sourcePath).copy(tempFile.path);
    await tempFile.rename(destinationPath);
    return destinationPath;
  }

  // --- Shared write helper --------------------------------------------------

  /// Writes [bytes] to [target] atomically: [target]'s directory is
  /// created if missing, [bytes] are written to a `<target>.temp` sibling,
  /// then that sibling is renamed over [target] — a single filesystem
  /// rename, so any reader either sees the complete old file or the
  /// complete new one, never a partial write (Phase Hγ requirement).
  Future<void> _writeAtomicBytes(File target, List<int> bytes) async {
    await target.parent.create(recursive: true);
    final tempFile = _fs.file('${target.path}.temp');
    await tempFile.writeAsBytes(bytes, flush: true);
    await tempFile.rename(target.path);
  }
}

/// Top-level (not a closure) so it can be passed to `compute()` — see
/// `services/tessellation_service.dart`'s [triangulate] for the same
/// constraint. Runs `jsonDecode` (potentially expensive for a
/// many-thousand-vertex document) off the UI thread.
Map<String, dynamic> _decodeJsonObject(String raw) {
  return jsonDecode(raw) as Map<String, dynamic>;
}

/// Top-level `compute()` target — see [_decodeJsonObject].
String _encodeArtworkDocumentJson(ArtworkDocument document) => jsonEncode(document.toJson());

/// Top-level `compute()` target — see [_decodeJsonObject].
String _encodeIndexJson(ArtworkIndex index) => jsonEncode(index.toJson());

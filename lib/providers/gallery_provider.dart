import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/artwork.dart';
import '../models/artwork_index.dart';
import '../models/underlay_layout.dart';
import 'artwork_repository_provider.dart';
import 'canvas_provider.dart';
import 'underlay_layout_provider.dart';
import 'underlay_provider.dart';

const _uuid = Uuid();

/// The current 索引ファイル contents, for `GalleryScreen`'s grid. Re-fetched
/// from [artworkRepositoryProvider] whenever invalidated — `GalleryController`
/// invalidates this after any action ([GalleryController.deleteArtwork]) that
/// changes what's on disk, and `GalleryScreen` also invalidates it itself on
/// returning from the editor, so a title/thumbnail edited during that visit
/// shows up immediately without a manual pull-to-refresh.
final artworkIndexProvider = FutureProvider<ArtworkIndex>((ref) async {
  final repository = await ref.watch(artworkRepositoryProvider.future);
  return repository.readIndex();
});

/// The three gallery lifecycle actions (Phase Hγ): 新規作成 / 開く（復帰） /
/// 削除. Deliberately returns/awaits plain data rather than performing any
/// navigation itself — `GalleryScreen` owns deciding *when* (and whether) to
/// push `EditorScreen` after one of these completes.
class GalleryController {
  GalleryController(this._ref);

  final Ref _ref;

  /// Resets every artwork-scoped provider to a brand new, empty artwork:
  /// [canvasProvider] gets a fresh id/title, and any underlay from whatever
  /// artwork was previously open is cleared. Safe to call even if nothing
  /// was open yet (e.g. the very first launch).
  void createNewArtwork() {
    _ref.read(canvasProvider.notifier).loadArtwork(Artwork.empty(id: _uuid.v4()));
    _ref.read(underlayProvider.notifier).setImagePath(null);
    _ref.read(underlayLayoutProvider).setLayout(UnderlayLayout.initial);
  }

  /// Loads artwork [id]'s saved `ArtworkDocument` and restores every
  /// provider it touched. Returns `false` (leaving every provider
  /// untouched) if [id] has no document — e.g. its file was deleted or
  /// corrupted out-of-band — so the caller can show an error instead of
  /// navigating to a half-restored editor.
  Future<bool> openArtwork(String id) async {
    final repository = await _ref.read(artworkRepositoryProvider.future);
    final document = await repository.readArtwork(id);
    if (document == null) return false;

    _ref.read(canvasProvider.notifier).loadArtwork(document.artwork);
    _ref.read(underlayProvider.notifier).setImagePath(document.underlayImagePath);
    _ref.read(underlayLayoutProvider).setLayout(document.underlayLayout ?? UnderlayLayout.initial);
    return true;
  }

  /// Deletes artwork [id] (its document, thumbnail, and 索引ファイル entry —
  /// see `ArtworkRepository.deleteArtwork`) and refreshes [artworkIndexProvider]
  /// so it disappears from the grid immediately.
  Future<void> deleteArtwork(String id) async {
    final repository = await _ref.read(artworkRepositoryProvider.future);
    await repository.deleteArtwork(id);
    _ref.invalidate(artworkIndexProvider);
  }
}

final galleryControllerProvider = Provider<GalleryController>((ref) => GalleryController(ref));

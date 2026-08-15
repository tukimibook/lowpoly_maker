import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/artwork.dart';
import '../models/artwork_document.dart';
import '../providers/underlay_layout_provider.dart';
import '../providers/underlay_provider.dart';
import '../services/auto_save_service.dart';
import '../services/gallery_quota.dart';
import '../services/thumbnail_capture_service.dart';
import 'artwork_repository_provider.dart';
import 'canvas_capture_provider.dart';
import 'canvas_provider.dart';
import 'selected_vertex_provider.dart' show EditorSessionRead;
import 'underlay_image_provider.dart';

/// Builds the current editing session as an [ArtworkDocument], or `null`
/// when [artworkRepositoryProvider] has not resolved yet.
///
/// Single source of truth for the `ArtworkDocument.fromSession` assembly
/// that auto-save and explicit flush (save-and-exit) previously duplicated.
/// Call as `currentArtworkDocument(ref.read)`.
ArtworkDocument? currentArtworkDocument(EditorSessionRead read) {
  final repository = read(artworkRepositoryProvider).valueOrNull;
  if (repository == null) return null;
  return ArtworkDocument.fromSession(
    artwork: read(canvasProvider),
    documentsPath: repository.documentsPath,
    underlayAbsolutePath: read(underlayProvider).imagePath,
    underlayLayout: read(underlayLayoutProvider).value,
  );
}

/// Forces an immediate (non-debounced) save of [currentArtworkDocument]
/// via [AutoSaveService.flush]. No-op when the repository or
/// [autoSaveServiceProvider] is not ready yet.
///
/// Rethrows [GalleryQuotaExceededException] so the editor can refuse to
/// pop. Call as `await saveAndFlushCurrentDocument(ref.read)`.
Future<void> saveAndFlushCurrentDocument(EditorSessionRead read) async {
  final service = read(autoSaveServiceProvider);
  final document = currentArtworkDocument(read);
  if (service == null || document == null) return;
  await service.flush(document);
}

/// Most recent auto-save failure (quota, disk, …). [EditorScreen] listens
/// and surfaces [GalleryQuotaExceededException] as a SnackBar. A new object
/// is written on every failure so consecutive identical errors still fire.
final autoSaveLastErrorProvider = StateProvider<Object?>((ref) => null);

/// Wires [AutoSaveService] to every provider a saved `ArtworkDocument`
/// actually depends on — [canvasProvider] (geometry), [underlayProvider]
/// (which photo, if any), and [underlayLayoutProvider] (its placement) —
/// for the lifetime of the app: a change to any of them schedules a
/// debounced save of the *current* combined [ArtworkDocument] snapshot
/// (Phase Hγ: "自動保存＋復帰").
///
/// `null` until [artworkRepositoryProvider] resolves (e.g. the very first
/// frame, before `path_provider` has answered) — nothing is lost in that
/// window; whichever state exists once the repository *does* resolve
/// becomes the first one scheduled, exactly like
/// `underlayFitCoordinatorProvider` waiting on its own async dependency.
///
/// Read (`ref.watch`) this once from somewhere that lives for the whole
/// editing session (e.g. `EditorScreen`) to activate it — like
/// `underlayFitCoordinatorProvider`, this provider's own value is only
/// exposed for tests; nothing needs to react to it changing.
final autoSaveServiceProvider = Provider<AutoSaveService?>((ref) {
  final repository = ref.watch(artworkRepositoryProvider).valueOrNull;
  if (repository == null) return null;

  final captureKey = ref.watch(canvasRepaintBoundaryKeyProvider);
  final thumbnailService = ThumbnailCaptureService();

  final service = AutoSaveService(
    repository: repository,
    currentQuota: () => ref.read(galleryQuotaProvider),
    captureThumbnail: () => thumbnailService.capture(captureKey),
    allowThumbnailCapture: (document) => _isUnderlayReadyForThumbnail(ref, document),
    onError: (error, stackTrace) {
      debugPrint('AutoSaveService: save failed: $error\n$stackTrace');
      ref.read(autoSaveLastErrorProvider.notifier).state = error;
    },
  );

  void scheduleCurrent() {
    final document = currentArtworkDocument(ref.read);
    if (document == null) return;
    service.scheduleSave(document);
  }

  ref.listen<Artwork>(canvasProvider, (previous, next) {
    scheduleCurrent();
  });
  ref.listen<UnderlayState>(underlayProvider, (previous, next) {
    scheduleCurrent();
  });

  // When an underlay finishes decoding after a save that skipped the
  // thumbnail (loading/error guard), schedule again so a good thumb can
  // land once the canvas is actually paintable.
  ref.listen(underlayImageProvider, (previous, next) {
    if (next.hasValue && next.valueOrNull != null) {
      scheduleCurrent();
    }
  });

  // `underlayLayoutProvider` exposes a `ValueNotifier`, not a
  // `StateNotifier` — its own value changes never make the *provider*
  // itself emit, so `ref.listen` alone wouldn't see them (same reasoning
  // as `underlayFitCoordinatorProvider` listening to `CanvasSizeController`
  // directly). Listening to the controller itself catches every
  // opacity/visibility/placement change too.
  final underlayLayoutController = ref.read(underlayLayoutProvider);
  void onUnderlayLayoutChanged() => scheduleCurrent();
  underlayLayoutController.addListener(onUnderlayLayoutChanged);

  ref.onDispose(() {
    underlayLayoutController.removeListener(onUnderlayLayoutChanged);
    service.dispose();
  });

  return service;
});

/// Thumbnail capture is allowed when the document has no underlay, or when
/// the underlay image has finished decoding successfully. Loading / error
/// states must not overwrite a previously good gallery thumbnail with a
/// dark, underlay-less frame.
bool _isUnderlayReadyForThumbnail(Ref ref, ArtworkDocument document) {
  if (document.underlay == null) return true;
  final image = ref.read(underlayImageProvider);
  if (image.isLoading || image.hasError) return false;
  return image.valueOrNull != null;
}

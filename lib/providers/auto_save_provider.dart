import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/artwork.dart';
import '../models/artwork_document.dart';
import '../providers/underlay_layout_provider.dart';
import '../providers/underlay_provider.dart';
import '../services/auto_save_service.dart';
import '../services/thumbnail_capture_service.dart';
import 'artwork_repository_provider.dart';
import 'canvas_capture_provider.dart';
import 'canvas_provider.dart';

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
    captureThumbnail: () => thumbnailService.capture(captureKey),
  );

  ArtworkDocument currentDocument() {
    return ArtworkDocument.fromSession(
      artwork: ref.read(canvasProvider),
      documentsPath: repository.documentsPath,
      underlayAbsolutePath: ref.read(underlayProvider).imagePath,
      underlayLayout: ref.read(underlayLayoutProvider).value,
    );
  }

  ref.listen<Artwork>(canvasProvider, (previous, next) {
    service.scheduleSave(currentDocument());
  });
  ref.listen<UnderlayState>(underlayProvider, (previous, next) {
    service.scheduleSave(currentDocument());
  });

  // `underlayLayoutProvider` exposes a `ValueNotifier`, not a
  // `StateNotifier` — its own value changes never make the *provider*
  // itself emit, so `ref.listen` alone wouldn't see them (same reasoning
  // as `underlayFitCoordinatorProvider` listening to `CanvasSizeController`
  // directly). Listening to the controller itself catches every
  // opacity/visibility/placement change too.
  final underlayLayoutController = ref.read(underlayLayoutProvider);
  void onUnderlayLayoutChanged() => service.scheduleSave(currentDocument());
  underlayLayoutController.addListener(onUnderlayLayoutChanged);

  ref.onDispose(() {
    underlayLayoutController.removeListener(onUnderlayLayoutChanged);
    service.dispose();
  });

  return service;
});

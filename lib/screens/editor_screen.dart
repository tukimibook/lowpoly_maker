import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../models/artwork_document.dart';
import '../providers/auto_save_provider.dart';
import '../providers/canvas_background_provider.dart';
import '../providers/canvas_provider.dart';
import '../providers/canvas_size_provider.dart';
import '../providers/export_provider.dart';
import '../providers/gallery_provider.dart';
import '../providers/tessellation_provider.dart';
import '../providers/underlay_layout_provider.dart';
import '../providers/underlay_provider.dart';
import '../widgets/canvas/polygon_canvas.dart';
import '../widgets/toolbar/editor_toolbar.dart';

/// Canvas background colors for each [Brightness] choice offered by
/// [canvasBackgroundProvider]. Deliberately separate from the app's own
/// `Theme.of(context).colorScheme` (see `app.dart`) — this is the artist's
/// own choice for the editing surface, not the OS/app chrome setting.
const Color _lightCanvasBackground = Color(0xFFF5F5F5); // Colors.grey.shade100
const Color _darkCanvasBackground = Color(0xFF212121); // Colors.grey.shade900

/// The two Phase Hδ export destinations offered by [EditorScreen]'s app bar
/// menu — a private enum (rather than wiring each `PopupMenuItem`'s
/// `onTap` directly to `ExportController.exportToGallery`/
/// `exportViaShareSheet`) so both share one `PopupMenuButton.onSelected`
/// callback and the exact same "read the current artwork/canvasSize, then
/// dispatch" plumbing.
enum _ExportAction { gallery, share }

class EditorScreen extends ConsumerWidget {
  const EditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artwork = ref.watch(canvasProvider);
    final isEmpty = artwork.polygons.isEmpty && artwork.draftVertexIds.isEmpty;
    final canvasBrightness = ref.watch(canvasBackgroundProvider);
    final isCanvasDark = canvasBrightness == Brightness.dark;
    final underlayImagePath = ref.watch(underlayProvider.select((state) => state.imagePath));
    final isTessellating = ref.watch(isTessellatingProvider);
    // Activates auto-save (Phase Hγ) for the lifetime of this screen — see
    // that provider's own doc for why watching it once here is enough.
    ref.watch(autoSaveServiceProvider);

    // Picking success is now visible directly on the canvas (the underlay
    // is drawn immediately, fit to the canvas — see `UnderlayLayer`), so
    // only pick *failures* need a toast; only surfaces *changes*, so
    // re-opening the editor doesn't re-toast an error from a previous
    // session.
    ref.listen<UnderlayState>(underlayProvider, (previous, next) {
      if (next.errorMessage != null && next.errorMessage != previous?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.errorMessage!)));
      }
    });

    // Phase Hδ (#19): a failed/succeeded export never crashes — it always
    // becomes exactly one `SnackBar`, the same "state carries the message,
    // this listener just shows it once" pattern as the underlay listener
    // above. Guarded on identity-changed-from-null so re-entering this
    // screen doesn't re-toast a stale result from a previous visit.
    ref.listen<ExportState>(exportControllerProvider, (previous, next) {
      final message = next.errorMessage ?? next.successMessage;
      final previousMessage = previous?.errorMessage ?? previous?.successMessage;
      if (message != null && message != previousMessage) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    });
    final isExporting = ref.watch(exportControllerProvider.select((s) => s.isExporting));

    Future<void> handleExport(_ExportAction action) async {
      final currentArtwork = ref.read(canvasProvider);
      final canvasSize = ref.read(canvasSizeProvider).value;
      final controller = ref.read(exportControllerProvider.notifier);
      switch (action) {
        case _ExportAction.gallery:
          await controller.exportToGallery(currentArtwork, canvasSize);
        case _ExportAction.share:
          await controller.exportViaShareSheet(currentArtwork, canvasSize);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(artwork.title),
        actions: [
          IconButton(
            tooltip: underlayImagePath == null ? '下絵を選択' : '下絵を変更',
            onPressed: () => ref.read(underlayProvider.notifier).pickImage(),
            icon: Icon(underlayImagePath == null ? Icons.image_outlined : Icons.image),
          ),
          IconButton(
            tooltip: isCanvasDark ? 'キャンバスをライトに切り替え' : 'キャンバスをダークに切り替え',
            onPressed: () {
              ref.read(canvasBackgroundProvider.notifier).state =
                  isCanvasDark ? Brightness.light : Brightness.dark;
            },
            icon: Icon(isCanvasDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
          ),
          IconButton(
            tooltip: 'すべて消去',
            onPressed: isEmpty ? null : () => ref.read(canvasProvider.notifier).clearAll(),
            icon: const Icon(Icons.delete_outline),
          ),
          PopupMenuButton<_ExportAction>(
            key: const Key('export-menu-button'),
            tooltip: 'PNGを書き出す',
            enabled: !isEmpty && !isExporting,
            onSelected: handleExport,
            icon: isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share),
            itemBuilder: (context) => const [
              PopupMenuItem(
                key: Key('export-menu-gallery'),
                value: _ExportAction.gallery,
                child: ListTile(
                  leading: Icon(Icons.save_alt_outlined),
                  title: Text('ギャラリーに保存'),
                ),
              ),
              PopupMenuItem(
                key: Key('export-menu-share'),
                value: _ExportAction.share,
                child: ListTile(leading: Icon(Icons.share_outlined), title: Text('共有')),
              ),
            ],
          ),
          const _SaveAndExitButton(),
        ],
      ),
      // `Stack` overlay instead of `Scaffold.bottomNavigationBar` (2026-07-16
      // — see `.cursor/plans/plan_phase_H_alpha.md`): `PolygonCanvas` fills
      // the entire body, at a size that no longer depends on the toolbar's
      // height at all, so switching between draw/eraser/edit — whose
      // toolbar rows used to differ in height — can never again trigger
      // the underlay's fit-to-canvas recompute (`underlayFitCoordinatorProvider`
      // listens for `canvasSizeProvider`'s value to change) and make the
      // underlay visibly jump. `EditorToolbar` floats on top, at the
      // bottom, as a normal `Positioned` overlay.
      body: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: isCanvasDark ? _darkCanvasBackground : _lightCanvasBackground,
              child: const PolygonCanvas(),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ToolbarBarrier(child: EditorToolbar()),
          ),
          if (isTessellating) const Positioned.fill(child: _TessellationBlockingOverlay()),
        ],
      ),
    );
  }
}

/// 「即時保存して作品一覧へ戻る」(defect-fix #2): forces an immediate
/// (non-debounced) save via [AutoSaveService.flush] — including a freshly
/// captured thumbnail, same as any debounced auto-save — then discards the
/// entire navigation stack and returns to `GalleryScreen`, regardless of
/// how this `EditorScreen` was reached (`HomeScreen`'s direct shortcut or
/// `GalleryScreen`'s own 新規作成/開く).
///
/// A dedicated (`ConsumerStatefulWidget`) widget, not a stateless callback
/// on [EditorScreen] itself, purely to hold [_isSaving] — the local "is a
/// save+exit already in flight" flag that disables the button and swaps
/// in a spinner for its whole duration, so a second tap while the first
/// `flush()` is still awaiting can never fire a second, overlapping save
/// (and, worse, a second stack-clearing navigation).
class _SaveAndExitButton extends ConsumerStatefulWidget {
  const _SaveAndExitButton();

  @override
  ConsumerState<_SaveAndExitButton> createState() => _SaveAndExitButtonState();
}

class _SaveAndExitButtonState extends ConsumerState<_SaveAndExitButton> {
  bool _isSaving = false;

  Future<void> _handleSaveAndExit() async {
    if (_isSaving) return; // Belt-and-suspenders: onPressed is already null while true.
    setState(() => _isSaving = true);
    try {
      final autoSaveService = ref.read(autoSaveServiceProvider);
      if (autoSaveService != null) {
        final document = ArtworkDocument(
          artwork: ref.read(canvasProvider),
          underlayImagePath: ref.read(underlayProvider).imagePath,
          underlayLayout: ref.read(underlayLayoutProvider).value,
        );
        await autoSaveService.flush(document);
      }
      // The grid may still be showing this artwork's previous title/
      // thumbnail (or may not have this artwork at all yet, for a
      // brand-new one) — refresh so it reflects what was just saved the
      // moment it's shown.
      ref.invalidate(artworkIndexProvider);
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        PolygonArtApp.galleryRoute,
        (route) => false,
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('save-and-exit-button'),
      tooltip: '保存して作品一覧へ戻る',
      onPressed: _isSaving ? null : _handleSaveAndExit,
      icon: _isSaving
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.check_circle_outline),
    );
  }
}

/// Shown while `TessellationController.tessellate` (plan #17) has a
/// `compute()` call in flight. Placed as the topmost `Stack` child (above
/// both [PolygonCanvas] and `_ToolbarBarrier`) so its [AbsorbPointer]
/// claims every touch before either can see it — same "topmost layer wins
/// hit-testing" principle as `_ToolbarBarrier` itself — preventing any
/// artwork mutation while the background triangulation is still running.
class _TessellationBlockingOverlay extends StatelessWidget {
  const _TessellationBlockingOverlay();

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.3),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('分割しています…', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wraps [EditorToolbar] so every tap landing anywhere within its bounds —
/// including the gaps between icons/rows, not just the icons themselves —
/// is claimed here and never reaches [PolygonCanvas] underneath in the
/// `Stack` (`HitTestBehavior.opaque` makes this render object's own
/// `hitTest` succeed unconditionally for any position inside it, which is
/// exactly what makes `RenderStack` stop testing the sibling behind it —
/// see `.cursor/plans/plan_phase_H_alpha.md`, 2026-07-16 検討メモ).
///
/// This does *not* interfere with the toolbar's own buttons: hit-testing
/// always tests descendants first regardless of `behavior`, so every
/// `IconButton`/`SegmentedButton` inside still receives its own taps
/// normally. No `onTap`/other callback is needed here — `behavior` alone
/// governs whether this render object counts as "hit".
class _ToolbarBarrier extends StatelessWidget {
  const _ToolbarBarrier({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      child: Material(elevation: 8, child: child),
    );
  }
}

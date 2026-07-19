import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/canvas_background_provider.dart';
import '../providers/canvas_provider.dart';
import '../providers/tessellation_provider.dart';
import '../providers/underlay_provider.dart';
import '../widgets/canvas/polygon_canvas.dart';
import '../widgets/toolbar/editor_toolbar.dart';

/// Canvas background colors for each [Brightness] choice offered by
/// [canvasBackgroundProvider]. Deliberately separate from the app's own
/// `Theme.of(context).colorScheme` (see `app.dart`) — this is the artist's
/// own choice for the editing surface, not the OS/app chrome setting.
const Color _lightCanvasBackground = Color(0xFFF5F5F5); // Colors.grey.shade100
const Color _darkCanvasBackground = Color(0xFF212121); // Colors.grey.shade900

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
        ],
      ),
      // `Stack` overlay instead of `Scaffold.bottomNavigationBar` (2026-07-16
      // — see `.cursor/plans/plan_phase_H_alpha.md`): `PolygonCanvas` fills
      // the entire body, at a size that no longer depends on the toolbar's
      // height at all, so switching between draw/eraser/edit — whose
      // toolbar rows used to differ in height — can never again trigger
      // the underlay's fit-to-canvas recompute (`underlayFitCoordinatorProvider`
      // listens for `canvasProvider`'s `canvasSize` to change) and make the
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

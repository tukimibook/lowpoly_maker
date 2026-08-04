import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../providers/auto_save_provider.dart';
import '../providers/canvas_background_provider.dart';
import '../providers/canvas_provider.dart';
import '../providers/canvas_size_provider.dart';
import '../providers/export_provider.dart';
import '../providers/gallery_provider.dart';
import '../providers/preview_mode_provider.dart';
import '../providers/tessellation_provider.dart';
import '../providers/underlay_provider.dart';
import '../widgets/canvas/polygon_canvas.dart';
import '../widgets/toolbar/editor_toolbar.dart';
import '../widgets/toolbar/underlay_menu_button.dart';

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

enum _EditorMoreAction { toggleCanvasTheme, clearAll }

class EditorScreen extends ConsumerWidget {
  const EditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artwork = ref.watch(canvasProvider);
    final isEmpty = artwork.polygons.isEmpty && artwork.draftVertexIds.isEmpty;
    final canvasBrightness = ref.watch(canvasBackgroundProvider);
    final isCanvasDark = canvasBrightness == Brightness.dark;
    final isTessellating = ref.watch(isTessellatingProvider);
    final isPreview = ref.watch(isPreviewModeProvider);
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

    Future<void> handleRename() async {
      final controller = TextEditingController(text: artwork.title);
      final newTitle = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Rename artwork'),
            content: TextField(
              key: const Key('artwork-rename-field'),
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Title'),
              onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(controller.text),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
      // Dispose after the dialog route has finished unmounting its TextField,
      // otherwise the field may still notify the controller during exit.
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
      if (newTitle == null) return;
      ref.read(canvasProvider.notifier).setTitle(newTitle);
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        // Two IconButtons side-by-side (Home + Gallery); default leading
        // width (56) is only enough for one.
        leadingWidth: 96,
        leading: const _EditorExitButtons(),
        title: InkWell(
          key: const Key('artwork-title'),
          onTap: handleRename,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(artwork.title),
          ),
        ),
        actions: [
          const UnderlayMenuButton(),
          IconButton(
            key: const Key('preview-mode-button'),
            tooltip: isPreview ? 'Exit preview' : 'Preview artwork',
            onPressed: () {
              ref.read(isPreviewModeProvider.notifier).state = !isPreview;
            },
            icon: Icon(
              isPreview ? Icons.check_box_outlined : Icons.check_box_outline_blank,
            ),
          ),
          PopupMenuButton<_ExportAction>(
            key: const Key('export-menu-button'),
            tooltip: 'Export PNG',
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
                  title: Text('Save to gallery'),
                ),
              ),
              PopupMenuItem(
                key: Key('export-menu-share'),
                value: _ExportAction.share,
                child: ListTile(leading: Icon(Icons.share_outlined), title: Text('Share')),
              ),
            ],
          ),
          PopupMenuButton<_EditorMoreAction>(
            key: const Key('editor-more-menu-button'),
            tooltip: 'More',
            icon: const Icon(Icons.more_vert),
            onSelected: (action) {
              switch (action) {
                case _EditorMoreAction.toggleCanvasTheme:
                  ref.read(canvasBackgroundProvider.notifier).state =
                      isCanvasDark ? Brightness.light : Brightness.dark;
                case _EditorMoreAction.clearAll:
                  ref.read(canvasProvider.notifier).clearAll();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _EditorMoreAction.toggleCanvasTheme,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    isCanvasDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  ),
                  title: Text(isCanvasDark ? 'Light canvas' : 'Dark canvas'),
                ),
              ),
              PopupMenuItem(
                value: _EditorMoreAction.clearAll,
                enabled: !isEmpty,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline),
                  title: Text('Clear all'),
                ),
              ),
            ],
          ),
        ],
      ),
      // Column + Expanded so [PolygonCanvas] sizes to the usable area above
      // the fixed-height toolbar (centering / fit-to-canvas stay correct).
      // Toolbar height is constant (3 rows), so underlay fit no longer jumps
      // when switching modes — the historical reason for a full-bleed Stack.
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: isCanvasDark ? _darkCanvasBackground : _lightCanvasBackground,
                    child: const PolygonCanvas(),
                  ),
                ),
                if (isTessellating) const Positioned.fill(child: _TessellationBlockingOverlay()),
              ],
            ),
          ),
          const _ToolbarBarrier(child: EditorToolbar()),
        ],
      ),
    );
  }
}

/// AppBar exit controls: flush the current artwork, then leave the editor.
///
/// Spec (Phase Select / 死角2): the single ambiguous "back" control is
/// replaced by **two** destinations so Home-direct and Gallery-via stacks
/// never share one underspecified `popUntil`. Both buttons always call
/// [saveAndFlushCurrentDocument] before navigating.
///
/// - **Home** ([_ExitDestination.home]): `popUntil(isFirst)` — always the
///   root [HomeScreen], regardless of whether Gallery was beneath the
///   editor.
/// - **Gallery** ([_ExitDestination.gallery]): if a route named
///   [PolygonArtApp.galleryRoute] is already on the stack (Home → Gallery
///   → Editor), `popUntil` that route; otherwise pop to the root and
///   [Navigator.pushNamed] the gallery (Home → Editor with no Gallery
///   underneath). Preferring `push` over `pushReplacement` keeps Home as
///   the stack root.
///
/// A dedicated [ConsumerStatefulWidget] holds [_isSaving] so a second tap
/// while the first `flush()` is still awaiting cannot fire a second save
/// or a second navigation.
enum _ExitDestination { home, gallery }

class _EditorExitButtons extends ConsumerStatefulWidget {
  const _EditorExitButtons();

  @override
  ConsumerState<_EditorExitButtons> createState() => _EditorExitButtonsState();
}

class _EditorExitButtonsState extends ConsumerState<_EditorExitButtons> {
  bool _isSaving = false;
  _ExitDestination? _activeDestination;

  Future<void> _handleExit(_ExitDestination destination) async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
      _activeDestination = destination;
    });
    try {
      await saveAndFlushCurrentDocument(ref.read);
      // Refresh the gallery grid so title/thumbnail (or a brand-new entry)
      // match what was just flushed the moment the artist sees it.
      ref.invalidate(artworkIndexProvider);
      if (!mounted) return;

      final navigator = Navigator.of(context);
      switch (destination) {
        case _ExitDestination.home:
          navigator.popUntil((route) => route.isFirst);
        case _ExitDestination.gallery:
          var galleryInStack = false;
          navigator.popUntil((route) {
            if (route.settings.name == PolygonArtApp.galleryRoute) {
              galleryInStack = true;
              return true;
            }
            return route.isFirst;
          });
          if (!galleryInStack && mounted) {
            await navigator.pushNamed(PolygonArtApp.galleryRoute);
          }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _activeDestination = null;
        });
      }
    }
  }

  Widget _exitIconButton({
    required Key key,
    required _ExitDestination destination,
    required String tooltip,
    required IconData icon,
  }) {
    final showSpinner = _isSaving && _activeDestination == destination;
    return IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: _isSaving ? null : () => _handleExit(destination),
      icon: showSpinner
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, semanticLabel: tooltip),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _exitIconButton(
          key: const Key('save-and-go-home-button'),
          destination: _ExitDestination.home,
          tooltip: 'Return to Home',
          icon: Icons.home,
        ),
        _exitIconButton(
          key: const Key('save-and-go-gallery-button'),
          destination: _ExitDestination.gallery,
          tooltip: 'Go to Gallery',
          icon: Icons.photo_library,
        ),
      ],
    );
  }
}

/// Shown while `TessellationController.tessellate` (plan #17) has a
/// `compute()` call in flight. Placed above [PolygonCanvas] inside the
/// editor body's [Expanded] so its [AbsorbPointer] claims every touch
/// before the canvas can see it — preventing artwork mutation while the
/// background triangulation is still running.
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
              Text('Tessellating…', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wraps [EditorToolbar] so taps in the gaps between controls are absorbed
/// and never reach the canvas above in the [Column].
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

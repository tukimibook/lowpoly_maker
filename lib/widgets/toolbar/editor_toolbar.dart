import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/canvas_mode.dart';
import '../../models/polygon_shape.dart';
import '../../providers/canvas_provider.dart';
import '../../providers/drag_preview_provider.dart';
import '../../providers/selected_vertex_provider.dart';
import '../../providers/vertex_drag_preview_provider.dart';

/// Bottom toolbar for Phase 1.
///
/// Always shows the draw/eraser/edit mode switch. Below it, the controls
/// change completely depending on the selected mode so the three behaviors
/// never mix:
/// - Draw mode: fill color palette + undo / close polygon.
/// - Eraser mode: just a short instruction (tapping a vertex deletes it).
/// - Edit mode: short instruction (tap to select, long-press drag to move).
class EditorToolbar extends ConsumerWidget {
  const EditorToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(canvasModeProvider);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ModeSwitch(mode: mode),
            const SizedBox(height: 12),
            switch (mode) {
              CanvasMode.draw => const _DrawModeControls(),
              CanvasMode.eraser => const _EraserModeHint(),
              CanvasMode.edit => const _EditModeControls(),
            },
          ],
        ),
      ),
    );
  }
}

class _ModeSwitch extends ConsumerWidget {
  const _ModeSwitch({required this.mode});

  final CanvasMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SegmentedButton<CanvasMode>(
      segments: const [
        ButtonSegment(
          value: CanvasMode.draw,
          label: Text('描画'),
          icon: Icon(Icons.edit_outlined),
        ),
        ButtonSegment(
          value: CanvasMode.eraser,
          label: Text('消しゴム'),
          icon: Icon(Icons.backspace_outlined),
        ),
        ButtonSegment(
          value: CanvasMode.edit,
          label: Text('編集'),
          icon: Icon(Icons.open_with),
        ),
      ],
      selected: {mode},
      onSelectionChanged: (selection) {
        final newMode = selection.first;
        ref.read(canvasModeProvider.notifier).state = newMode;
        if (newMode != CanvasMode.edit) {
          ref.read(selectedVertexProvider.notifier).state = null;
          ref.read(vertexDragPreviewProvider).value = null;
        }
        if (newMode != CanvasMode.draw) {
          ref.read(dragPreviewProvider).value = null;
        }
      },
    );
  }
}

class _DrawModeControls extends ConsumerWidget {
  const _DrawModeControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artwork = ref.watch(canvasProvider);
    final notifier = ref.read(canvasProvider.notifier);
    final selectedColor = ref.watch(selectedFillColorProvider);

    final canUndo = notifier.canUndo;
    final canClose = artwork.draftVertexIds.length >= kMinPolygonVertices;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kDefaultPolygonPalette.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final color = kDefaultPolygonPalette[index];
              final isSelected = color == selectedColor;
              return GestureDetector(
                onTap: () => ref.read(selectedFillColorProvider.notifier).state = color,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.black87 : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: canUndo ? notifier.undo : null,
                icon: const Icon(Icons.undo),
                label: const Text('元に戻す'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: canClose ? () => notifier.closePolygon(selectedColor) : null,
                icon: const Icon(Icons.check),
                label: const Text('閉じる'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EraserModeHint extends StatelessWidget {
  const _EraserModeHint();

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: errorColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '消したい頂点をタップしてください（1点ずつ削除されます）',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: errorColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditModeControls extends ConsumerWidget {
  const _EditModeControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(canvasProvider);
    final selectedVertexId = ref.watch(selectedVertexProvider);
    final notifier = ref.read(canvasProvider.notifier);
    final canUndo = notifier.canUndo;
    final color = Theme.of(context).colorScheme.primary;

    final showDetach = selectedVertexId != null &&
        notifier.isVertexShared(selectedVertexId);
    final referencingPolygons = showDetach
        ? notifier.polygonsReferencing(selectedVertexId)
        : const <PolygonShape>[];
    final draftReferences = showDetach &&
        notifier.draftReferencesVertex(selectedVertexId);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'タップで選択、長押しドラッグで移動。別の頂点をタップで溶接。共有の角は下のボタンで切り離し',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
        if (showDetach) ...[
          Text(
            'この頂点を切り離す:',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final polygon in referencingPolygons)
                OutlinedButton(
                  onPressed: () {
                    final copyId = notifier.detachVertexFromPolygon(
                      selectedVertexId,
                      polygon.id,
                    );
                    if (copyId != null) {
                      ref.read(selectedVertexProvider.notifier).state = copyId;
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 36),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: polygon.fillColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black26),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text('ポリゴン'),
                    ],
                  ),
                ),
              if (draftReferences)
                OutlinedButton(
                  onPressed: () {
                    final copyId = notifier.detachVertexFromDraft(
                      selectedVertexId,
                    );
                    if (copyId != null) {
                      ref.read(selectedVertexProvider.notifier).state = copyId;
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 36),
                  ),
                  child: const Text('下書き'),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          onPressed: canUndo ? notifier.undo : null,
          icon: const Icon(Icons.undo),
          label: const Text('元に戻す'),
        ),
      ],
    );
  }
}

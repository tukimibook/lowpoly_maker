import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/canvas_mode.dart';
import '../../providers/canvas_provider.dart';

/// Bottom toolbar for Phase 1.
///
/// Always shows the draw/eraser mode switch. Below it, the controls change
/// completely depending on the selected mode so the two behaviors never mix:
/// - Draw mode: fill color palette + undo last point / close polygon.
/// - Eraser mode: just a short instruction (tapping a vertex deletes it).
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
            if (mode == CanvasMode.draw) const _DrawModeControls() else const _EraserModeHint(),
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
      ],
      selected: {mode},
      onSelectionChanged: (selection) {
        ref.read(canvasModeProvider.notifier).state = selection.first;
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

    final canUndo = artwork.draftVertexIds.isNotEmpty;
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
                onPressed: canUndo ? notifier.undoLastVertex : null,
                icon: const Icon(Icons.undo),
                label: const Text('1点戻す'),
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

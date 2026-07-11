import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/canvas_background_provider.dart';
import '../providers/canvas_provider.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: Text(artwork.title),
        actions: [
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
      body: ColoredBox(
        color: isCanvasDark ? _darkCanvasBackground : _lightCanvasBackground,
        child: const PolygonCanvas(),
      ),
      bottomNavigationBar: const Material(
        elevation: 8,
        child: EditorToolbar(),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/canvas_provider.dart';
import '../widgets/canvas/polygon_canvas.dart';
import '../widgets/toolbar/editor_toolbar.dart';

class EditorScreen extends ConsumerWidget {
  const EditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artwork = ref.watch(canvasProvider);
    final isEmpty = artwork.polygons.isEmpty && artwork.draftVertices.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(artwork.title),
        actions: [
          IconButton(
            tooltip: 'すべて消去',
            onPressed: isEmpty ? null : () => ref.read(canvasProvider.notifier).clearAll(),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ColoredBox(
        color: Colors.grey.shade100,
        child: const PolygonCanvas(),
      ),
      bottomNavigationBar: const Material(
        elevation: 8,
        child: EditorToolbar(),
      ),
    );
  }
}

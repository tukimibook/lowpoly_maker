import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../geometry/tessellation_input.dart';
import '../../models/canvas_mode.dart';
import '../../models/draw_mode.dart';
import '../../models/shade_tool.dart';
import '../../providers/canvas_provider.dart';
import '../../providers/detach_cycle_provider.dart';
import '../../providers/polygon_edit_target_provider.dart';
import '../../providers/preview_mode_provider.dart';
import '../../providers/selected_vertex_provider.dart';
import '../../providers/shade_session_provider.dart';
import '../../providers/tessellation_provider.dart';
import '../../providers/viewport_provider.dart';
import 'fill_color_palette.dart';

/// Height each context / common row reserves.
const double _kRowHeight = 64;

/// Height of the conditional fill-color palette strip (Row 2).
const double _kPaletteRowHeight = 52;

/// Bottom toolbar: work-mode controls only (environment settings live in
/// the AppBar — underlay, preview, export, theme/clear).
///
/// - Row 0: Draw/Edit toggle, fit-screen, undo.
/// - Row 1: mode-specific context (draw close / edit shape tools).
/// - Row 2: [FillColorPalette] strip (always reserves height).
class EditorToolbar extends ConsumerWidget {
  const EditorToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(canvasModeProvider);

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _CommonRow(),
          const Divider(height: 1),
          switch (mode) {
            CanvasMode.draw => const _DrawModeContextRow(),
            CanvasMode.eraser => const _EraserModeRow(),
            CanvasMode.edit => const _EditModeContextRow(),
            CanvasMode.shade => const _ShadeModeContextRow(),
          },
          const _PaletteRow(),
        ],
      ),
    );
  }
}

/// Row 0: Draw/Edit toggle, fit-screen, undo.
class _CommonRow extends ConsumerWidget {
  const _CommonRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(canvasModeProvider);
    ref.watch(canvasProvider);
    final canUndo = ref.read(canvasProvider.notifier).canUndo;

    void selectMode(CanvasMode newMode) {
      ref.read(canvasModeProvider.notifier).state = newMode;
      ref.read(isPreviewModeProvider.notifier).state = false;
      clearGesturePreviews(ref.read);
      if (newMode != CanvasMode.edit) {
        clearEditSelectionUi(ref.read);
      } else {
        ref.read(weldArmedProvider.notifier).state = false;
      }
      // Phase Select: clear shade selection + ramp when leaving shade
      // (paired with gallery_provider open/new).
      if (newMode != CanvasMode.shade) {
        clearShadeSessionUi(ref.read);
      }
    }

    // Eraser is no longer offered in the UI; map it to Draw for the chip.
    final selectedMode = mode == CanvasMode.eraser ? CanvasMode.draw : mode;

    return SizedBox(
      height: _kRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<CanvasMode>(
                  segments: const [
                    ButtonSegment(
                      value: CanvasMode.draw,
                      icon: Icon(Icons.draw_outlined),
                      tooltip: 'Draw',
                    ),
                    ButtonSegment(
                      value: CanvasMode.edit,
                      icon: Icon(Icons.open_with),
                      tooltip: 'Edit',
                    ),
                    ButtonSegment(
                      value: CanvasMode.shade,
                      icon: Icon(Icons.gradient),
                      tooltip: 'Shade',
                    ),
                  ],
                  selected: {selectedMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) => selectMode(selection.first),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Fit screen',
              onPressed: ref.read(viewportProvider).reset,
              icon: const Icon(Icons.fit_screen),
            ),
            IconButton(
              tooltip: 'Undo',
              onPressed: canUndo ? ref.read(canvasProvider.notifier).undo : null,
              icon: const Icon(Icons.undo),
            ),
          ],
        ),
      ),
    );
  }
}

/// Row 1, draw mode: tap/trace toggle + close. Palette lives in [_PaletteRow].
class _DrawModeContextRow extends ConsumerWidget {
  const _DrawModeContextRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artwork = ref.watch(canvasProvider);
    final notifier = ref.read(canvasProvider.notifier);
    final selectedColor = ref.watch(selectedFillColorProvider);
    final drawMode = ref.watch(drawModeProvider);
    final canClose = artwork.draftVertexIds.length >= kMinPolygonVertices;
    final viewportScale = ref.read(viewportProvider).value.scale;

    void selectDrawMode(DrawMode newDrawMode) {
      ref.read(drawModeProvider.notifier).state = newDrawMode;
      clearGesturePreviews(ref.read);
    }

    return SizedBox(
      height: _kRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            SegmentedButton<DrawMode>(
              segments: const [
                ButtonSegment(
                  value: DrawMode.tap,
                  icon: Icon(Icons.touch_app_outlined),
                  tooltip: 'Tap',
                ),
                ButtonSegment(
                  value: DrawMode.trace,
                  icon: Icon(Icons.gesture),
                  tooltip: 'Trace',
                ),
              ],
              selected: {drawMode},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => selectDrawMode(selection.first),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Close shape',
              iconSize: 32,
              onPressed: canClose
                  ? () {
                      final result = notifier.closePolygon(
                        selectedColor,
                        lineAbsorptionTolerance:
                            kLineAbsorptionTolerance / viewportScale,
                      );
                      if (result ==
                          ClosePolygonResult.rejectedUnsafeClosingEdge) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(kClosePolygonRejectedMessage),
                          ),
                        );
                      }
                    }
                  : null,
              icon: const Icon(Icons.check_circle),
            ),
          ],
        ),
      ),
    );
  }
}

/// Row 1, eraser mode: non-interactive reminder.
class _EraserModeRow extends StatelessWidget {
  const _EraserModeRow();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return SizedBox(
      height: _kRowHeight,
      child: Center(
        child: Tooltip(
          message: 'Tap a vertex to erase',
          child: Icon(Icons.delete_outline, size: 28, color: color),
        ),
      ),
    );
  }
}

/// Row 1, edit mode: one shared skeleton for every selection state.
///
/// - Left (fixed): Cycle Shape — always present so buried polygons
///   remain reachable via cycling (Z-order rescue).
/// - Center ([Expanded] + horizontal scroll): hint / edge tools / vertex
///   tools depending on selection.
/// - Right (fixed): More (⋯) while a polygon is targeted with no vertex;
///   empty while a vertex is selected.
class _EditModeContextRow extends ConsumerWidget {
  const _EditModeContextRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artwork = ref.watch(canvasProvider);
    final notifier = ref.read(canvasProvider.notifier);
    final selectedVertexId = ref.watch(selectedVertexProvider);
    final polygonIndex = ref.watch(polygonCycleIndexProvider);
    final edgeIndex = ref.watch(edgeCycleIndexProvider);
    final weldArmed = ref.watch(weldArmedProvider);
    final isTessellating = ref.watch(isTessellatingProvider);

    final targetPolygonId = resolvePolygonTarget(
      polygons: artwork.polygons,
      rawCycleIndex: polygonIndex,
    );
    final targetPolygon =
        artwork.polygons.where((p) => p.id == targetPolygonId).firstOrNull;
    final targetEdge = targetPolygon == null
        ? null
        : resolveEdgeTarget(polygon: targetPolygon, rawCycleIndex: edgeIndex);

    final hasVertex = selectedVertexId != null;
    final hasPolygon = targetPolygonId != null && !hasVertex;
    final colorScheme = Theme.of(context).colorScheme;

    void cyclePolygon() {
      // Drop vertex selection first so the highlight / toolbar don't disagree
      // about which layer is active after the cycle advances.
      if (ref.read(selectedVertexProvider) != null) {
        clearEditSelectionUi(ref.read, resetWholeShapeCycles: false);
      }
      final current = ref.read(polygonCycleIndexProvider);
      ref.read(polygonCycleIndexProvider.notifier).state = current + 1;
      ref.read(edgeCycleIndexProvider.notifier).state = -1;
    }

    void cycleEdge() {
      ref.read(edgeCycleIndexProvider.notifier).state = edgeIndex + 1;
    }

    void addVertexAtEdge() {
      final edge = targetEdge;
      final polygonId = targetPolygonId;
      if (edge == null || polygonId == null) return;
      final newVertexId = notifier.insertVertexAtEdge(polygonId, edge.ringIndex);
      if (newVertexId != null) {
        ref.read(selectedVertexProvider.notifier).state = newVertexId;
      }
      ref.read(polygonCycleIndexProvider.notifier).state = -1;
      ref.read(edgeCycleIndexProvider.notifier).state = -1;
    }

    void deleteSelectedVertex() {
      final id = selectedVertexId;
      if (id == null) return;
      final position = artwork.vertices[id]?.position;
      if (position == null) return;
      // Reuses the eraser path (undo + dissolve rules) without new notifier API.
      notifier.handleEraseTap(position);
      clearEditSelectionUi(ref.read, resetWholeShapeCycles: false);
    }

    void deleteTargetPolygon() {
      final polygonId = targetPolygonId;
      if (polygonId == null) return;
      notifier.deletePolygon(polygonId);
      ref.read(polygonCycleIndexProvider.notifier).state = -1;
      ref.read(edgeCycleIndexProvider.notifier).state = -1;
    }

    Future<void> tessellateTargetPolygon() async {
      final polygonId = targetPolygonId;
      if (polygonId == null) return;
      final rejectReason =
          await ref.read(tessellationControllerProvider).tessellate(polygonId);
      ref.read(polygonCycleIndexProvider.notifier).state = -1;
      ref.read(edgeCycleIndexProvider.notifier).state = -1;
      if (rejectReason != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_describeTessellationRejection(rejectReason))),
        );
      }
    }

    final List<Widget> middleChildren;
    if (hasVertex) {
      final vertexId = selectedVertexId;
      middleChildren = [
        IconButton(
          key: const Key('delete-selected-vertex-button'),
          tooltip: 'Delete Vertex',
          iconSize: 28,
          color: colorScheme.error,
          onPressed: deleteSelectedVertex,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        IconButton(
          key: const Key('weld-vertices-button'),
          tooltip: 'Weld vertices',
          iconSize: 28,
          color: weldArmed ? colorScheme.primary : null,
          style: weldArmed
              ? IconButton.styleFrom(
                  foregroundColor: colorScheme.onPrimaryContainer,
                  backgroundColor: colorScheme.primaryContainer,
                )
              : null,
          onPressed: () {
            ref.read(weldArmedProvider.notifier).state = true;
            final messenger = ScaffoldMessenger.of(context);
            messenger.clearSnackBars();
            messenger.showSnackBar(
              const SnackBar(content: Text('Tap a vertex to weld')),
            );
          },
          icon: const Icon(Icons.merge_type),
        ),
        if (notifier.isVertexShared(vertexId))
          _DetachControls(selectedVertexId: vertexId)
        else
          Tooltip(
            message: 'Tap to select, long-press drag to move',
            child: Icon(
              Icons.touch_app_outlined,
              size: 28,
              color: colorScheme.primary,
            ),
          ),
      ];
    } else if (hasPolygon) {
      middleChildren = [
        IconButton(
          tooltip: 'Cycle Edge',
          iconSize: 28,
          onPressed: cycleEdge,
          icon: const Icon(Icons.skip_next),
        ),
        IconButton(
          tooltip: 'Add Vertex',
          iconSize: 28,
          onPressed: targetEdge == null ? null : addVertexAtEdge,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ];
    } else {
      middleChildren = [
        Text(
          'Tap a shape to select',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
        ),
      ];
    }

    return SizedBox(
      height: _kRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Cycle Shape',
              iconSize: 28,
              onPressed: artwork.polygons.isEmpty ? null : cyclePolygon,
              icon: const Icon(Icons.category_outlined),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: middleChildren,
                ),
              ),
            ),
            if (hasPolygon)
              PopupMenuButton<_PolygonMoreAction>(
                key: const Key('polygon-more-menu-button'),
                tooltip: 'More',
                icon: const Icon(Icons.more_horiz),
                onSelected: (action) {
                  switch (action) {
                    case _PolygonMoreAction.delete:
                      deleteTargetPolygon();
                    case _PolygonMoreAction.tessellate:
                      tessellateTargetPolygon();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: _PolygonMoreAction.delete,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline),
                      title: Text('Delete Shape'),
                    ),
                  ),
                  PopupMenuItem(
                    key: const Key('tessellate-target-polygon-button'),
                    value: _PolygonMoreAction.tessellate,
                    enabled: !isTessellating,
                    child: const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.change_history),
                      title: Text('Tessellate'),
                    ),
                  ),
                ],
              ),
            if (hasVertex)
              IconButton(
                tooltip: 'Clear selection',
                iconSize: 28,
                onPressed: () {
                  clearEditSelectionUi(ref.read, resetWholeShapeCycles: false);
                },
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ),
    );
  }
}

enum _PolygonMoreAction { delete, tessellate }

/// Detach cycle/execute pair for a shared selected vertex.
class _DetachControls extends ConsumerWidget {
  const _DetachControls({required this.selectedVertexId});

  final String selectedVertexId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(canvasProvider.notifier);
    final referencingPolygons = notifier.polygonsReferencing(selectedVertexId);
    final draftReferences = notifier.draftReferencesVertex(selectedVertexId);
    final cycleIndex = ref.watch(detachCycleIndexProvider);
    final target = resolveDetachTarget(
      referencingPolygons: referencingPolygons,
      draftReferences: draftReferences,
      rawCycleIndex: cycleIndex,
    );

    void cycleTarget() {
      ref.read(detachCycleIndexProvider.notifier).state = cycleIndex + 1;
    }

    void executeDetach() {
      final currentTarget = target;
      if (currentTarget == null) return;
      final copyId = currentTarget.isDraft
          ? notifier.detachVertexFromDraft(selectedVertexId)
          : notifier.detachVertexFromPolygon(
              selectedVertexId,
              currentTarget.polygonId!,
            );
      if (copyId != null) {
        ref.read(selectedVertexProvider.notifier).state = copyId;
      }
      ref.read(detachCycleIndexProvider.notifier).state = 0;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Cycle detach target',
          iconSize: 32,
          onPressed: cycleTarget,
          icon: const Icon(Icons.autorenew),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Detach',
          iconSize: 32,
          onPressed: target == null ? null : executeDetach,
          icon: const Icon(Icons.content_cut),
        ),
      ],
    );
  }
}

/// Row 1 while in [CanvasMode.shade]: solid / select / light sub-tools.
class _ShadeModeContextRow extends ConsumerWidget {
  const _ShadeModeContextRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shadeTool = ref.watch(shadeToolProvider);

    return SizedBox(
      height: _kRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<ShadeTool>(
            segments: const [
              ButtonSegment(
                value: ShadeTool.solid,
                icon: Icon(Icons.format_color_fill),
                tooltip: 'Solid fill',
              ),
              ButtonSegment(
                value: ShadeTool.select,
                icon: Icon(Icons.touch_app_outlined),
                tooltip: 'Select range',
              ),
              ButtonSegment(
                value: ShadeTool.light,
                icon: Icon(Icons.wb_sunny_outlined),
                tooltip: 'Light origin',
              ),
            ],
            selected: {shadeTool},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              ref.read(shadeToolProvider.notifier).state = selection.first;
            },
          ),
        ),
      ),
    );
  }
}

/// Row 2: fill palette when draw mode, or edit with a polygon target and
/// no vertex selected, or shade (base / solid color). Always reserves
/// [_kPaletteRowHeight].
class _PaletteRow extends ConsumerWidget {
  const _PaletteRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(canvasModeProvider);
    final selectedVertexId = ref.watch(selectedVertexProvider);
    final artwork = ref.watch(canvasProvider);
    final polygonIndex = ref.watch(polygonCycleIndexProvider);
    final penColor = ref.watch(selectedFillColorProvider);

    final targetPolygonId = resolvePolygonTarget(
      polygons: artwork.polygons,
      rawCycleIndex: polygonIndex,
    );
    final targetPolygon =
        artwork.polygons.where((p) => p.id == targetPolygonId).firstOrNull;

    final showDrawPalette = mode == CanvasMode.draw;
    final showShadePalette = mode == CanvasMode.shade;
    final showEditPalette = mode == CanvasMode.edit &&
        selectedVertexId == null &&
        targetPolygon != null;

    final highlighted = (showDrawPalette || showShadePalette)
        ? penColor
        : targetPolygon?.fillColor;

    return SizedBox(
      height: _kPaletteRowHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: (!showDrawPalette && !showEditPalette && !showShadePalette)
            ? const SizedBox.expand()
            : FillColorPalette(
                key: const Key('fill-color-palette'),
                colors: kDefaultPolygonPalette,
                highlightedColor: highlighted,
                onColorSelected: (color) {
                  if (showDrawPalette || showShadePalette) {
                    ref.read(selectedFillColorProvider.notifier).state = color;
                    return;
                  }
                  final id = targetPolygonId;
                  if (id == null) return;
                  ref.read(canvasProvider.notifier).changePolygonColor(id, color);
                },
              ),
      ),
    );
  }
}

String _describeTessellationRejection(TessellationRejectReason reason) {
  switch (reason) {
    case TessellationRejectReason.tooFewVertices:
      return 'Too few vertices to tessellate';
    case TessellationRejectReason.selfIntersecting:
      return 'Shape is self-intersecting';
    case TessellationRejectReason.computeFailed:
      return 'Tessellation failed. Please try again.';
  }
}

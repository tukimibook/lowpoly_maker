import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../geometry/polygon_shading.dart';
import '../../geometry/tessellation_input.dart';
import '../../models/canvas_mode.dart';
import '../../models/draw_mode.dart';
import '../../models/shade_tool.dart';
import '../../providers/canvas_provider.dart';
import '../../providers/detach_cycle_provider.dart';
import '../../providers/polygon_edit_target_provider.dart';
import '../../providers/preview_mode_provider.dart';
import '../../providers/selected_vertex_provider.dart';
import '../../providers/selection_drag_provider.dart';
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
///   tools depending on selection. When a polygon is targeted (no vertex),
///   Tessellate and Delete Shape trail the edge tools (Delete last).
/// - Right (fixed): Clear selection while a vertex is selected; empty
///   otherwise.
class _EditModeContextRow extends ConsumerWidget {
  const _EditModeContextRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artwork = ref.watch(canvasProvider);
    final notifier = ref.read(canvasProvider.notifier);
    final selectedVertexId = ref.watch(selectedVertexProvider);
    final editTarget = ref.watch(editTargetProvider);
    final weldArmed = ref.watch(weldArmedProvider);
    final isTessellating = ref.watch(isTessellatingProvider);

    final targetPolygonId = editTarget.polygonId;
    final targetEdge = editTarget.edge;

    final hasVertex = selectedVertexId != null;
    final hasPolygon = targetPolygonId != null && !hasVertex;
    final colorScheme = Theme.of(context).colorScheme;

    void cyclePolygon() {
      // Drop vertex selection first so the highlight / toolbar don't disagree
      // about which layer is active after the cycle advances.
      if (ref.read(selectedVertexProvider) != null) {
        clearEditSelectionUi(ref.read, resetWholeShapeCycles: false);
      }
      ref.read(editSelectionProvider.notifier).cyclePolygon();
    }

    void cycleEdge() {
      ref.read(editSelectionProvider.notifier).cycleEdge();
    }

    void addVertexAtEdge() {
      final edge = targetEdge;
      final polygonId = targetPolygonId;
      if (edge == null || polygonId == null) return;
      final newVertexId = notifier.insertVertexAtEdge(polygonId, edge.ringIndex);
      if (newVertexId != null) {
        ref.read(selectedVertexProvider.notifier).state = newVertexId;
      }
      ref.read(editSelectionProvider.notifier).clearBoth();
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
      ref.read(editSelectionProvider.notifier).clearBoth();
    }

    Future<void> tessellateTargetPolygon() async {
      final polygonId = targetPolygonId;
      if (polygonId == null) return;
      final rejectReason =
          await ref.read(tessellationControllerProvider).tessellate(polygonId);
      ref.read(editSelectionProvider.notifier).clearBoth();
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
        IconButton(
          key: const Key('tessellate-target-polygon-button'),
          tooltip: 'Tessellate',
          iconSize: 28,
          onPressed: isTessellating ? null : tessellateTargetPolygon,
          icon: const Icon(Icons.change_history),
        ),
        // Physical gap so Tessellate and Delete are harder to mis-tap.
        const SizedBox(width: 32),
        IconButton(
          key: const Key('delete-target-polygon-button'),
          tooltip: 'Delete Shape',
          iconSize: 28,
          color: colorScheme.error,
          onPressed: deleteTargetPolygon,
          icon: const Icon(Icons.delete_outline),
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

/// Row 1 while in [CanvasMode.shade]: solid / select / light sub-tools,
/// plus clear-all on the trailing edge (Wave 3.2.1).
class _ShadeModeContextRow extends ConsumerWidget {
  const _ShadeModeContextRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shadeTool = ref.watch(shadeToolProvider);
    // Watch the provider only to obtain the stable controller — membership
    // changes must not rebuild this whole row (ListenableBuilder below).
    final selectionDrag = ref.watch(selectionDragProvider);

    return SizedBox(
      height: _kRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            SegmentedButton<ShadeTool>(
              segments: const [
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
                ButtonSegment(
                  value: ShadeTool.solid,
                  icon: Icon(Icons.format_color_fill),
                  tooltip: 'Solid fill',
                ),
              ],
              selected: {shadeTool},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                ref.read(shadeToolProvider.notifier).state = selection.first;
              },
            ),
            const Spacer(),
            ListenableBuilder(
              listenable: selectionDrag,
              builder: (context, _) {
                final hasSelection = selectionDrag.value.isNotEmpty;
                return IconButton(
                  key: const Key('shade-clear-selection-button'),
                  tooltip: 'Clear selection',
                  iconSize: 28,
                  onPressed: hasSelection ? selectionDrag.clear : null,
                  icon: const Icon(
                    Icons.deselect,
                    semanticLabel: 'Clear selection',
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Row 2: fill palette in Draw (pen) or Shade (base / solid). Edit never
/// shows a palette — recoloring existing shapes is Shade-only, so an
/// accidental Edit-mode swatch tap cannot change a targeted polygon.
/// Always reserves [_kPaletteRowHeight].
class _PaletteRow extends ConsumerWidget {
  const _PaletteRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(canvasModeProvider);
    final penColor = ref.watch(selectedFillColorProvider);
    final activeBase = ref.watch(activeBaseColorProvider);

    final showDrawPalette = mode == CanvasMode.draw;
    final showShadePalette = mode == CanvasMode.shade;
    final showPalette = showDrawPalette || showShadePalette;

    // Shade: clear + presets, with optional accordion around activeBase.
    // Draw never includes [kClearFillColor] (pen color only).
    final List<Color> paletteColors;
    final List<Key>? itemKeys;
    int? familyStart;
    int? familyEnd;
    int? scrollToIndex;

    if (showShadePalette) {
      final built = _buildShadePalette(activeBase);
      paletteColors = built.colors;
      itemKeys = built.keys;
      familyStart = built.familyStart;
      familyEnd = built.familyEnd;
      scrollToIndex = built.anchorIndex;
    } else {
      paletteColors = kDefaultPolygonPalette;
      itemKeys = [
        for (final c in kDefaultPolygonPalette) ValueKey(('base', c)),
      ];
    }

    return SizedBox(
      height: _kPaletteRowHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: !showPalette
            ? const SizedBox.expand()
            : FillColorPalette(
                key: const Key('fill-color-palette'),
                colors: paletteColors,
                itemKeys: itemKeys,
                familyStart: familyStart,
                familyEnd: familyEnd,
                scrollToIndex: scrollToIndex,
                highlightedColor: penColor,
                onColorSelected: (color) {
                  ref.read(selectedFillColorProvider.notifier).state = color;
                  if (showShadePalette &&
                      kDefaultPolygonPalette.contains(color)) {
                    ref.read(activeBaseColorProvider.notifier).state = color;
                  }
                },
              ),
      ),
    );
  }
}

/// Shade strip: `[clear, …bases…]` with optional
/// `[…, lighter, base, dark…, …]` accordion around [activeBase].
({
  List<Color> colors,
  List<Key> keys,
  int? familyStart,
  int? familyEnd,
  int? anchorIndex,
}) _buildShadePalette(Color? activeBase) {
  final colors = <Color>[kClearFillColor];
  final keys = <Key>[const ValueKey('clear')];

  AccordionPaletteExpansion? expansion;
  if (activeBase != null && kDefaultPolygonPalette.contains(activeBase)) {
    expansion = buildAccordionPaletteExpansion(activeBase);
  }

  int? familyStart;
  int? familyEnd;
  int? anchorIndex;

  for (final base in kDefaultPolygonPalette) {
    if (expansion != null && base == activeBase) {
      familyStart = colors.length;
      colors.add(expansion.lighter);
      keys.add(ValueKey(('ramp', base, 'L')));

      anchorIndex = colors.length;
      colors.add(base);
      keys.add(ValueKey(('base', base)));

      for (var i = 0; i < expansion.darkers.length; i++) {
        colors.add(expansion.darkers[i]);
        keys.add(ValueKey(('ramp', base, i)));
      }
      familyEnd = colors.length - 1;
    } else {
      colors.add(base);
      keys.add(ValueKey(('base', base)));
    }
  }

  return (
    colors: colors,
    keys: keys,
    familyStart: familyStart,
    familyEnd: familyEnd,
    anchorIndex: anchorIndex,
  );
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

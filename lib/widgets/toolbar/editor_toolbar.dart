import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/canvas_mode.dart';
import '../../models/underlay_layout.dart';
import '../../providers/canvas_provider.dart';
import '../../providers/detach_cycle_provider.dart';
import '../../providers/drag_preview_provider.dart';
import '../../providers/polygon_edit_target_provider.dart';
import '../../providers/selected_vertex_provider.dart';
import '../../providers/underlay_layout_provider.dart';
import '../../providers/underlay_provider.dart';
import '../../providers/vertex_drag_preview_provider.dart';
import '../../providers/viewport_provider.dart';

/// Height each row (common + mode-specific) reserves. Two rows land the
/// whole bar in the ~120–150px "ゆったりとしたスペース" range agreed for a
/// global, icon-only design (`.cursor/plans/plan_phase_H_alpha.md`,
/// 2026-07-16 検討メモ) without needing to hard-code the bar's total
/// height anywhere — [EditorScreen] no longer cares what this adds up to
/// at all, since the `Stack` overlay structure keeps the canvas's own size
/// independent of it regardless (see that file's doc comment).
const double _kRowHeight = 64;

/// Bottom toolbar: two fixed-height rows, entirely icon-driven (no visible
/// text anywhere — every control's accessible name lives in its
/// [Tooltip]/`tooltip:` only), so the UI reads the same regardless of the
/// user's language.
///
/// - Row 1 is identical in every mode: the draw/eraser/edit switch, the
///   underlay's visibility/opacity toggles (moved here from the old
///   "下絵設定" modal sheet, removed 2026-07-16, so both are a single tap
///   away instead of buried in a sheet), and undo.
/// - Row 2 changes completely depending on [CanvasMode], mirroring the
///   previous version's design (draw/eraser/edit each get their own
///   sub-widget below) but every control is now a single icon-only toggle
///   rather than a row of separate buttons — see [_EditModeRow] in
///   particular, which condenses what used to be "one button per shared
///   polygon" into a fixed two-button cycle/execute pair.
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
            CanvasMode.draw => const _DrawModeRow(),
            CanvasMode.eraser => const _EraserModeRow(),
            CanvasMode.edit => const _EditModeRow(),
          },
        ],
      ),
    );
  }
}

/// Row 1: always the same three mode icons, plus the underlay's
/// visibility/opacity toggles and undo. See [EditorToolbar]'s doc for why
/// this row never changes shape between modes.
class _CommonRow extends ConsumerWidget {
  const _CommonRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(canvasModeProvider);
    final hasUnderlay = ref.watch(underlayProvider.select((state) => state.imagePath != null));
    final underlayController = ref.watch(underlayLayoutProvider);
    // Watched only to keep `canUndo` (read below) fresh after every
    // artwork mutation — mirrors the pre-existing `_DrawModeControls`/
    // `_EditModeControls` pattern this replaces.
    ref.watch(canvasProvider);
    final canUndo = ref.read(canvasProvider.notifier).canUndo;

    void selectMode(CanvasMode newMode) {
      ref.read(canvasModeProvider.notifier).state = newMode;
      if (newMode != CanvasMode.edit) {
        ref.read(selectedVertexProvider.notifier).state = null;
        ref.read(detachCycleIndexProvider.notifier).state = 0;
        ref.read(polygonCycleIndexProvider.notifier).state = -1;
        ref.read(edgeCycleIndexProvider.notifier).state = -1;
        ref.read(vertexDragPreviewProvider).value = null;
      }
      if (newMode != CanvasMode.draw) {
        ref.read(dragPreviewProvider).value = null;
      }
    }

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
                      tooltip: '描画モード',
                    ),
                    ButtonSegment(
                      value: CanvasMode.eraser,
                      icon: Icon(Icons.backspace_outlined),
                      tooltip: '消しゴムモード',
                    ),
                    ButtonSegment(
                      value: CanvasMode.edit,
                      icon: Icon(Icons.open_with),
                      tooltip: '編集モード',
                    ),
                  ],
                  selected: {mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) => selectMode(selection.first),
                ),
              ),
            ),
            ValueListenableBuilder<UnderlayLayout>(
              valueListenable: underlayController,
              builder: (context, layout, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: layout.visible ? '下絵を非表示' : '下絵を表示',
                      onPressed: hasUnderlay
                          ? () => underlayController.setVisible(!layout.visible)
                          : null,
                      icon: Icon(layout.visible ? Icons.visibility : Icons.visibility_off),
                    ),
                    IconButton(
                      tooltip: '下絵の不透明度: ${(layout.opacity * 100).round()}%',
                      onPressed: hasUnderlay ? underlayController.cycleOpacity : null,
                      icon: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.opacity, size: 18),
                          Text(
                            '${(layout.opacity * 100).round()}%',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            IconButton(
              tooltip: '全体表示に戻す',
              onPressed: ref.read(viewportProvider).reset,
              icon: const Icon(Icons.fit_screen),
            ),
            IconButton(
              tooltip: '元に戻す',
              onPressed: canUndo ? ref.read(canvasProvider.notifier).undo : null,
              icon: const Icon(Icons.undo),
            ),
          ],
        ),
      ),
    );
  }
}

/// Row 2, draw mode: the fill-color palette (unchanged — swatches were
/// already language-independent) plus a single "閉じる" icon button.
class _DrawModeRow extends ConsumerWidget {
  const _DrawModeRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artwork = ref.watch(canvasProvider);
    final notifier = ref.read(canvasProvider.notifier);
    final selectedColor = ref.watch(selectedFillColorProvider);
    final canClose = artwork.draftVertexIds.length >= kMinPolygonVertices;
    // The toolbar's own tap has no gesture-side viewport scale to read from
    // directly (unlike `PolygonCanvas`'s `hitRadius()`/`lineAbsorptionTolerance()`
    // helpers), so it reads the current scale here instead — Phase Hβ's
    // screen-px unification (`.cursor/plans/plan_phase_H_beta.md`) applies
    // to this explicit "閉じる" action just as much as to the implicit
    // double-tap close it mirrors.
    final viewportScale = ref.read(viewportProvider).value.scale;

    return SizedBox(
      height: _kRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: kDefaultPolygonPalette.length,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final color = kDefaultPolygonPalette[index];
                  final isSelected = color == selectedColor;
                  return Tooltip(
                    message: '塗り色を選択',
                    child: GestureDetector(
                      onTap: () => ref.read(selectedFillColorProvider.notifier).state = color,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.black87 : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '多角形を閉じる',
              iconSize: 32,
              onPressed: canClose
                  ? () => notifier.closePolygon(
                      selectedColor,
                      lineAbsorptionTolerance: kLineAbsorptionTolerance / viewportScale,
                    )
                  : null,
              icon: const Icon(Icons.check_circle),
            ),
          ],
        ),
      ),
    );
  }
}

/// Row 2, eraser mode: a decorative, non-interactive reminder of what
/// tapping the canvas does in this mode — there is nothing to press here,
/// erasing itself happens by tapping a vertex on the canvas.
class _EraserModeRow extends StatelessWidget {
  const _EraserModeRow();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return SizedBox(
      height: _kRowHeight,
      child: Center(
        child: Tooltip(
          message: '頂点をタップして削除',
          child: Icon(Icons.delete_outline, size: 28, color: color),
        ),
      ),
    );
  }
}

/// Row 2, edit mode: one of three sub-views depending on selection state:
/// - no vertex selected → [_NoSelectionRow] (whole-shape 図形/辺 target
///   cycling, insertion, deletion).
/// - a selected vertex that isn't shared → a decorative reminder (nothing
///   to detach).
/// - a selected, *shared* vertex → the detach cycle/execute pair.
///
/// Whenever a vertex *is* selected, a "選択を解除" button also sits fixed
/// at the row's trailing edge regardless of which of the latter two
/// sub-views is showing — a safety valve so the artist never has to hunt
/// for empty canvas to tap in order to back out of a selection (e.g. once
/// they've long-press-dragged one, per [PolygonCanvas.startVertexDrag]'s
/// doc). It lines up under Row 1's "元に戻す" for the same reason: both are
/// reversal/exit actions, so keeping them in the same column makes the
/// spot easy to find without looking.
class _EditModeRow extends ConsumerWidget {
  const _EditModeRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedVertexId = ref.watch(selectedVertexProvider);
    final notifier = ref.read(canvasProvider.notifier);
    // Watched so `isVertexShared`/`polygonsReferencing` below stay fresh
    // across weld/detach/undo — mirrors the row above.
    ref.watch(canvasProvider);

    if (selectedVertexId == null) {
      return const _NoSelectionRow();
    }

    final Widget content = notifier.isVertexShared(selectedVertexId)
        ? _DetachControls(selectedVertexId: selectedVertexId)
        : Builder(
            builder: (context) {
              final color = Theme.of(context).colorScheme.primary;
              return Tooltip(
                message: 'タップで選択、長押しドラッグで移動',
                child: Icon(Icons.touch_app_outlined, size: 28, color: color),
              );
            },
          );

    return SizedBox(
      height: _kRowHeight,
      child: Row(
        children: [
          Expanded(child: Center(child: content)),
          IconButton(
            tooltip: '選択を解除',
            iconSize: 28,
            onPressed: () {
              ref.read(selectedVertexProvider.notifier).state = null;
              ref.read(detachCycleIndexProvider.notifier).state = 0;
            },
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

/// The ♻️/✂️ pair shown in [_EditModeRow] once the selected vertex is
/// confirmed shared — split out purely so that widget stays focused on
/// picking *which* sub-view to show alongside the always-present "選択を
/// 解除" button, rather than also carrying this branch's own cycle state.
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
          : notifier.detachVertexFromPolygon(selectedVertexId, currentTarget.polygonId!);
      if (copyId != null) {
        ref.read(selectedVertexProvider.notifier).state = copyId;
      }
      ref.read(detachCycleIndexProvider.notifier).state = 0;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '切り離す多角形を切り替え',
          iconSize: 32,
          onPressed: cycleTarget,
          icon: const Icon(Icons.autorenew),
        ),
        const SizedBox(width: 32),
        IconButton(
          tooltip: '選択中の多角形から切り離す',
          iconSize: 32,
          onPressed: target == null ? null : executeDetach,
          icon: const Icon(Icons.content_cut),
        ),
      ],
    );
  }
}

/// Row 2, edit mode, no vertex selected: lets the artist target a whole
/// polygon and one of its edges without ever needing to tap precisely on
/// thin geometry — the four buttons operate purely through these two
/// cycling providers, matching what [PolygonCanvas] highlights on the
/// canvas (both read the exact same `resolvePolygonTarget`/
/// `resolveEdgeTarget` pure functions, so the two views can never
/// disagree).
class _NoSelectionRow extends ConsumerWidget {
  const _NoSelectionRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artwork = ref.watch(canvasProvider);
    final notifier = ref.read(canvasProvider.notifier);
    final polygonIndex = ref.watch(polygonCycleIndexProvider);
    final edgeIndex = ref.watch(edgeCycleIndexProvider);

    final targetPolygonId = resolvePolygonTarget(
      polygons: artwork.polygons,
      rawCycleIndex: polygonIndex,
    );
    final targetPolygon = artwork.polygons.where((p) => p.id == targetPolygonId).firstOrNull;
    final targetEdge = targetPolygon == null
        ? null
        : resolveEdgeTarget(polygon: targetPolygon, rawCycleIndex: edgeIndex);

    void cyclePolygon() {
      ref.read(polygonCycleIndexProvider.notifier).state = polygonIndex + 1;
      // An edge index only ever makes sense relative to whichever polygon
      // it was last read against, so switching shapes always restarts it.
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

    void deleteTargetPolygon() {
      final polygonId = targetPolygonId;
      if (polygonId == null) return;
      notifier.deletePolygon(polygonId);
      ref.read(polygonCycleIndexProvider.notifier).state = -1;
      ref.read(edgeCycleIndexProvider.notifier).state = -1;
    }

    return SizedBox(
      height: _kRowHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            tooltip: '図形を切り替え',
            iconSize: 28,
            onPressed: artwork.polygons.isEmpty ? null : cyclePolygon,
            icon: const Icon(Icons.autorenew),
          ),
          IconButton(
            tooltip: '辺を切り替え',
            iconSize: 28,
            onPressed: targetPolygonId == null ? null : cycleEdge,
            icon: const Icon(Icons.skip_next),
          ),
          IconButton(
            tooltip: 'ここに頂点を追加',
            iconSize: 28,
            onPressed: targetEdge == null ? null : addVertexAtEdge,
            icon: const Icon(Icons.add_circle_outline),
          ),
          IconButton(
            tooltip: '図形を削除',
            iconSize: 28,
            onPressed: targetPolygonId == null ? null : deleteTargetPolygon,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}
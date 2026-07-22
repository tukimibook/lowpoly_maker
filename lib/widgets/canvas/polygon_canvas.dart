import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../geometry/trace_point_generator.dart';
import '../../geometry/viewport_pinch.dart';
import '../../models/canvas_mode.dart';
import '../../models/draw_mode.dart';
import '../../providers/canvas_background_provider.dart';
import '../../providers/canvas_capture_provider.dart';
import '../../providers/canvas_provider.dart';
import '../../providers/canvas_size_provider.dart';
import '../../providers/detach_cycle_provider.dart';
import '../../providers/drag_preview_provider.dart';
import '../../providers/polygon_drag_preview_provider.dart';
import '../../providers/polygon_edit_target_provider.dart';
import '../../providers/selected_vertex_provider.dart';
import '../../providers/trace_gesture_provider.dart';
import '../../providers/trace_stroke_preview_provider.dart';
import '../../providers/vertex_drag_preview_provider.dart';
import '../../providers/viewport_gesture_provider.dart';
import '../../providers/viewport_provider.dart';
import 'polygon_painter.dart';
import 'underlay_layer.dart';

/// The drawable surface: renders confirmed polygons and the in-progress
/// draft, and interprets touches according to the current [CanvasMode]:
/// - [CanvasMode.draw]: place/extend/close polygons — either tap-by-tap, or
///   (see [DrawMode.trace]) by tracing a continuous stroke.
/// - [CanvasMode.eraser]: delete a single touched vertex.
/// - [CanvasMode.edit]: tap to select a vertex; long-press drag to move it.
///
/// Every mode also recognizes a 2-finger pinch/pan as a *viewport* gesture
/// (Phase Hβ, `.cursor/plans/plan_phase_H_beta.md`) rather than whatever
/// that mode's own 1-finger gesture means — see the gesture-sub-cycle
/// helpers inside [build] and `providers/viewport_gesture_provider.dart`
/// for how the two are told apart on every single `onScale*` callback.
///
/// [DrawMode.trace] (Phase F, `.cursor/plans/plan_phase_F.md`) is the one
/// exception to that shared `onScale*`-only mechanism: it layers a raw
/// [Listener] *around* its own `onScale*` `GestureDetector` so it can keep
/// sourcing a locked single finger's true position straight from the
/// pointer stream — bypassing `ScaleGestureRecognizer`'s multi-finger
/// focal-point fusion — once `TraceGestureController` confirms the stroke
/// and starts ignoring every other finger ("Lock & Ignore"). See that
/// controller's doc (`providers/trace_gesture_provider.dart`) for why a
/// brief disambiguation window comes first, so a genuine 2-finger
/// pinch/pan still reliably wins when that's what the artist meant.
class PolygonCanvas extends ConsumerWidget {
  const PolygonCanvas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artwork = ref.watch(canvasProvider);
    final mode = ref.watch(canvasModeProvider);
    final drawMode = ref.watch(drawModeProvider);
    final selectedVertexId = ref.watch(selectedVertexProvider);
    final notifier = ref.read(canvasProvider.notifier);
    final viewport = ref.watch(viewportProvider);
    final gestureBaseline = ref.watch(viewportGestureProvider);
    final dragPreview = ref.watch(dragPreviewProvider);
    final vertexDragPreview = ref.watch(vertexDragPreviewProvider);
    final polygonDragPreview = ref.watch(polygonDragPreviewProvider);
    final tracePreview = ref.watch(traceStrokePreviewProvider);
    final traceGesture = ref.watch(traceGestureProvider);
    final canvasBrightness = ref.watch(canvasBackgroundProvider);
    final detachCycleIndex = ref.watch(detachCycleIndexProvider);
    final polygonCycleIndex = ref.watch(polygonCycleIndexProvider);
    final edgeCycleIndex = ref.watch(edgeCycleIndexProvider);

    // Which polygon edit mode currently emphasizes, and — while no vertex
    // is selected — which of its edges, if any. Exactly one of these two
    // features is ever active at a time (selection state alone decides
    // which), so both resolve into the same `highlightedPolygonId` the
    // painter takes — see that field's doc for why. Computed once here,
    // rather than duplicated in the toolbar, so the canvas and toolbar
    // buttons can never disagree about the current target.
    String? highlightedPolygonId;
    PolygonEdge? targetEdge;
    if (mode == CanvasMode.edit) {
      if (selectedVertexId != null) {
        highlightedPolygonId = resolveDetachTarget(
          referencingPolygons: notifier.polygonsReferencing(selectedVertexId),
          draftReferences: notifier.draftReferencesVertex(selectedVertexId),
          rawCycleIndex: detachCycleIndex,
        )?.polygonId;
      } else {
        highlightedPolygonId = resolvePolygonTarget(
          polygons: artwork.polygons,
          rawCycleIndex: polygonCycleIndex,
        );
        final targetPolygon = artwork.polygons
            .where((p) => p.id == highlightedPolygonId)
            .firstOrNull;
        if (targetPolygon != null) {
          targetEdge = resolveEdgeTarget(
            polygon: targetPolygon,
            rawCycleIndex: edgeCycleIndex,
          );
        }
      }
    }
    final targetPolygonId = selectedVertexId == null ? highlightedPolygonId : null;

    double hitRadius() => kVertexHitRadius / viewport.value.scale;
    double doubleTapMaxDistance() => kDoubleTapMaxDistance / viewport.value.scale;
    double lineAbsorptionTolerance() => kLineAbsorptionTolerance / viewport.value.scale;

    Offset worldPosition(Offset localPosition) {
      return viewport.value.screenToWorld(localPosition);
    }

    // --- Viewport (pinch/pan) gesture bookkeeping -------------------------
    //
    // Shared across all three modes' `GestureDetector`s below: each one
    // still owns its own `onScale*` callbacks (since each mode's 1-finger
    // meaning is different), but every one of them starts with
    // `beginGestureSubCycle`, defers to `applyViewportUpdate` first inside
    // `onScaleUpdate`, and asks `endGestureSubCycle` whether to run its own
    // commit logic inside `onScaleEnd` — see `ViewportGestureBaseline`'s
    // doc (`providers/viewport_gesture_provider.dart`) for exactly what
    // problem this solves and why a plain `onPan*` can't express it
    // (`GestureDetector` cannot have both `onPan*` and `onScale*` at once —
    // pinch-zoom needs the latter, so every mode's previously-`onPan*`
    // 1-finger gesture had to move to `onScale*` too).
    //
    // Whenever `endGestureSubCycle` returns false, the mode must *discard*
    // (never commit) whatever single-finger preview it had in flight —
    // covering both a real second finger joining mid-gesture (a real pinch
    // almost never starts with both fingers touching in exactly the same
    // frame, so the first finger's own action must not silently apply just
    // because it happened to move first) and a final release that was part
    // of a multi-finger gesture the viewport already handled. See
    // `endGestureSubCycle`'s own doc for exactly how it tells those apart
    // from a genuine single-finger release.

    void beginGestureSubCycle(ScaleStartDetails details) {
      final previous = gestureBaseline.value;
      gestureBaseline.value = ViewportGestureBaseline(
        pointerCount: details.pointerCount,
        transform: viewport.value,
        focalPoint: details.localFocalPoint,
        hadMultiFinger:
            (previous?.hadMultiFinger ?? false) || details.pointerCount >= 2,
      );
    }

    /// True while the *whole physical gesture so far* is (or, per
    /// [ViewportGestureBaseline.hadMultiFinger], recently was) a 2+-finger
    /// pinch/pan — i.e. whenever a mode's own single-finger draw/erase/drag
    /// logic must stay out of the way entirely.
    bool isViewportGesture() {
      final baseline = gestureBaseline.value;
      return baseline != null &&
          (baseline.pointerCount >= 2 || baseline.hadMultiFinger);
    }

    /// Applies pinch/pan to the viewport if [isViewportGesture] (returning
    /// true, so the caller skips its own single-finger update path
    /// entirely); otherwise a no-op returning false. While
    /// [hadMultiFinger] is riding out a lifted finger
    /// (`details.pointerCount < 2` even though this whole gesture has
    /// already seen 2), the viewport is deliberately left untouched rather
    /// than reinterpreting the one remaining finger as a 1-finger pan.
    bool applyViewportUpdate(ScaleUpdateDetails details) {
      if (!isViewportGesture()) return false;
      if (details.pointerCount >= 2) {
        final baseline = gestureBaseline.value!;
        viewport.value = applyPinchPan(
          baselineTransform: baseline.transform,
          baselineFocalPoint: baseline.focalPoint,
          scale: details.scale,
          focalPoint: details.localFocalPoint,
        );
      }
      return true;
    }

    /// Ends the current gesture sub-cycle — clearing the baseline entirely
    /// once every finger has actually lifted (`details.pointerCount == 0`;
    /// a mid-gesture pointer-count change instead reports whatever the new
    /// nonzero count is, so the baseline must survive those to keep
    /// [ViewportGestureBaseline.hadMultiFinger] sticky) — and returns
    /// whether the mode's own single-finger commit logic
    /// (`commitDrawDrag`/`commitPolygonDrag`/...) should run: true only
    /// when *every* finger has now actually lifted (`details.pointerCount
    /// == 0`) *and* this whole physical gesture never involved a second
    /// finger.
    ///
    /// The `details.pointerCount == 0` half of that matters because
    /// Flutter's `ScaleGestureRecognizer` also synthesizes an `onEnd` (with
    /// `pointerCount` already reporting the *new*, larger count, e.g. 2 —
    /// see that class's `_reconfigure`) the instant a second finger joins
    /// an already-`started` 1-finger sub-cycle, before any `onStart` for
    /// the new 2-finger sub-cycle has fired. Without also checking for that
    /// case here, a real pinch/pan — which in practice almost never has
    /// both fingers touch down in exactly the same frame — would read as
    /// "the first finger just lifted, commit whatever it was doing" the
    /// instant the second one landed, silently placing/moving/deleting
    /// something right where finger 1 happened to be.
    bool endGestureSubCycle(ScaleEndDetails details) {
      final baseline = gestureBaseline.value;
      final isFinalRelease = details.pointerCount == 0;
      if (isFinalRelease) {
        gestureBaseline.value = null;
      }
      return isFinalRelease &&
          baseline != null &&
          !baseline.hadMultiFinger &&
          baseline.pointerCount < 2;
    }

    void updateDrawPreview(Offset localPosition) {
      final position = worldPosition(localPosition);
      final hit = notifier.findPolygonVertexNear(
        position,
        hitRadius: hitRadius(),
      );
      final previousSnap = dragPreview.value?.snappedVertexId;
      dragPreview.value = DragPreview(
        position: position,
        snappedVertexId: hit?.vertexId,
      );
      if (hit != null && hit.vertexId != previousSnap) {
        HapticFeedback.mediumImpact();
      }
    }

    void commitDrawDrag() {
      final preview = dragPreview.value;
      dragPreview.value = null;
      if (preview == null) return;

      final fillColor = ref.read(selectedFillColorProvider);
      final matchedColor = notifier.handleDrawTap(
        preview.position,
        fillColor: fillColor,
        hitRadius: hitRadius(),
        doubleTapMaxDistance: doubleTapMaxDistance(),
        lineAbsorptionTolerance: lineAbsorptionTolerance(),
      );
      if (matchedColor != null) {
        ref.read(selectedFillColorProvider.notifier).state = matchedColor;
      }
    }

    /// Resamples whatever [tracePreview] accumulated (see
    /// `generateTracePoints`) and hands the whole stroke to
    /// [CanvasNotifier.commitTraceStroke] as one batch, then clears the
    /// preview either way. No-op (nothing to commit, nothing to undo) for
    /// a degenerate stroke — the finger never actually moved, so there's
    /// only the single touch-down point and no length to resample.
    void commitTraceStrokeFromPreview() {
      final rawPoints = tracePreview.rawPoints;
      tracePreview.clear();
      if (rawPoints == null || rawPoints.length < 2) return;
      final points = generateTracePoints(rawPoints, spacing: kTraceVertexSpacing);
      notifier.commitTraceStroke(
        points,
        hitRadius: hitRadius(),
        lineAbsorptionTolerance: lineAbsorptionTolerance(),
      );
    }

    void handleEditTap(Offset localPosition) {
      // Read *before* the hit-test, and forward it as the tie-break
      // preference: right after a detach, the just-created copy sits at
      // the exact same spot as the vertex it was copied from, so without
      // this, tapping that same spot again could resolve to the *other*
      // one — coincidentally re-welding what the artist just detached,
      // purely because of `Artwork.polygons`' list order (see
      // `findNearestPoint`'s doc, and `.cursor/plans/
      // plan_phase_H_alpha.md`, 2026-07-16 検討メモ).
      final selected = ref.read(selectedVertexProvider);
      final tappedId = notifier.findVertexNear(
        worldPosition(localPosition),
        hitRadius: hitRadius(),
        preferredVertexId: selected,
      );

      // Explicit weld only while the toolbar has armed [weldArmedProvider]
      // — tapping another vertex without arming merely changes selection.
      if (ref.read(weldArmedProvider)) {
        var welded = false;
        if (selected != null && tappedId != null && tappedId != selected) {
          if (notifier.weldVertices(selected, tappedId)) {
            ref.read(selectedVertexProvider.notifier).state = selected;
            HapticFeedback.mediumImpact();
            welded = true;
          }
        }
        ref.read(weldArmedProvider.notifier).state = false;
        if (welded) return;
      }

      ref.read(selectedVertexProvider.notifier).state = tappedId;
      ref.read(detachCycleIndexProvider.notifier).state = 0;
      if (tappedId != null) {
        // A vertex just became selected — the whole-shape target UI (図形
        // 切替/辺切替/追加/削除) that only shows while nothing is selected
        // is about to disappear, so leave it starting fresh next time.
        ref.read(polygonCycleIndexProvider.notifier).state = -1;
        ref.read(edgeCycleIndexProvider.notifier).state = -1;
      }
    }

    void startPolygonDrag() {
      final polygonId = targetPolygonId;
      if (polygonId == null) return;
      final polygon = artwork.polygons.where((p) => p.id == polygonId).firstOrNull;
      if (polygon == null) return;
      polygonDragPreview.value = PolygonDragPreview(
        affectedVertexIds: polygon.vertexIds.toSet(),
        delta: Offset.zero,
      );
    }

    void updatePolygonDrag(Offset localDelta) {
      final preview = polygonDragPreview.value;
      if (preview == null) return;
      polygonDragPreview.value = PolygonDragPreview(
        affectedVertexIds: preview.affectedVertexIds,
        delta: preview.delta + localDelta / viewport.value.scale,
      );
    }

    void commitPolygonDrag() {
      final preview = polygonDragPreview.value;
      polygonDragPreview.value = null;
      final polygonId = targetPolygonId;
      if (preview == null || polygonId == null) return;
      notifier.translatePolygon(polygonId, preview.delta);
    }

    void startVertexDrag(Offset localPosition) {
      final position = worldPosition(localPosition);
      final previouslySelected = ref.read(selectedVertexProvider);
      // Same tie-break preference as `handleEditTap` — see its comment.
      // This is the hit-test that motivated adding `preferredVertexId` in
      // the first place: a detach immediately followed by a long-press
      // drag at that same spot was landing on the wrong one of the two
      // now-coincident vertices.
      final vertexId = notifier.findVertexNear(
        position,
        hitRadius: hitRadius(),
        preferredVertexId: previouslySelected,
      );
      if (vertexId == null) return;

      ref.read(selectedVertexProvider.notifier).state = vertexId;
      // A long-press that lands on a *different* vertex than the one
      // already selected is, semantically, the same "a vertex just became
      // the one being engaged with" moment `handleEditTap` resets these
      // for — it was just missing that treatment on this path. Guarded so
      // that re-long-pressing the *same* already-selected vertex (e.g. to
      // reposition it without releasing selection first) doesn't discard
      // an in-progress detach-cycle choice the artist already dialled in.
      if (vertexId != previouslySelected) {
        ref.read(detachCycleIndexProvider.notifier).state = 0;
        ref.read(polygonCycleIndexProvider.notifier).state = -1;
        ref.read(edgeCycleIndexProvider.notifier).state = -1;
      }
      vertexDragPreview.value = VertexDragPreview(
        vertexId: vertexId,
        position: position,
      );
      HapticFeedback.mediumImpact();
    }

    void updateVertexDrag(Offset localPosition) {
      final preview = vertexDragPreview.value;
      if (preview == null) return;
      vertexDragPreview.value = VertexDragPreview(
        vertexId: preview.vertexId,
        position: worldPosition(localPosition),
      );
    }

    void commitVertexDrag() {
      final preview = vertexDragPreview.value;
      vertexDragPreview.value = null;
      if (preview == null) return;
      notifier.moveVertex(preview.vertexId, preview.position);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          ref.read(canvasSizeProvider).setSize(size);
        });

        // The underlay paints behind the polygon layer; each gets its own
        // inner `RepaintBoundary` so redrawing one (e.g. an opacity change,
        // or a vertex drag) never forces the other to repaint too. The
        // whole `Stack` is *also* wrapped in an outer, keyed
        // `RepaintBoundary` — nested `RepaintBoundary`s are fully
        // supported — so `ThumbnailCaptureService` (via
        // `canvasRepaintBoundaryKeyProvider`) can capture underlay +
        // polygons together as one gallery thumbnail (Phase Hγ).
        final content = RepaintBoundary(
          key: ref.watch(canvasRepaintBoundaryKeyProvider),
          child: Stack(
            children: [
              UnderlayLayer(size: size),
              RepaintBoundary(
                child: CustomPaint(
                  size: size,
                  painter: PolygonPainter(
                    artwork: artwork,
                    mode: mode,
                    viewport: viewport,
                    dragPreview: dragPreview,
                    vertexDragPreview: vertexDragPreview,
                    polygonDragPreview: polygonDragPreview,
                    selectedVertexId: selectedVertexId,
                    highlightedPolygonId: highlightedPolygonId,
                    targetEdge: targetEdge,
                    canvasBrightness: canvasBrightness,
                    tracePreview: tracePreview,
                  ),
                ),
              ),
            ],
          ),
        );

        if (mode == CanvasMode.draw && drawMode == DrawMode.trace) {
          // See the class doc and `TraceGestureController`'s own doc
          // (`providers/trace_gesture_provider.dart`) for why this mode
          // alone wraps its `onScale*` `GestureDetector` in a raw
          // [Listener]: only a raw pointer stream can single out one
          // specific finger's true position once a second one joins,
          // which `ScaleGestureRecognizer`'s fused `focalPoint` cannot.
          void ignoreUntrackedFinger(int pointerId, VoidCallback action) {
            if (!traceGesture.isTrackedPointer(pointerId)) return;
            action();
          }

          return Listener(
            onPointerDown: (event) => traceGesture.onPointerDown(event.pointer),
            onPointerMove: (event) {
              // Pre-lock, `onScaleUpdate` below already sources the
              // preview from `ScaleUpdateDetails.localFocalPoint` (which,
              // with exactly one finger down, *is* that finger's raw
              // position) — only once `locked` does the arena's own fused
              // focal point stop being trustworthy, so only then does
              // this raw stream take over driving the preview.
              if (!traceGesture.isLocked) return;
              ignoreUntrackedFinger(event.pointer, () {
                tracePreview.lineTo(worldPosition(event.localPosition));
              });
            },
            onPointerUp: (event) {
              ignoreUntrackedFinger(event.pointer, () {
                final wasLocked = traceGesture.isLocked;
                traceGesture.reset();
                if (wasLocked) {
                  // Product decision (2026-07-18 検討メモ): commit the
                  // instant the locked finger itself lifts, regardless of
                  // whether some other, already-ignored finger is still
                  // down.
                  commitTraceStrokeFromPreview();
                } else {
                  // Released before ever confirming the lock — product
                  // decision (2026-07-18 検討メモ): discard, don't treat a
                  // quick tap as a one-point stroke.
                  tracePreview.clear();
                }
              });
            },
            onPointerCancel: (event) {
              ignoreUntrackedFinger(event.pointer, () {
                traceGesture.reset();
                tracePreview.clear();
              });
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (details) {
                if (traceGesture.isLocked) return;
                beginGestureSubCycle(details);
                if (isViewportGesture()) {
                  // A second finger arrived within the disambiguation
                  // window (or this whole gesture already had one) — a
                  // real pinch/pan wins; nothing was ever locked yet, so
                  // there's only ever a handful of provisional points to
                  // throw away.
                  traceGesture.reset();
                  tracePreview.clear();
                  return;
                }
                tracePreview.start(worldPosition(details.localFocalPoint));
                traceGesture.beginDisambiguation(
                  details.localFocalPoint,
                  traceGesture.confirmLock,
                );
              },
              onScaleUpdate: (details) {
                if (traceGesture.isLocked) {
                  // Locked: the raw `Listener` above is the sole position
                  // source from here on, so `onScale*`'s own (possibly
                  // multi-finger-fused) focal point is ignored entirely.
                  return;
                }
                if (isViewportGesture()) {
                  traceGesture.reset();
                  tracePreview.clear();
                  applyViewportUpdate(details);
                  return;
                }
                tracePreview.lineTo(worldPosition(details.localFocalPoint));
                traceGesture.maybeConfirmBySlop(details.localFocalPoint);
              },
              onScaleEnd: (details) {
                if (traceGesture.isLocked) return; // handled by `Listener` above.
                endGestureSubCycle(details);
                if (details.pointerCount == 0) {
                  // Every finger is now up without the lock ever having
                  // been confirmed — same "discard, don't commit a quick
                  // tap" rule as `Listener.onPointerUp` above.
                  traceGesture.reset();
                  tracePreview.clear();
                }
              },
              child: content,
            ),
          );
        }

        if (mode == CanvasMode.edit) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => handleEditTap(details.localPosition),
            onLongPressStart: (details) =>
                startVertexDrag(details.localPosition),
            onLongPressMoveUpdate: (details) =>
                updateVertexDrag(details.localPosition),
            onLongPressEnd: (details) => commitVertexDrag(),
            onLongPressCancel: () {
              vertexDragPreview.value = null;
            },
            // A plain (non-long-press) 1-finger drag translates the whole
            // "図形切替" target instead — active only while no vertex is
            // selected and a target has actually been chosen (see
            // `targetPolygonId`'s doc above); with neither, `startPolygonDrag`
            // is a no-op, exactly like today's plain drag in edit mode. A
            // 2-finger drag instead pans/zooms the viewport — see the
            // gesture-sub-cycle helpers above.
            onScaleStart: (details) {
              beginGestureSubCycle(details);
              if (isViewportGesture()) {
                // A second finger just joined (or this whole gesture
                // already had one) — a long-press vertex drag from finger
                // 1 has no business surviving into a pinch/pan either.
                vertexDragPreview.value = null;
                return;
              }
              startPolygonDrag();
            },
            onScaleUpdate: (details) {
              if (applyViewportUpdate(details)) return;
              updatePolygonDrag(details.focalPointDelta);
            },
            onScaleEnd: (details) {
              if (endGestureSubCycle(details)) {
                commitPolygonDrag();
              } else {
                // Not a genuine single-finger release — discard rather
                // than commit; see `endGestureSubCycle`'s doc.
                polygonDragPreview.value = null;
              }
            },
            child: content,
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (details) {
            beginGestureSubCycle(details);
            if (isViewportGesture()) {
              // A second finger just joined (or this whole gesture already
              // had one) — discard, don't leave dangling, whatever draft
              // preview finger 1 alone had set.
              dragPreview.value = null;
              return;
            }
            if (mode == CanvasMode.eraser) {
              notifier.handleEraseTap(
                worldPosition(details.localFocalPoint),
                hitRadius: hitRadius(),
              );
              return;
            }
            updateDrawPreview(details.localFocalPoint);
          },
          onScaleUpdate: (details) {
            if (applyViewportUpdate(details)) return;
            if (mode == CanvasMode.eraser) return;
            updateDrawPreview(details.localFocalPoint);
          },
          onScaleEnd: (details) {
            final shouldCommit = endGestureSubCycle(details);
            if (mode == CanvasMode.eraser) return;
            if (shouldCommit) {
              commitDrawDrag();
            } else {
              // Not a genuine single-finger release — discard rather than
              // commit; see `endGestureSubCycle`'s doc.
              dragPreview.value = null;
            }
          },
          child: content,
        );
      },
    );
  }
}

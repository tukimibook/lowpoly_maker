import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Session-only "clean view" toggle: when `true`, [PolygonPainter] draws
/// fills only (no strokes, vertex handles, drafts, or other edit chrome).
///
/// Deliberately outside [Artwork] / undo — presentation, not geometry.
final isPreviewModeProvider = StateProvider<bool>((ref) => false);

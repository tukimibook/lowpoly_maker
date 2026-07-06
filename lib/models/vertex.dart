import 'dart:ui';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'vertex.freezed.dart';

/// A single point stored in [Artwork.vertices], the shared vertex pool.
///
/// Multiple polygons can reference the very same [Vertex.id] (via their
/// `vertexIds`) to indicate they share that exact corner. This is what lets
/// adjacent shapes tile together with no gap: a shared corner is one single
/// point in memory, not merely several different points that happen to sit
/// at the same coordinate. Moving or deleting it (see later phases) then
/// affects every polygon that references it, together, automatically.
@freezed
abstract class Vertex with _$Vertex {
  const factory Vertex({required String id, required Offset position}) = _Vertex;
}

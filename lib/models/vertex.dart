import 'dart:ui';

import 'package:freezed_annotation/freezed_annotation.dart';

import 'json_converters.dart';

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

  /// Deserializes one entry of `Artwork.toJson()`'s `vertices` map. [id] is
  /// the map key that entry was stored under — not duplicated inside [json]
  /// itself (see [toJson]) — so callers must pass it through explicitly.
  factory Vertex.fromJson(String id, Map<String, dynamic> json) {
    return Vertex(id: id, position: offsetJsonConverter.fromJson(json));
  }
}

/// [Vertex.toJson] — an extension, not a class-body method; see
/// `ArtworkJson`'s doc (`models/artwork.dart`) for why freezed classes need
/// this pattern for custom instance methods.
extension VertexJson on Vertex {
  /// Serializes only [position] — [id] is carried by this vertex's key in
  /// `Artwork.vertices`/`Artwork.toJson()`'s `vertices` map, so repeating it
  /// inside the value here would be redundant.
  Map<String, dynamic> toJson() => offsetJsonConverter.toJson(position);
}

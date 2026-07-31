import 'package:flutter/painting.dart' show Color;
import 'package:freezed_annotation/freezed_annotation.dart';

import 'json_converters.dart';

part 'polygon_shape.freezed.dart';

/// A closed polygon defined by an ordered list of vertex IDs.
///
/// Rather than embedding [Vertex] objects directly, [PolygonShape] only
/// stores references (`vertexIds`) into the shared vertex pool at
/// `Artwork.vertices`. Any two polygons that list the same ID share that
/// exact corner. It is the caller's responsibility (see
/// `CanvasNotifier.closePolygon`) to only ever construct a [PolygonShape]
/// once it has at least 3 vertex IDs — a polygon can't be a real shape with
/// fewer than that.
@freezed
abstract class PolygonShape with _$PolygonShape {
  const factory PolygonShape({
    required String id,
    required List<String> vertexIds,
    required Color fillColor,
    required Color strokeColor,
    required double strokeWidth,
  }) = _PolygonShape;

  /// Deserializes one entry of `Artwork.toJson()`'s `polygons` list.
  /// [vertexIds] are restored as-is (UUID references into `Artwork.vertices`
  /// — resolving/validating them is the caller's job, not this model's).
  factory PolygonShape.fromJson(Map<String, dynamic> json) {
    return PolygonShape(
      id: json['id'] as String,
      vertexIds: (json['vertexIds'] as List<dynamic>).cast<String>(),
      fillColor: colorJsonConverter.fromJson(json['fillColor'] as int),
      strokeColor: colorJsonConverter.fromJson(json['strokeColor'] as int),
      strokeWidth: (json['strokeWidth'] as num).toDouble(),
    );
  }
}

/// [PolygonShape.toJson] — an extension, not a class-body method; see
/// `ArtworkJson`'s doc (`models/artwork.dart`) for why freezed classes need
/// this pattern for custom instance methods.
extension PolygonShapeJson on PolygonShape {
  /// Serializes colors via [ColorJsonConverter] as 32-bit ARGB ints.
  Map<String, dynamic> toJson() => {
    'id': id,
    'vertexIds': vertexIds,
    'fillColor': colorJsonConverter.toJson(fillColor),
    'strokeColor': colorJsonConverter.toJson(strokeColor),
    'strokeWidth': strokeWidth,
  };
}

import 'package:flutter/painting.dart' show Color;
import 'package:freezed_annotation/freezed_annotation.dart';

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
}

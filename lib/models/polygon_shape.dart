import 'dart:ui';

import 'vertex.dart';

/// A closed polygon made of 3 or more [Vertex]es.
class PolygonShape {
  const PolygonShape({
    required this.id,
    required this.vertices,
    required this.fillColor,
    required this.strokeColor,
    required this.strokeWidth,
  }) : assert(vertices.length >= 3, 'A polygon needs at least 3 vertices');

  final String id;
  final List<Vertex> vertices;
  final Color fillColor;
  final Color strokeColor;
  final double strokeWidth;

  PolygonShape copyWith({
    List<Vertex>? vertices,
    Color? fillColor,
    Color? strokeColor,
    double? strokeWidth,
  }) {
    return PolygonShape(
      id: id,
      vertices: vertices ?? this.vertices,
      fillColor: fillColor ?? this.fillColor,
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
    );
  }
}

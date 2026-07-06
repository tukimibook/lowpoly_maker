import 'dart:ui';

/// A single control point of a polygon, stored in world coordinates
/// (i.e. independent of the current canvas zoom/pan, which is introduced
/// in a later phase).
class Vertex {
  const Vertex({required this.id, required this.position});

  final String id;
  final Offset position;

  Vertex copyWith({Offset? position}) {
    return Vertex(id: id, position: position ?? this.position);
  }
}

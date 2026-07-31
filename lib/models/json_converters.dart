import 'dart:ui' show Color, Offset;

/// Dedicated JSON helpers for Flutter primitives used in `ArtworkDocument`
/// (Phase Hγ v1). Kept as plain static converters rather than
/// `json_serializable` `@JsonConverter`s — this codebase hand-writes
/// `toJson`/`fromJson` on freezed models, and these helpers are the single
/// place those call sites go through for [Offset] / [Color].
class OffsetJsonConverter {
  const OffsetJsonConverter();

  Map<String, dynamic> toJson(Offset offset) => {'x': offset.dx, 'y': offset.dy};

  Offset fromJson(Map<String, dynamic> json) {
    return Offset((json['x'] as num).toDouble(), (json['y'] as num).toDouble());
  }
}

/// Serializes [Color] as a 32-bit ARGB int ([Color.toARGB32]), matching
/// [Color.new]'s constructor on restore.
class ColorJsonConverter {
  const ColorJsonConverter();

  int toJson(Color color) => color.toARGB32();

  Color fromJson(int value) => Color(value);
}

/// Shared converter instances used by model `toJson`/`fromJson` extensions.
const offsetJsonConverter = OffsetJsonConverter();
const colorJsonConverter = ColorJsonConverter();

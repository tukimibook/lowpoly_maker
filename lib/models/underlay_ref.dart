import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import 'underlay_layout.dart';

/// Persisted underlay placement for [UnderlayRef] — the subset of
/// [UnderlayLayout] that belongs in `ArtworkDocument` JSON.
///
/// Deliberately excludes [UnderlayLayout.visible] (session-only; toggling
/// visibility must not survive save/reload as a document field).
@immutable
class UnderlayLayoutPersist {
  const UnderlayLayoutPersist({
    required this.offsetX,
    required this.offsetY,
    required this.scale,
    this.opacity = 1.0,
  });

  final double offsetX;
  final double offsetY;
  final double scale;
  final double opacity;

  /// Identity placement — same defaults as [UnderlayLayout.initial].
  static const UnderlayLayoutPersist initial = UnderlayLayoutPersist(
    offsetX: 0,
    offsetY: 0,
    scale: 1,
  );

  factory UnderlayLayoutPersist.fromLayout(UnderlayLayout layout) {
    return UnderlayLayoutPersist(
      offsetX: layout.offset.dx,
      offsetY: layout.offset.dy,
      scale: layout.scale,
      opacity: layout.opacity,
    );
  }

  /// Session [UnderlayLayout] with [UnderlayLayout.visible] left at its
  /// default (`true`) — visibility is not restored from disk.
  UnderlayLayout toLayout() {
    return UnderlayLayout(
      offset: Offset(offsetX, offsetY),
      scale: scale,
      opacity: opacity,
    );
  }

  Map<String, Object?> toJson() => {
    'offsetX': offsetX,
    'offsetY': offsetY,
    'scale': scale,
    'opacity': opacity,
  };

  factory UnderlayLayoutPersist.fromJson(Map<String, dynamic> json) {
    return UnderlayLayoutPersist(
      offsetX: (json['offsetX'] as num).toDouble(),
      offsetY: (json['offsetY'] as num).toDouble(),
      scale: (json['scale'] as num).toDouble(),
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is UnderlayLayoutPersist &&
            other.offsetX == offsetX &&
            other.offsetY == offsetY &&
            other.scale == scale &&
            other.opacity == opacity);
  }

  @override
  int get hashCode => Object.hash(offsetX, offsetY, scale, opacity);
}

/// Optional underlay block inside an `ArtworkDocument` (Phase Hγ v1).
///
/// [imageRelativePath] is always relative to the app documents directory
/// (e.g. `underlays/<id>.jpg`) — never a gallery/camera absolute path.
@immutable
class UnderlayRef {
  const UnderlayRef({required this.imageRelativePath, required this.layout});

  final String imageRelativePath;
  final UnderlayLayoutPersist layout;

  Map<String, Object?> toJson() => {
    'imageRelativePath': imageRelativePath,
    'layout': layout.toJson(),
  };

  /// Accepts v1 `imageRelativePath` and legacy `imagePath` (absolute or
  /// relative) so older on-disk documents still load.
  factory UnderlayRef.fromJson(Map<String, dynamic> json) {
    final relative =
        json['imageRelativePath'] as String? ?? json['imagePath'] as String?;
    if (relative == null || relative.isEmpty) {
      throw FormatException('UnderlayRef JSON missing imageRelativePath/imagePath');
    }
    final layoutJson = json['layout'] as Map<String, dynamic>?;
    return UnderlayRef(
      imageRelativePath: relative,
      layout: layoutJson == null
          ? UnderlayLayoutPersist.initial
          : UnderlayLayoutPersist.fromJson(layoutJson),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is UnderlayRef &&
            other.imageRelativePath == imageRelativePath &&
            other.layout == layout);
  }

  @override
  int get hashCode => Object.hash(imageRelativePath, layout);
}

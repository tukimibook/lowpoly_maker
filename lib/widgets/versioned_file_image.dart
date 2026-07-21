import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// A [FileImage]-like [ImageProvider] whose cache key also includes a
/// [version] (typically an artwork's `ArtworkSummary.updatedAt`).
///
/// Flutter's stock [FileImage] keys only on `file.path` + [scale], so when
/// a gallery thumbnail is overwritten in place at the same path the
/// [ImageCache] keeps serving the stale decode. Including [version] in
/// [operator ==] / [hashCode] makes a newer save a different cache entry
/// automatically — no imperative `imageCache.evict(...)` required
/// (defect-fix #4).
@immutable
class VersionedFileImage extends ImageProvider<VersionedFileImage> {
  /// Creates a provider that decodes [file] as an image, keyed also by
  /// [version] so content updates at the same path reload declaratively.
  const VersionedFileImage(this.file, this.version, {this.scale = 1.0});

  /// The file to decode into an image.
  final File file;

  /// Opaque version token — when this changes, the provider is no longer
  /// equal to its predecessor and [ImageCache] misses → reloads.
  final DateTime version;

  /// The scale to place in the [ImageInfo] object of the image.
  final double scale;

  @override
  Future<VersionedFileImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<VersionedFileImage>(this);
  }

  @override
  @protected
  ImageStreamCompleter loadImage(VersionedFileImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode: decode),
      scale: key.scale,
      debugLabel: key.file.path,
      informationCollector: () => <DiagnosticsNode>[
        ErrorDescription('Path: ${file.path}'),
        ErrorDescription('Version: $version'),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(
    VersionedFileImage key, {
    required ImageDecoderCallback decode,
  }) async {
    assert(key == this);
    final lengthInBytes = await file.length();
    if (lengthInBytes == 0) {
      // Deliberately do *not* call `imageCache.evict` here (unlike
      // [FileImage]): defect-fix #4 forbids imperative eviction; an empty
      // file is simply an error the [Image] widget's `errorBuilder` can
      // surface.
      throw StateError('$file is empty and cannot be loaded as an image.');
    }
    return (file.runtimeType == File)
        ? decode(await ui.ImmutableBuffer.fromFilePath(file.path))
        : decode(await ui.ImmutableBuffer.fromUint8List(await file.readAsBytes()));
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is VersionedFileImage &&
        other.file.path == file.path &&
        other.version == version &&
        other.scale == scale;
  }

  @override
  int get hashCode => Object.hash(file.path, version, scale);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'VersionedFileImage')}'
      '("${file.path}", version: $version, scale: ${scale.toStringAsFixed(1)})';
}

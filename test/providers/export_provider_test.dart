import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/painting.dart' show Color, Size;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:gal/gal.dart';

import 'package:polygon_art_app/models/artwork.dart';
import 'package:polygon_art_app/providers/export_provider.dart';
import 'package:polygon_art_app/services/artwork_png_renderer.dart';
import 'package:polygon_art_app/services/gallery_export_target.dart';
import 'package:polygon_art_app/services/share_sheet_target.dart';

/// A controllable stand-in for [ArtworkPngRenderer] — overriding the real
/// class (rather than a hand-rolled interface) matches this codebase's
/// existing fake style (e.g. `_ThrowingArtworkRepository` in
/// `test/services/auto_save_service_test.dart`), and lets tests force every
/// outcome [ExportController] must handle without going near a real
/// `PictureRecorder`: a successful render, "nothing to render"
/// ([Size.zero], surfaced as `null`), or a thrown rendering failure.
class _FakeRenderer implements ArtworkPngRenderer {
  _FakeRenderer({this.bytes, this.error, this.onRender});

  Uint8List? bytes;
  Object? error;

  /// Invoked (and awaited) inside [render] before returning — lets a test
  /// hold a call in flight (via a [Completer]) to observe
  /// [ExportState.isExporting] mid-export.
  Future<void> Function()? onRender;

  int callCount = 0;
  Artwork? lastArtwork;
  Size? lastCanvasSize;

  @override
  Future<Uint8List?> render(
    Artwork artwork,
    Size canvasSize, {
    Color backgroundColor = kExportBackgroundColor,
  }) async {
    callCount++;
    lastArtwork = artwork;
    lastCanvasSize = canvasSize;
    if (onRender != null) await onRender!();
    if (error != null) throw error!;
    return bytes;
  }
}

class _RecordingGalleryTarget implements GalleryExportTarget {
  Object? error;
  Uint8List? savedBytes;
  String? savedName;
  int callCount = 0;

  @override
  Future<void> saveImageBytes(Uint8List bytes, {required String name}) async {
    callCount++;
    if (error != null) throw error!;
    savedBytes = bytes;
    savedName = name;
  }
}

class _RecordingShareTarget implements ShareSheetTarget {
  Object? error;
  Uint8List? sharedBytes;
  String? sharedFileName;
  int callCount = 0;

  @override
  Future<void> shareImageBytes(Uint8List bytes, {required String fileName}) async {
    callCount++;
    if (error != null) throw error!;
    sharedBytes = bytes;
    sharedFileName = fileName;
  }
}

Artwork _artwork({String title = '無題の作品', String id = 'artwork-1'}) {
  return Artwork.empty(id: id, title: title);
}

/// Builds a [GalException] of [type] — `gal`'s constructor also requires a
/// [PlatformException]/[StackTrace] (native-code error detail this
/// codebase's [ExportController] never inspects, only [GalException.type]),
/// so tests only care about supplying a valid, arbitrary one.
GalException _galException(GalExceptionType type) {
  return GalException(
    type: type,
    platformException: PlatformException(code: type.code),
    stackTrace: StackTrace.empty,
  );
}

const _canvasSize = Size(300, 400);
final _pngBytes = Uint8List.fromList([1, 2, 3]);

void main() {
  group('ExportController.exportToGallery', () {
    test('renders, saves under the artwork title, and reports success', () async {
      final renderer = _FakeRenderer(bytes: _pngBytes);
      final galleryTarget = _RecordingGalleryTarget();
      final controller = ExportController(renderer, galleryTarget, _RecordingShareTarget());
      addTearDown(controller.dispose);

      final result = await controller.exportToGallery(_artwork(title: 'My Art'), _canvasSize);

      expect(result, isTrue);
      expect(galleryTarget.callCount, 1);
      expect(galleryTarget.savedBytes, _pngBytes);
      expect(galleryTarget.savedName, 'My Art.png');
      expect(controller.state.isExporting, isFalse);
      expect(controller.state.errorMessage, isNull);
      expect(controller.state.successMessage, 'ギャラリーに保存しました');
    });

    test('sanitizes filesystem-unsafe characters out of the artwork title', () async {
      final renderer = _FakeRenderer(bytes: _pngBytes);
      final galleryTarget = _RecordingGalleryTarget();
      final controller = ExportController(renderer, galleryTarget, _RecordingShareTarget());
      addTearDown(controller.dispose);

      await controller.exportToGallery(_artwork(title: 'a/b:c*d?e"f<g>h|i'), _canvasSize);

      expect(galleryTarget.savedName, 'a_b_c_d_e_f_g_h_i.png');
    });

    test('falls back to the artwork id when the title sanitizes to nothing', () async {
      final renderer = _FakeRenderer(bytes: _pngBytes);
      final galleryTarget = _RecordingGalleryTarget();
      final controller = ExportController(renderer, galleryTarget, _RecordingShareTarget());
      addTearDown(controller.dispose);

      await controller.exportToGallery(_artwork(title: '///', id: 'artwork-42'), _canvasSize);

      expect(galleryTarget.savedName, 'artwork-42.png');
    });

    test('sets isExporting while the render/save is in flight', () async {
      final renderGate = Completer<void>();
      final renderer = _FakeRenderer(bytes: _pngBytes, onRender: () => renderGate.future);
      final controller = ExportController(
        renderer,
        _RecordingGalleryTarget(),
        _RecordingShareTarget(),
      );
      addTearDown(controller.dispose);

      final future = controller.exportToGallery(_artwork(), _canvasSize);
      // Let the microtask that sets `isExporting = true` run before the
      // still-pending render gate is checked.
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.isExporting, isTrue);

      renderGate.complete();
      await future;
      expect(controller.state.isExporting, isFalse);
    });

    test(
      'does not call the gallery target and reports a Japanese error when rendering '
      'returns null (e.g. a zero canvas size)',
      () async {
        final renderer = _FakeRenderer(bytes: null);
        final galleryTarget = _RecordingGalleryTarget();
        final controller = ExportController(renderer, galleryTarget, _RecordingShareTarget());
        addTearDown(controller.dispose);

        final result = await controller.exportToGallery(_artwork(), Size.zero);

        expect(result, isFalse);
        expect(galleryTarget.callCount, 0);
        expect(controller.state.errorMessage, isNotNull);
        expect(controller.state.successMessage, isNull);
      },
    );

    test('never throws when rendering itself fails — surfaces a message instead', () async {
      final renderer = _FakeRenderer(error: Exception('boom'));
      final galleryTarget = _RecordingGalleryTarget();
      final controller = ExportController(renderer, galleryTarget, _RecordingShareTarget());
      addTearDown(controller.dispose);

      final result = await controller.exportToGallery(_artwork(), _canvasSize);

      expect(result, isFalse);
      expect(galleryTarget.callCount, 0);
      expect(controller.state.errorMessage, contains('boom'));
    });

    test(
      'translates a GalException into its own user-facing message (Phase Hδ #19: '
      'permission denial)',
      () async {
        final renderer = _FakeRenderer(bytes: _pngBytes);
        final galleryTarget = _RecordingGalleryTarget()
          ..error = _galException(GalExceptionType.accessDenied);
        final controller = ExportController(renderer, galleryTarget, _RecordingShareTarget());
        addTearDown(controller.dispose);

        final result = await controller.exportToGallery(_artwork(), _canvasSize);

        expect(result, isFalse);
        expect(controller.state.errorMessage, GalExceptionType.accessDenied.message);
      },
    );

    test('never throws when the gallery target fails for disk-full (Phase Hδ #19)', () async {
      final renderer = _FakeRenderer(bytes: _pngBytes);
      final galleryTarget = _RecordingGalleryTarget()
        ..error = _galException(GalExceptionType.notEnoughSpace);
      final controller = ExportController(renderer, galleryTarget, _RecordingShareTarget());
      addTearDown(controller.dispose);

      final result = await controller.exportToGallery(_artwork(), _canvasSize);

      expect(result, isFalse);
      expect(controller.state.errorMessage, GalExceptionType.notEnoughSpace.message);
    });

    test('a fresh attempt clears the previous attempt\'s error/success message', () async {
      final renderer = _FakeRenderer(bytes: null); // first attempt fails
      final galleryTarget = _RecordingGalleryTarget();
      final controller = ExportController(renderer, galleryTarget, _RecordingShareTarget());
      addTearDown(controller.dispose);

      await controller.exportToGallery(_artwork(), Size.zero);
      expect(controller.state.errorMessage, isNotNull);

      renderer.bytes = _pngBytes; // second attempt succeeds
      await controller.exportToGallery(_artwork(), _canvasSize);
      expect(controller.state.errorMessage, isNull);
      expect(controller.state.successMessage, isNotNull);
    });
  });

  group('ExportController.exportViaShareSheet', () {
    test('renders and hands the bytes to the share target, with no success message '
        '(the share sheet is its own confirmation)', () async {
      final renderer = _FakeRenderer(bytes: _pngBytes);
      final shareTarget = _RecordingShareTarget();
      final controller = ExportController(renderer, _RecordingGalleryTarget(), shareTarget);
      addTearDown(controller.dispose);

      final result = await controller.exportViaShareSheet(_artwork(title: 'Sunset'), _canvasSize);

      expect(result, isTrue);
      expect(shareTarget.callCount, 1);
      expect(shareTarget.sharedBytes, _pngBytes);
      expect(shareTarget.sharedFileName, 'Sunset.png');
      expect(controller.state.successMessage, isNull);
      expect(controller.state.errorMessage, isNull);
    });

    test('never throws when the share sheet itself fails — surfaces a message instead', () async {
      final renderer = _FakeRenderer(bytes: _pngBytes);
      final shareTarget = _RecordingShareTarget()..error = Exception('share sheet unavailable');
      final controller = ExportController(renderer, _RecordingGalleryTarget(), shareTarget);
      addTearDown(controller.dispose);

      final result = await controller.exportViaShareSheet(_artwork(), _canvasSize);

      expect(result, isFalse);
      expect(controller.state.errorMessage, contains('share sheet unavailable'));
    });

    test('does not call the share target when rendering fails', () async {
      final renderer = _FakeRenderer(error: Exception('render failure'));
      final shareTarget = _RecordingShareTarget();
      final controller = ExportController(renderer, _RecordingGalleryTarget(), shareTarget);
      addTearDown(controller.dispose);

      await controller.exportViaShareSheet(_artwork(), _canvasSize);

      expect(shareTarget.callCount, 0);
    });
  });
}

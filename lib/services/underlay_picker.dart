import 'package:image_picker/image_picker.dart';

/// Upper bounds (in device-independent pixels) that imported underlay
/// photos are downsampled to before they ever reach app memory.
///
/// Modern phone cameras commonly produce 4K+ photos; decoding one of those
/// at full resolution can pressure native memory enough to OOM-crash the
/// app (Phase Hα 検討メモ, #18). [ImagePicker.pickImage]'s `maxWidth`/
/// `maxHeight` resize natively *before* the bytes are decoded and handed
/// back to Dart, so these constants are passed straight through to it
/// rather than resizing after the fact in Dart.
///
/// Specifying `maxWidth`/`maxHeight` also makes the platform picker
/// re-encode the photo as a standard JPEG during that native resize, which
/// doubles as a normalization step: some photos produced by older/unusual
/// image-processing tools use JPEG encodings (e.g. unusual chroma
/// subsampling or unsupported markers) that Flutter's built-in decoder can
/// fail to fully decode, observed as the bottom portion of the image
/// rendering solid black (Phase Hα 検討メモ, 2026-07-16). Passing the image
/// through the platform's own bitmap resize/re-encode step avoids handing
/// that original, potentially non-standard encoding to Flutter's decoder.
const int kUnderlayMaxWidth = 1920;
const int kUnderlayMaxHeight = 1080;

/// Thin wrapper around [ImagePicker] for choosing an underlay photo from the
/// gallery.
///
/// v1 scope (Phase Hα): the photo is imported exactly as the user picked it
/// — no in-app rotation, flip, or crop UI (see `.cursor/plans/
/// plan_phase_H_alpha.md`). Kept as its own class, separate from any
/// provider/state, so the OOM-safe resize contract (`maxWidth`/`maxHeight`)
/// lives in exactly one place, and so tests can inject a fake picker (by
/// subclassing and overriding [pickUnderlayImagePath]) without touching a
/// real platform channel.
class UnderlayPicker {
  UnderlayPicker({ImagePicker? imagePicker}) : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  /// Opens the system gallery picker and returns the picked photo's file
  /// path, already downsampled to at most [kUnderlayMaxWidth] ×
  /// [kUnderlayMaxHeight] px and re-encoded as a standard JPEG (done
  /// natively by the platform before decoding).
  ///
  /// Returns `null` if the user cancels the picker without choosing a
  /// photo. Platform failures (e.g. permission denial) propagate as
  /// whatever [ImagePicker] itself throws, for the caller to catch.
  Future<String?> pickUnderlayImagePath() async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: kUnderlayMaxWidth.toDouble(),
      maxHeight: kUnderlayMaxHeight.toDouble(),
    );
    return file?.path;
  }
}

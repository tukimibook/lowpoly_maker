import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/underlay_picker.dart';

/// The current state of the (v1: single, session-only) underlay import.
///
/// This only tracks *which file was picked* and the outcome of the most
/// recent pick attempt. It deliberately does not yet hold placement/opacity
/// (`UnderlayLayout` — world rect, opacity, on/off) or persistence; those
/// are added by later Phase Hα tasks once the canvas-fit display exists.
/// Keeping this narrow now means the picker plumbing doesn't need to be
/// revisited when that model lands.
@immutable
class UnderlayState {
  const UnderlayState({this.imagePath, this.errorMessage});

  /// Path to the imported photo, already downsampled by [UnderlayPicker]
  /// (see [kUnderlayMaxWidth]/[kUnderlayMaxHeight]). `null` if nothing has
  /// been picked yet.
  final String? imagePath;

  /// A user-facing message describing why the most recent pick attempt
  /// failed, or `null` if it succeeded (or none has been attempted). A
  /// cancelled picker (the user backs out without choosing a photo) is
  /// *not* an error — it simply leaves [imagePath] unchanged.
  final String? errorMessage;

  UnderlayState copyWith({
    Object? imagePath = _unset,
    Object? errorMessage = _unset,
  }) {
    return UnderlayState(
      imagePath: imagePath == _unset ? this.imagePath : imagePath as String?,
      errorMessage: errorMessage == _unset ? this.errorMessage : errorMessage as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is UnderlayState &&
            other.imagePath == imagePath &&
            other.errorMessage == errorMessage);
  }

  @override
  int get hashCode => Object.hash(imagePath, errorMessage);
}

/// Sentinel used by [UnderlayState.copyWith] to distinguish "leave this
/// field unchanged" from "explicitly set it to null".
const Object _unset = Object();

/// Picks an underlay photo (via [UnderlayPicker]) and exposes the resulting
/// [UnderlayState] — the imported file's path, or an error message if the
/// pick failed.
class UnderlayController extends StateNotifier<UnderlayState> {
  UnderlayController(this._picker) : super(const UnderlayState());

  final UnderlayPicker _picker;

  /// Opens the gallery picker. On success, updates [state.imagePath] and
  /// clears any previous error. If the user cancels, [state] is left
  /// untouched. If the picker itself fails (e.g. permission denial),
  /// [state.errorMessage] is set and [state.imagePath] is left untouched
  /// (the previously imported photo, if any, is not cleared by a failed
  /// re-pick attempt).
  Future<void> pickImage() async {
    try {
      final path = await _picker.pickUnderlayImagePath();
      if (path == null) return;
      state = state.copyWith(imagePath: path, errorMessage: null);
    } catch (error) {
      state = state.copyWith(errorMessage: '画像を読み込めませんでした: $error');
    }
  }

  /// Directly sets [state.imagePath] — used to restore a saved artwork's
  /// underlay (`GalleryController.openArtwork`) or clear it for a brand
  /// new one (`GalleryController.createNewArtwork`), as opposed to
  /// [pickImage]'s interactive picker flow. Always clears any previous
  /// error: a restore/reset is not a failed pick.
  void setImagePath(String? path) {
    state = UnderlayState(imagePath: path);
  }
}

/// Provides the single [UnderlayPicker] instance used to import underlay
/// photos. Exposed as a provider (rather than constructed inline in
/// [underlayProvider]) so tests can override it with a fake picker.
final underlayPickerProvider = Provider<UnderlayPicker>((ref) => UnderlayPicker());

final underlayProvider = StateNotifierProvider<UnderlayController, UnderlayState>((ref) {
  // `read`, not `watch`: the picker is a fixed dependency for the lifetime
  // of the session (only swapped in tests), and re-reading it on every
  // rebuild of some unrelated provider would recreate the controller —
  // discarding whichever photo had already been imported.
  return UnderlayController(ref.read(underlayPickerProvider));
});

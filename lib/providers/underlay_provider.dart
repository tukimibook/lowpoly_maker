import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/artwork_repository.dart';
import '../services/underlay_picker.dart';
import 'artwork_repository_provider.dart';
import 'canvas_provider.dart';

/// The current state of the (v1: single) underlay import.
///
/// Tracks *which in-app file* is the underlay and the outcome of the most
/// recent pick/copy attempt. Placement/opacity live on `UnderlayLayout`.
@immutable
class UnderlayState {
  const UnderlayState({this.imagePath, this.errorMessage});

  /// Absolute path to the underlay photo **inside the app documents
  /// directory** (`ArtworkRepository.copyUnderlayImage` destination),
  /// already downsampled by [UnderlayPicker]. `null` if nothing has been
  /// imported (or restored) yet.
  ///
  /// Never holds the picker's transient cache/gallery path — that would
  /// vanish after process death. See Phase Hγ underlay-copy fix.
  final String? imagePath;

  /// A user-facing message describing why the most recent pick/copy attempt
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

/// Picks an underlay photo (via [UnderlayPicker]), copies it into the app
/// documents `underlays/` tree, and exposes the resulting [UnderlayState].
class UnderlayController extends StateNotifier<UnderlayState> {
  UnderlayController({
    required UnderlayPicker picker,
    required Future<ArtworkRepository> Function() resolveRepository,
    required String Function() currentArtworkId,
  }) : _picker = picker, // ignore: prefer_initializing_formals
       _resolveRepository = resolveRepository, // ignore: prefer_initializing_formals
       _currentArtworkId = currentArtworkId, // ignore: prefer_initializing_formals
       super(const UnderlayState());

  final UnderlayPicker _picker;
  final Future<ArtworkRepository> Function() _resolveRepository;
  final String Function() _currentArtworkId;

  /// Opens the gallery picker. On success, copies the picked file into
  /// `underlays/<artworkId>.<ext>` and stores **that** path as
  /// [UnderlayState.imagePath] — never the picker's transient path.
  ///
  /// If the user cancels, [state] is left untouched. If the picker or the
  /// copy fails, [state.errorMessage] is set and [state.imagePath] is left
  /// untouched (a failed re-pick must not clear a previously imported
  /// photo, and must not persist a temp path).
  Future<void> pickImage() async {
    try {
      final pickedPath = await _picker.pickUnderlayImagePath();
      if (pickedPath == null) return;

      final repository = await _resolveRepository();
      final copiedPath = await repository.copyUnderlayImage(
        artworkId: _currentArtworkId(),
        sourcePath: pickedPath,
      );
      state = state.copyWith(imagePath: copiedPath, errorMessage: null);
    } catch (error) {
      state = state.copyWith(errorMessage: 'Could not load image: $error');
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
  // `read`, not `watch`: the picker / id / repository resolvers are fixed
  // dependencies for the lifetime of the session (only swapped in tests),
  // and re-creating this controller on unrelated rebuilds would discard
  // whichever photo had already been imported.
  return UnderlayController(
    picker: ref.read(underlayPickerProvider),
    resolveRepository: () => ref.read(artworkRepositoryProvider.future),
    currentArtworkId: () => ref.read(canvasProvider).id,
  );
});

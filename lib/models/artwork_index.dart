import 'package:freezed_annotation/freezed_annotation.dart';

import 'artwork_summary.dart';

part 'artwork_index.freezed.dart';

/// Current 索引ファイル (index file) JSON schema version produced by
/// [ArtworkIndex.toJson] and understood by [ArtworkIndex.fromJson]. Tracked
/// independently of [kArtworkSchemaVersion] (`models/artwork.dart`) — the
/// index file and each artwork's own `ArtworkDocument` are separate files
/// that can evolve on their own schedules.
const int kArtworkIndexSchemaVersion = 1;

/// The single index file (Phase Hγ) listing every saved artwork, read in
/// full by the gallery (作品一覧) screen on startup instead of opening each
/// artwork's own `ArtworkDocument` JSON just to render the list.
@freezed
abstract class ArtworkIndex with _$ArtworkIndex {
  const factory ArtworkIndex({@Default(<ArtworkSummary>[]) List<ArtworkSummary> artworks}) =
      _ArtworkIndex;

  /// The index before any artwork has ever been saved — an empty gallery.
  factory ArtworkIndex.empty() => const ArtworkIndex();

  factory ArtworkIndex.fromJson(Map<String, dynamic> json) {
    final artworksJson = json['artworks'] as List<dynamic>? ?? const [];
    return ArtworkIndex(
      artworks: artworksJson
          .map((entry) => ArtworkSummary.fromJson(entry as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// [ArtworkIndex.toJson] — an extension, not a class-body method; see
/// `ArtworkJson`'s doc (`models/artwork.dart`) for why freezed classes need
/// this pattern for custom instance methods.
extension ArtworkIndexJson on ArtworkIndex {
  Map<String, dynamic> toJson() => {
    'schemaVersion': kArtworkIndexSchemaVersion,
    'artworks': artworks.map((summary) => summary.toJson()).toList(),
  };
}

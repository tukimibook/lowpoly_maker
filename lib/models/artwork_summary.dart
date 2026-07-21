import 'package:freezed_annotation/freezed_annotation.dart';

part 'artwork_summary.freezed.dart';

/// One entry in [ArtworkIndex.artworks] — the lightweight metadata the
/// artwork gallery (作品一覧, Phase Hγ) needs to render a single list row
/// (thumbnail, title, last-edited date) without opening every artwork's
/// full `ArtworkDocument` JSON file just to list it.
@freezed
abstract class ArtworkSummary with _$ArtworkSummary {
  const factory ArtworkSummary({
    required String id,
    required String title,
    required DateTime updatedAt,
    required String thumbnailPath,
    required String documentPath,
  }) = _ArtworkSummary;

  factory ArtworkSummary.fromJson(Map<String, dynamic> json) {
    return ArtworkSummary(
      id: json['id'] as String,
      title: json['title'] as String,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      thumbnailPath: json['thumbnailPath'] as String,
      documentPath: json['documentPath'] as String,
    );
  }
}

/// [ArtworkSummary.toJson] — an extension, not a class-body method; see
/// `ArtworkJson`'s doc (`models/artwork.dart`) for why freezed classes need
/// this pattern for custom instance methods.
extension ArtworkSummaryJson on ArtworkSummary {
  /// [ArtworkSummary.updatedAt] is serialized via [DateTime.toIso8601String]
  /// — timezone-free (v1 has no multi-device sync to disambiguate), matching
  /// [ArtworkSummary.fromJson]'s [DateTime.parse].
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'updatedAt': updatedAt.toIso8601String(),
    'thumbnailPath': thumbnailPath,
    'documentPath': documentPath,
  };
}

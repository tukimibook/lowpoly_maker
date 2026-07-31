/// Returns [absolutePath] relative to [documentsPath], using `/` separators.
///
/// Used so underlay (and similar) paths in `ArtworkDocument` JSON stay
/// documents-directory-relative and remain resolvable after the absolute
/// documents root changes. Path separators are normalized to `/` in the
/// relative form; absolute resolution uses [documentsPath] as given.
///
/// If [absolutePath] is not under [documentsPath], falls back to the
/// trailing `underlays/...` suffix when present, otherwise the basename —
/// never throws (save must not fail because of an unexpected path shape).
String toDocumentsRelativePath(String absolutePath, String documentsPath) {
  final abs = _normalizeSlashes(absolutePath);
  final docs = _stripTrailingSlash(_normalizeSlashes(documentsPath));

  if (abs == docs) return '';
  if (abs.startsWith('$docs/')) {
    return abs.substring(docs.length + 1);
  }

  const underlaysMarker = '/underlays/';
  final underlaysIndex = abs.indexOf(underlaysMarker);
  if (underlaysIndex >= 0) {
    return abs.substring(underlaysIndex + 1); // "underlays/..."
  }

  final slash = abs.lastIndexOf('/');
  return slash < 0 ? abs : abs.substring(slash + 1);
}

/// Joins [documentsPath] with a documents-relative [relativePath].
///
/// Legacy documents that stored an absolute `imagePath` are accepted as-is
/// when [relativePath] already looks absolute (leading `/`, or a Windows
/// drive prefix like `C:`).
String resolveDocumentsAbsolutePath(String relativePath, String documentsPath) {
  final relative = _normalizeSlashes(relativePath);
  if (relative.isEmpty) {
    return _stripTrailingSlash(_normalizeSlashes(documentsPath));
  }
  if (_looksAbsolute(relative)) {
    return relativePath; // preserve original separators for legacy abs paths
  }

  final docs = _stripTrailingSlash(documentsPath);
  final relNative = relativePath.replaceAll('/', _preferredSeparator(documentsPath));
  final sep = _preferredSeparator(documentsPath);
  return '$docs$sep$relNative';
}

bool _looksAbsolute(String normalizedPath) {
  if (normalizedPath.startsWith('/')) return true;
  // Windows: "C:/..." or "C:\..." (already normalized to /)
  return normalizedPath.length >= 2 &&
      normalizedPath[1] == ':' &&
      ((normalizedPath.codeUnitAt(0) >= 65 /*A*/ && normalizedPath.codeUnitAt(0) <= 90 /*Z*/) ||
          (normalizedPath.codeUnitAt(0) >= 97 /*a*/ && normalizedPath.codeUnitAt(0) <= 122 /*z*/));
}

String _normalizeSlashes(String path) => path.replaceAll('\\', '/');

String _stripTrailingSlash(String path) {
  if (path.length > 1 && path.endsWith('/')) {
    return path.substring(0, path.length - 1);
  }
  return path;
}

String _preferredSeparator(String documentsPath) => documentsPath.contains('\\') ? '\\' : '/';

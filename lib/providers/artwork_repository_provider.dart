import 'package:file/local.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../repositories/artwork_repository.dart';

/// Resolves the app's own local documents directory (`path_provider`) —
/// isolated behind its own `FutureProvider` so [artworkRepositoryProvider]
/// doesn't need to know *how* that path is obtained, and tests can override
/// this one provider directly (e.g. with a temp directory's path) instead
/// of faking a platform channel.
final documentsPathProvider = FutureProvider<String>((ref) async {
  final directory = await getApplicationDocumentsDirectory();
  return directory.path;
});

/// The single [ArtworkRepository] instance for the running app, backed by
/// the real filesystem ([LocalFileSystem]) rooted at [documentsPathProvider].
///
/// An `AsyncValue` (via `FutureProvider`) because resolving that path is
/// itself async — the very first frame(s) will see this still loading.
/// Callers that need a definite repository-or-not right now (e.g.
/// `autoSaveServiceProvider`) should read `.valueOrNull` and treat `null`
/// as "not ready yet", exactly like `underlayImageProvider`'s consumers do
/// for image decoding.
final artworkRepositoryProvider = FutureProvider<ArtworkRepository>((ref) async {
  final documentsPath = await ref.watch(documentsPathProvider.future);
  return ArtworkRepository(fileSystem: const LocalFileSystem(), documentsPath: documentsPath);
});

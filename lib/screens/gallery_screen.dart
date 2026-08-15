import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/artwork_summary.dart';
import '../providers/gallery_provider.dart';
import '../widgets/banner_ad_bar.dart';
import '../widgets/versioned_file_image.dart';
import 'editor_screen.dart';

/// 作品一覧 (Phase Hγ): lists every saved [ArtworkSummary] from
/// [artworkIndexProvider] in a grid, and hosts all three of this phase's
/// lifecycle actions — 新規作成 (the floating action button), 開く（復帰）
/// (tapping a tile), and 削除 (each tile's overflow-free delete icon, behind
/// a confirmation dialog so a stray tap can never silently destroy a
/// finished piece).
class GalleryScreen extends ConsumerWidget {
  const GalleryScreen({super.key});

  Future<void> _openEditor(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const EditorScreen()),
    );
    // The title/thumbnail may have changed while the editor was open (or a
    // brand new artwork may have been created) — refresh so the grid
    // reflects that the moment the artist comes back to it.
    ref.invalidate(artworkIndexProvider);
  }

  Future<void> _handleNew(BuildContext context, WidgetRef ref) async {
    ref.read(galleryControllerProvider).createNewArtwork();
    await _openEditor(context, ref);
  }

  Future<void> _handleOpen(BuildContext context, WidgetRef ref, String id) async {
    final opened = await ref.read(galleryControllerProvider).openArtwork(id);
    if (!context.mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open artwork')),
      );
      return;
    }
    await _openEditor(context, ref);
  }

  Future<void> _handleDelete(BuildContext context, WidgetRef ref, ArtworkSummary summary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete artwork?'),
          content: Text('Delete "${summary.title}"? This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await ref.read(galleryControllerProvider).deleteArtwork(summary.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final indexAsync = ref.watch(artworkIndexProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gallery'),
        // Prefer a home icon over the default back arrow so artists do not
        // mistake this control for "return to the editor" after save-and-exit
        // (real-device feedback). Behavior is unchanged: pop to Home.
        leading: IconButton(
          key: const Key('gallery-return-home-button'),
          tooltip: 'Return to Home',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.home, semanticLabel: 'Return to Home'),
        ),
      ),
      bottomNavigationBar: const BannerAdBar(),
      floatingActionButton: FloatingActionButton(
        key: const Key('gallery-new-fab'),
        tooltip: 'New Artwork',
        onPressed: () => _handleNew(context, ref),
        child: const Icon(Icons.add),
      ),
      body: indexAsync.when(
        data: (index) {
          if (index.artworks.isEmpty) {
            return const _EmptyGallery();
          }
          final artworks = index.artworks.toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.82,
            ),
            itemCount: artworks.length,
            itemBuilder: (context, i) {
              final summary = artworks[i];
              return _ArtworkTile(
                key: Key('gallery-tile-${summary.id}'),
                summary: summary,
                onOpen: () => _handleOpen(context, ref, summary.id),
                onDelete: () => _handleDelete(context, ref, summary),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text('Could not load gallery: $error'),
        ),
      ),
    );
  }
}

class _EmptyGallery extends StatelessWidget {
  const _EmptyGallery();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            const Text('No artworks yet', textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Tap + to create a new artwork',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtworkTile extends StatelessWidget {
  const _ArtworkTile({
    super.key,
    required this.summary,
    required this.onOpen,
    required this.onDelete,
  });

  final ArtworkSummary summary;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _Thumbnail(
                path: summary.thumbnailPath,
                updatedAt: summary.updatedAt,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      summary.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  IconButton(
                    key: Key('gallery-delete-${summary.id}'),
                    tooltip: 'Delete',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: onDelete,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.path, required this.updatedAt});

  final String path;

  /// Bumped whenever the artwork's index entry is rewritten (see
  /// `AutoSaveService._saveNow`) — fed into both [VersionedFileImage]'s
  /// cache key and this widget's [ValueKey] so an in-place thumbnail
  /// overwrite at the same [path] reloads declaratively (defect-fix #4).
  final DateTime updatedAt;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      // A synchronous existence check first, rather than always mounting
      // `Image` and relying on its `errorBuilder`: a never-generated
      // (or deleted) thumbnail is common and expected (e.g. before the
      // very first auto-save has completed), not exceptional, so this
      // avoids kicking off a real, unnecessary async decode attempt that
      // is guaranteed to fail every single time for that artwork.
      child: File(path).existsSync()
          ? Image(
              image: VersionedFileImage(File(path), updatedAt),
              key: ValueKey(updatedAt),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (context, error, stackTrace) => _placeholder(context),
            )
          : _placeholder(context),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Center(
      child: Icon(
        Icons.image_not_supported_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

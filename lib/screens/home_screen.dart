import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../providers/gallery_provider.dart';
import '../widgets/banner_ad_bar.dart';
import '../widgets/gallery_quota_dialog.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isCreating = false;

  Future<void> _handleNewArtwork() async {
    if (_isCreating) return;
    setState(() => _isCreating = true);
    try {
      final prepared = await prepareNewArtworkIfSlotAvailable(
        context: context,
        ref: ref,
      );
      if (!prepared || !mounted) return;
      await Navigator.of(context).pushNamed(PolygonArtApp.editorRoute);
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Prefetch the gallery index so a New Artwork tap can quota-check against
    // a ready repository instead of fail-opening on the first frame.
    ref.watch(artworkIndexProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Polygon Art'),
      ),
      bottomNavigationBar: const BannerAdBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.pentagon_outlined,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Polygon Art',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Tap points to create polygon art',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                key: const Key('home-new-artwork-button'),
                onPressed: _isCreating ? null : _handleNewArtwork,
                icon: const Icon(Icons.add),
                label: const Text('New Artwork'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pushNamed(PolygonArtApp.galleryRoute);
                },
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Gallery'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

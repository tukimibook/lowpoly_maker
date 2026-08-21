import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../providers/gallery_provider.dart';
import '../services/consent_service.dart';
import '../widgets/banner_ad_bar.dart';
import '../widgets/gallery_quota_dialog.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    unawaited(ConsentService.instance.ensureConsent());
  }

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
        title: const Text('Lowpoly Maker'),
        actions: [
          IconButton(
            key: const Key('home-about-button'),
            tooltip: 'About',
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              Navigator.of(context).pushNamed(PolygonArtApp.aboutRoute);
            },
          ),
        ],
      ),
      bottomNavigationBar: const BannerAdBar(),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: constraints.maxWidth,
                minHeight: constraints.maxHeight,
              ),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/app_icon_fg.png',
                        width: 120,
                        height: 120,
                        excludeFromSemantics: true, // 直下のテキストで既に説明されているため、装飾画像として扱う
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Lowpoly Maker',
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
            ),
          );
        },
      ),
    );
  }
}

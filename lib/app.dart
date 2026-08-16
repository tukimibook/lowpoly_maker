import 'package:flutter/material.dart';

import 'screens/editor_screen.dart';
import 'screens/gallery_screen.dart';
import 'screens/home_screen.dart';
import 'services/ad_config.dart';

/// Seed color every [ThemeData] (light and dark alike) is generated from,
/// so both variants read as the same brand rather than two unrelated
/// palettes.
const Color _seedColor = Color(0xFF5C6BC0);

class PolygonArtApp extends StatelessWidget {
  const PolygonArtApp({super.key});

  static const String homeRoute = '/';
  static const String editorRoute = '/editor';
  static const String galleryRoute = '/gallery';

  /// Builds the app's [ThemeData] for [brightness]. Every widget outside the
  /// canvas (see `EditorScreen`'s independent
  /// `canvasBackgroundProvider`) should read its colors from
  /// `Theme.of(context).colorScheme` rather than hardcoding them, so this
  /// single seed is what drives the whole app's look in both modes.
  static ThemeData _themeFor(Brightness brightness) {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: brightness,
      ),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(centerTitle: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lowpoly Maker',
      debugShowCheckedModeBanner: false,
      theme: _themeFor(Brightness.light),
      darkTheme: _themeFor(Brightness.dark),
      // Lets `BannerAdBar` (Home/Gallery) know when its route is covered by
      // another route vs. back on top, so it can tear down/reload instead of
      // refreshing an ad nobody can see (Phase R memory-management pass).
      navigatorObservers: [adRouteObserver],
      // No explicit themeMode: this deliberately falls back to the
      // MaterialApp default (ThemeMode.system), so the app chrome follows
      // whatever the OS is set to. An in-app override (light/dark/system)
      // can be added later (e.g. Phase H+'s settings) without needing to
      // touch anything else, since every screen already reads its colors
      // from the theme rather than hardcoding them.
      initialRoute: homeRoute,
      routes: {
        homeRoute: (context) => const HomeScreen(),
        editorRoute: (context) => const EditorScreen(),
        galleryRoute: (context) => const GalleryScreen(),
      },
    );
  }
}

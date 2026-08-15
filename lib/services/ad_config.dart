import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Phase R: AdMob identifiers.
///
/// **Always Google's official Android test IDs while developing.** Using a
/// real account's app/unit IDs with test traffic can get the AdMob account
/// banned. Production IDs are swapped in only at store-release wiring.
abstract final class AdConfig {
  /// Android test App ID (`AndroidManifest` `APPLICATION_ID`).
  static const String androidAppId = 'ca-app-pub-3940256099942544~3347511713';

  /// Android test banner unit ID.
  static const String androidBannerUnitId =
      'ca-app-pub-3940256099942544/6300978111';

  /// Ads run only on a real Android device/emulator, never in widget tests.
  static bool get isEnabled {
    if (kIsWeb) return false;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    return Platform.isAndroid;
  }
}

/// Registered on [PolygonArtApp]'s `navigatorObservers` and subscribed to by
/// every `BannerAdBar` instance, so a banner is torn down the moment its
/// screen is pushed behind another route (e.g. Home -> Editor) instead of
/// continuing to refresh/consume memory and network while invisible.
final RouteObserver<PageRoute<dynamic>> adRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

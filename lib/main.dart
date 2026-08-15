import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'app.dart';
import 'services/ad_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AdConfig.isEnabled) {
    await MobileAds.instance.initialize();
  }
  runApp(const ProviderScope(child: PolygonArtApp()));
}

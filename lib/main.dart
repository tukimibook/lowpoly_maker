import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/legal_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LegalConfig.registerVendoredLicenses();
  runApp(const ProviderScope(child: PolygonArtApp()));
}

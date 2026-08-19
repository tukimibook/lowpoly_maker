import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Store-facing legal URLs and labels (Phase R).
///
/// Keep this off the editor/canvas path — Home / About only.
abstract final class LegalConfig {
  /// Public privacy-policy page opened in an external browser.
  static const String privacyPolicyUrl =
      'https://tukimibook.github.io/lowpoly_maker/privacy_policy.html';

  // TODO(iOS): When adding an iOS target, declare the equivalent URL-query
  // entries in ios/Runner/Info.plist so url_launcher can open this https
  // URL (Android counterpart: <queries> VIEW/https in AndroidManifest.xml).

  /// Registers vendored (non-pub-package) OSS licenses so they appear on
  /// the `showLicensePage` screen alongside pub.dev dependencies, which
  /// Flutter's tooling collects automatically. Call once from `main()`
  /// before `runApp`.
  static void registerVendoredLicenses() {
    LicenseRegistry.addLicense(() async* {
      try {
        final license = await rootBundle.loadString(
          'lib/geometry/vendor/poly2tri/LICENSE',
        );
        yield LicenseEntryWithLineBreaks(['poly2tri'], license);
      } catch (error, stackTrace) {
        // A missing/renamed asset must never break the License page (which
        // also lists every pub.dev dependency) or app boot.
        debugPrint(
          'LegalConfig: failed to load poly2tri LICENSE: $error\n$stackTrace',
        );
      }
    });
  }
}

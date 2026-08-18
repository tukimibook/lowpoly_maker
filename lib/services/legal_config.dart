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
}

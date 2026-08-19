import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/consent_service.dart';

/// Indirection so widget tests can override with a fake
/// (`extends ConsentService`, see `ConsentService.forTesting`) instead of
/// relying on `AdConfig.isEnabled` being false under `FLUTTER_TEST` — same
/// pattern as `artworkRepositoryProvider`.
final consentServiceProvider = Provider<ConsentService>((ref) {
  return ConsentService.instance;
});

/// Whether `AboutScreen` should show the "Privacy options" entry point
/// (GDPR re-consent). `autoDispose` since it is only read while the About
/// screen is on-screen.
final privacyOptionsRequiredProvider = FutureProvider.autoDispose<bool>((
  ref,
) {
  return ref.watch(consentServiceProvider).isPrivacyOptionsRequired();
});

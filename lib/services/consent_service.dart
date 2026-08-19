import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';

/// Google UMP consent + AdMob SDK init, confined to Home/Gallery (Phase R).
///
/// Never import this from the editor canvas path. Fail-closed for ads:
/// if consent or init fails, [adsReady] stays false and the UI still works.
class ConsentService {
  ConsentService._();

  /// Test-only escape hatch so a fake can `extends ConsentService` and
  /// override just the methods a given test cares about — same pattern as
  /// `_TestArtworkRepository extends ArtworkRepository` elsewhere in this
  /// codebase. Lets widget tests inject explicit consent state instead of
  /// relying on the ambient `AdConfig.isEnabled` (false under
  /// `FLUTTER_TEST`).
  @visibleForTesting
  ConsentService.forTesting();

  static final ConsentService instance = ConsentService._();

  static const Duration _consentTimeout = Duration(seconds: 8);
  static const Duration _canRequestAdsTimeout = Duration(seconds: 2);

  /// Extra grace period after [_consentTimeout] elapses, giving a
  /// merely-slow (not hung) consent flow one more chance to resolve via
  /// the real native callback (`completeOk`/`completeErr`) before the
  /// safety net in [_scheduleTimeoutFallback] re-checks `canRequestAds()`
  /// itself.
  static const Duration _postTimeoutGracePeriod = Duration(seconds: 4);

  /// Becomes true only after UMP has resolved, [canRequestAds] is true,
  /// and [MobileAds.initialize] has completed. [BannerAdBar] listens here
  /// so the first Home visit still loads a banner after a late consent.
  final ValueNotifier<bool> adsReady = ValueNotifier<bool>(false);

  Future<void>? _inFlight;
  bool _adsInitialized = false;
  bool _finalizing = false;

  /// Fire-and-forget from [HomeScreen]: never blocks [runApp] or the first
  /// frame. No-ops in tests / non-Android (`AdConfig.isEnabled` is false).
  Future<void> ensureConsent() {
    if (!AdConfig.isEnabled) return Future<void>.value();
    return _inFlight ??= _run();
  }

  Future<void> _run() async {
    try {
      await _requestConsentChain().timeout(_consentTimeout);
      // Resolved (successfully or with a form/consent error) before the
      // timeout — completeOk/completeErr already triggered _finalizeAds().
      return;
    } on TimeoutException catch (error, stackTrace) {
      debugPrint('ConsentService: UMP timed out after ${_consentTimeout.inSeconds}s: $error\n$stackTrace');
    } catch (error, stackTrace) {
      debugPrint('ConsentService: UMP failed: $error\n$stackTrace');
    }
    // Safety net only: if the native SDK callbacks (completeOk/completeErr)
    // never fire at all — a fully wedged platform channel — nothing would
    // ever call _finalizeAds() and ads would stay disabled for the rest of
    // the session. Schedule ONE delayed re-check, decoupled from this
    // already-returned Future (so ensureConsent() still resolves promptly
    // for ANR safety), instead of calling _finalizeAds() here directly —
    // that would treat "gave up waiting" as if the flow had completed.
    unawaited(_scheduleTimeoutFallback());
  }

  /// See the safety-net note in [_run]. A no-op if [completeOk]/[completeErr]
  /// already resolved things during the grace period ([_finalizeAds]'s own
  /// `_adsInitialized` guard also makes a second call harmless either way).
  Future<void> _scheduleTimeoutFallback() async {
    await Future<void>.delayed(_postTimeoutGracePeriod);
    if (_adsInitialized) return;
    await _finalizeAds();
  }

  /// Wraps both UMP stages in one [Completer] so a single timeout covers
  /// `requestConsentInfoUpdate` and `loadAndShowConsentFormIfRequired`.
  Future<void> _requestConsentChain() {
    final completer = Completer<void>();

    void completeOk() {
      if (!completer.isCompleted) completer.complete();
      unawaited(_finalizeAds());
    }

    void completeErr(Object error) {
      if (!completer.isCompleted) completer.completeError(error);
      unawaited(_finalizeAds());
    }

    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(
          tagForUnderAgeOfConsent: false,
          consentDebugSettings: kDebugMode ? _debugSettings() : null,
        ),
        () {
          unawaited(
            ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
              if (error != null) {
                completeErr(error);
              } else {
                completeOk();
              }
            }).catchError(completeErr),
          );
        },
        completeErr,
      );
    } catch (error) {
      completeErr(error);
    }

    return completer.future;
  }

  Future<void> _finalizeAds() async {
    if (_adsInitialized || _finalizing) return;
    _finalizing = true;
    try {
      final canRequest = await ConsentInformation.instance
          .canRequestAds()
          .timeout(_canRequestAdsTimeout, onTimeout: () => false);
      if (!canRequest) return;
      await MobileAds.instance.initialize();
      _adsInitialized = true;
      adsReady.value = true;
    } catch (error, stackTrace) {
      debugPrint('ConsentService: ads init failed: $error\n$stackTrace');
    } finally {
      _finalizing = false;
    }
  }

  /// Whether `AboutScreen` should show a "Privacy options" entry point so
  /// the user can revisit their choice (GDPR re-consent). `false` outside
  /// Android / in tests, same convention as [ensureConsent].
  Future<bool> isPrivacyOptionsRequired() async {
    if (!AdConfig.isEnabled) return false;
    try {
      final status = await ConsentInformation.instance
          .getPrivacyOptionsRequirementStatus();
      return status == PrivacyOptionsRequirementStatus.required;
    } catch (error, stackTrace) {
      debugPrint(
        'ConsentService: getPrivacyOptionsRequirementStatus failed: '
        '$error\n$stackTrace',
      );
      return false;
    }
  }

  /// Re-opens the UMP privacy-options form (the "Privacy options" tile in
  /// `AboutScreen`). No-ops outside Android / in tests. Re-evaluates
  /// [canRequestAds] afterwards so [adsReady] (and `BannerAdBar`) picks up
  /// an opt-out without waiting for the next app launch.
  Future<void> showPrivacyOptionsForm() async {
    if (!AdConfig.isEnabled) return;
    try {
      await ConsentForm.showPrivacyOptionsForm((FormError? error) {
        if (error != null) {
          debugPrint('ConsentService: privacy options form error: $error');
        }
      }).timeout(_consentTimeout);
    } catch (error, stackTrace) {
      debugPrint(
        'ConsentService: showPrivacyOptionsForm failed: $error\n$stackTrace',
      );
    }
    // The user's choice may have changed canRequestAds() (e.g. opting out
    // after previously opting in) — _finalizeAds() only ever flips
    // adsReady to true, never back to false, so a true->false transition
    // still requires an app restart; that is an acceptable v1 trade-off.
    unawaited(_finalizeAds());
  }

  /// Debug-only. Paste the hashed device ID from logcat
  /// (`Use new ConsentDebugSettings.Builder().addTestDeviceHashedId`)
  /// into [ConsentDebugSettings.testIdentifiers] to force the EEA form.
  static ConsentDebugSettings? _debugSettings() {
    return ConsentDebugSettings(
      // testIdentifiers: ['TEST-DEVICE-HASHED-ID'],
      // debugGeography: DebugGeography.debugGeographyEea,
    );
  }
}

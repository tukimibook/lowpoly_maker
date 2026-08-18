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

  static final ConsentService instance = ConsentService._();

  static const Duration _consentTimeout = Duration(seconds: 8);
  static const Duration _canRequestAdsTimeout = Duration(seconds: 2);

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
    } on TimeoutException catch (error, stackTrace) {
      debugPrint('ConsentService: UMP timed out: $error\n$stackTrace');
    } catch (error, stackTrace) {
      debugPrint('ConsentService: UMP failed: $error\n$stackTrace');
    }
    // Timeout or form error must not freeze the UI. A late form dismiss
    // still calls [_finalizeAds] from the native callback below.
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

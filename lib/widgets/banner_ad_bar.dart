import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/ad_config.dart';

/// Bottom-anchored AdMob banner. Mount only on Home and Gallery — never on
/// the editor canvas (Phase R: ads stay off the drawing path).
class BannerAdBar extends StatefulWidget {
  const BannerAdBar({super.key});

  @override
  State<BannerAdBar> createState() => _BannerAdBarState();
}

class _BannerAdBarState extends State<BannerAdBar> with RouteAware {
  static const int _maxLoadAttempts = 3;

  BannerAd? _bannerAd;
  bool _isLoaded = false;
  bool _disposed = false;
  int _loadAttempts = 0;
  Timer? _retryTimer;
  PageRoute<dynamic>? _subscribedRoute;

  @override
  void initState() {
    super.initState();
    if (!AdConfig.isEnabled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadAd();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!AdConfig.isEnabled) return;
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && !identical(route, _subscribedRoute)) {
      if (_subscribedRoute != null) {
        adRouteObserver.unsubscribe(this);
      }
      _subscribedRoute = route;
      adRouteObserver.subscribe(this, route);
    }
  }

  /// Another route was just pushed on top of this screen's route — the
  /// banner is now hidden behind it, so tear it down instead of letting it
  /// keep refreshing (memory/network) for an ad nobody can see.
  @override
  void didPushNext() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _bannerAd?.dispose();
    _bannerAd = null;
    if (_isLoaded) setState(() => _isLoaded = false);
  }

  /// Back on top again (the route from [didPushNext] was popped) — reload
  /// from scratch since the previous banner was fully torn down.
  @override
  void didPopNext() {
    _loadAttempts = 0;
    _loadAd();
  }

  void _loadAd() {
    if (_disposed || _loadAttempts >= _maxLoadAttempts) return;
    _loadAttempts += 1;
    _bannerAd?.dispose();

    final bannerAd = BannerAd(
      adUnitId: AdConfig.androidBannerUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('BannerAd loaded');
          // A stale callback for an ad a teardown path (didPushNext or
          // dispose) already disposed — do not touch it or this State again.
          if (_disposed || !identical(ad, _bannerAd)) return;
          setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('BannerAd failed to load: $error');
          if (_disposed || !identical(ad, _bannerAd)) return;
          ad.dispose();
          setState(() {
            _bannerAd = null;
            _isLoaded = false;
          });
          _retryTimer?.cancel();
          _retryTimer = Timer(const Duration(seconds: 2), () {
            if (!_disposed && !_isLoaded) _loadAd();
          });
        },
      ),
    );
    _bannerAd = bannerAd;
    bannerAd.load();
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    adRouteObserver.unsubscribe(this);
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AdConfig.isEnabled) return const SizedBox.shrink();

    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: AdSize.banner.height.toDouble(),
          child: _isLoaded && _bannerAd != null
              ? Center(
                  child: SizedBox(
                    width: _bannerAd!.size.width.toDouble(),
                    height: _bannerAd!.size.height.toDouble(),
                    child: AdWidget(ad: _bannerAd!),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

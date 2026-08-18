import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/services/consent_service.dart';

void main() {
  test(
    'ensureConsent returns immediately when ads are disabled (widget tests)',
    () async {
      await ConsentService.instance.ensureConsent().timeout(
        const Duration(milliseconds: 200),
      );
      expect(ConsentService.instance.adsReady.value, isFalse);
    },
  );
}

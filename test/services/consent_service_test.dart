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

  group('outside Android / under FLUTTER_TEST (AdConfig.isEnabled == false)', () {
    test('isPrivacyOptionsRequired resolves to false without touching UMP', () async {
      final service = ConsentService.forTesting();
      final required = await service
          .isPrivacyOptionsRequired()
          .timeout(const Duration(milliseconds: 200));
      expect(required, isFalse);
    });

    test('showPrivacyOptionsForm no-ops without touching UMP', () async {
      final service = ConsentService.forTesting();
      await service.showPrivacyOptionsForm().timeout(
        const Duration(milliseconds: 200),
      );
    });
  });
}

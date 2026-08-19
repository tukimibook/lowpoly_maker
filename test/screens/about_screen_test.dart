import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/providers/consent_provider.dart';
import 'package:polygon_art_app/screens/about_screen.dart';
import 'package:polygon_art_app/services/consent_service.dart';

/// Explicit test double — see `ConsentService.forTesting()`'s doc for why
/// this is preferred over relying on `AdConfig.isEnabled`.
class _FakeConsentService extends ConsentService {
  _FakeConsentService({required this.privacyOptionsRequired})
    : super.forTesting();

  final bool privacyOptionsRequired;
  int showPrivacyOptionsFormCallCount = 0;

  @override
  Future<bool> isPrivacyOptionsRequired() async => privacyOptionsRequired;

  @override
  Future<void> showPrivacyOptionsForm() async {
    showPrivacyOptionsFormCallCount++;
  }
}

Widget _pumpAbout(_FakeConsentService fake) {
  return ProviderScope(
    overrides: [consentServiceProvider.overrideWithValue(fake)],
    child: const MaterialApp(home: AboutScreen()),
  );
}

void main() {
  testWidgets('shows privacy policy and OSS license entries', (tester) async {
    await tester.pumpWidget(
      _pumpAbout(_FakeConsentService(privacyOptionsRequired: false)),
    );
    await tester.pumpAndSettle();

    expect(find.text('About'), findsOneWidget);
    expect(find.byKey(const Key('about-privacy-policy-tile')), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.byKey(const Key('about-oss-licenses-tile')), findsOneWidget);
    expect(find.text('Open Source Licenses'), findsOneWidget);
  });

  testWidgets('Open Source Licenses opens the Flutter license page', (
    tester,
  ) async {
    await tester.pumpWidget(
      _pumpAbout(_FakeConsentService(privacyOptionsRequired: false)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('about-oss-licenses-tile')));
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('Lowpoly Maker'), findsWidgets);
  });

  group('Privacy options', () {
    testWidgets('hidden when not required', (tester) async {
      await tester.pumpWidget(
        _pumpAbout(_FakeConsentService(privacyOptionsRequired: false)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('about-privacy-options-tile')),
        findsNothing,
      );
    });

    testWidgets(
      'shown and opens the form when required',
      (tester) async {
        final fake = _FakeConsentService(privacyOptionsRequired: true);
        await tester.pumpWidget(_pumpAbout(fake));
        await tester.pumpAndSettle();

        final tileFinder = find.byKey(
          const Key('about-privacy-options-tile'),
        );
        expect(tileFinder, findsOneWidget);
        expect(find.text('Privacy Options'), findsOneWidget);

        await tester.tap(tileFinder);
        await tester.pumpAndSettle();

        expect(fake.showPrivacyOptionsFormCallCount, 1);
      },
    );
  });
}

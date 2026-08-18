import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/screens/about_screen.dart';

void main() {
  testWidgets('shows privacy policy and OSS license entries', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));

    expect(find.text('About'), findsOneWidget);
    expect(find.byKey(const Key('about-privacy-policy-tile')), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.byKey(const Key('about-oss-licenses-tile')), findsOneWidget);
    expect(find.text('Open Source Licenses'), findsOneWidget);
  });

  testWidgets('Open Source Licenses opens the Flutter license page', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));

    await tester.tap(find.byKey(const Key('about-oss-licenses-tile')));
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('Lowpoly Maker'), findsWidgets);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/app.dart';

void main() {
  testWidgets('Home screen shows new artwork button', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: PolygonArtApp()),
    );

    expect(find.text('Polygon Art'), findsOneWidget);
    expect(find.text('新規作成'), findsOneWidget);
  });

  testWidgets('Tapping new artwork navigates to editor', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: PolygonArtApp()),
    );

    await tester.tap(find.text('新規作成'));
    await tester.pumpAndSettle();

    expect(find.text('無題の作品'), findsOneWidget);
    expect(find.text('閉じる'), findsOneWidget);
  });

  testWidgets('Tapping the canvas three times enables closing a polygon', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: PolygonArtApp()),
    );
    await tester.tap(find.text('新規作成'));
    await tester.pumpAndSettle();

    final closeButtonFinder = find.widgetWithText(FilledButton, '閉じる');
    expect(tester.widget<FilledButton>(closeButtonFinder).onPressed, isNull);

    final canvasCenter = tester.getCenter(find.byType(CustomPaint).first);
    await tester.tapAt(canvasCenter + const Offset(-40, -40));
    await tester.pump();
    await tester.tapAt(canvasCenter + const Offset(40, -40));
    await tester.pump();
    await tester.tapAt(canvasCenter + const Offset(0, 40));
    await tester.pump();

    expect(tester.widget<FilledButton>(closeButtonFinder).onPressed, isNotNull);
  });
}

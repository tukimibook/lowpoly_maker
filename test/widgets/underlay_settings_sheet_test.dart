import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/providers/underlay_layout_provider.dart';
import 'package:polygon_art_app/widgets/underlay/underlay_settings_sheet.dart';

Future<void> _pumpSheet(WidgetTester tester, ProviderContainer container) {
  return tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Material(child: UnderlaySettingsSheet())),
    ),
  );
}

void main() {
  group('UnderlaySettingsSheet', () {
    testWidgets('defaults to visible and fully opaque, matching UnderlayLayout.initial', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await _pumpSheet(tester, container);

      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
      final segmented = tester.widget<SegmentedButton<double>>(
        find.byType(SegmentedButton<double>),
      );
      expect(segmented.selected, {1.0});
    });

    testWidgets('toggling the switch flips UnderlayLayout.visible, live', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await _pumpSheet(tester, container);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();

      expect(container.read(underlayLayoutProvider).value.visible, isFalse);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);
    });

    testWidgets('tapping an opacity segment updates .opacity immediately, no confirm step', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await _pumpSheet(tester, container);

      await tester.tap(find.text('40%'));
      await tester.pump();

      expect(container.read(underlayLayoutProvider).value.opacity, 0.4);
      final segmented = tester.widget<SegmentedButton<double>>(
        find.byType(SegmentedButton<double>),
      );
      expect(segmented.selected, {0.4});
    });

    testWidgets('offers exactly the five documented steps: 20/40/60/80/100%', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await _pumpSheet(tester, container);

      for (final label in ['20%', '40%', '60%', '80%', '100%']) {
        expect(find.text(label), findsOneWidget);
      }
    });
  });
}

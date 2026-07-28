import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/providers/underlay_provider.dart';
import 'package:polygon_art_app/widgets/toolbar/editor_toolbar.dart';

Finder _clearButton() => find.byKey(const Key('underlay-clear-button'));

void main() {
  group('EditorToolbar underlay clear button', () {
    Future<ProviderContainer> pumpToolbar(WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: EditorToolbar()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('is disabled when there is no underlay', (tester) async {
      await pumpToolbar(tester);

      final button = tester.widget<IconButton>(_clearButton());
      expect(button.onPressed, isNull);
      expect(button.tooltip, 'Remove underlay');
    });

    testWidgets('is enabled after an underlay path is set, and clears it on tap', (tester) async {
      final container = await pumpToolbar(tester);

      container.read(underlayProvider.notifier).setImagePath('/tmp/underlay.jpg');
      await tester.pump();

      final enabled = tester.widget<IconButton>(_clearButton());
      expect(enabled.onPressed, isNotNull);
      expect(container.read(underlayProvider).imagePath, '/tmp/underlay.jpg');

      await tester.tap(_clearButton());
      await tester.pump();

      expect(container.read(underlayProvider).imagePath, isNull);
      expect(tester.widget<IconButton>(_clearButton()).onPressed, isNull);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/providers/underlay_provider.dart';
import 'package:polygon_art_app/widgets/toolbar/underlay_menu_button.dart';

Finder _menuButton() => find.byKey(const Key('underlay-menu-button'));
Finder _clearItem() => find.byKey(const Key('underlay-clear-button'));

void main() {
  group('UnderlayMenuButton remove underlay', () {
    Future<ProviderContainer> pumpMenu(WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              appBar: AppBar(actions: const [UnderlayMenuButton()]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(_menuButton());
      await tester.pumpAndSettle();
    }

    testWidgets('Remove is disabled when there is no underlay', (tester) async {
      await pumpMenu(tester);
      await openMenu(tester);

      final item = tester.widget<MenuItemButton>(_clearItem());
      expect(item.onPressed, isNull);
      expect(find.text('Remove underlay'), findsOneWidget);
    });

    testWidgets('Remove is enabled after an underlay path is set, and clears it on tap', (
      tester,
    ) async {
      final container = await pumpMenu(tester);

      container.read(underlayProvider.notifier).setImagePath('/tmp/underlay.jpg');
      await tester.pump();

      await openMenu(tester);
      final enabled = tester.widget<MenuItemButton>(_clearItem());
      expect(enabled.onPressed, isNotNull);
      expect(container.read(underlayProvider).imagePath, '/tmp/underlay.jpg');

      await tester.tap(_clearItem());
      await tester.pumpAndSettle();

      expect(container.read(underlayProvider).imagePath, isNull);

      await openMenu(tester);
      expect(tester.widget<MenuItemButton>(_clearItem()).onPressed, isNull);
    });
  });
}

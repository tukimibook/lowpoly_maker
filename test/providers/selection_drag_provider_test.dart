import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/providers/selection_drag_provider.dart';

void main() {
  group('SelectionDragController', () {
    test('add inserts a new id and notifies listeners once', () {
      final controller = SelectionDragController();
      var notifications = 0;
      controller.addListener(() => notifications++);

      expect(controller.add('p1'), isTrue);
      expect(controller.value, {'p1'});
      expect(notifications, 1);

      expect(controller.add('p2'), isTrue);
      expect(controller.value, unorderedEquals({'p1', 'p2'}));
      expect(notifications, 2);
    });

    test('add is idempotent — duplicate id does not notify', () {
      final controller = SelectionDragController();
      controller.add('p1');
      var notifications = 0;
      controller.addListener(() => notifications++);

      expect(controller.add('p1'), isFalse);
      expect(controller.value, {'p1'});
      expect(notifications, 0);
    });

    test('clear empties the set and notifies; second clear is a no-op', () {
      final controller = SelectionDragController();
      controller.add('p1');
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.clear();
      expect(controller.value, isEmpty);
      expect(notifications, 1);

      controller.clear();
      expect(notifications, 1);
    });

    test('remove drops a selected id and notifies listeners once', () {
      final controller = SelectionDragController();
      controller.add('p1');
      controller.add('p2');
      var notifications = 0;
      controller.addListener(() => notifications++);

      expect(controller.remove('p1'), isTrue);
      expect(controller.value, {'p2'});
      expect(notifications, 1);
    });

    test('remove is idempotent — unknown id does not notify', () {
      final controller = SelectionDragController();
      controller.add('p1');
      var notifications = 0;
      controller.addListener(() => notifications++);

      expect(controller.remove('missing'), isFalse);
      expect(controller.value, {'p1'});
      expect(notifications, 0);
    });
  });
}

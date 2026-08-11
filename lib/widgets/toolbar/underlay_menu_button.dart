import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/underlay_layout.dart';
import '../../providers/underlay_layout_provider.dart';
import '../../providers/underlay_provider.dart';

/// AppBar control that folds underlay import / remove / visibility / opacity
/// into one [MenuAnchor] panel — presentation only; mutates
/// [underlayProvider] and [underlayLayoutProvider].
class UnderlayMenuButton extends ConsumerWidget {
  const UnderlayMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasUnderlay =
        ref.watch(underlayProvider.select((state) => state.imagePath != null));
    final layoutController = ref.watch(underlayLayoutProvider);

    return MenuAnchor(
      consumeOutsideTap: true,
      builder: (context, controller, child) {
        return IconButton(
          key: const Key('underlay-menu-button'),
          tooltip: 'Underlay',
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          icon: Icon(hasUnderlay ? Icons.image : Icons.image_outlined),
        );
      },
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.add_photo_alternate_outlined),
          onPressed: () {
            ref.read(underlayProvider.notifier).pickImage();
          },
          child: Text(hasUnderlay ? 'Replace underlay' : 'Import underlay'),
        ),
        MenuItemButton(
          key: const Key('underlay-clear-button'),
          leadingIcon: const Icon(Icons.hide_image_outlined),
          onPressed: hasUnderlay
              ? () => ref.read(underlayProvider.notifier).setImagePath(null)
              : null,
          child: const Text('Remove underlay'),
        ),
        const Divider(),
        ValueListenableBuilder<UnderlayLayout>(
          valueListenable: layoutController,
          builder: (context, layout, _) {
            return MenuItemButton(
              leadingIcon: Icon(
                layout.visible ? Icons.visibility : Icons.visibility_off,
              ),
              onPressed: hasUnderlay
                  ? () => layoutController.setVisible(!layout.visible)
                  : null,
              child: Text(layout.visible ? 'Hide underlay' : 'Show underlay'),
            );
          },
        ),
        ValueListenableBuilder<UnderlayLayout>(
          valueListenable: layoutController,
          builder: (context, layout, _) {
            final percent = (layout.opacity * 100).round();
            return SubmenuButton(
              key: const Key('underlay-opacity-button'),
              leadingIcon: const Icon(Icons.opacity),
              menuChildren: [
                for (final step in kUnderlayOpacitySteps)
                  MenuItemButton(
                    key: Key('underlay-opacity-step-${(step * 100).round()}'),
                    onPressed: hasUnderlay
                        ? () => layoutController.setOpacity(step)
                        : null,
                    trailingIcon: (layout.opacity - step).abs() < 0.001
                        ? const Icon(Icons.check, size: 18)
                        : null,
                    child: Text('${(step * 100).round()}%'),
                  ),
              ],
              child: Text('Opacity $percent%'),
            );
          },
        ),
      ],
    );
  }
}

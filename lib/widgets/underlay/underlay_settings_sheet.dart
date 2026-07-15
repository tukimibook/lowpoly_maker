import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/underlay_layout.dart';
import '../../providers/underlay_layout_provider.dart';

/// The five opacity steps the v1 settings sheet offers, per plan decision
/// (buttons, not a slider — see `.cursor/plans/plan_phase_H_alpha.md`):
/// picking one is a single tap that can't misfire into an OS swipe
/// gesture, unlike a slider drag would.
const List<double> kUnderlayOpacitySteps = [0.2, 0.4, 0.6, 0.8, 1.0];

/// Content of the "下絵設定" bottom sheet opened from [EditorScreen]'s app
/// bar: a visibility toggle and the five-step opacity picker above.
///
/// Reads [underlayLayoutProvider]'s controller directly and rebuilds via a
/// [ValueListenableBuilder] rather than `ref.watch` — the provider always
/// returns the same controller instance (see that file's doc), so a normal
/// Riverpod `watch` would never notice `.value` changes made by this very
/// sheet's own buttons.
class UnderlaySettingsSheet extends ConsumerWidget {
  const UnderlaySettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(underlayLayoutProvider);

    return SafeArea(
      child: ValueListenableBuilder<UnderlayLayout>(
        valueListenable: controller,
        builder: (context, layout, _) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('下絵設定', style: Theme.of(context).textTheme.titleMedium),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('下絵を表示'),
                  value: layout.visible,
                  onChanged: controller.setVisible,
                ),
                const SizedBox(height: 8),
                Text('不透明度', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<double>(
                  segments: [
                    for (final step in kUnderlayOpacitySteps)
                      ButtonSegment(value: step, label: Text('${(step * 100).round()}%')),
                  ],
                  selected: {_nearestStep(layout.opacity)},
                  onSelectionChanged: (selection) => controller.setOpacity(selection.first),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// [layout.opacity] is always one of [kUnderlayOpacitySteps] in v1 (only
  /// this sheet ever writes it), but snaps to the closest step anyway
  /// rather than requiring an exact `==` match, so a stray future writer
  /// (or floating-point rounding) can't leave [SegmentedButton] with no
  /// segment selected at all.
  static double _nearestStep(double opacity) {
    return kUnderlayOpacitySteps.reduce(
      (a, b) => (b - opacity).abs() < (a - opacity).abs() ? b : a,
    );
  }
}

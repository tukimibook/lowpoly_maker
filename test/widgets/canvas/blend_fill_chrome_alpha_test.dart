import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/providers/canvas_provider.dart';
import 'package:polygon_art_app/widgets/canvas/polygon_painter.dart';

void main() {
  group('blendFillChromeAlpha', () {
    test('opaque fill × any chrome is identical to the old absolute withAlpha', () {
      // Old path: Color(opaque).withAlpha(chrome) → chrome.
      // New path must match for every chrome value used today.
      for (final chrome in const [255, 153, 77, 0]) {
        expect(
          blendFillChromeAlpha(255, chrome),
          chrome,
          reason: 'fill=255, chrome=$chrome must equal old withAlpha($chrome)',
        );
      }
    });

    test('clear fill (alpha 0) always blends to 0 so Painter skips fill drawPath', () {
      expect(blendFillChromeAlpha(0, 255), 0);
      expect(blendFillChromeAlpha(0, 153), 0);
      expect(blendFillChromeAlpha(0, 77), 0);
      expect(
        blendFillChromeAlpha(
          (kClearFillColor.a * 255.0).round().clamp(0, 255),
          255,
        ),
        0,
      );
    });

    test('half-up rounding for mid-range translucency', () {
      // 200 * 200 = 40000; +127 = 40127; ~/255 = 157 (not truncated 156).
      expect(blendFillChromeAlpha(200, 200), 157);
    });
  });
}

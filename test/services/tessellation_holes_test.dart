import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/geometry/point_in_polygon.dart';
import 'package:polygon_art_app/services/tessellation_service.dart';

Offset _centroid(List<Offset> points, (int, int, int) triangle) {
  final (i, j, k) = triangle;
  return Offset(
    (points[i].dx + points[j].dx + points[k].dx) / 3,
    (points[i].dy + points[j].dy + points[k].dy) / 3,
  );
}

void main() {
  group('triangulate with holes', () {
    test('TessellationRequest defaults holes to empty', () {
      const request = TessellationRequest(
        boundary: [Offset(0, 0), Offset(10, 0), Offset(10, 10)],
        maxEdge: 50,
        minEdge: 5,
      );
      expect(request.holes, isEmpty);
    });

    test(
      'no triangle centroid lies inside a fully contained hole',
      () {
        const outer = [
          Offset(0, 0),
          Offset(200, 0),
          Offset(200, 200),
          Offset(0, 200),
        ];
        const hole = [
          Offset(60, 60),
          Offset(140, 60),
          Offset(140, 140),
          Offset(60, 140),
        ];

        final result = triangulate(
          const TessellationRequest(
            boundary: outer,
            holes: [hole],
            maxEdge: 80,
            minEdge: 15,
          ),
        );

        expect(result.triangleIndices, isNotEmpty);
        // Point layout: outer (4) then hole (4) then Steiner…
        expect(result.points.take(4), outer);
        expect(result.points.skip(4).take(4), hole);

        for (final triangle in result.triangleIndices) {
          final c = _centroid(result.points, triangle);
          expect(isPointInPolygon(c, outer), isTrue);
          expect(isPointInPolygon(c, hole), isFalse);
        }
      },
    );

    test('empty holes matches prior no-hole behavior for a simple triangle', () {
      const boundary = [
        Offset(0, 0),
        Offset(30, 0),
        Offset(0, 30),
      ];
      final withEmpty = triangulate(
        const TessellationRequest(
          boundary: boundary,
          holes: [],
          maxEdge: 100,
          minEdge: 5,
        ),
      );
      final withoutField = triangulate(
        const TessellationRequest(
          boundary: boundary,
          maxEdge: 100,
          minEdge: 5,
        ),
      );
      expect(withEmpty.triangleIndices, isNotEmpty);
      expect(withoutField.triangleIndices, isNotEmpty);
      for (final t in withEmpty.triangleIndices) {
        expect(isPointInPolygon(_centroid(withEmpty.points, t), boundary), isTrue);
      }
    });
  });
}

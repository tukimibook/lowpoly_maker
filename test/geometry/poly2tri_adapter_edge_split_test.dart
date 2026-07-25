import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/geometry/point_in_polygon.dart';
import 'package:polygon_art_app/geometry/poly2tri_adapter.dart';

double _dist(Offset a, Offset b) => (a - b).distance;

double _distToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.distanceSquared;
  if (len2 == 0) return _dist(p, a);
  var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2;
  t = t.clamp(0.0, 1.0);
  final proj = Offset(a.dx + t * ab.dx, a.dy + t * ab.dy);
  return _dist(p, proj);
}

void main() {
  group('splitRingEdges', () {
    test('leaves short edges and original vertices untouched', () {
      final ring = [
        const Offset(0, 0),
        const Offset(10, 0),
        const Offset(10, 10),
        const Offset(0, 10),
      ];
      final split = splitRingEdges(
        ring,
        maxEdge: 100,
        random: math.Random(1),
      );

      expect(split, hasLength(4));
      for (var i = 0; i < ring.length; i++) {
        expect(identical(split[i], ring[i]), isTrue);
      }
    });

    test('splits long edges; inserts stay near the original segment', () {
      final ring = [
        const Offset(0, 0),
        const Offset(200, 0),
        const Offset(200, 200),
        const Offset(0, 200),
      ];
      const maxEdge = 50.0;
      final rng = math.Random(42);
      final split = splitRingEdges(ring, maxEdge: maxEdge, random: rng);
      final inserts = collectEdgeSplitInserts(
        originalRing: ring,
        splitRing: split,
      );

      expect(inserts, isNotEmpty);
      // 200 / 50 = 4 segments → 3 inserts per long edge × 4 edges.
      expect(inserts, hasLength(12));

      for (final o in ring) {
        expect(split.where((p) => identical(p, o)), hasLength(1));
      }

      final slack = math.sqrt(2) * kEdgeSplitCollinearJitterHalf + 1e-9;
      for (var i = 0; i < split.length; i++) {
        final a = split[i];
        final b = split[(i + 1) % split.length];
        expect(_dist(a, b), lessThanOrEqualTo(maxEdge + slack));
      }

      for (final p in inserts) {
        // Each insert is near some original edge.
        final nearSomeEdge = [
          for (var i = 0; i < ring.length; i++)
            _distToSegment(p, ring[i], ring[(i + 1) % ring.length]),
        ].any((d) => d <= slack);
        expect(nearSomeEdge, isTrue);
      }
    });
  });

  group('isSafeSteinerCandidate / generateJitteredSteinerPoints', () {
    test('rejects points inside a hole or too close to constraints', () {
      final outer = [
        const Offset(0, 0),
        const Offset(100, 0),
        const Offset(100, 100),
        const Offset(0, 100),
      ];
      final hole = [
        const Offset(40, 40),
        const Offset(60, 40),
        const Offset(60, 60),
        const Offset(40, 60),
      ];
      final edges = [
        for (var i = 0; i < outer.length; i++)
          (outer[i], outer[(i + 1) % outer.length]),
        for (var i = 0; i < hole.length; i++)
          (hole[i], hole[(i + 1) % hole.length]),
      ];
      final existing = [...outer, ...hole];

      expect(
        isSafeSteinerCandidate(
          const Offset(50, 50),
          boundary: outer,
          holes: [hole],
          existing: existing,
          constraintEdges: edges,
          minEdge: 10,
        ),
        isFalse,
      );
      expect(
        isSafeSteinerCandidate(
          const Offset(5, 5),
          boundary: outer,
          holes: [hole],
          existing: existing,
          constraintEdges: edges,
          minEdge: 10,
        ),
        isFalse,
      );
      expect(
        isSafeSteinerCandidate(
          const Offset(25, 25),
          boundary: outer,
          holes: [hole],
          existing: existing,
          constraintEdges: edges,
          minEdge: 10,
        ),
        isTrue,
      );
    });

    test('jittered Steiners respect minEdge from verts and edges', () {
      final outer = [
        const Offset(0, 0),
        const Offset(120, 0),
        const Offset(120, 120),
        const Offset(0, 120),
      ];
      const minEdge = 15.0;
      const maxEdge = 30.0;
      final edges = [
        for (var i = 0; i < outer.length; i++)
          (outer[i], outer[(i + 1) % outer.length]),
      ];

      final steiners = generateJitteredSteinerPoints(
        boundary: outer,
        holes: const [],
        existingVertices: outer,
        constraintEdges: edges,
        maxEdge: maxEdge,
        minEdge: minEdge,
        random: math.Random(7),
      );

      for (final s in steiners) {
        expect(isPointInPolygon(s, outer), isTrue);
        for (final v in outer) {
          expect(_dist(s, v), greaterThanOrEqualTo(minEdge));
        }
        for (final (a, b) in edges) {
          expect(_distToSegment(s, a, b), greaterThanOrEqualTo(minEdge));
        }
      }
      for (var i = 0; i < steiners.length; i++) {
        for (var j = i + 1; j < steiners.length; j++) {
          expect(_dist(steiners[i], steiners[j]), greaterThanOrEqualTo(minEdge));
        }
      }
    });
  });

  group('runPoly2TriCdt point contract', () {
    test('prefix is original boundary; extras are split inserts and Steiners', () {
      final boundary = [
        const Offset(0, 0),
        const Offset(200, 0),
        const Offset(200, 200),
        const Offset(0, 200),
      ];
      final mesh = runPoly2TriCdt(
        boundary: boundary,
        maxEdge: 40,
        minEdge: 10,
        random: math.Random(3),
      );

      expect(mesh.points.sublist(0, 4), boundary);
      expect(mesh.points.length, greaterThan(4));
      expect(mesh.triangleIndices, isNotEmpty);

      for (final (a, b, c) in mesh.triangleIndices) {
        expect(a, lessThan(mesh.points.length));
        expect(b, lessThan(mesh.points.length));
        expect(c, lessThan(mesh.points.length));
      }
    });

    test('with holes: original outer+hole prefix, no centroid in hole', () {
      final outer = [
        const Offset(0, 0),
        const Offset(200, 0),
        const Offset(200, 200),
        const Offset(0, 200),
      ];
      final hole = [
        const Offset(60, 60),
        const Offset(140, 60),
        const Offset(140, 140),
        const Offset(60, 140),
      ];
      final mesh = runPoly2TriCdt(
        boundary: outer,
        holes: [hole],
        maxEdge: 40,
        minEdge: 10,
        random: math.Random(11),
      );

      expect(mesh.points.take(4), outer);
      expect(mesh.points.skip(4).take(4), hole);

      Offset centroid((int, int, int) t) {
        final (i, j, k) = t;
        return Offset(
          (mesh.points[i].dx + mesh.points[j].dx + mesh.points[k].dx) / 3,
          (mesh.points[i].dy + mesh.points[j].dy + mesh.points[k].dy) / 3,
        );
      }

      for (final t in mesh.triangleIndices) {
        final c = centroid(t);
        expect(isPointInPolygon(c, outer), isTrue);
        expect(isPointInPolygon(c, hole), isFalse);
      }
    });
  });
}

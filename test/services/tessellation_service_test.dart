import 'package:flutter_test/flutter_test.dart';

import 'package:polygon_art_app/services/tessellation_service.dart';

void main() {
  group('TessellationRequest', () {
    test('holds the boundary, maxEdge, and minEdge it was constructed with', () {
      const request = TessellationRequest(
        boundary: [Offset(0, 0), Offset(10, 0), Offset(10, 10)],
        maxEdge: 50,
        minEdge: 20,
      );

      expect(request.boundary, [const Offset(0, 0), const Offset(10, 0), const Offset(10, 10)]);
      expect(request.maxEdge, 50);
      expect(request.minEdge, 20);
    });
  });

  group('TessellationResult', () {
    test('holds the points and triangle indices it was constructed with', () {
      const result = TessellationResult(
        points: [Offset(0, 0), Offset(10, 0), Offset(10, 10)],
        triangleIndices: [(0, 1, 2)],
      );

      expect(result.points, hasLength(3));
      expect(result.triangleIndices, [(0, 1, 2)]);
    });
  });

  group('triangulate', () {
    test('is not yet implemented — throws UnimplementedError (algorithm lands separately)', () {
      const request = TessellationRequest(
        boundary: [Offset(0, 0), Offset(10, 0), Offset(10, 10)],
        maxEdge: 50,
        minEdge: 20,
      );

      expect(() => triangulate(request), throwsUnimplementedError);
    });
  });
}

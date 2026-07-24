// Poly2Tri Copyright (c) 2009-2018, Poly2Tri Contributors
// https://github.com/jhasse/poly2tri
//
// Pure Dart port of poly2tri/common/utils predicates (+ inCircle from sweep).

import 'point.dart';

/// Absolute tolerance used for near-collinear / near-zero orientation tests.
/// Matches upstream `EPSILON` (`1e-12`).
const double kP2tEpsilon = 1e-12;

/// Orientation of the ordered triple `(pa, pb, pc)`.
enum P2tOrientation {
  /// Clockwise.
  cw,

  /// Counter-clockwise.
  ccw,

  /// Collinear within [kP2tEpsilon].
  collinear,
}

/// Signed-area orientation test.
///
/// Positive → [P2tOrientation.ccw], negative → [P2tOrientation.cw],
/// `|val| < kP2tEpsilon` → [P2tOrientation.collinear].
///
/// ```
/// val = (pa.x - pc.x)*(pb.y - pc.y) - (pa.y - pc.y)*(pb.x - pc.x)
/// ```
P2tOrientation orient2d(P2tPoint pa, P2tPoint pb, P2tPoint pc) {
  final detLeft = (pa.x - pc.x) * (pb.y - pc.y);
  final detRight = (pa.y - pc.y) * (pb.x - pc.x);
  final val = detLeft - detRight;
  if (val > -kP2tEpsilon && val < kP2tEpsilon) {
    return P2tOrientation.collinear;
  }
  if (val > 0) {
    return P2tOrientation.ccw;
  }
  return P2tOrientation.cw;
}

/// Optimized in-circle test used by legalization.
///
/// Returns `true` when [pd] lies **strictly inside** the circumcircle of
/// triangle `(pa, pb, pc)`. Assumes the known orientation layout used by the
/// sweep legalize path (same formula as upstream `InCircle` / JS `inCircle`).
/// Returns `false` when [pd] is outside or on the circle.
bool inCircle(P2tPoint pa, P2tPoint pb, P2tPoint pc, P2tPoint pd) {
  final adx = pa.x - pd.x;
  final ady = pa.y - pd.y;
  final bdx = pb.x - pd.x;
  final bdy = pb.y - pd.y;

  final adxbdy = adx * bdy;
  final bdxady = bdx * ady;
  final oabd = adxbdy - bdxady;
  if (oabd <= 0) {
    return false;
  }

  final cdx = pc.x - pd.x;
  final cdy = pc.y - pd.y;

  final cdxady = cdx * ady;
  final adxcdy = adx * cdy;
  final ocad = cdxady - adxcdy;
  if (ocad <= 0) {
    return false;
  }

  final bdxcdy = bdx * cdy;
  final cdxbdy = cdx * bdy;

  final alift = adx * adx + ady * ady;
  final blift = bdx * bdx + bdy * bdy;
  final clift = cdx * cdx + cdy * cdy;

  final det = alift * (bdxcdy - cdxbdy) + blift * ocad + clift * oabd;
  return det > 0;
}

/// Whether [pd] lies in the open scan area defined by `pa, pb, pc`
/// (upstream `InScanArea`).
bool inScanArea(P2tPoint pa, P2tPoint pb, P2tPoint pc, P2tPoint pd) {
  final oadb =
      (pa.x - pb.x) * (pd.y - pb.y) - (pd.x - pb.x) * (pa.y - pb.y);
  if (oadb >= -kP2tEpsilon) {
    return false;
  }

  final oadc =
      (pa.x - pc.x) * (pd.y - pc.y) - (pd.x - pc.x) * (pa.y - pc.y);
  if (oadc <= kP2tEpsilon) {
    return false;
  }
  return true;
}

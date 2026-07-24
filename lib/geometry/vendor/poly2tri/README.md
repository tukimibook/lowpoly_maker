# poly2tri (pure Dart port)

Vendored pure-Dart port of [Poly2Tri](https://github.com/jhasse/poly2tri)
(sweep-line constrained Delaunay triangulation).

## Provenance

- Upstream C++: https://github.com/jhasse/poly2tri
- Structure also informed by the JS port: https://github.com/r3mi/poly2tri.js
- License: BSD-3-Clause — see [LICENSE](LICENSE)

## Layout

```text
common/     Point, Edge, Triangle, geometric predicates
sweep/      SweepContext, Sweep, CDT facade (added in later steps)
poly2tri.dart   barrel export
```

## Constraints (this tree)

- Pure Dart only — no Flutter / `dart:ui` / app models.
- Point identity is **reference equality**, not coordinate equality
  (same `x,y` may be distinct `P2tPoint` instances).
- Duplicate points within epsilon are not supported by the algorithm;
  callers must sanitize input before triangulation.

## Port status

- Step 1–2: skeleton + `common/` shapes and predicates.
- Sweep / CDT / app adapter: not yet implemented.

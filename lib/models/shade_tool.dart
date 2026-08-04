/// Sub-tool of [CanvasMode.shade] (Phase Select).
///
/// - [solid]: tap one polygon to apply the current fill color (1 undo entry).
/// - [select]: tap or drag to add polygon ids to the shade selection set.
/// - [light]: tap a selected polygon as the shading origin; runs
///   `computeDistanceShading` then `applyPolygonColors` (one undo).
enum ShadeTool { solid, select, light }

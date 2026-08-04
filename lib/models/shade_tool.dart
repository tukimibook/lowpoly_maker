/// Sub-tool of [CanvasMode.shade] (Phase Select).
///
/// - [solid]: tap one polygon to apply the current fill color (1 undo entry).
/// - [select]: tap or drag to add polygon ids to the shade selection set.
/// - [light]: tap a selected polygon as the shading origin (wired in a later
///   step to `computeDistanceShading` / `applyPolygonColors`).
enum ShadeTool { solid, select, light }

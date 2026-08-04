/// High-level interaction mode for the canvas.
///
/// - [draw]: tapping places new vertices / closes polygons / starts a new
///   shape from an existing vertex.
/// - [eraser]: tapping an existing vertex deletes just that single point.
/// - [edit]: tap to select a vertex; long-press drag to move it (welded
///   corners move every polygon that shares the same [Vertex.id]).
/// - [shade]: fill / multi-select / distance shading tools ([ShadeTool]).
enum CanvasMode { draw, eraser, edit, shade }

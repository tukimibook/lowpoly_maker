/// High-level interaction mode for the canvas.
///
/// - [draw]: tapping places new vertices / closes polygons / starts a new
///   shape from an existing vertex.
/// - [eraser]: tapping an existing vertex deletes just that single point.
enum CanvasMode { draw, eraser }

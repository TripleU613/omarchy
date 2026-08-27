pragma Singleton
import QtQuick

// The one place the bar's icon geometry rules live. Every icon's lit pixels
// are measured against them: by the buttons that fit the icons as they
// render, by `omarchy-dev-bar-icon-audit` scanning the live bar, and by the
// tests. Nothing else may carry its own idea of how far an icon sits from
// the edge of its canvas.
QtObject {
  // A pixel counts as lit above this alpha; fainter antialiasing fringe does
  // not.
  readonly property real litAlpha: 0.25
  // Every rule allows this much, in logical pixels: one pixel of the theme's
  // coordinate space, which is what rasterization can take from any edge.
  readonly property real tolerance: 1
  // How many render-and-measure passes a glyph may take to settle. Native
  // glyphs snap to whole device pixels, so a pass can overshoot; the best
  // pass seen is kept.
  readonly property int maxPasses: 5

  // How far a set of margins is from the rules, for ranking passes: the
  // centering imbalance plus whatever the filled axis falls short by.
  function distance(margins) {
    if (!margins) return Infinity
    var vertical = Math.max(margins.n, margins.s)
    var horizontal = Math.max(margins.e, margins.w)
    return Math.abs(margins.n - margins.s) + Math.abs(margins.e - margins.w) + Math.min(vertical, horizontal)
  }

  // Compass margins, in logical pixels, from the canvas edges to the lit
  // pixels. `measurement` is an InkMeasure result. Cardinal margins come
  // from the straight render; NW/NE/SE/SW from the render turned 45°, whose
  // bounding square puts each corner of the canvas at the middle of a side,
  // so its margins are the distances from those corners along the diagonals.
  function compass(measurement, canvasWidth, canvasHeight) {
    if (!measurement || !measurement.rect) return null
    var r = measurement.rect
    var out = {
      n: r.y * canvasHeight,
      s: (1 - r.y - r.height) * canvasHeight,
      w: r.x * canvasWidth,
      e: (1 - r.x - r.width) * canvasWidth
    }
    if (measurement.diagonal && measurement.width > 0) {
      var perPixel = canvasWidth / measurement.width
      var d = measurement.diagonal
      out.nw = d.y * measurement.diagonalHeight * perPixel
      out.ne = (1 - d.x - d.width) * measurement.diagonalWidth * perPixel
      out.se = (1 - d.y - d.height) * measurement.diagonalHeight * perPixel
      out.sw = d.x * measurement.diagonalWidth * perPixel
    }
    return out
  }

  // The rules, applied to compass margins. Empty when the icon passes.
  //   fill       the lit pixels span the canvas along the axis they fill:
  //              both margins on that axis are within tolerance
  //   centered   opposite margins match within tolerance, N with S and
  //              E with W
  //   contained  no lit pixel lies beyond the canvas by more than tolerance,
  //              corners included
  function evaluate(margins) {
    if (!margins) return ["unmeasured"]
    var problems = []
    var vertical = Math.max(margins.n, margins.s)
    var horizontal = Math.max(margins.e, margins.w)
    if (Math.min(vertical, horizontal) > tolerance) problems.push("fill")
    if (Math.abs(margins.n - margins.s) > tolerance || Math.abs(margins.e - margins.w) > tolerance) problems.push("centered")
    for (var key in margins) {
      if (margins[key] < -tolerance) {
        problems.push("contained")
        break
      }
    }
    return problems
  }
}

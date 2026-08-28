pragma Singleton
import QtQuick

// The one place the bar's icon geometry rules live. Every icon's ink is
// measured against them: by the buttons that fit the icons as they render,
// by `omarchy-dev-bar-icon-audit` scanning the live bar, and by the tests.
// Nothing else may carry its own idea of how far an icon sits from the edge
// of its canvas.
//
// An icon is sized by how far it reaches and placed by where it weighs.
// Those are two different questions and the old single answer — the box
// around the ink — got the second one wrong: it lines up the box, so a mark
// whose weight sits high in that box (an arc) rides high on the bar and one
// whose weight sits low (a body under a thin antenna) sags, even though
// every box is perfectly centered. Lining up the weight instead is what
// makes a row read as level.
QtObject {
  // A mark's shape is everything it paints above antialiasing fringe,
  // however brightly. Taking the shape before anything else measures a logo
  // drawn in two tones exactly as it measures the same logo drawn in one.
  readonly property real fringeAlpha: 0.06

  // How far the ink reaches is read optically rather than from the outermost
  // pixel that happens to be painted: the shape is blurred until it reads as
  // one soft mass, then cut at half that mass's peak. Half the peak of a
  // blurred edge falls exactly back on the edge, so a solid shape measures
  // its true size, while a hairline or a stray serif never reaches half and
  // so stops deciding how big the whole icon is. The radius is a fraction of
  // the render's shorter side, so the rule holds at every display size, and
  // is never less than a pixel.
  readonly property real opticalBlur: 0.015
  readonly property real opticalLevel: 0.5
  function blurRadius(renderWidth, renderHeight) {
    return Math.max(1, opticalBlur * Math.min(renderWidth, renderHeight))
  }

  // Every rule allows this much, in logical pixels: one pixel of the theme's
  // coordinate space, which is what rasterization can take from any edge. A
  // measurement can never be finer than the pixel it was measured in, so a
  // render whose pixels are coarser than that sets the floor instead.
  readonly property real tolerance: 1
  function slack(margins) {
    return Math.max(tolerance, margins && margins.pixel > 0 ? margins.pixel : 0)
  }

  // How many render-and-measure passes a glyph may take to settle. Native
  // glyphs snap to whole device pixels, so a pass can overshoot; the best
  // pass seen is kept.
  readonly property int maxPasses: 5

  // How many squares of the grid an icon takes along the bar. An icon is
  // fitted inside that many squares by one square's height, so a mark that is
  // genuinely wider than it is tall gets the room to stay full height instead
  // of being shrunk until its width fits one square — which is what leaves a
  // two-to-one badge reading half the height of everything beside it.
  //
  // Rounding to nearest is what keeps the extra squares to the marks that
  // really are wide. Rounding up would hand a second square to a 1.1:1 icon
  // and most of the row would be two squares wide, which is no grid at all.
  // A mark only gets the extra room if it actually fills it. An awkward
  // in-between shape — half again as wide as it is tall — would be handed a
  // second square it cannot reach the far side of, and would sit in a wider
  // slot under a wider mark still no taller than before. So the extra squares
  // go to marks that are cleanly that many squares wide, and everything else
  // stays in one, exactly as it was — including anything past the end of the
  // grid, which cannot cleanly fill the cap either and so keeps being fitted
  // by its width.
  readonly property int maxSquares: 3
  readonly property real squareFit: 0.25
  function squares(aspect) {
    if (!(aspect > 0)) return 1
    var whole = Math.min(maxSquares, Math.round(aspect))
    if (whole <= 1) return 1
    return Math.abs(aspect - whole) <= squareFit ? whole : 1
  }

  // How much of a mark a second tone has to cover before it counts as the
  // logo being drawn in two tones rather than one part of it being faded by
  // accident. Below this the faded part is brought back to full; at or above
  // it the mark is left as its author drew it.
  readonly property real twoToneMinShare: 0.2

  // The compass keys that are margins. The rest of the object says how the
  // measurement was taken, and is not one of them.
  readonly property var directions: ["n", "s", "e", "w", "nw", "ne", "se", "sw"]

  // How far a set of margins is from the rules, for ranking passes: how far
  // the weight sits off center plus whatever the filled axis falls short by.
  function distance(margins) {
    if (!margins) return Infinity
    var vertical = Math.max(margins.n, margins.s)
    var horizontal = Math.max(margins.e, margins.w)
    return Math.abs(margins.balanceX) + Math.abs(margins.balanceY) + Math.min(vertical, horizontal)
  }

  // Compass margins, in logical pixels, from the canvas edges to the ink,
  // plus where the ink's weight sits relative to the canvas center.
  // `measurement` is an InkMeasure result. Cardinal margins come from the
  // straight render; NW/NE/SE/SW from the render turned 45°, whose bounding
  // square puts each corner of the canvas at the middle of a side, so its
  // margins are the distances from those corners along the diagonals.
  function compass(measurement, canvasWidth, canvasHeight) {
    if (!measurement || !measurement.rect) return null
    var r = measurement.rect
    var c = measurement.centroid
    var out = {
      n: r.y * canvasHeight,
      s: (1 - r.y - r.height) * canvasHeight,
      w: r.x * canvasWidth,
      e: (1 - r.x - r.width) * canvasWidth,
      // Where the ink balances, as a distance from the canvas center.
      balanceX: c ? (c.x - 0.5) * canvasWidth : 0,
      balanceY: c ? (c.y - 0.5) * canvasHeight : 0,
      // One pixel of the render, in the canvas's own logical pixels.
      pixel: measurement.width > 0 ? canvasWidth / measurement.width : 0
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

  // How far past its canvas an icon may be moved to balance, as a fraction
  // of the canvas. The canvas edge is already a soft line — every rule here
  // allows a pixel of play on it — so balancing may spend that same pixel.
  // Without it an icon whose ink happens to reach both edges has nowhere to
  // move at all, and stays visibly off center for a reason no one can see.
  // Kept just under the tolerance so an icon moved the whole way is still
  // comfortably contained.
  function balanceAllowance(canvasSize) {
    return canvasSize > 0 ? (0.75 * tolerance) / canvasSize : 0
  }

  // Where an icon has to move to sit level with its neighbours: the shift,
  // in fractions of the canvas, that brings its weight onto the canvas
  // center. An icon may not be pushed clear off its canvas to achieve that,
  // so the shift is held to the room its box has left plus that allowance.
  function balanceShift(rect, centroid, allowance) {
    if (!rect || !centroid) return Qt.point(0, 0)
    var room = allowance > 0 ? allowance : 0
    return Qt.point(
      Math.max(-rect.x - room, Math.min(0.5 - centroid.x, 1 - rect.x - rect.width + room)),
      Math.max(-rect.y - room, Math.min(0.5 - centroid.y, 1 - rect.y - rect.height + room)))
  }

  // The rules, applied to compass margins. Empty when the icon passes.
  //   fill       the ink spans the canvas along the axis it fills: both
  //              margins on that axis are within tolerance
  //   balanced   the ink's weight sits on the canvas center, so the icon
  //              reads level with its neighbours whatever its silhouette
  //   contained  no ink lies beyond the canvas by more than tolerance,
  //              corners included
  function evaluate(margins) {
    if (!margins) return ["unmeasured"]
    var allowed = slack(margins)
    var problems = []
    var vertical = Math.max(margins.n, margins.s)
    var horizontal = Math.max(margins.e, margins.w)
    if (Math.min(vertical, horizontal) > allowed) problems.push("fill")
    if (Math.abs(margins.balanceX) > allowed || Math.abs(margins.balanceY) > allowed) problems.push("balanced")
    for (var i = 0; i < directions.length; i++) {
      var key = directions[i]
      if (key in margins && margins[key] < -allowed) {
        problems.push("contained")
        break
      }
    }
    return problems
  }
}

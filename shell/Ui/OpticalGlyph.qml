import QtQuick
import QtQuick.Window
import qs.Commons

// Places a font glyph by the bounds of its ink instead of its line box, and
// with `normalize` on sizes the font so that ink fills the item. The font's
// tight bounding rect gets it within a pixel; the rendered pixels are then
// measured and the size and position corrected until the glyph meets the
// shared icon rules, so unlike icons come out at one optical size, centered
// on the same point.
Item {
  id: root

  property string text: ""
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property color color: Color.foreground
  property bool normalize: false
  property bool debugBounds: false

  readonly property int renderedFontSize: Math.max(1, Math.round(fontSize))
  readonly property real baseInkWidth: Math.max(1, baseMetrics.tightBoundingRect.width)
  readonly property real baseInkHeight: Math.max(1, baseMetrics.tightBoundingRect.height)
  // Fitted to whichever axis of the item binds first, so a glyph in a canvas
  // wider than it is tall comes out full height rather than squashed to the
  // width of one square.
  readonly property real metricScale: normalize && width > 0 && height > 0
    ? Math.min(width / baseInkWidth, height / baseInkHeight)
    : 1
  // Corrections the measured pixels asked for, on top of the metric estimate.
  property real pixelScale: 1
  property real pixelOffsetX: 0
  property real pixelOffsetY: 0
  readonly property real normalizedScale: metricScale * pixelScale
  readonly property real tightWidth: baseInkWidth * normalizedScale
  readonly property real tightHeight: baseInkHeight * normalizedScale

  // A normalized glyph is rasterized at the fractional size that makes its
  // ink span the item; scaling a native raster instead only magnifies pixels.
  // Fractional sizes travel as points and Qt maps them back through the same
  // logical DPI, so an unnormalized glyph keeps its integer pixel size.
  readonly property real logicalDpi: Screen.logicalPixelDensity > 0 ? Screen.logicalPixelDensity * 25.4 : 96
  readonly property font glyphFont: normalize
    ? Qt.font({ family: fontFamily, pointSize: renderedFontSize * normalizedScale * 72 / logicalDpi })
    : Qt.font({ family: fontFamily, pixelSize: renderedFontSize })

  // Where the rasterized ink sits by the font's account, for centering it
  // rather than the line box.
  readonly property real inkWidth: Math.max(1, metrics.tightBoundingRect.width)
  readonly property real inkHeight: Math.max(1, metrics.tightBoundingRect.height)
  readonly property real horizontalCorrection: glyph.width / 2 - (metrics.tightBoundingRect.x + inkWidth / 2)
  // Without normalization the line box stays centered so glyphs of one font
  // size keep a shared baseline; with it the ink itself is centered.
  readonly property real verticalCorrection: normalize
    ? glyph.height / 2 - (glyph.baselineOffset + metrics.tightBoundingRect.y + inkHeight / 2)
    : 0
  readonly property real baselineY: glyph.y + glyph.baselineOffset

  // Lit-pixel verification. The glyph is rendered, its pixels measured, and
  // size and position corrected until the rules hold or the passes run out.
  readonly property var hostWindow: Window.window
  readonly property real inspectScale: 4 * (Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1)
  property var inkMeasurement: null
  property var inkCompass: null
  property bool inkVerified: !normalize
  property int inkPasses: 0
  property int inkRevision: 0
  // The closest pass so far, restored if later passes only overshoot.
  property var bestPass: null
  // How wide the rendered ink is against its own height. The canvas is sized
  // from this, and the font's own metrics disagree with what actually
  // rasterizes, so it has to come from the same ink the rules are judged on.
  //
  // A render is grabbed at the size of this item, so ink hanging outside the
  // canvas is cut off by the grab and a glyph that starts too wide measures
  // exactly one canvas wide. The aspect therefore keeps being taken until the
  // fit settles and the ink is inside, and is then frozen — otherwise a glyph
  // whose aspect sits near the rounding line would swap between one square
  // and two forever, each canvas making the other look right.
  property real latchedAspect: 0
  property bool aspectSettled: false
  property bool destroying: false
  readonly property var inkViolations: normalize ? IconRules.evaluate(inkCompass) : []
  // The lit box as fractions of this item: measured once the pixels are in,
  // the font's estimate until then.
  readonly property rect inkRect: inkMeasurement
    ? inkMeasurement.rect
    : Qt.rect(0.5 - tightWidth / (2 * Math.max(1, width)), 0.5 - tightHeight / (2 * Math.max(1, height)),
        tightWidth / Math.max(1, width), tightHeight / Math.max(1, height))
  readonly property real paintedCenterX: (inkRect.x + inkRect.width / 2) * width
  readonly property real paintedCenterY: (inkRect.y + inkRect.height / 2) * height

  // Everything that shapes the render, for the session cache.
  function inkKey() {
    return [fontFamily, text, renderedFontSize, width, height, inspectScale].join("|")
  }

  function applyPass(pass) {
    pixelScale = pass.pixelScale
    pixelOffsetX = pass.pixelOffsetX
    pixelOffsetY = pass.pixelOffsetY
    inkMeasurement = pass.measurement
    inkCompass = pass.compass
  }

  function requestInk() {
    inkRevision++
    inkPasses = 0
    bestPass = null
    pixelScale = 1
    pixelOffsetX = 0
    pixelOffsetY = 0
    inkMeasurement = null
    inkCompass = null
    inkVerified = !normalize
    if (!normalize) return

    var cached = InkCache.get(inkKey())
    if (cached) {
      applyPass(cached)
      inkVerified = true
      return
    }
    Qt.callLater(measureInk)
  }

  function measureInk() {
    if (destroying || !normalize || !hostWindow || width <= 0 || height <= 0 || text === "" || debugBounds) return
    var requested = inkRevision
    var key = inkKey()
    var size = Qt.size(Math.max(1, Math.round(width * inspectScale)), Math.max(1, Math.round(height * inspectScale)))
    ink.measure(root, size, function(result) {
      if (!root || root.destroying || requested !== root.inkRevision) return
      root.inkPasses++
      if (!result) {
        if (root.inkPasses < IconRules.maxPasses) Qt.callLater(root.measureInk)
        return
      }

      if (!root.aspectSettled && result.rect.width > 0 && result.rect.height > 0) {
        root.latchedAspect = (result.rect.width * root.width) / (result.rect.height * root.height)
      }

      var compass = IconRules.compass(result, root.width, root.height)
      var pass = { pixelScale: root.pixelScale, pixelOffsetX: root.pixelOffsetX, pixelOffsetY: root.pixelOffsetY,
        measurement: result, compass: compass }
      root.inkMeasurement = result
      root.inkCompass = compass
      var best = root.bestPass ? IconRules.distance(root.bestPass.compass) : Infinity
      var reached = IconRules.distance(compass)
      if (reached < best) root.bestPass = pass

      // Passes run until the glyph stops getting better, not until it is
      // merely inside tolerance. A native glyph can only be placed on whole
      // device pixels, so the last fraction of a pixel is not correctable and
      // a pass that no longer improves has found that floor; stopping at the
      // first acceptable pass instead leaves each glyph wherever it first
      // landed, which is what makes a row of them sit at slightly different
      // heights.
      if (reached >= best - 0.01 || root.inkPasses >= IconRules.maxPasses) {
        root.applyPass(root.bestPass)
        root.inkVerified = true
        root.aspectSettled = true
        InkCache.set(key, root.bestPass)
        return
      }

      // Grow or shrink until the ink spans the canvas, shift until its
      // weight sits on the canvas center, then look again. Size answers to
      // how far the glyph reaches and position to where it weighs, so a
      // top-heavy or bottom-heavy glyph comes out level with its neighbours
      // rather than merely boxed like them.
      var r = result.rect
      if (r.width > 0 && r.height > 0) root.pixelScale *= Math.min(1 / r.width, 1 / r.height)
      var shift = IconRules.balanceShift(r, result.centroid, IconRules.balanceAllowance(Math.min(root.width, root.height)))
      root.pixelOffsetX += shift.x * root.width
      root.pixelOffsetY += shift.y * root.height
      Qt.callLater(root.measureInk)
    })
  }

  onTextChanged: { latchedAspect = 0; aspectSettled = false; requestInk() }
  onFontFamilyChanged: { latchedAspect = 0; aspectSettled = false; requestInk() }
  onRenderedFontSizeChanged: { latchedAspect = 0; aspectSettled = false; requestInk() }
  onWidthChanged: requestInk()
  onHeightChanged: requestInk()
  onNormalizeChanged: requestInk()
  onHostWindowChanged: if (hostWindow) requestInk()
  Component.onCompleted: requestInk()
  Component.onDestruction: destroying = true

  InkMeasure {
    id: ink
  }

  TextMetrics {
    id: baseMetrics
    font.family: root.fontFamily
    font.pixelSize: root.renderedFontSize
    text: root.text
  }

  TextMetrics {
    id: metrics
    font: root.glyphFont
    text: root.text
  }

  Text {
    id: glyph
    x: (root.width - width) / 2 + root.horizontalCorrection + root.pixelOffsetX
    y: (root.height - height) / 2 + root.verticalCorrection + root.pixelOffsetY
    text: root.text
    color: root.color
    font: root.glyphFont
    renderType: Text.NativeRendering
  }

  Rectangle {
    visible: root.debugBounds
    anchors.fill: parent
    color: "transparent"
    border.width: 1
    border.color: "#4488ff"
  }

  Rectangle {
    visible: root.debugBounds
    x: 0
    y: Math.round(root.baselineY)
    width: parent.width
    height: 1
    color: "#44ff88"
  }
}

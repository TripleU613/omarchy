import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Measures where an item's lit pixels reach. The item is rendered to a
// temporary image and ImageMagick reports the bounding box of its alpha
// above the lit threshold, both straight and turned 45° for the diagonals.
// Boxes come back as fractions of their render, so they hold at any display
// size. One measurement runs at a time; a request made meanwhile replaces
// any earlier pending one.
Item {
  id: root

  visible: false
  width: 0
  height: 0

  readonly property string renderPath: Quickshell.env("XDG_RUNTIME_DIR") + "/omarchy-shell-ink-" + Quickshell.processId
    + "-" + Date.now().toString(36) + Math.random().toString(36).slice(2) + ".png"

  property var pending: null
  property var active: null
  // A released delegate loses its QML context before it is deleted; a deferred
  // start or a grab callback landing in that window has nothing to work with.
  property bool destroying: false

  Component.onDestruction: destroying = true

  // Renders `target` at `pixelSize` and calls done(result) with
  //   rect            lit box as fractions of the render
  //   width, height   render size in pixels
  //   diagonal        lit box of the render turned 45°, as fractions of that
  //                   turned render, or null
  //   diagonalWidth, diagonalHeight
  // An image lit to its edges yields the full box, since there is nothing to
  // trim; a render with no lit pixels at all, or one that failed, yields null.
  function measure(target, pixelSize, done) {
    pending = { target: target, pixelSize: pixelSize, done: done }
    Qt.callLater(start)
  }

  function start() {
    if (destroying || active || !pending) return
    var request = pending
    pending = null
    if (!request.target) {
      request.done(null)
      return
    }

    active = request
    var grabbing = request.target.grabToImage(function(result) {
      if (root.destroying) return
      if (!result || !result.saveToFile(root.renderPath)) {
        root.finish(null)
        return
      }
      // The render is consumed in one go and removed by the same command, so
      // nothing lingers however the shell exits. The turned copy is reported
      // first, the straight render last with its lit fraction.
      inspector.command = ["bash", "-c",
        'magick "$1" -alpha extract -threshold "$2" \\( +clone -background black -rotate 45 -format "%w %h %@\\n" -write info: +delete \\) -format "%w %h %@ %[fx:mean]\\n" info:; rm -f -- "$1"',
        "omarchy-shell-ink", root.renderPath, Math.round(IconRules.litAlpha * 100) + "%"]
      inspector.running = true
    }, request.pixelSize)
    if (!grabbing) finish(null)
  }

  function finish(result) {
    var request = active
    active = null
    if (request) request.done(result)
    if (pending) Qt.callLater(start)
  }

  // Lines of "W H wxh+x+y" for the turned render, then "W H wxh+x+y mean"
  // for the straight one. Uniform alpha gives an empty box, which is either
  // nothing lit (mean 0) or lit throughout.
  function parse(text) {
    var lines = String(text || "").trim().split("\n")
    var box = /^\s*(\d+)\s+(\d+)\s+(\d+)x(\d+)\+(\d+)\+(\d+)(?:\s+([0-9.eE+-]+))?/
    var straight = box.exec(lines[lines.length - 1] || "")
    if (!straight) return null
    var width = Number(straight[1]), height = Number(straight[2])
    var inkWidth = Number(straight[3]), inkHeight = Number(straight[4])
    if (width <= 0 || height <= 0) return null

    var result = { rect: null, width: width, height: height, diagonal: null, diagonalWidth: 0, diagonalHeight: 0 }
    if (inkWidth <= 0 || inkHeight <= 0) {
      if (!(Number(straight[7]) > 0)) return null
      result.rect = Qt.rect(0, 0, 1, 1)
    } else {
      result.rect = Qt.rect(Number(straight[5]) / width, Number(straight[6]) / height, inkWidth / width, inkHeight / height)
    }

    if (lines.length >= 2) {
      var turned = box.exec(lines[0])
      if (turned) {
        var turnedWidth = Number(turned[1]), turnedHeight = Number(turned[2])
        var turnedInkWidth = Number(turned[3]), turnedInkHeight = Number(turned[4])
        if (turnedWidth > 0 && turnedHeight > 0 && turnedInkWidth > 0 && turnedInkHeight > 0) {
          result.diagonal = Qt.rect(Number(turned[5]) / turnedWidth, Number(turned[6]) / turnedHeight,
            turnedInkWidth / turnedWidth, turnedInkHeight / turnedHeight)
          result.diagonalWidth = turnedWidth
          result.diagonalHeight = turnedHeight
        }
      }
    }
    return result
  }

  Process {
    id: inspector
    running: false
    command: []

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (!root.destroying) root.finish(root.parse(text))
    }

    onExited: if (!root.destroying && root.active) root.finish(null)
  }
}

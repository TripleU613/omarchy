#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const bar = requireFromRoot('shell/plugins/bar/BarModel.js')
const barSource = fs.readFileSync(root + '/shell/plugins/bar/Bar.qml', 'utf8')

// A bar long enough for every widget keeps the list it was given, and keeps
// the very same array: a wide display must not rebind its sections on every
// layout pass just because the filter ran.
const keys = ['a#1', 'b#2', 'c#3']
const entries = {
  'a#1': { id: 'omarchy.clock' },
  'b#2': { id: 'omarchy.active-window', minBarWidth: 1600 },
  'c#3': { id: 'omarchy.power' }
}
assert(bar.fittingKeys(keys, entries, 5120) === keys, 'a bar with room for everything is handed its own list back')
assertDeepEqual(bar.fittingKeys(keys, entries, 1600), keys, 'a widget shows on a bar exactly as long as its minBarWidth')
assertDeepEqual(bar.fittingKeys(keys, entries, 1280), ['a#1', 'c#3'], 'a narrower bar leaves out the widget that asked for more room')

// The setting is opt-in: nothing without it is ever dropped, however narrow
// the bar, and a malformed value is ignored rather than hiding a widget.
assertDeepEqual(bar.fittingKeys(keys, { 'a#1': {}, 'b#2': {}, 'c#3': {} }, 1), keys, 'widgets without minBarWidth survive any width')
for (const bad of [0, -100, 'wide', null, NaN, {}])
  assertDeepEqual(
    bar.fittingKeys(['b#2'], { 'b#2': { id: 'x', minBarWidth: bad } }, 320),
    ['b#2'],
    `an unusable minBarWidth (${String(bad)}) does not hide a widget`
  )

// A string entry carries no settings, and an unmeasured bar (a list that is
// not drawn) must not filter on a length it does not have yet.
assertDeepEqual(bar.fittingKeys(['s#1'], { 's#1': 'omarchy.clock' }, 320), ['s#1'], 'a bare string entry is never filtered')
assertDeepEqual(bar.fittingKeys(keys, entries, 0), keys, 'a bar that has not been measured yet filters nothing')
assertDeepEqual(bar.fittingKeys(null, entries, 1280), [], 'a missing key list yields no keys')

// The centered group stays centered while it fits between the two edge
// sections: the placement every bar had before this existed.
assertEqual(bar.centerBoxX(5120, 200, 300, 300, 400, 4720), 2460, 'the center box sits dead center when the group fits')
assertEqual(bar.centerBoxX(5120, 200, 0, 0, 0, 0), 2460, 'with no room reported the box is centered as before')

// Once it does not fit, it slides along the room instead of overprinting a
// neighbour. Centered would put the box at 540, which would run centerBegin
// back to 140 -- past the left section ending at 600.
assertEqual(bar.centerBoxX(1280, 200, 400, 100, 600, 1200), 1000, 'the group slides clear of the left section rather than overlapping it')
assertEqual(bar.centerBoxX(1280, 200, 100, 400, 0, 600), 100, 'the group slides clear of the right section too')

// Wider than the room there is no overlap-free placement; it starts where the
// room does, deterministically, and minBarWidth is what keeps a bar out of it.
assertEqual(bar.centerBoxX(1280, 400, 400, 400, 500, 800), 900, 'a group wider than the room starts where the room starts')

// Nonsense insets fall back to centering rather than throwing a bar off screen.
for (const [start, end] of [[NaN, 1200], [600, NaN], [900, 300]])
  assertEqual(bar.centerBoxX(1280, 200, 0, 0, start, end), 540, `unusable room (${start}, ${end}) leaves the box centered`)

// The engine has to actually consult both, or the model above is dead code.
assert(
  /readonly property var shownKeys: BarModel\.fittingKeys\(keys, root\.layoutWidgets\.entries, window \? window\.barLength : 0\)/.test(barSource),
  'every module list filters its keys by the length of the bar it is drawn on'
)
assert(
  /BarModel\.sectionRows\(shownKeys,/.test(barSource) && !/BarModel\.sectionRows\(keys,/.test(barSource),
  'module list rows are built from the filtered keys, not the configured ones'
)
assert(
  /BarModel\.slotEdge\(moduleListRoot\.shownKeys\.length, moduleListRoot\.shownKeys\.indexOf/.test(barSource),
  'slot edges are measured against the widgets actually shown'
)
assert(
  /x: root\.vertical \? 0 : \(sections\.besideRight \? beginList\.width : BarModel\.centerBoxX\(/.test(barSource),
  'the center box is placed within the room left by the edge sections'
)
assert(
  /startInset: leftModules\.x \+ leftModules\.width \+ Style\.space\(4\)/.test(barSource) &&
  /endInset: rightModules\.x - Style\.space\(4\)/.test(barSource),
  'the horizontal bar reports the room between its left and right sections'
)
assert(
  /readonly property int barLength: root\.vertical \? height : width/.test(barSource),
  'each bar surface publishes the length it runs on'
)
JS

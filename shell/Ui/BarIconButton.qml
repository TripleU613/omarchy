import QtQuick
import qs.Commons

// A bar button that occupies the shared icon slot. Its content is sized by
// WidgetButton's optical normalization; this only fixes the slot and the icon
// font size the canvas is derived from.
WidgetButton {
  id: root

  property real slotSize: Style.bar.iconSlot

  fontSize: Style.bar.iconFont
  fixedWidth: vertical ? -1 : slotSize
  fixedHeight: vertical ? slotSize : -1
}

import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The watch, in the bar.
//
// Four states, and the one people get wrong is the fourth: a monitor that
// cannot reach its source must not look like one reporting calm. So "not
// watching" is drawn in the warning colour and struck through — never greyed
// out and quietly forgotten.
BarWidget {
  id: root
  moduleName: "reidenxerx.varta"

  readonly property string pluginId: "reidenxerx.varta"

  property var varta: null

  function findService() {
    if (root.varta) return
    const shell = root.bar ? root.bar.shell : null
    root.varta = shell && typeof shell.serviceFor === "function"
                 ? shell.serviceFor(root.pluginId) : null
  }

  Timer {
    interval: 1000
    repeat: true
    running: !root.varta
    triggeredOnStart: true
    onTriggered: root.findService()
  }

  onBarChanged: findService()

  readonly property bool ready: root.varta && root.varta.region !== ""
  readonly property bool raised: root.varta ? root.varta.raised : false
  readonly property bool calm: root.varta ? root.varta.calm : false
  readonly property string health: root.varta ? root.varta.health : "blind"
  readonly property bool blind: root.ready && root.health !== "ok"

  readonly property color stateColor: {
    if (!root.ready) return Color.muted
    if (root.raised) return "#F87171"
    if (root.blind) return "#FBBF24"
    return root.bar ? root.bar.barForeground : Color.foreground
  }

  readonly property string tooltip: {
    if (!root.varta) return "Varta"
    if (!root.ready) {
      const state = root.varta.detectionState
      if (state === "asking") return "Varta: working out which region you are in"
      if (state && state !== "agreed")
        return "Varta: " + (root.varta.detectionWhy || "could not detect your region")
             + " — pick it in this widget's settings"
      return "Varta: pick your region in this widget's settings"
    }
    if (root.raised) return "Varta: ПОВІТРЯНА ТРИВОГА — " + root.varta.region
                            + " · unofficial, trust the siren and the official app"
    if (root.health === "ok") return "Varta: clear in " + root.varta.region
                                     + " · reading is " + root.varta.sourceAge + "s old"
    if (root.health === "stale") return "Varta: NOT WATCHING — the last reading is minutes old"
    return "Varta: NOT WATCHING — " + (root.varta.trouble || "cannot reach the feed")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    foreground: root.stateColor
    tooltipText: root.tooltip

    iconComponent: Component {
      // Drawn rather than typed: a shield needs no font to exist, and the bar
      // loads this into a fixed 16px canvas that clips nothing, so it lays
      // itself out inside what it is given.
      Item {
        Canvas {
          id: shield
          anchors.centerIn: parent
          width: Math.min(parent.width, parent.height)
          height: width

          readonly property color ink: root.stateColor
          readonly property bool filled: root.raised
          readonly property bool struck: root.blind

          onInkChanged: requestPaint()
          onFilledChanged: requestPaint()
          onStruckChanged: requestPaint()

          onPaint: {
            const c = getContext("2d")
            const s = width
            c.reset()
            c.lineWidth = Math.max(1.2, s * 0.11)
            c.lineJoin = "round"
            c.strokeStyle = shield.ink
            c.fillStyle = shield.ink

            c.beginPath()
            c.moveTo(s * 0.50, s * 0.07)
            c.lineTo(s * 0.86, s * 0.21)
            c.lineTo(s * 0.86, s * 0.52)
            c.quadraticCurveTo(s * 0.86, s * 0.80, s * 0.50, s * 0.94)
            c.quadraticCurveTo(s * 0.14, s * 0.80, s * 0.14, s * 0.52)
            c.lineTo(s * 0.14, s * 0.21)
            c.closePath()
            // Filled means an alert: the loudest thing this shape can do.
            if (shield.filled) c.fill(); else c.stroke()

            // Struck through means the watch cannot see. Not a shape anyone
            // reads as "fine".
            if (shield.struck) {
              c.beginPath()
              c.moveTo(s * 0.16, s * 0.84)
              c.lineTo(s * 0.84, s * 0.16)
              c.stroke()
            }
          }
        }

        // An alert breathes, so it is not something you can look straight at
        // without registering.
        SequentialAnimation on opacity {
          running: root.raised || root.blind
          loops: Animation.Infinite
          NumberAnimation { from: 1; to: 0.42; duration: 620; easing.type: Easing.InOutSine }
          NumberAnimation { from: 0.42; to: 1; duration: 620; easing.type: Easing.InOutSine }
          onStopped: parent.opacity = 1
        }
      }
    }
  }
}

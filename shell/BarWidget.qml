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
    root.share()
  }

  // The widget is where per-widget settings from shell.json arrive; the
  // service is what acts on them. Nothing carries them across on its own, so
  // the widget hands them over — and again whenever they change, so editing
  // the region takes effect without a restart.
  function share() {
    if (root.varta && "settings" in root.varta) root.varta.settings = root.settings
  }

  onSettingsChanged: root.share()

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
  // Only struck through once the watch has something to be blind about.
  readonly property bool blind: root.varta ? root.varta.lost === true : false
  readonly property bool settling: root.ready && root.health !== "ok" && !root.blind
  // Somewhere you keep an eye on, not somewhere you are.
  readonly property int elsewhere: root.varta ? root.varta.alsoRaisedCount : 0

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
    if (root.health === "ok") {
      let line = "Varta: clear in " + root.varta.region
      const watched = root.varta.alsoState || []
      for (const entry of watched) {
        line += "\n" + (entry.alert === true ? "  ПОВІТРЯНА ТРИВОГА  " : "  clear  ") + entry.region
      }
      return line + "\nreading is " + root.varta.sourceAge + "s old"
    }
    if (root.settling) return "Varta: starting up — waiting for the first reading"
    if (root.health === "stale") return "Varta: NOT WATCHING — the last reading is minutes old"
    return "Varta: NOT WATCHING — " + (root.varta.trouble || "cannot reach the feed")
  }

  property bool cardOpen: false
  // The card has two faces: what it knows, and which places to watch.






  // "Not watching" is a serious thing to say, so it is only said when it is
  // true. A watcher coming back after a settings change is not the feed being
  // lost, and must not be dressed up as it — that is how a real warning stops
  // being believed.
  function wordFor(alert) {
    if (!root.varta) return "not watching"
    if (root.varta.lost) return "not watching"
    if (root.varta.health !== "ok") return "reconnecting"
    if (alert === true) return "ПОВІТРЯНА ТРИВОГА"
    if (alert === false) return "clear"
    return "unknown"
  }

  function colourFor(alert) {
    if (!root.varta || root.varta.lost) return "#F2B441"
    if (root.varta.health !== "ok") return Color.muted
    return alert === true ? "#F87171" : Color.muted
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    foreground: root.stateColor
    tooltipText: root.tooltip
    onPressed: function (which) { root.cardOpen = !root.cardOpen }

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
          readonly property bool watching: root.elsewhere > 0 && !root.raised

          onInkChanged: requestPaint()
          onFilledChanged: requestPaint()
          onStruckChanged: requestPaint()
          onWatchingChanged: requestPaint()

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

            // A dot means somewhere you are keeping an eye on is under alert.
            // Deliberately small and deliberately not the alarm colour: it is
            // news, not something for you to act on.
            if (shield.watching) {
              c.beginPath()
              c.arc(s * 0.80, s * 0.20, s * 0.17, 0, Math.PI * 2)
              c.fillStyle = "#F2B441"
              c.fill()
            }

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
        // Same reasoning as the banner: the breathing is to be noticed, and it
        // has been noticed or it has not within the first minute.
        SequentialAnimation on opacity {
          running: (root.raised && root.varta && root.varta.freshlyRaised) || root.blind
          loops: Animation.Infinite
          NumberAnimation { from: 1; to: 0.42; duration: 620; easing.type: Easing.InOutSine }
          NumberAnimation { from: 0.42; to: 1; duration: 620; easing.type: Easing.InOutSine }
          onStopped: parent.opacity = 1
        }
      }
    }
  }

  // What it knows, and the two things you can do about it. Which regions are
  // watched is not set here on purpose: those belong in the widget's own
  // settings, with every other Omarchy widget's options, rather than in a
  // second place that can disagree with the first.
  PopupCard {
    id: card
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.cardOpen && !!root.varta
    padding: Style.space(8)
    contentWidth: card.fittedContentWidth(Style.space(300))
    contentHeight: card.fittedContentHeight(cardColumn.implicitHeight)
    onVisibleChanged: if (!visible) root.cardOpen = false

    Column {
      id: cardColumn
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(3)

      Text {
        width: parent.width
        text: !root.varta ? "Starting"
            : root.varta.health === "ok" ? "Reading is " + root.varta.sourceAge + "s old"
            : root.varta.lost ? "No current reading"
            : "Waiting for the first reading…"
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        bottomPadding: Style.space(3)
      }

      // Where you are.
      Row {
        width: parent.width
        spacing: Style.space(6)
        visible: root.ready

        Text {
          width: parent.width - status.width - Style.space(6)
          text: root.varta ? root.varta.region : ""
          elide: Text.ElideRight
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Text {
          id: status
          text: root.varta ? root.wordFor(root.varta.reading.alert) : ""
          color: root.varta ? root.colourFor(root.varta.reading.alert) : Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.weight: Font.DemiBold
        }
      }

      // And anywhere you keep an eye on.
      Repeater {
        model: root.varta && root.varta.alsoState ? root.varta.alsoState : []

        delegate: Row {
          required property var modelData
          width: cardColumn.width
          spacing: Style.space(6)

          Text {
            width: cardColumn.width - mark.width - Style.space(6)
            text: "· " + modelData.region
            elide: Text.ElideRight
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Text {
            id: mark
            text: root.wordFor(modelData.alert)
            color: root.colourFor(modelData.alert)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      Text {
        width: parent.width
        visible: !root.ready
        wrapMode: Text.WordWrap
        text: root.varta && root.varta.detectionState === "asking"
              ? "Working out which region you are in…"
              : "No region yet — choose one in this widget's settings."
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: {
          const rows = []
          if (root.varta && root.varta.banded)
            rows.push({ label: "Put the band away", action: "dismiss" })
          if (root.varta && root.varta.raised && !(root.varta.banded))
            rows.push({ label: "Show the band again", action: "unhide" })
          rows.push({ label: "Regions to watch…", action: "pick" })
          rows.push({ label: "Test the alert", action: "test" })
          rows.push({ label: "Find my region again", action: "detect" })
          return rows
        }

        delegate: Rectangle {
          id: entry
          required property var modelData
          width: cardColumn.width
          height: Style.space(30)
          radius: Style.space(6)
          color: entryHover.hovered ? Style.hoverFillFor(Color.popups.text, Color.accent)
                                    : "transparent"

          HoverHandler { id: entryHover }

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: entry.modelData.label
            elide: Text.ElideRight
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (!root.varta) return
              const what = entry.modelData.action
              if (what === "pick") { root.varta.openPicker(); root.cardOpen = false; return }
              if (what === "test") root.varta.rehearse()
              else if (what === "dismiss") root.varta.dismiss()
              else if (what === "unhide") root.varta.unhide()
              else root.varta.findMyRegion()
              root.cardOpen = false
            }
          }
        }
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        topPadding: Style.space(3)
        text: "Regions live in this widget's settings. Unofficial, and oblast-wide — "
              + "trust the siren and the official app."
        color: Color.muted
        opacity: 0.85
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

  }
}

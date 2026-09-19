import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons

// Everything Varta knows, and everything you can do about it, in one window.
//
// A window rather than a popup on the bar, for one blunt reason learned the
// hard way: the shell rebuilds its bar widgets whenever a setting is saved, so
// anything living inside one is destroyed mid-click. This outlives that.
FloatingWindow {
  id: panel

  property var service: null

  // What is ticked. Until you touch something this follows the service,
  // because a window opened before the settings arrive would otherwise start
  // empty — and saving that would quietly wipe the places you had chosen.
  property bool touched: false
  property var pending: []

  readonly property var chosen: panel.touched
    ? panel.pending
    : (panel.service ? panel.service.also : [])

  readonly property bool ready: panel.service && panel.service.region !== ""

  visible: true
  implicitWidth: 460
  implicitHeight: 620
  // Size hints, not wishes: a floating window with none gets whatever the
  // compositor feels like, which here was very nearly the whole screen.
  minimumSize: Qt.size(380, 460)
  maximumSize: Qt.size(560, 780)
  title: "Varta"
  // Opaque on purpose: themes give these colours an alpha, and a window you
  // can read the desktop through is a window you misread.
  color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 1)

  // "Not watching" is a serious thing to say, so it is only said when it is
  // true. A watcher coming back after a settings change is not the feed being
  // lost, and must not be dressed up as it — that is how a real warning stops
  // being believed.
  function wordFor(alert) {
    if (!panel.service) return "not watching"
    if (panel.service.lost) return "not watching"
    if (panel.service.health !== "ok") return "reconnecting"
    if (alert === true) return "ПОВІТРЯНА ТРИВОГА"
    if (alert === false) return "clear"
    return "unknown"
  }

  function colourFor(alert) {
    if (!panel.service || panel.service.lost) return "#F2B441"
    if (panel.service.health !== "ok") return Color.muted
    return alert === true ? "#F87171" : Color.muted
  }

  function has(name) {
    for (const current of panel.chosen) if (current === name) return true
    return false
  }

  function toggle(name) {
    if (!panel.service || name === panel.service.region) return
    const from = panel.chosen
    panel.touched = true
    const next = []
    let had = false
    for (const current of from) {
      if (current === name) had = true
      else next.push(current)
    }
    if (!had) next.push(name)
    panel.pending = next
  }

  function save() {
    if (panel.service) panel.service.saveAlso(panel.chosen)
    panel.dismissSelf()
  }

  function dismissSelf() {
    if (panel.service) panel.service.hidePanel()
  }

  // Painted, not merely declared. Setting the window's own colour leaves the
  // surface with an alpha channel the compositor honours, and a window you can
  // read your terminal through is a window you misread. A rectangle is opaque
  // because it is drawn.
  Rectangle {
    anchors.fill: parent
    // Alpha forced, not inherited: the theme's background colour is itself
    // transparent, so painting with it paints nothing and you read your
    // terminal through the window. Take its hue, keep none of its alpha.
    color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 1)
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 18
    spacing: 10

    // Where you are, and how it is. The first thing anyone opens this for.
    ColumnLayout {
      Layout.fillWidth: true
      spacing: 2

      RowLayout {
        Layout.fillWidth: true
        spacing: 10

        Text {
          // Everything shown here is ultimately somebody else's string:
          // region names and error text arrive from the feed. Rendered
          // literally, never interpreted as markup.
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: panel.ready ? panel.service.region : "No region yet"
          elide: Text.ElideRight
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Math.round(Style.font.body * 1.25)
          font.weight: Font.DemiBold
        }

        Text {
          // Everything shown here is ultimately somebody else's string:
          // region names and error text arrive from the feed. Rendered
          // literally, never interpreted as markup.
          textFormat: Text.PlainText
          visible: panel.ready
          text: panel.service ? panel.wordFor(panel.service.reading.alert) : ""
          color: panel.service ? panel.colourFor(panel.service.reading.alert) : Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.weight: Font.DemiBold
        }
      }

      Text {
        // Everything shown here is ultimately somebody else's string:
        // region names and error text arrive from the feed. Rendered
        // literally, never interpreted as markup.
        textFormat: Text.PlainText
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: !panel.service ? "Starting"
            : !panel.ready ? (panel.service.detectionState === "asking"
                              ? "Working out which region you are in…"
                              : "Pick where you are in this widget's settings.")
            : panel.service.health === "ok"
              ? "Reading is " + panel.service.sourceAge + "s old"
            : panel.service.lost ? "No current reading — " + (panel.service.trouble || "cannot reach the feed")
            : "Waiting for the first reading…"
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    // And anywhere you keep an eye on: news, not something to act on.
    ColumnLayout {
      Layout.fillWidth: true
      Layout.topMargin: 4
      spacing: 3
      visible: panel.service && (panel.service.alsoState || []).length > 0

      Repeater {
        model: panel.service && panel.service.alsoState ? panel.service.alsoState : []

        delegate: RowLayout {
          required property var modelData
          Layout.fillWidth: true
          spacing: 10

          Text {
            // Everything shown here is ultimately somebody else's string:
            // region names and error text arrive from the feed. Rendered
            // literally, never interpreted as markup.
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: "· " + modelData.region
            elide: Text.ElideRight
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Text {
            // Everything shown here is ultimately somebody else's string:
            // region names and error text arrive from the feed. Rendered
            // literally, never interpreted as markup.
            textFormat: Text.PlainText
            text: panel.wordFor(modelData.alert)
            color: panel.colourFor(modelData.alert)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.topMargin: 6
      height: 1
      color: Qt.rgba(1, 1, 1, 0.10)
    }

    Text {
      // Everything shown here is ultimately somebody else's string:
      // region names and error text arrive from the feed. Rendered
      // literally, never interpreted as markup.
      textFormat: Text.PlainText
      Layout.fillWidth: true
      wrapMode: Text.WordWrap
      text: "Where you are is marked ★. Anywhere else you tick is shown in the bar "
            + "and sounded once, quietly — it never puts the band on your screen."
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    ListView {
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      model: panel.service ? panel.service.knownRegions : []
      boundsBehavior: Flickable.StopAtBounds

      delegate: Rectangle {
        id: row
        required property var modelData
        width: ListView.view.width
        height: 34
        radius: 8
        readonly property bool mine: panel.service && modelData === panel.service.region
        readonly property bool kept: panel.has(modelData)
        color: row.mine ? Qt.rgba(1, 1, 1, 0.06)
             : hover.hovered ? Qt.rgba(1, 1, 1, 0.10) : "transparent"

        HoverHandler { id: hover; enabled: !row.mine }

        Text {
          // Everything shown here is ultimately somebody else's string:
          // region names and error text arrive from the feed. Rendered
          // literally, never interpreted as markup.
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.leftMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          width: 20
          text: row.mine ? "★" : (row.kept ? "✓" : "")
          color: row.mine ? Color.accent : Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Text {
          // Everything shown here is ultimately somebody else's string:
          // region names and error text arrive from the feed. Rendered
          // literally, never interpreted as markup.
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.leftMargin: 34
          anchors.right: parent.right
          anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          text: row.modelData
          elide: Text.ElideRight
          color: row.mine || row.kept ? Color.foreground : Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        MouseArea {
          anchors.fill: parent
          enabled: !row.mine
          cursorShape: Qt.PointingHandCursor
          onClicked: panel.toggle(row.modelData)
        }
      }
    }

    // The things you occasionally want, kept away from Save so neither is
    // pressed by accident.
    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Repeater {
        model: {
          const rows = []
          if (panel.service && panel.service.banded)
            rows.push({ label: "Put the band away", action: "dismiss" })
          if (panel.service && panel.service.raised && !panel.service.banded)
            rows.push({ label: "Show the band again", action: "unhide" })
          rows.push({ label: "Test the alert", action: "test" })
          rows.push({ label: "Find my region", action: "detect" })
          return rows
        }

        delegate: Rectangle {
          required property var modelData
          implicitWidth: quietLabel.implicitWidth + 20
          implicitHeight: 30
          radius: 8
          color: quietHover.hovered ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.14)

          HoverHandler { id: quietHover }

          Text {
            // Everything shown here is ultimately somebody else's string:
            // region names and error text arrive from the feed. Rendered
            // literally, never interpreted as markup.
            textFormat: Text.PlainText
            id: quietLabel
            anchors.centerIn: parent
            text: modelData.label
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (!panel.service) return
              const what = modelData.action
              if (what === "test") panel.service.rehearse()
              else if (what === "dismiss") panel.service.dismiss()
              else if (what === "unhide") panel.service.unhide()
              else panel.service.findMyRegion()
            }
          }
        }
      }

      Item { Layout.fillWidth: true }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 10

      Text {
        // Everything shown here is ultimately somebody else's string:
        // region names and error text arrive from the feed. Rendered
        // literally, never interpreted as markup.
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: panel.chosen.length === 0
              ? "Watching only where you are"
              : "Watching " + panel.chosen.length
                + (panel.chosen.length === 1 ? " other place" : " other places")
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: [{ label: "Close", save: false }, { label: "Save", save: true }]

        delegate: Rectangle {
          required property var modelData
          implicitWidth: label.implicitWidth + 28
          implicitHeight: 34
          radius: 8
          color: modelData.save
                 ? (buttonHover.hovered ? Color.accent : Qt.rgba(1, 1, 1, 0.14))
                 : (buttonHover.hovered ? Qt.rgba(1, 1, 1, 0.14) : "transparent")
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.18)

          HoverHandler { id: buttonHover }

          Text {
            // Everything shown here is ultimately somebody else's string:
            // region names and error text arrive from the feed. Rendered
            // literally, never interpreted as markup.
            textFormat: Text.PlainText
            id: label
            anchors.centerIn: parent
            text: modelData.label
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: modelData.save ? panel.save() : panel.dismissSelf()
          }
        }
      }
    }

    Text {
      // Everything shown here is ultimately somebody else's string:
      // region names and error text arrive from the feed. Rendered
      // literally, never interpreted as markup.
      textFormat: Text.PlainText
      Layout.fillWidth: true
      wrapMode: Text.WordWrap
      text: "Unofficial, and oblast-wide — trust the siren and the official app."
      color: Color.muted
      opacity: 0.85
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }
}

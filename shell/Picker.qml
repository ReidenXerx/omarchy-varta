import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons

// Choosing which places to watch.
//
// A window of its own, owned by the service, for one blunt reason: saving a
// widget option makes the shell rebuild its bar widgets, and anything living
// inside one of those is destroyed mid-click. This outlives that.
FloatingWindow {
  id: picker

  property var service: null

  // What is ticked. Until you touch something this follows the service, because
  // a window opened before the settings arrive would otherwise start empty —
  // and saving that would quietly wipe the places you had chosen.
  property bool touched: false
  property var pending: []

  readonly property var chosen: picker.touched
    ? picker.pending
    : (picker.service ? picker.service.also : [])

  visible: true
  implicitWidth: 460
  implicitHeight: 600
  // Size hints, not wishes: a floating window with none gets whatever the
  // compositor feels like, which here was very nearly the whole screen.
  minimumSize: Qt.size(380, 420)
  maximumSize: Qt.size(560, 760)
  title: "Varta — regions to watch"
  // Opaque on purpose: themes give these colours an alpha, and a chooser you
  // can read the desktop through is a chooser you misread.
  color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 1)

  function has(name) {
    for (const current of picker.chosen) if (current === name) return true
    return false
  }

  function toggle(name) {
    if (!picker.service || name === picker.service.region) return
    const from = picker.chosen
    picker.touched = true
    const next = []
    let had = false
    for (const current of from) {
      if (current === name) had = true
      else next.push(current)
    }
    if (!had) next.push(name)
    picker.pending = next
  }

  function save() {
    if (picker.service) picker.service.saveAlso(picker.chosen)
    picker.close()
  }

  function close() {
    if (picker.service) picker.service.pickerOpen = false
  }



  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 18
    spacing: 12

    Text {
      Layout.fillWidth: true
      text: "Places to watch"
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Math.round(Style.font.body * 1.25)
      font.weight: Font.DemiBold
    }

    Text {
      Layout.fillWidth: true
      wrapMode: Text.WordWrap
      text: "Where you are is marked ★ and comes from detection or the widget's "
            + "settings. Anywhere else you tick is shown in the bar and sounded "
            + "once, quietly — it never puts the band on your screen."
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    ListView {
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      model: picker.service ? picker.service.knownRegions : []
      boundsBehavior: Flickable.StopAtBounds

      delegate: Rectangle {
        id: row
        required property var modelData
        width: ListView.view.width
        height: 34
        radius: 8
        readonly property bool mine: picker.service && modelData === picker.service.region
        readonly property bool kept: picker.has(modelData)
        color: row.mine ? Qt.rgba(1, 1, 1, 0.06)
             : hover.hovered ? Qt.rgba(1, 1, 1, 0.10) : "transparent"

        HoverHandler { id: hover; enabled: !row.mine }

        Text {
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
          onClicked: picker.toggle(row.modelData)
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 10

      Text {
        Layout.fillWidth: true
        text: picker.chosen.length === 0
              ? "Watching only where you are"
              : "Watching " + picker.chosen.length
                + (picker.chosen.length === 1 ? " other place" : " other places")
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: [{ label: "Cancel", save: false }, { label: "Save", save: true }]

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
            onClicked: modelData.save ? picker.save() : picker.close()
          }
        }
      }
    }
  }
}

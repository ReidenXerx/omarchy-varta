import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

// The panel: where you are and what is known about it, the places you keep an eye on, the last week, and the list
// of regions to choose from. Everything shown here is ultimately the feed's string, so all of it is plain text.
PlasmaExtras.Representation {
  id: view

  required property var varta

  Layout.preferredWidth: Kirigami.Units.gridUnit * 24
  Layout.preferredHeight: Kirigami.Units.gridUnit * 36
  Layout.minimumWidth: Kirigami.Units.gridUnit * 18
  Layout.minimumHeight: Kirigami.Units.gridUnit * 20

  readonly property var v: view.varta
  readonly property var h: view.v.history
  readonly property color faint: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.65)
  readonly property color red: "#E5484D"
  readonly property color amber: "#D99A1E"
  // Sizes from a Plasma label (Kirigami.Theme.smallFont answers differently at a popup's root and in delegates).
  readonly property real smallPt: Math.max(7, Math.round(sizer.font.pointSize * 0.9))
  PlasmaComponents.Label { id: sizer; visible: false }

  function wordFor(alert) {
    if (view.v.lost) return "not watching"
    if (view.v.health !== "ok") return "reconnecting"
    if (alert === true) return "ПОВІТРЯНА ТРИВОГА"
    if (alert === false) return "clear"
    return "unknown"
  }

  function colourFor(alert) {
    if (view.v.lost) return view.amber
    if (view.v.health !== "ok") return view.faint
    return alert === true ? view.red : view.faint
  }

  function spell(seconds) {
    if (seconds === undefined || seconds === null) return ""
    if (seconds < 60) return seconds + " s"
    var minutes = Math.floor(seconds / 60)
    var hh = Math.floor(minutes / 60), m = minutes % 60
    return hh ? (hh + " h " + (m < 10 ? "0" : "") + m + " min") : (m + " min")
  }

  component Note: PlasmaComponents.Label {
    Layout.fillWidth: true
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: view.faint
    font.pointSize: view.smallPt
  }

  header: PlasmaExtras.PlasmoidHeading {
    ColumnLayout {
      anchors.fill: parent
      spacing: 0
      RowLayout {
        Layout.fillWidth: true
        Kirigami.Heading {
          Layout.fillWidth: true
          level: 3
          textFormat: Text.PlainText
          elide: Text.ElideRight
          text: view.v.ready ? view.v.region : "No region yet"
        }
        PlasmaComponents.Label {
          visible: view.v.ready
          textFormat: Text.PlainText
          text: view.wordFor(view.v.reading.alert)
          color: view.v.rehearsing ? view.red : view.colourFor(view.v.reading.alert)
          font.bold: true
        }
      }
      PlasmaComponents.Label {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: view.faint
        text: !view.v.ready ? (view.v.detectionState === "asking" ? "Working out which region you are in…"
                                                                  : "Pick where you are: ★ in the list below.")
            : view.v.health === "ok" ? "Reading is " + view.v.sourceAge + " s old"
            : view.v.lost ? "No current reading: " + (view.v.trouble || "cannot reach the feed")
            : "Waiting for the first reading…"
      }
    }
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Kirigami.Units.largeSpacing

    // ------------------------------------------------ the places kept an eye on
    ColumnLayout {
      Layout.fillWidth: true
      spacing: 0
      visible: view.v.alsoState.length > 0
      Repeater {
        model: view.v.alsoState
        delegate: RowLayout {
          required property var modelData
          Layout.fillWidth: true
          PlasmaComponents.Label {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: "· " + modelData.region
            color: view.faint
          }
          PlasmaComponents.Label {
            textFormat: Text.PlainText
            text: view.wordFor(modelData.alert)
            color: view.colourFor(modelData.alert)
          }
        }
      }
    }

    // ------------------------------------------------ the last week
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Kirigami.Units.smallSpacing
      visible: view.h !== null && (view.h.total > 0 || (view.h.ongoing || []).length > 0)

      RowLayout {
        Layout.fillWidth: true
        PlasmaComponents.Label {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: "Last " + (view.h ? view.h.days : 7) + " days"
          font.bold: true
        }
        PlasmaComponents.Label {
          textFormat: Text.PlainText
          color: view.faint
          text: view.h && view.h.quietSeconds !== null ? "quiet for " + view.spell(view.h.quietSeconds)
              : view.h && (view.h.ongoing || []).length ? "under alert now" : ""
        }
      }

      Repeater {
        model: view.h ? view.h.regions : []
        delegate: RowLayout {
          required property var modelData
          Layout.fillWidth: true
          PlasmaComponents.Label {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: modelData.region
            color: view.faint
          }
          PlasmaComponents.Label {
            textFormat: Text.PlainText
            text: modelData.count + (modelData.count === 1 ? " alert · " : " alerts · ") + view.spell(modelData.seconds)
          }
        }
      }

      // Which hours the alerts fell in, midnight to midnight.
      RowLayout {
        Layout.fillWidth: true
        spacing: 2
        visible: view.h !== null && view.h.byHour.some(function (n) { return n > 0 })
        Repeater {
          model: view.h ? view.h.byHour : []
          delegate: Item {
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: Kirigami.Units.gridUnit * 1.4
            readonly property int tallest: Math.max.apply(null, [1].concat(view.h.byHour))
            Rectangle {
              anchors.bottom: parent.bottom
              width: parent.width
              height: modelData > 0 ? Math.max(2, Math.round(parent.height * modelData / parent.tallest)) : 1
              radius: 1
              color: modelData > 0 ? Kirigami.Theme.highlightColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
            }
          }
        }
      }
      RowLayout {
        Layout.fillWidth: true
        spacing: 2
        visible: view.h !== null && view.h.byHour.some(function (n) { return n > 0 })
        Repeater {
          model: 24
          delegate: Item {
            required property int index
            Layout.fillWidth: true
            implicitHeight: mark.implicitHeight
            PlasmaComponents.Label {
              id: mark
              anchors.horizontalCenter: parent.horizontalCenter
              visible: index % 6 === 0 || index === 23
              textFormat: Text.PlainText
              text: (index < 10 ? "0" : "") + index
              color: view.faint
              font.pointSize: view.smallPt
            }
          }
        }
      }
      Note {
        visible: view.h !== null && !!view.h.longest
        text: view.h && view.h.longest ? "longest " + view.spell(view.h.longest.seconds) + " · " + view.h.longest.region : ""
      }
    }

    Kirigami.Separator { Layout.fillWidth: true }

    // ------------------------------------------------ the regions
    Note {
      text: view.v.knownRegions.length === 0
        ? "The list of regions appears with the first reading of the feed."
        : "★ is where you are. Anywhere else you tick is shown here and sounded once, quietly: it never puts the band on your screen."
    }

    PlasmaComponents.ScrollView {
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: Kirigami.Units.gridUnit * 6
      QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

      ListView {
        id: list
        clip: true
        model: view.v.knownRegions
        boundsBehavior: Flickable.StopAtBounds
        delegate: PlasmaComponents.ItemDelegate {
          id: row
          required property var modelData
          width: list.width
          readonly property bool mine: modelData === view.v.region
          readonly property bool kept: view.v.isWatched(modelData)
          highlighted: row.mine
          onClicked: if (!row.mine) view.v.toggleAlso(row.modelData)
          contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents.CheckBox {
              enabled: !row.mine
              checked: row.kept || row.mine
              onToggled: view.v.toggleAlso(row.modelData)
              Accessible.name: "Keep an eye on " + row.modelData
            }
            PlasmaComponents.Label {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              elide: Text.ElideRight
              text: row.modelData
            }
            PlasmaComponents.ToolButton {
              text: row.mine ? "★" : "☆"
              onClicked: view.v.setRegion(row.modelData)
              PlasmaComponents.ToolTip.text: row.mine ? "Where you are" : "Make this where you are"
              PlasmaComponents.ToolTip.visible: hovered
            }
          }
        }
      }
    }

    // ------------------------------------------------ actions and settings
    Flow {
      Layout.fillWidth: true
      spacing: Kirigami.Units.smallSpacing
      PlasmaComponents.Button {
        visible: view.v.banded || view.v.bandedLost
        text: "Put the band away"
        onClicked: view.v.dismiss()
      }
      PlasmaComponents.Button {
        visible: (view.v.raised && !view.v.banded) || (view.v.lost && !view.v.bandedLost)
        text: "Show the band again"
        onClicked: view.v.unhide()
      }
      PlasmaComponents.Button {
        icon.name: "media-playback-start"
        text: view.v.rehearsing ? "Testing…" : "Test the alert"
        enabled: !view.v.rehearsing
        onClicked: view.v.rehearse()
      }
      PlasmaComponents.Button {
        icon.name: "find-location"
        text: "Detect my region"
        onClicked: { view.v.setRegion(""); view.v.findMyRegion() }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      PlasmaComponents.Switch {
        Layout.fillWidth: true
        text: "Sound"
        checked: view.v.soundOn
        onToggled: view.v.saveSetting("sound", checked)
      }
      PlasmaComponents.ComboBox {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 7
        enabled: view.v.soundOn
        model: ["Glass", "Bell", "Marimba"]
        currentIndex: Math.max(0, ["glass", "bell", "marimba"].indexOf(view.v.voice))
        onActivated: function (i) { view.v.saveSetting("voice", ["Glass", "Bell", "Marimba"][i]) }
      }
    }

    Note { text: "Unofficial, and oblast-wide: trust the siren and the official app." }
  }
}

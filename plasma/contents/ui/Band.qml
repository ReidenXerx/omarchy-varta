import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.core as PlasmaCore

// The band at the top of the screen, for an alert here and for having gone blind: the two states you must not be
// allowed to keep working through unaware. Shown as a critical notification surface, so Plasma keeps it above
// everything, a fullscreen game or film included, and it never takes the keyboard. It covers only a strip at the
// top, with one control: putting it away.
PlasmaCore.Dialog {
  id: band

  property var varta: null

  readonly property bool raised: band.varta ? band.varta.raised : false
  readonly property bool rehearsing: band.varta ? band.varta.rehearsing : false
  readonly property string region: band.varta ? band.varta.region : ""

  // How long this app has been seeing the alert. The free feed cannot say when one actually started, so the
  // wording never pretends otherwise.
  property int seconds: 0
  readonly property bool catching: band.seconds < 60
  readonly property bool compact: band.raised && band.seconds > (band.varta ? band.varta.fullFor : 180)

  // A Dialog's children are its content, so the clock is held in a property.
  property Timer clock: Timer {
    interval: 1000
    repeat: true
    running: band.raised
    triggeredOnStart: true
    onTriggered: {
      var since = band.varta ? band.varta.since : ""
      var began = since ? new Date(since).getTime() : NaN
      band.seconds = isNaN(began) ? 0 : Math.max(0, Math.round((Date.now() - began) / 1000))
    }
  }

  function spoken(total) {
    if (total < 60) return "less than a minute"
    var minutes = Math.floor(total / 60)
    if (minutes < 60) return minutes + (minutes === 1 ? " minute" : " minutes")
    var hours = Math.floor(minutes / 60)
    return hours + (hours === 1 ? " hour " : " hours ") + (minutes % 60) + "m"
  }

  type: PlasmaCore.Dialog.CriticalNotification
  flags: Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
  backgroundHints: PlasmaCore.Dialog.NoBackground
  location: PlasmaCore.Types.Floating
  outputOnly: false
  visible: true

  readonly property rect area: band.screen ? Qt.rect(band.screen.virtualX, band.screen.virtualY, band.screen.width, band.screen.height)
                                           : Qt.rect(0, 0, 1280, 800)
  x: band.area.x + Math.round((band.area.width - strip.width) / 2)
  y: band.area.y + 8

  mainItem: Rectangle {
    id: strip
    width: Math.min(band.area.width - 32, 980)
    height: band.compact ? 34 : 96
    radius: 10
    color: band.rehearsing ? "#1E3A5F" : band.raised ? "#7F1D1D" : "#4A3407"
    Behavior on height { NumberAnimation { duration: 420; easing.type: Easing.InOutCubic } }

    // A slow pulse along the edge for the first minute: movement in the corner of your eye is what a still band
    // cannot do. After that it simply stays.
    Rectangle {
      anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 10; rightMargin: 10 }
      height: 4
      color: band.rehearsing ? "#60A5FA" : band.raised ? "#F87171" : "#FBBF24"
      SequentialAnimation on opacity {
        running: band.catching
        loops: Animation.Infinite
        NumberAnimation { from: 0.35; to: 1; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: 0.35; duration: 700; easing.type: Easing.InOutSine }
        onStopped: parent.opacity = 1
      }
    }

    RowLayout {
      visible: !band.compact
      anchors.fill: parent
      anchors.leftMargin: 26
      anchors.rightMargin: 14
      spacing: 20

      ColumnLayout {
        spacing: 2
        Text {
          // Everything shown here is ultimately somebody else's string: rendered literally, never as markup.
          textFormat: Text.PlainText
          text: band.rehearsing ? "ТЕСТ · ПОВІТРЯНА ТРИВОГА" : band.raised ? "ПОВІТРЯНА ТРИВОГА" : "ТРИВОГИ НЕ ВИДНО"
          color: "#FFF7ED"
          font.pixelSize: 27
          font.weight: Font.Bold
          font.letterSpacing: 1.2
        }
        Text {
          textFormat: Text.PlainText
          text: band.rehearsing ? "This is a test of the alert — no alert is in progress"
              : band.raised ? "Air raid alert · take shelter" : "Not watching · this app cannot see the feed"
          color: "#FDE8D7"
          font.pixelSize: 14
        }
      }

      Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 46; color: Qt.rgba(1, 1, 1, 0.22) }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          elide: Text.ElideRight
          text: band.region
          color: "#FFF7ED"
          font.pixelSize: 17
          font.weight: Font.DemiBold
        }
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          elide: Text.ElideRight
          // Only ever about this oblast.
          text: band.raised ? "seen for " + band.spoken(band.seconds)
                            : (band.varta && band.varta.trouble ? band.varta.trouble : "no reading for several minutes")
          color: "#FDE8D7"
          font.pixelSize: 13
        }
      }

      Text {
        textFormat: Text.PlainText
        text: band.raised ? "Unofficial · trust the siren\nand the official app" : "Check the official app"
        horizontalAlignment: Text.AlignRight
        color: Qt.rgba(1, 1, 1, 0.62)
        font.pixelSize: 12
      }

      Item { Layout.preferredWidth: 30; Layout.preferredHeight: 30 }
    }

    Text {
      visible: band.compact
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: "ПОВІТРЯНА ТРИВОГА · " + band.region + " · seen for " + band.spoken(band.seconds)
      color: "#FFF7ED"
      font.pixelSize: 14
      font.weight: Font.DemiBold
      font.letterSpacing: 0.6
    }

    // The only thing on here you can click.
    Rectangle {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.rightMargin: band.compact ? 6 : 14
      width: band.compact ? 24 : 30
      height: width
      radius: width / 2
      color: away.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.10)
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.28)
      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: "×"
        color: "#FFF7ED"
        font.pixelSize: band.compact ? 13 : 16
      }
      MouseArea {
        id: away
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (band.varta) band.varta.dismiss()
      }
      Accessible.role: Accessible.Button
      Accessible.name: "Put the band away"
    }
  }
}

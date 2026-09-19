import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// The band across the top of every screen.
//
// Loud but not in the way: it takes no keyboard focus and its mask is empty, so
// every click and keystroke goes straight through to whatever you were doing.
// It sits on the overlay layer so a fullscreen game or film does not hide it —
// which is the one place the usual rule about never covering a fullscreen
// window has to be inverted.
Scope {
  id: banner

  property var service: null

  readonly property bool raised: banner.service ? banner.service.raised : false
  readonly property bool rehearsing: banner.service ? banner.service.rehearsing : false
  readonly property string region: banner.service ? banner.service.region : ""

  // How long this app has been seeing the alert. The free feed cannot say when
  // one actually started, so the wording never pretends otherwise.
  property int seconds: 0

  // The edge pulses to catch your eye, then stops.
  //
  // An alert can stand for hours. Sixty frames a second of moving pixels for
  // that long costs real battery, and a band that has been pulsing since
  // midnight has become wallpaper anyway — the movement has done its job in the
  // first minute or it never will. After that the band simply stays, which is
  // the part that actually matters.
  readonly property bool catching: banner.seconds < 60

  // After a few minutes the band stops taking a tenth of the screen and becomes
  // a strip. It stays for the whole alert — it just stops being furniture you
  // have to work around while it does.
  readonly property int fullFor: banner.service ? banner.service.fullFor : 180
  readonly property bool compact: banner.raised && banner.seconds > banner.fullFor

  Timer {
    interval: 1000
    repeat: true
    running: banner.raised
    triggeredOnStart: true
    onTriggered: {
      const since = banner.service ? banner.service.since : ""
      if (!since) { banner.seconds = 0; return }
      const began = new Date(since).getTime()
      banner.seconds = isNaN(began) ? 0 : Math.max(0, Math.round((Date.now() - began) / 1000))
    }
  }

  function spoken(total) {
    if (total < 60) return "less than a minute"
    const minutes = Math.floor(total / 60)
    if (minutes < 60) return minutes + (minutes === 1 ? " minute" : " minutes")
    const hours = Math.floor(minutes / 60)
    const rest = minutes % 60
    return hours + (hours === 1 ? " hour " : " hours ") + rest + "m"
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: surface
      required property var modelData
      screen: surface.modelData

      visible: true
      color: "transparent"
      WlrLayershell.namespace: "omarchy-varta"
      WlrLayershell.layer: WlrLayer.Overlay
      // Never takes the keyboard, and nothing can be clicked on it: this must
      // not be something you have to get out of the way of.
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      // Click-through everywhere except the one control that puts it away.
      // Everything else you click goes to whatever is underneath, which is the
      // whole point of a band you are not meant to have to fight.
      mask: Region { item: putAway }
      anchors { top: true; left: true; right: true }
      implicitHeight: banner.compact ? 30 : 96

      Behavior on implicitHeight {
        NumberAnimation { duration: 420; easing.type: Easing.InOutCubic }
      }

      Rectangle {
        anchors.fill: parent
        color: banner.rehearsing ? "#1E3A5F" : banner.raised ? "#7F1D1D" : "#4A3407"
        opacity: 0.97

        // A slow pulse along the edge: movement in the corner of your eye is
        // what a still band cannot do.
        Rectangle {
          anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
          height: 4
          color: banner.rehearsing ? "#60A5FA" : banner.raised ? "#F87171" : "#FBBF24"

          SequentialAnimation on opacity {
            running: banner.catching
            loops: Animation.Infinite
            NumberAnimation { from: 0.35; to: 1; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1; to: 0.35; duration: 700; easing.type: Easing.InOutSine }
            onStopped: parent.opacity = 1
          }
        }

        // The whole thing, for the first few minutes.
        Row {
          visible: !banner.compact
          opacity: banner.compact ? 0 : 1
          Behavior on opacity { NumberAnimation { duration: 260 } }
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: 28
          anchors.rightMargin: 28
          spacing: 22

          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
              // Everything shown here is ultimately somebody else's string:
              // region names and error text arrive from the feed. Rendered
              // literally, never interpreted as markup.
              textFormat: Text.PlainText
              text: banner.rehearsing ? "ТЕСТ · ПОВІТРЯНА ТРИВОГА"
                  : banner.raised ? "ПОВІТРЯНА ТРИВОГА" : "ТРИВОГИ НЕ ВИДНО"
              color: "#FFF7ED"
              font.family: Style.font.family
              font.pixelSize: 27
              font.weight: Font.Bold
              font.letterSpacing: 1.2
            }

            Text {
              // Everything shown here is ultimately somebody else's string:
              // region names and error text arrive from the feed. Rendered
              // literally, never interpreted as markup.
              textFormat: Text.PlainText
              text: banner.rehearsing ? "This is a test of the alert — no alert is in progress"
                  : banner.raised ? "Air raid alert · take shelter"
                                  : "Not watching · this app cannot see the feed"
              color: "#FDE8D7"
              font.family: Style.font.family
              font.pixelSize: 14
            }
          }

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: 46
            color: Qt.rgba(1, 1, 1, 0.22)
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
              // Everything shown here is ultimately somebody else's string:
              // region names and error text arrive from the feed. Rendered
              // literally, never interpreted as markup.
              textFormat: Text.PlainText
              text: banner.region
              color: "#FFF7ED"
              font.family: Style.font.family
              font.pixelSize: 17
              font.weight: Font.DemiBold
            }

            Text {
              // Everything shown here is ultimately somebody else's string:
              // region names and error text arrive from the feed. Rendered
              // literally, never interpreted as markup.
              textFormat: Text.PlainText
              // Only ever about this oblast. What the rest of the country is
              // doing is not something to put in front of someone who is
              // deciding whether to move.
              text: banner.raised
                    ? "seen for " + banner.spoken(banner.seconds)
                    : (banner.service && banner.service.trouble
                       ? banner.service.trouble
                       : "no reading for several minutes")
              color: "#FDE8D7"
              font.family: Style.font.family
              font.pixelSize: 13
            }
          }

          Item { width: 1; height: 1 }
        }

        // And a strip afterwards, saying the same thing in one line.
        Text {
          // Everything shown here is ultimately somebody else's string:
          // region names and error text arrive from the feed. Rendered
          // literally, never interpreted as markup.
          textFormat: Text.PlainText
          visible: banner.compact
          anchors.centerIn: parent
          text: "ПОВІТРЯНА ТРИВОГА · " + banner.region
                + " · seen for " + banner.spoken(banner.seconds)
          color: "#FFF7ED"
          font.family: Style.font.family
          font.pixelSize: 14
          font.weight: Font.DemiBold
          font.letterSpacing: 0.6
        }

        // The only thing on here you can actually click.
        Rectangle {
          id: putAway
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.rightMargin: banner.compact ? 8 : 14
          width: banner.compact ? 24 : 30
          height: width
          radius: width / 2
          color: away.hovered ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.10)
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.28)

          Text {
            // Everything shown here is ultimately somebody else's string:
            // region names and error text arrive from the feed. Rendered
            // literally, never interpreted as markup.
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: "\u00d7"
            color: "#FFF7ED"
            font.family: Style.font.family
            font.pixelSize: banner.compact ? 13 : 16
          }

          HoverHandler {
            id: away
            cursorShape: Qt.PointingHandCursor
          }

          TapHandler {
            onTapped: if (banner.service) banner.service.dismiss()
          }
        }

        // The thing it is easiest to forget at three in the morning.
        Text {
          // Everything shown here is ultimately somebody else's string:
          // region names and error text arrive from the feed. Rendered
          // literally, never interpreted as markup.
          textFormat: Text.PlainText
          visible: !banner.compact
          anchors.right: putAway.left
          anchors.rightMargin: 16
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignRight
          text: banner.raised
                ? "Unofficial · trust the siren and the official app"
                : "Check the official app"
          color: Qt.rgba(1, 1, 1, 0.62)
          font.family: Style.font.family
          font.pixelSize: 12
        }
      }
    }
  }
}

import QtQuick
import Quickshell
import Quickshell.Io

// What is known about the air raid feed, and what the desktop does about it.
//
// The watcher is a separate process printing one JSON line per poll. That is
// deliberate: if it dies, this notices in the same breath rather than going on
// showing the last thing it heard. A monitor that cannot tell "calm" from "I
// stopped looking" is worse than no monitor, because it is reassuring.
//
// This is a companion to the official app and to the sirens outside, never a
// replacement for either.
Item {
  id: service

  property var shell: null
  property var manifest: null
  property var settings: ({})

  function setting(key, fallback) {
    const value = service.settings ? service.settings[key] : undefined
    return value === undefined || value === null || value === "" ? fallback : value
  }

  readonly property string chosen: String(service.setting("region", "Detect automatically"))
  readonly property bool soundOn: service.setting("sound", true) !== false
  readonly property int repeatEvery: Number(service.setting("repeatEvery", 45))
  readonly property string voice: String(service.setting("voice", "Glass")).toLowerCase()

  // Left on detect, the region comes from one lookup; choose one from the list
  // and the lookup never happens.
  readonly property bool detecting: service.chosen === "" || service.chosen === "Detect automatically"
  property string detected: ""
  property string detectionState: ""
  property string detectionWhy: ""

  readonly property string region: service.detecting ? service.detected : service.chosen

  readonly property string pluginDir:
    String(Qt.resolvedUrl("..")).replace("file://", "")

  // ------------------------------------------------------------ what is known

  property var reading: ({})

  readonly property string health: String(service.reading.health || "blind")
  readonly property bool watching: service.health === "ok"
  // Three answers, not two: true, false, and "I cannot see". The third is why
  // this plugin exists.
  property bool rehearsing: false
  readonly property bool raised: service.reading.alert === true || service.rehearsing
  readonly property bool calm: service.reading.alert === false
  readonly property string since: String(service.reading.since || "")
  readonly property int alertingCount: Number(service.reading.alerting_count || 0)
  readonly property int sourceAge: Number(service.reading.source_age_s || 0)
  readonly property string trouble: String(service.reading.error || "")

  // Starting up is not the same as having lost the feed, and must not look
  // like it: every shell restart would otherwise flash "NOT WATCHING" at you
  // for the second before the first reading lands. So the watch is given a
  // moment to get going, and only complains about going blind once it has
  // either had a reading to lose or been at it long enough to have failed.
  property bool everRead: false
  property bool patient: true

  onWatchingChanged: if (service.watching) service.everRead = true

  Timer {
    id: grace
    interval: 90000
    running: service.region !== "" && service.patient && !service.everRead
    onTriggered: service.patient = false
  }

  onRegionChanged: {
    service.everRead = false
    service.patient = true
    grace.restart()
  }

  // Worth putting on screen: the feed was being read and now is not, or it
  // never could be and that is no longer a startup hiccup.
  readonly property bool lost: service.region !== "" && service.health !== "ok"
                               && (service.everRead || !service.patient)

  // Configured but never yet heard from is its own thing: not calm, not an
  // alert, just not started.
  readonly property bool ready: service.region !== "" && service.reading.health !== undefined

  function absorb(line) {
    if (!line) return
    let next
    try {
      next = JSON.parse(line)
    } catch (problem) {
      return
    }
    const wasRaised = service.raised
    service.reading = next
    if (service.raised && !wasRaised) service.say("alert")
    else if (wasRaised && service.calm) service.say("clear")
  }

  Process {
    id: watcher
    running: service.region !== ""
    command: ["/usr/bin/python3", service.pluginDir + "bin/varta-watch",
              "--region", service.region]
    stdout: SplitParser {
      onRead: function (line) { service.absorb(line) }
    }
    onExited: function (code, status) {
      // The watcher stopping is news in itself. Say so, then try again.
      service.reading = { health: "blind", region: service.region,
                          error: "the watcher stopped (code " + code + ")" }
      revive.restart()
    }
  }

  Timer {
    id: revive
    interval: 5000
    onTriggered: if (service.region !== "") watcher.running = true
  }

  // ------------------------------------------------------------- where we are

  Process {
    id: locator
    command: ["/usr/bin/python3", service.pluginDir + "bin/varta-locate", "--json"]
    stdout: StdioCollector {
      onStreamFinished: {
        let found
        try {
          found = JSON.parse(text)
        } catch (problem) {
          service.detectionState = "failed"
          service.detectionWhy = "the lookup returned nothing usable"
          return
        }
        service.detectionState = String(found.confidence || "unknown")
        service.detectionWhy = String(found.why || "")
        // Only a region both services named is acted on. A guess would point
        // the watch at the wrong place, which is worse than asking.
        service.detected = found.region && found.confidence === "agreed"
                           ? String(found.region) : ""
      }
    }
  }

  // Once, when there is nothing else to go on.
  function findMyRegion() {
    if (!service.detecting || locator.running) return
    service.detectionState = "asking"
    locator.running = true
  }

  onDetectingChanged: if (service.detecting && service.detected === "") service.findMyRegion()
  Component.onCompleted: if (service.detecting) service.findMyRegion()

  // ---------------------------------------------------------------- the sound

  Process { id: player }

  function say(kind) {
    if (!service.soundOn) return
    player.command = ["/usr/bin/paplay",
                      service.pluginDir + "assets/" + kind + "-" + service.voice + ".wav"]
    player.running = true
  }

  // While an alert stands, say so again now and then: the first one can be
  // missed, and the second should not have to wait for the all-clear.
  Timer {
    interval: Math.max(15, service.repeatEvery) * 1000
    repeat: true
    running: service.raised && service.soundOn
    onTriggered: service.say("alert")
  }

  // ---------------------------------------------------------------- the banner

  // On screen for an alert here, and for having gone blind — those are the two
  // states you must not be allowed to keep working through unaware. A brief
  // stale patch stays in the bar, where it belongs.
  // Run it when you want to know it works, rather than finding out during an
  // attack. Everything the real thing does — banner, sound, repeat — with the
  // word ТЕСТ on it throughout, because a rehearsal nobody can tell from the
  // real thing is its own kind of harm.
  IpcHandler {
    target: "varta"

    function test(): string {
      if (service.rehearsing) return "already running"
      service.rehearsing = true
      rehearsal.restart()
      return "rehearsing for " + Math.round(rehearsal.interval / 1000) + "s"
    }

    function stop(): string {
      service.rehearsing = false
      rehearsal.stop()
      return "stopped"
    }

    function status(): string {
      return JSON.stringify({
        region: service.region,
        chosen: service.chosen,
        detection: service.detectionState,
        health: service.health,
        alert: service.reading.alert === undefined ? null : service.reading.alert,
        alertingCount: service.alertingCount,
        sourceAgeSeconds: service.sourceAge,
        rehearsing: service.rehearsing,
      })
    }
  }

  Timer {
    id: rehearsal
    interval: 20000
    onTriggered: service.rehearsing = false
  }

  Loader {
    active: service.raised || service.lost
    source: Qt.resolvedUrl("Banner.qml")
    onLoaded: if (item) item.service = service
  }
}

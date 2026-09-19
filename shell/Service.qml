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
  // Settings reach this service two ways, and it needs both.
  //
  // The widget hands them over when the shell has them — but the shell reads
  // per-widget options at start, so `omarchy bar set` writes the file and
  // nothing happens until a restart. Watching the file directly closes that
  // gap: however you change your region — Barber, the command line, an editor —
  // the watch follows within a second. For a safety tool, "you must remember to
  // restart the shell or it is silently watching the wrong oblast" is not an
  // acceptable rule.
  property var settings: ({})
  property var onDisk: ({})

  function setting(key, fallback) {
    let value = service.settings ? service.settings[key] : undefined
    if (value === undefined || value === null || value === "")
      value = service.onDisk ? service.onDisk[key] : undefined
    return value === undefined || value === null || value === "" ? fallback : value
  }

  FileView {
    id: barConfig
    path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"))
          + "/omarchy/shell.json"
    watchChanges: true
    onFileChanged: barConfig.reload()
    onLoaded: {
      let parsed
      try {
        parsed = JSON.parse(barConfig.text())
      } catch (problem) {
        return
      }
      const sections = parsed && parsed.bar && parsed.bar.layout ? parsed.bar.layout : {}
      for (const section in sections) {
        for (const entry of (sections[section] || [])) {
          if (entry && entry.id === "reidenxerx.varta") {
            service.onDisk = entry
            return
          }
        }
      }
      service.onDisk = ({})
    }
  }

  readonly property string chosen: String(service.setting("region", "Detect automatically"))
  readonly property bool soundOn: service.setting("sound", true) !== false
  readonly property int repeatEvery: Number(service.setting("repeatEvery", 45))
  readonly property int sayTimes: Number(service.setting("sayTimes", 3))
  readonly property int fullFor: Number(service.setting("fullFor", 180))
  readonly property string alsoRaw: String(service.setting("also", ""))
  readonly property string voice: String(service.setting("voice", "Glass")).toLowerCase()

  // Left on detect, the region comes from one lookup; choose one from the list
  // and the lookup never happens.
  readonly property bool detecting: service.chosen === "" || service.chosen === "Detect automatically"
  property string detected: ""
  property string detectionState: ""
  property string detectionWhy: ""

  readonly property string region: service.detecting ? service.detected : service.chosen

  // Places kept an eye on. Never enough to put a band on the screen: that is
  // reserved for where you actually are.
  readonly property var also: {
    const out = []
    for (const name of service.alsoRaw.split(",")) {
      const trimmed = name.trim()
      if (trimmed !== "" && trimmed !== service.region) out.push(trimmed)
    }
    return out
  }
  readonly property var alsoState: service.reading.also || []
  // Straight from the feed, so the list in the picker is the list that exists.
  readonly property var knownRegions: service.reading.known || []
  readonly property int alsoRaisedCount: {
    let n = 0
    for (const entry of service.alsoState) if (entry.alert === true) n++
    return n
  }

  readonly property string pluginDir:
    String(Qt.resolvedUrl("..")).replace("file://", "")

  // ------------------------------------------------------------ what is known

  property var reading: ({})

  readonly property string health: String(service.reading.health || "blind")
  readonly property bool watching: service.health === "ok"
  // Three answers, not two: true, false, and "I cannot see". The third is why
  // this plugin exists.
  property bool rehearsing: false

  // Putting the band away, for this alert only.
  //
  // It hides the band and nothing else: the shield in the bar stays red for as
  // long as the alert stands, so the fact is never actually gone — only the
  // thing taking up your screen. A new alert brings the band back, because
  // "dismissed" should never quietly mean "and never tell me again".
  property string dismissed: ""

  readonly property string alertKey: service.rehearsing
    ? "rehearsal" : service.region + "|" + service.since

  readonly property bool banded: service.raised && service.dismissed !== service.alertKey

  // And a way back, for a band put away by mistake.
  function unhide() {
    service.dismissed = ""
    return "band shown again"
  }

  function dismiss() {
    if (service.rehearsing) {
      service.rehearsing = false
      rehearsal.stop()
      return "rehearsal ended"
    }
    if (!service.raised) return "nothing to dismiss"
    service.dismissed = service.alertKey
    return "band hidden until this alert ends"
  }

  // True for the first minute of an alert, which is how long movement is worth
  // its cost on a battery.
  property bool freshlyRaised: false

  onRaisedChanged: {
    service.freshlyRaised = service.raised
    if (service.raised) {
      newsworthy.restart()
    } else {
      newsworthy.stop()
      service.said = 0
    }
  }

  Timer {
    id: newsworthy
    interval: 60000
    onTriggered: service.freshlyRaised = false
  }
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
    if (next.resumed) {
      // The machine slept. Its network is usually a moment behind it, and that
      // is not the feed being lost — shouting about it every morning is how a
      // warning becomes something you look past.
      service.everRead = false
      service.patient = true
      grace.restart()
    }
    const wasRaised = service.raised
    const wasElsewhere = service.alsoRaisedCount
    service.reading = next

    if (service.raised && !wasRaised) {
      service.said = 1
      service.say("alert", false)
    } else if (wasRaised && service.calm) {
      service.say("clear", false)
    } else if (service.alsoRaisedCount > wasElsewhere) {
      // Somewhere you are keeping an eye on. Said once, quietly, and never
      // with a band across the screen.
      service.say("alert", true)
    }
  }

  Process {
    id: watcher
    running: service.region !== ""
    command: ["/usr/bin/python3", service.pluginDir + "bin/varta-watch",
              "--region", service.region, "--also", service.also.join(",")]
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

  // Changing where you are must change what is being watched.
  //
  // A running process keeps the arguments it started with, so without this the
  // widget would say one oblast while the watcher reported another — the app
  // quietly watching the wrong place while looking entirely correct. Of every
  // way this could fail, that is the worst.
  readonly property string watchKey: service.region + "\u0000" + service.also.join(",")

  onWatchKeyChanged: {
    if (!watcher.running) {
      revive.restart()
      return
    }
    // Drop everything known about the old place before the new one answers.
    service.reading = ({})
    service.everRead = false
    service.patient = true
    grace.restart()
    watcher.running = false      // onExited schedules the restart
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

  // Settings are written with Omarchy's own tool rather than by editing
  // shell.json here: one writer, and the file keeps whatever shape the platform
  // expects. The change comes back through the FileView a moment later, which
  // is what makes the picker feel immediate.
  Process { id: writer }

  function saveAlso(regions) {
    writer.command = ["/usr/share/omarchy/bin/omarchy-bar", "set",
                      "reidenxerx.varta", "also", regions.join(", ")]
    writer.running = true
  }

  function toggleAlso(name) {
    if (!name || name === service.region) return
    const next = []
    let had = false
    for (const current of service.also) {
      if (current === name) had = true
      else next.push(current)
    }
    if (!had) next.push(name)
    service.saveAlso(next)
  }

  function isWatched(name) {
    for (const current of service.also) if (current === name) return true
    return false
  }

  function say(kind, soft) {
    if (!service.soundOn) return
    const file = service.pluginDir + "assets/" + kind + "-" + service.voice + ".wav"
    // Somewhere else is worth hearing about, quietly. Paplay's scale is out of
    // 65536, so this is a little under half.
    player.command = soft ? ["/usr/bin/paplay", "--volume=27000", file]
                          : ["/usr/bin/paplay", file]
    player.running = true
  }

  property int said: 0

  // The first sounding can be missed, so it says so again — a few times, and
  // then it stops. An alert can stand for hours, and something that has been
  // chiming since midnight is something you will turn off, which leaves you
  // with nothing at all.
  Timer {
    interval: Math.max(15, service.repeatEvery) * 1000
    repeat: true
    running: service.raised && service.soundOn && service.said < service.sayTimes
    onTriggered: {
      service.said++
      service.say("alert", false)
    }
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

    function test(): string { return service.rehearse() }

    function stop(): string {
      service.rehearsing = false
      rehearsal.stop()
      return "stopped"
    }

    function dismiss(): string { return service.dismiss() }

    function show(): string { return service.unhide() }

    function status(): string {
      return JSON.stringify({
        region: service.region,
        chosen: service.chosen,
        detection: service.detectionState,
        health: service.health,
        alert: service.reading.alert === undefined ? null : service.reading.alert,
        also: service.alsoState,
        alsoRaised: service.alsoRaisedCount,
        alertingCount: service.alertingCount,
        sourceAgeSeconds: service.sourceAge,
        rehearsing: service.rehearsing,
        bandDismissed: service.raised && service.dismissed === service.alertKey,
      })
    }
  }

  function rehearse() {
    if (service.rehearsing) return "already running"
    service.rehearsing = true
    rehearsal.restart()
    return "rehearsing for " + Math.round(rehearsal.interval / 1000) + "s"
  }

  Timer {
    id: rehearsal
    interval: 20000
    onTriggered: service.rehearsing = false
  }

  Loader {
    active: service.banded || service.lost
    source: Qt.resolvedUrl("Banner.qml")
    onLoaded: if (item) item.service = service
  }
}

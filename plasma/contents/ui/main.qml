import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support

// Varta for Plasma: what is known about the air raid feed, and what the desktop does about it.
//
// The watcher (bin/varta-watch, the same one the Omarchy edition streams) runs for as long as this widget does and
// keeps its latest reading in a private file in the runtime directory; this reads that file every few seconds. A
// reading that stops changing is treated exactly like a watcher that stopped: not watching. A monitor that cannot
// tell "calm" from "I stopped looking" is worse than no monitor, because it is reassuring.
//
// A companion to the official app and to the sirens outside, never a replacement for either.
PlasmoidItem {
  id: root

  readonly property string code: String(Qt.resolvedUrl("../code")).replace("file://", "")

  // Every helper starts from an empty environment with only what it needs: Python runs isolated on top of that.
  // PYTHONIOENCODING is not optional: region names are Cyrillic. The shell expands the runtime and state directories.
  readonly property string envPrefix: "/usr/bin/env -i HOME=\"$HOME\" PATH=/usr/bin:/bin LANG=C.UTF-8 PYTHONIOENCODING=utf-8"
    + " XDG_RUNTIME_DIR=\"$XDG_RUNTIME_DIR\" XDG_STATE_HOME=\"$XDG_STATE_HOME\" "
  readonly property string statePath: "\"$XDG_RUNTIME_DIR\"/varta/plasma.json"

  function quote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
  function helper(name) { return root.envPrefix + "/usr/bin/python3 -I " + root.quote(root.code + "/bin/" + name) }

  // ---------------------------------------------------------------- settings

  readonly property string chosen: String(Plasmoid.configuration.region || "Detect automatically")
  readonly property bool soundOn: Plasmoid.configuration.sound !== false
  readonly property int repeatEvery: Math.max(15, Number(Plasmoid.configuration.repeatEvery) || 45)
  readonly property int sayTimes: Math.max(0, Math.min(10, Number(Plasmoid.configuration.sayTimes) || 0))
  readonly property int fullFor: Math.max(10, Number(Plasmoid.configuration.fullFor) || 180)
  readonly property string voice: {
    var v = String(Plasmoid.configuration.voice || "Glass").toLowerCase()
    return ["glass", "bell", "marimba"].indexOf(v) >= 0 ? v : "glass"
  }

  readonly property bool detecting: root.chosen === "" || root.chosen === "Detect automatically"
  property string detected: ""
  property string detectionState: ""
  property string detectionWhy: ""
  readonly property string region: root.detecting ? root.detected : root.chosen

  // Places kept an eye on. Never enough to put a band on the screen: that is reserved for where you actually are.
  readonly property var also: String(Plasmoid.configuration.also || "").split(",")
    .map(function (n) { return n.trim() }).filter(function (n) { return n !== "" && n !== root.region }).slice(0, 30)

  // ---------------------------------------------------------------- commands

  P5Support.DataSource {
    id: runner
    engine: "executable"
    property var onDone: ({})
    onNewData: function (source, data) {
      disconnectSource(source)
      var cb = runner.onDone[source]
      delete runner.onDone[source]
      if (cb) cb(Number(data["exit code"]), String(data["stdout"] || ""))
    }
  }

  function run(command, done) {
    if (runner.onDone[command] !== undefined) return      // the same command is already running
    runner.onDone[command] = done || null
    runner.connectSource(command)
  }

  // ---------------------------------------------------------------- the watcher

  readonly property string watchCommand: root.region === "" ? ""
    : root.helper("varta-watch") + " --region " + root.quote(root.region) + " --also " + root.quote(root.also.join(","))
      + " --state " + root.statePath
  property string runningWatch: ""
  // Another Varta widget's watcher keeps the reading: this one only reads it.
  property bool sharing: false

  P5Support.DataSource {
    id: watchSource
    engine: "executable"
    // The only news a long-running command gives is that it stopped. That is news in itself.
    onNewData: function (source, data) {
      if (source !== root.runningWatch) return
      disconnectSource(source)
      root.runningWatch = ""
      var code = Number(data["exit code"])
      root.sharing = code === 75
      if (!root.sharing)
        root.reading = { health: "blind", region: root.region, error: "the watcher stopped (code " + code + ")" }
      revive.interval = root.sharing ? 60000 : 5000
      revive.restart()
    }
  }

  function startWatch() {
    if (root.runningWatch !== "") {
      watchSource.disconnectSource(root.runningWatch)       // stops it: the engine kills what it no longer runs
      root.runningWatch = ""
    }
    if (root.watchCommand === "") return
    root.runningWatch = root.watchCommand
    watchSource.connectSource(root.runningWatch)
  }

  Timer {
    id: revive
    interval: 5000
    onTriggered: if (root.runningWatch === "") root.startWatch()
  }

  // Changing where you are must change what is being watched: a widget saying one oblast while the watcher reports
  // another is, of every way this could fail, the worst.
  onWatchCommandChanged: {
    root.reading = ({})
    root.everRead = false
    root.patient = true
    grace.restart()
    Qt.callLater(root.startWatch)
  }

  // ---------------------------------------------------------------- what is known

  property var reading: ({})

  Timer {
    interval: 4000
    repeat: true
    running: root.region !== ""
    triggeredOnStart: true
    onTriggered: root.run("/usr/bin/head -c 262144 -- " + root.statePath + " # " + Date.now(), function (code, out) {
      if (code !== 0 || out === "") return
      var next
      try { next = JSON.parse(out) } catch (e) { return }
      if (!next || next.region !== root.region) return          // another widget's watcher, watching elsewhere
      root.absorb(next)
    })
  }

  // A reading older than this means the watcher stopped writing, however it stopped.
  readonly property int staleAfter: 6 * 60

  readonly property string health: {
    var h = String(root.reading.health || "blind")
    if (h === "ok" && root.reading.at) {
      var at = new Date(root.reading.at).getTime()
      if (!isNaN(at) && (root.nowMs - at) / 1000 > root.staleAfter) return "stale"
    }
    return h
  }
  property double nowMs: Date.now()
  Timer { interval: 5000; repeat: true; running: true; onTriggered: root.nowMs = Date.now() }

  readonly property bool watching: root.health === "ok"
  property bool rehearsing: false
  readonly property bool raised: (root.watching && root.reading.alert === true) || root.rehearsing
  readonly property bool calm: root.watching && root.reading.alert === false
  readonly property string since: String(root.reading.since || "")
  readonly property int sourceAge: Number(root.reading.source_age_s || 0)
  readonly property string trouble: String(root.reading.error || "")
  readonly property var alsoState: root.reading.also || []
  readonly property var knownRegions: root.reading.known || []
  readonly property int alsoRaisedCount: root.alsoState.filter(function (e) { return e.alert === true }).length

  // Starting up is not having lost the feed: the watch gets a moment, and only complains about going blind once it
  // has had a reading to lose or been at it long enough to have failed.
  property bool everRead: false
  property bool patient: true
  onWatchingChanged: if (root.watching) root.everRead = true
  Timer {
    id: grace
    interval: 90000
    running: root.region !== "" && root.patient && !root.everRead
    onTriggered: root.patient = false
  }
  readonly property bool lost: root.region !== "" && root.health !== "ok" && (root.everRead || !root.patient)

  property string lastAt: ""
  function absorb(next) {
    if (next.at === root.lastAt) return
    root.lastAt = String(next.at || "")
    if (next.resumed) {
      // The machine slept; its network is usually a moment behind it, and that is not the feed being lost.
      root.everRead = false
      root.patient = true
      grace.restart()
    }
    var wasRaised = root.raised
    var wasElsewhere = root.alsoRaisedCount
    root.reading = next
    if (root.raised && !wasRaised) {
      root.said = 1
      root.say("alert", false)
      root.notify(true)
    } else if (wasRaised && root.calm) {
      root.say("clear", false)
      root.notify(false)
    } else if (root.alsoRaisedCount > wasElsewhere) {
      root.say("alert", true)
    }
  }

  // ---------------------------------------------------------------- where we are

  function findMyRegion() {
    if (!root.detecting) return
    root.detectionState = "asking"
    root.run(root.helper("varta-locate") + " --json", function (code, out) {
      var found
      try { found = JSON.parse(out) } catch (e) {
        root.detectionState = "failed"
        root.detectionWhy = "the lookup returned nothing usable"
        return
      }
      root.detectionState = String(found.confidence || "unknown")
      root.detectionWhy = String(found.why || "")
      // Only a region both services named is acted on: a guess would point the watch at the wrong place.
      root.detected = found.region && found.confidence === "agreed" ? String(found.region) : ""
    })
  }

  onDetectingChanged: if (root.detecting && root.detected === "") root.findMyRegion()
  Component.onCompleted: if (root.detecting) root.findMyRegion()

  function saveSetting(key, value) { Plasmoid.configuration[key] = value }

  function setRegion(name) { Plasmoid.configuration.region = name ? String(name) : "Detect automatically" }

  function toggleAlso(name) {
    if (!name || name === root.region) return
    var next = root.also.filter(function (n) { return n !== name })
    if (next.length === root.also.length) next.push(name)
    Plasmoid.configuration.also = next.join(", ")
  }

  function isWatched(name) { return root.also.indexOf(name) >= 0 }

  // ---------------------------------------------------------------- the history

  property var history: null
  function refreshHistory() {
    root.run(root.helper("varta-history") + " --json", function (code, out) {
      try { root.history = JSON.parse(out) } catch (e) { root.history = null }
    })
  }
  onExpandedChanged: function () { if (root.expanded) root.refreshHistory() }
  onRaisedChanged: {
    root.freshlyRaised = root.raised
    if (root.expanded) root.refreshHistory()
    if (root.raised) newsworthy.restart(); else { newsworthy.stop(); root.said = 0 }
  }

  property bool freshlyRaised: false
  Timer { id: newsworthy; interval: 60000; onTriggered: root.freshlyRaised = false }

  // ---------------------------------------------------------------- sound and notices

  function say(kind, soft) {
    if (!root.soundOn) return
    var file = root.quote(root.code + "/assets/" + kind + "-" + root.voice + ".wav")
    // Paplay's scale is out of 65536: somewhere else is heard a little under half as loud.
    var env = "/usr/bin/env -i HOME=\"$HOME\" PATH=/usr/bin:/bin XDG_RUNTIME_DIR=\"$XDG_RUNTIME_DIR\" PULSE_SERVER=\"$PULSE_SERVER\" "
    root.run(env + "/usr/bin/paplay " + (soft ? "--volume=27000 " : "") + file + " # " + Date.now(), null)
  }

  property int said: 0
  // The first sounding can be missed, so it says so again a few times, and then it stops: something chiming since
  // midnight is something you will turn off, which leaves you with nothing at all.
  Timer {
    interval: root.repeatEvery * 1000
    repeat: true
    running: root.raised && root.soundOn && root.said < root.sayTimes
    onTriggered: { root.said++; root.say("alert", false) }
  }

  // Plasma's own critical notifications stay until dismissed and show through Do Not Disturb. The all-clear takes
  // the alert's place rather than leaving it standing above.
  property int noticeId: 0
  function notify(raisedNow) {
    var title = raisedNow ? (root.rehearsing ? "ТЕСТ · ПОВІТРЯНА ТРИВОГА" : "ПОВІТРЯНА ТРИВОГА") : "Відбій тривоги"
    var body = raisedNow
      ? (root.rehearsing ? "A test of the alert: no alert is in progress." : root.region + " · take shelter. Unofficial: trust the siren and the official app.")
      : root.region + ": the alert has ended."
    var replace = root.noticeId > 0 ? " --replace-id=" + root.noticeId : ""
    root.run("/usr/bin/notify-send --print-id --app-name=Varta --icon=" + (raisedNow ? "security-low" : "security-high")
             + " --urgency=" + (raisedNow ? "critical" : "normal") + replace + " -- " + root.quote(title) + " " + root.quote(body)
             + " # " + Date.now(), function (code, out) {
      var id = parseInt(out, 10)
      root.noticeId = raisedNow && id > 0 ? id : 0
    })
  }

  // ---------------------------------------------------------------- the band

  // Putting the band away hides the band and nothing else, for this alert only: the icon stays red for as long as
  // the alert stands, and a new alert brings the band back.
  property string dismissed: ""
  readonly property string alertKey: root.rehearsing ? "rehearsal" : root.region + "|" + root.since
  readonly property bool banded: root.raised && root.dismissed !== root.alertKey

  property string lostDismissed: ""
  property int lostEpisode: 0
  readonly property string lostKey: "lost:" + root.lostEpisode
  onLostChanged: if (root.lost) root.lostEpisode++
  readonly property bool bandedLost: root.lost && root.lostDismissed !== root.lostKey

  function dismiss() {
    if (root.rehearsing) { root.rehearsing = false; rehearsal.stop(); return }
    if (root.raised) { root.dismissed = root.alertKey; return }
    if (root.lost) root.lostDismissed = root.lostKey
  }

  function unhide() { root.dismissed = ""; root.lostDismissed = "" }

  function rehearse() {
    if (root.rehearsing) return
    root.rehearsing = true
    rehearsal.restart()
    root.said = 1
    root.say("alert", false)
    root.notify(true)
  }

  Timer { id: rehearsal; interval: 20000; onTriggered: root.rehearsing = false }

  Loader {
    active: root.banded || root.bandedLost
    source: "Band.qml"
    onLoaded: item.varta = root
  }

  // ---------------------------------------------------------------- the icon

  readonly property bool ready: root.region !== ""
  readonly property bool settling: root.ready && root.health !== "ok" && !root.lost

  Plasmoid.icon: !root.ready ? "security-medium" : root.raised ? "security-low" : root.lost ? "dialog-warning" : "security-high"
  Plasmoid.status: root.raised || root.lost ? PlasmaCore.Types.NeedsAttentionStatus : PlasmaCore.Types.ActiveStatus

  toolTipMainText: "Varta"
  toolTipSubText: {
    if (!root.ready) {
      if (root.detectionState === "asking") return "Working out which region you are in"
      if (root.detectionState && root.detectionState !== "agreed")
        return (root.detectionWhy || "Could not detect your region") + ": pick it in the panel"
      return "Pick your region in the panel"
    }
    if (root.raised) return "ПОВІТРЯНА ТРИВОГА · " + root.region + "\nUnofficial: trust the siren and the official app"
    if (root.watching) {
      var line = "Clear in " + root.region
      for (var i = 0; i < root.alsoState.length; i++)
        line += "\n" + (root.alsoState[i].alert === true ? "ПОВІТРЯНА ТРИВОГА · " : "clear · ") + root.alsoState[i].region
      return line + "\nReading is " + root.sourceAge + " s old"
    }
    if (root.settling) return "Starting: waiting for the first reading"
    if (root.health === "stale") return "NOT WATCHING: the last reading is minutes old"
    return "NOT WATCHING: " + (root.trouble || "cannot reach the feed")
  }

  preferredRepresentation: compactRepresentation
  fullRepresentation: FullView { varta: root }
}

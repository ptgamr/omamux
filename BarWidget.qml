import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.ptgamr.omamux"

  property var sessions: []
  property string hostName: "local"
  property bool tmuxAvailable: true
  property string tmuxVersion: ""
  property string errorText: ""
  property string statusMessage: ""
  property bool loading: false
  property bool refreshPending: false

  readonly property int sessionCount: sessions.length
  readonly property int runningSessionCount: {
    var count = 0
    for (var i = 0; i < sessions.length; i++)
      if (sessions[i].running !== false) count++
    return count
  }
  readonly property int savedSessionCount: sessionCount - runningSessionCount
  readonly property int attachedCount: {
    var count = 0
    for (var i = 0; i < sessions.length; i++)
      if (Number(sessions[i].attachedClients || 0) > 0) count++
    return count
  }
  readonly property int refreshIntervalMs: Math.max(3, Number(setting("refreshIntervalSec", 10))) * 1000
  readonly property string backendPath: localFilePath(Qt.resolvedUrl("scripts/omamux"))

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function localFilePath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.slice(7)
    try { return decodeURIComponent(value) } catch (e) { return value }
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
  }

  function refresh() {
    if (listProcess.running) {
      refreshPending = true
      return
    }

    loading = true
    listProcess.command = [backendPath, "list"]
    listProcess.running = true
  }

  function applyList(raw) {
    var result = Model.parseListPayload(raw)
    loading = false

    if (result.ok) {
      sessions = result.sessions
      hostName = String(result.host.name || "local")
      tmuxAvailable = result.tmux.available === true
      tmuxVersion = String(result.tmux.version || "")
      statusMessage = result.error
      errorText = ""
    } else {
      errorText = result.error
    }

    if (refreshPending) {
      refreshPending = false
      Qt.callLater(root.refresh)
    }
  }

  function tooltip() {
    if (loading && sessionCount === 0) return "Loading tmux sessions…"
    if (!tmuxAvailable) return "tmux is not installed"
    if (errorText !== "") return "Omamux · " + errorText
    var text = runningSessionCount + " tmux session"
      + (runningSessionCount === 1 ? "" : "s")
    if (savedSessionCount > 0) text += " · " + savedSessionCount + " saved"
    if (attachedCount > 0) text += " · " + attachedCount + " attached"
    return text
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  Process {
    id: listProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyList(text)
    }
  }

  Timer {
    interval: root.refreshIntervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: root.moduleName

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.broadcast("refresh") }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.tooltip()
    iconComponent: Component {
      OmamuxIcon {
        contentScale: 0.72
        paneColor: Color.muted
        accentColor: Color.accent
      }
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refresh()
      else root.toggle()
    }
  }
}

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.ptgamr.omamux"
  ipcTarget: moduleName
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property var rows: []
  property int selectedIndex: -1
  property bool cursorActive: false
  property bool creating: false
  property string createText: ""
  property string actionKind: ""
  property string actionError: ""
  property bool closeAfterAction: false
  property double nowMs: Date.now()

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Color.muted
  readonly property color availableColor: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool actionBusy: actionProcess.running
  readonly property int favoriteCount: {
    var count = 0
    for (var i = 0; i < rows.length; i++)
      if (rows[i].favorite === true) count++
    return count
  }
  readonly property int listHeight: rows.length > 0
    ? Math.min(Style.space(440), rows.length * Style.space(62) + Math.max(0, rows.length - 1) * Style.space(6))
    : Style.space(128)

  function open() {
    root.controller.show()
    if (hostWidget) hostWidget.refresh()
  }

  function close() {
    cancelCreate()
    root.controller.hide()
  }

  function toggle() {
    if (opened) close()
    else open()
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  function syncRows() {
    var previousName = selectedSession() ? String(selectedSession().name) : ""
    rows = hostWidget && Array.isArray(hostWidget.sessions)
      ? hostWidget.sessions.slice(0)
      : []

    var nextIndex = -1
    if (previousName !== "") {
      for (var i = 0; i < rows.length; i++)
        if (String(rows[i].name) === previousName) { nextIndex = i; break }
    }
    if (nextIndex < 0 && rows.length > 0) nextIndex = 0
    selectedIndex = nextIndex
    revealSelection()
  }

  function selectedSession() {
    if (selectedIndex < 0 || selectedIndex >= rows.length) return null
    return rows[selectedIndex]
  }

  function revealSelection() {
    if (selectedIndex >= 0 && sessionList)
      Qt.callLater(function() { sessionList.positionViewAtIndex(selectedIndex, ListView.Contain) })
  }

  function moveSelection(delta) {
    if (rows.length === 0) return
    cursorActive = true
    selectedIndex = Model.clampedIndex(selectedIndex + delta, rows.length)
    revealSelection()
  }

  function activateSelected() {
    var session = selectedSession()
    if (session) attachSession(String(session.name))
  }

  function selectRow(index) {
    cursorActive = true
    selectedIndex = Model.clampedIndex(index, rows.length)
  }

  function runAction(args, shouldClose) {
    if (actionBusy || !hostWidget) return
    actionError = ""
    actionKind = String(args[0] || "action")
    closeAfterAction = shouldClose === true
    actionProcess.command = [hostWidget.backendPath].concat(args)
    actionProcess.running = true
  }

  function applyAction(raw) {
    var result = Model.parseActionPayload(raw, "Omamux command failed")
    var shouldClose = closeAfterAction && result.ok
    closeAfterAction = false
    actionKind = ""

    if (result.ok) {
      actionError = ""
      if (hostWidget) hostWidget.refresh()
      if (shouldClose) close()
    } else {
      actionError = result.error
      syncRows()
    }
  }

  function attachSession(name) {
    runAction(["attach", name], true)
  }

  function toggleFavorite(name) {
    runAction(["favorite", "toggle", name], false)
  }

  function favoriteNames(values) {
    return Model.favoriteOrder(values)
  }

  function moveFavorite(from, to) {
    if (actionBusy || from < 0 || from >= favoriteCount) return
    var target = Math.max(0, Math.min(favoriteCount - 1, to))
    if (from === target) return

    var next = rows.slice(0)
    var moved = next.splice(from, 1)[0]
    next.splice(target, 0, moved)
    rows = next
    selectedIndex = target
    cursorActive = true
    revealSelection()
    runAction(["favorite", "reorder"].concat(favoriteNames(next)), false)
  }

  function moveSelectedFavorite(delta) {
    var session = selectedSession()
    if (!session || session.favorite !== true) return
    moveFavorite(selectedIndex, selectedIndex + delta)
  }

  function startCreate() {
    if (actionBusy || !hostWidget || !hostWidget.tmuxAvailable) return
    creating = true
    actionError = ""
    createText = Model.suggestSessionName(rows)
    Qt.callLater(function() {
      createField.selectAll()
      createField.forceActiveFocus()
    })
  }

  function cancelCreate() {
    creating = false
    createText = ""
    if (opened) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function createSession() {
    var name = Model.normalizedSessionName(createText)
    var error = Model.validationError(name)
    if (error !== "") {
      actionError = error
      return
    }
    runAction(["create", name], true)
  }

  onOpenedChanged: {
    if (opened) {
      nowMs = Date.now()
      cursorActive = false
      syncRows()
      if (hostWidget) hostWidget.refresh()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      creating = false
      actionError = ""
    }
  }

  Connections {
    target: root.hostWidget
    function onSessionsChanged() { root.syncRows() }
  }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  Process {
    id: actionProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyAction(text)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(700))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.creating

      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveSelection(dy)
        if (dx !== 0) root.moveSelectedFavorite(dx)
      }
      onActivateRequested: root.activateSelected()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r" || text === "R") {
          if (root.hostWidget) root.hostWidget.refresh()
        } else if (text === "n" || text === "N") {
          root.startCreate()
        } else if (text === "f" || text === "F") {
          var session = root.selectedSession()
          if (session) root.toggleFavorite(String(session.name))
        }
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "Omamux"
          meta: (root.hostWidget ? root.hostWidget.hostName : "local") + " · local tmux"
          detail: root.rows.length + " session" + (root.rows.length === 1 ? "" : "s")
          foreground: root.foreground
          fontFamily: root.fontFamily

          iconComponent: Component {
            Text {
              text: ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }

          trailingControl: Component {
            Row {
              spacing: Style.space(4)

              PanelActionButton {
                iconText: "󰑐"
                tooltipText: "Refresh sessions (r)"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !root.actionBusy
                onClicked: if (root.hostWidget) root.hostWidget.refresh()
              }

              PanelActionButton {
                iconText: "+"
                tooltipText: "New session (n)"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !!root.hostWidget && root.hostWidget.tmuxAvailable && !root.actionBusy
                onClicked: root.startCreate()
              }
            }
          }
        }

        BorderSurface {
          visible: root.actionError !== "" || (!!root.hostWidget && root.hostWidget.errorText !== "")
          width: parent.width
          implicitHeight: errorLabel.implicitHeight + Style.space(20)
          color: Util.alpha(root.urgent, 0.10)
          borderSpec: Border.flat(Util.alpha(root.urgent, 0.45), 1)
          radius: Style.cornerRadius

          Text {
            id: errorLabel
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            text: root.actionError !== ""
              ? root.actionError
              : (root.hostWidget ? root.hostWidget.errorText : "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        BorderSurface {
          visible: root.creating
          width: parent.width
          implicitHeight: createColumn.implicitHeight + Style.space(20)
          color: Style.selectedFillFor(root.foreground, Color.accent)
          borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
          radius: Style.cornerRadius

          Column {
            id: createColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "NEW SESSION"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              TextField {
                id: createField
                width: parent.width - createButton.width - cancelButton.width - parent.spacing * 2
                text: root.createText
                placeholderText: "main"
                foreground: root.foreground
                onTextChanged: root.createText = text
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    root.cancelCreate()
                    event.accepted = true
                  } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.createSession()
                    event.accepted = true
                  }
                }
              }

              Button {
                id: createButton
                text: "Create"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: Model.validSessionName(root.createText) && !root.actionBusy
                onClicked: root.createSession()
              }

              Button {
                id: cancelButton
                text: "Cancel"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !root.actionBusy
                onClicked: root.cancelCreate()
              }
            }

            Text {
              width: parent.width
              text: Model.validationError(root.createText) !== ""
                ? Model.validationError(root.createText)
                : "tmux -u attach-session -t =" + Model.normalizedSessionName(root.createText)
              color: Model.validationError(root.createText) !== "" ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }

        PanelSeparator {
          foreground: root.foreground
        }

        PanelSectionHeader {
          width: parent.width
          text: "SESSIONS"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Item {
          width: parent.width
          implicitHeight: root.listHeight
          height: implicitHeight

          ListView {
            id: sessionList
            anchors.fill: parent
            model: root.rows
            spacing: Style.space(6)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: root.selectedIndex
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: CursorSurface {
              id: sessionRow
              required property var modelData
              required property int index
              property real lastDragY: 0

              width: sessionList.width
              height: Style.space(62)
              hasCursor: root.cursorActive && index === root.selectedIndex
              bordered: true
              foreground: root.foreground
              accent: Color.accent
              z: dragHandler.active ? 2 : 0
              transform: Translate { y: dragHandler.active ? dragHandler.translation.y : 0 }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                enabled: !root.actionBusy
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectRow(sessionRow.index)
                onClicked: root.attachSession(String(sessionRow.modelData.name))
              }

              DragHandler {
                id: dragHandler
                target: null
                enabled: sessionRow.modelData.favorite === true && root.favoriteCount > 1 && !root.actionBusy
                xAxis.enabled: false
                onTranslationChanged: sessionRow.lastDragY = translation.y
                onActiveChanged: {
                  if (!active && Math.abs(sessionRow.lastDragY) > Style.space(20)) {
                    var step = sessionRow.height + sessionList.spacing
                    root.moveFavorite(sessionRow.index, sessionRow.index + Math.round(sessionRow.lastDragY / step))
                  }
                  if (!active) sessionRow.lastDragY = 0
                }
              }

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(10)

                Rectangle {
                  width: Style.space(8)
                  height: width
                  radius: width / 2
                  color: Number(sessionRow.modelData.attachedClients || 0) > 0
                    ? root.urgent
                    : root.availableColor
                  anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                  width: Math.max(0, parent.width - parent.children[0].width - trailing.width - parent.spacing * 2)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Text {
                    width: parent.width
                    text: String(sessionRow.modelData.name || "")
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    text: Model.sessionMeta(sessionRow.modelData, root.nowMs)
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                Row {
                  id: trailing
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(1)

                  Text {
                    visible: sessionRow.modelData.favorite === true && root.favoriteCount > 1
                    text: "≡"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.icon
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  PanelActionButton {
                    visible: sessionRow.modelData.favorite === true && root.favoriteCount > 1
                    iconText: "↑"
                    tooltipText: "Move favorite up (h)"
                    foreground: root.dim
                    hoverColor: root.foreground
                    fontFamily: root.fontFamily
                    enabled: sessionRow.index > 0 && !root.actionBusy
                    onClicked: root.moveFavorite(sessionRow.index, sessionRow.index - 1)
                  }

                  PanelActionButton {
                    visible: sessionRow.modelData.favorite === true && root.favoriteCount > 1
                    iconText: "↓"
                    tooltipText: "Move favorite down (l)"
                    foreground: root.dim
                    hoverColor: root.foreground
                    fontFamily: root.fontFamily
                    enabled: sessionRow.index < root.favoriteCount - 1 && !root.actionBusy
                    onClicked: root.moveFavorite(sessionRow.index, sessionRow.index + 1)
                  }

                  PanelActionButton {
                    iconText: sessionRow.modelData.favorite === true ? "★" : "☆"
                    tooltipText: sessionRow.modelData.favorite === true
                      ? "Remove favorite (f)"
                      : "Add favorite (f)"
                    foreground: sessionRow.modelData.favorite === true ? root.foreground : root.dim
                    hoverColor: root.foreground
                    fontFamily: root.fontFamily
                    enabled: !root.actionBusy
                    onClicked: root.toggleFavorite(String(sessionRow.modelData.name))
                  }

                  Text {
                    text: "›"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.icon
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }
              }
            }
          }

          Column {
            visible: root.rows.length === 0
            anchors.centerIn: parent
            width: parent.width - Style.space(40)
            spacing: Style.space(8)

            Text {
              width: parent.width
              text: root.hostWidget && root.hostWidget.loading
                ? "Loading tmux sessions…"
                : (root.hostWidget && !root.hostWidget.tmuxAvailable
                  ? "tmux is not installed"
                  : "No tmux sessions are running")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
            }

            Text {
              width: parent.width
              text: root.hostWidget && !root.hostWidget.tmuxAvailable
                ? "Install tmux, then refresh Omamux."
                : "Create one here and Omamux will open it in your configured terminal."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }
          }
        }

        Text {
          visible: root.rows.length > 0
          width: parent.width
          text: "↑↓ select · Enter attach · f favorite · h/l reorder · n new · r refresh"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }
      }
    }
  }
}

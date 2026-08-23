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
  property bool reorderAnimating: false
  property int reorderFrom: -1
  property int reorderTo: -1
  property var reorderedRows: []
  property var reorderAction: []
  property bool dragReordering: false
  property int dragFrom: -1
  property int dragTo: -1
  property real dragOffset: 0
  property bool favoriteSyncPending: false
  property var expectedFavoriteOrder: []

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Color.muted
  readonly property color availableColor: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool actionBusy: actionProcess.running
  readonly property bool interactionBusy: actionBusy || reorderAnimating || dragReordering || favoriteSyncPending
  readonly property int reorderDuration: 180
  readonly property int dragDisplaceDuration: 110
  readonly property int favoriteCount: {
    var count = 0
    for (var i = 0; i < rows.length; i++)
      if (rows[i].favorite === true) count++
    return count
  }
  readonly property int sessionRowHeight: Style.space(44)
  readonly property int sessionRowSpacing: Style.space(4)
  readonly property int listHeight: rows.length > 0
    ? Math.min(Style.space(360), rows.length * sessionRowHeight + Math.max(0, rows.length - 1) * sessionRowSpacing)
    : Style.space(112)

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
    if (rows.length === 0 || interactionBusy) return
    cursorActive = true
    selectedIndex = Model.clampedIndex(selectedIndex + delta, rows.length)
    revealSelection()
  }

  function activateSelected() {
    if (interactionBusy) return
    var session = selectedSession()
    if (session) attachSession(String(session.name))
  }

  function selectRow(index) {
    if (interactionBusy) return
    cursorActive = true
    selectedIndex = Model.clampedIndex(index, rows.length)
  }

  function runAction(args, shouldClose) {
    if (interactionBusy || !hostWidget) return false
    actionError = ""
    actionKind = String(args[0] || "action")
    closeAfterAction = shouldClose === true
    actionProcess.command = [hostWidget.backendPath].concat(args)
    actionProcess.running = true
    return true
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
      favoriteSyncTimer.stop()
      favoriteSyncPending = false
      expectedFavoriteOrder = []
      actionError = result.error
      syncRows()
    }
  }

  function attachSession(name) {
    runAction(["attach", name], true)
  }

  function toggleFavorite(name) {
    if (interactionBusy) return

    var index = -1
    for (var i = 0; i < rows.length; i++) {
      if (String(rows[i].name || "") === name) { index = i; break }
    }
    if (index < 0) return

    var toggled = Model.toggledFavoriteRows(rows, index)
    animateReorder(index, toggled.targetIndex, toggled.rows, ["favorite", "toggle", name])
  }

  function favoriteNames(values) {
    return Model.favoriteOrder(values)
  }

  function moveFavorite(from, to) {
    if (interactionBusy || from < 0 || from >= favoriteCount) return
    var target = Math.max(0, Math.min(favoriteCount - 1, to))
    if (from === target) return

    var next = rows.slice(0)
    var moved = next.splice(from, 1)[0]
    next.splice(target, 0, moved)
    animateReorder(from, target, next, ["favorite", "reorder"].concat(favoriteNames(next)))
  }

  function animatedRowOffset(index) {
    var step = sessionRowHeight + sessionRowSpacing
    if (dragReordering && dragFrom >= 0 && dragTo >= 0)
      return Model.reorderOffset(index, dragFrom, dragTo, step)
    if (reorderAnimating && reorderFrom >= 0 && reorderTo >= 0)
      return Model.reorderOffset(index, reorderFrom, reorderTo, step)
    return 0
  }

  function animateReorder(from, to, nextRows, actionArgs) {
    if (interactionBusy || from < 0 || to < 0) return

    reorderedRows = nextRows
    reorderAction = actionArgs
    cursorActive = true

    if (from === to) {
      reorderFrom = from
      reorderTo = to
      finishReorder()
      return
    }

    reorderAnimating = true
    reorderFrom = from
    reorderTo = to
    reorderTimer.restart()
  }

  function finishReorder() {
    var target = reorderTo
    var nextRows = reorderedRows
    var actionArgs = reorderAction

    reorderAnimating = false
    reorderFrom = -1
    reorderTo = -1
    reorderedRows = []
    reorderAction = []

    commitReorderedRows(target, nextRows, actionArgs)
  }

  function beginDrag(index) {
    if (actionBusy || reorderAnimating || favoriteSyncPending
        || index < 0 || index >= favoriteCount) return false
    dragFrom = index
    dragTo = index
    dragOffset = 0
    dragReordering = true
    cursorActive = true
    selectedIndex = index
    return true
  }

  function updateDrag(offset) {
    if (!dragReordering) return
    dragOffset = Number(offset || 0)
    var step = sessionRowHeight + sessionRowSpacing
    var target = dragFrom + Math.round(dragOffset / step)
    dragTo = Math.max(0, Math.min(favoriteCount - 1, target))
  }

  function finishDrag() {
    if (!dragReordering) return
    var from = dragFrom
    var target = dragTo

    dragReordering = false
    dragFrom = -1
    dragTo = -1
    dragOffset = 0

    if (from === target) return
    var nextRows = rows.slice(0)
    var moved = nextRows.splice(from, 1)[0]
    nextRows.splice(target, 0, moved)
    commitReorderedRows(target, nextRows,
      ["favorite", "reorder"].concat(favoriteNames(nextRows)))
  }

  function commitReorderedRows(target, nextRows, actionArgs) {
    rows = nextRows
    selectedIndex = target
    cursorActive = true
    revealSelection()
    expectedFavoriteOrder = favoriteNames(nextRows)
    if (runAction(actionArgs, false)) {
      favoriteSyncPending = true
      favoriteSyncTimer.restart()
    } else {
      expectedFavoriteOrder = []
    }
  }

  function favoriteOrderMatches(values) {
    var actual = favoriteNames(values)
    if (actual.length !== expectedFavoriteOrder.length) return false
    for (var i = 0; i < actual.length; i++)
      if (actual[i] !== expectedFavoriteOrder[i]) return false
    return true
  }

  function moveSelectedFavorite(delta) {
    var session = selectedSession()
    if (!session || session.favorite !== true) return
    moveFavorite(selectedIndex, selectedIndex + delta)
  }

  function startCreate() {
    if (interactionBusy || !hostWidget || !hostWidget.tmuxAvailable) return
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
    function onSessionsChanged() {
      if (root.reorderAnimating || root.dragReordering) return
      if (root.favoriteSyncPending) {
        if (!root.favoriteOrderMatches(root.hostWidget.sessions)) return
        favoriteSyncTimer.stop()
        root.favoriteSyncPending = false
        root.expectedFavoriteOrder = []
      }
      root.syncRows()
    }
  }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  Timer {
    id: reorderTimer
    interval: root.reorderDuration
    onTriggered: root.finishReorder()
  }

  Timer {
    id: favoriteSyncTimer
    interval: 5000
    onTriggered: {
      root.favoriteSyncPending = false
      root.expectedFavoriteOrder = []
      root.syncRows()
      if (root.hostWidget) root.hostWidget.refresh()
    }
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
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(560))

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
          foreground: root.foreground
          fontFamily: root.fontFamily

          iconComponent: Component {
            OmamuxIcon {
              width: Style.font.display
              height: width
              paneColor: root.dim
              accentColor: root.availableColor
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
                onClicked: if (root.hostWidget) root.hostWidget.refresh()
              }

              PanelActionButton {
                iconText: "+"
                tooltipText: "New session (n)"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !!root.hostWidget && root.hostWidget.tmuxAvailable
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
                enabled: Model.validSessionName(root.createText) && !root.interactionBusy
                onClicked: root.createSession()
              }

              Button {
                id: cancelButton
                text: "Cancel"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !root.interactionBusy
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

        Item {
          width: parent.width
          implicitHeight: Math.max(sessionsHeader.implicitHeight, sessionCount.implicitHeight)

          PanelSectionHeader {
            id: sessionsHeader
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "SESSIONS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            id: sessionCount
            anchors.right: parent.right
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            text: root.rows.length + " session" + (root.rows.length === 1 ? "" : "s")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        Item {
          width: parent.width
          implicitHeight: root.listHeight
          height: implicitHeight

          ListView {
            id: sessionList
            anchors.fill: parent
            model: root.rows
            spacing: root.sessionRowSpacing
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: root.selectedIndex
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            CursorSurface {
              id: sessionCursorSurface
              parent: sessionList.contentItem
              width: sessionList.width
              height: root.sessionRowHeight
              hasCursor: root.cursorActive
                && root.selectedIndex >= 0
                && root.selectedIndex < root.rows.length
              foreground: root.foreground
              accent: Color.accent
              z: 0
              y: {
                var step = root.sessionRowHeight + root.sessionRowSpacing
                if (root.dragReordering && root.dragFrom >= 0)
                  return root.dragFrom * step + root.dragOffset
                if (root.reorderAnimating && root.reorderFrom >= 0 && root.reorderTo >= 0)
                  return root.reorderTo * step
                return Math.max(0, root.selectedIndex) * step
              }

              Behavior on y {
                enabled: root.reorderAnimating
                NumberAnimation {
                  duration: root.reorderDuration
                  easing.type: Easing.OutCubic
                }
              }
            }

            delegate: CursorSurface {
              id: sessionRow
              required property var modelData
              required property int index
              readonly property bool canReorder: modelData.favorite === true && root.favoriteCount > 1
              readonly property bool hasSelectionCursor: root.cursorActive && index === root.selectedIndex
              readonly property bool showReorder: canReorder && hasSelectionCursor
              readonly property bool togglingFavorite: root.reorderAnimating
                && index === root.reorderFrom
                && root.reorderAction.length > 1
                && root.reorderAction[0] === "favorite"
                && root.reorderAction[1] === "toggle"
              readonly property bool displayFavorite: togglingFavorite
                ? modelData.favorite !== true
                : modelData.favorite === true
              property real animatedOffset: root.animatedRowOffset(index)

              width: sessionList.width
              height: root.sessionRowHeight
              hasCursor: false
              foreground: root.foreground
              accent: Color.accent
              z: dragHandler.active
                || (root.reorderAnimating && index === root.reorderFrom)
                ? 2 : 1
              transform: Translate {
                y: dragHandler.active ? dragHandler.translation.y : sessionRow.animatedOffset
              }

              Behavior on animatedOffset {
                enabled: (root.reorderAnimating || root.dragReordering) && !dragHandler.active
                NumberAnimation {
                  duration: root.dragReordering
                    ? root.dragDisplaceDuration
                    : root.reorderDuration
                  easing.type: Easing.OutCubic
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                enabled: !root.interactionBusy
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectRow(sessionRow.index)
                onClicked: root.attachSession(String(sessionRow.modelData.name))
              }

              DragHandler {
                id: dragHandler
                target: null
                enabled: sessionRow.modelData.favorite === true
                  && root.favoriteCount > 1
                  && !root.actionBusy
                  && !root.reorderAnimating
                  && !root.favoriteSyncPending
                xAxis.enabled: false
                onTranslationChanged: root.updateDrag(translation.y)
                onActiveChanged: {
                  if (active) {
                    root.beginDrag(sessionRow.index)
                  } else {
                    root.finishDrag()
                  }
                }
              }

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(4)
                spacing: Style.space(8)

                Rectangle {
                  id: statusDot
                  width: Style.space(7)
                  height: width
                  radius: width / 2
                  color: Number(sessionRow.modelData.attachedClients || 0) > 0
                    ? root.urgent
                    : root.availableColor
                  anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                  width: Math.max(0, parent.width - statusDot.width - trailing.width - parent.spacing * 2)
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
                    visible: sessionRow.showReorder
                    text: "≡"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.icon
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  PanelActionButton {
                    iconText: sessionRow.displayFavorite ? "★" : "☆"
                    tooltipText: sessionRow.displayFavorite
                      ? "Remove favorite (f)"
                      : "Add favorite (f)"
                    foreground: sessionRow.displayFavorite ? root.foreground : root.dim
                    hoverColor: root.foreground
                    fontFamily: root.fontFamily
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
          text: "Enter attach · f star · h/l order · n new · r refresh"
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

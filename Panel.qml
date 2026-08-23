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
  property bool renaming: false
  property string renameOriginalName: ""
  property string editText: ""
  property string preferredSelectionName: ""
  property bool showingDetail: false
  property string detailSessionName: ""
  property var detailWindows: []
  property int selectedDetailIndex: -1
  property bool detailCursorActive: false
  property string detailError: ""
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
  property string interactionHint: ""
  property string pendingAttachTargetKey: ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Color.muted
  readonly property color iconAccentColor: Color.accent
  property color attachedSessionColor: "#7aa2f7"
  property color unattachedSessionColor: "#e0af68"
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool actionBusy: actionProcess.running
  readonly property bool detailLoading: detailProcess.running
  readonly property bool editingName: creating || renaming
  readonly property bool interactionBusy: actionBusy || reorderAnimating || dragReordering || favoriteSyncPending
  readonly property int reorderDuration: 180
  readonly property int dragDisplaceDuration: 110
  readonly property int favoriteCount: {
    var count = 0
    for (var i = 0; i < rows.length; i++)
      if (rows[i].favorite === true) count++
    return count
  }
  readonly property int detailPaneCount: {
    var count = 0
    for (var i = 0; i < detailWindows.length; i++) {
      var panes = Array.isArray(detailWindows[i].panes) ? detailWindows[i].panes : []
      count += panes.length
    }
    return count
  }
  readonly property var detailRows: Model.detailRows(detailWindows)
  readonly property int detailWindowRowHeight: Style.space(34)
  readonly property int detailPaneRowHeight: Style.space(42)
  readonly property int detailRowSpacing: Style.space(2)
  readonly property int detailListHeight: {
    var height = Math.max(0, detailRows.length - 1) * detailRowSpacing
    for (var i = 0; i < detailRows.length; i++)
      height += detailRows[i].kind === "window" ? detailWindowRowHeight : detailPaneRowHeight
    return Math.min(Style.space(360), height)
  }
  readonly property int sessionRowHeight: Style.space(44)
  readonly property int sessionRowSpacing: Style.space(4)
  readonly property int listHeight: rows.length > 0
    ? Math.min(Style.space(360), rows.length * sessionRowHeight
      + Math.max(0, rows.length - 1) * sessionRowSpacing)
    : Style.space(112)

  function open() {
    root.controller.show()
    if (hostWidget) hostWidget.refresh()
  }

  function close() {
    cancelNameEdit()
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
    var previousName = preferredSelectionName !== ""
      ? preferredSelectionName
      : (selectedSession() ? String(selectedSession().name) : "")
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
    if (preferredSelectionName === previousName) preferredSelectionName = ""
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
    if (showingDetail || rows.length === 0 || interactionBusy) return
    selectedIndex = Model.movedSelection(selectedIndex, rows.length, delta, cursorActive)
    cursorActive = true
    revealSelection()
  }

  function moveDetailSelection(delta) {
    if (!showingDetail || detailRows.length === 0 || interactionBusy) return
    clearAttachConfirmation()
    selectedDetailIndex = Model.movedSelection(
      selectedDetailIndex, detailRows.length, delta, detailCursorActive)
    detailCursorActive = true
    revealDetailSelection()
  }

  function revealDetailSelection() {
    if (selectedDetailIndex >= 0 && detailList)
      Qt.callLater(function() {
        detailList.positionViewAtIndex(selectedDetailIndex, ListView.Contain)
      })
  }

  function selectDetailRow(index) {
    if (!showingDetail || interactionBusy) return
    if (selectedDetailIndex !== index) clearAttachConfirmation()
    detailCursorActive = true
    selectedDetailIndex = Model.clampedIndex(index, detailRows.length)
  }

  function selectedDetailRow() {
    if (selectedDetailIndex < 0 || selectedDetailIndex >= detailRows.length) return null
    return detailRows[selectedDetailIndex]
  }

  function detailSession() {
    for (var i = 0; i < rows.length; i++)
      if (String(rows[i].name || "") === detailSessionName) return rows[i]
    return null
  }

  function detailTargetKey(item) {
    if (!item) return ""
    var windowIndex = Number((item.window || ({})).index)
    if (item.kind === "pane")
      return "pane:" + windowIndex + ":" + String((item.pane || ({})).id || "")
    return "window:" + windowIndex
  }

  function detailTargetChangesView(item) {
    if (!item) return false
    var window = item.window || ({})
    if (item.kind === "pane")
      return window.active !== true || (item.pane || ({})).active !== true
    return window.active !== true
  }

  function clearAttachConfirmation() {
    pendingAttachTargetKey = ""
    interactionHint = ""
    interactionHintTimer.stop()
  }

  function activateDetailSelection() {
    var item = selectedDetailRow()
    if (!item || detailSessionName === "") return
    var session = detailSession()
    var clients = Number(session && session.attachedClients || 0)
    var targetKey = detailTargetKey(item)
    if (clients > 0 && detailTargetChangesView(item)
        && pendingAttachTargetKey !== targetKey) {
      pendingAttachTargetKey = targetKey
      interactionHint = clients + " client" + (clients === 1 ? "" : "s")
        + " attached · Enter again to switch their view"
      interactionHintTimer.restart()
      return
    }

    clearAttachConfirmation()
    var windowIndex = String(Number((item.window || ({})).index))
    var paneId = item.kind === "pane" ? String((item.pane || ({})).id || "") : ""
    attachSession(detailSessionName, windowIndex, paneId)
  }

  function activateSelected() {
    if (interactionBusy) return
    if (showingDetail) {
      activateDetailSelection()
      return
    }
    var session = selectedSession()
    if (session) attachSession(String(session.name))
  }

  function selectRow(index) {
    if (showingDetail || interactionBusy) return
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
    var completedAction = actionKind
    closeAfterAction = false
    actionKind = ""

    if (result.ok) {
      actionError = ""
      if (completedAction === "rename") {
        preferredSelectionName = String(result.session || "")
        cancelNameEdit()
      }
      if (hostWidget) hostWidget.refresh()
      if (shouldClose) close()
    } else {
      favoriteSyncTimer.stop()
      favoriteSyncPending = false
      expectedFavoriteOrder = []
      preferredSelectionName = ""
      actionError = result.error
      syncRows()
    }
  }

  function attachSession(name, windowIndex, paneId) {
    var args = ["attach", name]
    if (windowIndex !== undefined && String(windowIndex) !== "")
      args.push(String(windowIndex))
    if (paneId !== undefined && String(paneId) !== "")
      args.push(String(paneId))
    runAction(args, true)
  }

  function openSessionDetail(name) {
    if (interactionBusy || detailLoading || !hostWidget || name === "") return
    cancelNameEdit()
    showingDetail = true
    detailSessionName = name
    detailWindows = []
    selectedDetailIndex = -1
    detailCursorActive = false
    clearAttachConfirmation()
    detailError = ""
    detailProcess.command = [hostWidget.backendPath, "detail", name]
    detailProcess.running = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function openSelectedDetail() {
    if (showingDetail) return
    var session = selectedSession()
    if (session) openSessionDetail(String(session.name || ""))
  }

  function closeSessionDetail() {
    if (!showingDetail) return
    showingDetail = false
    detailSessionName = ""
    detailWindows = []
    selectedDetailIndex = -1
    detailCursorActive = false
    clearAttachConfirmation()
    detailError = ""
    revealSelection()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function applyDetail(raw) {
    var result = Model.parseDetailPayload(raw)
    if (result.ok) {
      detailSessionName = result.session
      detailWindows = result.windows
      selectedDetailIndex = detailRows.length > 0 ? 0 : -1
      detailCursorActive = false
      clearAttachConfirmation()
      detailError = ""
    } else {
      detailWindows = []
      selectedDetailIndex = -1
      detailCursorActive = false
      clearAttachConfirmation()
      detailError = result.error
    }
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

  function sessionItemY(index) {
    if (index < 0 || !sessionList) return 0
    var item = sessionList.itemAtIndex(index)
    if (item) return item.y
    return index * (sessionRowHeight + sessionRowSpacing)
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
    if (!session) return
    if (session.favorite !== true) {
      showInteractionHint("Only favorite sessions can be reordered")
      return
    }
    moveFavorite(selectedIndex, selectedIndex + delta)
  }

  function showInteractionHint(message) {
    pendingAttachTargetKey = ""
    interactionHint = message
    interactionHintTimer.restart()
  }

  function loadSessionColors(raw) {
    attachedSessionColor = Model.themeColor(raw, "blue", "#7aa2f7")
    unattachedSessionColor = Model.themeColor(raw, "yellow", "#e0af68")
  }

  function startCreate() {
    if (showingDetail || interactionBusy || !hostWidget || !hostWidget.tmuxAvailable) return
    creating = true
    renaming = false
    renameOriginalName = ""
    actionError = ""
    editText = Model.suggestSessionName(rows)
    Qt.callLater(function() {
      nameField.selectAll()
      nameField.forceActiveFocus()
    })
  }

  function startRename() {
    if (showingDetail || interactionBusy || !hostWidget || !hostWidget.tmuxAvailable) return
    var session = selectedSession()
    if (!session) return
    creating = false
    renaming = true
    renameOriginalName = String(session.name || "")
    editText = renameOriginalName
    actionError = ""
    Qt.callLater(function() {
      nameField.selectAll()
      nameField.forceActiveFocus()
    })
  }

  function cancelNameEdit() {
    creating = false
    renaming = false
    renameOriginalName = ""
    editText = ""
    if (opened) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function submitNameEdit() {
    if (renaming) renameSession()
    else createSession()
  }

  function createSession() {
    var name = Model.normalizedSessionName(editText)
    var error = Model.validationError(name)
    if (error !== "") {
      actionError = error
      return
    }
    runAction(["create", name], true)
  }

  function renameSession() {
    var name = Model.normalizedSessionName(editText)
    var error = Model.validationError(name)
    if (error !== "") {
      actionError = error
      return
    }
    if (name === renameOriginalName) {
      cancelNameEdit()
      return
    }
    runAction(["rename", renameOriginalName, name], false)
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
      renaming = false
      renameOriginalName = ""
      editText = ""
      actionError = ""
      interactionHint = ""
      pendingAttachTargetKey = ""
      showingDetail = false
      detailSessionName = ""
      detailWindows = []
      selectedDetailIndex = -1
      detailCursorActive = false
      detailError = ""
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

  Timer {
    id: interactionHintTimer
    interval: 2200
    onTriggered: {
      root.interactionHint = ""
      root.pendingAttachTargetKey = ""
    }
  }

  FileView {
    path: Color.currentThemePath + "/colors.toml"
    watchChanges: true
    onLoaded: root.loadSessionColors(text())
    onFileChanged: reload()
  }

  Process {
    id: actionProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyAction(text)
    }
  }

  Process {
    id: detailProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyDetail(text)
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
      blocked: root.editingName

      onMoveRequested: function(dx, dy) {
        if (dy !== 0) {
          if (root.showingDetail) root.moveDetailSelection(dy)
          else root.moveSelection(dy)
        }
        if (dx > 0) root.openSelectedDetail()
        if (dx < 0) root.closeSessionDetail()
      }
      onActivateRequested: root.activateSelected()
      onCloseRequested: {
        if (root.showingDetail) root.closeSessionDetail()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "J") {
          if (!root.showingDetail) root.moveSelectedFavorite(1)
        } else if (text === "K") {
          if (!root.showingDetail) root.moveSelectedFavorite(-1)
        } else if (text === "r") {
          root.startRename()
        } else if (text === "R") {
          if (root.hostWidget) root.hostWidget.refresh()
        } else if (text === "C") {
          root.startCreate()
        } else if (text === "f" || text === "F") {
          if (root.showingDetail) return
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
          title: root.showingDetail ? root.detailSessionName : "Omamux"
          meta: root.showingDetail
            ? "SESSION DETAILS · LOCAL TMUX"
            : (root.hostWidget ? root.hostWidget.hostName : "local") + " · local tmux"
          foreground: root.foreground
          fontFamily: root.fontFamily

          iconComponent: Component {
            OmamuxIcon {
              width: Style.font.display
              height: width
              paneColor: root.dim
              accentColor: root.iconAccentColor
            }
          }

          trailingControl: Component {
            Row {
              spacing: Style.space(4)

              PanelActionButton {
                visible: root.showingDetail
                iconText: "‹"
                tooltipText: "Back to sessions (←)"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.closeSessionDetail()
              }

              PanelActionButton {
                visible: !root.showingDetail
                iconText: "󰑐"
                tooltipText: "Refresh sessions (Shift+R)"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: if (root.hostWidget) root.hostWidget.refresh()
              }

              PanelActionButton {
                visible: !root.showingDetail
                iconText: "+"
                tooltipText: "New session (Shift+C)"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !!root.hostWidget && root.hostWidget.tmuxAvailable
                onClicked: root.startCreate()
              }
            }
          }
        }

        BorderSurface {
          visible: root.actionError !== ""
            || root.detailError !== ""
            || (!!root.hostWidget && root.hostWidget.errorText !== "")
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
              : (root.detailError !== ""
                ? root.detailError
                : (root.hostWidget ? root.hostWidget.errorText : ""))
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        BorderSurface {
          visible: root.editingName
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
              text: root.renaming ? "RENAME SESSION" : "NEW SESSION"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              TextField {
                id: nameField
                width: parent.width - createButton.width - cancelButton.width - parent.spacing * 2
                text: root.editText
                placeholderText: "main"
                foreground: root.foreground
                onTextChanged: root.editText = text
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    root.cancelNameEdit()
                    event.accepted = true
                  } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.submitNameEdit()
                    event.accepted = true
                  }
                }
              }

              Button {
                id: createButton
                text: root.renaming ? "Rename" : "Create"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: Model.validSessionName(root.editText)
                  && (!root.renaming
                    || Model.normalizedSessionName(root.editText) !== root.renameOriginalName)
                  && !root.interactionBusy
                onClicked: root.submitNameEdit()
              }

              Button {
                id: cancelButton
                text: "Cancel"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !root.interactionBusy
                onClicked: root.cancelNameEdit()
              }
            }

            Text {
              width: parent.width
              text: Model.validationError(root.editText) !== ""
                ? Model.validationError(root.editText)
                : (root.renaming
                  ? "Rename " + root.renameOriginalName + " to " + Model.normalizedSessionName(root.editText)
                  : "tmux -u attach-session -t =" + Model.normalizedSessionName(root.editText))
              color: Model.validationError(root.editText) !== "" ? root.urgent : root.dim
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
          id: sessionsHeading
          visible: !root.showingDetail
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
          id: sessionsView
          visible: !root.showingDetail
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
                if (root.dragReordering && root.dragFrom >= 0)
                  return root.sessionItemY(root.dragFrom) + root.dragOffset
                if (root.reorderAnimating && root.reorderFrom >= 0 && root.reorderTo >= 0)
                  return root.sessionItemY(root.reorderTo)
                return root.sessionItemY(root.selectedIndex)
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
                    ? root.attachedSessionColor
                    : root.unattachedSessionColor
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

                  PanelActionButton {
                    iconText: "›"
                    tooltipText: "Session details (→)"
                    foreground: root.dim
                    hoverColor: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: root.openSessionDetail(String(sessionRow.modelData.name || ""))
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

        Column {
          visible: root.showingDetail
          width: parent.width
          spacing: Style.space(8)

          Item {
            width: parent.width
            implicitHeight: Math.max(detailHeading.implicitHeight, detailCount.implicitHeight)

            PanelSectionHeader {
              id: detailHeading
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "WINDOWS AND PANES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              id: detailCount
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: root.detailWindows.length + " window"
                + (root.detailWindows.length === 1 ? "" : "s")
                + " · " + root.detailPaneCount + " pane"
                + (root.detailPaneCount === 1 ? "" : "s")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          Item {
            visible: root.detailLoading || root.detailError !== "" || root.detailWindows.length === 0
            width: parent.width
            implicitHeight: Style.space(112)

            Text {
              anchors.centerIn: parent
              width: parent.width - Style.space(40)
              text: root.detailLoading
                ? "Loading session details…"
                : (root.detailError !== "" ? "Session details unavailable" : "No windows found")
              color: root.detailError !== "" ? root.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
            }
          }

          ListView {
            id: detailList
            visible: !root.detailLoading && root.detailError === "" && root.detailWindows.length > 0
            width: parent.width
            implicitHeight: root.detailListHeight
            height: implicitHeight
            model: root.detailRows
            spacing: root.detailRowSpacing
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: root.selectedDetailIndex
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: CursorSurface {
              id: detailTreeRow
              required property var modelData
              required property int index
              readonly property bool isWindow: modelData.kind === "window"
              readonly property var windowData: modelData.window || ({})
              readonly property var paneData: modelData.pane || ({})
              readonly property bool isActiveWindow: isWindow && windowData.active === true

              width: detailList.width
              height: isWindow ? root.detailWindowRowHeight : root.detailPaneRowHeight
              hasCursor: root.detailCursorActive && index === root.selectedDetailIndex
              current: isActiveWindow
              foreground: root.foreground
              accent: Color.accent

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                enabled: !root.interactionBusy
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectDetailRow(detailTreeRow.index)
                onClicked: root.selectDetailRow(detailTreeRow.index)
              }

              Row {
                anchors.fill: parent
                anchors.leftMargin: detailTreeRow.isWindow ? Style.space(6) : Style.space(18)
                anchors.rightMargin: Style.space(6)
                spacing: Style.space(7)

                Text {
                  id: treeBranch
                  width: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  text: detailTreeRow.isWindow
                    ? "▾"
                    : (detailTreeRow.modelData.lastPane === true ? "└" : "├")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  horizontalAlignment: Text.AlignHCenter
                }

                Column {
                  width: Math.max(0, parent.width - treeBranch.width
                    - activeDetailLabel.width - parent.spacing * 2)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(1)

                  Text {
                    width: parent.width
                    text: detailTreeRow.isWindow
                      ? String(detailTreeRow.windowData.index) + ": "
                        + String(detailTreeRow.windowData.name || "window")
                      : String(detailTreeRow.paneData.index) + " · "
                        + String(detailTreeRow.paneData.command || "pane")
                        + (String(detailTreeRow.paneData.title || "") !== ""
                          ? " · " + String(detailTreeRow.paneData.title)
                          : "")
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: detailTreeRow.isWindow
                    elide: Text.ElideRight
                  }

                  Text {
                    visible: !detailTreeRow.isWindow
                    width: parent.width
                    text: String(detailTreeRow.paneData.path || "")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideMiddle
                  }
                }

                Text {
                  id: activeDetailLabel
                  visible: detailTreeRow.isWindow
                  width: visible ? implicitWidth : 0
                  anchors.verticalCenter: parent.verticalCenter
                  text: detailTreeRow.isWindow
                    ? detailTreeRow.modelData.paneCount + " PANE"
                      + (detailTreeRow.modelData.paneCount === 1 ? "" : "S")
                      + (detailTreeRow.isActiveWindow ? " · ACTIVE" : "")
                    : ""
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }
          }
        }

        Text {
          visible: !root.showingDetail && root.rows.length > 0
          width: parent.width
          text: root.interactionHint !== ""
            ? root.interactionHint
            : "j/k move · J/K order · r rename · R refresh · C new · → details · Enter attach · f star"
          color: root.interactionHint !== "" ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }

        Text {
          visible: root.showingDetail
          width: parent.width
          text: root.interactionHint !== ""
            ? root.interactionHint
            : "j/k select · ← sessions · Enter open selection"
          color: root.interactionHint !== "" ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }
}

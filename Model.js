function parseListPayload(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: false, error: "Omamux returned no data", sessions: [] }

  try {
    var payload = JSON.parse(text)
    if (!payload || typeof payload !== "object")
      return { ok: false, error: "Omamux returned invalid data", sessions: [] }

    if (payload.ok !== true)
      return { ok: false, error: String(payload.error || "Unable to read tmux sessions"), sessions: [] }

    return {
      ok: true,
      error: String(payload.error || ""),
      host: payload.host || { id: "local", name: "local" },
      tmux: payload.tmux || { available: false, version: "" },
      sessions: Array.isArray(payload.sessions) ? payload.sessions : []
    }
  } catch (e) {
    return { ok: false, error: "Unable to parse Omamux data", sessions: [] }
  }
}

function parseActionPayload(raw, fallbackError) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: false, error: fallbackError || "Omamux command failed" }

  try {
    var payload = JSON.parse(text)
    if (payload && payload.ok === true) return payload
    return { ok: false, error: String(payload && payload.error || fallbackError || "Omamux command failed") }
  } catch (e) {
    return { ok: false, error: fallbackError || "Unable to parse Omamux response" }
  }
}

function parseDetailPayload(raw) {
  var text = String(raw || "").trim()
  if (text === "")
    return { ok: false, error: "Omamux returned no session details", session: "", windows: [] }

  try {
    var payload = JSON.parse(text)
    if (!payload || payload.ok !== true)
      return {
        ok: false,
        error: String(payload && payload.error || "Unable to inspect tmux session"),
        session: "",
        windows: []
      }

    return {
      ok: true,
      error: "",
      session: String(payload.session || ""),
      windows: Array.isArray(payload.windows) ? payload.windows : []
    }
  } catch (e) {
    return { ok: false, error: "Unable to parse Omamux session details", session: "", windows: [] }
  }
}

function detailRows(windows) {
  var values = Array.isArray(windows) ? windows : []
  var rows = []
  for (var i = 0; i < values.length; i++) {
    var window = values[i] || ({})
    var panes = Array.isArray(window.panes) ? window.panes : []
    rows.push({ kind: "window", window: window, paneCount: panes.length })
    for (var j = 0; j < panes.length; j++) {
      rows.push({
        kind: "pane",
        window: window,
        pane: panes[j] || ({}),
        lastPane: j === panes.length - 1
      })
    }
  }
  return rows
}

function validationError(value) {
  var name = String(value || "").trim()
  if (name === "") return "Enter a session name"
  if (name.indexOf(".") !== -1 || name.indexOf(":") !== -1)
    return "Session names cannot contain . or :"
  if (/[\u0000-\u001f\u007f]/.test(name))
    return "Session names cannot contain control characters"
  return ""
}

function validSessionName(value) {
  return validationError(value) === ""
}

function normalizedSessionName(value) {
  return String(value || "").trim()
}

function themeColor(raw, name, fallback) {
  var key = String(name || "").replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
  var match = String(raw || "").match(new RegExp("^\\s*" + key
    + "\\s*=\\s*[\\\"']?(#[0-9A-Fa-f]{6})", "m"))
  return match ? match[1] : fallback
}

function suggestSessionName(sessions) {
  var taken = ({})
  var rows = Array.isArray(sessions) ? sessions : []
  for (var i = 0; i < rows.length; i++) taken[String(rows[i].name || "")] = true
  if (!taken.main) return "main"

  var suffix = 2
  while (taken["main-" + suffix]) suffix++
  return "main-" + suffix
}

function plural(value, singular) {
  var count = Number(value || 0)
  return count + " " + singular + (count === 1 ? "" : "s")
}

function formatAge(createdAt, nowMs) {
  var createdMs = Number(createdAt || 0) * 1000
  var currentMs = Number(nowMs || Date.now())
  if (!(createdMs > 0) || createdMs > currentMs) return "age unknown"

  var minutes = Math.floor((currentMs - createdMs) / 60000)
  if (minutes < 1) return "<1m old"
  if (minutes < 60) return minutes + "m old"

  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h old"

  return Math.floor(hours / 24) + "d old"
}

function clientLabel(attachedClients) {
  var count = Number(attachedClients || 0)
  if (count === 0) return ""
  return plural(count, "client")
}

function workspaceLabel(session) {
  var workspace = session && session.desktop && session.desktop.workspace
  if (!workspace || workspace.id === undefined || workspace.id === null) return ""
  var id = Number(workspace.id)
  return isFinite(id) && id >= 0 ? "ws " + id : ""
}

function sessionMeta(session, nowMs) {
  if (!session) return ""
  var meta = plural(session.windows, "window")
    + " · " + formatAge(session.createdAt, nowMs)
  var clients = clientLabel(session.attachedClients)
  var workspace = workspaceLabel(session)
  if (clients !== "") meta += " · " + clients
  if (workspace !== "") meta += " · " + workspace
  return meta
}

function clampedIndex(index, count) {
  var length = Math.max(0, Number(count || 0))
  if (length === 0) return -1
  return Math.max(0, Math.min(length - 1, Number(index || 0)))
}

function movedSelection(index, count, delta, cursorActive) {
  var length = Math.max(0, Number(count || 0))
  if (length === 0) return -1
  if (cursorActive !== true) return Number(delta || 0) < 0 ? length - 1 : 0
  return clampedIndex(Number(index || 0) + Number(delta || 0), length)
}

function favoriteOrder(sessions) {
  var rows = Array.isArray(sessions) ? sessions : []
  var names = []
  for (var i = 0; i < rows.length; i++)
    if (rows[i].favorite === true) names.push(String(rows[i].name || ""))
  return names
}

function toggledFavoriteRows(sessions, index) {
  var rows = Array.isArray(sessions) ? sessions.slice(0) : []
  var source = clampedIndex(index, rows.length)
  if (source < 0) return { rows: rows, targetIndex: -1, favorite: false }

  var original = rows[source] || ({})
  var session = ({})
  for (var key in original) session[key] = original[key]

  rows.splice(source, 1)
  if (original.favorite === true) {
    session.favorite = false
    session.starredAt = 0

    var target = 0
    while (target < rows.length && rows[target].favorite === true) target++
    var nativeOrder = Number(session.nativeOrder)
    if (isFinite(nativeOrder)) {
      while (target < rows.length
          && rows[target].favorite !== true
          && isFinite(Number(rows[target].nativeOrder))
          && Number(rows[target].nativeOrder) < nativeOrder)
        target++
    }
    rows.splice(target, 0, session)
    return { rows: rows, targetIndex: target, favorite: false }
  }

  session.favorite = true
  rows.unshift(session)
  return { rows: rows, targetIndex: 0, favorite: true }
}

function reorderOffset(index, from, to, step) {
  var row = Number(index)
  var source = Number(from)
  var target = Number(to)
  var distance = Number(step)
  if (source < 0 || target < 0 || !(distance > 0)) return 0
  if (row === source) return (target - source) * distance
  if (source < target && row > source && row <= target) return -distance
  if (source > target && row >= target && row < source) return distance
  return 0
}

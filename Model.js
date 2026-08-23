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
  if (count === 0) return "available"
  return plural(count, "client")
}

function sessionMeta(session, nowMs) {
  if (!session) return ""
  return plural(session.windows, "window")
    + " · " + formatAge(session.createdAt, nowMs)
    + " · " + clientLabel(session.attachedClients)
}

function clampedIndex(index, count) {
  var length = Math.max(0, Number(count || 0))
  if (length === 0) return -1
  return Math.max(0, Math.min(length - 1, Number(index || 0)))
}

function favoriteOrder(sessions) {
  var rows = Array.isArray(sessions) ? sessions : []
  var names = []
  for (var i = 0; i < rows.length; i++)
    if (rows[i].favorite === true) names.push(String(rows[i].name || ""))
  return names
}

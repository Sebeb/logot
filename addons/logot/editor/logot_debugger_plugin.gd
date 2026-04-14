@tool
extends EditorDebuggerPlugin

## Debugger plugin for Logot that detects and communicates with running game instances.
## Receives log messages from the game via EngineDebugger and forwards them to the editor panel.

signal instance_started(session_id: int)
signal instance_stopped(session_id: int)
signal log_received(session_id: int, entry_data: Dictionary)
signal channel_discovered(session_id: int, channel: String)
signal logs_cleared(session_id: int)
signal restart_requested(session_id: int)

# Track active sessions
var _active_sessions: Dictionary = {}  # {session_id: {connected: bool, name: String}}

const MESSAGE_PREFIX := "logot"


func _has_capture(prefix: String) -> bool:
	return prefix == MESSAGE_PREFIX


func _capture(message: String, data: Array, session_id: int) -> bool:
	# Auto-register session if not already registered (fallback for timing issues)
	if session_id not in _active_sessions:
		_active_sessions[session_id] = {
			"connected": false,
			"name": "Instance %d" % session_id
		}
		# Connect to stopped signal
		var session := get_session(session_id)
		if session and not session.stopped.is_connected(_on_session_stopped):
			session.stopped.connect(_on_session_stopped.bind(session_id))

	match message:
		"logot:log_entry":
			if data.size() >= 1 and data[0] is Dictionary:
				log_received.emit(session_id, data[0])
			return true
		"logot:channel_discovered":
			if data.size() >= 1:
				channel_discovered.emit(session_id, str(data[0]))
			return true
		"logot:logs_cleared":
			logs_cleared.emit(session_id)
			return true
		"logot:restart":
			restart_requested.emit(session_id)
			return true
		"logot:hello":
			# Game instance says hello when it starts
			if session_id in _active_sessions:
				_active_sessions[session_id].connected = true
				if data.size() >= 1:
					_active_sessions[session_id].name = str(data[0])
				instance_started.emit(session_id)
			return true
	return false


func _setup_session(session_id: int) -> void:
	# A new debug session started (game launched)
	_active_sessions[session_id] = {
		"connected": false,
		"name": "Instance %d" % session_id
	}

	# Get the session and connect to its stopped signal
	var session := get_session(session_id)
	if session:
		session.stopped.connect(_on_session_stopped.bind(session_id))


func _on_session_stopped(session_id: int) -> void:
	if session_id in _active_sessions:
		_active_sessions.erase(session_id)
		instance_stopped.emit(session_id)


## Get all active session IDs
func get_active_sessions() -> Array[int]:
	var sessions: Array[int] = []
	for session_id in _active_sessions:
		if _active_sessions[session_id].connected:
			sessions.append(session_id)
	return sessions


## Get the name of a session
func get_session_name(session_id: int) -> String:
	if session_id in _active_sessions:
		return _active_sessions[session_id].name
	return "Unknown"


## Check if a session is active and connected
func is_session_active(session_id: int) -> bool:
	return session_id in _active_sessions and _active_sessions[session_id].connected


## Send a message to a specific game instance
func send_to_instance(session_id: int, message: String, data: Array = []) -> void:
	var session := get_session(session_id)
	if session:
		session.send_message(MESSAGE_PREFIX + ":" + message, data)


## Send visibility change to game instance
func send_level_visibility(session_id: int, level: int, mode: int) -> void:
	send_to_instance(session_id, "set_level_visibility", [level, mode])


## Send channel visibility change to game instance
func send_channel_visibility(session_id: int, channel: String, mode: int) -> void:
	send_to_instance(session_id, "set_channel_visibility", [channel, mode])


## Send clear command to game instance
func send_clear(session_id: int) -> void:
	send_to_instance(session_id, "clear", [])

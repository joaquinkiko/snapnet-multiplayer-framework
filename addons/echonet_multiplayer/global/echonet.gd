## Global Echonet multiplayer manager
extends Node

## Max number of spawned objects
const MAX_SPAWNED_OBJECTS := 65535 # u16 max value

## Maximum characters for user nickname
const MAX_NICKNAME_SIZE := 32

## Local user's nickname to share when playing over the network
var local_nickname: String = ""

## Local user's UID to share over network (could be SteamID or custom login uid)
var local_uid: int = 0

## [EchonetTransport] currently in use-- defaults to [LocalTransport]
var transport: EchonetTransport:
	get: return _transport
	set(value): 
		if value == null: _transport = LocalTransport.new()
		else: _transport = value
var _transport: EchonetTransport = LocalTransport.new()

## Collection of currently spawned objects
var spawned_objects: Dictionary[int, Node]

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Default to randomized player nickname on launch
	local_nickname = "Player" + str(randi_range(1000,9999))

func _ready() -> void:
	if OS.has_feature("Server"):
		transport.init_headless_server()
		return

func _process(delta: float) -> void:
	transport.handle_events()
	transport.handle_time(delta)

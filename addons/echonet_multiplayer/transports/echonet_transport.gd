## Generic class for networking transports-- do not use directly
class_name EchonetTransport extends RefCounted

## Max Server Channels
const MAX_CHANNELS := 2

## Reason for client/server being disconnected
enum DisconnectReason {
	ERROR = -2,
	UNKNOWN = -1,
	LOST_CONNECTION = 0,
	LOCAL_REQUEST = 1,
	TIMEOUT = 2,
	SERVER_CLOSING = 3,
	KICKED = 4,
	SERVER_PRIVATE = 5,
	FAILED_AUTHENTICATION_HASH = 6,
	FAILED_AUTHENTICATION_PASSWORD = 7,
	FAILED_AUTHENTICATION_WHITELIST = 8,
}

## Result of authentication attempt
enum AuthenticationResult {
	FAILED_WHITELIST = -2,
	FAILED_PASSWORD = -1,
	FAILED_HASH = 0,
	SUCCESS = 1
}

## Called whene server is initialized successfully
signal on_server_initialized()
## Called when client connects to server successfully
signal on_connected_to_server()
## Called when disconnected from server
signal on_disconnected(reason: DisconnectReason)

## Called when remote peer connects to server
signal on_peer_connected(peer_id: int)
## Called when remote peer disconnects from server
signal on_peer_disconnecting(peer_id: int)
## Called when a new packet is received
signal on_packet_received(packet: EchonetPacket)

## Called when server info request is received as a non-client
signal on_server_info_request_received(packet: ServerInfoPacket)

## Called when a chat message is received
signal on_chat_received(message: String, sender: EchonetPeer)

## List of connected client-peers sorted by id (including self)
var client_peers: Dictionary[int, EchonetPeer]:
	get: return _client_peers
	set(value): push_error("'client_peers' cannot be set directly")
var _client_peers: Dictionary[int, EchonetPeer]
## Server peer
var server_peer: EchonetPeer:
	get: return _server_peer
	set(value): push_error("'server_peer' cannot be set directly")
var _server_peer: EchonetPeer

## Local machine's peer id
var local_id: int = -1

## How long to wait in msec before connection attempt fails
var connection_timeout_msec: int = 5000

## Max peers allowed in room-- cannot be set while [member is_connected] is true
var max_peers: int:
	get: return _max_peers
	set(value):
		if is_connected: push_error("'max_peers' must be set before connecting")
		elif value < 1: push_error("'max_peers' cannot be set to less than 1")
		elif value > 255: push_error("'max_peers' cannot be set to greater than 255")
		else: _max_peers = value
var _max_peers: int = 32

## Set whether server is currently joinable-- will reset to true on server start
var is_joinable: bool:
	get: return _is_joinable
	set(value):
		_is_joinable = value
		if is_server: server_broadcast(_create_server_info_packet(), 0, true)
var _is_joinable: bool = true

## Server password for connecting to server / compare against clients (empty for no password)
var password := PackedByteArray([])

## Authentication data for connecting to server / compare against clients
var authentication_hash := PackedByteArray([])

## List of UIDs that are whitelisted for server (leave empty for no whitelist)
var uid_whitelist : PackedInt64Array:
	get: return _uid_whitelist
	set(value): 
		if is_connected: push_error("'uid_whitelist' must be set before connecting")
		_uid_whitelist = value
var _uid_whitelist := PackedInt64Array([])

## Name of current server
var server_name: String:
	get: 
		if _server_name.is_empty(): return "%s's Server"%Echonet.local_nickname
		else: return _server_name
	set(value): 
		_server_name = value
		if is_server: server_broadcast(_create_server_info_packet(), 0, true)
var _server_name: String

## True if active connection of any type, or attempting connection
var is_connected: bool: 
	get: return _is_connected
	set(value): push_error("'is_connected' cannot be set directly")
var _is_connected: bool = false
## True if active connection as server
var is_server: bool: 
	get: return _is_server
	set(value): push_error("'is_server' cannot be set directly")
var _is_server: bool = false
## True if active connection as client
var is_client: bool: 
	get: return _is_client
	set(value): push_error("'is_client' cannot be set directly")
var _is_client: bool = false
## Must be set to true during connection setup to notify successful connection
var connection_successful: bool:
	get: return _connection_successful
	set(value): push_error("'connection_successful' cannot be set directly")
var _connection_successful: bool = false

var _has_server_info: bool = false
var _has_peer_info: bool = false

## Initialize connection as Client-Server
func init_server() -> bool:
	if is_connected:
		push_warning("Cannot create connection whilst one is already open!")
		return false
	print("Initializing server...")
	is_joinable = true
	_is_connected = true
	_is_server = true
	_is_client = true
	_server_peer = EchonetPeer.create_server()
	_server_peer.uid = Echonet.local_uid
	_server_peer.nickname = Echonet.local_nickname
	_server_peer.info_received = true
	local_id = 1
	_client_peers = {1:server_peer}
	_connection_successful = false
	_has_peer_info = true
	_has_server_info = true
	call_deferred("_check_for_successful_connection")
	return true

## Initialize connection as a client joining a server
func init_client() -> bool:
	if is_connected:
		push_warning("Cannot create connection whilst one is already open!")
		return false
	print("Initializing client...")
	_is_connected = true
	_is_client = true
	_client_peers = {}
	_connection_successful = false
	_has_peer_info = false
	_has_server_info = false
	call_deferred("_check_for_successful_connection")
	return true

## Initialize connection as Headless-Server
func init_headless_server() -> bool:
	if is_connected:
		push_warning("Cannot create connection whilst one is already open!")
		return false
	print("Initializing headless-server...")
	is_joinable = true
	_is_connected = true
	_is_server = true
	_server_peer = EchonetPeer.create_server()
	local_id = 1
	_client_peers = {}
	_connection_successful = false
	_has_peer_info = true
	_has_server_info = true
	call_deferred("_check_for_successful_connection")
	return true

## Sends an info request to a server
func init_server_info_request() -> bool:
	if is_connected:
		push_warning("Cannot create connection whilst one is already open!")
		return false
	print("Sending server info request...")
	_is_connected = true
	_connection_successful = false
	_has_peer_info = false
	_has_server_info = false
	call_deferred("_check_for_successful_connection")
	return true

## Shutdown open connections
func shutdown(reason: DisconnectReason = DisconnectReason.LOCAL_REQUEST) -> bool:
	if !is_connected:
		push_warning("No connection to shutdown")
		return false
	if is_server:
		print("Shutdown server")
	else:
		match reason:
			DisconnectReason.ERROR:
				print("Disconnected due to error")
			DisconnectReason.UNKNOWN:
				print("Disconnected for unkown reason")
			DisconnectReason.LOCAL_REQUEST:
				print("Disconnected from server")
			DisconnectReason.TIMEOUT:
				print("Disconnected due to timeout")
			DisconnectReason.SERVER_CLOSING:
				print("Server shutdown, connection lost")
			DisconnectReason.KICKED:
				print("Kicked from server")
			DisconnectReason.LOST_CONNECTION:
				print("Lost connection to server")
			DisconnectReason.FAILED_AUTHENTICATION_PASSWORD:
				print("Incorrect password to connect to server")
			DisconnectReason.FAILED_AUTHENTICATION_HASH:
				print("Failed to pass authentication")
			DisconnectReason.FAILED_AUTHENTICATION_WHITELIST:
				print("Unable to connect-- server is whitelisted")
			DisconnectReason.SERVER_PRIVATE:
				print("Unable to connect-- server is rejecting new connections")
	_is_connected = false
	_is_server = false
	_is_client = false
	_connection_successful = false
	_has_peer_info = false
	_has_server_info = false
	_client_peers.clear()
	_server_peer = null
	local_id = -1
	on_disconnected.emit(reason)
	return true

## Async method to check if client / server connected successfuly before timing out
func _check_for_successful_connection() -> void:
	var timeout_time := Time.get_ticks_msec() + connection_timeout_msec
	while Time.get_ticks_msec() < timeout_time:
		if !is_connected: return
		if _connection_successful && _has_server_info && _has_peer_info:
			print("Connected successfully!")
			if is_server: on_server_initialized.emit()
			if is_client: on_connected_to_server.emit()
			if !is_server && !is_client:
				shutdown(DisconnectReason.LOCAL_REQUEST)
			return
		await Engine.get_main_loop().process_frame
	shutdown(DisconnectReason.TIMEOUT)

## Returns next unused client ID
func _get_available_id() -> int:
	var new_id: int = 2
	while client_peers.has(new_id):
		new_id += 1
	return new_id

## Call when new peer connects-- assigns peer ID if none assigned yet
func peer_connected(peer: EchonetPeer) -> void:
	if peer.id == 0: peer.id = _get_available_id()
	_client_peers[peer.id] = peer
	if is_server: 
		server_broadcast(IDAssignmentPacket.new(peer.id, client_peers.keys()))
		print("New connection: ", peer)
		if !peer.is_self: on_peer_connected.emit.call_deferred(peer.id)

## Call when peer disconnects
func peer_disconnected(peer_id: int) -> void:
	on_peer_disconnecting.emit(peer_id)
	if is_server: server_broadcast(IDUnassignmentPacket.new(peer_id))
	print("Lost connection: ", client_peers.get(peer_id, EchonetPeer.placeholder()))
	_client_peers.erase(peer_id)

## Call when peer's info is updated
func peer_info_updated(peer: EchonetPeer) -> void:
	if peer.info_received:
		pass
	else:
		peer.info_received = true
		if !peer.is_self: on_peer_connected.emit.call_deferred(peer.id)
		print("New connection: ", peer)

## Should be called every frame
func handle_events() -> void: pass

## Handles receiving of packets
func handle_packet(packet: EchonetPacket) -> void:
	on_packet_received.emit(packet)
	match packet.type:
		EchonetPacket.PacketType.ID_ASSIGNMENT:
			if is_server: return
			packet = IDAssignmentPacket.new_remote(packet)
			if local_id == -1:
				local_id = packet.id
				for remote_id in packet.remote_ids:
					peer_connected(EchonetPeer.create_client(remote_id))
			else:
				peer_connected(EchonetPeer.create_client(packet.id))
		EchonetPacket.PacketType.ID_UNASSIGNMENT:
			if is_server: return
			packet = IDUnassignmentPacket.new_remote(packet)
			peer_disconnected(packet.id)
		EchonetPacket.PacketType.AUTHENTICATION:
			if !is_server: return
			packet = AuthenticationPacket.new_remote(packet)
			if password.size() > 0 && packet.password != password:
				processs_authentication(AuthenticationResult.FAILED_PASSWORD, packet)
			elif packet.auth_hash != authentication_hash:
				processs_authentication(AuthenticationResult.FAILED_HASH, packet)
			elif uid_whitelist.size() > 0 && !uid_whitelist.has(packet.uid):
				processs_authentication(AuthenticationResult.FAILED_WHITELIST, packet)
			else:
				processs_authentication(AuthenticationResult.SUCCESS, packet)
		EchonetPacket.PacketType.SERVER_INFO:
			if is_server: return
			if !_connection_successful: _connection_successful = true
			_has_server_info = true
			packet = ServerInfoPacket.new_remote(packet)
			if !is_client:
				printt("Server Info: ",
					'"%s"'%packet.server_name, 
					"%s/%s"%[packet.current_peers, packet.max_peers], 
					packet.status_to_string())
				on_server_info_request_received.emit(packet)
				_connection_successful = false
				shutdown(DisconnectReason.LOCAL_REQUEST)
				return
			server_name = packet.server_name
			_max_peers = packet.max_peers
			if packet.server_status == ServerInfoPacket.ServerStatus.NON_JOINABLE:
				is_joinable = false
			else: is_joinable = true
		EchonetPacket.PacketType.PEER_INFO:
			packet = PeerInfoPacket.new_remote(packet)
			if is_server:
				pass
			else:
				_has_peer_info = true
				for n in packet.nicknames.keys():
					if !client_peers.has(n): continue
					client_peers[n].nickname = packet.nicknames[n]
					client_peers[n].uid = packet.uids.get(n, 0)
					client_peers[n].is_admin = packet.admins.get(n, false)
					peer_info_updated(client_peers[n])
		EchonetPacket.PacketType.INFO_REQUEST:
			packet = InfoRequestPacket.new_remote(packet)
			if is_server:
				packet = InfoRequestPacket.new_remote(packet)
				if packet.request_type == InfoRequestPacket.RequestType.SERVER_INFO:
					send_server_info(packet)
			else:
				pass
		EchonetPacket.PacketType.CHAT:
			packet = ChatPacket.new_remote(packet)
			if is_server: server_relay_message(packet)
			else: 
				on_chat_received.emit(packet.text, client_peers.get(packet.original_sender_id, null))
		EchonetPacket.PacketType.ADMIN_UPDATE:
			packet = AdminUpdatePacket.new_remote(packet)
			if client_peers.has(packet.id): client_peers[packet.id].is_admin = packet.promotion
		_:
			push_error("Unrecognized packet type: ", packet.type)

## Call to kick a peer
func kick(peer: EchonetPeer) -> void: pass

## Server calls to broadcast to all clients
func server_broadcast(packet: EchonetPacket, channel: int = 0, reliable: bool = false): pass

## Server calls to send packet to specific client
func server_message(peer: EchonetPeer, packet: EchonetPacket, channel: int = 0, reliable: bool = false): pass

## Client calls to send packet to server
func client_message(packet: EchonetPacket, channel: int = 0, reliable: bool = false): pass

## Called by server when authentication packet is received
func processs_authentication(result: AuthenticationResult, packet: AuthenticationPacket) -> void: pass

## Called by server when server info is requested by non-client
func send_server_info(packet: EchonetPacket) -> void: pass

## Returns [ServerInfoPacket] with up-to-date info
func _create_server_info_packet() -> ServerInfoPacket:
	var status : ServerInfoPacket.ServerStatus = ServerInfoPacket.ServerStatus.OPEN
	if !is_joinable: status = ServerInfoPacket.ServerStatus.NON_JOINABLE
	elif uid_whitelist.size() > 0: status = ServerInfoPacket.ServerStatus.WHITELIST_ONLY
	var packet := ServerInfoPacket.new(server_name, client_peers.size(), max_peers, status)
	return packet

## Sends chat message over the network-- if [param audience] is null, sends to all
func send_chat(message: String, audience: EchonetPeer = null) -> void:
	var chat_packet := ChatPacket.new(0, local_id, message)
	if audience != null: chat_packet.receiver = audience.id
	if is_server:
		if message.begins_with("/"):
			if message.is_empty(): return
			var args: PackedStringArray = message.split(" ", false)
			var command: String = args[0].trim_prefix("/")
			args.remove_at(0)
			handle_server_command(command, args, server_peer)
			return
		if audience == null:
			server_broadcast(chat_packet, 0, true)
		else:
			server_message(audience, chat_packet, 0, true)
		on_chat_received.emit(message, server_peer)
	else:
		client_message(chat_packet, 0, true)

## Server sends non-personal chat message to specific peer-- null to send to all
func send_server_chat(message: String, audience: EchonetPeer) -> void:
	if audience != null:
		var chat_packet := ChatPacket.new(audience.id, 0, message)
		if audience.is_server: on_chat_received.emit(chat_packet.text, null)
		else: server_message(audience, chat_packet, 0, true)
	else:
		var chat_packet := ChatPacket.new(0, 0, message)
		on_chat_received.emit(chat_packet.text, null)
		server_broadcast(chat_packet, 0, true)

## Relays received [ChatPacket] across server
func server_relay_message(packet: ChatPacket) -> void:
	packet.original_sender_id = packet.sender.id
	if packet.text.begins_with("/"):
		if packet.text.is_empty(): return
		var args: PackedStringArray = packet.text.split(" ", false)
		var command: String = args[0].trim_prefix("/")
		args.remove_at(0)
		handle_server_command(command, args, packet.sender)
		return
	if is_client && packet.receiver == local_id: 
		on_chat_received.emit(packet.text, packet.sender)
		return
	elif packet.receiver == 0: 
		on_chat_received.emit(packet.text, packet.sender)
		server_broadcast(packet, 0, true)
	elif client_peers.has(packet.receiver): server_message(client_peers[packet.receiver], packet, 0, true)

## Called when server command is received
func handle_server_command(command: String, args: PackedStringArray, peer: EchonetPeer) -> void:
	print("%s sent command: %s (%s)"%[peer, command, args])
	match command:
		"whisper":
			if args.size() < 2:
				send_server_chat("Error: 'whisper' must include more arguments", peer)
				return
			var audience := get_client_by_nickname(args[0])
			if audience == null:
				send_server_chat("Error: '%s' could not be found to 'whisper'"%args[0], peer)
				return
			if audience.id == peer.id:
				send_server_chat("Error: cannot whisper self", peer)
				return
			args.remove_at(0)
			var message: String
			for arg in args:
				message += "%s "%arg
			message = message.trim_suffix(" ")
			var chat_packet := ChatPacket.new(audience.id, peer.id, "(whisper) %s"%message)
			if audience.is_self:
				on_chat_received.emit("(whisper) %s"%message, peer)
				var chat_ack_packet := ChatPacket.new(peer.id, peer.id, "(whisper) %s"%message)
				server_message(peer, chat_ack_packet, 0, true)
			else:
				server_message(audience, chat_packet, 0, true)
				var chat_ack_packet := ChatPacket.new(peer.id, peer.id, "(whisper) %s"%message)
				if is_server: on_chat_received.emit(chat_ack_packet.text, server_peer)
				else: server_message(peer, chat_ack_packet, 0, true)
		"kick":
			if !peer.is_admin:
				send_server_chat("Error: Must be admin to kick peers", peer)
				return
			if args.size() < 1:
				send_server_chat("Error: 'kick' must include argument", peer)
				return
			var target := get_client_by_nickname(args[0])
			if target == null:
				send_server_chat("Error: '%s' could not be found to 'kick'"%args[0], peer)
				return
			if target.is_self:
				send_server_chat("Error: Cannot 'kick' self", peer)
				return
			if target.is_server:
				send_server_chat("Error: Cannot 'kick' server", peer)
				return
			kick(target)
			send_server_chat("Kicking '%s'"%args[0], peer)
		"promote":
			if !peer.is_admin:
				send_server_chat("Error: Must be admin to promote peers", peer)
				return
			if args.size() < 1:
				send_server_chat("Error: 'promote' must include argument", peer)
				return
			var target := get_client_by_nickname(args[0])
			if target == null:
				send_server_chat("Error: '%s' could not be found to 'promote'"%args[0], peer)
				return
			if target.is_server:
				send_server_chat("Error: Cannot 'promote' server", peer)
				return
			if target.is_admin: 
				send_server_chat("Error: '%s' is already an admin"%args[0], peer)
				return
			update_admin_status(target, true)
			send_server_chat("Promoting '%s'"%args[0], null)
			send_server_chat("You are now an admin", target)
		"demote":
			if !peer.is_admin:
				send_server_chat("Error: Must be admin to demote peers", peer)
				return
			if args.size() < 1:
				send_server_chat("Error: 'demote' must include argument", peer)
				return
			var target := get_client_by_nickname(args[0])
			if target == null:
				send_server_chat("Error: '%s' could not be found to 'demote'"%args[0], peer)
				return
			if target.is_server:
				send_server_chat("Error: Cannot 'demote' server", peer)
				return
			if !target.is_admin: 
				send_server_chat("Error: '%s' is already not an admin"%args[0], peer)
				return
			update_admin_status(target, false)
			send_server_chat("Demoting '%s'"%args[0], peer)
			send_server_chat("You are no longer an admin", null)
		"joinable":
			if !peer.is_admin:
				send_server_chat("Error: Must be admin to set joinable status", peer)
				return
			if args.size() < 1:
				send_server_chat("Error: 'joinable' must include argument", peer)
				return
			match args[0]:
				"1": is_joinable = true
				"t": is_joinable = true
				"true": is_joinable = true
				"0": is_joinable = false
				"f": is_joinable = false
				"false": is_joinable = false
				_:
					send_server_chat("Error: '%s' unrecognized argument for 'joinable'"%args[0], peer)
					return
			if is_joinable: send_server_chat("Server is now set to joinable", null)
			else: send_server_chat("Server is now set to unjoinable", null)
		"server_name":
			if !peer.is_admin:
				send_server_chat("Error: Must be admin to set server name", peer)
				return
			if args.size() < 1:
				send_server_chat("Error: 'server_name' must include argument", peer)
				return
			var new_name: String
			for arg in args:
				new_name += "%s "%arg
			new_name = new_name.trim_suffix(" ")
			server_name = new_name
			send_server_chat("Server name updated to: %s"%server_name, null)
		_: 
			send_server_chat("'%s' command unrecognized"%command, peer)

## Returns first client with matching nickname-- return null if not found
func get_client_by_nickname(nickname: String) -> EchonetPeer:
	for client in client_peers.values():
		if client.nickname == nickname: return client
	return null

## Returns first client with matching UID-- return null if not found
func get_client_by_uid(uid: String) -> EchonetPeer:
	for client in client_peers.values():
		if client.uid == uid: return client
	return null

## Updates admin status of a peer
func update_admin_status(peer: EchonetPeer, promote: bool = true) -> void:
	peer.is_admin = promote
	var admin_update_packet := AdminUpdatePacket.new(peer.id, promote)
	server_broadcast(admin_update_packet, 0, true)

## Call at regular intervals to gather statistics in array
## 0:data in	1:data out	2:packets in	3:packets out	4:rtt	5:throttle	6:packet loss
func gather_statistics() -> PackedInt64Array: return [0,0,0,0,0,0,0]

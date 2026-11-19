extends Node
## Autoload "Net": owns the ENet multiplayer peer, the connection lifecycle, and a
## simple player registry. Menus and gameplay talk to this instead of touching the
## MultiplayerAPI directly. With no peer active (`is_multiplayer == false`) the game
## is plain single-player — every authority check is a no-op.
##
## Model: listen-server (the host also plays, peer id 1). The server is the source
## of truth for the roster; clients learn it via RPC. Transport is ENet/UDP, so a
## UDP tunnel (e.g. playit.gg) in front of `DEFAULT_PORT` makes it playable over the
## internet without router setup — no code here is tunnel-specific.

signal player_list_changed
signal connection_failed
signal server_disconnected
signal start_race

const DEFAULT_PORT := 24565
const MAX_PLAYERS := 4

var is_multiplayer: bool = false
var players: Dictionary = {}      # peer_id -> { "name": String }
var local_name: String = "Player"


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# --- Host / Join / Leave ---------------------------------------------------

func host(port: int = DEFAULT_PORT) -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port, MAX_PLAYERS) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	is_multiplayer = true
	players = { 1: { "name": local_name } }   # the host is peer 1
	player_list_changed.emit()
	return true


func join(address: String, port: int = DEFAULT_PORT) -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address, port) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	is_multiplayer = true
	return true


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	is_multiplayer = false
	players.clear()
	player_list_changed.emit()


func is_host() -> bool:
	return is_multiplayer and multiplayer.is_server()


func local_id() -> int:
	return multiplayer.get_unique_id() if is_multiplayer else 1


# --- Connection lifecycle --------------------------------------------------

func _on_peer_connected(id: int) -> void:
	# Server only: hand the newcomer the current roster (incl. the host).
	if multiplayer.is_server():
		for pid in players:
			_register_player.rpc_id(id, int(pid), String(players[pid]["name"]))


func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	player_list_changed.emit()
	if multiplayer.is_server():
		_remove_player.rpc(id)


func _on_connected_to_server() -> void:
	# Client just connected: announce ourselves to everyone (incl. server + self).
	_register_player.rpc(multiplayer.get_unique_id(), local_name)


func _on_connection_failed() -> void:
	leave()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	leave()
	server_disconnected.emit()


# --- Roster RPCs (the server relays client broadcasts to other clients) -----

@rpc("any_peer", "call_local", "reliable")
func _register_player(id: int, pname: String) -> void:
	players[id] = { "name": pname }
	player_list_changed.emit()


@rpc("any_peer", "call_local", "reliable")
func _remove_player(id: int) -> void:
	players.erase(id)
	player_list_changed.emit()


# --- Start race (host -> everyone) -----------------------------------------

func host_start_race() -> void:
	if multiplayer.is_server():
		_start_race.rpc()


@rpc("authority", "call_local", "reliable")
func _start_race() -> void:
	start_race.emit()

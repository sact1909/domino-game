extends Node

## Servidor dedicado. Por ahora solo prueba la cadena completa de despliegue
## (Godot headless -> Docker -> Coolify -> wss://): acepta conexiones WebSocket,
## saluda al conectar y responde a un "ping". Las salas y el juego vienen en la
## fase C; esto ya deja montado el transporte y el formato de mensajes.
##
## Protocolo: un mensaje = un paquete = JSON con la clave "type".
##
## Puerto: variable de entorno PORT (Coolify la inyecta), o DEFAULT_PORT en local.

const DEFAULT_PORT := 8090
const PROTOCOL_VERSION := 1

var _peer := WebSocketMultiplayerPeer.new()


func _ready() -> void:
	var port := _resolve_port()
	var err := _peer.create_server(port)
	if err != OK:
		push_error("No se pudo abrir el servidor en el puerto %d (error %d)." % [port, err])
		get_tree().quit(1)
		return

	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)

	# Este print es la señal de vida que se ve en los logs de Coolify.
	print("[servidor] Dominó Dominicano — protocolo v%d escuchando en el puerto %d" % [PROTOCOL_VERSION, port])


func _process(_delta: float) -> void:
	_peer.poll()
	# get_packet_peer() informa de quién viene el SIGUIENTE paquete, así que se
	# consulta antes de sacarlo de la cola.
	while _peer.get_available_packet_count() > 0:
		var from: int = _peer.get_packet_peer()
		var raw: PackedByteArray = _peer.get_packet()
		_handle_packet(from, raw)


func _on_peer_connected(id: int) -> void:
	print("[servidor] conectado: %d" % id)
	_send(id, {
		"type": "hello",
		"protocol": PROTOCOL_VERSION,
	})


func _on_peer_disconnected(id: int) -> void:
	print("[servidor] desconectado: %d" % id)


func _handle_packet(from: int, raw: PackedByteArray) -> void:
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		_send(from, {"type": "error", "reason": "mensaje_invalido"})
		return

	var msg: Dictionary = parsed
	var msg_type: String = str(msg.get("type", ""))
	print("[servidor] %d -> %s" % [from, msg_type])

	match msg_type:
		"ping":
			_send(from, {
				"type": "pong",
				"echo": msg.get("payload", null),
			})
		_:
			_send(from, {"type": "error", "reason": "tipo_desconocido", "got": msg_type})


func _send(peer_id: int, msg: Dictionary) -> void:
	_peer.set_target_peer(peer_id)
	_peer.put_packet(JSON.stringify(msg).to_utf8_buffer())


func _resolve_port() -> int:
	var from_env: String = OS.get_environment("PORT")
	if from_env.is_valid_int():
		return int(from_env)
	# Si PORT viene con basura conviene que se vea en los logs: si no, el servidor
	# arrancaría en el puerto por defecto y el proxy no encontraría a nadie.
	if not from_env.is_empty():
		push_warning("PORT no es un número válido (%s); se usa el puerto %d." % [from_env, DEFAULT_PORT])
	return DEFAULT_PORT

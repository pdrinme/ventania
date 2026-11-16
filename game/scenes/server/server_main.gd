extends Node
## Servidor dedicado da partida (sem interface).
## Uso: ./ventania.x86_64 --headless -- --servidor [--porta=24800]
##   ou: godot --headless --path game -- --servidor
## Etapa 2: um campo de treino aberto, sem salas nem fim de partida (Etapa 4/7).

var server: GameServer


func _ready() -> void:
	var porta := Protocol.DEFAULT_PORT
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--porta="):
			porta = int(a.trim_prefix("--porta="))
	var mundo := CampoTreino.new()
	mundo.com_ambiente = false
	add_child(mundo)
	server = GameServer.new(mundo)
	add_child(server)
	var e := server.start(porta)
	if e != OK:
		Log.error("servidor", "não foi possível abrir a porta %d: %s" % [porta, error_string(e)])
		get_tree().quit(1)
		return
	Log.info("servidor", "%s — servidor dedicado pronto. Jogadores entram com o endereço deste PC e a porta %d (UDP)." % [Version.full(), porta])

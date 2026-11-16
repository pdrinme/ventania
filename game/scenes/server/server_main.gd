extends Node
## Servidor dedicado da partida (sem interface).
## Uso: ./ventania.x86_64 --headless -- --servidor [--porta=24800] [--modo=br|treino] [--min-jogadores=2]
##   ou: godot --headless --path game -- --servidor --modo=br
## --modo=br (padrão): partidas Battle Royale seguidas na Ilha Ventania.
## --modo=treino: campo de treino aberto (reaparece, bonecos).

var server: GameServer


func _ready() -> void:
	var porta := Protocol.DEFAULT_PORT
	var modo := "br"
	var cfg := PartidaBR.carregar_config()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--porta="):
			porta = int(a.trim_prefix("--porta="))
		elif a.begins_with("--modo="):
			modo = a.trim_prefix("--modo=")
		elif a.begins_with("--config="):
			var extra: Variant = JSON.parse_string(FileAccess.get_file_as_string(a.trim_prefix("--config=")))
			if extra is Dictionary:
				cfg.merge(extra, true)
		elif a.begins_with("--min-jogadores="):
			cfg["min_jogadores"] = int(a.trim_prefix("--min-jogadores="))
	var mundo := Mapa.create(IlhaVentania.NOME if modo == "br" else CampoTreino.NOME)
	mundo.com_ambiente = false
	add_child(mundo)
	server = GameServer.new(mundo, 0, modo, cfg)
	add_child(server)
	var e := server.start(porta)
	if e != OK:
		Log.error("servidor", "não foi possível abrir a porta %d: %s" % [porta, error_string(e)])
		get_tree().quit(1)
		return
	Log.info("servidor", "modo: %s, mapa: %s" % [modo, mundo.display_name()])
	Log.info("servidor", "%s — servidor dedicado pronto. Jogadores entram com o endereço deste PC e a porta %d (UDP)." % [Version.full(), porta])

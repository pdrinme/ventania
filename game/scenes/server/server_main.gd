extends Node
## Servidor dedicado da partida (sem interface).
## Uso: ./ventania_servidor.x86_64 --headless -- --servidor [opções]
##   ou: godot --headless --path game -- --servidor --modo=br
## Opções:
##   --porta=24800          primeira porta UDP (a sala N usa porta + N - 1)
##   --salas=1              quantas salas (partidas independentes) neste processo
##   --modo=br|treino       br (padrão): partidas BR seguidas; treino: campo aberto
##   --max-jogadores=16     humanos por sala (acima disso: "sala cheia")
##   --bots=16              completa a partida com bots até este total (0 = sem bots)
##   --min-jogadores=2      humanos para começar a contagem
##   --config=arquivo.json  sobrescreve data/partida.json
##   --relatorio=30         a cada N s, registra banda e tempo de tick de cada sala

const SALAS_MAX := 8

var salas: Array[GameServer] = []
var _relatorio_s := 30.0
var _t := 0.0


func _ready() -> void:
	var porta := Protocol.DEFAULT_PORT
	var modo := "br"
	var n_salas := 1
	var max_jog := Protocol.MAX_PLAYERS
	var cfg := PartidaBR.carregar_config()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--porta="):
			porta = int(a.trim_prefix("--porta="))
		elif a.begins_with("--modo="):
			modo = a.trim_prefix("--modo=")
		elif a.begins_with("--salas="):
			n_salas = clampi(int(a.trim_prefix("--salas=")), 1, SALAS_MAX)
		elif a.begins_with("--max-jogadores="):
			max_jog = clampi(int(a.trim_prefix("--max-jogadores=")), 1, Protocol.MAX_PLAYERS)
		elif a.begins_with("--bots="):
			cfg["bots"] = {"preencher_ate": clampi(int(a.trim_prefix("--bots=")), 0, Protocol.MAX_PLAYERS)}
		elif a.begins_with("--relatorio="):
			_relatorio_s = maxf(5.0, float(a.trim_prefix("--relatorio=")))
		elif a.begins_with("--config="):
			var extra: Variant = JSON.parse_string(FileAccess.get_file_as_string(a.trim_prefix("--config=")))
			if extra is Dictionary:
				cfg.merge(extra, true)
		elif a.begins_with("--min-jogadores="):
			cfg["min_jogadores"] = int(a.trim_prefix("--min-jogadores="))
	var portas := []
	for i in n_salas:
		portas.append(porta + i)
	for i in n_salas:
		# cada sala tem o próprio mundo físico (SubViewport com own_world_3d)
		var vp := SubViewport.new()
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp.size = Vector2i(2, 2)
		vp.name = "Sala%d" % (i + 1)
		add_child(vp)
		var mundo := Mapa.create(IlhaVentania.NOME if modo == "br" else CampoTreino.NOME)
		mundo.com_ambiente = false
		vp.add_child(mundo)
		var s := GameServer.new(mundo, 0, modo, cfg.duplicate(true))
		s.max_jogadores = max_jog
		s.outras_salas = ", ".join(portas.filter(func(p): return p != porta + i).map(func(p): return str(p)))
		vp.add_child(s)
		var e := s.start(porta + i)
		if e != OK:
			Log.error("servidor", "não foi possível abrir a porta %d: %s" % [porta + i, error_string(e)])
			get_tree().quit(1)
			return
		salas.append(s)
	Log.info("servidor", "modo: %s, %d sala(s), até %d jogadores por sala" % [modo, n_salas, max_jog])
	Log.info("servidor", "%s — servidor dedicado pronto. Jogadores entram com o endereço deste PC e a porta %s (UDP)." % [
			Version.full(), " ou ".join(portas.map(func(p): return str(p)))])


func _process(delta: float) -> void:
	_t += delta
	if _t < _relatorio_s:
		return
	for i in salas.size():
		Log.info("servidor", "sala %d: %s" % [i + 1, salas[i].report(_t)])
	_t = 0.0

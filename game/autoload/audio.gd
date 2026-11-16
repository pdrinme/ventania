extends Node
## Barramentos de áudio (Master, Musica, Efeitos, Interface), volumes vindos das
## configurações e sons de interface com um pequeno pool de players.

const BUSES := {"master": "Master", "music": "Musica", "sfx": "Efeitos", "ui": "Interface"}
const SONS_UI := ["clique", "foco", "voltar", "confirmar"]  # res://assets/audio/ui/<nome>.wav
const POOL := 4

var _sons := {}
var _players: Array[AudioStreamPlayer] = []
var _proximo := 0


func _init() -> void:
	# cria os barramentos aqui (antes de Settings aplicar volumes)
	for chave in BUSES:
		var nome: String = BUSES[chave]
		if AudioServer.get_bus_index(nome) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, nome)
			AudioServer.set_bus_send(i, "Master")


func _ready() -> void:
	for nome in SONS_UI:
		var caminho := "res://assets/audio/ui/%s.wav" % nome
		if ResourceLoader.exists(caminho):
			_sons[nome] = load(caminho)
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = BUSES["ui"]
		add_child(p)
		_players.append(p)


func set_bus_volume(chave: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(BUSES.get(chave, ""))
	if i == -1:
		return
	AudioServer.set_bus_mute(i, linear <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.001)))


func play_ui(nome: String) -> void:
	if not _sons.has(nome):
		return
	var p := _players[_proximo]
	_proximo = (_proximo + 1) % POOL
	p.stream = _sons[nome]
	p.play()

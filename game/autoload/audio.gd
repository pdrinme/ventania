extends Node
## Barramentos de áudio (Master, Musica, Efeitos, Interface), volumes vindos das
## configurações e sons de interface com um pequeno pool de players.

const BUSES := {"master": "Master", "music": "Musica", "sfx": "Efeitos", "ui": "Interface"}
const SONS_UI := ["clique", "foco", "voltar", "confirmar", "compra", "nivel", "recompensa", "partida", "notificacao"]  # res://assets/audio/ui/<nome>.wav
const POOL := 4
const POOL_3D := 12
const PASTA_JOGO := "res://assets/audio/jogo/%s.wav"

var _sons := {}
var _players: Array[AudioStreamPlayer] = []
var _proximo := 0
var _jogo := {}                      # cache dos efeitos do jogo
var _p3d: Array[AudioStreamPlayer3D] = []
var _p2d: Array[AudioStreamPlayer] = []
var _prox3d := 0
var _prox2d := 0


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
	for i in POOL_3D:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = BUSES["sfx"]
		p3.unit_size = 6.0
		p3.max_distance = 120.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p3)
		_p3d.append(p3)
	for i in POOL:
		var p2 := AudioStreamPlayer.new()
		p2.bus = BUSES["sfx"]
		add_child(p2)
		_p2d.append(p2)


func _efeito(nome: String) -> AudioStream:
	if not _jogo.has(nome):
		var c := PASTA_JOGO % nome
		_jogo[nome] = load(c) if ResourceLoader.exists(c) else null
	return _jogo[nome]


## Efeito do próprio jogador (sem posição).
func play_sfx(nome: String, volume_db := 0.0, tom := 1.0) -> void:
	var s := _efeito(nome)
	if s == null:
		return
	var p := _p2d[_prox2d]
	_prox2d = (_prox2d + 1) % _p2d.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = tom
	p.play()


## Efeito no mundo (outros jogadores, baús, itens).
func play_at(nome: String, pos: Vector3, volume_db := 0.0, tom := 1.0) -> void:
	var s := _efeito(nome)
	if s == null:
		return
	var p := _p3d[_prox3d]
	_prox3d = (_prox3d + 1) % _p3d.size()
	p.stream = s
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = tom
	p.play()


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

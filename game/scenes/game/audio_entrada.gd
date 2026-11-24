class_name AudioEntrada
extends Node
## Som da entrada na partida (Ônibus dos Ventos → queda livre → planador).
##
## - Ônibus (3D, preso ao visual do ônibus): motor turboélice e vento passando,
##   ouvidos de longe e com a direção certa; o tom sobe e desce com a aproximação
##   (Doppler calculado aqui, a partir do movimento do ônibus e do ouvinte) e o
##   motor "acelera" de leve quando as portas abrem.
## - Dentro do ônibus (2D): cabine (motor abafado, sacolejo, rangidos) enquanto o
##   jogador está a bordo; some num fade quando ele salta.
## - Eventos por tick do servidor, UMA vez cada: buzina de aviso 3 s antes das
##   portas, chiado das portas + campainha ao abrir, buzina curta de "última
##   chamada" 5 s antes de fechar. Quem entra no meio não ouve eventos passados.
## - Queda livre / planador (2D): vento de altitude com volume e tom pela velocidade.
## Tudo com fades (sem cortes) e um único conjunto de players por partida.

const FADE := 1.2                  # s para entrar/sair
const SOM := 343.0                 # m/s (Doppler)
const AVISO_S := 3.0
const ULTIMA_CHAMADA_S := 5.0

var motor: AudioStreamPlayer3D
var vento_onibus: AudioStreamPlayer3D
var cabine: AudioStreamPlayer
var vento_queda: AudioStreamPlayer

var _g_motor := 0.0                # ganhos lineares atuais (fades)
var _g_vento := 0.0
var _g_cabine := 0.0
var _g_queda := 0.0
var _pos_onibus := Vector3.INF
var _pos_ouvinte := Vector3.INF
var _eventos := {}                 # nome -> tick0 da partida em que já tocou
var _ultimo_tick := -1


func _ready() -> void:
	motor = _p3d("onibus_motor", 34.0, 700.0)
	vento_onibus = _p3d("onibus_vento", 18.0, 260.0)
	cabine = _p2d("onibus_cabine")
	vento_queda = _p2d("vento_altitude")


static func _laco(nome: String) -> AudioStream:
	var c := "res://assets/audio/jogo/%s.wav" % nome
	if not ResourceLoader.exists(c):
		return null
	var s := (load(c) as AudioStreamWAV).duplicate() as AudioStreamWAV
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = int(s.get_length() * s.mix_rate)
	return s


func _p3d(nome: String, unidade: float, alcance: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = _laco(nome)
	p.bus = "Efeitos"
	p.unit_size = unidade
	p.max_distance = alcance
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.volume_db = -80.0
	return p


func _p2d(nome: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _laco(nome)
	p.bus = "Efeitos"
	p.volume_db = -80.0
	add_child(p)
	return p


## Prende os sons 3D ao visual do ônibus (uma vez; o visual é reaproveitado).
func attach_bus(visual: Node3D) -> void:
	for p in [motor, vento_onibus]:
		if p.get_parent() != visual:
			if p.get_parent():
				p.get_parent().remove_child(p)
			visual.add_child(p)
			p.position = Vector3(0, 2.3, 0.3)          # entre as turbinas


## Chamado a cada quadro pelo jogo.
##  ativo: ônibus no ar; a_bordo: o jogador local está dentro; tick: do servidor;
##  bus: rota (abre/fecha/tick0); ouvinte: posição da câmera;
##  queda: 0 no chão, 1 queda livre, 2 planador; vel_queda: m/s do jogador.
func update(delta: float, ativo: bool, a_bordo: bool, tick: int, bus: OnibusBatalha, ouvinte: Vector3,
		queda: int, vel_queda: float) -> void:
	var k := clampf(delta / FADE, 0.0, 1.0)
	# --- ônibus (3D)
	var alvo_motor := 1.0 if ativo else 0.0
	_g_motor = move_toward(_g_motor, alvo_motor, k)
	_g_vento = move_toward(_g_vento, alvo_motor * (0.6 if a_bordo else 1.0), k)
	var pitch := 1.0
	if ativo and motor.is_inside_tree():
		var p := motor.global_position
		if _pos_onibus != Vector3.INF and _pos_ouvinte != Vector3.INF and delta > 0.0:
			var v_fonte := (p - _pos_onibus) / delta
			var v_ouv := (ouvinte - _pos_ouvinte) / delta
			var dir := (ouvinte - p).normalized()
			# Doppler: aproximando sobe, afastando desce (limitado, sem "miado")
			pitch = clampf((SOM + v_ouv.dot(-dir)) / maxf(1.0, SOM - v_fonte.dot(dir)), 0.88, 1.12)
		_pos_onibus = p
		_pos_ouvinte = ouvinte
		# motor "respira" e acelera um pouco com as portas abertas (mais carga)
		var portas := bus != null and bus.doors_open(tick)
		pitch *= 1.0 + 0.015 * sin(Time.get_ticks_msec() * 0.0011) + (0.05 if portas else 0.0)
	else:
		_pos_onibus = Vector3.INF
	motor.pitch_scale = lerpf(motor.pitch_scale, pitch, clampf(delta * 3.0, 0.0, 1.0))
	vento_onibus.pitch_scale = motor.pitch_scale
	_aplicar3(motor, _g_motor, 0.0 if not a_bordo else -6.0)
	_aplicar3(vento_onibus, _g_vento, -4.0)
	# --- cabine (2D)
	_g_cabine = move_toward(_g_cabine, 1.0 if (ativo and a_bordo) else 0.0, clampf(delta / (0.5 if not a_bordo else FADE), 0.0, 1.0))
	_aplicar2(cabine, _g_cabine, -5.0)
	# --- vento de altitude na queda (2D)
	var alvo_q := 0.0
	if queda == 1:
		alvo_q = clampf(vel_queda / 30.0, 0.35, 1.0)
	elif queda == 2:
		alvo_q = 0.45
	_g_queda = move_toward(_g_queda, alvo_q, clampf(delta / 0.6, 0.0, 1.0))
	vento_queda.pitch_scale = lerpf(vento_queda.pitch_scale, 0.85 + 0.35 * clampf(vel_queda / 40.0, 0.0, 1.0), clampf(delta * 2.0, 0.0, 1.0))
	_aplicar2(vento_queda, _g_queda, -3.0)
	# --- eventos (uma vez por partida)
	if ativo and bus != null:
		_evento("aviso", tick, bus.abre - int(AVISO_S * Protocol.TICK_RATE), bus, "onibus_buzina", -2.0)
		_evento("portas", tick, bus.abre, bus, "onibus_portas", -1.0)
		_evento("ultima", tick, bus.fecha - int(ULTIMA_CHAMADA_S * Protocol.TICK_RATE), bus, "onibus_buzina_curta", -3.0)
	_ultimo_tick = tick


## Toca `som` quando o tick cruza `quando` — só se cruzou AGORA (até 1 s depois),
## para quem conecta no meio não ouvir eventos velhos; e só uma vez por ônibus.
func _evento(nome: String, tick: int, quando: int, bus: OnibusBatalha, som: String, db: float) -> void:
	if _eventos.get(nome, -1) == bus.tick0:
		return
	if tick >= quando and tick <= quando + Protocol.TICK_RATE:
		_eventos[nome] = bus.tick0
		var audio := get_node_or_null("/root/Audio")
		if audio and motor.is_inside_tree():
			audio.play_at(som, motor.global_position, db + 6.0)
			# a bordo, o som chega também "por dentro" (cabine)
			if _g_cabine > 0.3:
				audio.play_sfx(som, db - 4.0)


func _aplicar3(p: AudioStreamPlayer3D, g: float, db: float) -> void:
	if p.stream == null:
		return
	if g > 0.001:
		p.volume_db = linear_to_db(g) + db
		if not p.playing and p.is_inside_tree():
			p.play()
	elif p.playing:
		p.stop()


func _aplicar2(p: AudioStreamPlayer, g: float, db: float) -> void:
	if p.stream == null:
		return
	if g > 0.001:
		p.volume_db = linear_to_db(g) + db
		if not p.playing:
			p.play()
	elif p.playing:
		p.stop()


## Para tudo com fade (fim da partida, voltar ao lobby): o update leva a zero.
func reset() -> void:
	_eventos.clear()
	_pos_onibus = Vector3.INF


## Diagnóstico/testes: quais sons estão tocando e com que ganho.
func state() -> Dictionary:
	return {"motor": _g_motor if motor.playing else 0.0, "vento_onibus": _g_vento if vento_onibus.playing else 0.0,
			"cabine": _g_cabine if cabine.playing else 0.0, "vento_queda": _g_queda if vento_queda.playing else 0.0,
			"eventos": _eventos.keys()}

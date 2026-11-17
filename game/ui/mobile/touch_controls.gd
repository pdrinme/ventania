class_name TouchControls
extends Control
## Controles de toque (layout próprio do celular, não é o HUD do PC reduzido).
## - Joystick flutuante: toque em qualquer lugar da metade esquerda.
## - Olhar: arrastar na metade direita (fora dos botões).
## - Botões: Pular e Agachar (alterna), Mochila (inventário). Empurrar o joystick até a
##   borda = correr. A picareta e os itens são escolhidos tocando na barra.
## Tamanho dos botões: configuração interface/touch_button_scale.

signal inventory_pressed

const RAIO_JOY := 90.0
const RAIO_BOTAO := 62.0

var sampler: InputSampler
var camera: PlayerCamera
var construcao: BuildMode         # botões de construção (Construir, Peça, Material, Editar)

var _joy_dedo := -1
var _joy_centro := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _olhar_dedo := -1
var _botoes := {}            # nome -> {"centro": Vector2, "raio": float, "dedo": int}
var _escala := 1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Settings.changed.connect(func(s, k, _v):
		if s == "interface" and k == "touch_button_scale":
			_layout())
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	_escala = Settings.get_value("interface", "touch_button_scale")
	var r := RAIO_BOTAO * _escala
	var t := size
	_botoes = {
		"atirar": {"centro": Vector2(t.x - r * 1.6, t.y - r * 4.2), "raio": r * 1.1, "dedo": -1, "texto": "Atirar"},
		"pular": {"centro": Vector2(t.x - r * 1.5, t.y - r * 1.6), "raio": r, "dedo": -1, "texto": "Pular"},
		"agachar": {"centro": Vector2(t.x - r * 3.9, t.y - r * 1.1), "raio": r * 0.8, "dedo": -1, "texto": "Agachar"},
		"recarregar": {"centro": Vector2(t.x - r * 4.0, t.y - r * 3.4), "raio": r * 0.7, "dedo": -1, "texto": "Recarga"},
		"interagir": {"centro": Vector2(t.x - r * 6.0, t.y - r * 2.4), "raio": r * 0.75, "dedo": -1, "texto": "Pegar"},
		"mochila": {"centro": Vector2(t.x - r * 1.0, r * 2.2), "raio": r * 0.62, "dedo": -1, "texto": "Mochila"},
		"construir": {"centro": Vector2(t.x - r * 2.5, r * 2.2), "raio": r * 0.62, "dedo": -1, "texto": "Construir"},
		"peca": {"centro": Vector2(t.x - r * 6.2, t.y - r * 4.4), "raio": r * 0.62, "dedo": -1, "texto": "Peça", "so_construcao": true},
		"material": {"centro": Vector2(t.x - r * 4.0, t.y - r * 3.4), "raio": r * 0.62, "dedo": -1, "texto": "Material", "so_construcao": true},
		"editar": {"centro": Vector2(t.x - r * 4.0, r * 2.2), "raio": r * 0.62, "dedo": -1, "texto": "Editar", "so_construcao": true},
	}
	queue_redraw()


func _input(e: InputEvent) -> void:
	if not visible or sampler == null or sampler.bloqueado:
		return
	if e is InputEventScreenTouch:
		_toque(e as InputEventScreenTouch)
	elif e is InputEventScreenDrag:
		_arrasto(e as InputEventScreenDrag)


func _toque(e: InputEventScreenTouch) -> void:
	if e.pressed:
		for nome in _botoes:
			var b: Dictionary = _botoes[nome]
			if not _visivel(nome):
				continue
			if e.position.distance_to(b["centro"]) <= b["raio"] * 1.15:
				b["dedo"] = e.index
				_apertar(nome)
				queue_redraw()
				return
		if e.position.x < size.x * 0.45 and _joy_dedo == -1:
			_joy_dedo = e.index
			_joy_centro = e.position
			_joy_pos = e.position
		elif _olhar_dedo == -1:
			_olhar_dedo = e.index
	else:
		if e.index == _joy_dedo:
			_joy_dedo = -1
			sampler.touch_move = Vector2.ZERO
		elif e.index == _olhar_dedo:
			_olhar_dedo = -1
		for nome in _botoes:
			if _botoes[nome]["dedo"] == e.index:
				_botoes[nome]["dedo"] = -1
				_soltar(nome)
	queue_redraw()


func _arrasto(e: InputEventScreenDrag) -> void:
	if e.index == _joy_dedo:
		var raio := RAIO_JOY * _escala
		var d := (e.position - _joy_centro).limit_length(raio)
		_joy_pos = _joy_centro + d
		sampler.touch_move = Vector2(d.x, -d.y) / raio   # para cima = frente
		queue_redraw()
	elif camera and (e.index == _olhar_dedo or (_botoes.has("atirar") and _botoes["atirar"]["dedo"] == e.index)):
		# arrastar o dedo no botão Atirar também mira (padrão de jogos de toque)
		camera.add_look(e.relative * float(Settings.get_value("controls", "touch_sensitivity")) * 1.4)


## Botões de construção só aparecem no modo construção (e Recarga some nele).
func _visivel(nome: String) -> bool:
	var em_construcao := construcao != null and (construcao.ativo or construcao.editando >= 0)
	if _botoes[nome].get("so_construcao", false):
		return em_construcao
	return not (em_construcao and nome == "recarregar")


func _apertar(nome: String) -> void:
	if construcao:
		match nome:
			"construir":
				construcao.set_active(not construcao.ativo)
				return
			"peca":
				construcao.select_piece(construcao.escolha + 1)
				return
			"material":
				construcao.next_material()
				return
			"editar":
				if construcao.editando >= 0:
					construcao.confirm_edit()
				else:
					construcao.start_edit()
				return
			"atirar":
				if construcao.editando >= 0:
					construcao.toggle_tile()
					return
	match nome:
		"pular":
			sampler.touch_jump = true
		"agachar":
			sampler.touch_crouch = not sampler.touch_crouch
		"atirar":
			sampler.touch_fire = true
		"recarregar":
			sampler.touch_reload = true
		"interagir":
			sampler.touch_interact = true
		"mochila":
			inventory_pressed.emit()


func _soltar(nome: String) -> void:
	match nome:
		"atirar":
			sampler.touch_fire = false
		"interagir":
			sampler.touch_interact = false


func _draw() -> void:
	var fonte: Font = theme.default_font if theme and theme.default_font else get_theme_default_font()
	if _joy_dedo != -1:
		var raio := RAIO_JOY * _escala
		draw_circle(_joy_centro, raio, Color(1, 1, 1, 0.18))
		draw_arc(_joy_centro, raio, 0, TAU, 48, Color(1, 1, 1, 0.5), 3.0)
		draw_circle(_joy_pos, raio * 0.42, Color(VentaniaTheme.AMARELO, 0.9))
		draw_arc(_joy_pos, raio * 0.42, 0, TAU, 32, VentaniaTheme.TINTA, 3.0, true)
	else:
		var p := Vector2(size.x * 0.16, size.y * 0.72)
		draw_arc(p, RAIO_JOY * _escala, 0, TAU, 48, Color(1, 1, 1, 0.25), 3.0)
		draw_string(fonte, p + Vector2(-60, 6), "Mover", HORIZONTAL_ALIGNMENT_CENTER, 120, 20, Color(1, 1, 1, 0.5))
	for nome in _botoes:
		if not _visivel(nome):
			continue
		var b: Dictionary = _botoes[nome]
		var ativo: bool = b["dedo"] != -1 or (nome == "agachar" and sampler and sampler.touch_crouch)
		# redesign: disco escuro translúcido com contorno grosso; Atirar em amarelo (ação principal)
		var principal: bool = nome == "atirar"
		var fundo := Color(VentaniaTheme.AMARELO, 0.92 if ativo else 0.78) if principal else (Color(VentaniaTheme.NOITE_CLARA, 0.9) if ativo else Color(VentaniaTheme.NOITE, 0.55))
		draw_circle(b["centro"] + Vector2(0, 4), b["raio"], Color(VentaniaTheme.TINTA, 0.45))
		draw_circle(b["centro"], b["raio"], fundo)
		draw_arc(b["centro"], b["raio"] - 1.5, 0, TAU, 48, VentaniaTheme.TINTA if principal else Color(1, 1, 1, 0.75 if ativo else 0.45), 3.0, true)
		var cor_txt := VentaniaTheme.TINTA if principal else Color.WHITE
		draw_string(VentaniaTheme.FONTE_FORTE, b["centro"] + Vector2(-b["raio"], 7), b["texto"], HORIZONTAL_ALIGNMENT_CENTER, b["raio"] * 2, int(19 * _escala), cor_txt)

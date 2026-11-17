class_name VitrineCosmetico
extends SubViewportContainer
## Visualizador 3D de um cosmético com o MODELO REAL do jogo (o mesmo da partida):
## arraste (mouse ou dedo) para girar; enquadramentos "corpo", "rosto" e "costas"
## para trajes. Gira sozinho devagar até a pessoa mexer. Traje inclui o efeito
## (TrajeFx: aquário com peixes e bolhas etc.).

const CORES := {"comum": Color("8a93a8"), "incomum": Color("3fbf74"), "raro": Color("3a8ee6"),
		"epico": Color("9b5de5"), "lendario": Color("f2a33a"), "mitico": Color("ff6fd0")}
## posição da câmera / ponto olhado / rotação base, por enquadramento de traje
const QUADROS := {
	"corpo": [Vector3(0.0, 1.2, 4.6), Vector3(0, 1.02, 0), 0.0],
	"rosto": [Vector3(0.0, 1.8, 1.6), Vector3(0, 1.72, 0), 0.0],
	"costas": [Vector3(0.0, 1.2, 4.6), Vector3(0, 1.02, 0), PI],
}

var categoria := ""
var _giro: Node3D
var _cam: Camera3D
var _alvo_cam := Vector3.ZERO
var _alvo_olhar := Vector3.ZERO
var _olhar := Vector3.ZERO
var _rot := -0.4
var _rot_alvo := -0.4
var _auto := true
var _arrastando := false


static func criar(item_id: String, cat: String, raridade: String) -> VitrineCosmetico:
	var v := VitrineCosmetico.new()
	v.categoria = cat
	v.stretch = true
	v._montar(item_id, raridade)
	return v


func _montar(item_id: String, raridade: String) -> void:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	add_child(vp)
	var cor: Color = CORES.get(raridade, CORES["comum"])
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = cor.darkened(0.55)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d6dcff")
	env.ambient_light_energy = 0.65
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-30, -35, 0)
	sol.light_energy = 1.05
	vp.add_child(sol)
	var contra := DirectionalLight3D.new()
	contra.rotation_degrees = Vector3(-15, 150, 0)
	contra.light_energy = 0.7
	contra.light_color = cor.lightened(0.4)
	vp.add_child(contra)
	var painel := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(12, 12)
	painel.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = load("res://ui/shared/fundo_cosmetico.gdshader")
	mat.set_shader_parameter("cor", cor)
	painel.material_override = mat
	painel.position = Vector3(0, 1.0, -3.0)
	vp.add_child(painel)
	_giro = Node3D.new()
	vp.add_child(_giro)
	_cam = Camera3D.new()
	_cam.fov = 30
	vp.add_child(_cam)
	var cena := ""
	match categoria:
		"traje":
			cena = Cosmeticos.outfit_scene(item_id)
		"picareta":
			cena = Cosmeticos.pickaxe_scene(item_id)
		"planador":
			cena = Cosmeticos.glider_scene(item_id)
	if cena == "" or not ResourceLoader.exists(cena):
		return
	var m := (load(cena) as PackedScene).instantiate() as Node3D
	_giro.add_child(m)
	match categoria:
		"traje":
			var aps := m.find_children("*", "AnimationPlayer", true, false)
			if not aps.is_empty():
				(aps[0] as AnimationPlayer).play("idle")
			TrajeFx.attach(m, item_id)
			enquadrar("corpo", true)
		"picareta":
			m.rotation_degrees = Vector3(0, 0, -32)
			encaixar(m, 1.75, Vector3(0, 1.05, 0))
			_rot = 1.22
			_rot_alvo = _rot
			_definir_camera(Vector3(0, 1.05, 4.6), Vector3(0, 1.05, 0), true)
		"planador":
			m.rotation_degrees = Vector3(-38, 0, 8)
			encaixar(m, 2.0, Vector3(0, 1.05, 0))
			_rot = 0.49
			_rot_alvo = _rot
			_definir_camera(Vector3(0, 1.15, 5.0), Vector3(0, 1.05, 0), true)


## "corpo", "rosto" ou "costas" (só trajes). Transição suave.
func enquadrar(nome: String, imediato := false) -> void:
	var q: Array = QUADROS.get(nome, QUADROS["corpo"])
	_definir_camera(q[0], q[1], imediato)
	_auto = nome == "corpo"
	_rot_alvo = q[2] + (-0.4 if nome == "corpo" else 0.0)
	if imediato:
		_rot = _rot_alvo


func _definir_camera(pos: Vector3, olhar: Vector3, imediato: bool) -> void:
	_alvo_cam = pos
	_alvo_olhar = olhar
	if imediato:
		_olhar = olhar
		_cam.transform = Transform3D(Basis(), pos).looking_at(olhar)


func _process(delta: float) -> void:
	if _giro == null:
		return
	if _auto and not _arrastando:
		_rot_alvo += delta * 0.6
	_rot = lerpf(_rot, _rot_alvo, 1.0 - exp(-delta * 10.0))
	_giro.rotation.y = _rot
	var k := 1.0 - exp(-delta * 7.0)
	_cam.position = _cam.position.lerp(_alvo_cam, k)
	_olhar = _olhar.lerp(_alvo_olhar, k)
	_cam.look_at(_olhar)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_arrastando = e.pressed
		if e.pressed:
			_auto = false
		accept_event()
	elif e is InputEventScreenTouch:
		_arrastando = e.pressed
		_auto = false
		accept_event()
	elif e is InputEventMouseMotion and _arrastando:
		_rot_alvo += e.relative.x * 0.012
		accept_event()
	elif e is InputEventScreenDrag:
		_rot_alvo += e.relative.x * 0.012
		accept_event()


## Escala e centraliza um modelo (já girado) para caber em `tamanho` metros, centrado em `alvo`.
static func encaixar(m: Node3D, tamanho: float, alvo: Vector3) -> void:
	var caixa := AABB()
	var primeira := true
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var t := _relativo(m, mi as Node3D)
		var b: AABB = (Transform3D(m.basis, Vector3.ZERO) * t) * (mi as MeshInstance3D).get_aabb()
		caixa = b if primeira else caixa.merge(b)
		primeira = false
	if primeira:
		return
	var k := tamanho / maxf(caixa.size.x, caixa.size.y)
	m.scale = Vector3.ONE * k
	m.position = alvo - caixa.get_center() * k


## Transformação de `filho` relativa a `raiz` (funciona fora da árvore).
static func _relativo(raiz: Node3D, filho: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = filho
	while n != null and n != raiz:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## Imagem de apresentação gerada do modelo real (tests/gerar_imagens_loja.gd), ou null.
static func imagem(item_id: String) -> Texture2D:
	var p := "res://assets/ui/loja/%s.png" % item_id
	return load(p) as Texture2D if ResourceLoader.exists(p) else null


static func nome_categoria(cat: String) -> String:
	return {"traje": "TRAJE", "picareta": "PICARETA", "planador": "PLANADOR", "emote": "EMOTE",
			"mochila": "MOCHILA", "acessorio": "ACESSÓRIO"}.get(cat, cat.to_upper())

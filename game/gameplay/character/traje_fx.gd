class_name TrajeFx
extends Node3D
## Efeitos cosméticos de um traje (só aparência, nenhum efeito no gameplay).
## "aquario" (Capitão Maré): três peixinhos nadando em círculos dentro do
## aquário da cabeça, bolhas subindo do tubo de ar e a água reagindo ao
## movimento (parâmetro por instância do shader M_agua_ventania).
## Barato: 3 malhas pequenas + 1 CPUParticles3D com poucas partículas.

const PEIXES := ["res://assets/mochilas_acessorios/peixe_laranja_01.glb", "res://assets/mochilas_acessorios/peixe_amarelo_01.glb",
		"res://assets/mochilas_acessorios/peixe_laranja_01.glb"]
## Interior do aquário no espaço do osso Head (origem no pescoço, Y para cima):
## largura 0,40 (x), profundidade 0,30 (z), água de 0,03 a 0,29 m acima da base.
const CENTRO := Vector3(0, 0.17, 0)
const RAIO := Vector2(0.13, 0.08)

var tipo := ""
var velocidade := Vector3.ZERO        # do personagem (o PawnVisual atualiza); a água reage
var _peixes: Array[Node3D] = []
var _fases: Array[float] = []
var _malha: GeometryInstance3D
var _t := 0.0
var _mov := Vector2.ZERO


## Procura o efeito do traje e o prende ao modelo. Retorna o nó (ou null).
static func attach(modelo: Node3D, traje: String) -> TrajeFx:
	var tipo_fx: String = Cosmeticos.config().get("efeitos", {}).get(traje, "")
	if tipo_fx.is_empty() or modelo == null:
		return null
	var sk := modelo.find_children("*", "Skeleton3D", true, false)
	if sk.is_empty():
		return null
	var esq := sk[0] as Skeleton3D
	var anexo := BoneAttachment3D.new()
	anexo.bone_name = "Head"
	esq.add_child(anexo)
	var fx := TrajeFx.new()
	fx.tipo = tipo_fx
	anexo.add_child(fx)
	var malhas := modelo.find_children("*", "MeshInstance3D", true, false)
	if not malhas.is_empty():
		fx._malha = malhas[0] as GeometryInstance3D
	return fx


func _ready() -> void:
	if tipo != "aquario":
		return
	for i in PEIXES.size():
		var p := (load(PEIXES[i]) as PackedScene).instantiate() as Node3D
		add_child(p)
		_peixes.append(p)
		_fases.append(i * TAU / PEIXES.size() + randf() * 0.4)
	var bolhas := CPUParticles3D.new()
	bolhas.amount = 6
	bolhas.lifetime = 1.4
	bolhas.position = Vector3(0.13, 0.03, -0.08)
	bolhas.direction = Vector3.UP
	bolhas.spread = 8.0
	bolhas.initial_velocity_min = 0.12
	bolhas.initial_velocity_max = 0.18
	bolhas.gravity = Vector3.ZERO
	bolhas.scale_amount_min = 0.6
	bolhas.scale_amount_max = 1.2
	var esfera := SphereMesh.new()
	esfera.radius = 0.008
	esfera.height = 0.016
	esfera.radial_segments = 6
	esfera.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.98, 1.0, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	esfera.material = mat
	bolhas.mesh = esfera
	bolhas.local_coords = true
	add_child(bolhas)


func _process(delta: float) -> void:
	if tipo != "aquario":
		return
	_t += delta
	# peixes: elipses em alturas diferentes, virando na direção em que nadam
	for i in _peixes.size():
		var f := _fases[i] + _t * (0.9 + 0.25 * i) * (1 if i % 2 == 0 else -1)
		var pos := CENTRO + Vector3(cos(f) * RAIO.x, 0.05 * sin(_t * 1.3 + i) + (i - 1) * 0.045, sin(f) * RAIO.y)
		var dir := Vector3(-sin(f), 0, cos(f)) * (1 if i % 2 == 0 else -1)
		var p := _peixes[i]
		p.position = pos - Vector3(_mov.x, 0, _mov.y) * 0.03       # ficam um pouco "para trás" quando o corpo acelera
		p.basis = Basis.looking_at(-dir, Vector3.UP).rotated(dir, sin(_t * 9.0 + i) * 0.25)
	# água: reage à velocidade local (suavizada)
	var v := Vector2(clampf(velocidade.x / 7.0, -1, 1), clampf(velocidade.z / 7.0, -1, 1))
	_mov = _mov.lerp(v, clampf(delta * 3.0, 0.0, 1.0))
	if _malha:
		_malha.set_instance_shader_parameter("movimento", _mov)

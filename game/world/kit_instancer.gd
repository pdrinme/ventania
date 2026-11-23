class_name KitInstancer
extends RefCounted
## Coloca muitas cópias de assets estáticos do kit (construções, árvores, pedras)
## de forma barata para hardware modesto:
##  - colisão: um StaticBody3D por cópia, com as FORMAS COMPARTILHADAS do GLB
##    (servidor e cliente; meta "material" para o golpe da picareta);
##  - visual (só cliente): um MultiMeshInstance3D por (malha, região de REGIAO m),
##    com distância de visibilidade — poucas chamadas de desenho e corte por região.
## O asset é carregado e "desmontado" uma única vez.

const REGIAO := 100.0
## Decoração sem colisão que o perfil gráfico pode rarear (densidade da vegetação):
## esconder instâncias com colisão deixaria obstáculos invisíveis, então árvores e
## pedras ficam sempre.
const VEGETACAO_DECOR := ["arbusto_01", "arbusto_02", "girassol_01", "flores_01", "grama_01", "pedra_03"]

var com_visual := true
var distancia_visivel := 320.0
var _cache := {}                    # caminho -> {"malhas": [[Mesh, Transform3D]], "formas": [[Shape3D, Transform3D]]}
var _grupos := {}                   # "caminho|malha|rx|rz" -> {"mesh", "xforms": []}
var _pai: Node3D
var corpos := 0


func _init(pai: Node3D, visual := true) -> void:
	_pai = pai
	com_visual = visual


func _desmontar(caminho: String) -> Dictionary:
	if _cache.has(caminho):
		return _cache[caminho]
	var cena := (load(caminho) as PackedScene).instantiate() as Node3D
	var d := {"malhas": [], "formas": []}
	_coletar(cena, Transform3D(), d)
	cena.free()
	_cache[caminho] = d
	return d


func _coletar(n: Node, acumulado: Transform3D, d: Dictionary) -> void:
	for c in n.get_children():
		var t := acumulado
		if c is Node3D:
			t = acumulado * (c as Node3D).transform
		if c is MeshInstance3D and (c as MeshInstance3D).mesh:
			var mi := c as MeshInstance3D
			# distância de visibilidade do próprio asset (metadado visibilidade_m, ver
			# post_import.gd) e sombra: a mobília só aparece de perto e não projeta sombra
			d["malhas"].append([mi.mesh, t, mi.visibility_range_end, mi.cast_shadow])
		elif c is CollisionShape3D and (c as CollisionShape3D).shape:
			d["formas"].append([(c as CollisionShape3D).shape, t])
		_coletar(c, t, d)


## Coloca uma cópia. material: ImpactMaterial.* (gravado no corpo de colisão).
func place(caminho: String, xform: Transform3D, material: int) -> void:
	var d := _desmontar(caminho)
	if not d["formas"].is_empty():
		var corpo := StaticBody3D.new()
		corpo.transform = xform
		corpo.set_meta("material", material)
		for f in d["formas"]:
			var cs := CollisionShape3D.new()
			cs.shape = f[0]
			cs.transform = f[1]
			corpo.add_child(cs)
		_pai.add_child(corpo)
		corpos += 1
	if not com_visual:
		return
	var rx := floori(xform.origin.x / REGIAO)
	var rz := floori(xform.origin.z / REGIAO)
	for i in d["malhas"].size():
		var chave := "%s|%d|%d|%d" % [caminho, i, rx, rz]
		if not _grupos.has(chave):
			_grupos[chave] = {"mesh": d["malhas"][i][0], "xforms": [], "vis": float(d["malhas"][i][2]), "sombra": d["malhas"][i][3],
					"vegetacao": caminho.get_file().get_basename() in VEGETACAO_DECOR and d["formas"].is_empty()}
		_grupos[chave]["xforms"].append(xform * d["malhas"][i][1])


## Cria os MultiMeshInstance3D (chamar depois de colocar tudo).
func build() -> int:
	var n := 0
	for g in _grupos.values():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = g["mesh"]
		var xforms: Array = g["xforms"]
		if g.get("vegetacao", false):
			# ordem embaralhada (determinística): rarear = esconder as últimas, espalhadas
			xforms.sort_custom(func(a, b): return hash(a.origin) < hash(b.origin))
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var vis: float = g.get("vis", 0.0)
		mmi.visibility_range_end = minf(distancia_visivel, vis) if vis > 0.0 else distancia_visivel
		mmi.set_meta("vis_base", mmi.visibility_range_end)
		mmi.set_meta("vegetacao", g.get("vegetacao", false))
		mmi.add_to_group("kit_visual")
		mmi.cast_shadow = g.get("sombra", GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
		mmi.visibility_range_end_margin = 20.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		_pai.add_child(mmi)
		n += 1
	_grupos.clear()
	return n

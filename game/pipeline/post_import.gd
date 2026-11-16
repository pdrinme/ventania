@tool
extends EditorScenePostImport
## Script de pós-importação aplicado a todos os GLB (configurado em
## [importer_defaults] do project.godot). Executado pela Godot ao importar.
##
## O que faz:
##  - Sombras: desliga cast_shadow de malhas pequenas (raio < LIMITE_SOMBRA_M)
##    e de nós cujo nome termina em "-noshadow". Sombras custam draw calls extras.
##  - Distância de visibilidade: se o nó tiver o metadado "visibilidade_m"
##    (propriedade customizada no Blender), aplica visibility_range_end.
##  - Grava em metadados da raiz: categoria (pela pasta) e estatísticas
##    (malhas, superfícies, triângulos) para ferramentas e testes.

const LIMITE_SOMBRA_M := 0.5
## Materiais exportados só pelo nome (sem textura) e trocados por um material
## compartilhado do projeto. Um material para o kit inteiro = menos trocas de estado na GPU.
const MATERIAIS_COMPARTILHADOS := {
	"M_paleta_ventania": "res://assets/texturas_materiais/M_paleta_ventania.tres",
}

var _malhas := 0
var _superficies := 0
var _tris := 0


func _post_import(cena: Node) -> Object:
	_malhas = 0
	_superficies = 0
	_tris = 0
	_percorrer(cena)
	var origem := get_source_file()  # ex.: res://assets/baus_coletaveis/x.glb
	var partes := origem.trim_prefix("res://assets/").split("/")
	cena.set_meta("categoria", partes[0] if partes.size() > 1 else "")
	cena.set_meta("stats", {"malhas": _malhas, "superficies": _superficies, "tris": _tris})
	return cena


func _percorrer(no: Node) -> void:
	if no is MeshInstance3D:
		_ajustar_malha(no)
	for filho in no.get_children():
		_percorrer(filho)


func _ajustar_malha(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	_malhas += 1
	_superficies += mi.mesh.get_surface_count()
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		_tris += (idx.size() if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		var mat := mi.mesh.surface_get_material(s)
		if mat and MATERIAIS_COMPARTILHADOS.has(mat.resource_name):
			var compartilhado := load(MATERIAIS_COMPARTILHADOS[mat.resource_name]) as Material
			if compartilhado:
				mi.mesh.surface_set_material(s, compartilhado)
			else:
				push_warning("Material compartilhado ausente: " + MATERIAIS_COMPARTILHADOS[mat.resource_name])

	var raio := mi.mesh.get_aabb().size.length() * 0.5
	if raio < LIMITE_SOMBRA_M or String(mi.name).ends_with("-noshadow"):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var extras = mi.get_meta("extras", {})
	if extras is Dictionary and extras.has("visibilidade_m"):
		mi.visibility_range_end = float(extras["visibilidade_m"])
		mi.visibility_range_end_margin = 2.0

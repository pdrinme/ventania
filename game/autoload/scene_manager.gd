extends Node
## Troca de telas com carregamento em segundo plano e tela de carregamento.
## Uso: SceneManager.go("menu")  ou  SceneManager.go("res://caminho/cena.tscn")

signal scene_changed(key: String)

const SCENES := {
	"boot": "res://scenes/boot/boot.tscn",
	"menu": "res://scenes/menu/main_menu.tscn",
	"settings": "res://scenes/settings/settings_menu.tscn",
	"diagnostics": "res://scenes/diagnostics/diagnostics.tscn",
}

var current := ""
var previous := ""
var _carregando := false
var _tela: CanvasLayer
var _barra: ProgressBar
var _texto: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_criar_tela_carregamento()


func go(key_or_path: String) -> bool:
	if _carregando:
		return false
	var path: String = SCENES.get(key_or_path, key_or_path)
	if not ResourceLoader.exists(path):
		Log.error("cenas", "cena não encontrada: " + path)
		return false
	_carregando = true
	var loader := AsyncLoader.new(path)
	var mostrar := not loader.done
	if mostrar:
		_tela.visible = true
		_texto.text = "Carregando…"
	while not loader.done:
		loader.poll()
		_barra.value = loader.progress * 100.0
		await get_tree().process_frame
	_carregando = false
	_tela.visible = false
	if loader.failed or not (loader.resource is PackedScene):
		Log.error("cenas", "falha ao carregar " + path)
		return false
	var err := get_tree().change_scene_to_packed(loader.resource)
	if err != OK:
		Log.error("cenas", "falha ao trocar para %s: %s" % [path, error_string(err)])
		return false
	previous = current
	current = key_or_path
	await get_tree().process_frame
	Settings.apply_to_world(get_tree().root)
	Log.info("cenas", "tela: " + key_or_path)
	scene_changed.emit(key_or_path)
	return true


func back(fallback := "menu") -> void:
	go(previous if not previous.is_empty() and previous != current else fallback)


func _criar_tela_carregamento() -> void:
	_tela = CanvasLayer.new()
	_tela.layer = 100
	_tela.visible = false
	add_child(_tela)
	var fundo := ColorRect.new()
	fundo.color = Color("167c84")
	fundo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tela.add_child(fundo)
	var caixa := VBoxContainer.new()
	caixa.set_anchors_preset(Control.PRESET_CENTER)
	caixa.custom_minimum_size = Vector2(420, 0)
	caixa.position = Vector2(-210, -40)
	_tela.add_child(caixa)
	_texto = Label.new()
	_texto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caixa.add_child(_texto)
	_barra = ProgressBar.new()
	_barra.custom_minimum_size = Vector2(420, 28)
	caixa.add_child(_barra)

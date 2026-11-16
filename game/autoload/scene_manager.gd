extends Node
## Troca de telas com carregamento em segundo plano e tela de carregamento.
## Uso: SceneManager.go("menu")  ou  SceneManager.go("res://caminho/cena.tscn")

signal scene_changed(key: String)

const SCENES := {
	"boot": "res://scenes/boot/boot.tscn",
	"menu": "res://scenes/menu/main_menu.tscn",
	"settings": "res://scenes/settings/settings_menu.tscn",
	"diagnostics": "res://scenes/diagnostics/diagnostics.tscn",
	"game": "res://scenes/game/game.tscn",
	"server": "res://scenes/server/server_main.tscn",
}

var current := ""
var params := {}          # parâmetros para a próxima tela (ex.: modo da partida)
var message := ""         # mensagem para mostrar na próxima tela (ex.: erro de conexão)
var previous := ""
var _carregando := false
var _tela: CanvasLayer
var _barra: ProgressBar
var _texto: Label
var _fps: Label
var _fps_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_criar_tela_carregamento()
	_criar_fps()


func go(key_or_path: String, p := {}) -> bool:
	if _carregando:
		return false
	params = p
	# camadas do SceneManager ficam fora da árvore de Controls: aplicar o tema atual
	for c in _tela.get_children() + [_fps]:
		if c is Control:
			(c as Control).theme = get_tree().root.theme
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


## Contador de FPS no canto da tela (opção "Mostrar FPS").
func set_fps_visible(v: bool) -> void:
	if _fps:
		_fps.get_parent().visible = v


func _process(delta: float) -> void:
	if _fps == null or not _fps.get_parent().visible:
		return
	_fps_t += delta
	if _fps_t >= 0.5:
		_fps_t = 0.0
		_fps.text = "%d FPS" % Engine.get_frames_per_second()


func _criar_fps() -> void:
	var camada := CanvasLayer.new()
	camada.layer = 90
	add_child(camada)
	_fps = Label.new()
	_fps.position = Vector2(8, 4)
	_fps.add_theme_color_override("font_color", Color("ffc93c"))
	_fps.add_theme_color_override("font_outline_color", Color("24252c"))
	_fps.add_theme_constant_override("outline_size", 6)
	_fps.add_theme_font_size_override("font_size", 18)
	_fps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	camada.add_child(_fps)
	camada.visible = Settings.get_value("graphics", "show_fps")


func _criar_tela_carregamento() -> void:
	_tela = CanvasLayer.new()
	_tela.layer = 100
	_tela.visible = false
	add_child(_tela)
	var fundo := ColorRect.new()
	fundo.color = Color("167c84")
	fundo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tela.add_child(fundo)
	var caixa := VBoxContainer.new()
	caixa.custom_minimum_size = Vector2(420, 0)
	caixa.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	caixa.grow_horizontal = Control.GROW_DIRECTION_BOTH
	caixa.grow_vertical = Control.GROW_DIRECTION_BOTH
	_tela.add_child(caixa)
	_texto = Label.new()
	_texto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caixa.add_child(_texto)
	_barra = ProgressBar.new()
	_barra.custom_minimum_size = Vector2(420, 28)
	caixa.add_child(_barra)

extends MetaApi
## Conexão com o meta-servidor. Mantém o estado da conexão para a interface.

signal status_changed(state: String, info: Dictionary, error: String)

## "desconhecido" | "verificando" | "online" | "offline" | "incompatible"
var state := "desconhecido"
var info := {}
var last_error := ""


func _ready() -> void:
	base_url = Settings.get_value("network", "server_url")
	Settings.changed.connect(func(s, k, v):
		if s == "network" and k == "server_url":
			base_url = v)


func refresh() -> void:
	if state == "verificando":
		return
	_mudar_estado("verificando", {}, "")
	var r := await check_health()
	_mudar_estado(r["state"], r["info"], r["error"])
	if state == "online":
		Log.info("rede", "meta-servidor online: %s (versão %s)" % [base_url, info.get("server_version", "?")])
	else:
		Log.warn("rede", "meta-servidor %s: %s" % [state, last_error])


func _mudar_estado(s: String, i: Dictionary, e: String) -> void:
	state = s
	info = i
	last_error = e
	status_changed.emit(state, info, last_error)

extends SceneTree
## Integração: o cliente consulta um meta-servidor real.
## Uso: godot --headless --path game -s res://tests/integration/test_meta_health.gd -- http://127.0.0.1:PORTA


func _init() -> void:
	var url := "http://127.0.0.1:8080"
	if OS.get_cmdline_user_args().size() > 0:
		url = OS.get_cmdline_user_args()[0]
	var api := MetaApi.new()
	api.base_url = url
	root.add_child.call_deferred(api)
	await process_frame
	await process_frame
	var r: Dictionary = await api.check_health()
	var falhas := 0
	if r["state"] != "online":
		printerr("FALHA estado=%s erro=%s" % [r["state"], r["error"]])
		falhas += 1
	elif int(r["info"]["protocol_version"]) != Version.PROTOCOL:
		falhas += 1
	# porta sem servidor: deve dar offline, sem travar
	api.base_url = "http://127.0.0.1:9"
	var off: Dictionary = await api.check_health()
	if off["state"] != "offline":
		printerr("FALHA servidor ausente deveria ser offline: %s" % off)
		falhas += 1
	print("INTEGRACAO_META %s online=%s offline_ok=%s" % ["OK" if falhas == 0 else "FALHA", r["state"], off["state"] == "offline"])
	quit(1 if falhas else 0)

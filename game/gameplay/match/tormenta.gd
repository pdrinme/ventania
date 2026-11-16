class_name Tormenta
extends RefCounted
## A Tormenta (zona segura que encolhe). Determinística pela semente; o servidor
## avança um tick por vez e envia o estado (S_STORM); o cliente só interpola.
## Fases: espera -> fechamento (o círculo vai de "de" para "para") -> próxima.
## Depois da última fase, o círculo final fica parado (fase = fases.size()).

var fases: Array = []
var fase := 0
var fechando := false
var t := 0                          # ticks no subestado atual
var c_de := Vector2.ZERO
var r_de := 0.0
var c_para := Vector2.ZERO
var r_para := 0.0
var terminou := false
var _rng := RandomNumberGenerator.new()
var _valido: Callable               # (Vector2) -> bool: centro aceitável (ex.: em terra)
var _margem := 230.0


func _init(config: Dictionary, semente: int, valido := Callable()) -> void:
	fases = config["fases"]
	_margem = float(config.get("margem_terra", 230.0))
	_rng.seed = semente
	_valido = valido
	r_de = float(config["raio_inicial"])
	c_de = Vector2.ZERO
	_sortear_proxima()


func _ticks(s: float) -> int:
	return maxi(1, roundi(s * Protocol.TICK_RATE))


## Centro da próxima zona: dentro da zona atual, de modo que caiba inteira nela.
func _sortear_proxima() -> void:
	if fase >= fases.size():
		return
	r_para = float(fases[fase]["raio"])
	var folga := maxf(0.0, r_de - r_para)
	for i in 40:
		var ang := _rng.randf() * TAU
		var d := sqrt(_rng.randf()) * folga
		var c := c_de + Vector2(cos(ang), sin(ang)) * d
		if absf(c.x) > _margem or absf(c.y) > _margem:
			continue
		if _valido.is_valid() and not _valido.call(c):
			continue
		c_para = c
		return
	c_para = c_de


## Avança um tick. Retorna true quando o estado muda (fase/fechamento).
func update() -> bool:
	if terminou:
		return false
	t += 1
	var f: Dictionary = fases[fase]
	if not fechando and t >= _ticks(f["espera_s"]):
		fechando = true
		t = 0
		return true
	if fechando and t >= _ticks(f["fechamento_s"]):
		c_de = c_para
		r_de = r_para
		fechando = false
		t = 0
		fase += 1
		if fase >= fases.size():
			terminou = true
		else:
			_sortear_proxima()
		return true
	return false


## Fração do fechamento atual (0..1).
func progress() -> float:
	if not fechando or terminou:
		return 0.0
	return clampf(float(t) / _ticks(fases[fase]["fechamento_s"]), 0.0, 1.0)


## Círculo seguro atual: [centro, raio].
func current() -> Array:
	var k := progress()
	return [c_de.lerp(c_para, k), lerpf(r_de, r_para, k)]


func is_outside(pos: Vector3) -> bool:
	var c := current()
	return Vector2(pos.x, pos.z).distance_to(c[0]) > float(c[1])


## Dano por segundo da fase atual (a última continua depois do fim).
func damage_per_second() -> int:
	return int(fases[mini(fase, fases.size() - 1)]["dano"])


## Ticks até o próximo evento (fim da espera ou do fechamento).
func ticks_left() -> int:
	if terminou:
		return 0
	var f: Dictionary = fases[fase]
	return maxi(0, _ticks(f["fechamento_s"] if fechando else f["espera_s"]) - t)


func total_ticks() -> int:
	if terminou:
		return 0
	var f: Dictionary = fases[fase]
	return _ticks(f["fechamento_s"] if fechando else f["espera_s"])


func to_dict() -> Dictionary:
	var ms := 1000.0 / Protocol.TICK_RATE
	return {"fase": fase, "fases": fases.size(), "fechando": fechando, "terminou": terminou,
			"c_de": c_de, "r_de": r_de, "c_para": c_para, "r_para": r_para,
			"total_ms": roundi(total_ticks() * ms), "resta_ms": roundi(ticks_left() * ms), "dano": damage_per_second()}

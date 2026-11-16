class_name OnibusBatalha
extends RefCounted
## Ônibus de Batalha (o "Ônibus dos Ventos"): rota reta sobre a ilha, sorteada pelo
## servidor a cada partida e reproduzida igual no cliente pelo tick.
##  - Entra e sai sobre o mar; passa a até 80 m do centro (atravessa boa parte da ilha).
##  - Portas: abrem quando o ônibus está sobre terra e fecham um pouco antes de ele
##    deixar a ilha (quem não saltou é ejetado ali, ainda sobre terra).
##  - Altitude fixa, bem acima do ponto mais alto do mapa (nunca atravessa o relevo).

const VELOCIDADE := 20.0             # m/s
const ALTITUDE := 120.0
const META_TERRA := 240.0            # trecho mínimo sobre terra (m)

var inicio := Vector3.ZERO
var fim := Vector3.ZERO
var tick0 := 0                       # tick do servidor em que parte
var duracao := 1                     # ticks
var abre := 0                        # tick em que as portas abrem
var fecha := 0                       # tick em que as portas fecham (ejeta quem ficou)


## Sorteia uma rota válida para o mapa. `terra(x, z) -> bool`.
static func sortear(semente: int, tick_inicio: int, limite: float, terra: Callable) -> OnibusBatalha:
	var rng := RandomNumberGenerator.new()
	rng.seed = semente
	var o := OnibusBatalha.new()
	for tentativa in 60:
		var ang := rng.randf() * TAU
		var dir := Vector2(cos(ang), sin(ang))
		var lado := Vector2(-dir.y, dir.x)
		var meio := lado * rng.randf_range(-80.0, 80.0)
		var a := meio - dir * (limite + 40.0)
		var b := meio + dir * (limite + 40.0)
		o.inicio = Vector3(a.x, ALTITUDE, a.y)
		o.fim = Vector3(b.x, ALTITUDE, b.y)
		o.tick0 = tick_inicio
		o.duracao = maxi(1, roundi(a.distance_to(b) / VELOCIDADE * Protocol.TICK_RATE))
		# primeiro e último ponto sobre terra
		var primeiro := -1.0
		var ultimo := -1.0
		var n := 200
		for k in n + 1:
			var f := float(k) / n
			var p := a.lerp(b, f)
			if terra.call(p.x, p.y):
				if primeiro < 0.0:
					primeiro = f
				ultimo = f
		if primeiro < 0.0 or (ultimo - primeiro) * a.distance_to(b) < META_TERRA:
			continue
		o.abre = tick_inicio + roundi((primeiro + 0.01) * o.duracao)
		o.fecha = tick_inicio + roundi((ultimo - 0.03) * o.duracao)
		return o
	# reserva (mapa sem terra suficiente): portas o trajeto todo
	o.abre = o.tick0
	o.fecha = o.tick0 + o.duracao
	return o


func position_at(tick: float) -> Vector3:
	return inicio.lerp(fim, clampf((tick - tick0) / float(duracao), 0.0, 1.0))


func direction() -> Vector3:
	return inicio.direction_to(fim)


func doors_open(tick: float) -> bool:
	return tick >= abre and tick < fecha


func finished(tick: float) -> bool:
	return tick >= fecha


func to_dict() -> Dictionary:
	return {"inicio": inicio, "fim": fim, "tick0": tick0, "duracao": duracao, "abre": abre, "fecha": fecha}


static func from_dict(d: Dictionary) -> OnibusBatalha:
	var o := OnibusBatalha.new()
	o.inicio = d["inicio"]
	o.fim = d["fim"]
	o.tick0 = d["tick0"]
	o.duracao = d["duracao"]
	o.abre = d["abre"]
	o.fecha = d["fecha"]
	return o

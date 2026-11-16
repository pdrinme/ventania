class_name Combat
extends RefCounted
## Matemática do tiro, compartilhada por servidor (decide) e cliente (efeitos).

const EYE_STAND := 1.55       # = PlayerCamera.ALTURA_PE
const EYE_CROUCH := 1.05
const SHOULDER := 0.55        # = PlayerCamera.OMBRO


## Raio de mira: passa pelo ponto do ombro na direção da câmera, que é exatamente
## a linha da mira na tela (a câmera fica atrás desse ponto, na mesma reta).
static func aim_ray(pes: Vector3, agachado: bool, yaw: float, pitch: float) -> Dictionary:
	var base := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var origem := pes + Vector3(0, EYE_CROUCH if agachado else EYE_STAND, 0) + base * Vector3(SHOULDER, 0, 0)
	return {"origin": origem, "dir": (base * Vector3(0, 0, -1)).normalized()}


## Dispersão efetiva em graus para o estado do atirador.
static func spread_deg(arma: Dictionary, mirando: bool, movendo: bool, agachado: bool, no_chao: bool) -> float:
	var m: Dictionary = ItemDB.data()["modificadores_dispersao"]
	var d := float(arma["dispersao"])
	if mirando and arma.has("dispersao_mirando"):
		return float(arma["dispersao_mirando"])
	if mirando:
		d *= float(m["mirando"])
	if movendo:
		d *= float(m["movendo"])
	if agachado:
		d *= float(m["agachado"])
	if not no_chao:
		d *= float(m["no_ar"])
	return d


## Direções dos projéteis. Determinístico pela semente: cliente e servidor
## desenham/calculam os mesmos traçantes.
static func pellet_dirs(dir: Vector3, spread: float, n: int, semente: int) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = semente
	var out: Array[Vector3] = []
	var lado := dir.cross(Vector3.UP)
	if lado.length() < 0.01:
		lado = Vector3.RIGHT
	lado = lado.normalized()
	var cima := lado.cross(dir).normalized()
	for i in n:
		var ang := rng.randf() * TAU
		var r := sqrt(rng.randf()) * deg_to_rad(spread)   # distribuição uniforme no disco
		out.append((dir + (lado * cos(ang) + cima * sin(ang)) * tan(r)).normalized())
	return out


static func shot_seed(entity_id: int, seq: int) -> int:
	return entity_id * 1000003 + seq * 7919


## Dano final de um projétil.
static func pellet_damage(arma_id: String, raridade: int, cabeca: bool) -> int:
	var d := ItemDB.damage(arma_id, raridade)
	if cabeca:
		d *= float(ItemDB.weapon(arma_id)["cabeca"])
	return roundi(d)

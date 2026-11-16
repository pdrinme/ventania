class_name Hitbox
extends RefCounted
## Hitboxes analíticas (iguais para todos os trajes): cápsula do corpo + esfera da
## cabeça. O servidor testa o raio contra elas em posições "voltadas no tempo"
## (compensação de latência), sem mexer na física.

const BODY_RADIUS := 0.4
const HEAD_RADIUS := 0.25


## Pontos da cápsula do corpo e centro da cabeça, a partir da posição dos pés.
static func shape(pes: Vector3, agachado: bool) -> Dictionary:
	if agachado:
		return {"a": pes + Vector3(0, 0.35, 0), "b": pes + Vector3(0, 0.8, 0), "head": pes + Vector3(0, 1.1, 0)}
	return {"a": pes + Vector3(0, 0.4, 0), "b": pes + Vector3(0, 1.3, 0), "head": pes + Vector3(0, 1.62, 0)}


## Distância até a esfera ao longo do raio (dir normalizado) ou -1.
static func ray_sphere(origem: Vector3, dir: Vector3, centro: Vector3, raio: float) -> float:
	var oc := origem - centro
	var b := oc.dot(dir)
	var c := oc.dot(oc) - raio * raio
	var disc := b * b - c
	if disc < 0.0:
		return -1.0
	var t := -b - sqrt(disc)
	if t < 0.0:
		t = -b + sqrt(disc)   # origem dentro da esfera
	return t if t >= 0.0 else -1.0


## Distância até a cápsula (segmento a-b com raio) ou -1. Aproximada por esferas
## ao longo do eixo (espaçamento <= 15 cm, raio 40 cm: erro desprezível para tiro).
static func ray_capsule(origem: Vector3, dir: Vector3, a: Vector3, b: Vector3, raio: float) -> float:
	var n := maxi(2, ceili(a.distance_to(b) / 0.15) + 1)
	var melhor := -1.0
	for i in n:
		var t := ray_sphere(origem, dir, a.lerp(b, i / float(n - 1)), raio)
		if t >= 0.0 and (melhor < 0.0 or t < melhor):
			melhor = t
	return melhor


## Testa um alvo. Retorna {"t": distância, "head": bool} ou {} se errou.
static func test(origem: Vector3, dir: Vector3, pes: Vector3, agachado: bool) -> Dictionary:
	var f := shape(pes, agachado)
	var th := ray_sphere(origem, dir, f["head"], HEAD_RADIUS)
	var tb := ray_capsule(origem, dir, f["a"], f["b"], BODY_RADIUS)
	if th >= 0.0 and (tb < 0.0 or th <= tb + 0.1):
		return {"t": th, "head": true}
	if tb >= 0.0:
		return {"t": tb, "head": false}
	return {}

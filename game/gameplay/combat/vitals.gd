class_name Vitals
extends RefCounted
## Vida e escudo de um jogador. Dano consome o escudo primeiro.

const MAX_HEALTH := 100
const MAX_SHIELD := 100

var health := MAX_HEALTH
var shield := 0


func alive() -> bool:
	return health > 0


## Retorna {"shield": dano no escudo, "health": dano na vida, "killed": bool}.
func take_damage(amount: int) -> Dictionary:
	if not alive() or amount <= 0:
		return {"shield": 0, "health": 0, "killed": false}
	var no_escudo := mini(shield, amount)
	shield -= no_escudo
	var na_vida := mini(health, amount - no_escudo)
	health -= na_vida
	return {"shield": no_escudo, "health": na_vida, "killed": health <= 0}


## Cura até `limite`. Retorna quanto curou.
func heal(amount: int, limite: int) -> int:
	if not alive() or health >= limite:
		return 0
	var n := mini(amount, limite - health)
	health += n
	return n


func add_shield(amount: int, limite: int) -> int:
	if not alive() or shield >= limite:
		return 0
	var n := mini(amount, limite - shield)
	shield += n
	return n


func reset() -> void:
	health = MAX_HEALTH
	shield = 0


## Dano da Tormenta: ignora o escudo (vai direto na vida).
func take_storm_damage(amount: int) -> bool:
	if not alive() or amount <= 0:
		return false
	health = maxi(0, health - amount)
	return health <= 0

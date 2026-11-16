class_name ImpactMaterial
extends RefCounted
## Material do que um golpe/tiro atingiu (efeitos e, na Etapa 5, recursos e dano
## por material). O mapa marca cada peça com a meta "material" no nó raiz do
## asset; os corpos de colisão importados são filhos dele.

enum { NENHUM, MADEIRA, PEDRA, METAL, JOGADOR, TERRA }

const NOMES := ["nenhum", "madeira", "pedra", "metal", "jogador", "terra"]


## Material pelo id do asset (ex.: "parede_madeira", "pinheiro_01", "pedra_01").
static func from_asset(id: String) -> int:
	if id.contains("metal"):
		return METAL
	if id.contains("pedra") or id.contains("rocha"):
		return PEDRA
	if id.contains("madeira") or id.contains("arvore") or id.contains("pinheiro") or id.contains("bau") \
			or id.contains("cerca") or id.contains("caixote") or id.contains("arbusto"):
		return MADEIRA
	return NENHUM


## Sobe na árvore a partir do corpo atingido procurando a meta "material".
static func of(collider: Object) -> int:
	var n := collider as Node
	for i in 6:
		if n == null:
			break
		if n.has_meta("material"):
			return int(n.get_meta("material"))
		n = n.get_parent()
	return NENHUM


static func name_of(m: int) -> String:
	return NOMES[m] if m >= 0 and m < NOMES.size() else "nenhum"

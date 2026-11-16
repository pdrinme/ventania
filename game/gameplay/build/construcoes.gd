class_name Construcoes
extends RefCounted
## Estado das construções (peças do mapa e dos jogadores). O servidor é a
## autoridade; o cliente mantém uma cópia igual, aplicando só o que o servidor
## manda (S_PIECE, S_PIECE_GONE, S_PIECES_HP). Os testes comparam as duas.

class Peca:
	var id := 0
	var tipo := 0                   # Grade.PAREDE_X…TETO
	var cell := Vector3i.ZERO
	var rot := 0
	var material := 0               # 0 madeira, 1 pedra, 2 metal
	var dono := 0                   # id do jogador; 0 = peça do mapa
	var hp := 0.0
	var hp_max := 1.0
	var obra := 0.0                 # 1 = começando a construir, 0 = pronta
	var mask := 0                   # ladrilhos presentes (edição); 0 = não editável
	var ancorada := false

	func slot() -> Vector4i:
		return Grade.key(tipo, cell)

	func damage_frac() -> float:
		return clampf(1.0 - hp / maxf(1.0, hp_max), 0.0, 1.0)

	func edited() -> bool:
		return mask != Grade.full_mask(tipo)

	func to_dict() -> Dictionary:
		return {"id": id, "tipo": tipo, "cell": cell, "rot": rot, "material": material, "dono": dono,
				"hp": hp, "hp_max": hp_max, "obra": obra, "mask": mask}

var pecas := {}                     # id -> Peca
var por_slot := {}                  # Vector4i -> id
var por_aresta := {}                # aresta (int) -> Array[id]
var _dos_jogadores := 0             # contagem mantida (limite de peças sem percorrer tudo)


static func max_hp(material: int) -> float:
	return float(Grade.config()["materiais"][Grade.MATERIAIS[clampi(material, 0, 2)]]["vida_max"])


func count_players() -> int:
	return _dos_jogadores


func occupied(tipo: int, cell: Vector3i) -> bool:
	return por_slot.has(Grade.key(tipo, cell))


func add(p: Peca) -> void:
	pecas[p.id] = p
	if p.dono != 0:
		_dos_jogadores += 1
	por_slot[p.slot()] = p.id
	for e in Grade.edges(p.tipo, p.cell, p.rot):
		if not por_aresta.has(e):
			por_aresta[e] = []
		por_aresta[e].append(p.id)


func remove(id: int) -> Peca:
	var p: Peca = pecas.get(id)
	if p == null:
		return null
	pecas.erase(id)
	if p.dono != 0:
		_dos_jogadores -= 1
	por_slot.erase(p.slot())
	for e in Grade.edges(p.tipo, p.cell, p.rot):
		var l: Array = por_aresta.get(e, [])
		l.erase(id)
		if l.is_empty():
			por_aresta.erase(e)
	return p


func neighbors(id: int) -> Array:
	var p: Peca = pecas.get(id)
	var out := {}
	if p == null:
		return []
	for e in Grade.edges(p.tipo, p.cell, p.rot):
		for o in por_aresta.get(e, []):
			if o != id:
				out[o] = true
	return out.keys()


## Uma peça nova num slot pode ser colocada se estiver ancorada ou tocar outra peça.
func would_be_supported(tipo: int, cell: Vector3i, rot: int, ancorada: bool) -> bool:
	if ancorada:
		return true
	for e in Grade.edges(tipo, cell, rot):
		if not por_aresta.get(e, []).is_empty():
			return true
	return false


## Depois de remover peças, quais ficaram sem caminho até uma peça ancorada.
## `vizinhos`: peças que tocavam as removidas. Busca em largura, parando cedo
## quando acha uma âncora. Retorna os ids que devem desabar.
func unsupported(vizinhos: Array) -> Array:
	var condenadas := {}
	var seguras := {}
	for inicio in vizinhos:
		if not pecas.has(inicio) or condenadas.has(inicio) or seguras.has(inicio):
			continue
		var visitadas := {inicio: true}
		var fila := [inicio]
		var achou := false
		while not fila.is_empty() and not achou:
			var id: int = fila.pop_front()
			if pecas[id].ancorada or seguras.has(id):
				achou = true
				break
			for v in neighbors(id):
				if not visitadas.has(v):
					visitadas[v] = true
					fila.append(v)
		for id in visitadas:
			if achou:
				seguras[id] = true
			else:
				condenadas[id] = true
	return condenadas.keys()


## Resumo comparável (testes de divergência entre servidor e clientes).
func snapshot() -> Dictionary:
	var out := {}
	for p: Peca in pecas.values():
		out[p.id] = [p.tipo, p.cell, p.rot, p.material, p.mask, roundi(p.hp)]
	return out

class_name BuildServer
extends RefCounted
## Construção no servidor (autoridade): cria, edita, danifica e destrói peças,
## faz as sem apoio desabarem (em lotes por tick) e envia tudo aos clientes.
## As peças do mapa (casas da ilha) são do mesmo sistema: ids 1..N gerados de forma
## determinística pelo mapa (o cliente gera as mesmas), destrutíveis e restauradas
## a cada partida nova. Cada peça tem um StaticBody3D na camada do mundo, com a
## meta "peca_id" (tiros e picareta sabem o que atingiram).

var server: GameServer
var estado := Construcoes.new()
var corpos := {}                    # id -> StaticBody3D
var cfg: Dictionary
var _mapa_n := 0                    # peças do mapa (ids 1.._mapa_n)
var _proximo := 1
var _mudaram := {}                  # ids com vida/obra alterada (lote S_PIECES_HP)
var _desabar: Array = []            # fila de ids para desabar
var _em_obra := {}                  # ids ainda crescendo (o tick só passa por elas)
var construidas := 0                # diagnóstico/testes
var destruidas := 0
var desabaram := 0


func _init(s: GameServer) -> void:
	server = s
	cfg = Grade.config()


func _altura() -> Callable:
	var m := server.world
	return func(x: float, z: float) -> float: return m.ground_height(x, z)


## Cria (ou recria) as construções do mapa com vida cheia.
func init_map() -> void:
	var lista := server.world.building_pieces()
	_mapa_n = lista.size()
	for i in lista.size():
		var d: Dictionary = lista[i]
		var p := _nova(i + 1, d["tipo"], d["cell"], d["rot"], d["material"], 0)
		p.mask = d.get("mask", p.mask)      # portas e janelas das casas do mapa
		p.hp = p.hp_max
		p.obra = 0.0
		estado.add(p)
		_corpo(p)
	_proximo = _mapa_n + 1


func _nova(id: int, tipo: int, cell: Vector3i, rot: int, material: int, dono: int) -> Construcoes.Peca:
	var p := Construcoes.Peca.new()
	p.id = id
	p.tipo = tipo
	p.cell = cell
	p.rot = rot
	p.material = material
	p.dono = dono
	p.hp_max = Construcoes.max_hp(material)
	p.mask = Grade.full_mask(tipo)
	p.ancorada = Grade.anchored(tipo, cell, rot, _altura())
	return p


## Corpo de colisão: formas do kit (peça inteira) ou caixas dos ladrilhos (editada).
static func make_body(p: Construcoes.Peca) -> StaticBody3D:
	var corpo := StaticBody3D.new()
	corpo.transform = Grade.transform(p.tipo, p.cell, p.rot)
	corpo.set_meta("peca_id", p.id)
	corpo.set_meta("material", [ImpactMaterial.MADEIRA, ImpactMaterial.PEDRA, ImpactMaterial.METAL][p.material])
	if p.edited():
		for t in Grade.tile_boxes(p.tipo, p.mask):
			var cs := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			bx.size = t[1]
			cs.shape = bx
			cs.position = t[0]
			corpo.add_child(cs)
	else:
		for f in Grade.kit(Grade.asset_path(p.tipo, p.material))["formas"]:
			var cs := CollisionShape3D.new()
			cs.shape = f[0]
			cs.transform = f[1]
			corpo.add_child(cs)
	return corpo


func _corpo(p: Construcoes.Peca) -> void:
	if corpos.has(p.id):
		(corpos[p.id] as Node).free()
	var c := make_body(p)
	server.world.add_child(c)
	corpos[p.id] = c


# ---------------- pedidos dos jogadores ----------------

func try_build(c: GameServer.Cliente, b: Dictionary) -> int:
	if c.dead or c.pawn == null:
		return Inventory.Err.INVALID
	var tipo := Grade.slot_type(b["escolha"], b["rot"])
	var cell: Vector3i = b["cell"]
	var mat_nome: String = Grade.MATERIAIS[b["material"]]
	var custo := int(cfg["custo"])
	if c.pawn.global_position.distance_to(Grade.center(tipo, cell)) > float(cfg["alcance"]):
		return Inventory.Err.TOO_FAR
	if estado.occupied(tipo, cell):
		return Inventory.Err.OCCUPIED
	if estado.count_players() >= int(cfg["limite_pecas"]):
		return Inventory.Err.PIECE_LIMIT
	if int(c.inv.materials.get(mat_nome, 0)) < custo:
		return Inventory.Err.NO_MATERIAL
	var rot: int = b["rot"]
	var p := _nova(_proximo, tipo, cell, rot, b["material"], c.id)
	if not estado.would_be_supported(tipo, cell, rot, p.ancorada):
		return Inventory.Err.NO_SUPPORT
	_proximo += 1
	c.inv.materials[mat_nome] -= custo
	c.dirty = true
	p.hp = p.hp_max * float(cfg["materiais"][mat_nome]["vida_inicial"])
	p.obra = 1.0
	_em_obra[p.id] = true
	estado.add(p)
	_corpo(p)
	construidas += 1
	server.broadcast(Protocol.pack_piece(p.to_dict()), true)
	return Inventory.Err.OK


func try_edit(c: GameServer.Cliente, id: int, mask: int) -> int:
	var p: Construcoes.Peca = estado.pecas.get(id)
	if p == null:
		return Inventory.Err.GONE
	if p.dono != c.id:
		return Inventory.Err.NOT_OWNER
	if not Grade.valid_mask(p.tipo, mask):
		return Inventory.Err.INVALID
	if c.pawn.global_position.distance_to(Grade.center(p.tipo, p.cell)) > float(cfg["alcance"]):
		return Inventory.Err.TOO_FAR
	if mask == p.mask:
		return Inventory.Err.OK
	p.mask = mask
	_corpo(p)
	server.broadcast(Protocol.pack_piece(p.to_dict()), true)
	return Inventory.Err.OK


# ---------------- dano, coleta e destruição ----------------

## Dano numa peça. quem: jogador (0 = ambiente). Retorna true se destruiu.
func damage(id: int, quanto: float, quem: GameServer.Cliente = null, picareta := false) -> bool:
	var p: Construcoes.Peca = estado.pecas.get(id)
	if p == null or quanto <= 0.0:
		return false
	# picareta numa peça do mapa: coleta o material dela
	if picareta and quem and p.dono == 0:
		quem.inv.add_material(Grade.MATERIAIS[p.material], int(cfg["coleta"]["peca_mapa"]))
		quem.dirty = true
	p.hp -= quanto
	_mudaram[id] = true
	if p.hp <= 0.0:
		if picareta and quem and p.dono == 0:
			quem.inv.add_material(Grade.MATERIAIS[p.material], int(cfg["coleta"]["bonus_destruir"]))
		destroy(id, Protocol.GONE_DESTRUIDA)
		return true
	return false


## Golpe da picareta em qualquer coisa do cenário (CombatServer._golpe).
func on_pickaxe(c: GameServer.Cliente, collider: Object, material: int) -> void:
	var dano := float(ItemDB.tool_def(Inventory.PICKAXE_ID)["dano_construcao"])
	if collider is Node and (collider as Node).has_meta("peca_id"):
		damage(int((collider as Node).get_meta("peca_id")), dano, c, true)
		return
	# props: árvores/arbustos dão madeira, rochas dão pedra (não são destruídos)
	var col: Dictionary = cfg["coleta"]
	match material:
		ImpactMaterial.MADEIRA:
			c.inv.add_material("madeira", int(col["arvore"]))
			c.dirty = true
		ImpactMaterial.PEDRA:
			c.inv.add_material("pedra", int(col["pedra"]))
			c.dirty = true


func destroy(id: int, motivo: int) -> void:
	var vizinhos := estado.neighbors(id)
	var p := estado.remove(id)
	if p == null:
		return
	if corpos.has(id):
		(corpos[id] as Node).queue_free()
		corpos.erase(id)
	_mudaram.erase(id)
	if motivo == Protocol.GONE_DESABOU:
		desabaram += 1
	else:
		destruidas += 1
	server.broadcast(Protocol.pack_piece_gone(id, motivo), true)
	for v in estado.unsupported(vizinhos):
		if not _desabar.has(v):
			_desabar.append(v)


# ---------------- tick ----------------

func update() -> void:
	# peças em obra ganham vida até o máximo no tempo do material
	for id in _em_obra.keys():
		var p: Construcoes.Peca = estado.pecas.get(id)
		if p == null or p.obra <= 0.0:
			_em_obra.erase(id)
			continue
		var m: Dictionary = cfg["materiais"][Grade.MATERIAIS[p.material]]
		var passos := float(m["tempo_s"]) * Protocol.TICK_RATE
		var ganho := p.hp_max * (1.0 - float(m["vida_inicial"])) / passos
		p.obra = maxf(0.0, p.obra - 1.0 / passos)
		p.hp = minf(p.hp_max, p.hp + ganho)
		_mudaram[p.id] = true
	# desabamento em lotes (evita picos com estruturas grandes)
	var n := int(cfg["desabar_por_tick"])
	while n > 0 and not _desabar.is_empty():
		var id: int = _desabar.pop_front()
		if estado.pecas.has(id):
			destroy(id, Protocol.GONE_DESABOU)
			n -= 1
	if server.tick % 3 == 0 and not _mudaram.is_empty():
		var lista := []
		for id in _mudaram:
			var p: Construcoes.Peca = estado.pecas.get(id)
			if p:
				lista.append([id, p.hp, p.obra])
		_mudaram.clear()
		for i in range(0, lista.size(), 200):
			server.broadcast(Protocol.pack_pieces_hp(lista.slice(i, i + 200)), true)


## Estado para quem acabou de entrar: peças do mapa que sumiram, peças dos jogadores
## e vidas alteradas.
func full_state() -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	for id in range(1, _mapa_n + 1):
		if not estado.pecas.has(id):
			out.append(Protocol.pack_piece_gone(id, Protocol.GONE_DESTRUIDA))
	var hp := []
	for p: Construcoes.Peca in estado.pecas.values():
		if p.dono != 0 or p.edited():
			out.append(Protocol.pack_piece(p.to_dict()))
		elif p.hp < p.hp_max:
			hp.append([p.id, p.hp, p.obra])
	if not hp.is_empty():
		out.append(Protocol.pack_pieces_hp(hp))
	return out


## Partida nova: remove as peças dos jogadores e restaura o mapa.
func reset() -> void:
	for id in corpos:
		(corpos[id] as Node).queue_free()
	corpos.clear()
	estado = Construcoes.new()
	_em_obra.clear()
	_desabar.clear()
	_mudaram.clear()
	init_map()
	server.broadcast(PackedByteArray([Protocol.S_BUILD_RESET]), true)

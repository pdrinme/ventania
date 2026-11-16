class_name Mapa
extends Node3D
## Base dos mapas da partida. O mesmo mapa roda no servidor (colisão) e no cliente
## (visual + colisão para a predição). Tudo que o servidor, o loot e o cliente
## precisam saber do mapa passa por aqui (nada de constantes de um mapa específico).

var com_ambiente := true            # céu/sol/neblina só no cliente
var chest_nodes: Array[Node3D] = []


## Cria o mapa pelo nome que o servidor anuncia no S_WELCOME.
static func create(nome: String) -> Mapa:
	match nome:
		IlhaVentania.NOME:
			return IlhaVentania.new()
	return CampoTreino.new()


func map_name() -> String:
	return ""


func display_name() -> String:
	return map_name()


## Baús: [posição, rotação Y]. O índice é o id do baú na rede.
func chests() -> Array:
	return []


## Pontos de loot no chão (sorteados no início da partida).
func loot_points() -> Array:
	return []


## Bonecos de treino (só no campo de treino).
func dummies() -> Array:
	return []


func spawn_point(_i: int) -> Vector3:
	return Vector3.ZERO


## Pontos de início da partida Battle Royale (espalhados pelo mapa).
func match_spawn_points() -> Array:
	return []


func death_height() -> float:
	return -30.0


## Meia largura do mapa (m): bordas invisíveis em ±limit().
func limit() -> float:
	return 100.0


## Altura do chão (sem construções) num ponto do mapa.
func ground_height(_x: float, _z: float) -> float:
	return 0.0


## Pontos de interesse: [{"nome", "pos": Vector3, "raio"}] (mapa e minimapa).
func points_of_interest() -> Array:
	return []


## Construções do mapa na grade (Etapa 5): [{"tipo","cell","rot","material"}].
## Viram peças destrutíveis do sistema de construção, com ids 1..N nesta ordem.
func building_pieces() -> Array:
	return []

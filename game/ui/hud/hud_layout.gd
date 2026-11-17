class_name HudLayout
extends RefCounted
## Posicionamento do HUD da partida, com dois arranjos (redesign da Etapa 8,
## seguindo as convenções do gênero):
##  PC:  mapa no canto superior direito com vivos/eliminações/Tormenta embaixo;
##       ping no superior esquerdo; feed à esquerda; vida/escudo embaixo à
##       esquerda; barra de itens embaixo à direita, munição acima dela e
##       materiais em coluna na borda direita.
##  Toque: mapa e informações no superior esquerdo (o lado direito de cima fica
##       para pausa/Mochila/Construir); vida, escudo, materiais e barra de itens
##       no centro de baixo, entre os polegares; feed à esquerda, sob o mapa.

const MARGEM := 16.0
const MAPA_PC := 196.0
const MAPA_TOQUE := 150.0


## Prende o controle a um ponto da tela (âncora ax, ay em 0..1) e o faz crescer
## a partir dali: gx/gy = -1 cresce para a esquerda/cima, 1 para a direita/baixo,
## 0 para os dois lados (centralizado).
static func pin(c: Control, ax: float, ay: float, x: float, y: float, gx: int, gy: int) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = x
	c.offset_right = x
	c.offset_top = y
	c.offset_bottom = y
	c.grow_horizontal = [Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_END][gx + 1]
	c.grow_vertical = [Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_END][gy + 1]
	c.reset_size()

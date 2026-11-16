class_name Version
extends RefCounted
## Versões do jogo. O meta-servidor e o servidor de partida comparam
## PROTOCOL e CONTENT no handshake; versões diferentes são recusadas.

const NAME := "Ventania"
const GAME := "0.5.0"
const PROTOCOL := 1
const CONTENT := 1


static func full() -> String:
	return "%s %s (protocolo %d, conteúdo %d)" % [NAME, GAME, PROTOCOL, CONTENT]

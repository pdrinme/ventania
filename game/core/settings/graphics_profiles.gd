class_name GraphicsProfiles
extends RefCounted
## Perfis gráficos. Cada perfil só preenche valores; o jogador pode mudar
## qualquer opção depois (o perfil passa a "custom").

const KEYS := ["render_scale", "msaa", "shadows", "view_distance", "fps_limit"]

const PROFILES := {
	"performance": {"render_scale": 0.7, "msaa": 0, "shadows": "off", "view_distance": 120.0, "fps_limit": 30},
	"balanced": {"render_scale": 0.85, "msaa": 0, "shadows": "low", "view_distance": 250.0, "fps_limit": 60},
	"quality": {"render_scale": 1.0, "msaa": 2, "shadows": "high", "view_distance": 500.0, "fps_limit": 60},
}


## No PC o perfil Desempenho limita em 60 FPS (medição: HD Graphics 3000 faz ~106 FPS
## nele); no celular fica em 30 para poupar bateria e calor.
const MOBILE_OVERRIDES := {"performance": {"fps_limit": 30}}
const PC_OVERRIDES := {"performance": {"fps_limit": 60}}


## Valores de um perfil para a plataforma.
static func values(nome: String, is_mobile: bool) -> Dictionary:
	var v: Dictionary = PROFILES[nome].duplicate()
	v.merge((MOBILE_OVERRIDES if is_mobile else PC_OVERRIDES).get(nome, {}), true)
	return v


static func default_for(is_mobile: bool) -> String:
	return "performance" if is_mobile else "balanced"


## Qual perfil corresponde exatamente aos valores (ou "custom").
static func match_profile(atuais: Dictionary, is_mobile := false) -> String:
	for nome in PROFILES:
		var perfil := values(nome, is_mobile)
		var ok := true
		for k in KEYS:
			var esperado: Variant = perfil[k]
			var atual: Variant = atuais.get(k)
			if esperado is float:
				ok = (atual is float or atual is int) and is_equal_approx(float(atual), esperado)
			else:
				ok = typeof(atual) == typeof(esperado) and atual == esperado
			if not ok:
				break
		if ok:
			return nome
	return "custom"

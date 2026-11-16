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


static func default_for(is_mobile: bool) -> String:
	return "performance" if is_mobile else "balanced"


## Qual perfil corresponde exatamente aos valores (ou "custom").
static func match_profile(values: Dictionary) -> String:
	for nome in PROFILES:
		var ok := true
		for k in KEYS:
			var esperado: Variant = PROFILES[nome][k]
			var atual: Variant = values.get(k)
			if esperado is float:
				ok = (atual is float or atual is int) and is_equal_approx(float(atual), esperado)
			else:
				ok = typeof(atual) == typeof(esperado) and atual == esperado
			if not ok:
				break
		if ok:
			return nome
	return "custom"

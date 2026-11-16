// Shader cartoon do kit Ventania. Compatível com o renderizador Compatibility (GLES3).
// - Cor vem do atlas de paleta (uma célula por peça, amostragem "nearest", sem mipmaps).
// - Luz em 2 faixas com transição curta (visual de desenho animado).
// - Sombra puxada para azul (o lado escuro fica frio, não cinza).
// - Brilho de borda (rim) leve no lado iluminado, para destacar a silhueta.
// - Construções (Etapa 5, MultiMesh com dados por instância): INSTANCE_CUSTOM.x = dano
//   0..1 (escurece e abre rachaduras progressivas), .y = obra 0..1 (tom azulado de
//   "em construção"). Fora de MultiMesh com dados, os dois valem 0 e nada muda.
shader_type spatial;
render_mode specular_disabled;

uniform sampler2D paleta : source_color, filter_nearest, repeat_disable;
uniform vec3 cor_sombra : source_color = vec3(0.62, 0.66, 0.92);
uniform float limite_luz : hint_range(-1.0, 1.0) = 0.05;
uniform float suavidade : hint_range(0.0, 0.5) = 0.06;
uniform float forca_rim : hint_range(0.0, 1.0) = 0.25;

varying vec3 p_local;
varying vec2 estado_peca;

void vertex() {
	p_local = VERTEX;
	estado_peca = INSTANCE_CUSTOM.xy;
}

vec2 sorteio(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Distância até a borda da célula de Voronoi mais próxima (linhas de rachadura).
float borda_celula(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + sorteio(n + g) - f;
			float d = dot(r, r);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return sqrt(d2) - sqrt(d1);
}

void fragment() {
	vec3 cor = texture(paleta, UV).rgb;
	float dano = estado_peca.x;
	if (dano > 0.02) {
		vec2 q = (p_local.xy + p_local.zx * 0.8) * 1.4;
		float b = borda_celula(q);
		// mais dano: rachaduras mais largas e em mais células
		float largura = 0.02 + dano * 0.10;
		float aparece = step(1.0 - dano * 1.25, sorteio(floor(q)).x + 0.15);
		float rachadura = (1.0 - smoothstep(largura * 0.4, largura, b)) * max(aparece, step(0.6, dano));
		cor *= 1.0 - dano * 0.30;
		cor = mix(cor, vec3(0.13, 0.10, 0.09), rachadura * 0.9);
	}
	float obra = estado_peca.y;
	if (obra > 0.01) {
		float linhas = step(0.55, fract(p_local.y * 2.0 - TIME * 0.6));
		cor = mix(cor, vec3(0.45, 0.78, 1.0), obra * (0.45 + 0.25 * linhas));
	}
	ALBEDO = cor;
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float faixa = smoothstep(limite_luz, limite_luz + suavidade, ndl) * ATTENUATION;
	// No lado escuro sobra só um toque frio; a luz ambiente (WorldEnvironment) faz o resto.
	vec3 tom = mix(cor_sombra * 0.12, vec3(0.9), faixa);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0) * faixa * forca_rim;
	DIFFUSE_LIGHT += (tom + rim) * LIGHT_COLOR / PI;
}

// Shader cartoon do kit Ventania. Compatível com o renderizador Compatibility (GLES3).
// - Cor vem do atlas de paleta (uma célula por peça, amostragem "nearest", sem mipmaps).
// - Luz em 2 faixas com transição curta (visual de desenho animado).
// - Sombra puxada para azul (o lado escuro fica frio, não cinza).
// - Brilho de borda (rim) leve no lado iluminado, para destacar a silhueta.
// - Construções (Etapa 5, MultiMesh com dados por instância): INSTANCE_CUSTOM.x = dano
//   0..1 (escurece e abre rachaduras progressivas), .y = obra 0..1 (tom azulado de
//   "em construção"). .z = pintura (índice/16 na tabela TINTAS: paredes pastel e
//   telhados coloridos das casas do mapa) e .w = "torto" (envergadura suave das peças
//   do mapa, contínua no espaço do mundo: as emendas entre peças continuam fechadas;
//   no máximo ~12 cm, a colisão continua valendo). Fora de MultiMesh com dados, tudo
//   vale 0 e nada muda.
shader_type spatial;
render_mode specular_disabled;

uniform sampler2D paleta : source_color, filter_nearest, repeat_disable;
uniform vec3 cor_sombra : source_color = vec3(0.62, 0.66, 0.92);
uniform float limite_luz : hint_range(-1.0, 1.0) = 0.05;
uniform float suavidade : hint_range(0.0, 0.5) = 0.06;
uniform float forca_rim : hint_range(0.0, 1.0) = 0.25;
// oclusão ambiente assada nos vértices pelo exportador (COLOR.r; 1 sem dados)
uniform float forca_ao : hint_range(0.0, 1.0) = 0.75;
// variação de "pintura à mão": manchas suaves e grão fino, para a cor não ficar chapada
uniform float forca_variacao : hint_range(0.0, 0.3) = 0.07;

varying vec3 p_local;
varying vec2 estado_peca;
varying float ao_vertice;
varying float tinta;

const vec3 TINTAS[9] = vec3[](vec3(1.0), vec3(0.45, 0.82, 0.68), vec3(1.0, 0.66, 0.50), vec3(1.0, 0.85, 0.42),
		vec3(0.72, 0.62, 0.96), vec3(0.50, 0.74, 1.0), vec3(0.88, 0.34, 0.28), vec3(0.16, 0.56, 0.62), vec3(0.44, 0.36, 0.78));

void vertex() {
	p_local = VERTEX;
	estado_peca = INSTANCE_CUSTOM.xy;
	tinta = INSTANCE_CUSTOM.z * 16.0;
	if (INSTANCE_CUSTOM.w > 0.5) {
		// envergadura "de desenho": função suave da posição no mundo (sem emendas)
		vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 off = vec3(sin(w.y * 0.31 + w.z * 0.09 + 1.3) * sin(w.x * 0.045 + w.z * 0.061 + 0.4),
				sin(w.x * 0.07 + w.z * 0.05) * 0.25,
				sin(w.y * 0.27 + w.x * 0.11 + 2.1) * cos(w.z * 0.052 - w.x * 0.037)) * 0.12;
		VERTEX += transpose(mat3(MODEL_MATRIX)) * off;
	}
	// sem cor de vértice o atributo chega como preto (GLES3): a AO exportada nunca é
	// menor que 0,35, então preto puro = "sem dado" (não escurece)
	ao_vertice = (COLOR.r + COLOR.g + COLOR.b) < 0.03 ? 1.0 : COLOR.r;
}

float ruido(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n = i.x + i.y * 57.0 + i.z * 113.0;
	float a = fract(sin(n) * 43758.5453);
	float b = fract(sin(n + 1.0) * 43758.5453);
	float c = fract(sin(n + 57.0) * 43758.5453);
	float d = fract(sin(n + 58.0) * 43758.5453);
	float e = fract(sin(n + 113.0) * 43758.5453);
	float g = fract(sin(n + 114.0) * 43758.5453);
	float h = fract(sin(n + 170.0) * 43758.5453);
	float k = fract(sin(n + 171.0) * 43758.5453);
	return mix(mix(mix(a, b, f.x), mix(c, d, f.x), f.y), mix(mix(e, g, f.x), mix(h, k, f.x), f.y), f.z);
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
	int t = int(round(tinta));
	if (t > 0 && t < 9) {
		// pinta as partes claras (tábuas, blocos); molduras e frestas escuras ficam
		float l = dot(cor, vec3(0.3, 0.59, 0.11));
		float pintar = smoothstep(0.3, 0.48, l);
		cor = mix(cor, TINTAS[t] * (0.7 + 0.3 * l), pintar * 0.88);
	}
	float obra = estado_peca.y;
	if (obra > 0.01) {
		float linhas = step(0.55, fract(p_local.y * 2.0 - TIME * 0.6));
		cor = mix(cor, vec3(0.45, 0.78, 1.0), obra * (0.45 + 0.25 * linhas));
	}
	// pintura: manchas grandes + pinceladas finas (no espaço do objeto: não "escorrega")
	float manchas = ruido(p_local * 1.7) - 0.5;
	float grao = ruido(p_local * 9.0 + 3.1) - 0.5;
	cor *= 1.0 + forca_variacao * (manchas * 1.2 + grao * 0.6);
	cor *= mix(1.0, ao_vertice, forca_ao);
	ALBEDO = cor;
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// três faixas (sombra, meio-tom, luz) com transições curtas: volume de desenho animado
	float faixa = smoothstep(limite_luz, limite_luz + suavidade, ndl) * ATTENUATION;
	float plena = smoothstep(0.45, 0.45 + suavidade, ndl) * ATTENUATION;
	// No lado escuro sobra só um toque frio; a luz ambiente (WorldEnvironment) faz o resto.
	vec3 tom = mix(cor_sombra * 0.12, vec3(0.78), faixa) + vec3(0.14) * plena;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0) * faixa * forca_rim;
	DIFFUSE_LIGHT += (tom + rim) * LIGHT_COLOR / PI;
}

// Terreno da Ilha Ventania (Compatibility/GLES3). Sem texturas: os materiais são
// procedurais, no espaço do mundo, misturados por pesos gravados na cor do vértice:
//   COLOR.r = areia, COLOR.g = rocha, COLOR.b = terra/caminho; o resto é grama.
// As transições vêm da interpolação dos pesos entre vértices (3 m) mais um ruído
// que "morde" a borda, para não ficar uma linha reta. Luz em faixas, como o kit.
shader_type spatial;
render_mode specular_disabled;

uniform vec3 grama_a : source_color = vec3(0.42, 0.76, 0.29);
uniform vec3 grama_b : source_color = vec3(0.33, 0.64, 0.25);
uniform vec3 grama_sol : source_color = vec3(0.62, 0.80, 0.30);   // manchas amareladas (campo)
uniform vec3 grama_funda : source_color = vec3(0.22, 0.52, 0.30);  // vales/bosques, mais azulada
uniform vec3 areia : source_color = vec3(0.91, 0.83, 0.60);
uniform vec3 rocha : source_color = vec3(0.56, 0.54, 0.50);
uniform vec3 terra : source_color = vec3(0.62, 0.47, 0.30);
uniform vec3 cor_sombra : source_color = vec3(0.62, 0.66, 0.92);

global uniform float detalhe_arte;     // 0 no detalhe baixo: só o essencial

varying vec3 p_mundo;
varying vec3 pesos;
varying vec3 n_mundo;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float ruido(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	p_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	pesos = COLOR.rgb;
	n_mundo = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 q = p_mundo.xz;
	float grande = ruido(q * 0.035);
	float medio = ruido(q * 0.21);
	float fino = ruido(q * 1.7);
	bool rico = detalhe_arte > 0.5;
	float muito_grande = rico ? ruido(q * 0.009 + 7.3) : 0.5;
	float incl = 1.0 - clamp(n_mundo.y, 0.0, 1.0);          // 0 = plano, ~0.5 = encosta forte
	// grama: manchas grandes (campo ensolarado x vale úmido), dois tons médios e "tufos"
	vec3 g = mix(grama_a, grama_b, smoothstep(0.35, 0.75, grande));
	g = mix(g, grama_sol, smoothstep(0.55, 0.85, muito_grande) * 0.75);
	g = mix(g, grama_funda, smoothstep(0.6, 0.25, muito_grande) * 0.55);
	g = mix(g, grama_funda * 0.9, smoothstep(0.08, 0.35, incl) * 0.5);   // encostas mais escuras
	g *= 0.93 + 0.12 * medio + 0.06 * step(0.82, fino) - 0.05 * step(fino, 0.12);
	// pontinhos de flor no campo plano (bem esparsos, só de perto pesa pouco)
	if (rico) {
		float flor = step(0.985, ruido(q * 3.3 + 11.0)) * step(incl, 0.12) * smoothstep(0.4, 0.7, muito_grande);
		g = mix(g, mix(vec3(1.0, 0.95, 0.85), vec3(1.0, 0.62, 0.78), step(0.5, fino)), flor);
	}
	// areia: ondulações; molhada (mais escura) perto do mar
	vec3 a = areia * (0.95 + 0.06 * sin(q.x * 0.9 + q.y * 0.4 + medio * 3.0));
	a = mix(a * vec3(0.78, 0.74, 0.70), a, smoothstep(0.2, 1.1, p_mundo.y));
	// rocha: camadas horizontais (estratos tortos), blocos e rachaduras
	float bloco = ruido(q * 0.45);
	float estrato = fract(p_mundo.y * 0.55 + medio * 0.6);
	vec3 r = rocha * (0.82 + 0.25 * bloco) * (1.0 - 0.25 * step(0.92, fino));
	r *= 0.9 + 0.18 * smoothstep(0.1, 0.5, estrato) - 0.12 * step(0.9, estrato);
	r = mix(r, r * vec3(1.05, 0.95, 0.85), muito_grande * 0.5);   // rocha mais quente em partes
	// terra: pedrinhas e marcas de rodas
	vec3 t = terra * (0.9 + 0.12 * medio) * (1.0 - 0.18 * step(0.88, fino));
	// pesos com borda irregular
	vec3 w = clamp(pesos + (medio - 0.5) * 0.35 * step(0.02, pesos), 0.0, 1.0);
	float soma = w.r + w.g + w.b;
	if (soma > 1.0) { w /= soma; soma = 1.0; }
	// borda do caminho: grama pisada e mais escura logo ao lado da terra
	float beira = smoothstep(0.02, 0.2, w.b) * (1.0 - smoothstep(0.35, 0.6, w.b));
	g = mix(g, g * vec3(0.82, 0.8, 0.7), beira * 0.6);
	vec3 cor = g * (1.0 - soma) + a * w.r + r * w.g + t * w.b;
	ALBEDO = cor;
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float faixa = smoothstep(0.05, 0.11, ndl) * ATTENUATION;
	float plena = smoothstep(0.45, 0.55, ndl) * ATTENUATION;
	vec3 tom = mix(cor_sombra * 0.12, vec3(0.8), faixa) + vec3(0.12) * plena;
	DIFFUSE_LIGHT += tom * LIGHT_COLOR / PI;
}

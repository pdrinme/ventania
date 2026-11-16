// Terreno da Ilha Ventania (Compatibility/GLES3). Sem texturas: os materiais são
// procedurais, no espaço do mundo, misturados por pesos gravados na cor do vértice:
//   COLOR.r = areia, COLOR.g = rocha, COLOR.b = terra/caminho; o resto é grama.
// As transições vêm da interpolação dos pesos entre vértices (3 m) mais um ruído
// que "morde" a borda, para não ficar uma linha reta. Luz em faixas, como o kit.
shader_type spatial;
render_mode specular_disabled;

uniform vec3 grama_a : source_color = vec3(0.42, 0.76, 0.29);
uniform vec3 grama_b : source_color = vec3(0.33, 0.64, 0.25);
uniform vec3 areia : source_color = vec3(0.91, 0.83, 0.60);
uniform vec3 rocha : source_color = vec3(0.56, 0.54, 0.50);
uniform vec3 terra : source_color = vec3(0.62, 0.47, 0.30);
uniform vec3 cor_sombra : source_color = vec3(0.62, 0.66, 0.92);

varying vec3 p_mundo;
varying vec3 pesos;

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
}

void fragment() {
	vec2 q = p_mundo.xz;
	float grande = ruido(q * 0.035);
	float medio = ruido(q * 0.21);
	float fino = ruido(q * 1.7);
	// grama: manchas de dois tons + "tufos"
	vec3 g = mix(grama_a, grama_b, smoothstep(0.35, 0.75, grande));
	g *= 0.93 + 0.12 * medio + 0.05 * step(0.82, fino);
	// areia: ondulações
	vec3 a = areia * (0.95 + 0.06 * sin(q.x * 0.9 + q.y * 0.4 + medio * 3.0));
	// rocha: blocos e rachaduras
	float bloco = ruido(q * 0.45);
	vec3 r = rocha * (0.82 + 0.25 * bloco) * (1.0 - 0.25 * step(0.92, fino));
	// terra: pedrinhas
	vec3 t = terra * (0.9 + 0.12 * medio) * (1.0 - 0.18 * step(0.88, fino));
	// pesos com borda irregular
	vec3 w = clamp(pesos + (medio - 0.5) * 0.35 * step(0.02, pesos), 0.0, 1.0);
	float soma = w.r + w.g + w.b;
	if (soma > 1.0) { w /= soma; soma = 1.0; }
	vec3 cor = g * (1.0 - soma) + a * w.r + r * w.g + t * w.b;
	ALBEDO = cor;
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float faixa = smoothstep(0.05, 0.11, ndl) * ATTENUATION;
	vec3 tom = mix(cor_sombra * 0.12, vec3(0.9), faixa);
	DIFFUSE_LIGHT += tom * LIGHT_COLOR / PI;
}

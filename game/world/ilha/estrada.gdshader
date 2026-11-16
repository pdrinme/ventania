// Estradas, faixas de pedestres e calçadas (sem texturas, procedural).
// UV.x = atravessando a pista (0..1); UV.y = ao longo (metros).
// modo 0: asfalto com linhas de borda brancas e faixa central amarela tracejada
// modo 1: faixa de pedestres (listras brancas sobre o asfalto)
// modo 2: calçada de placas de concreto com meio-fio escuro na borda da rua
// modo 3: rua de bairro (asfalto sem faixa central, bordas tracejadas)
shader_type spatial;
render_mode specular_disabled;

uniform int modo = 0;
uniform vec3 asfalto : source_color = vec3(0.30, 0.31, 0.34);
uniform vec3 cor_sombra : source_color = vec3(0.62, 0.66, 0.92);

varying vec3 p_mundo;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	p_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float x = UV.x;
	float y = UV.y;
	float grao = h21(floor(p_mundo.xz * 6.0));
	vec3 cor = asfalto * (0.92 + 0.12 * grao);
	if (modo == 0 || modo == 3) {
		float borda = step(x, 0.04) * step(0.015, x) + step(0.96, x) * step(x, 0.985);
		if (modo == 3) borda *= step(0.4, fract(y / 4.0));
		cor = mix(cor, vec3(0.94), borda);
		if (modo == 0) {
			float centro = step(abs(x - 0.5), 0.018) * step(fract(y / 6.0), 0.55);
			cor = mix(cor, vec3(1.0, 0.82, 0.25), centro);
		}
	} else if (modo == 1) {
		cor = mix(cor, vec3(0.95), step(0.5, fract(x * 7.0)) * step(0.06, y) * step(y, 2.9));
	} else {
		vec3 concreto = vec3(0.80, 0.78, 0.73) * (0.95 + 0.06 * grao);
		float junta = step(fract(y / 2.0), 0.03) + step(abs(x - 0.5), 0.012);
		cor = mix(concreto, concreto * 0.78, clamp(junta, 0.0, 1.0));
		cor = mix(cor, vec3(0.55, 0.55, 0.56), step(x, 0.1));   // meio-fio (lado da rua)
	}
	ALBEDO = cor;
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float faixa = smoothstep(0.05, 0.11, ndl) * ATTENUATION;
	DIFFUSE_LIGHT += mix(cor_sombra * 0.12, vec3(0.9), faixa) * LIGHT_COLOR / PI;
}

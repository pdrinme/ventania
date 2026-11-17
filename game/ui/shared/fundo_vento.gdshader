shader_type canvas_item;
// Fundo dos menus: gradiente noturno (azul-petróleo -> índigo) com rajadas de
// vento estilizadas (faixas curvas que atravessam a tela devagar) e um brilho
// suave atrás do personagem. Barato: só aritmética, sem texturas.

uniform vec4 cor_a : source_color = vec4(0.047, 0.24, 0.31, 1.0);
uniform vec4 cor_b : source_color = vec4(0.17, 0.14, 0.44, 1.0);
uniform vec4 cor_vento : source_color = vec4(0.62, 0.92, 1.0, 1.0);
uniform vec2 brilho_centro = vec2(0.5, 0.55);
uniform float velocidade = 0.035;

float faixa(vec2 uv, float y0, float amp, float freq, float fase, float largura, float t) {
	float y = y0 + amp * sin(uv.x * freq + fase + t * 0.6);
	float d = abs(uv.y - y);
	// trechos: a rajada aparece e some ao longo do x (como um traço de vento)
	float trecho = smoothstep(0.0, 0.25, fract(uv.x * 0.55 - t * velocidade * 9.0 + fase));
	trecho *= 1.0 - smoothstep(0.55, 0.85, fract(uv.x * 0.55 - t * velocidade * 9.0 + fase));
	return (1.0 - smoothstep(largura * 0.4, largura, d)) * trecho;
}

void fragment() {
	vec2 uv = UV;
	float aspecto = 1.0 / SCREEN_PIXEL_SIZE.x * SCREEN_PIXEL_SIZE.y;
	float g = clamp(uv.x * 0.55 + uv.y * 0.6, 0.0, 1.0);
	vec3 cor = mix(cor_a.rgb, cor_b.rgb, g);
	// brilho atrás do personagem
	vec2 p = (uv - brilho_centro) * vec2(1.0 / aspecto, 1.0);
	cor += vec3(0.10, 0.20, 0.22) * (1.0 - smoothstep(0.0, 0.42, length(p)));
	float t = TIME;
	float v = 0.0;
	v += faixa(uv, 0.22, 0.05, 3.1, 0.0, 0.006, t);
	v += faixa(uv, 0.36, 0.07, 2.3, 1.7, 0.004, t) * 0.7;
	v += faixa(uv, 0.71, 0.06, 2.7, 3.1, 0.005, t) * 0.8;
	v += faixa(uv, 0.86, 0.04, 3.7, 4.4, 0.003, t) * 0.6;
	cor = mix(cor, cor_vento.rgb, clamp(v, 0.0, 1.0) * 0.22);
	// vinheta
	vec2 c = uv - 0.5;
	cor *= 1.0 - dot(c, c) * 0.55;
	COLOR = vec4(cor, 1.0);
}

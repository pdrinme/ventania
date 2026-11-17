// Fundo das imagens de cosméticos (loja, coleção, passe): degradê radial na cor
// da raridade, com rajadas de vento em diagonal (identidade do Ventania).
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 cor : source_color = vec4(0.23, 0.56, 0.9, 1.0);

void fragment() {
	vec2 uv = UV;
	float r = length((uv - vec2(0.5, 0.45)) * vec2(1.0, 0.85));
	vec3 c = mix(cor.rgb * 1.05, cor.rgb * 0.35, smoothstep(0.0, 0.75, r));
	float faixa = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float y = 0.18 + fi * 0.22 + 0.04 * sin(uv.x * 6.0 + fi * 1.7);
		faixa += (1.0 - smoothstep(0.003, 0.012, abs(uv.y - y + uv.x * 0.18))) * smoothstep(0.1, 0.4, fract(uv.x * 0.9 + fi * 0.37));
	}
	c = mix(c, vec3(1.0), clamp(faixa, 0.0, 1.0) * 0.18);
	ALBEDO = c;
}

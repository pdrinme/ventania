// Shader cartoon do kit Ventania. Compatível com o renderizador Compatibility (GLES3).
// - Cor vem do atlas de paleta (uma célula por peça, amostragem "nearest", sem mipmaps).
// - Luz em 2 faixas com transição curta (visual de desenho animado).
// - Sombra puxada para azul (o lado escuro fica frio, não cinza).
// - Brilho de borda (rim) leve no lado iluminado, para destacar a silhueta.
shader_type spatial;
render_mode specular_disabled;

uniform sampler2D paleta : source_color, filter_nearest, repeat_disable;
uniform vec3 cor_sombra : source_color = vec3(0.62, 0.66, 0.92);
uniform float limite_luz : hint_range(-1.0, 1.0) = 0.05;
uniform float suavidade : hint_range(0.0, 0.5) = 0.06;
uniform float forca_rim : hint_range(0.0, 1.0) = 0.25;

void fragment() {
	ALBEDO = texture(paleta, UV).rgb;
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

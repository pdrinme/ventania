// Vidro do aquário (Capitão Maré). Compatível com GLES3.
// Transparente no centro e mais opaco nas bordas (fresnel), com um reflexo
// vertical "pintado" (cartoon) que acompanha o lado iluminado.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_disabled;

uniform vec3 cor_vidro : source_color = vec3(0.78, 0.96, 1.0);
uniform float alfa_centro : hint_range(0.0, 1.0) = 0.10;
uniform float alfa_borda : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	// reflexo: faixa clara inclinada, na região de normal voltada para cima/esquerda
	float faixa = smoothstep(0.55, 0.6, NORMAL.x * -0.6 + NORMAL.y * 0.8) * (1.0 - smoothstep(0.75, 0.8, NORMAL.x * -0.6 + NORMAL.y * 0.8));
	ALBEDO = mix(cor_vidro, vec3(1.0), faixa * 0.8 + fres * 0.3);
	ALPHA = clamp(mix(alfa_centro, alfa_borda, fres) + faixa * 0.35, 0.0, 0.9);
	EMISSION = vec3(faixa * 0.25);
}

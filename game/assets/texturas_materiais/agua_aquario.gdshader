// Água do aquário (Capitão Maré). Compatível com GLES3.
// Azul translúcido, mais escuro embaixo, com ondas de luz (cáusticas cartoon)
// correndo devagar; elas se deslocam quando o personagem anda (parâmetro por
// instância "movimento", vindo do TrajeFx). Só cor: nada de deformar vértices
// (o personagem agacha, cai e inclina; a água acompanha o osso da cabeça).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_disabled;

uniform vec3 cor_agua : source_color = vec3(0.24, 0.66, 0.97);
uniform vec3 cor_fundo : source_color = vec3(0.07, 0.30, 0.60);
uniform float alfa : hint_range(0.0, 1.0) = 0.5;
instance uniform vec2 movimento = vec2(0.0);    // velocidade local (lado, frente) normalizada

varying vec3 p_obj;

void vertex() {
	p_obj = VERTEX;
}

void fragment() {
	// "altura" pela normal: faces de cima mais claras, de baixo mais escuras
	float cima = clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 cor = mix(cor_fundo, cor_agua, cima);
	vec2 d = p_obj.xz * 22.0 + vec2(TIME * 1.3, TIME * 0.9) + movimento * 6.0;
	float c = sin(d.x + sin(d.y * 0.8)) * sin(d.y * 1.1 + sin(d.x * 0.7));
	float causticas = smoothstep(0.55, 0.95, c);
	ALBEDO = cor + vec3(causticas * 0.25);
	ALPHA = alfa;
	EMISSION = cor_agua * 0.10 + vec3(causticas * 0.08);
}

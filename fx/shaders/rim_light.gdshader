shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never;
// Shared rim light for dark actors (black cats, orc). Assign as the `next_pass` of an actor's
// material so it reads against dark forest. Defaults follow PLAN.md: rim_light colour,
// strength 0.35.

uniform vec4 rim_color : source_color = vec4(0.8863, 0.9020, 0.8353, 1.0); // Palette.RIM_LIGHT
uniform float rim_strength : hint_range(0.0, 2.0) = 0.35;
uniform float rim_power : hint_range(0.5, 8.0) = 2.5;

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	ALBEDO = rim_color.rgb * fresnel * rim_strength;
}

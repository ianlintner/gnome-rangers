shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Shared light wind for foliage (ferns, grass, hanging moss). Sways vertices by height above the
// mesh origin so the root stays planted; phase comes from the instance's world position so a
// MultiMesh field never moves in lock-step. Textures are copied from the prop's imported
// StandardMaterial3D by the scatterer (levels/rootfall_hollow/foliage_scatter.gd).

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_roughness_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float roughness_scale : hint_range(0.0, 1.0) = 1.0;
uniform float wind_strength : hint_range(0.0, 0.5) = 0.06;
uniform float wind_speed : hint_range(0.0, 4.0) = 1.1;
uniform vec2 wind_direction = vec2(1.0, 0.35);
uniform float sway_height : hint_range(0.1, 10.0) = 1.0;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = dot(origin.xz, vec2(0.37, 0.61));
	float height = clamp(VERTEX.y / sway_height, 0.0, 1.0);
	float gust = sin(TIME * wind_speed + phase) + 0.5 * sin(TIME * wind_speed * 2.3 + phase * 1.7);
	vec2 dir = normalize(wind_direction);
	VERTEX.x += dir.x * gust * wind_strength * height * height;
	VERTEX.z += dir.y * gust * wind_strength * height * height;
}

void fragment() {
	vec4 albedo = texture(albedo_texture, UV) * albedo_tint;
	ALBEDO = albedo.rgb;
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	vec4 orm = texture(orm_texture, UV);
	ROUGHNESS = clamp(orm.g * roughness_scale, 0.0, 1.0);
	METALLIC = 0.0;
	// Two-sided leaves: shade the back face as lit from the front.
	BACKLIGHT = albedo.rgb * 0.25;
}

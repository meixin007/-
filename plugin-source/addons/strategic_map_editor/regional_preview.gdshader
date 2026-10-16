shader_type canvas_item;
render_mode unshaded;

// CanvasGroup's premultiplied backbuffer, with a soft sample boundary.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec2 region_size;
uniform float feather = 14.0;
varying vec2 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec4 composite = textureLod(screen_texture, SCREEN_UV, 0.0);
	if (composite.a > 0.0001) {
		composite.rgb /= composite.a;
	}
	vec2 distance_to_edge = min(local_position, region_size - local_position);
	float edge = smoothstep(0.0, feather, min(distance_to_edge.x, distance_to_edge.y));
	COLOR *= composite;
	COLOR.a *= edge;
}


shader_type canvas_item;

uniform float progresso : hint_range(0.0, 1.0) = 0.0;


uniform sampler2D screen_texture
	: hint_screen_texture, repeat_disable, filter_nearest;

uniform float vignette_strength : hint_range(0.0, 1.0) = 0.15;
uniform float vignette_size : hint_range(0.1, 1.5) = 0.95;

uniform float rgb_shift : hint_range(0.0, 0.005) = 0.0007;
uniform float glitch_strength : hint_range(0.0, 0.02) = 0.001;
uniform float glitch_frequency : hint_range(0.0, 1.0) = 0.12;

uniform bool glitch_enabled = true;

float rand(float x) {
	return fract(sin(x * 127.1 + 311.7) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// Glitch raro e discreto.
	float time_step = floor(TIME * 5.0);
	float row = floor(uv.y * 100.0);
	float noise = rand(row + time_step * 17.0);
	float evento = rand(time_step * 3.7);

	if (
		glitch_enabled
		&& evento > 1.0 - glitch_frequency * 0.04
		&& noise > 0.92
	) {
		uv.x += (noise - 0.92) * glitch_strength;
	}

	// Separação RGB sutil.
	vec4 original = texture(screen_texture, uv);

	float red = texture(
		screen_texture,
		uv + vec2(rgb_shift, 0.0)
	).r;

	float blue = texture(
		screen_texture,
		uv - vec2(rgb_shift, 0.0)
	).b;

	vec3 color = vec3(red, original.g, blue);

	// Vinheta reduzida.
	vec2 centered = SCREEN_UV - vec2(0.5);
	centered.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;

	float dist = length(centered);
	float vignette = smoothstep(
		vignette_size * 0.5,
		0.85,
		dist
	);

	color *= 1.0 - vignette * vignette_strength;

	// Sem scanlines.
	COLOR = vec4(color, original.a);
}

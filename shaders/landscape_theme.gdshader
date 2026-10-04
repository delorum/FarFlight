shader_type canvas_item;
// Recolour source drawing colours, not the final composited image: glyphs,
// antialiasing and translucent weather keep their original alpha and detail.
uniform bool theme_enabled = false;
uniform bool navigation_map = false;
// Set once at material creation from UIPalette, not on every frame.
uniform vec3 source_paper;
uniform vec3 source_route;
uniform vec3 dark_background;
varying vec4 drawing_color;

vec3 landscape_color(vec3 source) {
	// User-drawn routes (including the unfinished segment) keep their blue
	// ink in both themes; only chart ink is converted to beige.
	if (navigation_map && distance(source, source_route) < 0.015) {
		return source;
	}
	vec3 paper = source_paper;
	vec3 background = dark_background;
	float lightness = dot(source, vec3(0.2126, 0.7152, 0.0722));
	float spread = max(source.r, max(source.g, source.b)) - min(source.r, min(source.g, source.b));
	bool neutral = spread < 0.16;
	bool warm = source.r >= source.g && source.g >= source.b && source.r - source.g < 0.27 && source.g - source.b < 0.30;
	// Ordinary map annotations become beige; warning/linked-line reds,
	// orange highlights and radar weather colours retain their meaning.
	bool map_ink = navigation_map && (
		distance(source, vec3(0.46275, 0.13725, 0.11373)) < 0.015 ||
		distance(source, vec3(0.59216, 0.17647, 0.14510)) < 0.015 ||
		(source.g > source.r && source.g >= source.b && spread < 0.25) ||
		(source.b > source.r && source.g > source.r && lightness < 0.40) ||
		(source.g > source.r && source.b >= source.g && spread < 0.42));
	if (neutral || warm || map_ink) {
		if (distance(source, paper) < 0.025) { return background; }
		if (lightness < 0.60) { return paper * (1.0 - 0.28 * lightness / 0.60); }
		return mix(vec3(0.27, 0.30, 0.29), background, smoothstep(0.60, 0.85, lightness));
	}
	return lightness < 0.45 ? mix(source, vec3(1.0), 0.22) : source;
}

void vertex() {
	// Palette conversion runs per vertex, not per pixel of the full-size map.
	drawing_color = theme_enabled ? vec4(landscape_color(COLOR.rgb), COLOR.a) : COLOR;
}

void fragment() {
	if (theme_enabled) {
		COLOR = drawing_color * texture(TEXTURE, UV);
	}
}

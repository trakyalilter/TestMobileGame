shader_type canvas_item;
// Animated rarity frame for Armory tiles AND equipped slots.
// A glowing border in the rarity colour with a soft highlight that orbits the
// frame, a gentle pulse, and soft sparse twinkles for legendary/unique. Border
// thickness is aspect-corrected via `rect_px`, so it reads uniform on square
// tiles and tall equipped cards alike. Animated entirely on the GPU via TIME;
// uses only GL-Compatibility-safe operations. The card centre stays transparent.

uniform vec4 rarity_color : source_color = vec4(0.5, 0.7, 1.0, 1.0);
uniform float intensity = 1.0;   // overall brightness/strength
uniform float rainbow = 0.0;     // 0 = pure rarity tint (no holographic rainbow)
uniform float speed = 1.0;       // animation speed multiplier
uniform float sparkle = 0.0;     // >0.5 enables twinkling sparkles
uniform float border = 0.13;     // border thickness, fraction of the SHORT side
uniform float glow = 0.07;       // soft inward glow falloff
uniform float corner = 0.06;     // rounded-corner radius (short-side units)
uniform vec2 rect_px = vec2(1.0, 1.0);  // card pixel size (only the ratio matters)

vec3 hue(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;

	// Aspect normalisation: scale each axis into SHORT-side units so the border
	// is uniform thickness regardless of card aspect (square tiles == tall cards).
	vec2 norm = rect_px / min(rect_px.x, rect_px.y);
	vec2 d = min(uv, 1.0 - uv) * norm;
	float edge = min(d.x, d.y);

	// Rounded-corner clip (aspect-correct), softened to avoid aliased corners.
	vec2 pcn = abs(uv - 0.5) * norm;
	vec2 qd = max(pcn - (0.5 * norm - vec2(corner)), vec2(0.0));
	float outside = smoothstep(corner, corner + 0.02, length(qd));

	// Bright border band + soft inner glow.
	float band = 1.0 - smoothstep(0.0, border, edge);
	float halo = (1.0 - smoothstep(border, border + glow, edge)) * 0.4;
	float mask = max(band, halo);

	// Tint (rarity colour by default; optional iridescence if rainbow > 0).
	float sweep = fract((uv.x + uv.y) * 0.5 - t * 0.18);
	vec3 col = mix(rarity_color.rgb, hue(sweep), rainbow);

	// A single soft highlight that ORBITS the frame, low-frequency (no aliasing).
	float ang = atan(uv.y - 0.5, uv.x - 0.5) / 6.2831853 + 0.5;
	float orbit = fract(ang - t * 0.16);
	float comet = exp(-pow((orbit - 0.5) * 5.0, 2.0));
	float pulse = 0.82 + 0.18 * sin(t * 2.0);
	float a = mask * intensity * (0.5 + 0.6 * comet) * pulse;

	// Soft, sparse ROUND twinkles (legendary / unique only).
	if (sparkle > 0.5) {
		vec2 g = uv * norm * 7.0;
		vec2 cell = floor(g);
		float seed = hash21(cell);
		vec2 pp = vec2(hash21(cell + 1.7), hash21(cell + 9.1));
		float pd = length(fract(g) - pp);
		float tw = 0.5 + 0.5 * sin(t * (2.5 + seed * 3.0) + seed * 40.0);
		float pt = smoothstep(0.16, 0.0, pd) * smoothstep(0.72, 1.0, tw) * step(0.35, band);
		a += pt * 0.85;
		col = mix(col, vec3(1.0), pt * 0.8);
	}

	a = clamp(a, 0.0, 1.0) * (1.0 - outside);
	COLOR = vec4(col * (0.85 + 0.5 * a), a);
}

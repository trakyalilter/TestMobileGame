shader_type canvas_item;
// Animated "ARAM-style" rarity frame for Armory module/core cards.
// Draws a glowing, iridescent border that sweeps + shimmers + pulses, with
// optional twinkling sparkles. Animated entirely on the GPU via TIME (no
// per-frame GDScript), and uses only GL-Compatibility-safe operations. The
// card centre stays transparent so the tile shows through.

uniform vec4 rarity_color : source_color = vec4(0.5, 0.7, 1.0, 1.0);
uniform float intensity = 1.0;   // overall brightness/strength
uniform float rainbow = 0.0;     // 0 = pure rarity tint, 1 = full holographic
uniform float speed = 1.0;       // animation speed multiplier
uniform float sparkle = 0.0;     // >0.5 enables twinkling sparkles
uniform float border = 0.13;     // bright border band thickness (UV)
uniform float glow = 0.07;       // soft inward glow falloff (UV)
uniform float corner = 0.06;     // rounded-corner radius (UV) for clipping

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

	// Distance to the nearest straight edge: 0 at the edge, 0.5 at the centre.
	// (The previous rounded-box SDF saturated to a constant INSIDE the card, so
	// the "border" — and the sparkles — wrongly filled the whole tile.)
	float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));

	// Rounded-corner clip: drop only the square corner nubs beyond the radius.
	vec2 pc = abs(uv - 0.5);
	vec2 qd = max(pc - vec2(0.5 - corner), vec2(0.0));
	float outside = smoothstep(corner, corner + 0.02, length(qd));  // soft clip

	// Bright border band + soft inner glow.
	float band = 1.0 - smoothstep(0.0, border, edge);
	float halo = (1.0 - smoothstep(border, border + glow, edge)) * 0.4;
	float mask = max(band, halo);

	// Iridescent base tint, slowly cycling along a diagonal.
	float sweep = fract((uv.x + uv.y) * 0.5 - t * 0.18);
	vec3 col = mix(rarity_color.rgb, hue(sweep), rainbow);

	// A single soft highlight that ORBITS the frame (premium "light sweep"),
	// low-frequency so it never aliases into static. Plus a gentle pulse.
	float ang = atan(uv.y - 0.5, uv.x - 0.5) / 6.2831853 + 0.5;   // 0..1 around
	float orbit = fract(ang - t * 0.16);
	float comet = exp(-pow((orbit - 0.5) * 5.0, 2.0));            // smooth moving spot
	float pulse = 0.82 + 0.18 * sin(t * 2.0);
	float a = mask * intensity * (0.5 + 0.6 * comet) * pulse;

	// Soft, sparse ROUND twinkles (not blocky cells) — legendary / unique only.
	if (sparkle > 0.5) {
		vec2 g = uv * 7.0;
		vec2 cell = floor(g);
		float seed = hash21(cell);
		vec2 pp = vec2(hash21(cell + 1.7), hash21(cell + 9.1));
		float d = length(fract(g) - pp);
		float tw = 0.5 + 0.5 * sin(t * (2.5 + seed * 3.0) + seed * 40.0);
		float pt = smoothstep(0.16, 0.0, d) * smoothstep(0.72, 1.0, tw) * step(0.35, band);
		a += pt * 0.85;
		col = mix(col, vec3(1.0), pt * 0.8);
	}

	a = clamp(a, 0.0, 1.0) * (1.0 - outside);
	COLOR = vec4(col * (0.85 + 0.5 * a), a);
}

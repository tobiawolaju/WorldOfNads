shader_type canvas_item;

// Match-card stat glyphs, ported from the two Material Symbols Rounded icons the web
// dashboard puts in `.match-icon-badge`: the filled `favorite` heart and the filled
// `group` people. The Godot project ships no icon font, so both silhouettes are drawn
// here as filled shapes instead - `shape` picks one, `ink` is the glyph colour.
//
// UV is the glyph's own 0..1 box; the black circle behind it is a stylebox on the
// parent Panel (see _match_stat_badge_style in dshbord.gd).

// 0 = heart (likes), 1 = people (players).
uniform int shape : hint_range(0, 1) = 0;
uniform vec4 ink : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Filled heart: (x^2 + y^2 - 1)^3 - x^2 y^3 < 0, cleft up and point down. It spans
// +-1.1389 across and +-1 in y, so 2.3378 is the largest fit that keeps both tips and
// both sides whole (the CSS glyph sits in its em box the same way).
float heart_field(vec2 h) {
	float a = dot(h, h) - 1.0;
	return a * a * a - h.x * h.x * h.y * h.y * h.y;
}

float sd_circle(vec2 p, vec2 c, float r) {
	return length(p - c) - r;
}

// half_size.xy is the half extent, half_size.z the corner radius.
float sd_round_box(vec2 p, vec2 c, vec3 half_size) {
	vec2 q = abs(p - c) - half_size.xy + half_size.z;
	return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - half_size.z;
}

// Two people - the front one larger and lower-left, the second smaller and higher to
// the right, the way Material's filled `group` reads - unioned into one silhouette.
// Takes the same -1..1 box the heart uses and normalises the union to fill it: the
// union's bbox is 1.57 wide and its centre sits at (0.03, 0.0925).
float people_field(vec2 p) {
	vec2 n = p / 1.2102 + vec2(0.0300, 0.0925);
	// Front: head + shoulders.
	float d = sd_circle(n, vec2(-0.30, 0.42), 0.30);
	d = min(d, sd_round_box(n, vec2(-0.30, -0.22), vec3(0.46, 0.46, 0.30)));
	// Back: head + shoulders, overlapping the front pair so the union stays one shape.
	d = min(d, sd_circle(n, vec2(0.46, 0.62), 0.25));
	d = min(d, sd_round_box(n, vec2(0.46, 0.02), vec3(0.36, 0.42, 0.26)));
	return d;
}

void fragment() {
	// The card tints its children with modulate (`.match-card` rests at opacity 0.5),
	// so the incoming alpha has to survive the overwrite.
	float node_alpha = COLOR.a;

	vec2 q = UV - 0.5;
	// y up, so the shapes read the same way in both spaces.
	vec2 p = vec2(q.x, -q.y) * 2.0;
	float field = shape == 0 ? heart_field(p * 1.1689) : people_field(p);

	// dFdx/dFdy (the same pixel-derivative idiom the match-card shader uses) turn the
	// implicit heart field and the people distance into the same pixel-wide edge, so
	// both glyphs anti-alias without needing a per-shape edge width.
	float aa = max(0.5 * (abs(dFdx(field)) + abs(dFdy(field))), 0.0001);
	COLOR = vec4(ink.rgb, ink.a * (1.0 - smoothstep(-aa, aa, field)) * node_alpha);
}

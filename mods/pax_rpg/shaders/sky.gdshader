// Небо Юрумы со сменой суток: цвет зенита и горизонта (день — лазурь и розовая мана, закат — алый и золото,
// ночь — глубокая синь), диск светила (LIGHT0: днём солнце, ночью луна), плывущие облака (fbm), звёзды ночью.
// daynight.gd задаёт day (0 ночь … 1 день) и dusk (0..1 — насколько сейчас закат/рассвет).
shader_type sky;
render_mode use_half_res_pass;

uniform float day = 1.0;
uniform float dusk = 0.0;
uniform vec3 zenith_day : source_color = vec3(0.22, 0.42, 0.85);
uniform vec3 horizon_day : source_color = vec3(1.0, 0.66, 0.86);
uniform vec3 zenith_night : source_color = vec3(0.02, 0.03, 0.09);
uniform vec3 horizon_night : source_color = vec3(0.12, 0.08, 0.22);
uniform vec3 horizon_dusk : source_color = vec3(1.0, 0.42, 0.3);
uniform vec3 ground : source_color = vec3(0.32, 0.24, 0.26);
uniform float cloud_cover = 0.48;
uniform float cloud_speed = 0.006;

// хэш без sin (Dave Hoskins, hash12): sin больших чисел на GPU теряет точность — облака шли квадратами
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float h = clamp(d.y, -1.0, 1.0);
	vec3 zen = mix(zenith_night, zenith_day, day);
	vec3 hor = mix(horizon_night, horizon_day, day);
	hor = mix(hor, horizon_dusk, dusk);
	float t = pow(1.0 - clamp(h, 0.0, 1.0), 2.6);
	vec3 col = mix(zen, hor, t);
	// солнце и ореол
	if (LIGHT0_ENABLED) {
		float sd = dot(d, LIGHT0_DIRECTION);
		col += LIGHT0_COLOR * (pow(max(sd, 0.0), 900.0) * 18.0 + pow(max(sd, 0.0), 12.0) * 0.35 * (0.4 + dusk));
	}
	// звёзды
	if (h > 0.0 && day < 0.6) {
		vec2 sp = d.xz / (d.y + 0.15) * 90.0;
		float st = step(0.996, hash(floor(sp))) * (0.5 + 0.5 * sin(TIME * 2.0 + hash(floor(sp) + 3.0) * 40.0));
		col += vec3(st) * (1.0 - day / 0.6) * smoothstep(0.0, 0.25, h);
	}
	// облака: плоскость над миром
	if (h > 0.02) {
		vec2 cp = d.xz / (d.y + 0.12) * 1.6 + mod(vec2(TIME * cloud_speed, TIME * cloud_speed * 0.4), 1000.0);
		float c = fbm(cp);
		float m = smoothstep(cloud_cover, cloud_cover + 0.25, c) * smoothstep(0.02, 0.2, h);
		vec3 lit = mix(vec3(0.16, 0.14, 0.24), vec3(1.0, 0.95, 0.98), day);
		lit = mix(lit, vec3(1.0, 0.6, 0.5), dusk * 0.8);
		vec3 shade = mix(vec3(0.08, 0.07, 0.14), vec3(0.7, 0.62, 0.8), day);
		vec3 cc = mix(shade, lit, smoothstep(0.35, 0.9, fbm(cp * 1.7 + 4.0)));
		col = mix(col, cc, m * 0.9);
	}
	// под горизонтом — земля в дымке
	col = mix(col, mix(ground * (0.25 + 0.75 * day), hor, 0.55), smoothstep(0.0, -0.08, h));
	COLOR = col;
}

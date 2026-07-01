shader_type canvas_item;

group_uniforms ColorOverlay;
uniform bool use_color_overlay = false;
uniform vec4 color_overlay_color : source_color = vec4(1.0);
uniform float color_overlay_opacity : hint_range(0.0, 1.0) = 1.0;

group_uniforms Stroke;
uniform bool use_stroke = false;
uniform vec4 stroke_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float stroke_opacity : hint_range(0.0, 1.0) = 1.0;
uniform float stroke_size : hint_range(0.0, 64.0) = 1.0;

group_uniforms OuterGlow;
uniform bool use_outer_glow = false;
uniform vec4 outer_glow_color : source_color = vec4(1.0);
uniform float outer_glow_opacity : hint_range(0.0, 1.0) = 1.0;
uniform float outer_glow_size : hint_range(0.0, 64.0) = 8.0;

group_uniforms DropShadow;
uniform bool use_drop_shadow = false;
uniform vec4 drop_shadow_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float drop_shadow_opacity : hint_range(0.0, 1.0) = 0.75;
uniform float drop_shadow_size : hint_range(0.0, 64.0) = 8.0;
uniform vec2 drop_shadow_offset = vec2(4.0, 4.0);
group_uniforms;

float sample_alpha(sampler2D tex, vec2 uv) {
	return texture(tex, uv).a;
}

float alpha_max_ring(sampler2D tex, vec2 uv, vec2 texel, float radius) {
	float r = max(radius, 0.0);
	if (r <= 0.0) {
		return sample_alpha(tex, uv);
	}

	float a = 0.0;
	a = max(a, sample_alpha(tex, uv + texel * vec2( r,  0.0)));
	a = max(a, sample_alpha(tex, uv + texel * vec2(-r,  0.0)));
	a = max(a, sample_alpha(tex, uv + texel * vec2( 0.0,  r)));
	a = max(a, sample_alpha(tex, uv + texel * vec2( 0.0, -r)));
	a = max(a, sample_alpha(tex, uv + texel * vec2( r,  r)));
	a = max(a, sample_alpha(tex, uv + texel * vec2(-r,  r)));
	a = max(a, sample_alpha(tex, uv + texel * vec2( r, -r)));
	a = max(a, sample_alpha(tex, uv + texel * vec2(-r, -r)));
	return a;
}

float alpha_blur(sampler2D tex, vec2 uv, vec2 texel, float radius) {
	float r = max(radius, 0.0);
	if (r <= 0.0) {
		return sample_alpha(tex, uv);
	}

	float a = sample_alpha(tex, uv) * 0.20;
	a += sample_alpha(tex, uv + texel * vec2( r,  0.0)) * 0.10;
	a += sample_alpha(tex, uv + texel * vec2(-r,  0.0)) * 0.10;
	a += sample_alpha(tex, uv + texel * vec2( 0.0,  r)) * 0.10;
	a += sample_alpha(tex, uv + texel * vec2( 0.0, -r)) * 0.10;
	a += sample_alpha(tex, uv + texel * vec2( r,  r)) * 0.10;
	a += sample_alpha(tex, uv + texel * vec2(-r,  r)) * 0.10;
	a += sample_alpha(tex, uv + texel * vec2( r, -r)) * 0.10;
	a += sample_alpha(tex, uv + texel * vec2(-r, -r)) * 0.10;
	return clamp(a, 0.0, 1.0);
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec2 texel = TEXTURE_PIXEL_SIZE;
	vec4 out_color = base;

	if (use_color_overlay) {
		vec3 overlay_rgb = mix(base.rgb, color_overlay_color.rgb, color_overlay_opacity);
		out_color.rgb = mix(out_color.rgb, overlay_rgb, base.a);
	}

	if (use_stroke && stroke_size > 0.0) {
		float expanded = alpha_max_ring(TEXTURE, UV, texel, stroke_size);
		float stroke_alpha = clamp(expanded - base.a, 0.0, 1.0) * stroke_opacity;
		vec4 stroke = vec4(stroke_color.rgb, stroke_alpha * stroke_color.a);
		out_color = mix(stroke, out_color, out_color.a);
		out_color.a = max(out_color.a, stroke.a);
	}

	if (use_outer_glow && outer_glow_size > 0.0) {
		float glow_alpha = alpha_blur(TEXTURE, UV, texel, outer_glow_size);
		glow_alpha = clamp(glow_alpha - base.a, 0.0, 1.0) * outer_glow_opacity;
		vec4 glow = vec4(outer_glow_color.rgb, glow_alpha * outer_glow_color.a);
		out_color.rgb += glow.rgb * glow.a * (1.0 - out_color.a);
		out_color.a = max(out_color.a, glow.a);
	}

	if (use_drop_shadow && drop_shadow_size >= 0.0) {
		vec2 shadow_uv = UV - drop_shadow_offset * texel;
		float shadow_alpha = alpha_blur(TEXTURE, shadow_uv, texel, drop_shadow_size);
		shadow_alpha = clamp(shadow_alpha - base.a, 0.0, 1.0) * drop_shadow_opacity;
		vec4 shadow = vec4(drop_shadow_color.rgb, shadow_alpha * drop_shadow_color.a);
		out_color = mix(shadow, out_color, out_color.a);
		out_color.a = max(out_color.a, shadow.a);
	}

	COLOR = out_color;
}

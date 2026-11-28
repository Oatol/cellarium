shader_type canvas_item;
render_mode blend_mix, unshaded;

// v0.52.0 第二步原型：对齐 Cell Lab 的「每对象固定顶点 + fragment 造形」。
// 每个细胞只提交一个 quad（6 顶点），圆/内膜/核/细胞器/接触弦全部在这里算，
// 因此 per-cell 顶点数恒定，细胞数只影响实例数，不影响管线。
//
// 每细胞参数放在一张 RGBA32F 的 1 行纹理里，每细胞占 PARAM_TEXELS 个 texel：
//   +0 : body rgb + a
//   +1 : outline rgb + a
//   +2 : nucleus rgb + a
//   +3 : organelle rgb + 细胞器数量
//   +4..+7  : 最多 8 条接触弦，每条 (a.xy, b.xy)，每 texel 存 2 条
//   +8..+12 : 5 个细胞器 (局部偏移 xy, 半径比例)
//   +13..+15: 保留

const int PARAM_TEXELS = 16;
const int MAX_CHORDS = 8;
const int MAX_ORGANELLES = 5;

uniform sampler2D cell_params : filter_nearest, repeat_disable;
uniform int cell_count = 1;
// 纹理实际宽度（texel 数）。纹理按容量分配，可能大于 cell_count * PARAM_TEXELS，
// 所以 UV 必须用真实宽度算，不能用细胞数反推。
uniform float tex_width = 16.0;
// 以下都是「半径归一化」后的局部单位（1.0 = 细胞半径）。
uniform float outline_width = 0.07;
uniform float inner_ring_radius = 0.62;
uniform float inner_ring_width = 0.05;
uniform float nucleus_radius = 0.15;

varying vec4 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
}

vec4 fetch4(float cell_index, int offset) {
	float u = (cell_index * float(PARAM_TEXELS) + float(offset) + 0.5) / tex_width;
	return texture(cell_params, vec2(u, 0.5));
}

// 直线 a-b 把平面分成两侧；保留包含原点的那一侧，返回该侧的半平面距离。
// 距离 <= 0 表示在内侧。
float half_plane(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	if (dot(ab, ab) < 1e-8) {
		return -1e9; // 空槽：不参与裁剪
	}
	vec2 n = normalize(vec2(-ab.y, ab.x));
	// 保留包含原点的那一侧：要求 dot(origin - a, n) <= 0，否则把法线翻过来。
	if (dot(-a, n) > 0.0) {
		n = -n;
	}
	return dot(p - a, n);
}

void over(inout vec3 rgb, inout float alpha, vec4 src) {
	float out_a = src.a + alpha * (1.0 - src.a);
	if (out_a > 0.00001) {
		rgb = (src.rgb * src.a + rgb * alpha * (1.0 - src.a)) / out_a;
	}
	alpha = out_a;
}

void fragment() {
	float cell_index = floor(v_custom.x + 0.5);
	vec2 p = (UV - 0.5) * 2.0;

	// 有符号距离：圆的边界 + 每条接触弦的半平面，取最大值。
	float sd = length(p) - 1.0;
	for (int i = 0; i < MAX_CHORDS; i++) {
		int texel = 4 + i / 2;
		vec4 c = fetch4(cell_index, texel);
		vec2 a = (i % 2 == 0) ? c.xy : c.zw;
		vec2 b = (i % 2 == 0) ? c.zw : c.xy;
		sd = max(sd, half_plane(p, a, b));
	}

	float aa = max(fwidth(sd), 0.0015) * 1.2;

	vec4 body_color = fetch4(cell_index, 0);
	vec4 outline_color = fetch4(cell_index, 1);
	vec4 nucleus_color = fetch4(cell_index, 2);
	vec4 organelle_color = fetch4(cell_index, 3);

	vec3 rgb = vec3(0.0);
	float alpha = 0.0;

	// 细胞体（被接触弦切平）
	float body_mask = 1.0 - smoothstep(-aa, aa, sd);
	over(rgb, alpha, vec4(body_color.rgb, body_color.a * body_mask));

	// 外轮廓：沿「圆 + 弦」的合成边界，弦面上也有一圈，接触处不会缺边。
	float outline_mask = 1.0 - smoothstep(outline_width, outline_width + aa, abs(sd));
	over(rgb, alpha, vec4(outline_color.rgb, outline_color.a * outline_mask));

	// 内膜环：只在体内显示
	float ring_sd = abs(length(p) - inner_ring_radius);
	float ring_mask = 1.0 - smoothstep(inner_ring_width, inner_ring_width + aa, ring_sd);
	ring_mask *= 1.0 - smoothstep(-aa, aa, sd);
	over(rgb, alpha, vec4(outline_color.rgb, outline_color.a * 0.45 * ring_mask));

	// 细胞核
	float nucleus_mask = 1.0 - smoothstep(nucleus_radius, nucleus_radius + aa, length(p));
	nucleus_mask *= 1.0 - smoothstep(-aa, aa, sd);
	over(rgb, alpha, vec4(nucleus_color.rgb, nucleus_color.a * nucleus_mask));

	// 细胞器：5 个固定局部偏移的小圆
	int organelle_count = int(floor(organelle_color.a * 255.0 + 0.5));
	for (int k = 0; k < MAX_ORGANELLES; k++) {
		if (k >= organelle_count) {
			break;
		}
		vec4 slot = fetch4(cell_index, 8 + k);
		float r = max(slot.z, 0.01);
		float d = length(p - slot.xy) - r;
		float m = 1.0 - smoothstep(-aa, aa, d);
		m *= 1.0 - smoothstep(-aa, aa, sd);
		over(rgb, alpha, vec4(organelle_color.rgb, 0.72 * m));
	}

	COLOR = vec4(rgb, alpha);
}

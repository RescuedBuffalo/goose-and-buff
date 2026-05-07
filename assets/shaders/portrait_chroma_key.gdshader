// Portrait chroma-key shader (BUF-181 placeholder).
//
// The Scenario-generated character portraits (buffalo_character.png et al)
// ship on a solid cream "parchment" background — that's the asset canon
// for portrait reference, but for in-world rendering we need the cream
// removed so the character reads against tiles + shadows.
//
// This shader is a placeholder used only for the portrait-as-sprite
// validation. Once Phase 3 lands (Skeleton2D rigs assembled from
// rigging-sheet AtlasTextures with proper alpha) the rigs render without
// this shader.
//
// Tunable uniforms (exposed on the ShaderMaterial in the inspector):
//   key_color   — the background color to remove. Sampled cream is
//                 ~(0.988, 0.969, 0.910). Per-portrait variance is small
//                 so one value works for all 7 placeholders.
//   threshold   — RGB-distance under which a pixel counts as background.
//                 0.06 catches all the cream variations without eating
//                 light fur (Buffalo cream highlights, polar-bear belly).
//   smoothness  — soft-edge falloff. Small (~0.02) to avoid haloing.

shader_type canvas_item;

uniform vec3 key_color : source_color = vec3(0.988, 0.969, 0.910);
uniform float threshold : hint_range(0.0, 0.5) = 0.06;
uniform float smoothness : hint_range(0.0, 0.2) = 0.02;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float d = distance(tex.rgb, key_color);
	float mask = smoothstep(threshold, threshold + smoothness, d);
	COLOR = vec4(tex.rgb, tex.a * mask);
}

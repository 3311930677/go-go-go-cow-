class_name RewindFx
extends CanvasLayer
## 时光回闪的"老旧胶片"全屏特效：噪点 + 扫描线 + 暗角。
## 用一个极简 canvas_item shader 实现——刻意保留廉价颗粒感。

const SHADER := """
shader_type canvas_item;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	// 颗粒噪点（低分辨率块状——廉价胶片）
	float n = hash(floor(uv * vec2(320.0, 180.0)) + floor(TIME * 24.0));
	// 扫描线
	float scan = step(0.5, fract(uv.y * 90.0)) * 0.12;
	// 暗角
	vec2 c = uv - 0.5;
	float vig = 1.0 - smoothstep(0.3, 0.8, length(c));
	float a = intensity * (0.5 + n * 0.35) * vig;
	vec3 tint = vec3(0.9, 0.85, 0.7) * (0.3 + n * 0.7) + scan;
	COLOR = vec4(tint, a);
}
"""

var _rect: ColorRect
var _mat: ShaderMaterial
var _t := 0.0
var _dur := 0.0


func _ready() -> void:
	layer = 25
	var shader := Shader.new()
	shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = shader

	_rect = ColorRect.new()
	_rect.name = "FilmGrain"
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.visible = false
	add_child(_rect)


## 播放：intensity 从 1 衰减到 0，dur 秒结束
func play(duration: float) -> void:
	_dur = maxf(duration, 0.1)
	_t = 0.0
	_rect.visible = true
	_mat.set_shader_parameter("intensity", 1.0)


func _process(delta: float) -> void:
	if not _rect.visible:
		return
	_t += delta
	var k := 1.0 - _t / _dur
	if k <= 0.0:
		_rect.visible = false
		_mat.set_shader_parameter("intensity", 0.0)
	else:
		_mat.set_shader_parameter("intensity", k)

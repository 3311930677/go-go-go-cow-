class_name Flashback
extends CanvasLayer
## 闪回过场：全黑画面 + 逐行渐显的白字——"原来这一切只是小牛吃奶时做的一个梦"。
## 播放完毕（或任意键跳过）后发出 done 信号。

signal done

const LINES := [
	"……",
	"草原、飞天、那面结实的墙、金牛雕像……",
	"——原来这一切",
	"只是小牛吃奶时做的一个梦。",
]
const LINE_INTERVAL := 0.9  # 每行间隔（秒）

var _panel: Control
var _clock := 0.0
var _playing := false
var _finished := false


func _ready() -> void:
	layer = 40
	visible = false
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.draw.connect(_draw_scene)
	add_child(_panel)


func _process(delta: float) -> void:
	if not _playing or _finished:
		return
	_clock += delta
	_panel.queue_redraw()
	var total := LINE_INTERVAL * LINES.size() + 1.2
	if _clock >= total:
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if _playing and not _finished and event.is_pressed():
		_finish()


## 开始播放
func play() -> void:
	visible = true
	_playing = true
	_finished = false
	_clock = 0.0


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_playing = false
	visible = false
	done.emit()


func _draw_scene() -> void:
	var vp := _panel.get_viewport_rect().size
	var font := ThemeDB.fallback_font
	# 全黑
	_panel.draw_rect(Rect2(Vector2.ZERO, vp), Color.BLACK)
	# 逐行渐显白字
	for i in LINES.size():
		var appear_at := 0.4 + i * LINE_INTERVAL
		if _clock < appear_at:
			break
		var alpha := clampf((_clock - appear_at) / 0.5, 0.0, 1.0)
		var line: String = LINES[i]
		var y: float = vp.y * 0.38 + i * 44.0
		var x: float = vp.x * 0.5 - line.length() * 13.0
		_panel.draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1, alpha))
	# 底部提示
	if _clock > 1.0:
		_panel.draw_string(font, Vector2(vp.x * 0.5 - 110.0, vp.y - 40.0), "（按任意键跳过）", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.5, 0.5))

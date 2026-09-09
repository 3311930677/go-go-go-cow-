class_name SfxBank
extends Node
## 程序化音效库：全部用代码合成 PCM（AudioStreamWAV，44100Hz 16bit）。
## 刻意"廉价"的合成音色——配得上"手搓大作"的定位。
## 用法：sfx.play("moo")，可带随机变调制造机械重复中的荒诞感。

const SAMPLE_RATE := 44100

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_build_all()


func play(stream_name: String, volume_db := 0.0, pitch_jitter := 0.06) -> void:
	if not _streams.has(stream_name):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[stream_name]
	p.volume_db = volume_db
	p.pitch_scale = clampf(1.0 + randf_range(-pitch_jitter, pitch_jitter), 0.5, 2.0)
	p.play()


# ————————————————— 合成 —————————————————

## 通用合成器：频率从 f0 滑到 f1，波形 type（"sine"/"square"/"saw"/"noise"），
## wobble 为颤音频率（0 = 无）。音量包络：快起慢落。
func _synth(dur: float, f0: float, f1: float, type: String, vol: float, wobble := 0.0) -> AudioStreamWAV:
	var n := int(dur * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(f0, f1, t)
		if wobble > 0.0:
			f *= 1.0 + sin(TAU * wobble * i / SAMPLE_RATE) * 0.06
		phase += TAU * f / SAMPLE_RATE
		var s := 0.0
		match type:
			"sine": s = sin(phase)
			"square": s = 1.0 if fmod(phase, TAU) < PI else -1.0
			"saw": s = fmod(phase, TAU) / PI - 1.0
			"noise": s = randf_range(-1.0, 1.0)
		# 包络：前 5% 快起，后 30% 缓落
		var env := 1.0
		if t < 0.05:
			env = t / 0.05
		elif t > 0.7:
			env = (1.0 - t) / 0.3
		var v := int(clampf(s * env * vol, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	return wav


func _build_all() -> void:
	# 哞叫：低频方波下滑 + 颤音——毫无感染力的电子牛叫
	_streams["moo"] = _synth(0.55, 185.0, 125.0, "square", 0.32, 24.0)
	# 跳跃：短促上滑正弦
	_streams["jump"] = _synth(0.14, 300.0, 620.0, "sine", 0.30)
	# 吃草：三段白噪声（咔嚓咔嚓咔嚓）
	_streams["eat"] = _synth(0.42, 100.0, 100.0, "noise", 0.22)
	# 冲撞：低频锯齿加速
	_streams["charge"] = _synth(0.30, 90.0, 170.0, "saw", 0.30)
	# 飞天：夸张的长上滑——"咻——！"
	_streams["fly"] = _synth(0.7, 220.0, 920.0, "sine", 0.33)
	# 落地弹跳：颤音下滑
	_streams["bounce"] = _synth(0.25, 520.0, 200.0, "sine", 0.30, 55.0)
	# 事件号角：低沉双音——"哔——噗"
	_streams["event"] = _synth(0.5, 220.0, 165.0, "saw", 0.25, 8.0)
	# 任务完成：清脆"叮～"
	_streams["ding"] = _synth(0.45, 880.0, 870.0, "sine", 0.28)
	# UI 点击：极短方波
	_streams["click"] = _synth(0.05, 440.0, 440.0, "square", 0.20)
	# 现实踉跄：无力低哼
	_streams["stumble"] = _synth(0.22, 130.0, 82.0, "sine", 0.26)
	# —— P1-B 战斗 ——
	# 长角：清亮上扬的双音
	_streams["horn"] = _synth(0.4, 620.0, 980.0, "sine", 0.26)
	# 处决：刺耳骤降的锯齿（残忍但短）
	_streams["exec"] = _synth(0.6, 880.0, 210.0, "saw", 0.32, 40.0)
	# 挨打：白噪声闷响
	_streams["hit"] = _synth(0.12, 150.0, 110.0, "noise", 0.3)
	# 死亡：长叹下滑（毫无尊严）
	_streams["death"] = _synth(0.9, 320.0, 55.0, "sine", 0.34, 12.0)
	# —— P1-C 狼群 ——
	# 狼出现：跑调口哨——正弦高频 + 强颤音随机漂移，故意难听
	_streams["wolf"] = _synth(0.7, 760.0, 1180.0, "sine", 0.28, 30.0)
	# 被咬：尖利短促的锯齿（"砰——咔"）
	_streams["bite"] = _synth(0.18, 260.0, 90.0, "saw", 0.34)

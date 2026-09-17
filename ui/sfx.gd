class_name Sfx
extends RefCounted
## 程序生成音效（不引入外部素材）：正弦脉冲写入 AudioStreamWAV，按名缓存复用。
## 提供出牌、收分、比赛胜/负四类提示音。

const SAMPLE_RATE := 11025
const MAX_VOLUME := 0.3
const GAP_SECONDS := 0.03

static var _cache := {}


## 出牌：短促单击声。
static func card_play() -> AudioStreamWAV:
	return _cached("card", [[660.0, 0.07]])


## 收分：上扬双音。
static func score() -> AudioStreamWAV:
	return _cached("score", [[520.0, 0.09], [780.0, 0.12]])


## 比赛胜利：上行三音。
static func match_win() -> AudioStreamWAV:
	return _cached("win", [[523.0, 0.14], [659.0, 0.14], [784.0, 0.3]])


## 比赛失利：下行双音。
static func match_lose() -> AudioStreamWAV:
	return _cached("lose", [[392.0, 0.2], [311.0, 0.34]])


static func _cached(key: String, notes: Array) -> AudioStreamWAV:
	if not _cache.has(key):
		_cache[key] = _render(notes)
	return _cache[key]


# notes 为 [频率 Hz, 时长秒] 序列；单音内 10% 起音 + 线性衰减防爆音。
static func _render(notes: Array) -> AudioStreamWAV:
	var total := 0
	for note in notes:
		total += int((float(note[1]) + GAP_SECONDS) * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(total * 2)
	var frame := 0
	for note in notes:
		var freq: float = note[0]
		var count := int(float(note[1]) * SAMPLE_RATE)
		for i in count:
			var t := float(i) / SAMPLE_RATE
			var envelope := minf(float(i) / (count * 0.1), 1.0) * (1.0 - float(i) / count)
			var sample := int(sin(TAU * freq * t) * envelope * MAX_VOLUME * 32767.0)
			data.encode_s16(frame * 2, sample)
			frame += 1
		frame += int(GAP_SECONDS * SAMPLE_RATE)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = data
	return stream

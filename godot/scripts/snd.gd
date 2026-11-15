extends Node
# Route Defense - sound (autoload "Snd"): one music player reused for every song (two songs can never play at once),
# and a few players for sound effects. Songs and effects are the ROMs' own (snd/*.mp3).
var music: AudioStreamPlayer
var fx: Array[AudioStreamPlayer] = []
var cur := ""; var want := ""
var last := {}
const VOL := 0.5; const SFX_VOL := 0.6

func _ready() -> void:
	music = AudioStreamPlayer.new(); add_child(music); music.volume_db = linear_to_db(VOL)
	for i in 6:
		var p := AudioStreamPlayer.new(); p.volume_db = linear_to_db(SFX_VOL); add_child(p); fx.append(p)
func muted() -> bool: return C.G != null and C.G.opts.get("mute", false)
func _stream(f: String) -> AudioStream:
	var p := "res://snd/%s.mp3" % f
	return load(p) if ResourceLoader.exists(p) else null
func play_music(key: String) -> void:
	want = key
	var f = C.DB.snd.music.get(key, null)
	if f == null or cur == f: return
	cur = f
	var s = _stream(f)
	if s == null: return
	if s is AudioStreamMP3: s.loop = not (key.ends_with("win") or key.ends_with("lose"))   # the victory / defeat jingles play once
	music.stream = s
	if not muted(): music.play()
func set_mute(m: bool) -> void:
	if m: music.stop()
	elif music.stream: music.play()
func sfx(key: String) -> void:
	if muted(): return
	var f = C.DB.snd.sfx.get(key, null)
	if f == null: return
	var now := Time.get_ticks_msec()
	if now - last.get(key, 0) < 90: return
	last[key] = now
	for p in fx:
		if not p.playing:
			p.stream = _stream(f); p.play(); return

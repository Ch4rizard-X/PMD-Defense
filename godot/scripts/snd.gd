extends Node
# Route Defense - sound (autoload "Snd"): one music player reused for every song (two songs can never play at once),
# and a few players for sound effects. Songs and effects are the ROMs' own (snd/*.mp3).
var music: AudioStreamPlayer
var fx: Array[AudioStreamPlayer] = []
var cur := ""; var want := ""
var last := {}
var mvfx: Array[AudioStreamPlayer] = []; var mv_last := {}; var mv_any := 0
const VOL := 0.5; const SFX_VOL := 0.6

func _ready() -> void:
	music = AudioStreamPlayer.new(); add_child(music); music.volume_db = linear_to_db(VOL)
	for i in 6:
		var p := AudioStreamPlayer.new(); p.volume_db = linear_to_db(SFX_VOL); add_child(p); fx.append(p)
	for i in 4:   # move sounds have their own players, so a busy battle never cuts off menu / level-up sounds
		var p := AudioStreamPlayer.new(); p.volume_db = linear_to_db(SFX_VOL * 0.8); add_child(p); mvfx.append(p)
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
# a move's own sound (Explorers of Sky's, from its move-animation data; snd.bin "mv": move id -> file). Kept from
# becoming noise: the same sound at most every 0.12 s, any move sound at most every 0.05 s, and when all 4 move
# players are busy the new one is skipped (nothing is cut off).
func move_sfx(m: int) -> void:
	if muted(): return
	var f = C.DB.snd.get("mv", {}).get(m, null)
	if f == null: return
	var now := Time.get_ticks_msec()
	if now - mv_any < 50 or now - mv_last.get(f, -100000) < 120: return
	for p in mvfx:
		if not p.playing:
			var s = _stream(f)
			if s == null: return
			p.stream = s; p.play(); mv_any = now; mv_last[f] = now; return

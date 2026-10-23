extends SceneTree
## Отдельные картинки мода (mod.texture) → <name>.dds рядом: BC7 (BPTC, почти без потерь, с альфой) — в видеопамяти
## в 4 раза меньше несжатых. Игра берёт .dds, если он есть (assets.gd → Assets.tex), иначе — картинку как раньше.
## Mip-уровни — только там, где их и так строит игра (mip): интерфейс и картинки без mip остаются без них — вид тот же.
## Список — bc7_textures.txt: «путь [mip] [normal] [bc5]» (normal — mip с перенормировкой; bc5 — карта нормалей в BC5,
## два канала почти без потерь: только там, где её читают как NORMAL_MAP — z движок восстанавливает сам; если шейдер
## берёт .xyz (mountain.gdshader → ground_n) — BC7, z нужен). Стороны должны делиться на 4 (блоки BC) — иначе картинка
## выросла бы до кратного 4 и сдвинула вёрстку; такие (арты загрузки 1920×1079, рамка босса 1100×274) не берём.
## Картинки, из которых код читает пиксели на ЦП (маска дорог roads_mask.png и т. п.), сюда не входят.
## Запуск (редакторская сборка Godot — в игре сжатия нет):
##   godot --headless --path <любой проект> -s tex_bc7.gd -- <папка мода mods/pax_rpg> <список>
## В конце — сверка с исходником по каждой картинке: PSNR (дБ) и наибольшая ошибка канала (0..255).


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var root: String = a[0]
	for line: String in FileAccess.get_file_as_string(a[1]).split("\n"):
		var w := line.strip_edges().split(" ", false)
		if w.is_empty() or w[0].begins_with("#"):
			continue
		var rel: String = w[0]
		var mip := w.has("mip") or w.has("normal") or w.has("bc5")
		var normal := w.has("normal") or w.has("bc5")
		var bc5 := w.has("bc5")
		var src := Image.load_from_file(root.path_join(rel))
		if src == null or src.is_empty():
			print("нет ", rel)
			continue
		if src.get_width() % 4 != 0 or src.get_height() % 4 != 0:
			print("пропуск %s: %dx%d не кратно 4" % [rel, src.get_width(), src.get_height()])
			continue
		var t0 := Time.get_ticks_msec()
		src.convert(Image.FORMAT_RGBA8 if src.detect_alpha() != Image.ALPHA_NONE else Image.FORMAT_RGB8)
		var img := src.duplicate() as Image
		if mip:
			img.generate_mipmaps(normal)
		# цвет — с оценкой ошибки в sRGB; нормали и маски — как есть по каналам (BC7 хранит RGB, без восстановления z)
		var srgb := not normal and not rel.contains("_r.") and not rel.contains("_h.") and not rel.contains("mask")
		if bc5:
			img.convert(Image.FORMAT_RGB8)
			img.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_NORMAL)   # S3TC + нормаль → RGTC (BC5)
		else:
			img.compress(Image.COMPRESS_BPTC, Image.COMPRESS_SOURCE_SRGB if srgb else Image.COMPRESS_SOURCE_GENERIC)
		var out := root.path_join(rel.get_basename() + ".dds")
		img.save_dds(out)
		print("%s → %s %dx%d %s, %d КБ, %d мс, %s" % [rel, out.get_file(), img.get_width(), img.get_height(),
			"mip" if mip else "без mip", FileAccess.get_file_as_bytes(out).size() / 1024, Time.get_ticks_msec() - t0,
			compare(src, out, 2 if bc5 else 3)])
	quit()


## PSNR и наибольшая ошибка: верхний уровень DDS (прочитан обратно, как в игре) против исходника, первые ch каналов.
static func compare(src: Image, dds_path: String, ch: int) -> String:
	var back := Image.new()
	if back.load_dds_from_buffer(FileAccess.get_file_as_bytes(dds_path)) != OK:
		return "DDS не читается"
	var fmt := back.get_format()
	if back.get_size() != src.get_size():
		return "размер %s ≠ %s" % [back.get_size(), src.get_size()]
	back.decompress()
	back.clear_mipmaps()
	back.convert(Image.FORMAT_RGBA8)
	var s := src.duplicate() as Image
	s.clear_mipmaps()
	s.convert(Image.FORMAT_RGBA8)
	var pa := s.get_data()
	var pb := back.get_data()
	var se := 0.0
	var mx := 0
	var cnt := 0
	var chans := ch + (1 if src.detect_alpha() != Image.ALPHA_NONE and ch == 3 else 0)
	for i: int in range(0, pa.size(), 4):
		for k: int in chans:
			var d := absi(pa[i + k] - pb[i + k])
			se += d * d
			mx = maxi(mx, d)
		cnt += chans
	var mse := se / maxf(cnt, 1.0)
	var psnr := 99.0 if mse <= 0.0 else 10.0 * log(65025.0 / mse) / log(10.0)
	return "формат %d, PSNR %.1f дБ, макс. %d" % [fmt, psnr, mx]

extends SceneTree
## Текстуры материалов (CC0, Poly Haven) → сжатые DDS для мода: цвет — 4K BC1 (S3TC) с мипмапами,
## нормали — 2K BC5 (RGTC, два канала — меньше артефактов). Имя *_nor* — нормаль.
##   godot --headless -s tex_dds.gd -- <папка jpg> <папка dds>

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var src: String = a[0]
	var dst: String = a[1]
	DirAccess.make_dir_recursive_absolute(dst)
	for f: String in DirAccess.get_files_at(src):
		if not f.ends_with(".jpg") and not f.ends_with(".png"):
			continue
		var img := Image.load_from_file(src.path_join(f))
		var nor := f.contains("_nor")
		var mx := 2048 if nor else 4096
		if maxi(img.get_width(), img.get_height()) > mx:
			img.resize(mx, mx, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGB8)
		img.generate_mipmaps(nor)
		if nor:
			img.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_NORMAL)   # S3TC + нормаль → BC5
		else:
			img.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_SRGB)
		var out := dst.path_join(f.get_basename() + ".dds")
		img.save_dds(out)
		print(f, " → ", out, " ", img.get_width(), " ", img.get_format())
	quit()

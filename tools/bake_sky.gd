extends SceneTree

## Run with the three original Poly Haven HDR files renamed sunset.hdr, day.hdr and dusk.hdr.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("Supply the source directory after --")
		quit(2)
		return
	for preset in ["sunset", "day", "dusk"]:
		var photo := Image.load_from_file(args[0].path_join(preset + ".hdr"))
		if photo == null or photo.is_empty():
			quit(1)
			return
		photo.convert(Image.FORMAT_RGBF)
		photo.resize(1024, 512, Image.INTERPOLATE_LANCZOS)
		for y in photo.get_height():
			for x in photo.get_width():
				var sample := photo.get_pixel(x, y)
				var peak := maxf(maxf(sample.r, sample.g), sample.b)
				var shoulder := 0.84 / (2.34 * (1.0 + peak * 0.36))
				photo.set_pixel(x, y, Color(maxf(sample.r, 0.0) * shoulder, maxf(sample.g, 0.0) * shoulder, maxf(sample.b, 0.0) * shoulder).linear_to_srgb())
		photo.convert(Image.FORMAT_RGB8)
		if photo.save_png(ProjectSettings.globalize_path("res://assets/environment/%s.png" % preset)) != OK:
			quit(1)
			return
	quit()

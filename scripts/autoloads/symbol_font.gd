extends Node
## Puts DejaVu Sans under every font the game draws words with, so a symbol those fonts lack (the
## map's marks, the fight's icons, the arrows and triangles in the menus) is drawn from it.
##
## None of the bundled faces, nor Godot's built-in default, holds the symbols the game uses. A desktop
## build used to borrow them from a font of the operating system's, so they looked however that
## font drew them; a browser build has no system fonts and drew every one as an empty box. With
## DejaVu Sans as each font's fallback, every platform draws the same symbols, and a fallback the
## font lists is tried before the system's.
##
## Castoro is left out on purpose: it only prints numerals, it holds the ones it prints, and DejaVu's
## taller line would make its line box taller. The other fonts' line heights are unchanged by it.

const SYMBOL_FONT_PATH := "res://assets/fonts/dejavu_sans/DejaVuSans.ttf"
## Every font a control draws words with, besides Godot's default (ThemeDB.fallback_font).
const DRAWING_FONT_PATHS: Array[String] = [
	"res://assets/fonts/eb_garamond/EBGaramond-Variable.ttf",
	"res://assets/fonts/grenze_gotisch/GrenzeGotisch-Variable.ttf",
	"res://assets/fonts/grenze_gotisch/GrenzeGotisch-Bold.tres",
	"res://assets/fonts/marcellus_sc/MarcellusSC-Regular.ttf",
]

## Held for the life of the game, so the fonts stay in the resource cache with the fallback set:
## a font every reference let go of would load again without it.
var _fonts: Array[Font] = []


func _init() -> void:
	var symbols: Font = load(SYMBOL_FONT_PATH)
	if symbols == null:
		push_error("SymbolFont: %s did not load" % SYMBOL_FONT_PATH)
		return
	_fonts.append(symbols)
	var targets: Array[Font] = [ThemeDB.fallback_font]
	for path in DRAWING_FONT_PATHS:
		var font: Font = load(path)
		if font:
			targets.append(font)
	for font in targets:
		if font == null or font == symbols:
			continue
		var fallbacks: Array[Font] = font.fallbacks
		if not fallbacks.has(symbols):
			fallbacks.append(symbols)
			font.fallbacks = fallbacks
		_fonts.append(font)

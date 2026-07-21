package main

import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

// The returned string is allocated with context.allocator.
// The caller owns it and should call delete(result) when finished.
slugify :: proc(input: string) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	byte_offset := 0
	has_output := false
	pending_dash := false

	for byte_offset < len(input) {
		r, width := utf8.decode_rune_in_string(input[byte_offset:])
		if width <= 0 {
			break
		}
		byte_offset += width

		normalized, skip := normalize_slug_rune(r)
		if skip {
			continue
		}

		r = unicode.to_lower(normalized)

		if is_ascii_alphanumeric(r) {
			write_pending_slug_dash(&builder, &pending_dash, has_output)
			strings.write_byte(&builder, u8(r))
			has_output = true
			continue
		}

		replacement := transliterate_latin_slug_rune(r)
		if replacement != "" {
			write_pending_slug_dash(&builder, &pending_dash, has_output)
			strings.write_string(&builder, replacement)
			has_output = true
			continue
		}

		if unicode.is_combining(r) {
			continue
		}

		if has_output {
			pending_dash = true
		}
	}

	return strings.clone(strings.to_string(builder))
}

write_pending_slug_dash :: proc(builder: ^strings.Builder, pending_dash: ^bool, has_output: bool) {
	if pending_dash^ && has_output {
		strings.write_byte(builder, '-')
	}
	pending_dash^ = false
}

is_ascii_alphanumeric :: proc(r: rune) -> bool {
	return ('a' <= r && r <= 'z') || ('0' <= r && r <= '9')
}

normalize_slug_rune :: proc(r: rune) -> (normalized: rune, skip: bool) {
	if 'Ａ' <= r && r <= 'Ｚ' {
		offset := i32(r) - i32('Ａ')
		return rune(i32('A') + offset), false
	}

	if 'ａ' <= r && r <= 'ｚ' {
		offset := i32(r) - i32('ａ')
		return rune(i32('a') + offset), false
	}

	if '０' <= r && r <= '９' {
		offset := i32(r) - i32('０')
		return rune(i32('0') + offset), false
	}

	switch r {
	case '‐', '‑', '‒', '–', '—', '―', '−', '－':
		return '-', false
	case '\'', '’', '‘', '‛', '′', '＇':
		return 0, true
	case '\u00ad', '\u200b', '\u200c', '\u200d', '\u2060', '\ufeff':
		return 0, true
	}

	return r, false
}

transliterate_latin_slug_rune :: proc(r: rune) -> string {
	switch r {
	case 'à',
	     'á',
	     'â',
	     'ã',
	     'ä',
	     'å',
	     'ā',
	     'ă',
	     'ą',
	     'ǎ',
	     'ȁ',
	     'ȃ',
	     'ạ',
	     'ả',
	     'ấ',
	     'ầ',
	     'ẩ',
	     'ẫ',
	     'ậ',
	     'ắ',
	     'ằ',
	     'ẳ',
	     'ẵ',
	     'ặ':
		return "a"
	case 'æ', 'ǽ':
		return "ae"
	case 'ç', 'ć', 'ĉ', 'ċ', 'č':
		return "c"
	case 'ď', 'đ', 'ð':
		return "d"
	case 'è',
	     'é',
	     'ê',
	     'ë',
	     'ē',
	     'ĕ',
	     'ė',
	     'ę',
	     'ě',
	     'ȅ',
	     'ȇ',
	     'ẹ',
	     'ẻ',
	     'ẽ',
	     'ế',
	     'ề',
	     'ể',
	     'ễ',
	     'ệ':
		return "e"
	case 'ƒ':
		return "f"
	case 'ĝ', 'ğ', 'ġ', 'ģ':
		return "g"
	case 'ĥ', 'ħ':
		return "h"
	case 'ì', 'í', 'î', 'ï', 'ĩ', 'ī', 'ĭ', 'į', 'ı', 'ǐ', 'ȉ', 'ȋ', 'ị', 'ỉ':
		return "i"
	case 'ĵ':
		return "j"
	case 'ķ':
		return "k"
	case 'ĺ', 'ļ', 'ľ', 'ŀ', 'ł':
		return "l"
	case 'ñ', 'ń', 'ņ', 'ň', 'ŋ':
		return "n"
	case 'ò',
	     'ó',
	     'ô',
	     'õ',
	     'ö',
	     'ø',
	     'ō',
	     'ŏ',
	     'ő',
	     'ǒ',
	     'ȍ',
	     'ȏ',
	     'ọ',
	     'ỏ',
	     'ố',
	     'ồ',
	     'ổ',
	     'ỗ',
	     'ộ',
	     'ơ',
	     'ớ',
	     'ờ',
	     'ở',
	     'ỡ',
	     'ợ':
		return "o"
	case 'œ':
		return "oe"
	case 'ŕ', 'ŗ', 'ř':
		return "r"
	case 'ś', 'ŝ', 'ş', 'š', 'ș':
		return "s"
	case 'ß':
		return "ss"
	case 'ţ', 'ť', 'ŧ', 'ț':
		return "t"
	case 'þ':
		return "th"
	case 'ù',
	     'ú',
	     'û',
	     'ü',
	     'ũ',
	     'ū',
	     'ŭ',
	     'ů',
	     'ű',
	     'ų',
	     'ǔ',
	     'ȕ',
	     'ȗ',
	     'ụ',
	     'ủ',
	     'ư',
	     'ứ',
	     'ừ',
	     'ử',
	     'ữ',
	     'ự':
		return "u"
	case 'ŵ':
		return "w"
	case 'ý', 'ÿ', 'ŷ', 'ỳ', 'ỵ', 'ỷ', 'ỹ':
		return "y"
	case 'ź', 'ż', 'ž':
		return "z"
	}

	return ""
}

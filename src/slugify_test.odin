package main

import "core:testing"

@(test, require)
test_slugify_english_text :: proc(t: ^testing.T) {
	result := slugify("Hello, world! Don't Stop 2026")
	defer delete(result)

	testing.expect_value(t, result, "hello-world-dont-stop-2026")
}

@(test, require)
test_slugify_vietnamese_text :: proc(t: ^testing.T) {
	result := slugify("Ảnh Đẹp Ở Việt Nam 2026")
	defer delete(result)

	testing.expect_value(t, result, "anh-dep-o-viet-nam-2026")
}

@(test, require)
test_slugify_camel_and_pascal_case_do_not_gain_dashes :: proc(t: ^testing.T) {
	camel := slugify("camelCase")
	defer delete(camel)
	pascal := slugify("PascalCase")
	defer delete(pascal)
	combined := slugify("camelCase PascalCase")
	defer delete(combined)

	testing.expect_value(t, camel, "camelcase")
	testing.expect_value(t, pascal, "pascalcase")
	testing.expect_value(t, combined, "camelcase-pascalcase")
}

@(test, require)
test_slugify_decomposed_vietnamese_marks :: proc(t: ^testing.T) {
	result := slugify("To\u0302i a\u0306n pho\u031b")
	defer delete(result)

	testing.expect_value(t, result, "toi-an-pho")
}

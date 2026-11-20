extends GutTest
## Look-sensitivity validation for settings that parse but hold bad values.


func test_valid_numbers_pass_through() -> void:
	assert_eq(ThirdPersonCamera.sanitize_sensitivity(2.5), 2.5)
	assert_eq(ThirdPersonCamera.sanitize_sensitivity(2), 2.0)


func test_invalid_values_fall_back_to_default() -> void:
	var bad: Array[Variant] = [0.0, -1.0, NAN, INF, -INF, "fast", null, true, [1.0], Vector2.ONE]
	for value: Variant in bad:
		assert_eq(ThirdPersonCamera.sanitize_sensitivity(value), 1.0, "bad value: %s" % [value])

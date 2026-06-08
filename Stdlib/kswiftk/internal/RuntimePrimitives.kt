package kswiftk.internal

// MARK: - Numeric bit operations

@KSwiftKRuntimeName("kk_int_countOneBits")
external fun __intCountOneBits(value: Int): Int

@KSwiftKRuntimeName("kk_int_countLeadingZeroBits")
external fun __intCountLeadingZeroBits(value: Int): Int

@KSwiftKRuntimeName("kk_int_countTrailingZeroBits")
external fun __intCountTrailingZeroBits(value: Int): Int

@KSwiftKRuntimeName("kk_int_highestOneBit")
external fun __intHighestOneBit(value: Int): Int

@KSwiftKRuntimeName("kk_int_lowestOneBit")
external fun __intLowestOneBit(value: Int): Int

@KSwiftKRuntimeName("kk_int_rotateLeft")
external fun __intRotateLeft(value: Int, distance: Int): Int

@KSwiftKRuntimeName("kk_int_rotateRight")
external fun __intRotateRight(value: Int, distance: Int): Int

@KSwiftKRuntimeName("kk_long_highestOneBit")
external fun __longHighestOneBit(value: Long): Long

@KSwiftKRuntimeName("kk_long_lowestOneBit")
external fun __longLowestOneBit(value: Long): Long

@KSwiftKRuntimeName("kk_long_rotateLeft")
external fun __longRotateLeft(value: Long, distance: Int): Long

@KSwiftKRuntimeName("kk_long_rotateRight")
external fun __longRotateRight(value: Long, distance: Int): Long

// MARK: - Floating point classification

@KSwiftKRuntimeName("kk_double_isNaN")
external fun __doubleIsNaN(value: Double): Boolean

@KSwiftKRuntimeName("kk_double_isInfinite")
external fun __doubleIsInfinite(value: Double): Boolean

@KSwiftKRuntimeName("kk_float_isNaN")
external fun __floatIsNaN(value: Float): Boolean

@KSwiftKRuntimeName("kk_float_isInfinite")
external fun __floatIsInfinite(value: Float): Boolean

// MARK: - Preconditions and TODO

@KSwiftKRuntimeName("kk_require_lazy")
external fun __requireLazy(condition: Boolean, lazyMessage: () -> Any)

@KSwiftKRuntimeName("kk_check_lazy")
external fun __checkLazy(condition: Boolean, lazyMessage: () -> Any)

@KSwiftKRuntimeName("kk_precondition_assert")
external fun __assert(value: Boolean)

@KSwiftKRuntimeName("kk_precondition_assert_lazy")
external fun __assertLazy(value: Boolean, lazyMessage: () -> Any)

@KSwiftKRuntimeName("kk_todo_noarg")
external fun __todo(): Nothing

@KSwiftKRuntimeName("kk_todo")
external fun __todo(reason: String): Nothing

// MARK: - Console IO

@KSwiftKRuntimeName("kk_println_newline")
external fun __println()

@KSwiftKRuntimeName("kk_println_any")
external fun __println(message: Any?)

@KSwiftKRuntimeName("kk_print_noarg")
external fun __print()

@KSwiftKRuntimeName("kk_print_any")
external fun __print(message: Any?)

@KSwiftKRuntimeName("kk_readlnOrNull")
external fun __readlnOrNull(): String?

@KSwiftKRuntimeName("kk_system_exitProcess")
external fun __exitProcess(status: Int): Nothing

// MARK: - Time functions (system-level APIs)

@KSwiftKRuntimeName("kk_system_getTimeMicros")
external fun __getTimeMicros(): Long

@KSwiftKRuntimeName("kk_system_getTimeMillis")
external fun __getTimeMillis(): Long

@KSwiftKRuntimeName("kk_system_getTimeNanos")
external fun __getTimeNanos(): Long

// MARK: - Synchronization (necessary for thread safety)

@KSwiftKRuntimeName("kk_synchronized")
external fun __synchronized(lock: Any, block: () -> Any?): Any

// MARK: - Floating point bit operations (low-level bit manipulation)

@KSwiftKRuntimeName("kk_double_toBits")
external fun __doubleToBits(value: Double): Long

@KSwiftKRuntimeName("kk_double_toRawBits")
external fun __doubleToRawBits(value: Double): Long

@KSwiftKRuntimeName("kk_float_toBits")
external fun __floatToBits(value: Float): Int

@KSwiftKRuntimeName("kk_float_toRawBits")
external fun __floatToRawBits(value: Float): Int

@KSwiftKRuntimeName("kk_double_fromBits")
external fun __doubleFromBits(bits: Long): Double

@KSwiftKRuntimeName("kk_float_fromBits")
external fun __floatFromBits(bits: Int): Float

// MARK: - Math runtime operations

@KSwiftKRuntimeName("kk_math_sqrt")
external fun __mathSqrt(value: Double): Double

@KSwiftKRuntimeName("kk_math_sqrt_float")
external fun __mathSqrt(value: Float): Float

@KSwiftKRuntimeName("kk_math_ceil")
external fun __mathCeil(value: Double): Double

@KSwiftKRuntimeName("kk_math_ceil_float")
external fun __mathCeil(value: Float): Float

@KSwiftKRuntimeName("kk_math_floor")
external fun __mathFloor(value: Double): Double

@KSwiftKRuntimeName("kk_math_floor_float")
external fun __mathFloor(value: Float): Float

@KSwiftKRuntimeName("kk_math_round")
external fun __mathRound(value: Double): Double

@KSwiftKRuntimeName("kk_math_round_float")
external fun __mathRound(value: Float): Float

@KSwiftKRuntimeName("kk_math_truncate")
external fun __mathTruncate(value: Double): Double

@KSwiftKRuntimeName("kk_math_truncate_float")
external fun __mathTruncate(value: Float): Float

@KSwiftKRuntimeName("kk_math_sin")
external fun __mathSin(value: Double): Double

@KSwiftKRuntimeName("kk_math_sin_float")
external fun __mathSin(value: Float): Float

@KSwiftKRuntimeName("kk_math_cos")
external fun __mathCos(value: Double): Double

@KSwiftKRuntimeName("kk_math_cos_float")
external fun __mathCos(value: Float): Float

@KSwiftKRuntimeName("kk_math_tan")
external fun __mathTan(value: Double): Double

@KSwiftKRuntimeName("kk_math_tan_float")
external fun __mathTan(value: Float): Float

@KSwiftKRuntimeName("kk_math_asin")
external fun __mathAsin(value: Double): Double

@KSwiftKRuntimeName("kk_math_asin_float")
external fun __mathAsin(value: Float): Float

@KSwiftKRuntimeName("kk_math_acos")
external fun __mathAcos(value: Double): Double

@KSwiftKRuntimeName("kk_math_acos_float")
external fun __mathAcos(value: Float): Float

@KSwiftKRuntimeName("kk_math_atan")
external fun __mathAtan(value: Double): Double

@KSwiftKRuntimeName("kk_math_atan_float")
external fun __mathAtan(value: Float): Float

@KSwiftKRuntimeName("kk_math_atan2")
external fun __mathAtan2(y: Double, x: Double): Double

@KSwiftKRuntimeName("kk_math_atan2_float")
external fun __mathAtan2(y: Float, x: Float): Float

@KSwiftKRuntimeName("kk_math_exp")
external fun __mathExp(value: Double): Double

@KSwiftKRuntimeName("kk_math_exp_float")
external fun __mathExp(value: Float): Float

@KSwiftKRuntimeName("kk_math_expm1")
external fun __mathExpm1(value: Double): Double

@KSwiftKRuntimeName("kk_math_expm1_float")
external fun __mathExpm1(value: Float): Float

@KSwiftKRuntimeName("kk_math_ln")
external fun __mathLn(value: Double): Double

@KSwiftKRuntimeName("kk_math_ln_float")
external fun __mathLn(value: Float): Float

@KSwiftKRuntimeName("kk_math_ln1p")
external fun __mathLn1p(value: Double): Double

@KSwiftKRuntimeName("kk_math_ln1p_float")
external fun __mathLn1p(value: Float): Float

@KSwiftKRuntimeName("kk_math_log2")
external fun __mathLog2(value: Double): Double

@KSwiftKRuntimeName("kk_math_log2_float")
external fun __mathLog2(value: Float): Float

@KSwiftKRuntimeName("kk_math_log10")
external fun __mathLog10(value: Double): Double

@KSwiftKRuntimeName("kk_math_log10_float")
external fun __mathLog10(value: Float): Float

@KSwiftKRuntimeName("kk_math_sinh")
external fun __mathSinh(value: Double): Double

@KSwiftKRuntimeName("kk_math_sinh_float")
external fun __mathSinh(value: Float): Float

@KSwiftKRuntimeName("kk_math_cosh")
external fun __mathCosh(value: Double): Double

@KSwiftKRuntimeName("kk_math_cosh_float")
external fun __mathCosh(value: Float): Float

@KSwiftKRuntimeName("kk_math_tanh")
external fun __mathTanh(value: Double): Double

@KSwiftKRuntimeName("kk_math_tanh_float")
external fun __mathTanh(value: Float): Float

@KSwiftKRuntimeName("kk_math_cbrt")
external fun __mathCbrt(value: Double): Double

@KSwiftKRuntimeName("kk_math_cbrt_float")
external fun __mathCbrt(value: Float): Float

@KSwiftKRuntimeName("kk_math_acosh")
external fun __mathAcosh(value: Double): Double

@KSwiftKRuntimeName("kk_math_acosh_float")
external fun __mathAcosh(value: Float): Float

@KSwiftKRuntimeName("kk_math_asinh")
external fun __mathAsinh(value: Double): Double

@KSwiftKRuntimeName("kk_math_asinh_float")
external fun __mathAsinh(value: Float): Float

@KSwiftKRuntimeName("kk_math_atanh")
external fun __mathAtanh(value: Double): Double

@KSwiftKRuntimeName("kk_math_atanh_float")
external fun __mathAtanh(value: Float): Float

@KSwiftKRuntimeName("kk_math_hypot")
external fun __mathHypot(x: Double, y: Double): Double

@KSwiftKRuntimeName("kk_math_hypot_float")
external fun __mathHypot(x: Float, y: Float): Float

@KSwiftKRuntimeName("kk_double_ulp")
external fun __doubleUlp(value: Double): Double

@KSwiftKRuntimeName("kk_float_ulp")
external fun __floatUlp(value: Float): Float

@KSwiftKRuntimeName("kk_double_nextUp")
external fun __doubleNextUp(value: Double): Double

@KSwiftKRuntimeName("kk_float_nextUp")
external fun __floatNextUp(value: Float): Float

@KSwiftKRuntimeName("kk_double_nextDown")
external fun __doubleNextDown(value: Double): Double

@KSwiftKRuntimeName("kk_float_nextDown")
external fun __floatNextDown(value: Float): Float

@KSwiftKRuntimeName("kk_double_roundToInt")
external fun __doubleRoundToInt(value: Double): Int

@KSwiftKRuntimeName("kk_float_roundToInt")
external fun __floatRoundToInt(value: Float): Int

@KSwiftKRuntimeName("kk_double_roundToLong")
external fun __doubleRoundToLong(value: Double): Long

@KSwiftKRuntimeName("kk_float_roundToLong")
external fun __floatRoundToLong(value: Float): Long

@KSwiftKRuntimeName("kk_math_pow")
external fun __mathPow(value: Double, exponent: Double): Double

@KSwiftKRuntimeName("kk_math_pow_float")
external fun __mathPow(value: Float, exponent: Float): Float

@KSwiftKRuntimeName("kk_math_max")
external fun __mathMax(a: Double, b: Double): Double

@KSwiftKRuntimeName("kk_math_max_float")
external fun __mathMax(a: Float, b: Float): Float

@KSwiftKRuntimeName("kk_math_min")
external fun __mathMin(a: Double, b: Double): Double

@KSwiftKRuntimeName("kk_math_min_float")
external fun __mathMin(a: Float, b: Float): Float

// MARK: - Test assertions

@KSwiftKRuntimeName("kk_test_assertEquals")
external fun __testAssertEquals(expected: Any?, actualValue: Any?)

@KSwiftKRuntimeName("kk_test_assertEquals_message")
external fun __testAssertEqualsMessage(expected: Any?, actualValue: Any?, message: Any?)

@KSwiftKRuntimeName("kk_test_assertTrue")
external fun __testAssertTrue(actualValue: Boolean)

@KSwiftKRuntimeName("kk_test_assertTrue_message")
external fun __testAssertTrueMessage(actualValue: Boolean, message: Any?)

@KSwiftKRuntimeName("kk_test_assertNull")
external fun __testAssertNull(actualValue: Any?)

@KSwiftKRuntimeName("kk_test_assertNull_message")
external fun __testAssertNullMessage(actualValue: Any?, message: Any?)

// MARK: - Char functions (Unicode-dependent, require runtime)

@KSwiftKRuntimeName("kk_char_isDigit")
external fun __char_isDigit(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isLetter")
external fun __char_isLetter(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isLetterOrDigit")
external fun __char_isLetterOrDigit(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isUpperCase")
external fun __char_isUpperCase(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isLowerCase")
external fun __char_isLowerCase(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isWhitespace")
external fun __char_isWhitespace(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isDefined")
external fun __char_isDefined(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isSurrogate")
external fun __char_isSurrogate(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isHighSurrogate")
external fun __char_isHighSurrogate(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isLowSurrogate")
external fun __char_isLowSurrogate(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isISOControl")
external fun __char_isISOControl(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isTitleCase")
external fun __char_isTitleCase(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isJavaIdentifierPart")
external fun __char_isJavaIdentifierPart(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isIdentifierIgnorable")
external fun __char_isIdentifierIgnorable(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isUnicodeIdentifierPart")
external fun __char_isUnicodeIdentifierPart(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_isJavaIdentifierStart")
external fun __char_isJavaIdentifierStart(c: Char): Boolean

@KSwiftKRuntimeName("kk_char_uppercaseChar")
external fun __char_uppercaseChar(c: Char): Char

@KSwiftKRuntimeName("kk_char_lowercaseChar")
external fun __char_lowercaseChar(c: Char): Char

@KSwiftKRuntimeName("kk_char_titlecaseChar")
external fun __char_titlecaseChar(c: Char): Char

@KSwiftKRuntimeName("kk_char_uppercase")
external fun __char_uppercase(c: Char): Char

@KSwiftKRuntimeName("kk_char_lowercase")
external fun __char_lowercase(c: Char): Char

@KSwiftKRuntimeName("kk_char_titlecase")
external fun __char_titlecase(c: Char): Char

@KSwiftKRuntimeName("kk_char_digitToInt")
external fun __char_digitToInt(c: Char): Int

@KSwiftKRuntimeName("kk_char_digitToIntOrNull")
external fun __char_digitToIntOrNull(c: Char): Int?

@KSwiftKRuntimeName("kk_char_digitToInt_radix")
external fun __char_digitToInt_radix(c: Char, radix: Int): Int

// MARK: - String struct field access functions (new struct-based representation)

@KSwiftKRuntimeName("kk_string_struct_get_length")
external fun __string_struct_get_length(s: String): Int

// MARK: - String operations still requiring runtime support

@KSwiftKRuntimeName("kk_string_compareTo_flat")
external fun __string_compareTo_flat(s1: String, s2: String): Int

@KSwiftKRuntimeName("kk_string_compareToIgnoreCase_flat")
external fun __string_compareToIgnoreCase_flat(s1: String, s2: String, ignoreCase: Boolean): Int

@KSwiftKRuntimeName("kk_string_concat_flat")
external fun __string_concat(s1: String, s2: String): String

@KSwiftKRuntimeName("kk_string_isEmpty_flat")
external fun __string_isEmpty_flat(s: String): Boolean

@KSwiftKRuntimeName("kk_string_isNotEmpty_flat")
external fun __string_isNotEmpty_flat(s: String): Boolean

@KSwiftKRuntimeName("kk_string_isBlank_flat")
external fun __string_isBlank_flat(s: String): Boolean

@KSwiftKRuntimeName("kk_string_isNotBlank_flat")
external fun __string_isNotBlank_flat(s: String): Boolean

@KSwiftKRuntimeName("kk_string_isNullOrEmpty_flat")
external fun __string_isNullOrEmpty_flat(s: String?): Boolean

@KSwiftKRuntimeName("kk_string_isNullOrBlank_flat")
external fun __string_isNullOrBlank_flat(s: String?): Boolean

@KSwiftKRuntimeName("kk_string_get_flat")
external fun __string_get_flat(s: String, index: Int): Char

@KSwiftKRuntimeName("kk_string_getOrNull_flat")
external fun __string_getOrNull_flat(s: String, index: Int): Char?

@KSwiftKRuntimeName("kk_string_first_flat")
external fun __string_first_flat(s: String): Char

@KSwiftKRuntimeName("kk_string_last_flat")
external fun __string_last_flat(s: String): Char

@KSwiftKRuntimeName("kk_string_single_flat")
external fun __string_single_flat(s: String): Char

@KSwiftKRuntimeName("kk_string_firstOrNull_flat")
external fun __string_firstOrNull_flat(s: String): Char?

@KSwiftKRuntimeName("kk_string_lastOrNull_flat")
external fun __string_lastOrNull_flat(s: String): Char?

@KSwiftKRuntimeName("kk_string_singleOrNull_flat")
external fun __string_singleOrNull_flat(s: String): Char?

@KSwiftKRuntimeName("kk_string_startsWith_flat")
external fun __string_startsWith_flat(s: String, prefix: String): Boolean

@KSwiftKRuntimeName("kk_string_endsWith_flat")
external fun __string_endsWith_flat(s: String, suffix: String): Boolean

@KSwiftKRuntimeName("kk_string_contains_str_flat")
external fun __string_contains_flat(s: String, other: String): Boolean

@KSwiftKRuntimeName("kk_string_contains_ignoreCase_flat")
external fun __string_contains_ignoreCase_flat(s: String, other: String, ignoreCase: Boolean): Boolean

@KSwiftKRuntimeName("kk_string_indexOf_flat")
external fun __string_indexOf_flat(s: String, other: String): Int

@KSwiftKRuntimeName("kk_string_indexOf_from_flat")
external fun __string_indexOf_from_flat(s: String, other: String, startIndex: Int): Int

@KSwiftKRuntimeName("kk_string_indexOf_ignoreCase_flat")
external fun __string_indexOf_ignoreCase_flat(
    s: String,
    other: String,
    startIndex: Int,
    ignoreCase: Boolean
): Int

@KSwiftKRuntimeName("kk_string_lastIndexOf_flat")
external fun __string_lastIndexOf_flat(s: String, other: String): Int

@KSwiftKRuntimeName("kk_string_lastIndexOf_ignoreCase_flat")
external fun __string_lastIndexOf_ignoreCase_flat(
    s: String,
    other: String,
    startIndex: Int,
    ignoreCase: Boolean
): Int

@KSwiftKRuntimeName("kk_string_equals_flat")
external fun __string_equals_flat(s: String, other: String?): Boolean

@KSwiftKRuntimeName("kk_string_equalsIgnoreCase_flat")
external fun __string_equalsIgnoreCase_flat(s: String, other: String?, ignoreCase: Boolean): Boolean

@KSwiftKRuntimeName("kk_string_contentEquals_flat")
external fun __string_contentEquals_flat(s: String?, other: String?): Boolean

@KSwiftKRuntimeName("kk_string_contentEquals_ignoreCase_flat")
external fun __string_contentEquals_ignoreCase_flat(s: String?, other: String?, ignoreCase: Boolean): Boolean

@KSwiftKRuntimeName("kk_string_count_flat")
external fun __string_count_flat(s: String, predicate: (Char) -> Boolean): Int

@KSwiftKRuntimeName("kk_string_count_flat")
external fun __string_count_flat(s: CharSequence, predicate: (Char) -> Boolean): Int

@KSwiftKRuntimeName("kk_string_any_flat")
external fun __string_any_flat(s: String, predicate: (Char) -> Boolean): Boolean

@KSwiftKRuntimeName("kk_string_any_flat")
external fun __string_any_flat(s: CharSequence, predicate: (Char) -> Boolean): Boolean

@KSwiftKRuntimeName("kk_string_all_flat")
external fun __string_all_flat(s: String, predicate: (Char) -> Boolean): Boolean

@KSwiftKRuntimeName("kk_string_all_flat")
external fun __string_all_flat(s: CharSequence, predicate: (Char) -> Boolean): Boolean

@KSwiftKRuntimeName("kk_string_none_flat")
external fun __string_none_flat(s: String, predicate: (Char) -> Boolean): Boolean

@KSwiftKRuntimeName("kk_string_none_flat")
external fun __string_none_flat(s: CharSequence, predicate: (Char) -> Boolean): Boolean

@KSwiftKRuntimeName("kk_string_indexOfFirst_flat")
external fun __string_indexOfFirst_flat(s: String, predicate: (Char) -> Boolean): Int

@KSwiftKRuntimeName("kk_string_indexOfFirst_flat")
external fun __string_indexOfFirst_flat(s: CharSequence, predicate: (Char) -> Boolean): Int

@KSwiftKRuntimeName("kk_string_indexOfLast_flat")
external fun __string_indexOfLast_flat(s: String, predicate: (Char) -> Boolean): Int

@KSwiftKRuntimeName("kk_string_indexOfLast_flat")
external fun __string_indexOfLast_flat(s: CharSequence, predicate: (Char) -> Boolean): Int

@KSwiftKRuntimeName("kk_string_lines_flat")
external fun __string_lines_flat(s: String): List<String>

@KSwiftKRuntimeName("kk_string_lineSequence_flat")
external fun __string_lineSequence_flat(s: String): Sequence<String>

@KSwiftKRuntimeName("kk_string_asSequence_flat")
external fun __string_asSequence_flat(s: String): Sequence<Char>

@KSwiftKRuntimeName("kk_string_asIterable_flat")
external fun __string_asIterable_flat(s: String): Iterable<Char>

@KSwiftKRuntimeName("kk_string_withIndex_flat")
external fun __string_withIndex_flat(s: String): Iterable<IndexedValue<Char>>

@KSwiftKRuntimeName("kk_string_withIndex_flat")
external fun __string_withIndex_flat(s: CharSequence): Iterable<IndexedValue<Char>>

@KSwiftKRuntimeName("kk_string_toInt_flat")
external fun __string_toInt_flat(s: String): Int

@KSwiftKRuntimeName("kk_string_toInt_radix_flat")
external fun __string_toInt_radix_flat(s: String, radix: Int): Int

@KSwiftKRuntimeName("kk_string_toIntOrNull_flat")
external fun __string_toIntOrNull_flat(s: String): Int?

@KSwiftKRuntimeName("kk_string_toIntOrNull_radix_flat")
external fun __string_toIntOrNull_radix_flat(s: String, radix: Int): Int?

@KSwiftKRuntimeName("kk_string_toLong_flat")
external fun __string_toLong_flat(s: String): Long

@KSwiftKRuntimeName("kk_string_toLongOrNull_flat")
external fun __string_toLongOrNull_flat(s: String): Long?

@KSwiftKRuntimeName("kk_string_toFloat_flat")
external fun __string_toFloat_flat(s: String): Float

@KSwiftKRuntimeName("kk_string_toFloatOrNull_flat")
external fun __string_toFloatOrNull_flat(s: String): Float?

@KSwiftKRuntimeName("kk_string_toDouble_flat")
external fun __string_toDouble_flat(s: String): Double

@KSwiftKRuntimeName("kk_string_toDoubleOrNull_flat")
external fun __string_toDoubleOrNull_flat(s: String): Double?

@KSwiftKRuntimeName("kk_string_toBoolean_flat")
external fun __string_toBoolean_flat(s: String?): Boolean

@KSwiftKRuntimeName("kk_string_toBooleanStrict_flat")
external fun __string_toBooleanStrict_flat(s: String): Boolean

@KSwiftKRuntimeName("kk_string_toBooleanStrictOrNull_flat")
external fun __string_toBooleanStrictOrNull_flat(s: String): Boolean?

@KSwiftKRuntimeName("kk_string_toShort_flat")
external fun __string_toShort_flat(s: String): Short

@KSwiftKRuntimeName("kk_string_toShortOrNull_flat")
external fun __string_toShortOrNull_flat(s: String): Short?

@KSwiftKRuntimeName("kk_string_toByte_flat")
external fun __string_toByte_flat(s: String): Byte

@KSwiftKRuntimeName("kk_string_toByte_radix_flat")
external fun __string_toByte_radix_flat(s: String, radix: Int): Byte

@KSwiftKRuntimeName("kk_string_toByteOrNull_flat")
external fun __string_toByteOrNull_flat(s: String): Byte?

@KSwiftKRuntimeName("kk_string_toUByteOrNull_radix_flat")
external fun __string_toUByteOrNull_radix_flat(s: String, radix: Int): UByte?

@KSwiftKRuntimeName("kk_string_toUShortOrNull_radix_flat")
external fun __string_toUShortOrNull_radix_flat(s: String, radix: Int): UShort?

@KSwiftKRuntimeName("kk_string_toUIntOrNull_radix_flat")
external fun __string_toUIntOrNull_radix_flat(s: String, radix: Int): UInt?

@KSwiftKRuntimeName("kk_string_toULongOrNull_radix_flat")
external fun __string_toULongOrNull_radix_flat(s: String, radix: Int): ULong?
